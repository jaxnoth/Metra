# Metra Patterns loader (P2/P3). Pure filesystem helpers; pass -MetraRoot.
# Cabinet is organizational only - no runtime branches on cabinet value.

Set-StrictMode -Version Latest

function Get-MetraPatternsDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MetraRoot)
    return [System.IO.Path]::GetFullPath((Join-Path $MetraRoot 'docs\patterns'))
}

function Get-MetraPatternContentHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Test-MetraPatternPathWithinPatternsRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $patternsRoot = Get-MetraPatternsDirectory -MetraRoot $MetraRoot
        $full = [System.IO.Path]::GetFullPath($Path)
        $rootFull = $patternsRoot.TrimEnd('\', '/')
        if ([string]::Equals($full, $rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
        return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Read-MetraPatternIndex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MetraRoot)

    $dir = Get-MetraPatternsDirectory -MetraRoot $MetraRoot
    $indexPath = Join-Path $dir 'index.yaml'
    $map = @{}
    $dupes = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $indexPath)) {
        return [PSCustomObject]@{
            path       = $indexPath
            byId       = @{}
            duplicates = @()
            errors     = @('index-missing')
        }
    }
    $lines = [System.IO.File]::ReadAllLines($indexPath, [System.Text.UTF8Encoding]::new($false))
    $seenCase = @{}
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($t) -or $t.StartsWith('#') -or $t -eq '{}' -or $t -eq '---') { continue }
        if ($t -notmatch '^([A-Za-z0-9][A-Za-z0-9._-]*):\s*(.+)$') { continue }
        $id = $Matches[1]
        $rel = $Matches[2].Trim().Trim('"').Trim("'")
        $idKey = $id.ToLowerInvariant()
        if ($seenCase.ContainsKey($idKey)) {
            [void]$dupes.Add($id)
            continue
        }
        $seenCase[$idKey] = $id
        $map[$id] = $rel
    }
    return [PSCustomObject]@{
        path       = $indexPath
        byId       = $map
        duplicates = @($dupes)
        errors     = @()
    }
}

function Read-MetraPatternRequiredCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MetraRoot)

    $path = Join-Path (Get-MetraPatternsDirectory -MetraRoot $MetraRoot) 'required.yaml'
    $catalog = @{
        loom  = @()
        metra = @()
        yarn  = @()
        atlas = @()
    }
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{ path = $path; byOwner = $catalog; errors = @('required-missing') }
    }
    $lines = [System.IO.File]::ReadAllLines($path, [System.Text.UTF8Encoding]::new($false))
    $current = $null
    foreach ($line in $lines) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^([A-Za-z0-9_-]+):\s*$') {
            $current = $Matches[1].ToLowerInvariant()
            if (-not $catalog.ContainsKey($current)) { $catalog[$current] = @() }
            continue
        }
        if ($null -ne $current -and $line -match '^\s*-\s+([A-Za-z0-9][A-Za-z0-9._-]*)') {
            $catalog[$current] = @($catalog[$current] + $Matches[1])
        }
    }
    return [PSCustomObject]@{ path = $path; byOwner = $catalog; errors = @() }
}

function ConvertFrom-MetraPatternFrontMatter {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $result = [ordered]@{
        ok                 = $false
        patternId          = $null
        owner              = $null
        cabinet            = $null
        status             = $null
        implemented        = $null
        patternSchemaVersion = $null
        defaultContext     = $null
        loadWhen           = @()
        errors             = New-Object System.Collections.Generic.List[string]
        warnings           = New-Object System.Collections.Generic.List[string]
    }

    if ($Text -notmatch '(?ms)^---\r?\n(.*?)\r?\n---') {
        [void]$result.errors.Add('missing-front-matter')
        return [PSCustomObject]$result
    }
    $yaml = $Matches[1]
    if ($yaml -match '(?m)^product\s*:') { [void]$result.errors.Add('legacy-field-product') }
    if ($yaml -match '(?m)^domain\s*:') { [void]$result.errors.Add('legacy-field-domain') }

    if ($yaml -match '(?m)^patternId:\s*(.+)$') {
        $result.patternId = $Matches[1].Trim().Trim('"').Trim("'")
    }
    else { [void]$result.errors.Add('missing-patternId') }

    if ($yaml -match '(?m)^owner:\s*(.+)$') {
        $result.owner = $Matches[1].Trim().Trim('"').Trim("'").ToLowerInvariant()
    }
    else { [void]$result.errors.Add('missing-owner') }

    if ($yaml -match '(?m)^cabinet:\s*(.+)$') {
        $cab = $Matches[1].Trim().Trim('"').Trim("'")
        if ($cab -eq 'null' -or $cab -eq '~' -or $cab -eq '') { $result.cabinet = $null }
        else { $result.cabinet = $cab.ToLowerInvariant() }
    }

    if ($yaml -match '(?m)^status:\s*(.+)$') {
        $result.status = $Matches[1].Trim().Trim('"').Trim("'").ToLowerInvariant()
    }
    else { [void]$result.errors.Add('missing-status') }

    if ($yaml -match '(?m)^implemented:\s*(true|false)\s*$') {
        $result.implemented = ($Matches[1] -eq 'true')
    }
    else { [void]$result.errors.Add('missing-implemented') }

    if ($yaml -match '(?m)^patternSchemaVersion:\s*(\d+)\s*$') {
        $result.patternSchemaVersion = [int]$Matches[1]
    }
    else { [void]$result.errors.Add('missing-patternSchemaVersion') }

    if ($yaml -match '(?m)^defaultContext:\s*(true|false)\s*$') {
        $result.defaultContext = ($Matches[1] -eq 'true')
        if ($result.defaultContext) { [void]$result.errors.Add('defaultContext-must-be-false') }
    }
    else { [void]$result.errors.Add('missing-defaultContext') }

    $allowedOwners = @('metra', 'yarn', 'loom', 'atlas')
    if ($result.owner -and ($allowedOwners -notcontains $result.owner)) {
        [void]$result.errors.Add('unknown-owner')
    }
    $allowedCabinets = @('guild')
    if ($null -ne $result.cabinet -and ($allowedCabinets -notcontains $result.cabinet)) {
        [void]$result.errors.Add('unknown-cabinet')
    }

    $loadBlock = $false
    foreach ($line in ($yaml -split '\r?\n')) {
        if ($line -match '^loadWhen:\s*$') { $loadBlock = $true; continue }
        if ($loadBlock) {
            if ($line -match '^\S') { $loadBlock = $false; continue }
            if ($line -match '^\s*-\s+(.+)$') {
                $result.loadWhen = @($result.loadWhen + $Matches[1].Trim().Trim('"').Trim("'"))
            }
        }
    }

    $result.ok = ($result.errors.Count -eq 0)
    $result.errors = @($result.errors)
    $result.warnings = @($result.warnings)
    $result.loadWhen = @($result.loadWhen)
    return [PSCustomObject]$result
}

function Resolve-MetraPatternPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [Parameter(Mandatory)][string]$PatternId
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($PatternId)) {
        return [PSCustomObject]@{ ok = $false; path = $null; relativePath = $null; errors = @('empty-patternId'); warnings = @() }
    }
    if ([System.IO.Path]::IsPathRooted($PatternId) -or $PatternId.Contains('\') -or $PatternId.Contains('/') -or $PatternId.Contains('..')) {
        return [PSCustomObject]@{ ok = $false; path = $null; relativePath = $null; errors = @('patternId-must-not-be-path'); warnings = @() }
    }

    $index = Read-MetraPatternIndex -MetraRoot $MetraRoot
    if ($index.duplicates.Count -gt 0) {
        [void]$errors.Add('duplicate-patternId-in-index')
    }
    $rel = $null
    foreach ($k in @($index.byId.Keys)) {
        if ([string]::Equals($k, $PatternId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = [string]$index.byId[$k]
            if (-not [string]::Equals($k, $PatternId, [System.StringComparison]::Ordinal)) {
                [void]$warnings.Add('patternId-case-normalized')
            }
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($rel)) {
        [void]$warnings.Add('pattern-unresolved')
        return [PSCustomObject]@{
            ok           = $false
            path         = $null
            relativePath = $null
            errors       = @($errors)
            warnings     = @($warnings)
        }
    }
    if ([System.IO.Path]::IsPathRooted($rel)) {
        return [PSCustomObject]@{ ok = $false; path = $null; relativePath = $rel; errors = @('absolute-path-in-index'); warnings = @($warnings) }
    }
    $patternsRoot = Get-MetraPatternsDirectory -MetraRoot $MetraRoot
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $patternsRoot $rel))
    if (-not (Test-MetraPatternPathWithinPatternsRoot -Path $candidate -MetraRoot $MetraRoot)) {
        return [PSCustomObject]@{ ok = $false; path = $null; relativePath = $rel; errors = @('path-escapes-patterns-root'); warnings = @($warnings) }
    }
    if (-not (Test-Path -LiteralPath $candidate)) {
        [void]$warnings.Add('pattern-file-missing')
        return [PSCustomObject]@{
            ok           = $false
            path         = $candidate
            relativePath = $rel
            errors       = @($errors)
            warnings     = @($warnings)
        }
    }
    return [PSCustomObject]@{
        ok           = ($errors.Count -eq 0)
        path         = $candidate
        relativePath = $rel
        errors       = @($errors)
        warnings     = @($warnings)
    }
}

function Read-MetraPatternFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [Parameter(Mandatory)][string]$PatternId,
        [int]$MaxBodyBytes = 12000
    )

    $resolved = Resolve-MetraPatternPath -MetraRoot $MetraRoot -PatternId $PatternId
    if (-not $resolved.ok -or [string]::IsNullOrWhiteSpace($resolved.path) -or -not (Test-Path -LiteralPath $resolved.path)) {
        return [PSCustomObject]@{
            ok           = $false
            patternId    = $PatternId
            path         = $resolved.path
            relativePath = $resolved.relativePath
            owner        = $null
            cabinet      = $null
            loadWhen     = @()
            contentHash  = $null
            bodyExcerpt  = $null
            errors       = @($resolved.errors)
            warnings     = @($resolved.warnings)
        }
    }

    $text = [System.IO.File]::ReadAllText($resolved.path, [System.Text.UTF8Encoding]::new($false))
    $fm = ConvertFrom-MetraPatternFrontMatter -Text $text
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    foreach ($e in @($resolved.errors)) { [void]$errors.Add($e) }
    foreach ($w in @($resolved.warnings)) { [void]$warnings.Add($w) }
    foreach ($e in @($fm.errors)) { [void]$errors.Add($e) }
    foreach ($w in @($fm.warnings)) { [void]$warnings.Add($w) }

    if ($fm.patternId -and -not [string]::Equals($fm.patternId, $PatternId, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$errors.Add('patternId-mismatch-file-vs-index')
    }

    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($text)
    $excerpt = $text
    if ($bytes -gt $MaxBodyBytes) {
        $excerpt = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes($text)[0..($MaxBodyBytes - 1)])
        [void]$warnings.Add('pattern-body-truncated')
    }

    return [PSCustomObject]@{
        ok           = ($errors.Count -eq 0)
        patternId    = $(if ($fm.patternId) { $fm.patternId } else { $PatternId })
        path         = $resolved.path
        relativePath = $resolved.relativePath
        owner        = $fm.owner
        cabinet      = $fm.cabinet
        loadWhen     = @($fm.loadWhen)
        status       = $fm.status
        implemented  = $fm.implemented
        contentHash  = (Get-MetraPatternContentHash -Text $text)
        bodyExcerpt  = $excerpt
        errors       = @($errors)
        warnings     = @($warnings)
    }
}

function Get-MetraPlanPatternIds {
    [CmdletBinding()]
    param(
        [string]$PlanText,
        [string]$PlanPath
    )
    if ([string]::IsNullOrWhiteSpace($PlanText) -and -not [string]::IsNullOrWhiteSpace($PlanPath) -and (Test-Path -LiteralPath $PlanPath)) {
        $PlanText = [System.IO.File]::ReadAllText($PlanPath, [System.Text.UTF8Encoding]::new($false))
    }
    if ([string]::IsNullOrWhiteSpace($PlanText)) { return @() }
    if ($PlanText -notmatch '(?ms)^---\r?\n(.*?)\r?\n---') { return @() }
    $yaml = $Matches[1]
    $ids = New-Object System.Collections.Generic.List[string]
    if ($yaml -match '(?ms)^patterns:\s*\r?\n((?:\s*-\s+.+\r?\n?)+)') {
        foreach ($m in [regex]::Matches($Matches[1], '(?m)^\s*-\s+(.+)$')) {
            $id = $m.Groups[1].Value.Trim().Trim('"').Trim("'")
            if ($id) { [void]$ids.Add($id) }
        }
    }
    elseif ($yaml -match '(?m)^patterns:\s*\[([^\]]*)\]') {
        foreach ($part in ($Matches[1] -split ',')) {
            $id = $part.Trim().Trim('"').Trim("'")
            if ($id) { [void]$ids.Add($id) }
        }
    }
    return @($ids)
}

function Get-MetraPatternsForPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [string[]]$PatternIds = @(),
        [int]$MaxCount = 8,
        [int]$MaxTotalBytes = 48000,
        [int]$MaxEachBytes = 12000
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]
    $patterns = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $total = 0
    $index = Read-MetraPatternIndex -MetraRoot $MetraRoot
    if ($index.duplicates.Count -gt 0) {
        [void]$errors.Add('duplicate-patternId-in-index')
    }

    foreach ($rawId in @($PatternIds)) {
        if ($errors.Count -gt 0) { break }
        if ($patterns.Count -ge $MaxCount) {
            [void]$warnings.Add('pattern-count-ceiling')
            break
        }
        $id = [string]$rawId
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $key = $id.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            [void]$warnings.Add("duplicate-cite:$id")
            continue
        }
        $seen[$key] = $true
        $p = Read-MetraPatternFile -MetraRoot $MetraRoot -PatternId $id -MaxBodyBytes $MaxEachBytes
        if (-not $p.ok) {
            $fatal = $false
            foreach ($e in @($p.errors)) {
                if ($e -in @('duplicate-patternId-in-index', 'absolute-path-in-index', 'path-escapes-patterns-root', 'unknown-owner', 'unknown-cabinet', 'legacy-field-product', 'legacy-field-domain', 'defaultContext-must-be-false', 'patternId-mismatch-file-vs-index', 'patternId-must-not-be-path')) {
                    [void]$errors.Add("$id`:$e")
                    $fatal = $true
                }
                else {
                    [void]$warnings.Add("$id`:$e")
                }
            }
            foreach ($w in @($p.warnings)) {
                if ($w -in @('pattern-unresolved', 'pattern-file-missing')) {
                    [void]$warnings.Add("$id`:$w")
                }
                else {
                    [void]$warnings.Add("$id`:$w")
                }
            }
            if ($fatal) { continue }
            continue
        }
        $len = [System.Text.Encoding]::UTF8.GetByteCount([string]$p.bodyExcerpt)
        if (($total + $len) -gt $MaxTotalBytes) {
            [void]$warnings.Add('pattern-aggregate-byte-ceiling')
            break
        }
        $total += $len
        [void]$patterns.Add([PSCustomObject]@{
                patternId   = $p.patternId
                path        = $p.relativePath
                owner       = $p.owner
                cabinet     = $p.cabinet
                contentHash = $p.contentHash
                bodyExcerpt = $p.bodyExcerpt
                reason      = 'plan-citation'
            })
    }

    return [PSCustomObject]@{
        ok       = ($errors.Count -eq 0)
        patterns = [object[]]@($patterns.ToArray())
        warnings = [string[]]@($warnings.ToArray())
        errors   = [string[]]@($errors.ToArray())
    }
}

function ConvertTo-MetraPatternMatchText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text.ToLowerInvariant()
    $t = [regex]::Replace($t, '\s+', ' ')
    return $t.Trim()
}

function Find-MetraPatternsMatching {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [string]$Owner = '',
        [string]$Cabinet = '',
        [string]$MatchText = '',
        [string[]]$CitedPatternIds = @(),
        [int]$MaxCount = 8
    )

    $ownerNorm = if ($Owner) { $Owner.Trim().ToLowerInvariant() } else { '' }
    $cabinetNorm = if ($Cabinet) { $Cabinet.Trim().ToLowerInvariant() } else { '' }
    $textNorm = ConvertTo-MetraPatternMatchText -Text $MatchText
    $index = Read-MetraPatternIndex -MetraRoot $MetraRoot
    $candidates = New-Object System.Collections.Generic.List[object]

    # Priority 1: explicit citations
    foreach ($cid in @($CitedPatternIds)) {
        $p = Read-MetraPatternFile -MetraRoot $MetraRoot -PatternId $cid
        if ($p.ok) {
            [void]$candidates.Add([PSCustomObject]@{
                    patternId = $p.patternId
                    path      = $p.relativePath
                    owner     = $p.owner
                    cabinet   = $p.cabinet
                    reason    = 'plan-citation'
                    rank      = 1
                })
        }
    }

    foreach ($id in @($index.byId.Keys)) {
        $p = Read-MetraPatternFile -MetraRoot $MetraRoot -PatternId $id
        if (-not $p.ok) { continue }

        # Rank 2: exact loadWhen phrase contained in MatchText
        if ($textNorm -and @($p.loadWhen).Count -gt 0) {
            foreach ($lw in @($p.loadWhen)) {
                $phrase = ConvertTo-MetraPatternMatchText -Text $lw
                if ($phrase -and $textNorm.Contains($phrase)) {
                    [void]$candidates.Add([PSCustomObject]@{
                            patternId = $p.patternId
                            path      = $p.relativePath
                            owner     = $p.owner
                            cabinet   = $p.cabinet
                            reason    = "loadWhen: $lw"
                            rank      = 2
                        })
                    break
                }
            }
        }

        # Rank 3: owner filter (product owner only)
        if ($ownerNorm -and $p.owner -eq $ownerNorm) {
            [void]$candidates.Add([PSCustomObject]@{
                    patternId = $p.patternId
                    path      = $p.relativePath
                    owner     = $p.owner
                    cabinet   = $p.cabinet
                    reason    = "owner: $ownerNorm"
                    rank      = 3
                })
        }

        # Rank 4: cabinet filter — organizational only; no special-case for guild (invariant 15)
        if ($cabinetNorm -and $p.cabinet -and ($p.cabinet -eq $cabinetNorm)) {
            [void]$candidates.Add([PSCustomObject]@{
                    patternId = $p.patternId
                    path      = $p.relativePath
                    owner     = $p.owner
                    cabinet   = $p.cabinet
                    reason    = "cabinet: $cabinetNorm"
                    rank      = 4
                })
        }
    }

    $seen = @{}
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($c in ($candidates | Sort-Object rank, patternId)) {
        $k = [string]$c.patternId.ToLowerInvariant()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        [void]$out.Add($c)
        if ($out.Count -ge $MaxCount) { break }
    }
    return [object[]]@($out.ToArray())
}

function Get-MetraPatternGaps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [string]$Owner = ''
    )

    $catalog = Read-MetraPatternRequiredCatalog -MetraRoot $MetraRoot
    $index = Read-MetraPatternIndex -MetraRoot $MetraRoot
    $owners = if ($Owner) { @($Owner.ToLowerInvariant()) } else { @($catalog.byOwner.Keys) }
    $gaps = New-Object System.Collections.Generic.List[object]
    foreach ($o in $owners) {
        if (-not $catalog.byOwner.ContainsKey($o)) { continue }
        foreach ($req in @($catalog.byOwner[$o])) {
            $found = $false
            foreach ($k in @($index.byId.Keys)) {
                if ([string]::Equals($k, $req, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                [void]$gaps.Add([PSCustomObject]@{
                        type               = 'pattern-gap'
                        suggestedPatternId = $req
                        owner              = $o
                        observedBehavior   = "Required Pattern '$req' missing from docs/patterns/index.yaml"
                        status             = 'candidate'
                    })
            }
        }
    }
    return [object[]]@($gaps.ToArray())
}
