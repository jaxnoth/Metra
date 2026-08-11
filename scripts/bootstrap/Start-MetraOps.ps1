#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap Metra Ops desk under process-scoped Bypass (no machine policy change).
#>
[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [switch]$NoRefresh,
    [switch]$Full,
    [switch]$Quick,
    [switch]$ForceLocal,
    [ValidateRange(1, 65535)]
    [int]$Port = 7380
)

$ErrorActionPreference = 'Stop'

if ($Full -and $Quick) {
    throw '-Full and -Quick cannot both be specified.'
}

$metraRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$metraCli = Join-Path $metraRoot 'metra.ps1'
if (-not (Test-Path -LiteralPath $metraCli -PathType Leaf)) {
    throw "Unable to locate Metra CLI: $metraCli"
}

Set-Location -LiteralPath $metraRoot

# Stay in-process so Ctrl+C reaches the Ops listener (do not nest powershell.exe).
# Splat a hashtable, not an array: array splatting binds positionally, so switches and -Port
# would land in the CLI's remaining-arguments parameter and be ignored.
$opsArgs = @{ Port = $Port }
if ($NoBrowser) { $opsArgs.NoBrowser = $true }
if ($NoRefresh) { $opsArgs.NoRefresh = $true }
if ($Full) { $opsArgs.Full = $true }
if ($Quick) { $opsArgs.Quick = $true }
if ($ForceLocal) { $opsArgs.ForceLocal = $true }

& $metraCli 'ops' @opsArgs
exit $(if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 })
