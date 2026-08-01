<#
.SYNOPSIS
    First-run bootstrap for ZIP / blocked checkouts. Clears mark-of-the-web, then runs setup.
.DESCRIPTION
    Intended to be launched via Metra-Setup.cmd with process-scoped -ExecutionPolicy Bypass.
    Does not change the machine ExecutionPolicy. Prefer this over explaining ADS streams.
#>
[CmdletBinding()]
param(
    [switch]$SkipSetup,
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'
$metraRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $metraRoot

Write-Host ''
Write-Host 'Metra first-run bootstrap' -ForegroundColor Cyan
Write-Host ("  Root: {0}" -f $metraRoot)

Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
$unblock = Show-MetraUnblockCli -Path $metraRoot -Preview:$Preview
if ($unblock.Failed -gt 0) {
    Write-Host ''
    Write-Host 'Unblock reported failures. Fix those files, then re-run Metra-Setup.cmd.' -ForegroundColor Yellow
    if (-not $SkipSetup) {
        Write-Host 'Press Enter to close...'
        $null = Read-Host
    }
    exit 1
}

if ($SkipSetup -or $Preview) {
    Write-Host ''
    Write-Host 'Skipping setup (-SkipSetup or -Preview).' -ForegroundColor Yellow
    if (-not $SkipSetup) {
        Write-Host 'Press Enter to close...'
        $null = Read-Host
    }
    exit 0
}

Write-Host ''
Write-Host 'Running setup...' -ForegroundColor Cyan
& (Join-Path $metraRoot 'metra.ps1') setup
$setupExit = $LASTEXITCODE

Write-Host ''
Write-Host 'Next:' -ForegroundColor Yellow
Write-Host '  - Edit metra.config.json roots if paths differ, then: .\metra.ps1 setup'
Write-Host '  - Day-2 CLI under RemoteSigned: .\metra.ps1 verify'
Write-Host '  - If scripts still refuse to run: .\metra.ps1 unblock'
Write-Host ''
Write-Host 'Press Enter to close...'
$null = Read-Host
exit $(if ($null -ne $setupExit -and $setupExit -ne 0) { $setupExit } else { 0 })
