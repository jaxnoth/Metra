# Porter - transport Metra Cursor Project pack (Cursor Project continuity)
#
# Writes:
# - <MetraRoot>\porter\manifest.json
# - <MetraRoot>\porter\OPEN-PLANS.md
# - <MetraRoot>\porter\plans\<cursorLeaf> (index cursorLeaf or Approved Cursor-discovered)
# - %LOCALAPPDATA%\Metra\porter\ (mirror stamp + writeback-ledger.json)
# - Agent Store docs/plans/<stem>.plan.md (Approved write-back when projectId+projectKey valid)
#
# Sources: plans/index.yaml (in-scope) + Approved Cursor leaves not already indexed.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$CursorProjectConfigPath,
    [string]$AgentStoresRoot,
    [string]$WritebackLedgerPath,
    [string]$CursorPlansDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-YamlIndexEntries {
    param([string]$IndexPath)
    if (-not (Test-Path -LiteralPath $IndexPath)) {
        return @()
    }
    $raw = Get-Content -LiteralPath $IndexPath -Raw
    $entries = @()
    $current = $null
    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -match '^\s*-\s+stem:\s*(.+)\s*$') {
            if ($null -ne $current) { $entries += $current }
            $current = [ordered]@{
                stem        = (Get-YamlScalar $Matches[1])
                cursorLeaf  = $null
                authority   = $null
                repoPath    = $null
                updatedAt   = $null
            }
            continue
        }
        if ($null -eq $current) { continue }
        if ($line -match '^\s+cursorLeaf:\s*(.+)\s*$') {
            $v = Get-YamlScalar $Matches[1]
            if ($v -eq 'null' -or [string]::IsNullOrWhiteSpace($v)) { $current.cursorLeaf = $null }
            else { $current.cursorLeaf = $v }
        }
        elseif ($line -match '^\s+authority:\s*(.+)\s*$') {
            $current.authority = Get-YamlScalar $Matches[1]
        }
        elseif ($line -match '^\s+repoPath:\s*(.+)\s*$') {
            $v = Get-YamlScalar $Matches[1]
            if ($v -eq 'null') { $current.repoPath = $null } else { $current.repoPath = $v }
        }
        elseif ($line -match '^\s+updatedAt:\s*(.+)\s*$') {
            $current.updatedAt = Get-YamlScalar $Matches[1]
        }
    }
    if ($null -ne $current) { $entries += $current }
    return $entries
}

function Get-YamlScalar {
    param([string]$Raw)
    $v = $Raw.Trim()
    if (($v.StartsWith("'") -and $v.EndsWith("'")) -or ($v.StartsWith('"') -and $v.EndsWith('"'))) {
        if ($v.Length -ge 2) { $v = $v.Substring(1, $v.Length - 2) }
    }
    return $v
}

function Test-MetraPorterStem {
    param(
        [string]$Stem,
        [string[]]$IncludePrefixes,
        [string[]]$ExcludePrefixes
    )
    if ([string]::IsNullOrWhiteSpace($Stem)) { return $false }
    $s = $Stem.ToLowerInvariant()
    foreach ($ex in $ExcludePrefixes) {
        if ([string]::IsNullOrWhiteSpace($ex)) { continue }
        if ($s.StartsWith($ex.ToLowerInvariant())) { return $false }
    }
    foreach ($inc in $IncludePrefixes) {
        if ([string]::IsNullOrWhiteSpace($inc)) { continue }
        if ($s.StartsWith($inc.ToLowerInvariant())) { return $true }
    }
    return $false
}

function Resolve-MetraPorterCursorLeafName {
    param([string]$CursorLeaf)
    if ([string]::IsNullOrWhiteSpace($CursorLeaf)) { return $null }
    $raw = $CursorLeaf.Trim()
    # Reject any path-shaped leaf (separators, volume, parent segments) before join.
    if ($raw.IndexOfAny([char[]]@('\', '/', ':')) -ge 0) { return $null }
    if ($raw -eq '.' -or $raw -eq '..') { return $null }
    $name = [System.IO.Path]::GetFileName($raw)
    if ([string]::IsNullOrWhiteSpace($name) -or -not [string]::Equals($name, $raw, [StringComparison]::Ordinal)) {
        return $null
    }
    return $name
}

function Test-MetraPorterPathUnderRoot {
    param(
        [Parameter(Mandatory)][string]$RootDirectory,
        [Parameter(Mandatory)][string]$CandidatePath
    )
    $rootFull = [System.IO.Path]::GetFullPath($RootDirectory).TrimEnd('\', '/')
    $candidateFull = [System.IO.Path]::GetFullPath($CandidatePath)
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    return $candidateFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-MetraPorterNormalizeStem {
    <#
    .SYNOPSIS
        Leaf/title -> stem. Parity with Yarn Get-YarnPlanBoardInventoryNormalizeStem / Surveyor normalizePlanStem.
    #>
    param([string]$Text)
    $s = [string]$Text
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $s = $s.ToLowerInvariant().Trim()
    $s = $s -replace '\.plan\.md$', ''
    $s = $s -replace '_[0-9a-f]{8}$', ''
    $s = $s -replace '-[0-9a-f]{8}$', ''
    $s = $s -replace '[^a-z0-9]+', '-'
    $s = $s.Trim('-')
    return $s
}

function Get-MetraPorterPlanFrontmatterMap {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    try {
        $raw = [System.IO.File]::ReadAllText($Path)
    }
    catch {
        Write-Warning "Porter: could not read plan frontmatter from $Path ($($_.Exception.Message))"
        return @{}
    }
    if ($raw -notmatch '(?s)\A---\r?\n(.*?)\r?\n---') {
        return @{}
    }
    $map = @{}
    foreach ($line in ($Matches[1] -split "`r?`n")) {
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*:\s*(.*?)\s*$') {
            $map[$Matches[1]] = (Get-YamlScalar $Matches[2])
        }
    }
    return $map
}

function Test-MetraPorterYamlTruthy {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    switch ($Value.Trim().ToLowerInvariant()) {
        'true' { return $true }
        'yes' { return $true }
        '1' { return $true }
        default { return $false }
    }
}

function Test-MetraPorterPlanApproved {
    <#
    .SYNOPSIS
        Cursor-discovered leaves need Approved (or comparable affirmed terminal) before transport.
    .NOTES
        Affirmed when status is Approved (case-insensitive) OR approveForLoom is truthy.
        Index-driven rows do not use this gate (index implies intentional affiliation).
        Agent Store write-back always requires this gate (B: never clobber drafts).
    #>
    param([Parameter(Mandatory)][string]$Path)
    $fm = Get-MetraPorterPlanFrontmatterMap -Path $Path
    $status = if ($fm.ContainsKey('status')) { [string]$fm['status'] } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($status) -and
        $status.Trim().Equals('Approved', [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $approve = if ($fm.ContainsKey('approveForLoom')) { [string]$fm['approveForLoom'] } else { '' }
    return (Test-MetraPorterYamlTruthy -Value $approve)
}

function Get-MetraPorterContentHash {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Resolve-MetraPorterCursorProjectConfig {
    param(
        [string]$LocalAppData,
        [string]$ConfigPath
    )
    $path = $ConfigPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $LocalAppData 'Metra\porter\cursor-project.local.json'
    }
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            Ok       = $false
            Reason   = 'missing-config'
            Path     = $path
            ProjectId = $null
            ProjectKey = $null
        }
    }
    try {
        $rawText = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($rawText)) {
            return [pscustomobject]@{
                Ok         = $false
                Reason     = 'unreadable-config:null-or-empty'
                Path       = $path
                ProjectId  = $null
                ProjectKey = $null
            }
        }
        $doc = $rawText | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            Ok       = $false
            Reason   = "unreadable-config:$($_.Exception.Message)"
            Path     = $path
            ProjectId = $null
            ProjectKey = $null
        }
    }
    if ($null -eq $doc) {
        return [pscustomobject]@{
            Ok         = $false
            Reason     = 'unreadable-config:null-or-empty'
            Path       = $path
            ProjectId  = $null
            ProjectKey = $null
        }
    }
    $id = if ($doc.PSObject.Properties['projectId']) { [string]$doc.projectId } else { '' }
    $key = if ($doc.PSObject.Properties['projectKey']) { [string]$doc.projectKey } else { '' }
    if ([string]::IsNullOrWhiteSpace($id)) {
        return [pscustomobject]@{
            Ok       = $false
            Reason   = 'missing-projectId'
            Path     = $path
            ProjectId = $null
            ProjectKey = $key
        }
    }
    if ([string]::IsNullOrWhiteSpace($key) -or -not $key.Trim().Equals('Metra', [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            Ok       = $false
            Reason   = 'projectKey-mismatch'
            Path     = $path
            ProjectId = $id.Trim()
            ProjectKey = $key
        }
    }
    return [pscustomobject]@{
        Ok         = $true
        Reason     = 'ok'
        Path       = $path
        ProjectId  = $id.Trim()
        ProjectKey = 'Metra'
    }
}

function Resolve-MetraPorterAgentStorePlansDir {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [string]$AgentStoresRoot,
        [string]$LocalAppData
    )
    $id = $ProjectId.Trim()
    if ($id -notmatch '^[a-zA-Z0-9_-]+$') {
        throw "Porter write-back: invalid projectId (must be alphanumeric/_/- only): $ProjectId"
    }
    $root = $AgentStoresRoot
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Join-Path $LocalAppData 'Cursor\AgentStores\cursor_agent_stores'
    }
    $storeRoot = Join-Path $root $id
    if (-not (Test-MetraPorterPathUnderRoot -RootDirectory $root -CandidatePath $storeRoot)) {
        throw "Porter write-back: projectId escapes AgentStoresRoot."
    }
    $filesRoot = Join-Path $storeRoot 'files'
    $plansDir = Join-Path $filesRoot 'docs\plans'
    $markerCharter = Join-Path $filesRoot 'docs\metra-charter.md'
    $markerContext = Join-Path $filesRoot 'docs\project-context.md'
    $markerOk = (Test-Path -LiteralPath $markerCharter) -or (Test-Path -LiteralPath $markerContext)
    return [pscustomobject]@{
        AgentStoresRoot = $root
        StoreRoot       = $storeRoot
        FilesRoot       = $filesRoot
        PlansDir        = $plansDir
        MarkerPresent   = $markerOk
        StoreExists     = (Test-Path -LiteralPath $storeRoot)
    }
}

function Read-MetraPorterWritebackLedger {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{ schemaVersion = 1; updatedUtc = $null; stems = @{} }
    }
    try {
        $rawText = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($rawText)) {
            return [ordered]@{ schemaVersion = 1; updatedUtc = $null; stems = @{} }
        }
        $raw = $rawText | ConvertFrom-Json
        if ($null -eq $raw) {
            return [ordered]@{ schemaVersion = 1; updatedUtc = $null; stems = @{} }
        }
        $stems = @{}
        if ($null -ne $raw.stems) {
            foreach ($p in $raw.stems.PSObject.Properties) {
                $stems[$p.Name] = [ordered]@{
                    contentHash = [string]$p.Value.contentHash
                    writtenUtc  = $(if ($p.Value.PSObject.Properties['writtenUtc']) { [string]$p.Value.writtenUtc } else { $null })
                    cursorLeaf  = $(if ($p.Value.PSObject.Properties['cursorLeaf']) { [string]$p.Value.cursorLeaf } else { $null })
                }
            }
        }
        return [ordered]@{
            schemaVersion = 1
            updatedUtc    = $(if ($raw.PSObject.Properties['updatedUtc']) { [string]$raw.updatedUtc } else { $null })
            stems         = $stems
        }
    }
    catch {
        Write-Warning "Porter write-back: ledger unreadable ($($_.Exception.Message)); treating as empty."
        return [ordered]@{ schemaVersion = 1; updatedUtc = $null; stems = @{} }
    }
}

function Write-MetraPorterWritebackLedger {
    param(
        [string]$Path,
        $Ledger
    )
    $Ledger['updatedUtc'] = [datetime]::UtcNow.ToString('o')
    $stemObj = [ordered]@{}
    foreach ($k in @($Ledger.stems.Keys)) {
        $stemObj[$k] = $Ledger.stems[$k]
    }
    $payload = [ordered]@{
        schemaVersion = 1
        updatedUtc    = $Ledger.updatedUtc
        stems         = $stemObj
    }
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, (($payload | ConvertTo-Json -Depth 6) + "`n"), [System.Text.UTF8Encoding]::new($false))
}

function Invoke-MetraPorterAgentStoreWriteback {
    param(
        [string]$CursorPlansDir,
        [System.Collections.Generic.HashSet[string]]$KeptLeaves,
        [string]$LocalAppData,
        [string]$CursorProjectConfigPath,
        [string]$AgentStoresRoot,
        [string]$WritebackLedgerPath
    )

    $counters = [ordered]@{
        wouldWrite                 = 0
        wouldWriteDriftCorrected   = 0
        written                    = 0
        writtenDriftCorrected      = 0
        skippedUnchanged           = 0
        skippedNotApproved         = 0
        skippedNoProjectId         = 0
        skippedProjectKeyMismatch  = 0
        skippedMissingStore        = 0
        skippedUnsafe              = 0
        softFailErrors             = 0
        writebackEnabled           = $false
        projectId                  = $null
        plansDir                   = $null
        markerPresent              = $false
        skipReason                 = $null
    }

    $cfg = Resolve-MetraPorterCursorProjectConfig -LocalAppData $LocalAppData -ConfigPath $CursorProjectConfigPath
    if (-not $cfg.Ok) {
        if ($cfg.Reason -eq 'projectKey-mismatch') {
            $counters.skippedProjectKeyMismatch = 1
            $counters.skipReason = $cfg.Reason
            Write-Warning "Porter write-back skipped: projectKey must be Metra (config=$($cfg.Path))."
        }
        else {
            $counters.skippedNoProjectId = 1
            $counters.skipReason = $cfg.Reason
            Write-Host "Porter write-back skipped: $($cfg.Reason) (config=$($cfg.Path))."
        }
        return [pscustomobject]$counters
    }

    try {
        $store = Resolve-MetraPorterAgentStorePlansDir -ProjectId $cfg.ProjectId -AgentStoresRoot $AgentStoresRoot -LocalAppData $LocalAppData
    }
    catch {
        $counters.skippedUnsafe = 1
        $counters.skipReason = "invalid-projectId:$($_.Exception.Message)"
        Write-Warning "Porter write-back skipped: $($_.Exception.Message)"
        return [pscustomobject]$counters
    }
    $counters.projectId = $cfg.ProjectId
    $counters.plansDir = $store.PlansDir
    $counters.markerPresent = [bool]$store.MarkerPresent
    if (-not $store.MarkerPresent) {
        Write-Host 'Porter write-back: store-content Metra marker (metra-charter.md / project-context.md) not found; projectKey=Metra accepted.'
    }
    if (-not $store.StoreExists) {
        $counters.skippedMissingStore = 1
        $counters.skipReason = 'missing-store'
        Write-Warning "Porter write-back skipped: Agent Store not found at $($store.StoreRoot)."
        return [pscustomobject]$counters
    }

    $counters.writebackEnabled = $true
    $ledgerPath = $WritebackLedgerPath
    if ([string]::IsNullOrWhiteSpace($ledgerPath)) {
        $ledgerPath = Join-Path $LocalAppData 'Metra\porter\writeback-ledger.json'
    }
    $ledger = Read-MetraPorterWritebackLedger -Path $ledgerPath
    $ledgerDirty = $false

    foreach ($safeLeaf in @($KeptLeaves)) {
        if ([string]::IsNullOrWhiteSpace($safeLeaf) -or $safeLeaf -eq 'README.md') { continue }
        $src = Join-Path $CursorPlansDir $safeLeaf
        if (-not (Test-Path -LiteralPath $src)) { continue }
        if (-not (Test-MetraPorterPathUnderRoot -RootDirectory $CursorPlansDir -CandidatePath $src)) {
            $counters.skippedUnsafe++
            continue
        }
        if (-not (Test-MetraPorterPlanApproved -Path $src)) {
            $counters.skippedNotApproved++
            continue
        }

        $stem = Get-MetraPorterNormalizeStem -Text $safeLeaf
        if ([string]::IsNullOrWhiteSpace($stem)) {
            $counters.skippedUnsafe++
            continue
        }
        $destName = "$stem.plan.md"
        $dest = Join-Path $store.PlansDir $destName
        if (-not (Test-MetraPorterPathUnderRoot -RootDirectory $store.FilesRoot -CandidatePath $dest)) {
            $counters.skippedUnsafe++
            continue
        }

        try {
            $sourceHash = Get-MetraPorterContentHash -Path $src
        }
        catch {
            $counters.softFailErrors++
            Write-Warning "Porter write-back: hash failed for $safeLeaf ($($_.Exception.Message))"
            continue
        }

        $destinationHash = $null
        if (Test-Path -LiteralPath $dest) {
            try {
                $destinationHash = Get-MetraPorterContentHash -Path $dest
            }
            catch {
                $counters.softFailErrors++
                Write-Warning "Porter write-back: dest hash failed for $destName ($($_.Exception.Message))"
                continue
            }
        }

        $ledgerHash = $null
        if ($ledger.stems.ContainsKey($stem)) {
            $ledgerHash = [string]$ledger.stems[$stem].contentHash
        }

        # B+A: skip only when ledger, source, and destination all agree. Source-only
        # ledger match must not leave post-Approve Agent Store drift in place.
        if ($ledgerHash -eq $sourceHash -and $destinationHash -eq $sourceHash) {
            $counters.skippedUnchanged++
            continue
        }

        $isDriftCorrect = ($null -ne $destinationHash -and $destinationHash -ne $sourceHash -and $ledgerHash -eq $sourceHash)

        if ($PSCmdlet.ShouldProcess($dest, "Write-back Approved plan $destName to Agent Store")) {
            try {
                if (-not (Test-Path -LiteralPath $store.PlansDir)) {
                    New-Item -ItemType Directory -Force -Path $store.PlansDir | Out-Null
                }
                Copy-Item -LiteralPath $src -Destination $dest -Force
                $ledger.stems[$stem] = [ordered]@{
                    contentHash = $sourceHash
                    writtenUtc  = [datetime]::UtcNow.ToString('o')
                    cursorLeaf  = $safeLeaf
                }
                $ledgerDirty = $true
                $counters.written++
                if ($isDriftCorrect) { $counters.writtenDriftCorrected++ }
            }
            catch {
                $counters.softFailErrors++
                Write-Warning "Porter write-back: failed $dest ($($_.Exception.Message))"
            }
        }
        else {
            $counters.wouldWrite++
            if ($isDriftCorrect) { $counters.wouldWriteDriftCorrected++ }
        }
    }

    if ($ledgerDirty -and -not $WhatIfPreference) {
        try {
            Write-MetraPorterWritebackLedger -Path $ledgerPath -Ledger $ledger
        }
        catch {
            Write-Warning "Porter write-back: ledger save failed ($($_.Exception.Message))"
            $counters.softFailErrors++
        }
    }

    return [pscustomobject]$counters
}

$porterRoot = Join-Path $MetraRoot 'porter'
$plansOut = Join-Path $porterRoot 'plans'
$indexPath = Join-Path $MetraRoot 'plans\index.yaml'
$scopePath = Join-Path $porterRoot 'scope.json'
$cursorPlansDir = if (-not [string]::IsNullOrWhiteSpace($CursorPlansDir)) {
    $CursorPlansDir
}
else {
    Join-Path $env:USERPROFILE '.cursor\plans'
}
$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $localAppData = Join-Path $env:USERPROFILE 'AppData\Local'
}
$localMirror = Join-Path $localAppData 'Metra\porter'
$stampUtc = [datetime]::UtcNow.ToString('o')

if (-not (Test-Path -LiteralPath $porterRoot)) {
    throw "porter missing under $MetraRoot - create the pack folder first."
}
if (-not (Test-Path -LiteralPath $scopePath)) {
    throw "porter/scope.json missing - Metra-product filter is required."
}

$scope = Get-Content -LiteralPath $scopePath -Raw | ConvertFrom-Json
$includePrefixes = @($scope.includeStemPrefixes)
$excludePrefixes = @($scope.excludeStemPrefixes)

if ($PSCmdlet.ShouldProcess($plansOut, 'Ensure Porter pack directories')) {
    New-Item -ItemType Directory -Force -Path $plansOut | Out-Null
    New-Item -ItemType Directory -Force -Path $localMirror | Out-Null
}

$allEntries = @(Get-YamlIndexEntries -IndexPath $indexPath)
$entries = @($allEntries | Where-Object {
        Test-MetraPorterStem -Stem $_.stem -IncludePrefixes $includePrefixes -ExcludePrefixes $excludePrefixes
    })
$skipped = $allEntries.Count - $entries.Count

$copied = 0
$repoAuth = 0
$missing = 0
$unsafeLeaf = 0
$cursorDiscovered = 0
$cursorSkippedNotApproved = 0
$cursorSkippedOutOfScope = 0
$keptLeaves = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$indexStems = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$rows = New-Object System.Collections.Generic.List[string]
[void]$rows.Add('# Metra-product plans (porter scope)')
[void]$rows.Add('')
[void]$rows.Add("Generated: $stampUtc")
[void]$rows.Add("Scope: porter/scope.json (Metra product only; $skipped index entries skipped)")
[void]$rows.Add('Sources: plans/index.yaml + Approved Cursor leaves under %USERPROFILE%\.cursor\plans (in-scope, not already indexed)')
[void]$rows.Add('')
[void]$rows.Add('| Stem | Authority | Cursor leaf | Repo path | Snapshot |')
[void]$rows.Add('|------|-----------|-------------|-----------|----------|')

foreach ($ie in $allEntries) {
    if (-not [string]::IsNullOrWhiteSpace([string]$ie.stem)) {
        [void]$indexStems.Add([string]$ie.stem)
    }
}

foreach ($e in $entries) {
    $snap = '-'
    if ($e.authority -eq 'repo') { $repoAuth++ }
    if ($e.cursorLeaf) {
        $safeLeaf = Resolve-MetraPorterCursorLeafName -CursorLeaf $e.cursorLeaf
        if (-not $safeLeaf) {
            $unsafeLeaf++
            $snap = 'unsafe-cursor-leaf'
        }
        else {
            $src = Join-Path $cursorPlansDir $safeLeaf
            $dest = Join-Path $plansOut $safeLeaf
            if (-not (Test-MetraPorterPathUnderRoot -RootDirectory $cursorPlansDir -CandidatePath $src) -or
                -not (Test-MetraPorterPathUnderRoot -RootDirectory $plansOut -CandidatePath $dest)) {
                $unsafeLeaf++
                $snap = 'unsafe-cursor-leaf'
            }
            elseif (Test-Path -LiteralPath $src) {
                if ($PSCmdlet.ShouldProcess($dest, "Copy Cursor plan $safeLeaf")) {
                    Copy-Item -LiteralPath $src -Destination $dest -Force
                }
                [void]$keptLeaves.Add($safeLeaf)
                $copied++
                $snap = "plans/$safeLeaf"
            }
            else {
                $missing++
                $snap = 'missing-cursor-leaf'
            }
        }
    }
    $repoCol = if ($e.repoPath) { "plans/$($e.repoPath)" } else { '-' }
    $leafCol = if ($e.cursorLeaf) { $e.cursorLeaf } else { '-' }
    [void]$rows.Add("| $($e.stem) | $($e.authority) | $leafCol | $repoCol | $snap |")
}

# Cursor-directory discovery: in-scope Approved leaves whose stem is not already indexed.
if (Test-Path -LiteralPath $cursorPlansDir) {
    Get-ChildItem -LiteralPath $cursorPlansDir -File -Filter '*.plan.md' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $safeLeaf = Resolve-MetraPorterCursorLeafName -CursorLeaf $_.Name
            if (-not $safeLeaf) {
                $unsafeLeaf++
                return
            }
            if ($keptLeaves.Contains($safeLeaf)) { return }

            $stem = Get-MetraPorterNormalizeStem -Text $safeLeaf
            if ([string]::IsNullOrWhiteSpace($stem)) { return }
            if ($indexStems.Contains($stem)) { return }

            if (-not (Test-MetraPorterStem -Stem $stem -IncludePrefixes $includePrefixes -ExcludePrefixes $excludePrefixes)) {
                $cursorSkippedOutOfScope++
                return
            }

            $src = $_.FullName
            if (-not (Test-MetraPorterPathUnderRoot -RootDirectory $cursorPlansDir -CandidatePath $src)) {
                $unsafeLeaf++
                return
            }

            if (-not (Test-MetraPorterPlanApproved -Path $src)) {
                $cursorSkippedNotApproved++
                return
            }

            $dest = Join-Path $plansOut $safeLeaf
            if (-not (Test-MetraPorterPathUnderRoot -RootDirectory $plansOut -CandidatePath $dest)) {
                $unsafeLeaf++
                return
            }

            if ($PSCmdlet.ShouldProcess($dest, "Copy Approved Cursor-discovered plan $safeLeaf")) {
                Copy-Item -LiteralPath $src -Destination $dest -Force
            }
            [void]$keptLeaves.Add($safeLeaf)
            $copied++
            $cursorDiscovered++
            [void]$rows.Add("| $stem | cursor | $safeLeaf | - | plans/$safeLeaf |")
        }
}

$removed = 0
Get-ChildItem -LiteralPath $plansOut -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'README.md' -and -not $keptLeaves.Contains($_.Name) } |
    ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove out-of-scope Porter snapshot')) {
            Remove-Item -LiteralPath $_.FullName -Force
            $removed++
        }
    }

$manifest = [ordered]@{
    schemaVersion   = 1
    projectKey      = 'Metra'
    lastRefreshUtc  = $stampUtc
    scopePath       = 'porter/scope.json'
    source          = [ordered]@{
        metraRoot       = $MetraRoot
        cursorPlansDir  = $cursorPlansDir
        planIndex       = 'plans/index.yaml'
        cursorDiscovery = 'Approved in-scope Cursor leaves not already in index'
    }
    counts          = [ordered]@{
        indexEntries               = $allEntries.Count
        inScope                    = $entries.Count
        skippedOutOfScope          = $skipped
        cursorBodiesCopied         = $copied
        cursorDiscovered           = $cursorDiscovered
        cursorSkippedNotApproved   = $cursorSkippedNotApproved
        cursorSkippedOutOfScope    = $cursorSkippedOutOfScope
        orphanSnapshotsRemoved     = $removed
        repoAuthority              = $repoAuth
        missingCursorLeaf          = $missing
        unsafeCursorLeaf           = $unsafeLeaf
    }
    notes           = 'Generated by scripts/Invoke-MetraPorter.ps1. Metra-product filter via scope.json. Cursor discovery requires Approved (or approveForLoom). Agent Store write-back requires projectId+projectKey=Metra. Do not hand-edit.'
}

$manifestPath = Join-Path $porterRoot 'manifest.json'
$openPlansPath = Join-Path $porterRoot 'OPEN-PLANS.md'
$mirrorManifest = Join-Path $localMirror 'manifest.json'
$mirrorReadme = Join-Path $localMirror 'README.md'

$writeback = Invoke-MetraPorterAgentStoreWriteback `
    -CursorPlansDir $cursorPlansDir `
    -KeptLeaves $keptLeaves `
    -LocalAppData $localAppData `
    -CursorProjectConfigPath $CursorProjectConfigPath `
    -AgentStoresRoot $AgentStoresRoot `
    -WritebackLedgerPath $WritebackLedgerPath

$manifest.counts['writebackWritten'] = [int]$writeback.written
$manifest.counts['writebackWrittenDriftCorrected'] = [int]$writeback.writtenDriftCorrected
$manifest.counts['writebackWouldWrite'] = [int]$writeback.wouldWrite
$manifest.counts['writebackWouldWriteDriftCorrected'] = [int]$writeback.wouldWriteDriftCorrected
$manifest.counts['writebackSkippedUnchanged'] = [int]$writeback.skippedUnchanged
$manifest.counts['writebackSkippedNotApproved'] = [int]$writeback.skippedNotApproved
$manifest.counts['writebackSkippedNoProjectId'] = [int]$writeback.skippedNoProjectId
$manifest.counts['writebackSkippedProjectKeyMismatch'] = [int]$writeback.skippedProjectKeyMismatch
$manifest.counts['writebackSkippedMissingStore'] = [int]$writeback.skippedMissingStore
$manifest.counts['writebackSoftFailErrors'] = [int]$writeback.softFailErrors
$manifest['agentStoreWriteback'] = [ordered]@{
    enabled       = [bool]$writeback.writebackEnabled
    projectId     = $writeback.projectId
    plansDir      = $writeback.plansDir
    markerPresent = [bool]$writeback.markerPresent
    skipReason    = $writeback.skipReason
}

if (-not $PSCmdlet.ShouldProcess($manifestPath, 'Write Porter manifest and OPEN-PLANS')) {
    Write-Host "WhatIf: inScope=$($entries.Count) skipped=$skipped wouldCopy=$copied cursorDiscovered=$cursorDiscovered writebackWouldWrite=$($writeback.wouldWrite) writebackSkip=$($writeback.skipReason)"
    return
}

($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $manifestPath -Encoding utf8
($rows -join "`n") + "`n" | Set-Content -LiteralPath $openPlansPath -Encoding utf8
Copy-Item -LiteralPath $manifestPath -Destination $mirrorManifest -Force
@(
    '# Metra Cursor Project local mirror (Porter)'
    ''
    "lastRefreshUtc: $stampUtc"
    "inScope: $($entries.Count) (skipped $skipped); cursorDiscovered: $cursorDiscovered"
    ''
    'Primary pack (repo working tree):'
    $porterRoot
    ''
    'Filter: porter/scope.json (Metra product only)'
    'Cursor discovery: Approved (or approveForLoom) in-scope leaves not in plans/index.yaml'
    'Agent Store write-back: Approved desk leaves -> docs/plans/<stem>.plan.md (projectId+projectKey=Metra; skip only when source+dest+ledger hashes match)'
    ''
    'Regenerate: pwsh -File <MetraRoot>\scripts\Invoke-MetraPorter.ps1'
    'Also runs on MetraYarnLoomPulse after Scout.'
) -join "`n" | Set-Content -LiteralPath $mirrorReadme -Encoding utf8

Write-Host "Porter refreshed: inScope=$($entries.Count) skipped=$skipped copied=$copied cursorDiscovered=$cursorDiscovered notApproved=$cursorSkippedNotApproved removedOrphans=$removed missingLeaf=$missing"
Write-Host "  write-back: written=$($writeback.written) driftCorrected=$($writeback.writtenDriftCorrected) unchanged=$($writeback.skippedUnchanged) notApproved=$($writeback.skippedNotApproved) skip=$($writeback.skipReason)"
Write-Host "  $manifestPath"
Write-Host "  $openPlansPath"
Write-Host "  mirror: $localMirror"
