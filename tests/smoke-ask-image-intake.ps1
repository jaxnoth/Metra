#Requires -Version 7
# Ladder 3 operator smoke - run: pwsh -NoProfile -File .\tests\smoke-ask-image-intake.ps1
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

$metraRoot = Split-Path -Parent $PSScriptRoot
$cfg = New-PesterConfiguration
$cfg.Run.Path = Join-Path $PSScriptRoot 'smoke-ask-image-intake.Tests.ps1'
$cfg.Output.Verbosity = 'Detailed'
$cfg.Run.Exit = $true
Push-Location $metraRoot
try {
    Invoke-Pester -Configuration $cfg
}
finally {
    Pop-Location
}
