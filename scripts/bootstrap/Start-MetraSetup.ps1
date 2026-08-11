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
#>
[CmdletBinding()]
param(
    [switch]$SkipSetup,
    [switch]$Preview,
    [switch]$NoPause,
    [switch]$Quiet,
    [ValidateSet('Hq', 'Satellite', 'Standalone')]
    [string]$Role,
    [string]$OpsBaseUrl,
    [string]$SyncToken,
    [switch]$PreferFriendly,
    [switch]$NoPreferFriendly,
    [switch]$BindTailscale,
    [switch]$AcceptAsk
)

$ErrorActionPreference = 'Stop'
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

Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force

$logSession = $null
try {
    $null = Copy-MetraInnoInstallerLog -MetraRoot $metraRoot
    $logSession = Start-MetraSetupTranscript -MetraRoot $metraRoot -Source 'bootstrap'

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
        $setupArgs = @('setup')
        if ($Quiet) { $setupArgs += '-Quiet' }
        if ($Role) { $setupArgs += @('-Role', $Role) }
        if (-not [string]::IsNullOrWhiteSpace($OpsBaseUrl)) {
            $setupArgs += @('-OpsBaseUrl', $OpsBaseUrl.Trim())
        }
        if (-not [string]::IsNullOrWhiteSpace($SyncToken)) {
            $setupArgs += @('-SyncToken', $SyncToken.Trim())
        }
        if ($PreferFriendly) { $setupArgs += '-PreferFriendly' }
        if ($NoPreferFriendly) { $setupArgs += '-NoPreferFriendly' }
        if ($BindTailscale) { $setupArgs += '-BindTailscale' }
        if ($AcceptAsk) { $setupArgs += '-AcceptAsk' }
        & (Join-Path $metraRoot 'metra.ps1') @setupArgs
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
