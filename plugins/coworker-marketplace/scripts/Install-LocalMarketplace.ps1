#Requires -Version 5.1
<#
.SYNOPSIS
  Symlink IWU Coworker marketplace plugins into Cursor local plugins for testing.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string[]]$Plugin = @('coworker-desk', 'tickets', 'codex'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$marketRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pluginsRoot = Join-Path $marketRoot 'plugins'
$localRoot = Join-Path $env:USERPROFILE '.cursor\plugins\local'
if (-not (Test-Path -LiteralPath $localRoot)) {
    if ($PSCmdlet.ShouldProcess($localRoot, 'Ensure local plugins directory')) {
        New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
    }
    elseif (-not (Test-Path -LiteralPath $localRoot)) {
        # -WhatIf: still simulate link targets without creating the directory
        Write-Host "WhatIf: would create $localRoot"
    }
}

if (Test-Path -LiteralPath $localRoot) {
    $localRootResolved = (Resolve-Path -LiteralPath $localRoot).Path
}
else {
    $localRootResolved = [System.IO.Path]::GetFullPath($localRoot)
}
$localRootPrefix = $localRootResolved.TrimEnd('\') + '\'

foreach ($name in @($Plugin)) {
    if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/]' -or $name -in @('.', '..')) {
        throw "Invalid plugin name: '$name' (must be a non-empty single path segment)."
    }
    $src = Join-Path $pluginsRoot $name
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Plugin folder missing: $src"
    }
    $linkPath = Join-Path $localRoot $name
    $linkPathResolved = [System.IO.Path]::GetFullPath($linkPath)
    if (-not $linkPathResolved.StartsWith($localRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Plugin name resolves outside local plugins root: $linkPathResolved"
    }

    if (Test-Path -LiteralPath $linkPath) {
        if (-not $Force) {
            throw "Already exists: $linkPath. Re-run with -Force to replace."
        }
        if (-not $PSCmdlet.ShouldProcess($linkPath, 'Replace plugin symbolic link')) {
            continue
        }
        $existing = Get-Item -LiteralPath $linkPath -Force
        $isReparse = [bool]($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
        if ($isReparse) {
            # Never Remove-Item -Recurse on a directory symlink (can delete the target tree).
            if ($existing.PSIsContainer) {
                [System.IO.Directory]::Delete($linkPath)
            }
            else {
                [System.IO.File]::Delete($linkPath)
            }
        }
        else {
            Remove-Item -LiteralPath $linkPath -Force -Recurse
        }
    }
    elseif (-not $PSCmdlet.ShouldProcess($linkPath, 'Create symbolic link')) {
        continue
    }

    $srcResolved = (Resolve-Path -LiteralPath $src).Path
    Write-Host "Linking $name"
    Write-Host "  Source: $srcResolved"
    Write-Host "  Target: $linkPath"
    try {
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $srcResolved -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Verbose $_.Exception.Message
        throw @"
Symbolic link creation failed for $name.
On Windows, enable Developer Mode or run an elevated shell, then retry.
"@
    }
}

Write-Host ''
Write-Host 'Next:'
Write-Host '  1. Developer: Reload Window in Cursor'
Write-Host '  2. Customize -> Plugins / Skills -> verify coworker-desk, tickets, codex'
Write-Host '  3. Team: point IWU SDT Market (or similar) at the GitHub repo whose root is this folder, then Refresh'
