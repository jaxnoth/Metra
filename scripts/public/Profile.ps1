# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Export-MetraProfile {
    <#
    .SYNOPSIS
        Packs local Metra customizations into a portable profile.
    .DESCRIPTION
        Writes the same layout used by profiles/sample. A path ending in .zip produces an
        archive; other paths produce a folder. Secrets, ticket caches, canvas snapshots, and
        personal-root registry files are not included.
    .PARAMETER Path
        Destination folder or .zip path. Environment variables and relative paths are supported.
    .EXAMPLE
        Export-MetraProfile -Path $env:TEMP\my-metra-profile.zip
    .EXAMPLE
        Export-MetraProfile -Path .\profile-backup
    .OUTPUTS
        PSCustomObject containing destination path, included files, archive state, and manifest.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
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
    $destFull = [System.IO.Path]::GetFullPath($expanded)
    $asZip = $destFull.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)

    $staging = if ($asZip) {
        Join-Path ([System.IO.Path]::GetTempPath()) ('metra-profile-export-' + [guid]::NewGuid().ToString('N'))
    }
    else {
        $destFull
    }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    foreach ($rel in $present) {
        $src = Join-Path $metraRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $dst = Join-Path $staging ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    $status = Get-MetraProfileStatus -MetraRoot $metraRoot
    $fileDetails = @(
        $status.files | ForEach-Object {
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
        source             = 'jumpbox'
        files              = $fileDetails
        notes              = @(
            'Personal-root registryFile (e.g. projects.personal.json beside personal projects) is not included; copy it with that root separately.',
            'Optional metra-humor.local.mdc / metra-teaching-gentle.local.mdc are included when present (Persona Add-ons).',
            'Do not pack secrets, ticket caches, or canvas snapshots.',
            'Metra Profile Sync v1: HQ-published, satellite-pulled.'
        )
    }
    $manifestPath = Join-Path $staging 'metra-profile.json'
    ($manifest | ConvertTo-Json -Depth 6) | Set-Content -Path $manifestPath -Encoding utf8

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
"@ | Set-Content -Path $readmePath -Encoding utf8

    $resultPath = $destFull
    $manifestOut = $manifestPath
    if ($asZip) {
        $zipDir = Split-Path -Parent $destFull
        if ($zipDir -and -not (Test-Path -LiteralPath $zipDir)) {
            New-Item -ItemType Directory -Path $zipDir -Force | Out-Null
        }
        if (Test-Path -LiteralPath $destFull) {
            Remove-Item -LiteralPath $destFull -Force
        }
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $destFull -Force
        Remove-Item -LiteralPath $staging -Recurse -Force
        $manifestOut = 'metra-profile.json (inside zip)'
    }

    return [PSCustomObject]@{
        Path      = $resultPath
        Files     = @($present.ToArray())
        IsZip     = $asZip
        Manifest  = $manifestOut
    }
}

function Import-MetraProfile {
    <#
    .SYNOPSIS
        Imports a Metra operator profile.
    .DESCRIPTION
        Reads a folder or .zip profile using the profiles/sample layout. Only recognized local
        configuration, registry, and persona overlay files can be imported.
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Preview,
        [switch]$Force,
        [switch]$Quiet
    )

    $metraRoot = Get-MetraRoot
    $resolved = Resolve-MetraProfileSourceDir -Path $Path
    try {
        $srcDir = $resolved.Directory
        $manifestPath = Join-Path $srcDir 'metra-profile.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            $manifestPath = Join-Path $srcDir 'meta-profile.json'
        }
        $fileMap = @(Get-MetraProfileFileMap)
        $fromManifest = @()
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
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

        foreach ($row in $plan) {
            $dstDir = Split-Path -Parent $row.Dest
            if (-not (Test-Path -LiteralPath $dstDir)) {
                New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $row.Source -Destination $row.Dest -Force
            if (-not $Quiet) {
                Write-Host ("Imported {0}" -f $row.Relative)
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
            Files   = @($plan | ForEach-Object { $_.Relative })
            Source  = $resolved.Source
            Dest    = $metraRoot
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
        Import-MetraProfile. Never writes the remote machine.
    #>
    [CmdletBinding()]
    param(
        [string]$OpsBaseUrl,
        [string]$SyncToken,
        [switch]$WhatIf,
        [switch]$Force,
        [switch]$Quiet,
        # Test / offline inject: skip HTTP GET /api/profile/status when provided.
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
            $status = Invoke-RestMethod -Uri $statusUri -Headers $headers -Method Get
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

    if (-not $Force -and $lastApplied -eq $remoteHash) {
        if (-not $Quiet) {
            Write-Host "Profile already current: $remoteHash"
        }
        return [PSCustomObject]@{
            Ok              = $true
            AlreadyCurrent  = $true
            ContentHash     = $remoteHash
            OpsBaseUrl      = $base
            Imported        = $false
            WhatIf          = [bool]$WhatIf
        }
    }

    if ($WhatIf) {
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
    $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("metra-profile-$safeName.zip")
    $exportUri = "$base/api/profile/export"
    try {
        Invoke-WebRequest -Uri $exportUri -Headers $headers -OutFile $zipPath -UseBasicParsing | Out-Null
    }
    catch {
        throw "Failed to download profile export from $exportUri : $($_.Exception.Message)"
    }

    try {
        $importResult = Import-MetraProfile -Path $zipPath -Force -Quiet:$Quiet
    }
    finally {
        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }
    }

    $prevToken = $token
    $prevOps = $base
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
    }
}

