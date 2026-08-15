#Requires -Version 5.1
<#
.SYNOPSIS
  Symlink this Agent Plugin into Cursor local plugins for P1 testing.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidatePattern('^(?!\.{1,2}$)[a-zA-Z0-9][a-zA-Z0-9._-]*$')]
    [string]$PluginName = 'iwu-api-readiness',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$pluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$localRoot = Join-Path $env:USERPROFILE '.cursor\plugins\local'
if (-not (Test-Path -LiteralPath $localRoot)) {
    if ($PSCmdlet.ShouldProcess($localRoot, 'Ensure local plugins directory')) {
        New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
    }
    elseif (-not (Test-Path -LiteralPath $localRoot)) {
        return
    }
}
$localRootResolved = (Resolve-Path -LiteralPath $localRoot).Path
$linkPath = Join-Path $localRoot $PluginName
$linkPathResolved = [System.IO.Path]::GetFullPath($linkPath)
if (-not $linkPathResolved.StartsWith($localRootResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "PluginName resolves outside local plugins root: $linkPathResolved"
}

$replaceExisting = Test-Path -LiteralPath $linkPath
if ($replaceExisting) {
    if (-not $Force) {
        throw "Already exists: $linkPath. Re-run with -Force to replace."
    }
    if (-not $PSCmdlet.ShouldProcess($linkPath, 'Replace plugin symbolic link')) {
        return
    }
    Remove-Item -LiteralPath $linkPath -Force -Recurse
}
elseif (-not $PSCmdlet.ShouldProcess($linkPath, 'Create symbolic link')) {
    return
}

Write-Host "Linking plugin:"
Write-Host "  Source: $pluginRoot"
Write-Host "  Target: $linkPath"

try {
    New-Item -ItemType SymbolicLink -Path $linkPath -Target $pluginRoot -ErrorAction Stop | Out-Null
}
catch {
    Write-Verbose $_.Exception.Message
    throw @"
Symbolic link creation failed.
On Windows, enable Developer Mode or run an elevated shell, then retry.
"@
}

Write-Host ""
Write-Host "Next:"
Write-Host "  1. Set POSTMAN_API_KEY in User environment (optional for file-only scan)"
Write-Host "  2. Developer: Reload Window in Cursor"
Write-Host "  3. Customize -> verify skills and Postman MCP"
Write-Host "  4. Smoke: Scan examples/sample-openapi.yaml for agent readiness"
