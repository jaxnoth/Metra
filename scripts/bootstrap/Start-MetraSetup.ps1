<#
.SYNOPSIS
    First-run bootstrap for ZIP / installer / blocked checkouts. Clears mark-of-the-web, then runs setup.
.DESCRIPTION
    Intended to be launched via Metra-Setup.cmd with process-scoped -ExecutionPolicy Bypass.
    Does not change the machine ExecutionPolicy. Prefer this over explaining ADS streams.
    Use -NoPause for installer post-install tasks (no interactive Read-Host pause).
    Use -Quiet -Role [-OpsBaseUrl] [-SyncToken] [-PreferFriendly|-NoPreferFriendly] [-BindTailscale] [-AcceptAsk]
    when the installer already collected choices (no terminal quiz).
    Writes a durable transcript to docs/setup.local.log and copies Inno logs when found.
    Quiet Satellite installs require -OpsBaseUrl.
#>
[CmdletBinding()]
param(
    [switch]$SkipSetup,
    [switch]$Preview,
    [switch]$NoPause,
    [switch]$Quiet,
    [ValidateSet('Hq', 'Satellite', 'Standalone')]
    [string]$Role,
    [ValidateNotNullOrEmpty()]
    [string]$OpsBaseUrl,
    [ValidateNotNullOrEmpty()]
    [string]$SyncToken,
    [switch]$PreferFriendly,
    [switch]$NoPreferFriendly,
    [switch]$BindTailscale,
    [switch]$AcceptAsk
)

$ErrorActionPreference = 'Stop'

if ($PreferFriendly -and $NoPreferFriendly) {
    throw '-PreferFriendly and -NoPreferFriendly cannot both be specified.'
}

if ($Quiet -and $Role -eq 'Satellite' -and [string]::IsNullOrWhiteSpace($OpsBaseUrl)) {
    throw '-OpsBaseUrl is required when using -Quiet -Role Satellite.'
}

if (-not [string]::IsNullOrWhiteSpace($OpsBaseUrl)) {
    try {
        $opsUri = [uri]$OpsBaseUrl.Trim()
    }
    catch {
        throw ("Invalid OpsBaseUrl: {0}" -f $OpsBaseUrl)
    }
    if (-not $opsUri.IsAbsoluteUri -or $opsUri.Scheme -notin @('http', 'https')) {
        throw ("OpsBaseUrl must be an absolute http:// or https:// URL: {0}" -f $OpsBaseUrl)
    }
    $OpsBaseUrl = $opsUri.AbsoluteUri.TrimEnd('/')
}

if ($Quiet -and $Role -eq 'Satellite' -and [string]::IsNullOrWhiteSpace($SyncToken)) {
    Write-Warning 'No SyncToken supplied. Profile sync will not be configured during quiet Satellite setup.'
}

$metraRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $metraRoot

if ($Quiet) {
    $NoPause = $true
}

function Wait-MetraBootstrapPause {
    if ($NoPause) {
        return
    }
    Write-Host 'Press Enter to close...'
    $null = Read-Host
}

$modulePath = Join-Path $metraRoot 'scripts\Metra.psd1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Metra module not found: $modulePath"
}

Import-Module $modulePath -Force

$logSession = $null
try {
    # Transcript first so later steps are captured; failures are non-fatal for installer UX.
    try {
        $logSession = Start-MetraSetupTranscript -MetraRoot $metraRoot -Source 'bootstrap'
    }
    catch {
        Write-Warning ("Unable to start setup transcript: {0}" -f $_.Exception.Message)
    }

    try {
        $null = Copy-MetraInnoInstallerLog -MetraRoot $metraRoot
    }
    catch {
        Write-Warning ("Unable to copy installer log: {0}" -f $_.Exception.Message)
    }

    Write-Host ''
    Write-Host 'Metra first-run bootstrap' -ForegroundColor Cyan
    Write-Host ("  Root: {0}" -f $metraRoot)
    Write-Host ("  Log:  {0}" -f (Get-MetraSetupLogPath -MetraRoot $metraRoot)) -ForegroundColor DarkGray
    if ($Quiet) {
        Write-Host ("  Mode: Quiet Role={0}" -f $(if ($Role) { $Role } else { '(default Standalone)' })) -ForegroundColor DarkGray
    }

    $unblock = Show-MetraUnblockCli -Path $metraRoot -Preview:$Preview -Quiet
    if ($unblock.Failed -gt 0) {
        Write-Host ''
        Write-Host 'Unblock reported failures. Fix those files, then re-run Metra-Setup.cmd.' -ForegroundColor Yellow
        Write-Host ("Setup log: {0}" -f (Get-MetraSetupLogPath -MetraRoot $metraRoot)) -ForegroundColor Yellow
        Wait-MetraBootstrapPause
        exit 1
    }

    if ($SkipSetup -or $Preview) {
        Write-Host ''
        Write-Host 'Skipping setup (-SkipSetup or -Preview).' -ForegroundColor Yellow
        Wait-MetraBootstrapPause
        exit 0
    }

    Write-Host ''
    Write-Host 'Running setup...' -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    $setupExit = 0
    try {
        # Call Initialize-Metra directly with a hashtable splat.
        # Array-splatting through metra.ps1 puts switches in $Rest on Windows PowerShell 5.1,
        # and setup treats $Rest[0] as a profile path (e.g. "-Quiet").
        $setupParams = @{}
        if ($Quiet) { $setupParams.Quiet = $true }
        if ($PreferFriendly) { $setupParams.PreferFriendly = $true }
        if ($NoPreferFriendly) { $setupParams.NoPreferFriendly = $true }
        if ($BindTailscale) { $setupParams.BindTailscale = $true }
        if ($AcceptAsk) { $setupParams.AcceptAsk = $true }
        if ($Role) { $setupParams.Role = $Role }
        if (-not [string]::IsNullOrWhiteSpace($OpsBaseUrl)) {
            $setupParams.OpsBaseUrl = $OpsBaseUrl
        }
        if (-not [string]::IsNullOrWhiteSpace($SyncToken)) {
            $setupParams.SyncToken = $SyncToken.Trim()
        }
        $null = Initialize-Metra @setupParams
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            $setupExit = [int]$LASTEXITCODE
        }
    }
    catch {
        Write-Host ("Setup failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        Write-Host ("Setup log: {0}" -f (Get-MetraSetupLogPath -MetraRoot $metraRoot)) -ForegroundColor Yellow
        Wait-MetraBootstrapPause
        exit 1
    }

    Write-Host ''
    Write-Host 'Done.' -ForegroundColor Green
    Write-Host ("Setup log: {0}" -f (Get-MetraSetupLogPath -MetraRoot $metraRoot)) -ForegroundColor DarkGray
    if (-not $Quiet) {
        Write-Host 'Press Enter to close (or use Start Menu: Metra Ops).' -ForegroundColor Green
    }
    Wait-MetraBootstrapPause
    exit $(if ($null -ne $setupExit -and $setupExit -ne 0) { $setupExit } else { 0 })
}
finally {
    if ($null -ne $logSession) {
        Stop-MetraSetupTranscript -Session $logSession -MetraRoot $metraRoot
    }
}
