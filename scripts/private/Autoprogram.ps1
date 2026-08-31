# Autoprogram harness — Phase A (Slices 1–2): state foundation + triage preview.
# Queue authority: %LOCALAPPDATA%\Metra\autoprogram\ (mutable item files + append-only journal).

function Get-MetraAutoprogramSchemaVersion {
    return 1
}

function Get-MetraAutoprogramRoot {
    [CmdletBinding()]
    param(
        [string]$OverrideRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($OverrideRoot)) {
        return [System.IO.Path]::GetFullPath($OverrideRoot)
    }
    return Join-Path $env:LOCALAPPDATA 'Metra\autoprogram'
}

function Get-MetraAutoprogramMinimumRoutingConfidence {
    return 0.85
}

function Get-MetraAutoprogramPhaseATransitions {
    [CmdletBinding()]
    param(
        [string]$From
    )

    $map = @{
        '@new'   = @('queued')
        'queued' = @('blocked')
    }
    if ($From) {
        return @($map[[string]$From])
    }
    return $map
}

function Test-MetraAutoprogramTransition {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$From,
        [Parameter(Mandatory)][string]$To
    )

    $fromKey = if ([string]::IsNullOrWhiteSpace($From)) { '@new' } else { [string]$From }
    $allowed = @(Get-MetraAutoprogramPhaseATransitions -From $fromKey)
    return ($allowed -contains $To)
}

function Initialize-MetraAutoprogramLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    foreach ($sub in @('queue', 'journal', 'candidates', 'runs', 'daily', 'locks')) {
        $dir = Join-Path $Root $sub
        if (-not (Test-Path -LiteralPath $dir)) {
            [void][System.IO.Directory]::CreateDirectory($dir)
        }
    }

    $statePath = Join-Path $Root 'state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        $state = [ordered]@{
            schemaVersion = Get-MetraAutoprogramSchemaVersion
            nextQueueSeq  = 1
            nextCandidateSeq = 1
            rubricVersion = 'triage-v1'
            phase         = 'A'
            createdAt     = (Get-Date).ToString('o')
            updatedAt     = (Get-Date).ToString('o')
        }
        Write-MetraAtomicUtf8Text -Path $statePath -Text (($state | ConvertTo-Json -Depth 6) + "`n")
    }
}

function Get-MetraAutoprogramState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    Initialize-MetraAutoprogramLayout -Root $Root
    $path = Join-Path $Root 'state.json'
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return $raw
    }
    catch {
        throw "Autoprogram state unreadable: $path"
    }
}

function Save-MetraAutoprogramState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$State
    )

    $path = Join-Path $Root 'state.json'
    $State.updatedAt = (Get-Date).ToString('o')
    Write-MetraAtomicUtf8Text -Path $path -Text (($State | ConvertTo-Json -Depth 6) + "`n")
}

function Get-MetraAutoprogramJournalPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [datetime]$On = (Get-Date)
    )
    $day = $On.ToString('yyyy-MM-dd')
    return Join-Path (Join-Path $Root 'journal') ("$day.jsonl")
}

function Add-MetraAutoprogramJournalEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][hashtable]$Entry
    )

    $path = Get-MetraAutoprogramJournalPath -Root $Root
    $line = ($Entry | ConvertTo-Json -Compress -Depth 8)
    $enc = Get-MetraUtf8NoBomEncoding
    if (-not (Test-Path -LiteralPath $path)) {
        Write-MetraAtomicUtf8Text -Path $path -Text ($line + "`n")
    }
    else {
        [System.IO.File]::AppendAllText($path, $line + "`n", $enc)
    }
}

function Get-MetraAutoprogramJournalEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ItemId,
        [datetime]$On
    )

    $path = Get-MetraAutoprogramJournalPath -Root $Root -On $On
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }
    $enc = Get-MetraUtf8NoBomEncoding
    $lines = [System.IO.File]::ReadAllLines($path, $enc)
    $entries = @()
    foreach ($line in @($lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            if ($ItemId -and [string](Get-MetraProp -Object $obj -Name 'itemId' -Default '') -ne $ItemId) {
                continue
            }
            $entries += $obj
        }
        catch {
            continue
        }
    }
    return @($entries)
}

function Test-MetraAutoprogramItemId {
    <#
    .SYNOPSIS
        True when Id matches the autoprogram queue (AP-*) or candidate (CAND-*) id shape.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Id,
        [Parameter(Mandatory)][ValidateSet('queue', 'candidate')][string]$Kind
    )

    $trimmed = [string]$Id
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $false }
    if ($trimmed.IndexOfAny([char[]]@('\', '/', ':')) -ge 0) { return $false }
    switch ($Kind) {
        'queue' { return [bool]($trimmed -match '^AP-\d{8}-\d{4}$') }
        'candidate' { return [bool]($trimmed -match '^CAND-\d{8}-\d{4}$') }
        default { return $false }
    }
}

function Resolve-MetraAutoprogramItemPath {
    <#
    .SYNOPSIS
        Build a queue/candidate JSON path under Root after id + containment checks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('queue', 'candidates')][string]$Subfolder
    )

    $kind = if ($Subfolder -eq 'queue') { 'queue' } else { 'candidate' }
    if (-not (Test-MetraAutoprogramItemId -Id $Id -Kind $kind)) {
        throw ("Invalid autoprogram {0} id '{1}'." -f $kind, $Id)
    }

    $dir = Join-Path $Root $Subfolder
    $path = Join-Path $dir ("$Id.json")
    $full = $null
    $rootFull = $null
    try {
        $full = [System.IO.Path]::GetFullPath($path)
        $rootFull = [System.IO.Path]::GetFullPath($Root)
    }
    catch {
        throw ("Invalid autoprogram path for id '{0}'." -f $Id)
    }
    if (-not (Test-MetraPathWithinRoot -Path $full -Root $rootFull)) {
        throw ("Autoprogram path escapes root for id '{0}'." -f $Id)
    }
    return $full
}

function Get-MetraAutoprogramQueueItemPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Id
    )
    return Resolve-MetraAutoprogramItemPath -Root $Root -Id $Id -Subfolder 'queue'
}

function Get-MetraAutoprogramQueueItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Status
    )

    Initialize-MetraAutoprogramLayout -Root $Root
    $dir = Join-Path $Root 'queue'
    $files = @(Get-ChildItem -LiteralPath $dir -Filter 'AP-*.json' -File -ErrorAction SilentlyContinue)
    $items = @()
    foreach ($f in $files) {
        try {
            $item = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
            if ($Status -and [string]$item.status -ne $Status) { continue }
            $items += $item
        }
        catch { continue }
    }
    return @(
        $items | Sort-Object {
            try { [datetime]::Parse([string]$_.updatedAt) } catch { [datetime]::MinValue }
        } -Descending
    )
}

function Get-MetraAutoprogramQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Id
    )

    $path = Get-MetraAutoprogramQueueItemPath -Root $Root -Id $Id
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Save-MetraAutoprogramQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Item
    )

    $path = Get-MetraAutoprogramQueueItemPath -Root $Root -Id ([string]$Item.id)
    Write-MetraAtomicUtf8Text -Path $path -Text (($Item | ConvertTo-Json -Depth 12) + "`n")
}

function Test-MetraAutoprogramQueueItemSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item
    )

    foreach ($prop in @('schemaVersion', 'id', 'summary', 'status', 'createdAt', 'updatedAt')) {
        if (-not ($Item.PSObject.Properties.Name -contains $prop)) {
            throw "Queue item missing required property: $prop"
        }
    }
    if ([int]$Item.schemaVersion -ne (Get-MetraAutoprogramSchemaVersion)) {
        throw "Unsupported queue item schemaVersion: $($Item.schemaVersion)"
    }
    return $true
}

function New-MetraAutoprogramQueueId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    return Invoke-MetraWithNamedMutex -Name 'autoprogram_state' -Script {
        $state = Get-MetraAutoprogramState -Root $Root
        $day = (Get-Date).ToString('yyyyMMdd')
        $seq = [int]$state.nextQueueSeq
        if ($seq -lt 1) { $seq = 1 }
        $id = 'AP-{0}-{1:D4}' -f $day, $seq
        $state.nextQueueSeq = $seq + 1
        Save-MetraAutoprogramState -Root $Root -State $state
        return $id
    }
}

function New-MetraAutoprogramCandidateId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    return Invoke-MetraWithNamedMutex -Name 'autoprogram_state' -Script {
        $state = Get-MetraAutoprogramState -Root $Root
        $day = (Get-Date).ToString('yyyyMMdd')
        $seq = [int]$state.nextCandidateSeq
        if ($seq -lt 1) { $seq = 1 }
        $id = 'CAND-{0}-{1:D4}' -f $day, $seq
        $state.nextCandidateSeq = $seq + 1
        Save-MetraAutoprogramState -Root $Root -State $state
        return $id
    }
}

function Invoke-MetraAutoprogramStateChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId,
        [Parameter(Mandatory)][string]$To,
        [string]$From,
        [string]$Actor = 'operator',
        [string]$Reason = '',
        [scriptblock]$Mutator
    )

    if (-not (Test-MetraAutoprogramTransition -From $From -To $To)) {
        throw "Illegal autoprogram transition: '$From' -> '$To' (Phase A)"
    }

    return Invoke-MetraWithNamedMutex -Name 'autoprogram_queue' -Script {
        $item = Get-MetraAutoprogramQueueItem -Root $Root -Id $ItemId
        if (-not $item -and $From -ne '@new' -and -not [string]::IsNullOrWhiteSpace($From)) {
            throw "Queue item not found: $ItemId"
        }
        if ($item) {
            $current = [string]$item.status
            if ($From -and $From -ne '@new' -and $current -ne $From) {
                throw "Queue item $ItemId status is '$current', expected '$From'"
            }
            if (-not (Test-MetraAutoprogramTransition -From $current -To $To)) {
                throw "Illegal autoprogram transition: '$current' -> '$To' (Phase A)"
            }
        }

        if ($Mutator) {
            $item = & $Mutator $item
        }
        if ($item) {
            $item.status = $To
            $item.updatedAt = (Get-Date).ToString('o')
            Test-MetraAutoprogramQueueItemSchema -Item $item | Out-Null
            Save-MetraAutoprogramQueueItem -Root $Root -Item $item
        }

        Add-MetraAutoprogramJournalEntry -Root $Root -Entry @{
            timestamp = (Get-Date).ToString('o')
            itemId    = $ItemId
            from      = $(if ($From) { $From } elseif ($item) { '@new' } else { '@new' })
            to        = $To
            actor     = $Actor
            reason    = [string]$Reason
        }

        return $item
    }
}

function Get-MetraAutoprogramPlanRoots {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($r in @(Get-MetraInspectPlanRoots -MetraRoot $MetraRoot)) {
        [void]$roots.Add([System.IO.Path]::GetFullPath($r))
    }
    $docs = Join-Path $MetraRoot 'docs'
    if (Test-Path -LiteralPath $docs) {
        [void]$roots.Add([System.IO.Path]::GetFullPath($docs))
    }
    return @($roots | Select-Object -Unique)
}

function Get-MetraAutoprogramFormalPlans {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $files = @()
    foreach ($root in @(Get-MetraAutoprogramPlanRoots -MetraRoot $MetraRoot)) {
        $files += @(Get-ChildItem -LiteralPath $root -Filter '*.plan.md' -File -Recurse -ErrorAction SilentlyContinue)
    }
    $seen = @{}
    $plans = @()
    foreach ($f in ($files | Sort-Object LastWriteTimeUtc -Descending)) {
        $full = [System.IO.Path]::GetFullPath($f.FullName)
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        $parsed = Read-MetraAutoprogramPlanFile -Path $full -MetraRoot $MetraRoot
        if ($parsed) { $plans += $parsed }
    }
    return @($plans)
}

function Read-MetraAutoprogramPlanFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [System.IO.File]::ReadAllText($Path, (Get-MetraUtf8NoBomEncoding))
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $overview = ''
    $todos = @()

    if ($text -match '(?ms)^---\r?\n(.*?)\r?\n---') {
        $yaml = $Matches[1]
        if ($yaml -match '(?m)^name:\s*(.+)$') { $name = $Matches[1].Trim().Trim('"') }
        if ($yaml -match '(?m)^overview:\s*(.+)$') { $overview = $Matches[1].Trim().Trim('"') }
        $todoMatches = [regex]::Matches($yaml, '(?ms)- id:\s*(\S+)\s*\r?\n\s*content:\s*"?(.*?)"?\s*\r?\n\s*status:\s*(\S+)')
        foreach ($m in $todoMatches) {
            $todos += [PSCustomObject]@{
                id      = $m.Groups[1].Value
                content = $m.Groups[2].Value.Trim()
                status  = $m.Groups[3].Value
            }
        }
    }

    $planStatus = 'Unknown'
    if ($text -match '(?mi)\*\*Status:\*\*\s*(.+)') {
        $planStatus = $Matches[1].Trim()
    }
    $approved = ($planStatus -match '(?i)\bApproved\b') -and ($planStatus -notmatch '(?i)\bPending\b')

    $project = Resolve-MetraAutoprogramPlanProject -Path $Path -MetraRoot $MetraRoot -Title $name -Overview $overview

    $verifyCommands = @()
    foreach ($m in [regex]::Matches($text, '(?m)^[\s]*[\\]?\.\\metra\.ps1\s+verify')) {
        $verifyCommands += '.\metra.ps1 verify'
    }
    foreach ($m in [regex]::Matches($text, '(?m)Invoke-Pester\s+([^\r\n`]+)')) {
        $verifyCommands += ('Invoke-Pester ' + $m.Groups[1].Value.Trim())
    }
    $verifyCommands = @($verifyCommands | Select-Object -Unique)

    $doneWhen = @()
    foreach ($m in [regex]::Matches($text, '(?m)^\s*-\s+(.{10,120})$')) {
        $line = $m.Groups[1].Value.Trim()
        if ($line -match '(?i)(pass|accept|must|required|pester|verify|goal|when)') {
            $doneWhen += $line
        }
    }
    if ($doneWhen.Count -gt 5) { $doneWhen = @($doneWhen | Select-Object -First 5) }

    return [PSCustomObject]@{
        path           = $Path
        name           = $name
        overview       = $overview
        planStatus     = $planStatus
        approved       = [bool]$approved
        todos          = @($todos)
        project        = $project
        verifyCommands = @($verifyCommands)
        doneWhen       = @($doneWhen)
        lastWriteUtc   = (Get-Item -LiteralPath $Path).LastWriteTimeUtc
    }
}

function Resolve-MetraAutoprogramPlanProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$Title,
        [string]$Overview
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    $metraFull = [System.IO.Path]::GetFullPath($MetraRoot)
    if (Test-MetraPathWithinRoot -Path $full -Root $metraFull) {
        return [PSCustomObject]@{
            registryName      = 'Metra'
            root              = $metraFull
            routingConfidence = 0.99
            routingEvidence   = 'plan-path-under-metra-root'
        }
    }

    if ($Title -match '(?i)\bmetra\b' -or $Overview -match '(?i)\bmetra\b') {
        return [PSCustomObject]@{
            registryName      = 'Metra'
            root              = $metraFull
            routingConfidence = 0.92
            routingEvidence   = 'plan-title-mentions-metra'
        }
    }

    $query = ("$Title $Overview").Trim()
    if ([string]::IsNullOrWhiteSpace($query)) { $query = $Title }
    try {
        $amb = Get-MetraRoutingAmbiguity -Query $query -SkipTelemetry
        if ($amb.Primary) {
            $route = $amb.Primary
            $score = [int]$route.Score
            $conf = if ($score -ge 2) { 0.90 } elseif ($score -eq 1) { 0.75 } else { 0.50 }
            return [PSCustomObject]@{
                registryName      = [string]$route.Name
                root              = [string]$route.Root
                routingConfidence = $conf
                routingEvidence   = 'routing-ambiguity-primary'
            }
        }
    }
    catch { }

    return [PSCustomObject]@{
        registryName      = ''
        root              = ''
        routingConfidence = 0.0
        routingEvidence   = 'unresolved'
    }
}

function Get-MetraAutoprogramReversibilityPenalty {
    param([string]$Reversibility)
    switch ([string]$Reversibility) {
        'code' { return 0 }
        'config' { return 4 }
        'docs' { return 2 }
        default { return 6 }
    }
}

function Get-MetraAutoprogramRoutingAmbiguityPenalty {
    param([double]$RoutingConfidence)
    if ($RoutingConfidence -ge 0.95) { return 0 }
    if ($RoutingConfidence -ge 0.85) { return 2 }
    return 8
}

function Measure-MetraAutoprogramTriageScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Classification,
        [Parameter(Mandatory)][hashtable]$Scores,
        [Parameter(Mandatory)][object]$Project
    )

    $impact = [int]$Scores.impact
    $confidence = [int]$Scores.confidence
    $userTestBurden = [int]$Scores.userTestBurden
    $autoVerifiable = [int]$Scores.autoVerifiable
    $dependencyValue = [int]$Scores.dependencyValue
    $routingConfidence = [double](Get-MetraProp -Object $Project -Name 'routingConfidence' -Default 0)

    $priority = ($impact * 3) + ($confidence * 2) + ($autoVerifiable * 3) + $dependencyValue `
        - ($userTestBurden * 2) `
        - (Get-MetraAutoprogramReversibilityPenalty -Reversibility ([string]$Classification.reversibility)) `
        - (Get-MetraAutoprogramRoutingAmbiguityPenalty -RoutingConfidence $routingConfidence)

    return [PSCustomObject]@{
        impact            = $impact
        confidence        = $confidence
        userTestBurden    = $userTestBurden
        autoVerifiable    = $autoVerifiable
        dependencyValue   = $dependencyValue
        total             = $priority
        rubricVersion     = 'triage-v1'
    }
}

function Test-MetraAutoprogramEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Classification,
        [Parameter(Mandatory)][object]$Project,
        [Parameter(Mandatory)][object]$Contract,
        [switch]$RequireApprovedPlan
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    if ([string]$Classification.reversibility -ne 'code') {
        [void]$reasons.Add('reversibility-not-code')
    }
    if ([bool]$Classification.crossRoot) { [void]$reasons.Add('cross-root') }
    if ([bool]$Classification.productionTouch) { [void]$reasons.Add('production-touch') }
    if ([bool]$Classification.externalSideEffect) { [void]$reasons.Add('external-side-effect') }
    if ([double]$Project.routingConfidence -lt (Get-MetraAutoprogramMinimumRoutingConfidence)) {
        [void]$reasons.Add('routing-confidence-low')
    }
    if (@($Contract.verifyCommands).Count -eq 0) { [void]$reasons.Add('missing-verify-commands') }
    if (@($Contract.doneWhen).Count -eq 0) { [void]$reasons.Add('missing-done-when') }
    if ($RequireApprovedPlan) { [void]$reasons.Add('formal-plan-not-approved') }

    return [PSCustomObject]@{
        eligible = ($reasons.Count -eq 0)
        reasons  = @($reasons)
    }
}

function Save-MetraAutoprogramCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Candidate
    )

    $path = Resolve-MetraAutoprogramItemPath -Root $Root -Id ([string]$Candidate.id) -Subfolder 'candidates'
    Write-MetraAtomicUtf8Text -Path $path -Text (($Candidate | ConvertTo-Json -Depth 12) + "`n")
    return $Candidate
}

function Get-MetraAutoprogramCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Id
    )

    $path = Resolve-MetraAutoprogramItemPath -Root $Root -Id $Id -Subfolder 'candidates'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Candidate not found: $Id"
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Add-MetraAutoprogramQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Item,
        [string]$Reason = 'enqueue'
    )

    if (-not (Test-MetraAutoprogramTransition -From '@new' -To 'queued')) {
        throw "Illegal autoprogram transition: '@new' -> 'queued' (Phase A)"
    }

    return Invoke-MetraWithNamedMutex -Name 'autoprogram_queue' -Script {
        $Item.status = 'queued'
        $Item.updatedAt = (Get-Date).ToString('o')
        Test-MetraAutoprogramQueueItemSchema -Item $Item | Out-Null
        Save-MetraAutoprogramQueueItem -Root $Root -Item $Item
        Add-MetraAutoprogramJournalEntry -Root $Root -Entry @{
            timestamp = (Get-Date).ToString('o')
            itemId    = [string]$Item.id
            from      = '@new'
            to        = 'queued'
            actor     = 'operator'
            reason    = [string]$Reason
        }
        return $Item
    }
}

function New-MetraAutoprogramQueueItemFromCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Candidate
    )

    if (-not $Candidate.eligible) {
        throw ("Candidate {0} is ineligible: {1}" -f $Candidate.id, (($Candidate.ineligibleReasons) -join ', '))
    }

    $id = New-MetraAutoprogramQueueId -Root $Root
    $now = (Get-Date).ToString('o')
    $branchDay = (Get-Date).ToString('yyyy-MM-dd')
    $projSlug = [string]$Candidate.project.registryName
    if ([string]::IsNullOrWhiteSpace($projSlug)) { $projSlug = 'unknown' }
    $branch = ('autoprogram/{0}/{1}/{2}' -f $projSlug.ToLowerInvariant(), $branchDay, $id).Replace('\', '/')

    $item = [PSCustomObject]@{
        schemaVersion = Get-MetraAutoprogramSchemaVersion
        id            = $id
        summary       = [string]$Candidate.summary
        source        = $Candidate.source
        project       = $Candidate.project
        classification = $Candidate.classification
        scores        = $Candidate.scores
        contract      = $Candidate.contract
        execution     = [PSCustomObject]@{
            maxImplementAttempts = 2
            maxReviewLoops       = 5
            maxChangedFiles      = 10
            maxRuntimeMinutes    = 45
            branch               = $branch
        }
        status    = 'queued'
        evidence  = @()
        createdAt = $now
        updatedAt = $now
    }

    return Add-MetraAutoprogramQueueItem -Root $Root -Item $item -Reason 'enqueue-from-candidate'
}

function Invoke-MetraAutoprogramTriage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$DryRun
    )

    Initialize-MetraAutoprogramLayout -Root $Root
    $dry = $true
    if ($PSBoundParameters.ContainsKey('DryRun') -and -not $DryRun) { $dry = $false }
    # Phase A: triage is always dry-run (no auto-enqueue).

    $results = New-Object System.Collections.Generic.List[object]
    $plans = @(Get-MetraAutoprogramFormalPlans -MetraRoot $MetraRoot)

    foreach ($plan in $plans) {
        $classification = @{
            reversibility        = 'code'
            crossRoot            = $false
            productionTouch      = $false
            externalSideEffect   = $false
            manualTestClass      = 'none'
        }
        $scoresIn = @{
            impact          = $(if ($plan.approved) { 4 } else { 2 })
            confidence      = $(if ($plan.approved) { 5 } else { 2 })
            userTestBurden  = 1
            autoVerifiable  = $(if (@($plan.verifyCommands).Count -gt 0) { 5 } else { 1 })
            dependencyValue = 3
        }
        $contract = [PSCustomObject]@{
            objective      = [string]$plan.overview
            allowedPaths   = @('scripts', 'tests', 'docs')
            forbiddenPaths = @('docs/Decisions.md')
            doneWhen       = @($plan.doneWhen)
            verifyCommands = @($plan.verifyCommands)
        }
        if (@($contract.doneWhen).Count -eq 0 -and $plan.approved) {
            $contract.doneWhen = @('Plan slice acceptance criteria met.')
        }
        if (@($contract.verifyCommands).Count -eq 0 -and $plan.approved) {
            $contract.verifyCommands = @('.\metra.ps1 verify')
        }

        $score = Measure-MetraAutoprogramTriageScore -Classification $classification -Scores $scoresIn -Project $plan.project
        $elig = Test-MetraAutoprogramEligibility -Classification $classification -Project $plan.project -Contract $contract `
            -RequireApprovedPlan:(-not $plan.approved)

        $candId = New-MetraAutoprogramCandidateId -Root $Root
        $candidate = [PSCustomObject]@{
            id                = $candId
            summary           = [string]$plan.name
            source            = [PSCustomObject]@{
                type       = 'formal-plan'
                path       = [string]$plan.path
                planStatus = [string]$plan.planStatus
                approved   = [bool]$plan.approved
            }
            project           = $plan.project
            classification    = $classification
            scores            = $score
            contract          = $contract
            eligible          = [bool]$elig.eligible
            ineligibleReasons = @($elig.reasons)
            dryRun            = $true
            triagedAt         = (Get-Date).ToString('o')
        }
        Save-MetraAutoprogramCandidate -Root $Root -Candidate $candidate | Out-Null
        $results.Add($candidate)
    }

    $captures = @(Get-MetraCaptureLedger -MetraRoot $MetraRoot -Limit 40 -Status candidate)
    foreach ($cap in $captures) {
        $classification = @{
            reversibility        = 'code'
            crossRoot            = $false
            productionTouch      = $false
            externalSideEffect   = $false
            manualTestClass      = 'none'
        }
        $scoresIn = @{
            impact = 2; confidence = 2; userTestBurden = 2; autoVerifiable = 1; dependencyValue = 1
        }
        $contract = [PSCustomObject]@{
            objective = [string]$cap.summary
            allowedPaths = @(); forbiddenPaths = @(); doneWhen = @(); verifyCommands = @()
        }
        $score = Measure-MetraAutoprogramTriageScore -Classification $classification -Scores $scoresIn -Project ([PSCustomObject]@{
            routingConfidence = 0.0
        })
        $elig = Test-MetraAutoprogramEligibility -Classification $classification -Project ([PSCustomObject]@{
            routingConfidence = 0.0
        }) -Contract $contract
        $ineligibleReasons = @($elig.reasons) + @('needs-formal-plan')

        $candId = New-MetraAutoprogramCandidateId -Root $Root
        $candidate = [PSCustomObject]@{
            id                = $candId
            summary           = [string]$cap.summary
            source            = [PSCustomObject]@{
                type = 'capture'
                id   = [string]$cap.id
            }
            project           = [PSCustomObject]@{
                registryName = ''; root = ''; routingConfidence = 0.0; routingEvidence = 'capture-unrouted'
            }
            classification    = $classification
            scores            = $score
            contract          = $contract
            eligible          = $false
            ineligibleReasons = @($ineligibleReasons | Select-Object -Unique)
            dryRun            = $true
            triagedAt         = (Get-Date).ToString('o')
        }
        Save-MetraAutoprogramCandidate -Root $Root -Candidate $candidate | Out-Null
        $results.Add($candidate)
    }

    return [PSCustomObject]@{
        dryRun     = $true
        candidates = @($results | Sort-Object { [int]$_.scores.total } -Descending)
        planCount  = @($plans).Count
        captureCount = @($captures).Count
    }
}

function Invoke-MetraAutoprogramEnqueueFromPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [string]$TodoId,
        [string]$Slice,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $plan = Read-MetraAutoprogramPlanFile -Path $full -MetraRoot $MetraRoot
    if (-not $plan) { throw "Plan not found: $full" }
    if (-not $plan.approved) {
        throw "Plan is not Approved (status: $($plan.planStatus)). Daily Bing review required before enqueue."
    }

    $summary = [string]$plan.name
    if ($TodoId) {
        $todo = @($plan.todos | Where-Object { $_.id -eq $TodoId } | Select-Object -First 1)
        if (-not $todo) { throw "Todo id not found in plan: $TodoId" }
        $summary = "$($plan.name) — $($todo.content)"
    }
    elseif ($Slice) {
        $summary = "$($plan.name) — slice $Slice"
    }

    $classification = @{
        reversibility = 'code'; crossRoot = $false; productionTouch = $false
        externalSideEffect = $false; manualTestClass = 'none'
    }
    $scoresIn = @{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 3 }
    $contract = [PSCustomObject]@{
        objective      = [string]$plan.overview
        allowedPaths   = @('scripts', 'tests', 'docs')
        forbiddenPaths = @('docs/Decisions.md')
        doneWhen       = @($(if (@($plan.doneWhen).Count -gt 0) { $plan.doneWhen } else { 'Plan slice acceptance criteria met.' }))
        verifyCommands = @($(if (@($plan.verifyCommands).Count -gt 0) { $plan.verifyCommands } else { '.\metra.ps1 verify' }))
    }
    $score = Measure-MetraAutoprogramTriageScore -Classification $classification -Scores $scoresIn -Project $plan.project
    $elig = Test-MetraAutoprogramEligibility -Classification $classification -Project $plan.project -Contract $contract
    if (-not $elig.eligible) {
        throw ("Plan ineligible for enqueue: {0}" -f (($elig.reasons) -join ', '))
    }

    $source = [PSCustomObject]@{
        type         = 'formal-plan'
        path         = $full
        todoOrSlice  = $(if ($TodoId) { $TodoId } elseif ($Slice) { $Slice } else { $null })
        planStatus   = [string]$plan.planStatus
        bingReviewed = $true
    }

    $cand = [PSCustomObject]@{
        id             = 'direct-plan'
        summary        = $summary
        source         = $source
        project        = $plan.project
        classification = $classification
        scores         = $score
        contract       = $contract
        eligible       = $true
        ineligibleReasons = @()
    }
    return New-MetraAutoprogramQueueItemFromCandidate -Root $Root -Candidate $cand
}

function Invoke-MetraAutoprogramDailyStub {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-MetraRoot),
        [datetime]$Date = (Get-Date)
    )

    Initialize-MetraAutoprogramLayout -Root $Root
    $day = $Date.ToString('yyyy-MM-dd')
    $path = Join-Path (Join-Path $Root 'daily') ("$day-intake.md")

    $pending = @(
        Get-MetraAutoprogramFormalPlans -MetraRoot $MetraRoot |
            Where-Object { -not $_.approved }
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Metra Daily Intake")
    [void]$sb.AppendLine("Date: $day")
    [void]$sb.AppendLine("Phase: A (stub — pack-diff and approve ship in Slice 5)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 1. Overarching changes made')
    [void]$sb.AppendLine('(none — Phase A stub)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 2. Manual testing required')
    [void]$sb.AppendLine('(none — Phase A stub)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 3. Next plan(s) for review')
    if (@($pending).Count -eq 0) {
        [void]$sb.AppendLine('(none pending)')
    }
    else {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| Plan | Path | Status |')
        [void]$sb.AppendLine('|------|------|--------|')
        foreach ($p in $pending) {
            [void]$sb.AppendLine("| $($p.name) | $($p.path) | $($p.planStatus) |")
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Archive candidates (knowledge score ≥ 5)')
    [void]$sb.AppendLine('(none — Slice 8 deferred)')

    Write-MetraAtomicUtf8Text -Path $path -Text $sb.ToString()
    return [PSCustomObject]@{ path = $path; phase = 'A-stub'; pendingPlans = @($pending).Count }
}

function Invoke-MetraAutoprogramCommand {
    <#
    .SYNOPSIS
        CLI: autoprogram triage|enqueue|plans|status|show|block|daily
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = Get-MetraAutoprogramRoot
    }
    Initialize-MetraAutoprogramLayout -Root $Root

    switch ($Subcommand.ToLowerInvariant()) {
        'status' {
            $items = @(Get-MetraAutoprogramQueueItems -Root $Root)
            $byStatus = @{}
            foreach ($i in $items) {
                $s = [string]$i.status
                if (-not $byStatus.ContainsKey($s)) { $byStatus[$s] = 0 }
                $byStatus[$s]++
            }
            return [PSCustomObject]@{
                root       = $Root
                phase      = 'A'
                totalItems = @($items).Count
                byStatus   = $byStatus
            }
        }
        'show' {
            $id = $null
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Id' -and ($i + 1) -lt $ArgsRest.Count) {
                    $id = [string]$ArgsRest[$i + 1]
                }
            }
            if ([string]::IsNullOrWhiteSpace($id)) { throw 'autoprogram show -Id <AP-...>' }
            $item = Get-MetraAutoprogramQueueItem -Root $Root -Id $id
            if (-not $item) { throw "Queue item not found: $id" }
            return $item
        }
        'block' {
            $id = $null
            $reason = 'operator-block'
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Id' -and ($i + 1) -lt $ArgsRest.Count) { $id = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-Reason' -and ($i + 1) -lt $ArgsRest.Count) { $reason = [string]$ArgsRest[$i + 1]; $i++ }
            }
            if ([string]::IsNullOrWhiteSpace($id)) { throw 'autoprogram block -Id <AP-...> [-Reason "..."]' }
            return Invoke-MetraAutoprogramStateChange -Root $Root -ItemId $id -From 'queued' -To 'blocked' -Reason $reason
        }
        'enqueue' {
            $candidateId = $null
            $fromPlan = $false
            $planPath = $null
            $todoId = $null
            $slice = $null
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-CandidateId' -and ($i + 1) -lt $ArgsRest.Count) { $candidateId = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-FromPlan') { $fromPlan = $true }
                elseif ($ArgsRest[$i] -eq '-Path' -and ($i + 1) -lt $ArgsRest.Count) { $planPath = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-TodoId' -and ($i + 1) -lt $ArgsRest.Count) { $todoId = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-Slice' -and ($i + 1) -lt $ArgsRest.Count) { $slice = [string]$ArgsRest[$i + 1]; $i++ }
            }
            if ($fromPlan) {
                if ([string]::IsNullOrWhiteSpace($planPath)) { throw 'autoprogram enqueue -FromPlan -Path <plan.md> [-TodoId id] [-Slice name]' }
                return Invoke-MetraAutoprogramEnqueueFromPlan -Root $Root -Path $planPath -TodoId $todoId -Slice $slice -MetraRoot $MetraRoot
            }
            if ([string]::IsNullOrWhiteSpace($candidateId)) {
                throw 'autoprogram enqueue requires -CandidateId <id> or -FromPlan -Path <plan.md>'
            }
            $candidate = Get-MetraAutoprogramCandidate -Root $Root -Id $candidateId
            return New-MetraAutoprogramQueueItemFromCandidate -Root $Root -Candidate $candidate
        }
        'triage' {
            $explicitDry = $true
            if ($ArgsRest -contains '-DryRun') { $explicitDry = $true }
            return Invoke-MetraAutoprogramTriage -Root $Root -MetraRoot $MetraRoot -DryRun:$explicitDry
        }
        'plans' {
            if ($ArgsRest.Count -eq 0) { throw 'autoprogram plans requires list|show|pending' }
            $plansSub = [string]$ArgsRest[0]
            switch ($plansSub.ToLowerInvariant()) {
                'list' {
                    return ,@(Get-MetraAutoprogramFormalPlans -MetraRoot $MetraRoot)
                }
                'pending' {
                    return ,@(
                        Get-MetraAutoprogramFormalPlans -MetraRoot $MetraRoot |
                            Where-Object { -not $_.approved }
                    )
                }
                'show' {
                    $planPath = $null
                    for ($i = 1; $i -lt $ArgsRest.Count; $i++) {
                        if ($ArgsRest[$i] -eq '-Path' -and ($i + 1) -lt $ArgsRest.Count) {
                            $planPath = [string]$ArgsRest[$i + 1]
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($planPath)) { throw 'autoprogram plans show -Path <plan.md>' }
                    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($planPath)
                    $plan = Read-MetraAutoprogramPlanFile -Path $full -MetraRoot $MetraRoot
                    if (-not $plan) { throw "Plan not found: $full" }
                    return $plan
                }
                default { throw "Unknown autoprogram plans subcommand: $plansSub" }
            }
        }
        'daily' {
            return Invoke-MetraAutoprogramDailyStub -Root $Root -MetraRoot $MetraRoot
        }
        default {
            throw "Unknown autoprogram subcommand: $Subcommand. Use triage|enqueue|plans|status|show|block|daily."
        }
    }
}
