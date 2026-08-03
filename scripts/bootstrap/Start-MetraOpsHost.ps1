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
    [int]$Port = 7380
)

$ErrorActionPreference = 'Stop'
$metraRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $metraRoot

Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force

if ($Stop) {
    Stop-MetraOpsHost -Port $Port
    exit 0
}

$hostArgs = @{ Port = $Port }
if ($NoBrowser) { $hostArgs.NoBrowser = $true }
if ($NoRefresh) { $hostArgs.NoRefresh = $true }
if ($Quick) { $hostArgs.Quick = $true }

Start-MetraOpsHost @hostArgs
