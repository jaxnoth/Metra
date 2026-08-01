<#
.SYNOPSIS
    First-run bootstrap for ZIP / installer / blocked checkouts. Clears mark-of-the-web, then runs setup.
.DESCRIPTION
    Intended to be launched via Metra-Setup.cmd with process-scoped -ExecutionPolicy Bypass.
    Does not change the machine ExecutionPolicy. Prefer this over explaining ADS streams.
    Use -NoPause for installer post-install tasks (no interactive Read-Host).
#>
[CmdletBinding()]
param(
    [switch]$SkipSetup,
    [switch]$Preview,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$metraRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $metraRoot

function Wait-MetraBootstrapPause {
    if ($NoPause) {
        return
    }
    Write-Host 'Press Enter to close...'
    $null = Read-Host
}

Write-Host ''
Write-Host 'Metra first-run bootstrap' -ForegroundColor Cyan
Write-Host ("  Root: {0}" -f $metraRoot)

Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
$unblock = Show-MetraUnblockCli -Path $metraRoot -Preview:$Preview
if ($unblock.Failed -gt 0) {
    Write-Host ''
    Write-Host 'Unblock reported failures. Fix those files, then re-run Metra-Setup.cmd.' -ForegroundColor Yellow
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
try {
    & (Join-Path $metraRoot 'metra.ps1') setup
    $setupExit = 0
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        $setupExit = [int]$LASTEXITCODE
    }
}
catch {
    Write-Host ("Setup failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    Wait-MetraBootstrapPause
    exit 1
}

Write-Host ''
Write-Host 'Next:' -ForegroundColor Yellow
Write-Host '  - Edit metra.config.json roots if paths differ, then: .\metra.ps1 setup'
Write-Host '  - Day-2 CLI under RemoteSigned: .\metra.ps1 verify'
Write-Host '  - Optional packs (after install): .\metra.ps1 import-profile -Path .\profiles\addons\humor-desk -Force'
Write-Host '  - If scripts still refuse to run: .\metra.ps1 unblock'
Write-Host ''
Wait-MetraBootstrapPause
exit $(if ($null -ne $setupExit -and $setupExit -ne 0) { $setupExit } else { 0 })
