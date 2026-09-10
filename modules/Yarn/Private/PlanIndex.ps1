# Plan index (plans/index.yaml) - schemaVersion 1.
# Affiliation metadata only; Surveyor must not rewrite these files.

Set-StrictMode -Version Latest

function Get-MetraPlanIndexSchemaVersion {
    return 1
}

function Get-MetraPlanIndexPath {
    param(
        [Parameter(Mandatory)][string]$PlansDir
    )
    return [System.IO.Path]::GetFullPath((Join-Path $PlansDir 'index.yaml'))
}

function ConvertTo-MetraPlanIndexYamlScalar {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return 'null' }
    $s = [string]$Value
    if ($s -eq '') { return '""' }
    if ($s -match '[:#\[\]\{\},"''>|*&!%@`]|^\s|\s$') {
        $escaped = $s.Replace("'", "''")
        return "'$escaped'"
    }
    return $s
}

function ConvertTo-MetraPlanIndexYaml {
    param(
        [Parameter(Mandatory)]$Document
    )
    $schema = [int](Get-YarnProp -Object $Document -Name 'schemaVersion' -Default (Get-MetraPlanIndexSchemaVersion))
    $project = [string](Get-YarnProp -Object $Document -Name 'project' -Default 'Metra')
    $plans = @(Get-YarnProp -Object $Document -Name 'plans' -Default @())
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("schemaVersion: $schema")
    [void]$sb.AppendLine("project: $(ConvertTo-MetraPlanIndexYamlScalar $project)")
    [void]$sb.AppendLine('plans:')
    if ($plans.Count -eq 0) {
        [void]$sb.AppendLine('  []')
    }
    else {
        foreach ($p in $plans) {
            $stem = [string](Get-YarnProp -Object $p -Name 'stem' -Default '')
            $leaf = Get-YarnProp -Object $p -Name 'cursorLeaf' -Default $null
            $auth = [string](Get-YarnProp -Object $p -Name 'authority' -Default '')
            $repo = Get-YarnProp -Object $p -Name 'repoPath' -Default $null
            $updated = [string](Get-YarnProp -Object $p -Name 'updatedAt' -Default '')
            [void]$sb.AppendLine("  - stem: $(ConvertTo-MetraPlanIndexYamlScalar $stem)")
            if ($null -eq $leaf -or [string]::IsNullOrWhiteSpace([string]$leaf)) {
                [void]$sb.AppendLine('    cursorLeaf: null')
            }
            else {
                [void]$sb.AppendLine("    cursorLeaf: $(ConvertTo-MetraPlanIndexYamlScalar ([string]$leaf))")
            }
            [void]$sb.AppendLine("    authority: $(ConvertTo-MetraPlanIndexYamlScalar $auth)")
            if ($null -eq $repo -or [string]::IsNullOrWhiteSpace([string]$repo)) {
                [void]$sb.AppendLine('    repoPath: null')
            }
            else {
                [void]$sb.AppendLine("    repoPath: $(ConvertTo-MetraPlanIndexYamlScalar ([string]$repo))")
            }
            [void]$sb.AppendLine("    updatedAt: $(ConvertTo-MetraPlanIndexYamlScalar $updated)")
        }
    }
    return ($sb.ToString().TrimEnd() + "`n")
}

function ConvertFrom-MetraPlanIndexYamlScalar {
    param([string]$Raw)
    $t = ([string]$Raw).Trim()
    if ($t -eq 'null' -or $t -eq '~' -or $t -eq '') { return $null }
    if ($t.Length -ge 2) {
        $q = $t[0]
        if (($q -eq '"' -or $q -eq "'") -and $t[-1] -eq $q) {
            $inner = $t.Substring(1, $t.Length - 2)
            if ($q -eq "'") { return $inner.Replace("''", "'") }
            return $inner.Replace('\"', '"')
        }
    }
    return $t
}

function Assert-MetraPlanIndexDocument {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$PlansDir
    )
    $errors = New-Object System.Collections.Generic.List[string]
    $schema = Get-YarnProp -Object $Document -Name 'schemaVersion' -Default $null
    if ($null -eq $schema -or [int]$schema -ne (Get-MetraPlanIndexSchemaVersion)) {
        [void]$errors.Add("schemaVersion must be $(Get-MetraPlanIndexSchemaVersion)")
    }
    $project = [string](Get-YarnProp -Object $Document -Name 'project' -Default '')
    if ([string]::IsNullOrWhiteSpace($project)) {
        [void]$errors.Add('project is required')
    }
    $plans = @(Get-YarnProp -Object $Document -Name 'plans' -Default @())
    $seen = @{}
    $plansDirFull = [System.IO.Path]::GetFullPath($PlansDir)
    foreach ($p in $plans) {
        $stemRaw = [string](Get-YarnProp -Object $p -Name 'stem' -Default '')
        $stem = Get-YarnPlanBoardInventoryNormalizeStem -Text $stemRaw
        if ([string]::IsNullOrWhiteSpace($stem)) {
            [void]$errors.Add('plans[].stem is required')
            continue
        }
        if ($stem -ne $stemRaw.Trim()) {
            # allow already-normalized stems only; writers normalize before write
        }
        if ($seen.ContainsKey($stem)) {
            [void]$errors.Add("duplicate stem: $stem")
        }
        else {
            $seen[$stem] = $true
        }
        $auth = [string](Get-YarnProp -Object $p -Name 'authority' -Default '')
        if ($auth -ne 'repo' -and $auth -ne 'cursor') {
            [void]$errors.Add("stem ${stem}: authority must be repo|cursor")
        }
        $leaf = Get-YarnProp -Object $p -Name 'cursorLeaf' -Default $null
        if ($null -ne $leaf -and -not [string]::IsNullOrWhiteSpace([string]$leaf)) {
            $leafStr = [string]$leaf
            if ($leafStr -match '[\\/]' -or $leafStr -match '\.\.') {
                [void]$errors.Add("stem ${stem}: cursorLeaf must be a leaf filename")
            }
            elseif (-not $leafStr.ToLowerInvariant().EndsWith('.plan.md')) {
                [void]$errors.Add("stem ${stem}: cursorLeaf must end with .plan.md")
            }
        }
        $repo = Get-YarnProp -Object $p -Name 'repoPath' -Default $null
        if ($auth -eq 'repo') {
            if ($null -eq $repo -or [string]::IsNullOrWhiteSpace([string]$repo)) {
                [void]$errors.Add("stem ${stem}: repoPath required when authority is repo")
            }
        }
        if ($null -ne $repo -and -not [string]::IsNullOrWhiteSpace([string]$repo)) {
            $repoStr = [string]$repo
            if ([System.IO.Path]::IsPathRooted($repoStr) -or $repoStr -match '\.\.') {
                [void]$errors.Add("stem ${stem}: repoPath must be relative without traversal")
            }
            else {
                $combined = [System.IO.Path]::GetFullPath((Join-Path $plansDirFull $repoStr))
                $prefix = $plansDirFull.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
                if (-not $combined.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -and
                    -not [string]::Equals($combined, $plansDirFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$errors.Add("stem ${stem}: repoPath escapes plans directory")
                }
            }
        }
        $updated = [string](Get-YarnProp -Object $p -Name 'updatedAt' -Default '')
        if ([string]::IsNullOrWhiteSpace($updated)) {
            [void]$errors.Add("stem ${stem}: updatedAt is required")
        }
    }
    if ($errors.Count -gt 0) {
        throw ("Plan index invalid: " + ($errors -join '; '))
    }
}

function ConvertFrom-MetraPlanIndexYaml {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$PlansDir
    )
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw 'Plan index empty'
    }
    $schema = $null
    $project = $null
    if ($Text -match '(?m)^schemaVersion:\s*(.+)$') {
        $schema = [int](ConvertFrom-MetraPlanIndexYamlScalar $Matches[1])
    }
    if ($Text -match '(?m)^project:\s*(.+)$') {
        $project = [string](ConvertFrom-MetraPlanIndexYamlScalar $Matches[1])
    }
    $plans = @()
    if ($Text -match '(?ms)^plans:\s*\r?\n\s*\[\]\s*$') {
        # empty list
    }
    else {
        $entryMatches = [regex]::Matches(
            $Text,
            '(?m)^  - stem:\s*(.+)\r?\n((?:    [^\r\n]+\r?\n?)*)'
        )
        foreach ($m in $entryMatches) {
            $stem = [string](ConvertFrom-MetraPlanIndexYamlScalar $m.Groups[1].Value)
            $block = $m.Groups[2].Value
            $leaf = $null
            $auth = $null
            $repo = $null
            $updated = $null
            if ($block -match '(?m)^    cursorLeaf:\s*(.+)$') {
                $leaf = ConvertFrom-MetraPlanIndexYamlScalar $Matches[1]
            }
            if ($block -match '(?m)^    authority:\s*(.+)$') {
                $auth = [string](ConvertFrom-MetraPlanIndexYamlScalar $Matches[1])
            }
            if ($block -match '(?m)^    repoPath:\s*(.+)$') {
                $repo = ConvertFrom-MetraPlanIndexYamlScalar $Matches[1]
            }
            if ($block -match '(?m)^    updatedAt:\s*(.+)$') {
                $updated = [string](ConvertFrom-MetraPlanIndexYamlScalar $Matches[1])
            }
            $plans += [PSCustomObject]@{
                stem       = Get-YarnPlanBoardInventoryNormalizeStem -Text $stem
                cursorLeaf = $leaf
                authority  = $auth
                repoPath   = $repo
                updatedAt  = $updated
            }
        }
    }
    if ($null -eq $schema) {
        throw 'Plan index missing schemaVersion'
    }
    $doc = [PSCustomObject]@{
        schemaVersion = [int]$schema
        project       = [string]$project
        plans         = @($plans)
    }
    Assert-MetraPlanIndexDocument -Document $doc -PlansDir $PlansDir
    return $doc
}

function Read-MetraPlanIndex {
    <#
    .SYNOPSIS
        Read and validate plans/index.yaml (schemaVersion 1). Fail closed on malformed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlansDir
    )
    $path = Get-MetraPlanIndexPath -PlansDir $PlansDir
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    $raw = [System.IO.File]::ReadAllText($path, (Get-YarnUtf8NoBomEncoding))
    return (ConvertFrom-MetraPlanIndexYaml -Text $raw -PlansDir $PlansDir)
}

function New-MetraPlanIndexDocument {
    param(
        [Parameter(Mandatory)][string]$Project
    )
    return [PSCustomObject]@{
        schemaVersion = Get-MetraPlanIndexSchemaVersion
        project       = $Project
        plans         = @()
    }
}

function Test-MetraPlanIndexEntryEqual {
    param($A, $B)
    if ($null -eq $A -or $null -eq $B) { return $false }
    $fields = @('stem', 'cursorLeaf', 'authority', 'repoPath')
    foreach ($f in $fields) {
        $av = Get-YarnProp -Object $A -Name $f -Default $null
        $bv = Get-YarnProp -Object $B -Name $f -Default $null
        $as = if ($null -eq $av) { '' } else { [string]$av }
        $bs = if ($null -eq $bv) { '' } else { [string]$bv }
        if (-not [string]::Equals($as, $bs, [System.StringComparison]::Ordinal)) {
            return $false
        }
    }
    return $true
}

function Set-MetraPlanIndexEntry {
    <#
    .SYNOPSIS
        Atomic upsert of one plan-index entry by normalized stem.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlansDir,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Stem,
        [AllowNull()][string]$CursorLeaf,
        [Parameter(Mandatory)][ValidateSet('repo', 'cursor')][string]$Authority,
        [AllowNull()][string]$RepoPath,
        [string]$UpdatedAt = (Get-Date).ToUniversalTime().ToString('o'),
        [switch]$WhatIf
    )
    $normStem = Get-YarnPlanBoardInventoryNormalizeStem -Text $Stem
    if ([string]::IsNullOrWhiteSpace($normStem)) {
        throw 'Set-MetraPlanIndexEntry: stem required'
    }
    if ($Authority -eq 'repo' -and [string]::IsNullOrWhiteSpace($RepoPath)) {
        throw "Set-MetraPlanIndexEntry: repoPath required for authority repo ($normStem)"
    }
    if ($Authority -eq 'cursor') {
        $RepoPath = $null
    }
    if (-not [string]::IsNullOrWhiteSpace($CursorLeaf)) {
        if ($CursorLeaf -match '[\\/]' -or $CursorLeaf -match '\.\.') {
            throw "Set-MetraPlanIndexEntry: cursorLeaf must be a leaf filename"
        }
    }
    else {
        $CursorLeaf = $null
    }

    $path = Get-MetraPlanIndexPath -PlansDir $PlansDir
    $doc = $null
    if (Test-Path -LiteralPath $path) {
        $doc = Read-MetraPlanIndex -PlansDir $PlansDir
    }
    if ($null -eq $doc) {
        $doc = New-MetraPlanIndexDocument -Project $Project
    }
    elseif ([string](Get-YarnProp -Object $doc -Name 'project' -Default '') -ne $Project) {
        throw "Set-MetraPlanIndexEntry: index project '$((Get-YarnProp -Object $doc -Name 'project' -Default ''))' does not match '$Project'"
    }

    $entry = [PSCustomObject]@{
        stem       = $normStem
        cursorLeaf = $CursorLeaf
        authority  = $Authority
        repoPath   = $RepoPath
        updatedAt  = $UpdatedAt
    }
    $existing = @($doc.plans)
    $prior = $existing | Where-Object {
        (Get-YarnPlanBoardInventoryNormalizeStem -Text ([string](Get-YarnProp -Object $_ -Name 'stem' -Default ''))) -eq $normStem
    } | Select-Object -First 1
    if ($null -ne $prior -and (Test-MetraPlanIndexEntryEqual -A $prior -B $entry)) {
        return [PSCustomObject]@{
            outcome = 'unchanged'
            path    = $path
            entry   = $prior
        }
    }
    $rest = @($existing | Where-Object {
            (Get-YarnPlanBoardInventoryNormalizeStem -Text ([string](Get-YarnProp -Object $_ -Name 'stem' -Default ''))) -ne $normStem
        })
    $merged = @($rest + @($entry) | Sort-Object { [string]$_.stem })
    $doc = [PSCustomObject]@{
        schemaVersion = Get-MetraPlanIndexSchemaVersion
        project       = $Project
        plans         = $merged
    }
    Assert-MetraPlanIndexDocument -Document $doc -PlansDir $PlansDir
    $yaml = ConvertTo-MetraPlanIndexYaml -Document $doc
    if ($WhatIf) {
        return [PSCustomObject]@{
            outcome = 'what-if'
            path    = $path
            entry   = $entry
            yaml    = $yaml
        }
    }
    [void][System.IO.Directory]::CreateDirectory($PlansDir)
    Write-YarnAtomicUtf8Text -Path $path -Text $yaml
    return [PSCustomObject]@{
        outcome = if ($null -eq $prior) { 'created' } else { 'updated' }
        path    = $path
        entry   = $entry
    }
}

function Test-MetraPlanCursorLeafValid {
    param(
        [Parameter(Mandatory)][string]$CursorPlansDir,
        [Parameter(Mandatory)][string]$Stem,
        [AllowNull()][string]$CursorLeaf
    )
    if ([string]::IsNullOrWhiteSpace($CursorLeaf)) { return $false }
    if ($CursorLeaf -match '[\\/]' -or $CursorLeaf -match '\.\.') { return $false }
    if (-not $CursorLeaf.ToLowerInvariant().EndsWith('.plan.md')) { return $false }
    $full = [System.IO.Path]::GetFullPath((Join-Path $CursorPlansDir $CursorLeaf))
    $root = [System.IO.Path]::GetFullPath($CursorPlansDir).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    if (-not (Test-Path -LiteralPath $full)) { return $false }
    $fileStem = Get-YarnPlanBoardInventoryNormalizeStem -Text ([System.IO.Path]::GetFileName($full))
    return ($fileStem -eq $Stem)
}

function Find-MetraPlanCursorLeaf {
    <#
    .SYNOPSIS
        Resolve a Cursor leaf for a stem (validated cursorLeaf, then fallback search).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CursorPlansDir,
        [Parameter(Mandatory)][string]$Stem,
        [AllowNull()][string]$PreferredLeaf
    )
    $norm = Get-YarnPlanBoardInventoryNormalizeStem -Text $Stem
    if ([string]::IsNullOrWhiteSpace($norm)) {
        return [PSCustomObject]@{
            status = 'Missing'
            path   = $null
            leaf   = $null
            note   = 'empty-stem'
        }
    }
    if (Test-MetraPlanCursorLeafValid -CursorPlansDir $CursorPlansDir -Stem $norm -CursorLeaf $PreferredLeaf) {
        $path = [System.IO.Path]::GetFullPath((Join-Path $CursorPlansDir $PreferredLeaf))
        return [PSCustomObject]@{
            status = 'Resolved'
            path   = $path
            leaf   = [System.IO.Path]::GetFileName($path)
            note   = 'preferred-leaf'
        }
    }
    if (-not (Test-Path -LiteralPath $CursorPlansDir)) {
        return [PSCustomObject]@{
            status = 'Missing'
            path   = $null
            leaf   = $null
            note   = 'cursor-dir-missing'
        }
    }
    $files = @(Get-ChildItem -LiteralPath $CursorPlansDir -Filter '*.plan.md' -File -ErrorAction SilentlyContinue)
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($f in $files) {
        $fs = Get-YarnPlanBoardInventoryNormalizeStem -Text $f.Name
        if ($fs -eq $norm) {
            $candidates.Add($f) | Out-Null
        }
    }
    if ($candidates.Count -eq 0) {
        return [PSCustomObject]@{
            status = 'Missing'
            path   = $null
            leaf   = $null
            note   = 'no-match'
        }
    }
    $sorted = @(
        $candidates | Sort-Object @{ Expression = 'LastWriteTimeUtc'; Descending = $true }, @{ Expression = 'Name' }
    )
    $pick = $sorted[0]
    $status = if ($candidates.Count -gt 1) { 'AmbiguousSelected' } else { 'Resolved' }
    return [PSCustomObject]@{
        status = $status
        path   = $pick.FullName
        leaf   = $pick.Name
        note   = if ($candidates.Count -gt 1) { "candidates=$($candidates.Count)" } else { 'stem-match' }
    }
}

function Confirm-MetraPlanIndexSelectedCursorLeaf {
    <#
    .SYNOPSIS
        Persist a resolved Cursor leaf into the index when an entry already exists.
        Stabilizes AmbiguousSelected / stem-search picks so later reads use exact-leaf.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlansDir,
        [Parameter(Mandatory)][string]$Stem,
        [Parameter(Mandatory)][string]$Leaf,
        [Parameter(Mandatory)][string]$Status
    )
    if ($Status -notin @('Resolved', 'AmbiguousSelected')) { return }
    if ([string]::IsNullOrWhiteSpace($Leaf)) { return }
    if ($Leaf -match '[\\/]' -or $Leaf -match '\.\.') { return }
    $indexPath = Get-MetraPlanIndexPath -PlansDir $PlansDir
    if (-not (Test-Path -LiteralPath $indexPath)) { return }
    $doc = $null
    try { $doc = Read-MetraPlanIndex -PlansDir $PlansDir } catch { return }
    if ($null -eq $doc) { return }
    $norm = Get-YarnPlanBoardInventoryNormalizeStem -Text $Stem
    $entry = @($doc.plans) | Where-Object { [string]$_.stem -eq $norm } | Select-Object -First 1
    if ($null -eq $entry) { return }
    $priorLeaf = [string]$entry.cursorLeaf
    if (-not [string]::IsNullOrWhiteSpace($priorLeaf) -and
        [string]::Equals($priorLeaf, $Leaf, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    $project = [string](Get-YarnProp -Object $doc -Name 'project' -Default '')
    if ([string]::IsNullOrWhiteSpace($project)) { return }
    $auth = [string]$entry.authority
    if ($auth -notin @('repo', 'cursor')) { return }
    $repoPath = if ($auth -eq 'repo') { [string]$entry.repoPath } else { $null }
    try {
        [void](Set-MetraPlanIndexEntry -PlansDir $PlansDir -Project $project -Stem $norm `
                -CursorLeaf $Leaf -Authority $auth -RepoPath $repoPath)
    }
    catch {
        # Fail open on read-path persistence; callers still return the selected path.
    }
}

function Resolve-MetraPlanPath {
    <#
    .SYNOPSIS
        Honor authority: repo body or Cursor working body.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlansDir,
        [Parameter(Mandatory)][string]$Stem,
        [string]$CursorPlansDir = (Resolve-YarnCursorPlansDir)
    )
    $norm = Get-YarnPlanBoardInventoryNormalizeStem -Text $Stem
    $doc = Read-MetraPlanIndex -PlansDir $PlansDir
    if ($null -eq $doc) {
        return [PSCustomObject]@{
            status    = 'Missing'
            authority = $null
            path      = $null
            note      = 'no-index'
        }
    }
    $entry = @($doc.plans) | Where-Object { [string]$_.stem -eq $norm } | Select-Object -First 1
    if ($null -eq $entry) {
        return [PSCustomObject]@{
            status    = 'Missing'
            authority = $null
            path      = $null
            note      = 'stem-not-in-index'
        }
    }
    $auth = [string]$entry.authority
    if ($auth -eq 'repo') {
        $repoRel = [string]$entry.repoPath
        $full = [System.IO.Path]::GetFullPath((Join-Path $PlansDir $repoRel))
        if (-not (Test-Path -LiteralPath $full)) {
            return [PSCustomObject]@{
                status    = 'Missing'
                authority = 'repo'
                path      = $full
                note      = 'repo-body-missing'
            }
        }
        # Still pin a Cursor twin leaf when ambiguity was resolved for working-path use.
        $twin = Find-MetraPlanCursorLeaf -CursorPlansDir $CursorPlansDir -Stem $norm -PreferredLeaf ([string]$entry.cursorLeaf)
        if (($twin.status -eq 'Resolved' -or $twin.status -eq 'AmbiguousSelected') -and
            -not [string]::IsNullOrWhiteSpace([string]$twin.leaf)) {
            Confirm-MetraPlanIndexSelectedCursorLeaf -PlansDir $PlansDir -Stem $norm -Leaf ([string]$twin.leaf) -Status $twin.status
        }
        return [PSCustomObject]@{
            status    = 'Resolved'
            authority = 'repo'
            path      = $full
            note      = 'repo'
        }
    }
    $found = Find-MetraPlanCursorLeaf -CursorPlansDir $CursorPlansDir -Stem $norm -PreferredLeaf ([string]$entry.cursorLeaf)
    if (($found.status -eq 'Resolved' -or $found.status -eq 'AmbiguousSelected') -and
        -not [string]::IsNullOrWhiteSpace([string]$found.leaf)) {
        Confirm-MetraPlanIndexSelectedCursorLeaf -PlansDir $PlansDir -Stem $norm -Leaf ([string]$found.leaf) -Status $found.status
    }
    return [PSCustomObject]@{
        status    = $found.status
        authority = 'cursor'
        path      = $found.path
        note      = $found.note
        leaf      = $found.leaf
    }
}

function Resolve-MetraPlanWorkingPath {
    <#
    .SYNOPSIS
        Cursor working body only. Never returns a repo scar path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlansDir,
        [Parameter(Mandatory)][string]$Stem,
        [string]$CursorPlansDir = (Resolve-YarnCursorPlansDir)
    )
    $norm = Get-YarnPlanBoardInventoryNormalizeStem -Text $Stem
    $doc = $null
    try {
        $doc = Read-MetraPlanIndex -PlansDir $PlansDir
    }
    catch {
        $doc = $null
    }
    $preferred = $null
    if ($null -ne $doc) {
        $entry = @($doc.plans) | Where-Object { [string]$_.stem -eq $norm } | Select-Object -First 1
        if ($null -ne $entry) {
            if ([string]$entry.authority -eq 'repo' -and [string]::IsNullOrWhiteSpace([string]$entry.cursorLeaf)) {
                return [PSCustomObject]@{
                    status = 'Missing'
                    path   = $null
                    note   = 'repo-only-scar'
                }
            }
            $preferred = [string]$entry.cursorLeaf
        }
    }
    $found = Find-MetraPlanCursorLeaf -CursorPlansDir $CursorPlansDir -Stem $norm -PreferredLeaf $preferred
    if (($found.status -eq 'Resolved' -or $found.status -eq 'AmbiguousSelected') -and
        -not [string]::IsNullOrWhiteSpace([string]$found.leaf) -and
        $null -ne $doc) {
        Confirm-MetraPlanIndexSelectedCursorLeaf -PlansDir $PlansDir -Stem $norm -Leaf ([string]$found.leaf) -Status $found.status
    }
    return [PSCustomObject]@{
        status = $found.status
        path   = $found.path
        note   = $found.note
        leaf   = $found.leaf
    }
}

function Initialize-MetraPlanIndexSeed {
    <#
    .SYNOPSIS
        Seed plans/index.yaml from existing *.plan.md scars (authority: repo).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [string]$Project = 'Metra',
        [string]$CursorPlansDir = (Resolve-YarnCursorPlansDir),
        [switch]$WhatIf
    )
    $plansDir = Resolve-YarnProjectPlansPath -MetraRoot $MetraRoot -ProjectKey $Project
    $files = @(Get-ChildItem -LiteralPath $plansDir -Filter '*.plan.md' -File -ErrorAction SilentlyContinue)
    $collisions = New-Object System.Collections.Generic.List[string]
    $byStem = @{}
    foreach ($f in $files) {
        if ([string]::Equals($f.Name, 'index.yaml', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $stem = Get-YarnPlanBoardInventoryNormalizeStem -Text $f.Name
        if ([string]::IsNullOrWhiteSpace($stem)) { continue }
        if ($byStem.ContainsKey($stem)) {
            [void]$collisions.Add("stem ${stem}: $($byStem[$stem].Name) vs $($f.Name)")
            continue
        }
        $byStem[$stem] = $f
    }
    $results = @()
    foreach ($stem in @($byStem.Keys | Sort-Object)) {
        $f = $byStem[$stem]
        $twin = Find-MetraPlanCursorLeaf -CursorPlansDir $CursorPlansDir -Stem $stem -PreferredLeaf $null
        $leaf = $null
        if ($twin.status -eq 'Resolved' -or $twin.status -eq 'AmbiguousSelected') {
            $leaf = $twin.leaf
        }
        $r = Set-MetraPlanIndexEntry `
            -PlansDir $plansDir `
            -Project $Project `
            -Stem $stem `
            -CursorLeaf $leaf `
            -Authority repo `
            -RepoPath $f.Name `
            -WhatIf:$WhatIf
        $results += $r
    }
    return [PSCustomObject]@{
        plansDir   = $plansDir
        indexPath  = (Get-MetraPlanIndexPath -PlansDir $plansDir)
        entryCount = @($byStem.Keys).Count
        collisions = @($collisions.ToArray())
        results    = @($results)
    }
}
