<#
.SYNOPSIS
    Stages private Node + ensures engines/cursor deps for Cursor Ask packaging (ship second).
.DESCRIPTION
    Does not download Node automatically in CI without METRA_NODE_ZIP. Prefer copying a
    portable Node build into runtimes/node before installer build. Runs npm ci/install in
    engines/cursor when package.json exists.
#>
[CmdletBinding()]
param(
    [string]$MetraRoot,
    [string]$NodeZipUrl,
    [switch]$SkipNpm
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
    $MetraRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

$runtimeDir = Join-Path $MetraRoot 'runtimes\node'
$cursorDir = Join-Path $MetraRoot 'engines\cursor'
$nodeExe = Join-Path $runtimeDir 'node.exe'

Write-Host 'Metra Cursor Ask packaging helper' -ForegroundColor Cyan
Write-Host ("  Root: {0}" -f $MetraRoot)

if (-not (Test-Path -LiteralPath $nodeExe)) {
    $url = if ($NodeZipUrl) { $NodeZipUrl } else { $env:METRA_NODE_ZIP }
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-Warning "Private Node missing at $nodeExe. Place a Windows x64 Node portable build there before shipping Cursor Ask. Do not tell consumers to install Node themselves."
    }
    else {
        Write-Host "  Downloading Node zip from METRA_NODE_ZIP / -NodeZipUrl..." -ForegroundColor DarkGray
        $tmp = Join-Path $env:TEMP ("metra-node-{0}.zip" -f [guid]::NewGuid().ToString('n'))
        Invoke-WebRequest -Uri $url -OutFile $tmp
        $extract = Join-Path $env:TEMP ("metra-node-{0}" -f [guid]::NewGuid().ToString('n'))
        Expand-Archive -LiteralPath $tmp -DestinationPath $extract -Force
        $found = Get-ChildItem -Path $extract -Recurse -Filter node.exe | Select-Object -First 1
        if (-not $found) { throw "node.exe not found in $url" }
        New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
        Copy-Item -LiteralPath $found.DirectoryName -Destination $runtimeDir -Recurse -Force
        # If we copied a nested folder, flatten when node.exe is one level down
        if (-not (Test-Path -LiteralPath $nodeExe)) {
            $nested = Get-ChildItem -Path $runtimeDir -Recurse -Filter node.exe | Select-Object -First 1
            if ($nested) {
                Get-ChildItem -LiteralPath $nested.DirectoryName | Copy-Item -Destination $runtimeDir -Recurse -Force
            }
        }
        Remove-Item -LiteralPath $tmp, $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path -LiteralPath $nodeExe) {
    Write-Host ("  Private Node: {0}" -f $nodeExe) -ForegroundColor Green
}
else {
    Write-Host '  Private Node: not staged' -ForegroundColor Yellow
}

if (-not $SkipNpm -and (Test-Path -LiteralPath (Join-Path $cursorDir 'package.json'))) {
    Push-Location $cursorDir
    try {
        if (Test-Path -LiteralPath (Join-Path $cursorDir 'package-lock.json')) {
            npm ci
        }
        else {
            npm install
        }
    }
    finally {
        Pop-Location
    }
    Write-Host '  engines/cursor dependencies installed' -ForegroundColor Green
}

Write-Host 'Done. Installer build will include engines/cursor/node_modules and runtimes/node when present.'
