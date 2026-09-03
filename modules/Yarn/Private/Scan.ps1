# Yarn scan: Capture + Future-Dev + Atlas → backlog upsert (no synth/pack).

function ConvertTo-YarnSlug {
    param([Parameter(Mandatory)][string]$Text)
    $s = $Text.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $s = $s.Trim('-')
    if ([string]::IsNullOrWhiteSpace($s)) { $s = 'item' }
    if ($s.Length -gt 48) { $s = $s.Substring(0, 48).TrimEnd('-') }
    return $s
}

function Get-YarnFutureDevPath {
    param([string]$MetraRoot)
    return Join-Path $MetraRoot 'docs\Future-Development.local.md'
}

function Get-YarnStrategicAlignmentForAtlasKind {
    param([string]$AtlasKind)
    switch ($AtlasKind) {
        'Plan' { return 0.15 }
        'Roadmap' { return 0.15 }
        'Parked' { return 0.10 }
        default { return 0.0 }
    }
}

function Test-YarnAtlasStableIdAlreadyScheduled {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$StableId
    )
    $links = @(Get-YarnPlanLinks -Root $Root)
    foreach ($link in $links) {
        $aid = [string](Get-YarnProp -Object $link -Name 'atlasStableId' -Default '')
        if ($aid -and [string]::Equals($aid, $StableId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    $items = @(Get-MetraYarnBacklog -Root $Root)
    foreach ($item in $items) {
        $aid = [string](Get-YarnProp -Object $item -Name 'atlasStableId' -Default '')
        if (-not $aid) {
            $psk = [string](Get-YarnProp -Object $item -Name 'primarySourceKey' -Default '')
            if ($psk -like 'atlas:*') { $aid = $psk.Substring(6) }
        }
        if (-not $aid -or -not [string]::Equals($aid, $StableId, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $path = [string](Get-YarnProp -Object $item -Name 'formalPlanPath' -Default '')
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $true
        }
    }
    return $false
}

function Read-YarnAtlasIdeas {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$MetraRoot,
        [int]$Limit = 80
    )

    $result = [PSCustomObject]@{
        ideas      = @()
        memoryLane = 'ok'
        lastError  = $null
    }
    try {
        if (-not (Test-YarnAtlasAdapterAvailable -MetraRoot $MetraRoot)) {
            throw 'Atlas adapter unavailable'
        }
        $candidates = @(Get-YarnAtlasIntakeCandidates -MetraRoot $MetraRoot -Limit $Limit)
        $ideas = New-Object System.Collections.Generic.List[object]
        foreach ($c in $candidates) {
            $stableId = [string](Get-YarnProp -Object $c -Name 'stableId' -Default '')
            if ([string]::IsNullOrWhiteSpace($stableId)) { continue }
            if (Test-YarnAtlasStableIdAlreadyScheduled -Root $Root -StableId $stableId) { continue }
            $kind = [string](Get-YarnProp -Object $c -Name 'kind' -Default '')
            if ($kind -notin @('Plan', 'Roadmap', 'Parked')) { continue }
            $title = [string](Get-YarnProp -Object $c -Name 'title' -Default $stableId)
            $projectKey = [string](Get-YarnProp -Object $c -Name 'projectKey' -Default 'Metra')
            $sourceText = [string](Get-YarnProp -Object $c -Name 'sourceText' -Default $title)
            [void]$ideas.Add([PSCustomObject]@{
                    title                   = $title
                    primarySourceKey        = "atlas:$stableId"
                    sources                 = @("atlas:$stableId")
                    sourceKind              = 'atlas'
                    atlasStableId           = $stableId
                    memoryLane              = 'atlas'
                    atlasKind               = $kind
                    projectKey              = if ($projectKey) { $projectKey } else { 'Metra' }
                    operatorPriority        = 0
                    urgency                 = 0
                    strategicAlignment      = (Get-YarnStrategicAlignmentForAtlasKind -AtlasKind $kind)
                    boundedTodosPresent     = $false
                    verificationPathPresent = $false
                    riskKnownAndAcceptable  = $false
                    dependenciesResolved    = $true
                    sourceText              = $sourceText
                    health                  = 'ok'
                })
        }
        $result.ideas = @($ideas.ToArray())
        $result.memoryLane = 'ok'
        Save-YarnMemoryLaneState -Root $Root -State 'ok' -LastError $null
    }
    catch {
        $err = [PSCustomObject]@{
            operation = 'atlas-scan'
            message   = $_.Exception.Message
            at        = (Get-Date).ToUniversalTime().ToString('o')
            retryable = $true
        }
        $result.ideas = @()
        $result.memoryLane = 'paused'
        $result.lastError = $err
        Save-YarnMemoryLaneState -Root $Root -State 'paused' -LastError $err
    }
    return $result
}

function Read-YarnFutureDevIdeas {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MetraRoot)

    $path = Get-YarnFutureDevPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) { return @() }

    try {
        $text = [System.IO.File]::ReadAllText($path, (Get-YarnUtf8NoBomEncoding))
    }
    catch {
        # Malformed / unreadable Future-Dev: degrade to empty intake (scan continues).
        return @()
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }

    $ideas = New-Object System.Collections.Generic.List[object]
    $seenStems = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in ($text -split "`n")) {
        $t = $line.TrimEnd("`r")
        # Headings that look like parked ideas (### Title) - skip Contents noise
        if ($t -match '^###\s+(.+)$') {
            $title = $Matches[1].Trim()
            if ([string]::IsNullOrWhiteSpace($title)) { continue }
            if ($title -match '^(Contents|Day-to-day|Buckets|Priority)') { continue }
            if ($title.Length -lt 4) { continue }
            $stem = ConvertTo-YarnSlug -Text $title
            if (-not $seenStems.Add($stem)) {
                # Duplicate heading / same slug: keep first, skip rest.
                continue
            }
            [void]$ideas.Add([PSCustomObject]@{
                    title                   = $title
                    primarySourceKey        = "future-dev:$stem"
                    sources                 = @("future-dev:$stem")
                    sourceKind              = 'future-dev'
                    projectKey              = 'Metra'
                    operatorPriority        = 0
                    urgency                 = 0
                    strategicAlignment      = 0.10
                    boundedTodosPresent     = $false
                    verificationPathPresent = $false
                    riskKnownAndAcceptable  = $false
                    dependenciesResolved    = $true
                    sourceText              = $title
                    health                  = 'ok'
                })
        }
    }
    return @($ideas.ToArray())
}

function Read-YarnCaptureIdeas {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [int]$Limit = 40
    )

    $items = @(Get-YarnCaptureLedger -MetraRoot $MetraRoot -Limit $Limit -Status 'candidate')
    $ideas = New-Object System.Collections.Generic.List[object]
    foreach ($cap in $items) {
        $id = [string](Get-YarnProp -Object $cap -Name 'id' -Default '')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $summary = [string](Get-YarnProp -Object $cap -Name 'summary' -Default '')
        if ([string]::IsNullOrWhiteSpace($summary)) {
            $summary = [string](Get-YarnProp -Object $cap -Name 'text' -Default '')
        }
        if ([string]::IsNullOrWhiteSpace($summary)) {
            $summary = [string](Get-YarnProp -Object $cap -Name 'note' -Default "Capture $id")
        }
        $title = if ($summary.Length -gt 80) { $summary.Substring(0, 80) } else { $summary }
        $routeHint = [string](Get-YarnProp -Object $cap -Name 'suggestedProject' -Default '')
        if ([string]::IsNullOrWhiteSpace($routeHint)) {
            $routeHint = [string](Get-YarnProp -Object $cap -Name 'project' -Default 'Metra')
        }
        $urgency = 0.0
        $tags = @(Get-YarnProp -Object $cap -Name 'tags' -Default @())
        $tagText = ((@($tags) | ForEach-Object { [string]$_ }) -join ' ').ToLowerInvariant()
        if ($tagText -match 'urgent|outage|security') { $urgency = 0.15 }

        [void]$ideas.Add([PSCustomObject]@{
                title                   = $title
                primarySourceKey        = "capture:$id"
                sources                 = @("capture:$id")
                sourceKind              = 'capture'
                captureId               = $id
                projectKey              = if ($routeHint) { $routeHint } else { 'Metra' }
                operatorPriority        = 0
                urgency                 = $urgency
                strategicAlignment      = 0
                boundedTodosPresent     = $false
                verificationPathPresent = $false
                riskKnownAndAcceptable  = $false
                dependenciesResolved    = $true
                sourceText              = $summary
            })
    }
    return @($ideas.ToArray())
}

function Invoke-MetraYarnScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot)
    )

    Initialize-MetraYarnLayout -Root $Root
    $captured = @(Read-YarnCaptureIdeas -MetraRoot $MetraRoot)
    $future = @(Read-YarnFutureDevIdeas -MetraRoot $MetraRoot)
    $atlasResult = Read-YarnAtlasIdeas -Root $Root -MetraRoot $MetraRoot
    $atlas = @($atlasResult.ideas)
    $upserted = New-Object System.Collections.Generic.List[object]
    foreach ($idea in (@($captured) + @($future) + @($atlas))) {
        $map = @{}
        foreach ($p in $idea.PSObject.Properties) { $map[$p.Name] = $p.Value }
        $map['sourceHash'] = Get-YarnSourceHash -NormalizedSourceText ([string]$idea.sourceText)
        $row = Sync-YarnBacklogItem -Root $Root -Incoming (New-YarnPsObject -Map $map) -SkipPlanBoard
        [void]$upserted.Add($row)
    }
    Add-MetraYarnJournalEntry -Root $Root -Entry @{
        op         = 'scan'
        capture    = $captured.Count
        future     = $future.Count
        atlas      = $atlas.Count
        total      = $upserted.Count
        memoryLane = [string]$atlasResult.memoryLane
    }
    return [PSCustomObject]@{
        outcome        = 'scanned'
        captureCount   = $captured.Count
        futureDevCount = $future.Count
        atlasCount     = $atlas.Count
        backlogCount   = @(Get-MetraYarnBacklog -Root $Root).Count
        memoryLane     = [string]$atlasResult.memoryLane
        lastError      = $atlasResult.lastError
        items          = @(Sort-YarnBacklogItems -Items $upserted)
    }
}
