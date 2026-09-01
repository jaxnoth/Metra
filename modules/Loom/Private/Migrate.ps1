# Loom storage migration: autoprogram -> loom (copy-first, idempotent marker).

function Get-LoomLegacyStorageRoot {
    return Join-Path $env:LOCALAPPDATA 'Metra\autoprogram'
}

function Get-LoomDefaultStorageRoot {
    return Join-Path $env:LOCALAPPDATA 'Metra\loom'
}

function Get-LoomMigrationMarkerPath {
    param([Parameter(Mandatory)][string]$LoomRoot)
    return Join-Path $LoomRoot '.loom-migration.json'
}

function Get-LoomMigrationMarker {
    param([Parameter(Mandatory)][string]$LoomRoot)
    $path = Get-LoomMigrationMarkerPath -LoomRoot $LoomRoot
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Test-LoomMigrationMutexAvailable {
    $names = @('loom_state', 'loom_queue', 'autoprogram_state', 'autoprogram_queue')
    $held = @()
    foreach ($n in $names) {
        $mutexName = "Local\Metra_$n"
        $m = New-Object System.Threading.Mutex($false, $mutexName)
        $acquired = $false
        try {
            $acquired = $m.WaitOne(0)
            if (-not $acquired) { $held += $n }
        }
        finally {
            if ($acquired) { [void]$m.ReleaseMutex() }
            $m.Dispose()
        }
    }
    return $held
}

function Get-LoomLegacyBranchReferenceCount {
    param([Parameter(Mandatory)][string]$Root)
    $count = 0
    $queueDir = Join-Path $Root 'queue'
    if (-not (Test-Path -LiteralPath $queueDir)) { return 0 }
    foreach ($f in Get-ChildItem -LiteralPath $queueDir -Filter 'AP-*.json' -File -ErrorAction SilentlyContinue) {
        try {
            $item = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
            $branch = [string](Get-LoomProp -Object $item.execution -Name 'branch' -Default '')
            if ($branch -like 'autoprogram/*') { $count++ }
        }
        catch { }
    }
    return $count
}

function Test-LoomDirectoryHasData {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $subs = @('queue', 'journal', 'candidates', 'runs', 'daily', 'locks', 'state.json')
    foreach ($s in $subs) {
        $p = Join-Path $Path $s
        if (Test-Path -LiteralPath $p) {
            if ((Get-Item -LiteralPath $p).PSIsContainer) {
                if ((Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
                    return $true
                }
            }
            else {
                return $true
            }
        }
    }
    return $false
}

function Copy-LoomStorageTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$DestRoot,
        [switch]$Force
    )

    $subs = @('queue', 'journal', 'candidates', 'runs', 'daily', 'locks')
    $plan = New-Object System.Collections.Generic.List[object]
    $conflicts = New-Object System.Collections.Generic.List[string]
    $skipped = 0

    foreach ($sub in $subs) {
        $src = Join-Path $SourceRoot $sub
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path $DestRoot $sub
        foreach ($item in Get-ChildItem -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue) {
            if ($item.PSIsContainer) { continue }
            $rel = $item.FullName.Substring($src.Length).TrimStart('\', '/')
            $target = Join-Path $dst $rel
            if (Test-Path -LiteralPath $target) {
                $same = $false
                try {
                    $h1 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
                    $h2 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
                    $same = ($h1 -eq $h2)
                }
                catch { $same = $false }
                if ($same) {
                    $skipped++
                    continue
                }
                if (-not $Force) {
                    [void]$conflicts.Add($target)
                    continue
                }
            }
            [void]$plan.Add([PSCustomObject]@{ Source = $item.FullName; Target = $target })
        }
    }

    $srcState = Join-Path $SourceRoot 'state.json'
    if (Test-Path -LiteralPath $srcState) {
        $dstState = Join-Path $DestRoot 'state.json'
        if (Test-Path -LiteralPath $dstState) {
            $same = $false
            try {
                $h1 = (Get-FileHash -LiteralPath $srcState -Algorithm SHA256).Hash
                $h2 = (Get-FileHash -LiteralPath $dstState -Algorithm SHA256).Hash
                $same = ($h1 -eq $h2)
            }
            catch { $same = $false }
            if ($same) {
                $skipped++
            }
            elseif ($Force) {
                [void]$plan.Add([PSCustomObject]@{ Source = $srcState; Target = $dstState })
            }
            else {
                [void]$conflicts.Add($dstState)
            }
        }
        else {
            [void]$plan.Add([PSCustomObject]@{ Source = $srcState; Target = $dstState })
        }
    }

    if ($conflicts.Count -gt 0 -and -not $Force) {
        return [PSCustomObject]@{
            Copied    = 0
            Skipped   = $skipped
            Conflicts = @($conflicts)
        }
    }

    $copied = 0
    foreach ($entry in $plan) {
        $targetDir = Split-Path -Parent $entry.Target
        if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
            [void][System.IO.Directory]::CreateDirectory($targetDir)
        }
        Copy-Item -LiteralPath $entry.Source -Destination $entry.Target -Force
        $copied++
    }

    return [PSCustomObject]@{
        Copied    = $copied
        Skipped   = $skipped
        Conflicts = @()
    }
}

function Invoke-LoomWithMigrationMutexes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [int]$TimeoutMs = 15000
    )
    $names = @('loom_state', 'loom_queue', 'autoprogram_state', 'autoprogram_queue')
    $mutexes = @()
    $acquired = @()
    try {
        foreach ($n in $names) {
            $m = New-Object System.Threading.Mutex($false, "Local\Metra_$n")
            $mutexes += $m
            $ok = $m.WaitOne($TimeoutMs)
            if (-not $ok) {
                throw "Timed out waiting for migration mutex $n (${TimeoutMs}ms)."
            }
            $acquired += $m
        }
        return (& $Script)
    }
    finally {
        foreach ($m in $acquired) {
            [void]$m.ReleaseMutex()
            $m.Dispose()
        }
        foreach ($m in $mutexes) {
            if ($m -notin $acquired) { $m.Dispose() }
        }
    }
}

function Invoke-MetraLoomMigrate {
    <#
    .SYNOPSIS
        Migrate Loom storage from Metra\autoprogram to Metra\loom (copy-first).
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [switch]$Apply,
        [switch]$Force
    )

    if ($Force -and -not $Apply) {
        throw 'loom migrate -Force requires -Apply.'
    }

    $source = Get-LoomLegacyStorageRoot
    $dest = Get-LoomDefaultStorageRoot
    $legacyBranchRefs = 0
    if (Test-Path -LiteralPath $source) {
        $legacyBranchRefs = Get-LoomLegacyBranchReferenceCount -Root $source
    }

    $marker = Get-LoomMigrationMarker -LoomRoot $dest
    if ($marker -and [string]$marker.status -eq 'completed') {
        return [PSCustomObject]@{
            mode                  = $(if ($Apply) { 'apply' } else { 'dry-run' })
            status                = 'already-completed'
            source                = $source
            destination           = $dest
            legacyBranchReferences = $legacyBranchRefs
            message               = 'Migration marker already completed.'
        }
    }

    if (-not (Test-Path -LiteralPath $source)) {
        return [PSCustomObject]@{
            mode        = $(if ($Apply) { 'apply' } else { 'dry-run' })
            status      = 'no-source'
            source      = $source
            destination = $dest
            message     = 'Legacy autoprogram storage not found; nothing to migrate.'
        }
    }

    $destHasData = Test-LoomDirectoryHasData -Path $dest
    if ($destHasData -and -not $marker) {
        if (-not $Apply) {
            return [PSCustomObject]@{
                mode        = 'dry-run'
                status      = 'refused'
                source      = $source
                destination = $dest
                message     = 'Destination has data but no migration marker; use -Apply -Force -Confirm to resolve conflicts.'
            }
        }
        if (-not $Force) {
            throw 'Destination contains data without a completed migration marker. Refusing. Use -Apply -Force -Confirm if conflicts are understood.'
        }
    }

    if ($Apply) {
        $held = @(Test-LoomMigrationMutexAvailable)
        if ($held.Count -gt 0) {
            throw "Migration refused: mutation mutex held ($($held -join ', '))."
        }
    }

    $summary = [ordered]@{
        mode                   = $(if ($Apply) { 'apply' } else { 'dry-run' })
        status                 = 'pending'
        source                 = $source
        destination            = $dest
        legacyBranchReferences = $legacyBranchRefs
        copied                 = 0
        skipped                = 0
        conflicts              = @()
        message                = ''
    }

    if (-not $Apply) {
        $summary.status = 'dry-run-summary'
        $summary.message = 'No filesystem changes (dry-run). Use -Apply to migrate.'
        return [PSCustomObject]$summary
    }

    if (-not $PSCmdlet.ShouldProcess($dest, 'Migrate Loom storage from autoprogram')) {
        $summary.status = 'cancelled'
        return [PSCustomObject]$summary
    }

    if (-not (Test-Path -LiteralPath $dest)) {
        [void][System.IO.Directory]::CreateDirectory($dest)
    }

    $copyResult = Invoke-LoomWithMigrationMutexes -Script {
        Copy-LoomStorageTree -SourceRoot $source -DestRoot $dest -Force:$Force
    }
    $summary.copied = $copyResult.Copied
    $summary.skipped = $copyResult.Skipped
    $summary.conflicts = @($copyResult.Conflicts)

    if (@($copyResult.Conflicts).Count -gt 0 -and -not $Force) {
        $summary.status = 'refused-conflicts'
        $summary.message = 'Conflicting destination files; migration aborted before marker write.'
        return [PSCustomObject]$summary
    }

    $markerObj = [ordered]@{
        schemaVersion          = 1
        status                 = 'completed'
        migratedFrom           = 'autoprogram'
        migratedAt             = (Get-Date).ToUniversalTime().ToString('o')
        sourceExists           = (Test-Path -LiteralPath $source)
        legacyBranchReferences = $legacyBranchRefs
    }
    $markerPath = Get-LoomMigrationMarkerPath -LoomRoot $dest
    $json = ($markerObj | ConvertTo-Json -Depth 4) + "`n"
    Write-LoomAtomicUtf8Text -Path $markerPath -Text $json

    $readme = Join-Path $source 'README.txt'
    $readmeText = "Loom storage migrated to:`r`n$dest`r`n`r`nThis folder is preserved as a copy source. Safe to remove after verification.`r`n"
    Write-LoomAtomicUtf8Text -Path $readme -Text $readmeText

    $summary.status = 'completed'
    $summary.message = 'Migration completed (copy-first). Source preserved.'
    return [PSCustomObject]$summary
}

function Test-LoomExecutionBranchPrefix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Branch
    )
    if ([string]::IsNullOrWhiteSpace($Branch)) { return $false }
    $b = $Branch.Replace('\', '/')
    return ($b -like 'loom/*' -or $b -like 'autoprogram/*')
}
