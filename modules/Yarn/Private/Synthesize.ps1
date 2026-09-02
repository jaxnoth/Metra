# Template synthesis (A2) — Pending Bing Review only; no Approved; no agent on auto path.

function New-YarnPlanSlugFromTitle {
    param([Parameter(Mandatory)][string]$Title)
    return ConvertTo-YarnSlug -Text $Title
}

function Resolve-YarnPatternOwnerHint {
    param([string]$ProjectKey)
    $k = if ($ProjectKey) { $ProjectKey.Trim().ToLowerInvariant() } else { '' }
    $allowed = @('metra', 'yarn', 'loom', 'atlas')
    if ($allowed -contains $k) { return $k }
    return 'metra'
}

function New-YarnFormalPlanText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BacklogItem,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [string]$SynthesizerVersion = 'yarn-template-v1'
    )

    $title = [string](Get-YarnProp -Object $BacklogItem -Name 'title' -Default 'Untitled')
    $captureId = [string](Get-YarnProp -Object $BacklogItem -Name 'captureId' -Default '')
    $sourceKey = [string](Get-YarnProp -Object $BacklogItem -Name 'primarySourceKey' -Default '')
    $sourceText = [string](Get-YarnProp -Object $BacklogItem -Name 'sourceText' -Default $title)
    $projectKey = [string](Get-YarnProp -Object $BacklogItem -Name 'projectKey' -Default 'Metra')
    $ownerHint = Resolve-YarnPatternOwnerHint -ProjectKey $projectKey
    $matchText = "$title`n$sourceText"
    $matched = @(Find-MetraPatternsMatching -MetraRoot $MetraRoot -Owner $ownerHint -MatchText $matchText -MaxCount 8)
    $gaps = @(Get-MetraPatternGaps -MetraRoot $MetraRoot -Owner $ownerHint)

    $atlasId = [string](Get-YarnProp -Object $BacklogItem -Name 'atlasStableId' -Default '')
    if (-not $atlasId -and $sourceKey -like 'atlas:*') { $atlasId = $sourceKey.Substring(6) }
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $todoId = 'draft-1'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine("name: $title")
    [void]$sb.AppendLine("overview: `"Draft from Yarn synthesize ($sourceKey). Pending Bing Review.`"")
    [void]$sb.AppendLine('status: Pending Bing Review')
    [void]$sb.AppendLine('bingReviewed: false')
    if ($atlasId) { [void]$sb.AppendLine("atlasStableId: $atlasId") }
    if ($captureId) { [void]$sb.AppendLine("captureId: $captureId") }
    [void]$sb.AppendLine("synthesizedAt: `"$now`"")
    [void]$sb.AppendLine("synthesizerVersion: $SynthesizerVersion")
    if ($matched.Count -eq 0) {
        [void]$sb.AppendLine('patterns: []')
    }
    else {
        [void]$sb.AppendLine('patterns:')
        foreach ($m in $matched) {
            [void]$sb.AppendLine("  - $($m.patternId)")
        }
    }
    [void]$sb.AppendLine('todos:')
    [void]$sb.AppendLine("  - id: $todoId")
    [void]$sb.AppendLine("    content: Refine scope and done-when for $title")
    [void]$sb.AppendLine('    status: pending')
    [void]$sb.AppendLine('isProject: false')
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("# $title")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Product shape')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($sourceText)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Architecture')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('_Draft - fill during Bing finalize._')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Delivery')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('- [ ] Clarify done-when')
    [void]$sb.AppendLine('- [ ] Add verify commands')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Pattern gaps')
    [void]$sb.AppendLine('')
    if ($gaps.Count -eq 0) {
        [void]$sb.AppendLine('_None - required catalog satisfied for owner hint._')
    }
    else {
        foreach ($g in $gaps) {
            [void]$sb.AppendLine("- candidate: $($g.suggestedPatternId) (owner $($g.owner)) - $($g.observedBehavior)")
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Constraints')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('- Status remains Pending Bing Review until Yarn human approval')
    [void]$sb.AppendLine('- Pattern gap checklist does not auto-author Pattern bodies')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Open questions')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('- _TBD_')
    [void]$sb.AppendLine('')
    return $sb.ToString()
}

function Resolve-YarnProjectDocsPath {
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [Parameter(Mandatory)][string]$ProjectKey
    )
    if ($ProjectKey -eq 'Metra' -or [string]::IsNullOrWhiteSpace($ProjectKey)) {
        return Join-Path $MetraRoot 'docs'
    }
    $key = [string]$ProjectKey.Trim()
    if ($key -match '[\\/]' -or $key -match '\.\.' -or [System.IO.Path]::IsPathRooted($key)) {
        throw "Invalid projectKey for docs path (refusing traversal): $ProjectKey"
    }
    if ($key -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        throw "Invalid projectKey for docs path: $ProjectKey"
    }
    $parent = Split-Path -Parent $MetraRoot
    $sibling = Join-Path $parent $key
    $siblingFull = [System.IO.Path]::GetFullPath($sibling)
    $parentFull = [System.IO.Path]::GetFullPath($parent)
    if (-not $parentFull.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
        $parentFull = $parentFull + [System.IO.Path]::DirectorySeparatorChar
    }
    if (-not $siblingFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved project docs path escaped parent root: $ProjectKey"
    }
    $docs = Join-Path $siblingFull 'docs'
    if (Test-Path -LiteralPath $siblingFull) {
        [void][System.IO.Directory]::CreateDirectory($docs)
        return $docs
    }
    return Join-Path $MetraRoot 'docs'
}

function Invoke-MetraYarnSynthesize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [string]$BacklogId,
        [string]$FromCapture,
        [string]$FromFutureDev,
        [string]$FromMemory,
        [switch]$DryRun,
        [switch]$Confirm,
        [switch]$Force,
        [switch]$UseAgent
    )

    if ($UseAgent) {
        throw 'Agent synthesis requires A3+ policy; A2 is template-only. Do not pass -UseAgent.'
    }
    if (-not $DryRun -and -not $Confirm) {
        throw 'yarn synthesize requires -DryRun or -Confirm'
    }

    $items = @(Get-MetraYarnBacklog -Root $Root)
    $item = $null
    if ($BacklogId) {
        $item = $items | Where-Object { [string]$_.id -eq $BacklogId } | Select-Object -First 1
    }
    elseif ($FromCapture) {
        $key = "capture:$FromCapture"
        $item = $items | Where-Object { [string]$_.primarySourceKey -eq $key } | Select-Object -First 1
    }
    elseif ($FromFutureDev) {
        $key = "future-dev:$FromFutureDev"
        $item = $items | Where-Object { [string]$_.primarySourceKey -eq $key } | Select-Object -First 1
    }
    elseif ($FromMemory) {
        $stableId = [string]$FromMemory
        if ($stableId -like 'atlas:*') { $stableId = $stableId.Substring(6) }
        $key = "atlas:$stableId"
        $item = $items | Where-Object {
            $psk = [string](Get-YarnProp -Object $_ -Name 'primarySourceKey' -Default '')
            $aid = [string](Get-YarnProp -Object $_ -Name 'atlasStableId' -Default '')
            ($psk -eq $key) -or ($aid -eq $stableId)
        } | Select-Object -First 1
        if (-not $item) {
            $candidates = @(Get-YarnAtlasIntakeCandidates -MetraRoot $MetraRoot)
            $cand = $candidates | Where-Object {
                [string](Get-YarnProp -Object $_ -Name 'stableId' -Default '') -eq $stableId
            } | Select-Object -First 1
            if (-not $cand) { throw "Atlas StableId not found for synthesize: $stableId" }
            $kind = [string](Get-YarnProp -Object $cand -Name 'kind' -Default 'Plan')
            $title = [string](Get-YarnProp -Object $cand -Name 'title' -Default $stableId)
            $sourceText = [string](Get-YarnProp -Object $cand -Name 'sourceText' -Default $title)
            $projectKey = [string](Get-YarnProp -Object $cand -Name 'projectKey' -Default 'Metra')
            $incoming = New-YarnPsObject -Map @{
                title                   = $title
                primarySourceKey        = $key
                sources                 = @($key)
                sourceKind              = 'atlas'
                atlasStableId           = $stableId
                memoryLane              = 'atlas'
                atlasKind               = $kind
                projectKey              = $projectKey
                operatorPriority        = 0
                urgency                 = 0
                strategicAlignment      = (Get-YarnStrategicAlignmentForAtlasKind -AtlasKind $kind)
                boundedTodosPresent     = $false
                verificationPathPresent = $false
                riskKnownAndAcceptable  = $false
                dependenciesResolved    = $true
                sourceText              = $sourceText
                sourceHash              = (Get-YarnSourceHash -NormalizedSourceText $sourceText)
                health                  = 'ok'
            }
            if ($DryRun) {
                # Keep -FromMemory dry-run side-effect free (no backlog upsert).
                $item = New-YarnPsObject -Map (@{ id = 'YARN-DRYRUN' } + (ConvertTo-YarnPropertyMap -Object $incoming))
            }
            else {
                $item = Sync-YarnBacklogItem -Root $Root -Incoming $incoming
            }
        }
    }
    if (-not $item) { throw 'Backlog item not found for synthesize' }

    $projectKey = [string](Get-YarnProp -Object $item -Name 'projectKey' -Default 'Metra')
    $docs = Resolve-YarnProjectDocsPath -MetraRoot $MetraRoot -ProjectKey $projectKey
    $slug = New-YarnPlanSlugFromTitle -Title ([string]$item.title)
    $planPath = Join-Path $docs ("$slug.plan.md")
    $existing = Test-Path -LiteralPath $planPath
    if ($existing -and -not $Force -and -not $DryRun) {
        $link = @(Get-YarnPlanLinks -Root $Root) | Where-Object { [string]$_.backlogId -eq [string]$item.id } | Select-Object -First 1
        $prevSource = [string](Get-YarnProp -Object $link -Name 'sourceHash' -Default '')
        $curSource = [string](Get-YarnProp -Object $item -Name 'sourceHash' -Default '')
        $linkedRefresh = ($null -ne $link) -and (-not [string]::IsNullOrWhiteSpace($prevSource)) -and (-not [string]::IsNullOrWhiteSpace($curSource)) -and ($prevSource -ne $curSource)
        if (-not $linkedRefresh) {
            if ($null -eq $link -or [string]::IsNullOrWhiteSpace($prevSource) -or [string]::IsNullOrWhiteSpace($curSource)) {
                throw "Plan already exists at $planPath without a linked sourceHash change (use -Force)"
            }
            throw "Plan already exists at $planPath (use -Force or changed sourceHash)"
        }
    }

    $text = New-YarnFormalPlanText -BacklogItem $item -MetraRoot $MetraRoot
    $planHash = Get-YarnPlanContentHash -PlanText $text
    $patternIds = @(Get-MetraPlanPatternIds -PlanText $text)
    if ($DryRun) {
        return [PSCustomObject]@{
            outcome          = 'dry-run'
            backlogId        = [string]$item.id
            planPath         = $planPath
            planContentHash  = $planHash
            status           = 'Pending Bing Review'
            patterns         = @($patternIds)
        }
    }

    Write-YarnAtomicUtf8Text -Path $planPath -Text $text
    $itemMap = @{}
    foreach ($p in $item.PSObject.Properties) { $itemMap[$p.Name] = $p.Value }
    $itemMap['formalPlanPath'] = $planPath
    $itemMap['boundedTodosPresent'] = $true
    $itemMap['status'] = 'pending-bing'
    $rank = Measure-YarnRank -Item (New-YarnPsObject -Map $itemMap)
    foreach ($rp in $rank.PSObject.Properties) { $itemMap[$rp.Name] = $rp.Value }
    $updated = New-YarnPsObject -Map $itemMap
    $all = @(Get-MetraYarnBacklog -Root $Root | Where-Object { [string]$_.id -ne [string]$item.id }) + @($updated)
    Save-MetraYarnBacklogItems -Root $Root -Items $all

    Sync-YarnPlanLink -Root $Root -Link (New-YarnPsObject -Map @{
            backlogId              = [string]$item.id
            formalPlanPath         = $planPath
            planStatus             = 'Pending Bing Review'
            sourceHash             = [string](Get-YarnProp -Object $item -Name 'sourceHash' -Default '')
            planContentHash        = $planHash
            packContractVersion    = Get-YarnPackContractVersion
            handoffContractVersion = Get-YarnHandoffContractVersion
            synthesizerVersion     = 'yarn-template-v1'
            synthesizedAt          = (Get-Date).ToUniversalTime().ToString('o')
            atlasStableId          = [string](Get-YarnProp -Object $item -Name 'atlasStableId' -Default '')
            atlasKind              = [string](Get-YarnProp -Object $item -Name 'atlasKind' -Default '')
            memoryLane             = [string](Get-YarnProp -Object $item -Name 'memoryLane' -Default '')
        })

    Add-MetraYarnJournalEntry -Root $Root -Entry @{
        op        = 'synthesize'
        backlogId = [string]$item.id
        planPath  = $planPath
    }

    return [PSCustomObject]@{
        outcome         = 'synthesized'
        backlogId       = [string]$item.id
        planPath        = $planPath
        planContentHash = $planHash
        status          = 'Pending Bing Review'
    }
}
