#Requires -Version 5.1
<#
.SYNOPSIS
    Build MetraHost.exe (C# tray supervisor) into host/MetraHost/publish.
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$proj = Join-Path $root 'host\MetraHost\MetraHost.csproj'
$out = Join-Path $root 'host\MetraHost\publish'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'dotnet SDK required to build MetraHost.'
}

dotnet publish $proj -c $Configuration -o $out --nologo
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit $LASTEXITCODE"
}

$exe = Join-Path $out 'MetraHost.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    throw "Publish succeeded but MetraHost.exe missing at $exe"
}

Write-Host "Built $exe" -ForegroundColor Green
