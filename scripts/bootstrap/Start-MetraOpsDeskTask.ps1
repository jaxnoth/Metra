# Headless Ops desk for MetraOpsDesk Scheduled Task (reach layer).
# Does not start the tray Host. Ops owns Ask.
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force

# NoBrowser: no interactive desk open. Process stays on the console (Task keeps it alive).
Start-MetraOpsServer -NoBrowser -NoRefresh
