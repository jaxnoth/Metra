# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Export-MetraProfile {
    <#
    .SYNOPSIS
        Packs local Metra customizations into a portable profile.
    .DESCRIPTION
        Writes the same layout used by profiles/sample. A path ending in .zip produces an
        archive; other paths produce a folder. Secrets, ticket caches, canvas snapshots, and
        personal-root registry files are not included.
        Non-empty destination folders and existing zip files require -Force.
    .PARAMETER Path
        Destination folder or .zip path. Environment variables and relative paths are supported.
    .PARAMETER Force
        Replace an existing non-empty folder or existing .zip destination.
    .PARAMETER Quiet
        Suppresses host status messages.
    .EXAMPLE
        Export-MetraProfile -Path $env:TEMP\my-metra-profile.zip
    .EXAMPLE
        Export-MetraProfile -Path .\profile-backup -Force
    .OUTPUTS
        PSCustomObject containing destination path, included files, archive state, and manifest.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$Force,

        [switch]$Quiet
    )

    $metraRoot = Get-MetraRoot
    $fileMap = @(Get-MetraProfileFileMap)
    $present = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $fileMap) {
        $src = Join-Path $metraRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $src) {
            [void]$present.Add($rel)
        }
    }
    if ($present.Count -eq 0) {
        throw 'Nothing to export: no metra.config.json, projects.local.json, persona/learned local rules, or operator-contract.json found.'
    }

    $expanded = [System.Environment]::ExpandEnvironmentVariables($Path)
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path (Get-Location).Path $expanded
    }
    try {
        $destFull = [System.IO.Path]::GetFullPath($expanded)
    }
    catch {
        throw "Invalid profile destination path: $Path"
    }
    $asZip = $destFull.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)

    if (-not $PSCmdlet.ShouldProcess($destFull, 'Export Metra profile pack')) {
        return [PSCustomObject]@{
            Path     = $destFull
            Files    = @($present.ToArray())
            IsZip    = $asZip
            Manifest = $null
            WhatIf   = $true
        }
    }

    if ($asZip) {
        $zipDir = Split-Path -Parent $destFull
        if ($zipDir -and -not (Test-Path -LiteralPath $zipDir)) {
            [void][System.IO.Directory]::CreateDirectory($zipDir)
        }
        if ((Test-Path -LiteralPath $destFull) -and -not $Force) {
            throw "Destination zip already exists. Use -Force to replace it: $destFull"
        }
    }
    else {
        if (Test-Path -LiteralPath $destFull) {
            $existing = @(Get-ChildItem -LiteralPath $destFull -Force -ErrorAction SilentlyContinue)
            if ($existing.Count -gt 0 -and -not $Force) {
                throw "Destination folder is not empty. Use -Force to replace profile export contents: $destFull"
            }
            if ($Force -and $existing.Count -gt 0) {
                Remove-Item -LiteralPath $destFull -Recurse -Force
            }
        }
    }

    $staging = if ($asZip) {
        Join-Path ([System.IO.Path]::GetTempPath()) ('metra-profile-export-' + [guid]::NewGuid().ToString('N'))
    }
    else {
        $destFull
    }
    [void][System.IO.Directory]::CreateDirectory($staging)

    foreach ($rel in $present) {
        $src = Join-Path $metraRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $dst = Join-Path $staging ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) {
            [void][System.IO.Directory]::CreateDirectory($dstDir)
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    $status = Get-MetraProfileStatus -MetraRoot $metraRoot
    $presentSet = @{}
    foreach ($rel in $present) {
        $presentSet[($rel -replace '\\', '/')] = $true
    }
    $fileDetails = @(
        $status.files |
            Where-Object { $presentSet.ContainsKey(($_.relativePath -replace '\\', '/')) } |
            ForEach-Object {
                [ordered]@{
                    logicalName  = $_.logicalName
                    relativePath = $_.relativePath
                    hash         = $_.hash
                }
            }
    )

    $manifest = [ordered]@{
        version            = 1
        profilePackVersion = 1
        id                 = 'export'
        description        = 'Operator profile exported from local Metra checkout customizations.'
        exportedUtc        = [DateTime]::UtcNow.ToString('o')
        createdUtc         = [DateTime]::UtcNow.ToString('o')
        contentHash        = $status.contentHash
        source             = [System.Environment]::MachineName
        files              = $fileDetails
        notes              = @(
            'Personal-root registryFile (e.g. projects.personal.json beside personal projects) is not included; copy it with that root separately.',
            'Optional metra-humor.local.mdc / metra-teaching-gentle.local.mdc are included when present (Persona Add-ons).',
            'Do not pack secrets, ticket caches, or canvas snapshots.',
            'Metra Profile Sync v1: HQ-published, satellite-pulled.',
            'Machine-local roots/projectsRoot/workspace.outputs are preserved on satellite import when HQ paths are foreign; see satellite connect.'
        )
    }
    $manifestPath = Join-Path $staging 'metra-profile.json'
    ($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $manifestPath -Encoding utf8

    $readmePath = Join-Path $staging 'README.md'
    @"
# Exported Metra operator profile

Created: $($manifest.exportedUtc)

Import into another Metra checkout:

``````powershell
.\metra.ps1 import-profile -Path <this-folder-or-zip> -Force
# Then edit metra.config.json roots / operator name in metra-persona.local.mdc
# Optional: metra-humor.local.mdc / metra-teaching-gentle.local.mdc come from profiles/addons when you opted in
``````

Personal-root ``registryFile`` is not included in this pack.
"@ | Set-Content -LiteralPath $readmePath -Encoding utf8

    $resultPath = $destFull
    $manifestOut = $manifestPath
    if ($asZip) {
        try {
            if (Test-Path -LiteralPath $destFull) {
                Remove-Item -LiteralPath $destFull -Force
            }
            Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $destFull -Force
            $manifestOut = 'metra-profile.json (inside zip)'
        }
        finally {
            if (Test-Path -LiteralPath $staging) {
                Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not $Quiet) {
        Write-Host ("Exported profile: {0}" -f $resultPath)
    }

    return [PSCustomObject]@{
        Path     = $resultPath
        Files    = @($present.ToArray())
        IsZip    = $asZip
        Manifest = $manifestOut
        WhatIf   = $false
    }
}

function Import-MetraProfile {
    <#
    .SYNOPSIS
        Imports a Metra operator profile.
    .DESCRIPTION
        Reads a folder or .zip profile using the profiles/sample layout. Only recognized local
        configuration, registry, and persona overlay files can be imported. When the manifest
        includes per-file hashes, those hashes are verified before copy.
    .PARAMETER Path
        Source profile folder or .zip path.
    .PARAMETER Preview
        Lists planned copies without writing files.
    .PARAMETER Force
        Overwrites existing local files. Without Force, the command refuses any overwrite.
    .PARAMETER Quiet
        Suppresses host messages for automated callers.
    .EXAMPLE
        Import-MetraProfile -Path .\profiles\sample -Preview
    .EXAMPLE
        Import-MetraProfile -Path $env:TEMP\my-metra-profile.zip -Force
    .OUTPUTS
        PSCustomObject containing preview state, files, source, and destination when applicable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$Preview,

        [switch]$Force,

        [switch]$MergeMachineLocal,

        [switch]$Quiet
    )

    $metraRoot = Get-MetraRoot
    $configPath = Join-Path $metraRoot 'metra.config.json'
    $localConfigBefore = $null
    if ($MergeMachineLocal -and (Test-Path -LiteralPath $configPath)) {
        try {
            $localConfigBefore = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            if (-not $Quiet) {
                Write-Warning "Could not read existing metra.config.json for merge: $($_.Exception.Message)"
            }
        }
    }

    $resolved = Resolve-MetraProfileSourceDir -Path $Path
    try {
        $srcDir = $resolved.Directory
        $manifestPath = Join-Path $srcDir 'metra-profile.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            $manifestPath = Join-Path $srcDir 'meta-profile.json'
        }
        $fileMap = @(Get-MetraProfileFileMap)
        $fromManifest = @()
        $manifest = $null
        if (Test-Path -LiteralPath $manifestPath) {
            try {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                throw "Profile manifest is not valid JSON: $manifestPath"
            }
            $rawFiles = @(Get-MetraProp -Object $manifest -Name 'files' -Default @())
            $fromManifest = @(ConvertTo-MetraProfileManifestRelativePaths -Candidates $rawFiles)
        }
        $candidates = if ($fromManifest.Count -gt 0) { $fromManifest } else { $fileMap }

        $plan = New-Object System.Collections.Generic.List[object]
        foreach ($rel in $candidates) {
            $relNorm = [string]$rel -replace '\\', '/'
            # Legacy pack filenames map onto current destinations.
            $destRel = switch ($relNorm) {
                'meta.config.json' { 'metra.config.json' }
                default { $relNorm }
            }
            $allowed = $false
            foreach ($known in $fileMap) {
                if ($known -eq $destRel) { $allowed = $true; break }
            }
            if (-not $allowed) { continue }

            $src = Join-Path $srcDir ($relNorm -replace '/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $src) -and $relNorm -eq 'metra.config.json') {
                $src = Join-Path $srcDir 'meta.config.json'
            }
            if (-not (Test-Path -LiteralPath $src)) { continue }
            $dst = Join-Path $metraRoot ($destRel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $exists = Test-Path -LiteralPath $dst
            [void]$plan.Add([PSCustomObject]@{
                    Relative = $destRel
                    Source   = $src
                    Dest     = $dst
                    Exists   = $exists
                })
        }

        if ($plan.Count -eq 0) {
            throw "No importable profile files found under: $srcDir"
        }

        if ($manifest) {
            Assert-MetraProfilePlanHashes -Manifest $manifest -Plan $plan.ToArray()
        }

        if ($Preview) {
            if (-not $Quiet) {
                Write-Host 'Preview import (no writes):' -ForegroundColor Cyan
                foreach ($row in $plan) {
                    $flag = if ($row.Exists) { 'OVERWRITE' } else { 'NEW' }
                    Write-Host ("  [{0}] {1}" -f $flag, $row.Relative)
                }
                Write-Host ''
                Write-Host 'Post-import checklist (after a real import):'
                Write-Host '  - Edit metra.config.json roots / workspace.alwaysInclude for this machine'
                Write-Host '  - Edit .cursor/rules/metra-persona.local.mdc operator display name'
                Write-Host '  - Personal-root registryFile is not in the pack; copy separately if needed'
                Write-Host '  - Run .\metra.ps1 setup (or workspace) after editing roots'
            }
            return [PSCustomObject]@{
                Preview = $true
                Files   = @($plan | ForEach-Object { $_.Relative })
                Source  = $resolved.Source
            }
        }

        $blocked = @($plan | Where-Object { $_.Exists })
        if ($blocked.Count -gt 0 -and -not $Force) {
            $names = ($blocked | ForEach-Object { $_.Relative }) -join ', '
            throw "Refusing to overwrite existing files without -Force: $names"
        }

        $copied = New-Object System.Collections.Generic.List[string]
        foreach ($row in $plan) {
            if (-not $PSCmdlet.ShouldProcess($row.Dest, "Import Metra profile file $($row.Relative)")) {
                continue
            }
            $dstDir = Split-Path -Parent $row.Dest
            if (-not (Test-Path -LiteralPath $dstDir)) {
                [void][System.IO.Directory]::CreateDirectory($dstDir)
            }
            Copy-Item -LiteralPath $row.Source -Destination $row.Dest -Force
            [void]$copied.Add($row.Relative)
            if (-not $Quiet) {
                Write-Host ("Imported {0}" -f $row.Relative)
            }
        }

        if ($MergeMachineLocal -and $localConfigBefore -and ($copied -contains 'metra.config.json')) {
            try {
                $importedCfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $merge = Merge-MetraProfileMachineLocalConfig -Imported $importedCfg -Local $localConfigBefore -Quiet:$Quiet
                if ($merge.Merged) {
                    $null = Save-MetraProfileConfigObject -Config $merge.Config -MetraRoot $metraRoot
                }
            }
            catch {
                if (-not $Quiet) {
                    Write-Warning "Profile machine-local merge skipped: $($_.Exception.Message)"
                }
            }
        }

        if ($copied.Count -eq 0) {
            return [PSCustomObject]@{
                Preview = $false
                Files   = @()
                Source  = $resolved.Source
                Dest    = $metraRoot
                WhatIf  = $true
            }
        }

        if (-not $Quiet) {
            Write-Host ''
            Write-Host 'Post-import checklist:' -ForegroundColor Yellow
            Write-Host '  - Edit metra.config.json roots / workspace.alwaysInclude for this machine'
            Write-Host '  - Edit .cursor/rules/metra-persona.local.mdc operator display name'
            Write-Host '  - Personal-root registryFile is not in the pack; copy separately if needed'
            Write-Host '  - Run .\metra.ps1 setup (or workspace) after editing roots'
        }

        return [PSCustomObject]@{
            Preview = $false
            Files   = @($copied.ToArray())
            Source  = $resolved.Source
            Dest    = $metraRoot
            WhatIf  = $false
        }
    }
    finally {
        if ($resolved.TempDir -and (Test-Path -LiteralPath $resolved.TempDir)) {
            Remove-Item -LiteralPath $resolved.TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Sync-MetraProfile {
    <#
    .SYNOPSIS
        Pulls HQ profile pack over Ops when contentHash differs (satellite apply).
    .DESCRIPTION
        Metra Profile Sync v1: HQ-published, satellite-pulled. Calls GET /api/profile/status,
        downloads export when remote hash differs from docs/profile-sync.local.json, then
        Import-MetraProfile. Never writes the remote machine. Best-effort check-in after status/sync.
        Supports native -WhatIf / -Confirm (SupportsShouldProcess).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$OpsBaseUrl,

        [ValidateNotNullOrEmpty()]
        [string]$SyncToken,

        [switch]$Force,

        [switch]$Quiet,

        [Parameter(DontShow)]
        $RemoteStatus
    )

    $metraRoot = Get-MetraRoot
    $base = if ($RemoteStatus -and [string]::IsNullOrWhiteSpace($OpsBaseUrl)) {
        'test://local'
    }
    else {
        Resolve-MetraProfileOpsBaseUrl -OpsBaseUrl $OpsBaseUrl -MetraRoot $metraRoot
    }
    $token = Resolve-MetraProfileSyncToken -SyncToken $SyncToken -MetraRoot $metraRoot
    if (-not $RemoteStatus -and [string]::IsNullOrWhiteSpace($token)) {
        throw 'Profile sync token missing. Pass -SyncToken, set METRA_PROFILE_SYNC_TOKEN, or store syncToken in docs/profile-sync.local.json (issue on HQ via profile issue-sync-token).'
    }

    if ($RemoteStatus) {
        $status = $RemoteStatus
    }
    else {
        $headers = @{
            'X-Metra-Profile-Sync' = $token
        }

        $statusUri = "$base/api/profile/status"
        try {
            $status = Invoke-RestMethod -Uri $statusUri -Headers $headers -Method Get -TimeoutSec 30 -ErrorAction Stop
        }
        catch {
            throw "Failed to GET profile status from $statusUri : $($_.Exception.Message)"
        }
    }

    $remoteHash = [string](Get-MetraProp -Object $status -Name 'contentHash' -Default '')
    if ([string]::IsNullOrWhiteSpace($remoteHash)) {
        throw 'Remote /api/profile/status did not return contentHash.'
    }

    $local = Get-MetraProfileSyncLocalState -MetraRoot $metraRoot
    $lastApplied = ''
    if ($local.Data) {
        $lastApplied = [string](Get-MetraProp -Object $local.Data -Name 'lastAppliedHash' -Default '')
    }

    # Report current applied hash (or empty) so Behind machines still appear on HQ roster.
    if (-not $RemoteStatus -and -not $WhatIfPreference -and -not [string]::IsNullOrWhiteSpace($token)) {
        $checkIn = Send-MetraProfileCheckIn -OpsBaseUrl $base -SyncToken $token -LastAppliedHash $lastApplied
        if (-not $Quiet -and $checkIn -and -not $checkIn.Ok -and -not $checkIn.Skipped) {
            Write-Warning ("Profile check-in failed: {0}" -f $checkIn.Error)
        }
    }

    if (-not $Force -and $lastApplied -eq $remoteHash) {
        if (-not $Quiet) {
            Write-Host "Profile already current: $remoteHash"
        }
        return [PSCustomObject]@{
            Ok             = $true
            AlreadyCurrent = $true
            ContentHash    = $remoteHash
            OpsBaseUrl     = $base
            Imported       = $false
            WhatIf         = [bool]$WhatIfPreference
        }
    }

    if (-not $PSCmdlet.ShouldProcess($metraRoot, "Sync Metra profile from $base")) {
        if (-not $Quiet) {
            Write-Host 'Would sync profile:'
            Write-Host "  Remote hash: $remoteHash"
            Write-Host "  Local hash:  $(if ($lastApplied) { $lastApplied } else { '(none)' })"
            Write-Host "  Ops:         $base"
        }
        return [PSCustomObject]@{
            Ok             = $true
            AlreadyCurrent = $false
            ContentHash    = $remoteHash
            LocalHash      = $lastApplied
            OpsBaseUrl     = $base
            Imported       = $false
            WhatIf         = $true
        }
    }

    if ($RemoteStatus) {
        throw 'RemoteStatus is for status/WhatIf tests only. Omit it to download and import from Ops.'
    }

    $headers = @{
        'X-Metra-Profile-Sync' = $token
    }
    $safeName = ($remoteHash -replace '[:\\/]', '-')
    $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) (
        "metra-profile-$safeName-$([guid]::NewGuid().ToString('N')).zip"
    )
    $exportUri = "$base/api/profile/export"
    try {
        Invoke-WebRequest -Uri $exportUri -Headers $headers -OutFile $zipPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop |
            Out-Null
    }
    catch {
        throw "Failed to download profile export from $exportUri : $($_.Exception.Message)"
    }

    if (-not (Test-Path -LiteralPath $zipPath)) {
        throw 'Profile export download did not create a file.'
    }
    if ((Get-Item -LiteralPath $zipPath).Length -le 0) {
        throw 'Profile export download was empty.'
    }

    try {
        $importResult = Import-MetraProfile -Path $zipPath -Force -MergeMachineLocal -Quiet:$Quiet -Confirm:$false
    }
    finally {
        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }
    }

    $rootsRepair = $null
    try {
        $rootsRepair = Repair-MetraSatelliteLocalRoots -MetraRoot $metraRoot -Quiet:$Quiet
    }
    catch {
        if (-not $Quiet) {
            Write-Warning "Satellite roots repair skipped: $($_.Exception.Message)"
        }
    }

    $postSync = $null
    try {
        $postSync = Complete-MetraSatellitePostSync -MetraRoot $metraRoot -OpsBaseUrl $base -Quiet:$Quiet
    }
    catch {
        if (-not $Quiet) {
            Write-Warning "Satellite post-sync prefs skipped: $($_.Exception.Message)"
        }
    }

    $prevToken = $token
    if ($local.Data) {
        $existingTok = [string](Get-MetraProp -Object $local.Data -Name 'syncToken' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($existingTok)) {
            $prevToken = $existingTok
        }
    }

    $newState = [ordered]@{
        lastAppliedHash = $remoteHash
        lastSyncUtc     = [DateTime]::UtcNow.ToString('o')
        lastSourceUrl   = $base
        opsBaseUrl      = $base
        lastFileCount   = [int](Get-MetraProp -Object $status -Name 'fileCount' -Default 0)
        syncToken       = $prevToken
    }
    $statePath = Save-MetraProfileSyncLocalState -State $newState -MetraRoot $metraRoot

    $checkIn2 = Send-MetraProfileCheckIn -OpsBaseUrl $base -SyncToken $token -LastAppliedHash $remoteHash
    if (-not $Quiet -and $checkIn2 -and -not $checkIn2.Ok -and -not $checkIn2.Skipped) {
        Write-Warning ("Profile check-in failed: {0}" -f $checkIn2.Error)
    }

    if (-not $Quiet) {
        Write-Host "Profile synced: $remoteHash"
    }

    return [PSCustomObject]@{
        Ok             = $true
        AlreadyCurrent = $false
        ContentHash    = $remoteHash
        OpsBaseUrl     = $base
        Imported       = $true
        WhatIf         = $false
        Files          = @($importResult.Files)
        StatePath      = $statePath
        RootsRepair    = $rootsRepair
        PostSync       = $postSync
    }
}

function Get-MetraProfileSyncClientStatus {
    <#
    .SYNOPSIS
        Satellite freshness vs HQ published fingerprint (Current / Behind / Unknown).
    .DESCRIPTION
        Compares remote contentHash to local lastAppliedHash. Does not import. Best-effort check-in.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$OpsBaseUrl,

        [ValidateNotNullOrEmpty()]
        [string]$SyncToken,

        [switch]$Quiet,

        [Parameter(DontShow)]
        $RemoteStatus
    )

    $metraRoot = Get-MetraRoot
    $base = $null
    try {
        $base = if ($RemoteStatus -and [string]::IsNullOrWhiteSpace($OpsBaseUrl)) {
            'test://local'
        }
        else {
            Resolve-MetraProfileOpsBaseUrl -OpsBaseUrl $OpsBaseUrl -MetraRoot $metraRoot
        }
    }
    catch {
        $msg = $_.Exception.Message
        if (-not $Quiet) {
            Write-Host 'Profile status: Unknown'
            Write-Host 'Unable to reach the main Metra machine.'
            Write-Host 'Configured HQ: (not set)'
            Write-Host $msg
        }
        return [PSCustomObject]@{
            Ok              = $false
            State           = 'Unknown'
            Message         = 'Unable to reach the main Metra machine.'
            OpsBaseUrl      = $null
            ContentHash     = $null
            LastAppliedHash = $null
            Error           = $msg
        }
    }

    $token = Resolve-MetraProfileSyncToken -SyncToken $SyncToken -MetraRoot $metraRoot
    $local = Get-MetraProfileSyncLocalState -MetraRoot $metraRoot
    $lastApplied = ''
    if ($local.Data) {
        $lastApplied = [string](Get-MetraProp -Object $local.Data -Name 'lastAppliedHash' -Default '')
    }

    if ($RemoteStatus) {
        $status = $RemoteStatus
    }
    else {
        if ([string]::IsNullOrWhiteSpace($token)) {
            $msg = 'Profile sync token missing.'
            if (-not $Quiet) {
                Write-Host 'Profile status: Unknown'
                Write-Host 'Unable to reach the main Metra machine.'
                Write-Host ("Configured HQ: {0}" -f $base)
                Write-Host $msg
            }
            return [PSCustomObject]@{
                Ok              = $false
                State           = 'Unknown'
                Message         = 'Unable to reach the main Metra machine.'
                OpsBaseUrl      = $base
                ContentHash     = $null
                LastAppliedHash = $lastApplied
                Error           = $msg
            }
        }
        $headers = @{ 'X-Metra-Profile-Sync' = $token }
        $statusUri = "$base/api/profile/status"
        try {
            $status = Invoke-RestMethod -Uri $statusUri -Headers $headers -Method Get -TimeoutSec 30 -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            if (-not $Quiet) {
                Write-Host 'Profile status: Unknown'
                Write-Host 'Unable to reach the main Metra machine.'
                Write-Host ("Configured HQ: {0}" -f $base)
            }
            return [PSCustomObject]@{
                Ok              = $false
                State           = 'Unknown'
                Message         = 'Unable to reach the main Metra machine.'
                OpsBaseUrl      = $base
                ContentHash     = $null
                LastAppliedHash = $lastApplied
                Error           = $msg
            }
        }
    }

    $remoteHash = [string](Get-MetraProp -Object $status -Name 'contentHash' -Default '')
    if ([string]::IsNullOrWhiteSpace($remoteHash)) {
        if (-not $Quiet) {
            Write-Host 'Profile status: Unknown'
            Write-Host 'Unable to reach the main Metra machine.'
            Write-Host ("Configured HQ: {0}" -f $base)
            Write-Host 'Remote /api/profile/status did not return contentHash.'
        }
        return [PSCustomObject]@{
            Ok              = $false
            State           = 'Unknown'
            Message         = 'Unable to reach the main Metra machine.'
            OpsBaseUrl      = $base
            ContentHash     = $null
            LastAppliedHash = $lastApplied
            Error           = 'Remote /api/profile/status did not return contentHash.'
        }
    }

    if (-not $RemoteStatus -and -not [string]::IsNullOrWhiteSpace($token)) {
        $checkIn = Send-MetraProfileCheckIn -OpsBaseUrl $base -SyncToken $token -LastAppliedHash $lastApplied
        if (-not $Quiet -and $checkIn -and -not $checkIn.Ok -and -not $checkIn.Skipped) {
            Write-Warning ("Profile check-in failed: {0}" -f $checkIn.Error)
        }
    }

    $state = if ($lastApplied -eq $remoteHash) { 'Current' } else { 'Behind' }
    if (-not $Quiet) {
        Write-Host ("Profile status: {0}" -f $state)
        Write-Host ("  Remote: {0}" -f $remoteHash)
        Write-Host ("  Local:  {0}" -f $(if ($lastApplied) { $lastApplied } else { '(none)' }))
        Write-Host ("  Ops:    {0}" -f $base)
    }

    return [PSCustomObject]@{
        Ok              = $true
        State           = $state
        Message         = $state
        OpsBaseUrl      = $base
        ContentHash     = $remoteHash
        LastAppliedHash = $lastApplied
        Error           = $null
    }
}
