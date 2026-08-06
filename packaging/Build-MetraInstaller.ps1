<#
.SYNOPSIS
    Stages a clean Metra product tree and compiles MetraSetup-{version}.exe with Inno Setup.
.DESCRIPTION
    Reads ModuleVersion from scripts/Metra.psd1. Excludes user-state and local-only paths from the
    payload so upgrades replace product files without clobbering machine-local data.
    Requires Inno Setup 6 (ISCC.exe). If missing: winget install -e --id JRSoftware.InnoSetup
#>
[CmdletBinding()]
param(
    [string]$MetraRoot,
    [string]$OutDir,
    [switch]$SkipCompile,
    [switch]$KeepStage
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
    $MetraRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
else {
    $MetraRoot = (Resolve-Path -LiteralPath $MetraRoot).Path
}

$packagingRoot = Join-Path $MetraRoot 'packaging'
$stageRoot = Join-Path $packagingRoot 'stage'
$issPath = Join-Path $packagingRoot 'inno\Metra.iss'
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $packagingRoot 'out'
}

$manifestPath = Join-Path $MetraRoot 'scripts\Metra.psd1'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Missing module manifest: $manifestPath"
}
$manifest = Import-PowerShellDataFile -Path $manifestPath
$version = [string]$manifest.ModuleVersion
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "ModuleVersion missing in $manifestPath"
}

function Find-MetraIscc {
    $localPrograms = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
    $candidates = @(
        ${env:METRA_ISCC},
        $localPrograms,
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )
    $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $candidates += $cmd.Source
    }

    foreach ($c in @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (Test-Path -LiteralPath $c) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    return $null
}

# Directory / file name segments to skip anywhere under the tree.
$excludeDirNames = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('.git', 'packaging', 'node_modules', '__pycache__', '.vs'),
    [StringComparer]::OrdinalIgnoreCase
)

# Exact relative paths (forward or backslash normalized later) never staged.
$excludeRelativeExact = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
    'metra.config.json',
    'meta.config.json',
    'projects.local.json',
    'docs/decision-registry.json',
    'docs/operator-contract.json',
    'docs/context-pack.md',
    'docs/context-pack.json',
    'docs/canvas-snapshot.json',
    'docs/ops-preferences.local.json',
    'docs/ops-ask-log.local.json',
    'docs/ops-capture.local.json',
    '.cursor/mcp.json'
) | ForEach-Object { [void]$excludeRelativeExact.Add(($_ -replace '/', '\')) }

function Test-MetraStageExcluded {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $full = $Item.FullName
    $rel = $full.Substring($RootPath.Length).TrimStart('\', '/')

    foreach ($segment in ($rel -split '[\\/]')) {
        if ($excludeDirNames.Contains($segment)) {
            return $true
        }
    }

    if ($Item -is [System.IO.FileInfo]) {
        $name = $Item.Name
        if ($name -like '*.local.md' -and $rel.StartsWith('docs\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        if ($name -like '*.local.mdc' -and $rel.StartsWith('.cursor\rules\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        if ($name -like '*.code-workspace') {
            return $true
        }
        if ($excludeRelativeExact.Contains($rel)) {
            return $true
        }
    }

    return $false
}

Write-Host "Metra installer build" -ForegroundColor Cyan
Write-Host ("  Root:    {0}" -f $MetraRoot)
Write-Host ("  Version: {0}" -f $version)
Write-Host ("  Stage:   {0}" -f $stageRoot)
Write-Host ("  Out:     {0}" -f $OutDir)

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$copied = 0
$skipped = 0
Get-ChildItem -LiteralPath $MetraRoot -Force | ForEach-Object {
    $top = $_
    if ($excludeDirNames.Contains($top.Name)) {
        $skipped++
        return
    }
    if ($top -is [System.IO.FileInfo] -and (Test-MetraStageExcluded -Item $top -RootPath $MetraRoot)) {
        $skipped++
        return
    }

    if ($top -is [System.IO.DirectoryInfo]) {
        Get-ChildItem -LiteralPath $top.FullName -Recurse -Force | ForEach-Object {
            if (Test-MetraStageExcluded -Item $_ -RootPath $MetraRoot) {
                $skipped++
                return
            }
            if ($_ -is [System.IO.DirectoryInfo]) {
                return
            }
            $rel = $_.FullName.Substring($MetraRoot.Length).TrimStart('\', '/')
            $dest = Join-Path $stageRoot $rel
            $destDir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
            $copied++
        }
    }
    else {
        $dest = Join-Path $stageRoot $top.Name
        Copy-Item -LiteralPath $top.FullName -Destination $dest -Force
        $copied++
    }
}

# Ensure required bootstrap entry points exist in the stage.
foreach ($required in @(
        'Metra-Setup.cmd'
        'Metra-Ops.cmd'
        'Metra-Ops-Console.cmd'
        'metra.ps1'
        'scripts\bootstrap\Start-MetraSetup.ps1'
        'scripts\bootstrap\Start-MetraOps.ps1'
        'scripts\bootstrap\Start-MetraOpsHost.ps1'
        'scripts\Metra.psd1'
        'docs\assets\metra.ico'
    )) {
    $p = Join-Path $stageRoot $required
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Staged payload missing required file: $required"
    }
}

Write-Host ("  Copied:  {0} file(s); skipped entries: {1}" -f $copied, $skipped)

if ($SkipCompile) {
    Write-Host 'SkipCompile set - stage ready, ISCC not invoked.' -ForegroundColor Yellow
    return [PSCustomObject]@{
        Version   = $version
        StageRoot = $stageRoot
        OutDir    = $OutDir
        ExePath   = $null
        SkippedCompile = $true
    }
}

$iscc = Find-MetraIscc
if (-not $iscc) {
    throw @"
ISCC.exe not found. Install Inno Setup 6, then re-run:
  winget install -e --id JRSoftware.InnoSetup
Or set METRA_ISCC to the full path of ISCC.exe.
"@
}

Write-Host ("  ISCC:    {0}" -f $iscc)
$argList = @(
    "/DMyAppVersion=$version",
    "`"$issPath`""
)
$p = Start-Process -FilePath $iscc -ArgumentList $argList -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) {
    throw "ISCC failed with exit code $($p.ExitCode)"
}

$exeName = "MetraSetup-$version.exe"
$exePath = Join-Path $OutDir $exeName
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Expected output missing: $exePath"
}

# Convenience copy without version for Releases funnel docs.
$latest = Join-Path $OutDir 'MetraSetup.exe'
Copy-Item -LiteralPath $exePath -Destination $latest -Force

if (-not $KeepStage -and (Test-Path -LiteralPath $stageRoot)) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}

Write-Host ("Built: {0}" -f $exePath) -ForegroundColor Green
Write-Host ("Also:  {0}" -f $latest) -ForegroundColor Green

return [PSCustomObject]@{
    Version        = $version
    StageRoot      = $(if ($KeepStage) { $stageRoot } else { $null })
    OutDir         = $OutDir
    ExePath        = $exePath
    LatestPath     = $latest
    SkippedCompile = $false
}
