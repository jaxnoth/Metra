# Satellite onboarding - HQ Client connect, profile sync merge, Mac root repair.

function Test-MetraHostIsWindows {
    [CmdletBinding()]
    param()
    return [bool]($IsWindows -or ($env:OS -match 'Windows'))
}

function Test-MetraProfileRootPathMatchesHost {
    <#
    .SYNOPSIS
        True when a configured root path looks native to this OS (not the other platform's absolute style).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }

    $expanded = [System.Environment]::ExpandEnvironmentVariables([string]$Path).Trim()
    if ([string]::IsNullOrWhiteSpace($expanded)) { return $true }

    if (Test-MetraHostIsWindows) {
        if ($expanded -match '^/[A-Za-z]:') { return $false }
        if ($expanded -match '^/[Uu]sers/') { return $false }
        if ($expanded -match '^/[Hh]ome/') { return $false }
        if ($expanded -match '^[A-Za-z]:[\\/]') { return $true }
        if ($expanded -match '^\\\\') { return $true }
        return -not [System.IO.Path]::IsPathRooted($expanded)
    }

    if ($expanded -match '^[A-Za-z]:[\\/]') { return $false }
    if ($expanded -match '^\\\\') { return $false }
    if ($expanded -match '^/[A-Za-z]:') { return $false }
    if ($expanded.StartsWith('/')) { return $true }
    return -not [System.IO.Path]::IsPathRooted($expanded)
}

function Test-MetraProfileConfigRootsForeignToHost {
    <#
    .SYNOPSIS
        True when any root.path in config looks like the wrong platform for this machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Config
    )

    $roots = @(Get-MetraProp -Object $Config -Name 'roots' -Default @())
    foreach ($root in $roots) {
        $raw = [string](Get-MetraProp -Object $root -Name 'path' -Default '')
        if (-not (Test-MetraProfileRootPathMatchesHost -Path $raw)) {
            return $true
        }
    }

    $projectsRoot = [string](Get-MetraProp -Object $Config -Name 'projectsRoot' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($projectsRoot)) {
        if (-not (Test-MetraProfileRootPathMatchesHost -Path $projectsRoot)) {
            return $true
        }
    }

    return $false
}

function Get-MetraSatelliteMacConfigTemplate {
    <#
    .SYNOPSIS
        Relative-path Mac-friendly roots template (profiles/satellite-mac/metra.config.json).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $path = Join-Path $MetraRoot 'profiles/satellite-mac/metra.config.json'
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Merge-MetraProfileMachineLocalConfig {
    <#
    .SYNOPSIS
        After HQ profile import, keep machine-local portfolio paths; take HQ opsBaseUrl and desk settings.
    .DESCRIPTION
        Preserves local roots, projectsRoot, and workspace.outputs when the imported pack carries
        foreign (e.g. Windows C:\) paths and local values match this host. HQ-published fields
        (opsBaseUrl, ask, inspect, workspace pins, excludes) stay from the import.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        $Imported,

        [Parameter(Mandatory)]
        $Local,

        [switch]$Quiet
    )

    if (-not $Imported) {
        throw 'Merge-MetraProfileMachineLocalConfig requires Imported config.'
    }
    if (-not $Local) {
        return [PSCustomObject]@{
            Config  = $Imported
            Merged  = $false
            Preserved = @()
        }
    }

    $importForeign = Test-MetraProfileConfigRootsForeignToHost -Config $Imported
    $localForeign = Test-MetraProfileConfigRootsForeignToHost -Config $Local
    $mergedJson = ($Imported | ConvertTo-Json -Depth 30)
    $merged = $mergedJson | ConvertFrom-Json
    $preserved = New-Object System.Collections.Generic.List[string]

    if ($importForeign -and -not $localForeign) {
        $localRoots = Get-MetraProp -Object $Local -Name 'roots' -Default $null
        if ($null -ne $localRoots) {
            $merged | Add-Member -NotePropertyName roots -NotePropertyValue $localRoots -Force
            [void]$preserved.Add('roots')
        }
        $localProjectsRoot = [string](Get-MetraProp -Object $Local -Name 'projectsRoot' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($localProjectsRoot)) {
            $merged | Add-Member -NotePropertyName projectsRoot -NotePropertyValue $localProjectsRoot -Force
            [void]$preserved.Add('projectsRoot')
        }
    }

    $localWorkspace = Get-MetraProp -Object $Local -Name 'workspace' -Default $null
    $localOutputs = if ($localWorkspace) { Get-MetraProp -Object $localWorkspace -Name 'outputs' -Default $null } else { $null }
    if ($null -ne $localOutputs) {
        if (-not $merged.workspace) {
            $merged | Add-Member -NotePropertyName workspace -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $merged.workspace | Add-Member -NotePropertyName outputs -NotePropertyValue $localOutputs -Force
        [void]$preserved.Add('workspace.outputs')
    }

    $didMerge = $preserved.Count -gt 0
    if ($didMerge -and -not $Quiet) {
        Write-Host ("Profile config merge preserved: {0}" -f (($preserved.ToArray()) -join ', ')) -ForegroundColor Cyan
    }

    return [PSCustomObject]@{
        Config    = $merged
        Merged    = $didMerge
        Preserved = @($preserved.ToArray())
    }
}

function Save-MetraProfileConfigObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Config,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $configPath = Join-Path $MetraRoot 'metra.config.json'
    $json = ($Config | ConvertTo-Json -Depth 30)
    Write-MetraProfileAtomicText -Path $configPath -Text ($json + "`r`n")
    return $configPath
}

function Repair-MetraSatelliteLocalRoots {
    <#
    .SYNOPSIS
        When synced HQ config still has foreign roots, apply profiles/satellite-mac template paths.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Preview,
        [switch]$Quiet
    )

    $configPath = Join-Path $metraRoot 'metra.config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return [PSCustomObject]@{
            Ok      = $false
            Preview = [bool]$Preview
            Changed = $false
            Reason  = 'missing metra.config.json'
        }
    }

    $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not (Test-MetraProfileConfigRootsForeignToHost -Config $cfg)) {
        return [PSCustomObject]@{
            Ok      = $true
            Preview = [bool]$Preview
            Changed = $false
            Reason  = 'roots already native'
        }
    }

    $template = Get-MetraSatelliteMacConfigTemplate -MetraRoot $metraRoot
    if (-not $template) {
        return [PSCustomObject]@{
            Ok      = $false
            Preview = [bool]$Preview
            Changed = $false
            Reason  = 'missing profiles/satellite-mac/metra.config.json'
        }
    }

    if ($Preview -or $WhatIfPreference) {
        if (-not $Quiet) {
            Write-Host 'Would apply satellite-mac roots template (foreign HQ paths detected).' -ForegroundColor Cyan
        }
        return [PSCustomObject]@{
            Ok       = $true
            Preview  = $true
            Changed  = $false
            Reason   = 'foreign roots'
            Template = 'profiles/satellite-mac/metra.config.json'
        }
    }

    if (-not $PSCmdlet.ShouldProcess($configPath, 'Apply satellite-mac roots template')) {
        if (-not $Quiet) {
            Write-Host 'Cancelled satellite roots repair.' -ForegroundColor Yellow
        }
        return [PSCustomObject]@{
            Ok       = $false
            Preview  = $false
            Changed  = $false
            Reason   = 'Cancelled'
            Template = 'profiles/satellite-mac/metra.config.json'
        }
    }

    $merge = Merge-MetraProfileMachineLocalConfig -Imported $cfg -Local $template -Quiet:$Quiet
    $saved = Save-MetraProfileConfigObject -Config $merge.Config -MetraRoot $metraRoot
    if (-not $Quiet) {
        Write-Host ("Satellite roots repaired from template: {0}" -f $saved) -ForegroundColor Green
    }

    return [PSCustomObject]@{
        Ok       = $true
        Preview  = $false
        Changed  = $true
        Path     = $saved
        Preserved = @($merge.Preserved)
        Reason   = 'applied satellite-mac template'
    }
}

function Test-MetraOpsHttpsReachable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OpsBaseUrl,
        [int]$TimeoutSec = 15
    )

    $base = $OpsBaseUrl.Trim().TrimEnd('/')
    if (-not (Test-MetraProfileOpsBaseUrlForm -OpsBaseUrl $base)) {
        return [PSCustomObject]@{ Ok = $false; Url = $base; Error = 'invalid OpsBaseUrl form' }
    }

    $uri = "$base/api/settings"
    try {
        $null = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
        return [PSCustomObject]@{ Ok = $true; Url = $uri; Error = $null }
    }
    catch {
        return [PSCustomObject]@{ Ok = $false; Url = $uri; Error = [string]$_.Exception.Message }
    }
}

function Complete-MetraSatellitePostSync {
    <#
    .SYNOPSIS
        After profile sync on a satellite, ensure Desk Mode B prefs and opsBaseUrl align with HQ.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$OpsBaseUrl,
        [switch]$Quiet
    )

    $base = Resolve-MetraProfileOpsBaseUrl -OpsBaseUrl $OpsBaseUrl -MetraRoot $metraRoot
    if ([string]::IsNullOrWhiteSpace($base)) {
        return [PSCustomObject]@{ Ok = $false; Reason = 'OpsBaseUrl missing' }
    }

    $null = Invoke-MetraMachineRoleSetup -MetraRoot $metraRoot -Role Satellite -OpsBaseUrl $base -Quiet:$Quiet
    $written = Set-MetraConfiguredOpsBaseUrl -OpsBaseUrl $base -MetraRoot $metraRoot

    return [PSCustomObject]@{
        Ok         = $true
        OpsBaseUrl = $written.OpsBaseUrl
        MachineRole = 'Satellite'
    }
}

function Invoke-MetraSatelliteConnect {
    <#
    .SYNOPSIS
        Guided satellite bootstrap: validate HQ HTTPS, set role, profile sync, merge local roots.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OpsBaseUrl,

        [ValidateNotNullOrEmpty()]
        [string]$SyncToken,

        [switch]$Force,

        [switch]$SkipCampusHosts,

        [switch]$SkipSync,

        [switch]$Quiet
    )

    $metraRoot = Get-MetraRoot
    $base = $OpsBaseUrl.Trim().TrimEnd('/')
    if (-not (Test-MetraProfileOpsBaseUrlForm -OpsBaseUrl $base)) {
        throw "Invalid OpsBaseUrl (use HTTPS Tailscale Serve URL): $base"
    }
    if ($base -notmatch '^https://' -and -not $Quiet) {
        Write-Warning 'OpsBaseUrl is not HTTPS. Prefer https://<hq>.ts.net (Tailscale Serve).'
    }

    if (-not $PSCmdlet.ShouldProcess($metraRoot, "Connect Metra satellite to $base")) {
        return [PSCustomObject]@{
            Ok         = $false
            Preview    = $false
            Cancelled  = $true
            OpsBaseUrl = $base
            Reason     = 'Cancelled'
        }
    }

    $reach = Test-MetraOpsHttpsReachable -OpsBaseUrl $base
    if (-not $reach.Ok) {
        throw "HQ Ops not reachable at $($reach.Url): $($reach.Error)"
    }
    if (-not $Quiet) {
        Write-Host ("HQ Ops reachable: {0}" -f $reach.Url) -ForegroundColor Green
    }

    if (-not [string]::IsNullOrWhiteSpace($SyncToken)) {
        $null = Set-MetraProfileSyncClientToken -SyncToken $SyncToken -MetraRoot $metraRoot
    }

    $null = Invoke-MetraMachineRoleSetup -MetraRoot $metraRoot -Role Satellite -OpsBaseUrl $base -SyncToken $SyncToken -Quiet:$Quiet

    $syncResult = $null
    if (-not $SkipSync) {
        $syncParams = @{
            OpsBaseUrl = $base
            Quiet      = [bool]$Quiet
            Force      = [bool]$Force
        }
        if (-not [string]::IsNullOrWhiteSpace($SyncToken)) {
            $syncParams.SyncToken = $SyncToken
        }
        $syncResult = Sync-MetraProfile @syncParams
    }

    $rootsRepair = Repair-MetraSatelliteLocalRoots -MetraRoot $metraRoot -Quiet:$Quiet
    $post = Complete-MetraSatellitePostSync -MetraRoot $metraRoot -OpsBaseUrl $base -Quiet:$Quiet

    $campus = $null
    if (-not $SkipCampusHosts -and (Test-MetraHostIsWindows)) {
        try {
            $campus = Show-MetraTailscaleCli -Subcommand 'campus-hosts' -Preview -Quiet:$Quiet
        }
        catch {
            $campus = [PSCustomObject]@{ Ok = $false; Error = [string]$_.Exception.Message }
        }
        if (-not $Quiet -and $campus -and $campus.NeedsWrite) {
            Write-Host ''
            Write-Host 'IWU campus: run elevated campus-hosts before Tailscale Serve admin pages:' -ForegroundColor Yellow
            Write-Host '  pwsh -NoProfile -File .\metra.ps1 tailscale campus-hosts -Force' -ForegroundColor DarkGray
        }
    }

    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Satellite connect done. Verify:' -ForegroundColor Cyan
        Write-Host '  pwsh -NoProfile -File .\metra.ps1 profile status'
        Write-Host '  pwsh -NoProfile -File .\metra.ps1 ask sessions'
    }

    return [PSCustomObject]@{
        Ok           = $true
        Preview      = $false
        OpsBaseUrl   = $base
        Reachable    = $true
        Sync         = $syncResult
        RootsRepair  = $rootsRepair
        PostSync     = $post
        CampusPreview = $campus
    }
}

function Show-MetraSatelliteCli {
    <#
    .SYNOPSIS
        Thin CLI export for satellite onboarding helpers.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('connect', 'repair-roots', 'help')]
        [string]$Subcommand = 'help',

        [string]$OpsBaseUrl,
        [string]$SyncToken,
        [switch]$Force,
        [switch]$SkipCampusHosts,
        [switch]$SkipSync,
        [switch]$Preview,
        [switch]$Quiet
    )

    switch ($Subcommand) {
        'connect' {
            if ([string]::IsNullOrWhiteSpace($OpsBaseUrl)) {
                throw 'connect requires -OpsBaseUrl (HTTPS HQ Tailscale Serve URL). Example: .\metra.ps1 satellite connect -OpsBaseUrl https://jumpbox.emerald-banana.ts.net'
            }
            if ($Preview) {
                if (-not $Quiet) {
                    Write-Host 'Would connect satellite:' -ForegroundColor Cyan
                    Write-Host "  OpsBaseUrl: $($OpsBaseUrl.Trim().TrimEnd('/'))"
                    Write-Host '  Steps: reachability test, Satellite role, profile sync (merge local roots), repair-roots if needed'
                }
                return [PSCustomObject]@{ Ok = $true; Preview = $true; OpsBaseUrl = $OpsBaseUrl.Trim().TrimEnd('/') }
            }
            return Invoke-MetraSatelliteConnect -OpsBaseUrl $OpsBaseUrl -SyncToken $SyncToken -Force:$Force `
                -SkipCampusHosts:$SkipCampusHosts -SkipSync:$SkipSync -Quiet:$Quiet
        }
        'repair-roots' {
            return Repair-MetraSatelliteLocalRoots -Preview:$Preview -Quiet:$Quiet
        }
        default {
            Write-Host @'
Metra satellite onboarding (HQ Client / Desk Mode B):

  pwsh -NoProfile -File .\metra.ps1 satellite connect -OpsBaseUrl https://<hq>.ts.net [-SyncToken ...] [-Force]

  - Validates HTTPS reachability to HQ Ops
  - Sets machine role Satellite and opsBaseUrl
  - profile sync with machine-local roots merge (won't clobber Mac paths with Windows C:\)
  - Applies profiles/satellite-mac template when foreign roots remain

  pwsh -NoProfile -File .\metra.ps1 satellite repair-roots [-Preview]

On IWU campus Windows hosts, connect previews campus-hosts; run elevated if NeededWrite.

See docs/playbooks/satellite-remote-install.md
'@
            return [PSCustomObject]@{ Ok = $true; Subcommand = 'help' }
        }
    }
}
