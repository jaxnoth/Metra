# Porter - transport Metra Cursor Project pack (Cursor Project continuity)
#
# Writes:
# - <MetraRoot>\porter\manifest.json
# - <MetraRoot>\porter\OPEN-PLANS.md
# - <MetraRoot>\porter\plans\<cursorLeaf> (index cursorLeaf or Approved Cursor-discovered)
# - %LOCALAPPDATA%\Metra\porter\ (mirror stamp)
#
# Sources: plans/index.yaml (in-scope) + Approved Cursor leaves not already indexed.

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

function Get-MetraPorterNormalizeStem {
    <#
    .SYNOPSIS
        Leaf/title -> stem. Parity with Yarn Get-YarnPlanBoardInventoryNormalizeStem / Surveyor normalizePlanStem.
    #>
    param([string]$Text)
    $s = [string]$Text
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $s = $s.ToLowerInvariant().Trim()
    $s = $s -replace '\.plan\.md$', ''
    $s = $s -replace '_[0-9a-f]{8}$', ''
    $s = $s -replace '-[0-9a-f]{8}$', ''
    $s = $s -replace '[^a-z0-9]+', '-'
    $s = $s.Trim('-')
    return $s
}

function Get-MetraPorterPlanFrontmatterMap {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    try {
        $raw = [System.IO.File]::ReadAllText($Path)
    }
    catch {
        Write-Warning "Porter: could not read plan frontmatter from $Path ($($_.Exception.Message))"
        return @{}
    }
    if ($raw -notmatch '(?s)\A---\r?\n(.*?)\r?\n---') {
        return @{}
    }
    $map = @{}
    foreach ($line in ($Matches[1] -split "`r?`n")) {
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*:\s*(.*?)\s*$') {
            $map[$Matches[1]] = (Get-YamlScalar $Matches[2])
        }
    }
    return $map
}

function Test-MetraPorterYamlTruthy {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    switch ($Value.Trim().ToLowerInvariant()) {
        'true' { return $true }
        'yes' { return $true }
        '1' { return $true }
        default { return $false }
    }
}

function Test-MetraPorterPlanApproved {
    <#
    .SYNOPSIS
        Cursor-discovered leaves need Approved (or comparable affirmed terminal) before transport.
    .NOTES
        Affirmed when status is Approved (case-insensitive) OR approveForLoom is truthy.
        Index-driven rows do not use this gate (index implies intentional affiliation).
    #>
    param([Parameter(Mandatory)][string]$Path)
    $fm = Get-MetraPorterPlanFrontmatterMap -Path $Path
    $status = if ($fm.ContainsKey('status')) { [string]$fm['status'] } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($status) -and
        $status.Trim().Equals('Approved', [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $approve = if ($fm.ContainsKey('approveForLoom')) { [string]$fm['approveForLoom'] } else { '' }
    return (Test-MetraPorterYamlTruthy -Value $approve)
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
$cursorDiscovered = 0
$cursorSkippedNotApproved = 0
$cursorSkippedOutOfScope = 0
$keptLeaves = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$indexStems = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$rows = New-Object System.Collections.Generic.List[string]
[void]$rows.Add('# Metra-product plans (porter scope)')
[void]$rows.Add('')
[void]$rows.Add("Generated: $stampUtc")
[void]$rows.Add("Scope: porter/scope.json (Metra product only; $skipped index entries skipped)")
[void]$rows.Add('Sources: plans/index.yaml + Approved Cursor leaves under %USERPROFILE%\.cursor\plans (in-scope, not already indexed)')
[void]$rows.Add('')
[void]$rows.Add('| Stem | Authority | Cursor leaf | Repo path | Snapshot |')
[void]$rows.Add('|------|-----------|-------------|-----------|----------|')

foreach ($ie in $allEntries) {
    if (-not [string]::IsNullOrWhiteSpace([string]$ie.stem)) {
        [void]$indexStems.Add([string]$ie.stem)
    }
}

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

# Cursor-directory discovery: in-scope Approved leaves whose stem is not already indexed.
if (Test-Path -LiteralPath $cursorPlansDir) {
    Get-ChildItem -LiteralPath $cursorPlansDir -File -Filter '*.plan.md' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $safeLeaf = Resolve-MetraPorterCursorLeafName -CursorLeaf $_.Name
            if (-not $safeLeaf) {
                $unsafeLeaf++
                return
            }
            if ($keptLeaves.Contains($safeLeaf)) { return }

            $stem = Get-MetraPorterNormalizeStem -Text $safeLeaf
            if ([string]::IsNullOrWhiteSpace($stem)) { return }
            if ($indexStems.Contains($stem)) { return }

            if (-not (Test-MetraPorterStem -Stem $stem -IncludePrefixes $includePrefixes -ExcludePrefixes $excludePrefixes)) {
                $cursorSkippedOutOfScope++
                return
            }

            $src = $_.FullName
            if (-not (Test-MetraPorterPathUnderRoot -RootDirectory $cursorPlansDir -CandidatePath $src)) {
                $unsafeLeaf++
                return
            }

            if (-not (Test-MetraPorterPlanApproved -Path $src)) {
                $cursorSkippedNotApproved++
                return
            }

            $dest = Join-Path $plansOut $safeLeaf
            if (-not (Test-MetraPorterPathUnderRoot -RootDirectory $plansOut -CandidatePath $dest)) {
                $unsafeLeaf++
                return
            }

            if ($PSCmdlet.ShouldProcess($dest, "Copy Approved Cursor-discovered plan $safeLeaf")) {
                Copy-Item -LiteralPath $src -Destination $dest -Force
            }
            [void]$keptLeaves.Add($safeLeaf)
            $copied++
            $cursorDiscovered++
            [void]$rows.Add("| $stem | cursor | $safeLeaf | - | plans/$safeLeaf |")
        }
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
        cursorDiscovery = 'Approved in-scope Cursor leaves not already in index'
    }
    counts          = [ordered]@{
        indexEntries               = $allEntries.Count
        inScope                    = $entries.Count
        skippedOutOfScope          = $skipped
        cursorBodiesCopied         = $copied
        cursorDiscovered           = $cursorDiscovered
        cursorSkippedNotApproved   = $cursorSkippedNotApproved
        cursorSkippedOutOfScope    = $cursorSkippedOutOfScope
        orphanSnapshotsRemoved     = $removed
        repoAuthority              = $repoAuth
        missingCursorLeaf          = $missing
        unsafeCursorLeaf           = $unsafeLeaf
    }
    notes           = 'Generated by scripts/Invoke-MetraPorter.ps1. Metra-product filter via scope.json. Cursor discovery requires Approved (or approveForLoom). Do not hand-edit.'
}

$manifestPath = Join-Path $porterRoot 'manifest.json'
$openPlansPath = Join-Path $porterRoot 'OPEN-PLANS.md'
$mirrorManifest = Join-Path $localMirror 'manifest.json'
$mirrorReadme = Join-Path $localMirror 'README.md'

if (-not $PSCmdlet.ShouldProcess($manifestPath, 'Write Porter manifest and OPEN-PLANS')) {
    Write-Host "WhatIf: inScope=$($entries.Count) skipped=$skipped wouldCopy=$copied cursorDiscovered=$cursorDiscovered"
    return
}

($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $manifestPath -Encoding utf8
($rows -join "`n") + "`n" | Set-Content -LiteralPath $openPlansPath -Encoding utf8
Copy-Item -LiteralPath $manifestPath -Destination $mirrorManifest -Force
@(
    '# Metra Cursor Project local mirror (Porter)'
    ''
    "lastRefreshUtc: $stampUtc"
    "inScope: $($entries.Count) (skipped $skipped); cursorDiscovered: $cursorDiscovered"
    ''
    'Primary pack (repo working tree):'
    $porterRoot
    ''
    'Filter: porter/scope.json (Metra product only)'
    'Cursor discovery: Approved (or approveForLoom) in-scope leaves not in plans/index.yaml'
    ''
    'Regenerate: pwsh -File <MetraRoot>\scripts\Invoke-MetraPorter.ps1'
    'Also runs on MetraYarnLoomPulse after Scout.'
) -join "`n" | Set-Content -LiteralPath $mirrorReadme -Encoding utf8

Write-Host "Porter refreshed: inScope=$($entries.Count) skipped=$skipped copied=$copied cursorDiscovered=$cursorDiscovered notApproved=$cursorSkippedNotApproved removedOrphans=$removed missingLeaf=$missing"
Write-Host "  $manifestPath"
Write-Host "  $openPlansPath"
Write-Host "  mirror: $localMirror"
