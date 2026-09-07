#Requires -Version 5.1
<#
.SYNOPSIS
  Copy TicketTracker tickets skill into the coworker marketplace tickets plugin.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TicketTrackerRoot = $(
        if ($env:TICKETTRACKER_ROOT) { $env:TICKETTRACKER_ROOT }
        elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\TicketTracker')) {
            (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\TicketTracker')).Path
        }
        else { '' }
    ),
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if (-not $TicketTrackerRoot) {
    throw @"
TicketTracker root not set.
Pass -TicketTrackerRoot <path> or set env TICKETTRACKER_ROOT.
"@
}

$src = Join-Path $TicketTrackerRoot '.cursor\skills\tickets\SKILL.md'
if (-not (Test-Path -LiteralPath $src)) {
    throw "Source skill missing: $src"
}

$destDir = Join-Path $PSScriptRoot '..\plugins\tickets\skills\tickets'
$dest = Join-Path $destDir 'SKILL.md'
if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

if ($PSCmdlet.ShouldProcess($dest, "Copy from $src")) {
    Copy-Item -LiteralPath $src -Destination $dest -Force
    Write-Host "Synced tickets skill:"
    Write-Host "  From: $src"
    Write-Host "  To:   $dest"
    Write-Host "Note: re-run Assert-PublishSafe and re-check absolute paths after sync."
}
