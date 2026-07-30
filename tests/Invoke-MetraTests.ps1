#Requires -Version 7
<#
.SYNOPSIS
    Run focused Metra Pester tests (Pester 5+).
.EXAMPLE
    pwsh -NoProfile -File .\tests\Invoke-MetraTests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testsRoot = $PSScriptRoot
$metraRoot = Split-Path -Parent $testsRoot

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path = (Join-Path $testsRoot 'Metra.Tests.ps1')
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'

Push-Location $metraRoot
try {
    Invoke-Pester -Configuration $config
}
finally {
    Pop-Location
}

