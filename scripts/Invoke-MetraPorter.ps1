# Porter - transport Metra Cursor Project pack (Cursor Project continuity)

# Writes:
# - <MetraRoot>\porter\manifest.json
# - <MetraRoot>\porter\OPEN-PLANS.md
# - <MetraRoot>\porter\plans\<cursorLeaf> (when present)
# - %LOCALAPPDATA%\Metra\porter\ (mirror stamp)

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-YamlIndexEntries {
    param([string]$IndexPath)
    if (-not (Test-Path -LiteralPath $IndexPath)) {
        return @()
    }
    $raw = Get-Content -LiteralPath $IndexPath -Raw
    $entries = @()
    $current = $null
    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -match '^\s*-\s+stem:\s*(.+)\s*$') {
            if ($null -ne $current) { $entries += $current }
            $current = [ordered]@{
                stem        = (Get-YamlScalar $Matches[1])
                cursorLeaf  = $null
                authority   = $null
                repoPath    = $null
                updatedAt   = $null
            }
            continue
        }
        if ($null -eq $current) { continue }
        if ($line -match '^\s+cursorLeaf:\s*(.+)\s*$') {
            $v = Get-YamlScalar $Matches[1]
            if ($v -eq 'null' -or [string]::IsNullOrWhiteSpace($v)) { $current.cursorLeaf = $null }
            else { $current.cursorLeaf = $v }
        }
        elseif ($line -match '^\s+authority:\s*(.+)\s*$') {
            $current.authority = Get-YamlScalar $Matches[1]
        }
        elseif ($line -match '^\s+repoPath:\s*(.+)\s*$') {
            $v = Get-YamlScalar $Matches[1]
            if ($v -eq 'null') { $current.repoPath = $null } else { $current.repoPath = $v }
        }
        elseif ($line -match '^\s+updatedAt:\s*(.+)\s*$') {
            $current.updatedAt = Get-YamlScalar $Matches[1]
        }
    }
    if ($null -ne $current) { $entries += $current }
    return $entries
}

function Get-YamlScalar {
    param([string]$Raw)
    $v = $Raw.Trim()
    if (($v.StartsWith("'") -and $v.EndsWith("'")) -or ($v.StartsWith('"') -and $v.EndsWith('"'))) {
        if ($v.Length -ge 2) { $v = $v.Substring(1, $v.Length - 2) }
    }
    return $v
}

function Test-MetraPorterStem {
    param(
        [string]$Stem,
        [string[]]$IncludePrefixes,
        [string[]]$ExcludePrefixes
    )
    if ([string]::IsNullOrWhiteSpace($Stem)) { return $false }
    $s = $Stem.ToLowerInvariant()
    foreach ($ex in $ExcludePrefixes) {
        if ([string]::IsNullOrWhiteSpace($ex)) { continue }
        if ($s.StartsWith($ex.ToLowerInvariant())) { return $false }
    }
    foreach ($inc in $IncludePrefixes) {
        if ([string]::IsNullOrWhiteSpace($inc)) { continue }
        if ($s.StartsWith($inc.ToLowerInvariant())) { return $true }
    }
    return $false
}

function Resolve-MetraPorterCursorLeafName {
    param([string]$CursorLeaf)
    if ([string]::IsNullOrWhiteSpace($CursorLeaf)) { return $null }
    $raw = $CursorLeaf.Trim()
    # Reject any path-shaped leaf (separators, volume, parent segments) before join.
    if ($raw.IndexOfAny([char[]]@('\', '/', ':')) -ge 0) { return $null }
    if ($raw -eq '.' -or $raw -eq '..') { return $null }
    $name = [System.IO.Path]::GetFileName($raw)
    if ([string]::IsNullOrWhiteSpace($name) -or -not [string]::Equals($name, $raw, [StringComparison]::Ordinal)) {
        return $null
    }
    return $name
}

function Test-MetraPorterPathUnderRoot {
    param(
        [Parameter(Mandatory)][string]$RootDirectory,
        [Parameter(Mandatory)][string]$CandidatePath
    )
    $rootFull = [System.IO.Path]::GetFullPath($RootDirectory).TrimEnd('\', '/')
    $candidateFull = [System.IO.Path]::GetFullPath($CandidatePath)
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    return $candidateFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

$porterRoot = Join-Path $MetraRoot 'porter'
$plansOut = Join-Path $porterRoot 'plans'
$indexPath = Join-Path $MetraRoot 'plans\index.yaml'
$scopePath = Join-Path $porterRoot 'scope.json'
$cursorPlansDir = Join-Path $env:USERPROFILE '.cursor\plans'
$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $localAppData = Join-Path $env:USERPROFILE 'AppData\Local'
}
$localMirror = Join-Path $localAppData 'Metra\porter'
$stampUtc = [datetime]::UtcNow.ToString('o')

if (-not (Test-Path -LiteralPath $porterRoot)) {
    throw "porter missing under $MetraRoot - create the pack folder first."
}
if (-not (Test-Path -LiteralPath $scopePath)) {
    throw "porter/scope.json missing - Metra-product filter is required."
}

$scope = Get-Content -LiteralPath $scopePath -Raw | ConvertFrom-Json
$includePrefixes = @($scope.includeStemPrefixes)
$excludePrefixes = @($scope.excludeStemPrefixes)

if ($PSCmdlet.ShouldProcess($plansOut, 'Ensure Porter pack directories')) {
    New-Item -ItemType Directory -Force -Path $plansOut | Out-Null
    New-Item -ItemType Directory -Force -Path $localMirror | Out-Null
}

$allEntries = @(Get-YamlIndexEntries -IndexPath $indexPath)
$entries = @($allEntries | Where-Object {
        Test-MetraPorterStem -Stem $_.stem -IncludePrefixes $includePrefixes -ExcludePrefixes $excludePrefixes
    })
$skipped = $allEntries.Count - $entries.Count

$copied = 0
$repoAuth = 0
$missing = 0
$unsafeLeaf = 0
$keptLeaves = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$rows = New-Object System.Collections.Generic.List[string]
[void]$rows.Add('# Metra-product plans (porter scope)')
[void]$rows.Add('')
[void]$rows.Add("Generated: $stampUtc")
[void]$rows.Add("Scope: porter/scope.json (Metra product only; $skipped index entries skipped)")
[void]$rows.Add('')
[void]$rows.Add('| Stem | Authority | Cursor leaf | Repo path | Snapshot |')
[void]$rows.Add('|------|-----------|-------------|-----------|----------|')

foreach ($e in $entries) {
    $snap = '-'
    if ($e.authority -eq 'repo') { $repoAuth++ }
    if ($e.cursorLeaf) {
        $safeLeaf = Resolve-MetraPorterCursorLeafName -CursorLeaf $e.cursorLeaf
        if (-not $safeLeaf) {
            $unsafeLeaf++
            $snap = 'unsafe-cursor-leaf'
        }
        else {
            $src = Join-Path $cursorPlansDir $safeLeaf
            $dest = Join-Path $plansOut $safeLeaf
            if (-not (Test-MetraPorterPathUnderRoot -RootDirectory $cursorPlansDir -CandidatePath $src) -or
                -not (Test-MetraPorterPathUnderRoot -RootDirectory $plansOut -CandidatePath $dest)) {
                $unsafeLeaf++
                $snap = 'unsafe-cursor-leaf'
            }
            elseif (Test-Path -LiteralPath $src) {
                if ($PSCmdlet.ShouldProcess($dest, "Copy Cursor plan $safeLeaf")) {
                    Copy-Item -LiteralPath $src -Destination $dest -Force
                }
                [void]$keptLeaves.Add($safeLeaf)
                $copied++
                $snap = "plans/$safeLeaf"
            }
            else {
                $missing++
                $snap = 'missing-cursor-leaf'
            }
        }
    }
    $repoCol = if ($e.repoPath) { "plans/$($e.repoPath)" } else { '-' }
    $leafCol = if ($e.cursorLeaf) { $e.cursorLeaf } else { '-' }
    [void]$rows.Add("| $($e.stem) | $($e.authority) | $leafCol | $repoCol | $snap |")
}

$removed = 0
Get-ChildItem -LiteralPath $plansOut -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'README.md' -and -not $keptLeaves.Contains($_.Name) } |
    ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove out-of-scope Porter snapshot')) {
            Remove-Item -LiteralPath $_.FullName -Force
            $removed++
        }
    }

$manifest = [ordered]@{
    schemaVersion   = 1
    projectKey      = 'Metra'
    lastRefreshUtc  = $stampUtc
    scopePath       = 'porter/scope.json'
    source          = [ordered]@{
        metraRoot       = $MetraRoot
        cursorPlansDir  = $cursorPlansDir
        planIndex       = 'plans/index.yaml'
    }
    counts          = [ordered]@{
        indexEntries           = $allEntries.Count
        inScope                = $entries.Count
        skippedOutOfScope      = $skipped
        cursorBodiesCopied     = $copied
        orphanSnapshotsRemoved = $removed
        repoAuthority          = $repoAuth
        missingCursorLeaf      = $missing
        unsafeCursorLeaf       = $unsafeLeaf
    }
    notes           = 'Generated by scripts/Invoke-MetraPorter.ps1. Metra-product filter via scope.json. Do not hand-edit.'
}

$manifestPath = Join-Path $porterRoot 'manifest.json'
$openPlansPath = Join-Path $porterRoot 'OPEN-PLANS.md'
$mirrorManifest = Join-Path $localMirror 'manifest.json'
$mirrorReadme = Join-Path $localMirror 'README.md'

if (-not $PSCmdlet.ShouldProcess($manifestPath, 'Write Porter manifest and OPEN-PLANS')) {
    Write-Host "WhatIf: inScope=$($entries.Count) skipped=$skipped wouldCopy=$copied"
    return
}

($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $manifestPath -Encoding utf8
($rows -join "`n") + "`n" | Set-Content -LiteralPath $openPlansPath -Encoding utf8
Copy-Item -LiteralPath $manifestPath -Destination $mirrorManifest -Force
@(
    '# Metra Cursor Project local mirror (Porter)'
    ''
    "lastRefreshUtc: $stampUtc"
    "inScope: $($entries.Count) (skipped $skipped)"
    ''
    'Primary pack (repo working tree):'
    $porterRoot
    ''
    'Filter: porter/scope.json (Metra product only)'
    ''
    'Regenerate: pwsh -File <MetraRoot>\scripts\Invoke-MetraPorter.ps1'
    'Also runs on MetraYarnLoomPulse after Scout.'
) -join "`n" | Set-Content -LiteralPath $mirrorReadme -Encoding utf8

Write-Host "Porter refreshed: inScope=$($entries.Count) skipped=$skipped copied=$copied removedOrphans=$removed missingLeaf=$missing"
Write-Host "  $manifestPath"
Write-Host "  $openPlansPath"
Write-Host "  mirror: $localMirror"
