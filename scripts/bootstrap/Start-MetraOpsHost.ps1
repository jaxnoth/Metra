#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap Metra Ops tray host (user-session). Host -> Ops -> Ask.
#>
[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [switch]$NoRefresh,
    [switch]$Quick,
    [switch]$Stop,
    [ValidateRange(0, 65535)]
    [int]$Port = 0
)

$ErrorActionPreference = 'Stop'

if ($Stop -and ($Quick -or $NoBrowser -or $NoRefresh)) {
    throw '-Stop cannot be combined with startup options.'
}

$metraRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $metraRoot

$modulePath = Join-Path $metraRoot 'scripts\Metra.psd1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Metra module not found: $modulePath"
}

Import-Module $modulePath -Force

if ($Port -le 0) {
    $Port = [int](Resolve-MetraOpsDeskBinding -MetraRoot $metraRoot).Port
}

if ($Port -lt 1 -or $Port -gt 65535) {
    throw "Resolved Ops host port is invalid: $Port"
}

if ($Stop) {
    Stop-MetraOpsHost -Port $Port
    exit 0
}

$hostArgs = @{ Port = $Port }
if ($NoBrowser) { $hostArgs.NoBrowser = $true }
if ($NoRefresh) { $hostArgs.NoRefresh = $true }
if ($Quick) { $hostArgs.Quick = $true }

Start-MetraOpsHost @hostArgs
