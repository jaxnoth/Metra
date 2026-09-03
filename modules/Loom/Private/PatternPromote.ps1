# Slice 8 - Pattern score / promote (accept-gated Atlas publication).
# Cabinet is organizational only (invariant 15). Authority stays on tracked Pattern files.

function Get-LoomPatternPromotionsPath {
    param([Parameter(Mandatory)][string]$Root)
    return Join-Path $Root 'patterns\promotions.json'
}

function Get-LoomPatternPromotions {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $path = Get-LoomPatternPromotionsPath -Root $Root
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{
            schemaVersion = 1
            promotions    = @()
        }
    }
    try {
        $doc = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $list = @($(Get-LoomProp -Object $doc -Name 'promotions' -Default @()))
        return [PSCustomObject]@{
            schemaVersion = 1
            promotions    = @($list)
        }
    }
    catch {
        throw "Pattern promotions ledger unreadable: $path"
    }
}

function Save-LoomPatternPromotions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Document
    )
    $dir = Join-Path $Root 'patterns'
    if (-not (Test-Path -LiteralPath $dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $path = Get-LoomPatternPromotionsPath -Root $Root
    $payload = [ordered]@{
        schemaVersion = 1
        promotions    = @($(Get-LoomProp -Object $Document -Name 'promotions' -Default @()))
    }
    Write-LoomAtomicUtf8Text -Path $path -Text (($payload | ConvertTo-Json -Depth 10) + "`n")
    return $path
}

function Resolve-LoomPatternFileUnderMetra {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$MetraRoot
    )

    $metraFull = [System.IO.Path]::GetFullPath($MetraRoot)
    $candidate = $Path
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $candidate = Join-Path $metraFull $Path
    }
    $full = Get-MetraCanonicalPath -Path ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($candidate))
    if (-not (Test-MetraPatternPathWithinPatternsRoot -Path $full -MetraRoot $metraFull)) {
        throw "Pattern path escapes docs/patterns: $Path"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Pattern file not found: $full"
    }
    $patternsRoot = Get-MetraPatternsDirectory -MetraRoot $MetraRoot
    $rel = $full.Substring($patternsRoot.TrimEnd('\', '/').Length).TrimStart('\', '/')
    $relUnix = ($rel -replace '\\', '/')
    return [PSCustomObject]@{
        fullPath     = $full
        relativePath = $relUnix
        repoRelative = ('docs/patterns/' + $relUnix)
    }
}

function Get-LoomGitNameOnlyDiff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$BaselineCommit,
        [Parameter(Mandatory)][string]$CompletedCommit,
        [string]$PathFilter = 'docs/patterns'
    )

    if ($script:LoomPatternDiffOverride) {
        return @(& $script:LoomPatternDiffOverride -ProjectRoot $ProjectRoot -BaselineCommit $BaselineCommit -CompletedCommit $CompletedCommit -PathFilter $PathFilter)
    }

    $args = @('diff', '--name-only', "${BaselineCommit}..${CompletedCommit}", '--', $PathFilter)
    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs $args
    if ($r.ExitCode -ne 0) {
        return @()
    }
    $lines = @()
    foreach ($line in @(([string]$r.Stdout) -split '\r?\n')) {
        $t = $line.Trim()
        if ($t) { $lines += ($t -replace '\\', '/') }
    }
    return @($lines)
}

function Get-LoomGitBlobText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$RepoRelativePath
    )

    if ($script:LoomPatternBlobOverride) {
        return & $script:LoomPatternBlobOverride -ProjectRoot $ProjectRoot -Commit $Commit -RepoRelativePath $RepoRelativePath
    }

    $spec = "${Commit}:$($RepoRelativePath -replace '\\', '/')"
    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('show', $spec)
    if ($r.ExitCode -ne 0) { return $null }
    return [string]$r.Stdout
}

function Test-LoomPatternAlreadyPromoted {
    param(
        [Parameter(Mandatory)][object]$Ledger,
        [Parameter(Mandatory)][string]$PatternId,
        [Parameter(Mandatory)][string]$ContentHash
    )
    foreach ($p in @($(Get-LoomProp -Object $Ledger -Name 'promotions' -Default @()))) {
        $id = [string](Get-LoomProp -Object $p -Name 'patternId' -Default '')
        $hash = [string](Get-LoomProp -Object $p -Name 'contentHash' -Default '')
        $outcome = [string](Get-LoomProp -Object $p -Name 'outcome' -Default '')
        if ($outcome -ne 'promoted') { continue }
        if ([string]::Equals($id, $PatternId, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($hash, $ContentHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-MetraLoomPatternPromoteEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item,
        [Parameter(Mandatory)][string]$MetraRoot,
        [Parameter(Mandatory)][string]$PatternFullPath,
        [Parameter(Mandatory)][string]$RepoRelativePath,
        [Parameter(Mandatory)][object]$Ledger,
        [string]$WorkingContentHash
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $status = [string](Get-LoomProp -Object $Item -Name 'status' -Default '')
    if ($status -ne 'accepted') {
        [void]$reasons.Add("item-not-accepted:$status")
    }

    $projectRoot = [string](Get-LoomProp -Object $Item.project -Name 'root' -Default '')
    if ([string]::IsNullOrWhiteSpace($projectRoot)) {
        [void]$reasons.Add('missing-project-root')
    }

    $completed = [string](Get-LoomProp -Object $Item.execution -Name 'completedCommit' -Default '')
    $baseline = Get-LoomItemBaselineCommit -Item $Item
    if ([string]::IsNullOrWhiteSpace($completed) -or [string]::IsNullOrWhiteSpace($baseline)) {
        [void]$reasons.Add('missing-commit-range')
    }

    $changed = @()
    if ($projectRoot -and $completed -and $baseline) {
        $changed = @(Get-LoomGitNameOnlyDiff -ProjectRoot $projectRoot -BaselineCommit $baseline -CompletedCommit $completed)
    }
    $repoRelNorm = ($RepoRelativePath -replace '\\', '/')
    $touched = $false
    foreach ($c in $changed) {
        if ([string]::Equals($c, $repoRelNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
            $touched = $true
            break
        }
    }
    if (-not $touched) {
        [void]$reasons.Add('pattern-not-in-accepted-diff')
    }

    $patternIdHint = [IO.Path]::GetFileNameWithoutExtension($PatternFullPath)
    $parsed = $null
    if (Test-Path -LiteralPath $PatternFullPath) {
        # Resolve via index when possible; fall back to file read by scanning index paths
        $index = Read-MetraPatternIndex -MetraRoot $MetraRoot
        $id = $null
        foreach ($k in @($index.byId.Keys)) {
            $rel = ([string]$index.byId[$k] -replace '\\', '/')
            if ($repoRelNorm.EndsWith($rel, [System.StringComparison]::OrdinalIgnoreCase) -or
                $repoRelNorm.EndsWith(('docs/patterns/' + $rel), [System.StringComparison]::OrdinalIgnoreCase) -or
                ('docs/patterns/' + $rel) -eq $repoRelNorm) {
                $id = $k
                break
            }
        }
        if ($id) {
            $parsed = Read-MetraPatternFile -MetraRoot $MetraRoot -PatternId $id
        }
        else {
            $text = [System.IO.File]::ReadAllText($PatternFullPath, [System.Text.UTF8Encoding]::new($false))
            $fm = ConvertFrom-MetraPatternFrontMatter -Text $text
            $parsed = [PSCustomObject]@{
                ok          = $fm.ok
                patternId   = $(if ($fm.patternId) { $fm.patternId } else { $patternIdHint })
                owner       = $fm.owner
                cabinet     = $fm.cabinet
                contentHash = (Get-MetraPatternContentHash -Text $text)
                errors      = @($fm.errors)
                warnings    = @($fm.warnings)
            }
        }
    }
    else {
        [void]$reasons.Add('pattern-file-missing')
    }

    if ($parsed -and -not $parsed.ok) {
        foreach ($e in @($parsed.errors)) { [void]$reasons.Add("validation:$e") }
    }

    $contentHash = $WorkingContentHash
    if ([string]::IsNullOrWhiteSpace($contentHash) -and $parsed) {
        $contentHash = [string]$parsed.contentHash
    }

    if ($projectRoot -and $completed -and $parsed -and $parsed.ok) {
        $blob = Get-LoomGitBlobText -ProjectRoot $projectRoot -Commit $completed -RepoRelativePath $repoRelNorm
        if ($null -eq $blob) {
            [void]$reasons.Add('pattern-missing-at-accepted-revision')
        }
        else {
            $acceptedHash = Get-MetraPatternContentHash -Text $blob
            if ($contentHash -and -not [string]::Equals($acceptedHash, $contentHash, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$reasons.Add('working-tree-differs-from-accepted-revision')
            }
            $contentHash = $acceptedHash
        }
    }

    if ($parsed -and $parsed.ok -and $contentHash -and (Test-LoomPatternAlreadyPromoted -Ledger $Ledger -PatternId ([string]$parsed.patternId) -ContentHash $contentHash)) {
        [void]$reasons.Add('already-promoted-same-hash')
    }

    $eligible = ($reasons.Count -eq 0)
    return [PSCustomObject]@{
        eligible          = $eligible
        reasons           = [string[]]@($reasons.ToArray())
        warnings          = [string[]]@($warnings.ToArray())
        patternId         = $(if ($parsed) { [string]$parsed.patternId } else { $null })
        owner             = $(if ($parsed) { $parsed.owner } else { $null })
        cabinet           = $(if ($parsed) { $parsed.cabinet } else { $null })
        contentHash       = $contentHash
        itemId            = [string](Get-LoomProp -Object $Item -Name 'id' -Default '')
        completedCommit   = $completed
        baselineCommit    = $baseline
        changedPatternPaths = @($changed)
        repoRelativePath  = $repoRelNorm
        stableId          = $(if ($parsed -and $parsed.patternId) { "pattern:$($parsed.patternId)" } else { $null })
    }
}

function Invoke-MetraLoomPatternScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-LoomHostRoot),
        [string]$ItemId
    )

    Initialize-MetraLoomLayout -Root $Root
    $ledger = Get-LoomPatternPromotions -Root $Root
    $items = @(Get-MetraLoomQueueItems -Root $Root)
    if ($ItemId) {
        $items = @($items | Where-Object { [string]$_.id -eq $ItemId })
    }
    $candidates = New-Object System.Collections.Generic.List[object]
    $gaps = @(Get-MetraPatternGaps -MetraRoot $MetraRoot)

    foreach ($item in $items) {
        if ([string]$item.status -ne 'accepted') { continue }
        $projectRoot = [string](Get-LoomProp -Object $item.project -Name 'root' -Default '')
        $completed = [string](Get-LoomProp -Object $item.execution -Name 'completedCommit' -Default '')
        $baseline = Get-LoomItemBaselineCommit -Item $item
        if (-not $projectRoot -or -not $completed -or -not $baseline) { continue }
        $changed = @(Get-LoomGitNameOnlyDiff -ProjectRoot $projectRoot -BaselineCommit $baseline -CompletedCommit $completed)
        foreach ($rel in $changed) {
            if ($rel -notmatch '(?i)^docs/patterns/.+\.md$') { continue }
            $full = Join-Path $projectRoot ($rel -replace '/', '\')
            if (-not (Test-Path -LiteralPath $full)) {
                # Prefer MetraRoot copy when project root is Metra
                $alt = Join-Path $MetraRoot ($rel -replace '/', '\')
                if (Test-Path -LiteralPath $alt) { $full = $alt }
            }
            if (-not (Test-Path -LiteralPath $full)) { continue }
            try {
                $resolved = Resolve-LoomPatternFileUnderMetra -Path $full -MetraRoot $MetraRoot
            }
            catch { continue }
            $elig = Test-MetraLoomPatternPromoteEligibility `
                -Item $item `
                -MetraRoot $MetraRoot `
                -PatternFullPath $resolved.fullPath `
                -RepoRelativePath $resolved.repoRelative `
                -Ledger $ledger
            $score = 0
            if ($elig.eligible) { $score = 100 }
            elseif ($elig.reasons -notcontains 'item-not-accepted') { $score = 40 }
            [void]$candidates.Add([PSCustomObject]@{
                    type         = 'pattern-promote-candidate'
                    score        = $score
                    eligible     = [bool]$elig.eligible
                    patternId    = $elig.patternId
                    path         = $resolved.repoRelative
                    itemId       = $elig.itemId
                    contentHash  = $elig.contentHash
                    reasons      = @($elig.reasons)
                    status       = $(if ($elig.eligible) { 'eligible' } else { 'blocked' })
                })
        }
    }

    return [PSCustomObject]@{
        outcome    = 'scored'
        candidates = [object[]]@($candidates.ToArray())
        gaps       = @($gaps)
    }
}

function Invoke-MetraLoomPatternPromote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [string]$MetraRoot = (Get-LoomHostRoot),
        [string]$ItemId,
        [switch]$Preview,
        [switch]$Confirm,
        [switch]$Publish
    )

    if (-not $Preview -and -not $Confirm) {
        throw 'loom pattern promote requires -Preview or -Confirm'
    }
    if ($Preview -and $Confirm) {
        throw 'loom pattern promote: use -Preview or -Confirm, not both'
    }

    Initialize-MetraLoomLayout -Root $Root
    $resolved = Resolve-LoomPatternFileUnderMetra -Path $Path -MetraRoot $MetraRoot
    $ledger = Get-LoomPatternPromotions -Root $Root

    $items = @()
    if ($ItemId) {
        $one = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
        if (-not $one) { throw "Queue item not found: $ItemId" }
        $items = @($one)
    }
    else {
        $items = @(Get-MetraLoomQueueItems -Root $Root | Where-Object { [string]$_.status -eq 'accepted' })
    }

    $best = $null
    foreach ($item in $items) {
        $elig = Test-MetraLoomPatternPromoteEligibility `
            -Item $item `
            -MetraRoot $MetraRoot `
            -PatternFullPath $resolved.fullPath `
            -RepoRelativePath $resolved.repoRelative `
            -Ledger $ledger
        if ($elig.eligible) {
            $best = $elig
            break
        }
        if ($null -eq $best) { $best = $elig }
        elseif (-not $best.eligible -and $elig.reasons.Count -lt $best.reasons.Count) {
            $best = $elig
        }
    }

    if ($null -eq $best) {
        return [PSCustomObject]@{
            outcome  = 'rejected'
            eligible = $false
            reasons  = @('no-accepted-item')
            path     = $resolved.repoRelative
        }
    }

    if ($Preview) {
        return [PSCustomObject]@{
            outcome     = $(if ($best.eligible) { 'preview-eligible' } else { 'preview-blocked' })
            eligible    = [bool]$best.eligible
            reasons     = @($best.reasons)
            warnings    = @($best.warnings)
            patternId   = $best.patternId
            stableId    = $best.stableId
            path        = $resolved.repoRelative
            owner       = $best.owner
            cabinet     = $best.cabinet
            contentHash = $best.contentHash
            itemId      = $best.itemId
            publish     = [bool]$Publish
        }
    }

    # Confirm path
    if (-not $best.eligible) {
        throw ("Pattern promote rejected: " + (($best.reasons) -join '; '))
    }

    $title = $best.patternId
    $atlas = Invoke-LoomAtlasPutAdapter `
        -StableId $best.stableId `
        -Project 'Metra' `
        -Kind 'Doc' `
        -Title $title `
        -BodyPath $resolved.fullPath `
        -Publish:$Publish `
        -MetraRoot $MetraRoot

    if (-not (Get-LoomProp -Object $atlas -Name 'ok' -Default $false)) {
        $detail = [string](Get-LoomProp -Object $atlas -Name 'message' -Default 'Atlas put failed')
        throw "Pattern promote rejected (Atlas put failed): $detail"
    }

    $record = [PSCustomObject]@{
        schemaVersion   = 1
        patternId       = $best.patternId
        stableId        = $best.stableId
        contentHash     = $best.contentHash
        path            = $resolved.repoRelative
        itemId          = $best.itemId
        acceptedCommit  = $best.completedCommit
        promotedAt      = (Get-Date).ToUniversalTime().ToString('o')
        atlasMode       = $(if ($Publish) { 'published' } else { 'local' })
        outcome         = 'promoted'
        atlasOk         = [bool](Get-LoomProp -Object $atlas -Name 'ok' -Default $true)
    }

    $promos = @($(Get-LoomProp -Object $ledger -Name 'promotions' -Default @())) + @($record)
    $null = Save-LoomPatternPromotions -Root $Root -Document ([PSCustomObject]@{ promotions = $promos })
    $null = Add-MetraLoomJournalEntry -Root $Root -Entry @{
        itemId      = $best.itemId
        from        = 'accepted'
        to          = 'accepted'
        actor       = 'operator'
        reason      = "pattern-promote:$($best.patternId)"
        patternId   = $best.patternId
        stableId    = $best.stableId
        contentHash = $best.contentHash
        atlasMode   = $record.atlasMode
    }

    return [PSCustomObject]@{
        outcome     = 'promoted'
        eligible    = $true
        patternId   = $best.patternId
        stableId    = $best.stableId
        path        = $resolved.repoRelative
        contentHash = $best.contentHash
        itemId      = $best.itemId
        atlas       = $atlas
        record      = $record
    }
}
