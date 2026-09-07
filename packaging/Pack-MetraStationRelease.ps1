<#
.SYNOPSIS
    Packs a Metra Station release zip + SHA-256 sidecar for GitHub Releases.
.DESCRIPTION
    Stages a clean station tree (no .git, no *.local.json secrets, no data dumps),
    requires root station.package.json, emits {Label}-{version}.zip and matching .sha256.
    Stage directory is always under %TEMP% so OutDir inside the station tree cannot recurse.
.EXAMPLE
    .\packaging\Pack-MetraStationRelease.ps1 -StationRoot C:\Projects\TicketTracker -OutDir .\packaging\out
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StationRoot,
    [string]$OutDir,
    [string]$Label,
    [string[]]$ExcludeDirNames = @('.git', 'node_modules', '__pycache__', '.vs', '.venv', 'bin', 'obj', 'build'),
    [string[]]$ExcludeRelativeExact = @(),
    [switch]$KeepStage
)

$ErrorActionPreference = 'Stop'

$StationRoot = (Resolve-Path -LiteralPath $StationRoot).Path
$descriptorPath = Join-Path $StationRoot 'station.package.json'
if (-not (Test-Path -LiteralPath $descriptorPath)) {
    throw "Missing station.package.json at $descriptorPath"
}

$descriptor = Get-Content -LiteralPath $descriptorPath -Raw -Encoding UTF8 | ConvertFrom-Json
$id = [string]$descriptor.id
$version = [string]$descriptor.version
if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($version)) {
    throw 'station.package.json must include id and version.'
}
if ($id -notmatch '^[a-z0-9][a-z0-9-]*$') {
    throw "Invalid station id '$id' (expected lowercase slug)."
}

if ([string]::IsNullOrWhiteSpace($Label)) {
    if ($id -eq 'tickettracker') { $Label = 'TicketTracker' }
    elseif ($id -eq 'codex') { $Label = 'Codex' }
    else { $Label = $id }
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $StationRoot 'build\out'
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    [void][System.IO.Directory]::CreateDirectory($OutDir)
}
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

$stageRoot = Join-Path $env:TEMP ("metra-station-stage-{0}-{1}" -f $id, ([guid]::NewGuid().ToString('n').Substring(0, 8)))
if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
[void][System.IO.Directory]::CreateDirectory($stageRoot)

$excludeDirs = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]$ExcludeDirNames,
    [StringComparer]::OrdinalIgnoreCase
)
# Always exclude build to avoid packing OutDir into itself.
[void]$excludeDirs.Add('build')
[void]$excludeDirs.Add('.git')

$excludeExact = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($rel in @($ExcludeRelativeExact)) {
    if (-not [string]::IsNullOrWhiteSpace($rel)) {
        [void]$excludeExact.Add(($rel -replace '/', '\').Trim('\', '/'))
    }
}

function Test-StationPackSkip {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][bool]$IsDirectory,
        [Parameter(Mandatory)][string]$Name
    )

    foreach ($segment in ($RelativePath -split '[\\/]')) {
        if ($excludeDirs.Contains($segment)) { return $true }
    }
    if ($excludeExact.Contains(($RelativePath -replace '/', '\'))) { return $true }
    if (-not $IsDirectory) {
        if ($Name -like '*.local.json') { return $true }
        if ($Name -like '*.local.mdc') { return $true }
        if ($Name -eq '.env' -or $Name -like '.env.*') { return $true }
        if ($Name -like '*.key' -or $Name -like '*.pem') { return $true }
        if ($Name -like '*.pfx' -or $Name -like '*.p12' -or $Name -like '*.cer' -or $Name -like '*.crt') { return $true }
        if ($Name -like '*.kdbx' -or $Name -like '*.secret' -or $Name -like 'id_rsa*') { return $true }
        if ($Name -like '*.db' -or $Name -like '*.sqlite') { return $true }
        if ($Name -eq 'station.version' -or $Name -eq 'station.install.json') { return $true }
    }
    return $false
}

try {
    $rootLen = $StationRoot.Length
    Get-ChildItem -LiteralPath $StationRoot -Recurse -Force | ForEach-Object {
        $rel = $_.FullName.Substring($rootLen).TrimStart('\', '/')
        if ([string]::IsNullOrWhiteSpace($rel)) { return }
        if (Test-StationPackSkip -RelativePath $rel -IsDirectory:$_.PSIsContainer -Name $_.Name) { return }
        $dest = Join-Path $stageRoot $rel
        if ($_.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $dest)) {
                [void][System.IO.Directory]::CreateDirectory($dest)
            }
        }
        else {
            $parent = Split-Path -Parent $dest
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                [void][System.IO.Directory]::CreateDirectory($parent)
            }
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        }
    }

    $stagedDescriptor = Join-Path $stageRoot 'station.package.json'
    if (-not (Test-Path -LiteralPath $stagedDescriptor)) {
        throw 'Staging lost station.package.json.'
    }
    if (Test-Path -LiteralPath (Join-Path $stageRoot '.git')) {
        throw 'Refusing to pack: .git present in stage.'
    }

    $zipName = '{0}-{1}.zip' -f $Label, $version
    if ($zipName -notmatch ('(?i)^{0}-{1}\.zip$' -f [regex]::Escape($Label), [regex]::Escape($version))) {
        throw "Internal pack error: zip name '$zipName' does not agree with label '$Label' and version '$version'."
    }
    $zipPath = Join-Path $OutDir $zipName
    $shaPath = "$zipPath.sha256"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    if (Test-Path -LiteralPath $shaPath) { Remove-Item -LiteralPath $shaPath -Force }

    # Compress-Archive with '*' omits top-level dotfiles on Windows PowerShell 5.1.
    # Stage under %TEMP% so excluding 'build' never touches OutDir mid-pack.
    $archiveItems = @(Get-ChildItem -LiteralPath $stageRoot -Force | ForEach-Object { $_.FullName })
    if ($archiveItems.Count -eq 0) {
        throw 'Staging produced an empty tree.'
    }
    Compress-Archive -Path $archiveItems -DestinationPath $zipPath -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sidecar = "{0}  {1}`r`n" -f $hash, $zipName
    [System.IO.File]::WriteAllText($shaPath, $sidecar, [System.Text.UTF8Encoding]::new($false))

    [PSCustomObject]@{
        ok         = $true
        id         = $id
        version    = $version
        label      = $Label
        zipPath    = $zipPath
        sha256Path = $shaPath
        sha256     = $hash
    }
}
finally {
    if (-not $KeepStage -and (Test-Path -LiteralPath $stageRoot)) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
