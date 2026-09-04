# Loom harness — queue, journal, triage, runner.
# Queue authority: %LOCALAPPDATA%\Metra\loom\ (mutable item files + append-only journal).

function Get-MetraLoomSchemaVersion {
    return 1
}

function Resolve-MetraLoomRoot {
    [CmdletBinding()]
    param(
        [string]$OverrideRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($OverrideRoot)) {
        return [PSCustomObject]@{
            Path       = [System.IO.Path]::GetFullPath($OverrideRoot)
            Source     = 'Explicit'
            IsReadOnly = $false
            IsLegacy   = $false
        }
    }

    $envRoot = [Environment]::GetEnvironmentVariable('METRA_LOOM_ROOT')
    if (-not [string]::IsNullOrWhiteSpace($envRoot)) {
        if (-not [System.IO.Path]::IsPathRooted($envRoot)) {
            throw 'METRA_LOOM_ROOT must be an absolute path.'
        }
        return [PSCustomObject]@{
            Path       = [System.IO.Path]::GetFullPath($envRoot)
            Source     = 'Environment'
            IsReadOnly = $false
            IsLegacy   = $false
        }
    }

    $loomRoot = Get-LoomDefaultStorageRoot
    $marker = Get-LoomMigrationMarker -LoomRoot $loomRoot
    if ($marker -and [string]$marker.status -eq 'completed') {
        return [PSCustomObject]@{
            Path       = $loomRoot
            Source     = 'Loom'
            IsReadOnly = $false
            IsLegacy   = $false
        }
    }

    if (Test-LoomDirectoryHasData -Path $loomRoot) {
        return [PSCustomObject]@{
            Path       = $loomRoot
            Source     = 'Loom'
            IsReadOnly = $false
            IsLegacy   = $false
        }
    }

    $legacyRoot = Get-LoomLegacyStorageRoot
    if (Test-Path -LiteralPath $legacyRoot) {
        return [PSCustomObject]@{
            Path       = $legacyRoot
            Source     = 'Legacy'
            IsReadOnly = $true
            IsLegacy   = $true
        }
    }

    if (-not (Test-Path -LiteralPath $loomRoot)) {
        [void][System.IO.Directory]::CreateDirectory($loomRoot)
    }
    return [PSCustomObject]@{
        Path       = $loomRoot
        Source     = 'Loom'
        IsReadOnly = $false
        IsLegacy   = $false
    }
}

function Get-MetraLoomRoot {
    [CmdletBinding()]
    param(
        [string]$OverrideRoot
    )

    return (Resolve-MetraLoomRoot -OverrideRoot $OverrideRoot).Path
}

function Assert-LoomRootWritable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$OverrideRoot
    )

    $resolved = Resolve-MetraLoomRoot -OverrideRoot $OverrideRoot
    if ($resolved.IsReadOnly -and [string]::Equals($resolved.Path, $Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Loom storage at '$Root' is legacy read-only. Run: .\metra.ps1 loom migrate -Apply -Confirm"
    }
}

function Get-MetraLoomMinimumRoutingConfidence {
    return 0.85
}

function Get-MetraLoomPhaseATransitions {
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


function Get-LoomStatusCatalog {
    <#
    .SYNOPSIS
        Full lifecycle status enum (authority catalog). Phase A activates a subset.
    #>
    return @(
        '@new', 'queued', 'claimed', 'implementing', 'reviewing', 'blocked',
        'completed', 'accepted-pending-commit', 'accepted', 'rejected', 'failed',
        'needsManualTest', 'superseded'
    )
}

function Get-LoomActiveTransitions {
    <#
    .SYNOPSIS
        Active transition map for the current phase (Slice 3 enables run lifecycle).
    #>
    [CmdletBinding()]
    param([string]$From)
    $map = Get-LoomActiveTransitionMap
    if ($From) {
        $key = [string]$From
        if (-not $map.ContainsKey($key)) { return @() }
        return @($map[$key])
    }
    return $map
}
function Test-MetraLoomTransition {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$From,
        [Parameter(Mandatory)][string]$To
    )

    $fromKey = if ([string]::IsNullOrWhiteSpace($From)) { '@new' } else { [string]$From }
    $allowed = @(Get-LoomActiveTransitions -From $fromKey)
    return ($allowed -contains $To)
}

function Initialize-MetraLoomLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    foreach ($sub in @('queue', 'journal', 'candidates', 'runs', 'daily', 'locks', 'patterns')) {
        $dir = Join-Path $Root $sub
        if (-not (Test-Path -LiteralPath $dir)) {
            [void][System.IO.Directory]::CreateDirectory($dir)
        }
    }

    $statePath = Join-Path $Root 'state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        $state = [ordered]@{
            schemaVersion = Get-MetraLoomSchemaVersion
            nextQueueSeq  = 1
            nextCandidateSeq = 1
            rubricVersion = 'triage-v1'
            phase         = 'A'
            createdAt     = (Get-Date).ToString('o')
            updatedAt     = (Get-Date).ToString('o')
        }
        Write-LoomAtomicUtf8Text -Path $statePath -Text (($state | ConvertTo-Json -Depth 6) + "`n")
    }
}

function Get-MetraLoomState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    Initialize-MetraLoomLayout -Root $Root
    $path = Join-Path $Root 'state.json'
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return $raw
    }
    catch {
        throw "Loom state unreadable: $path"
    }
}

function Save-MetraLoomState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$State
    )

    $path = Join-Path $Root 'state.json'
    $State.updatedAt = (Get-Date).ToString('o')
    Write-LoomAtomicUtf8Text -Path $path -Text (($State | ConvertTo-Json -Depth 6) + "`n")
}

function Get-MetraLoomJournalPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [datetime]$On = (Get-Date)
    )
    $day = $On.ToString('yyyy-MM-dd')
    return Join-Path (Join-Path $Root 'journal') ("$day.jsonl")
}

function Add-MetraLoomJournalEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][hashtable]$Entry
    )

    $normalized = @{}
    foreach ($key in $Entry.Keys) {
        $normalized[[string]$key] = $Entry[$key]
    }
    if (-not $normalized.ContainsKey('timestamp') -or [string]::IsNullOrWhiteSpace([string]$normalized['timestamp'])) {
        $normalized['timestamp'] = (Get-Date).ToString('o')
    }
    if (-not $normalized.ContainsKey('from')) {
        $normalized['from'] = ''
    }
    if (-not $normalized.ContainsKey('actor') -or [string]::IsNullOrWhiteSpace([string]$normalized['actor'])) {
        $normalized['actor'] = 'operator'
    }
    Test-LoomContract -Schema 'journal-entry' -Object $normalized | Out-Null

    $path = Get-MetraLoomJournalPath -Root $Root
    $line = ($normalized | ConvertTo-Json -Compress -Depth 8)
    $enc = Get-LoomUtf8NoBomEncoding
    if (-not (Test-Path -LiteralPath $path)) {
        Write-LoomAtomicUtf8Text -Path $path -Text ($line + "`n")
    }
    else {
        [System.IO.File]::AppendAllText($path, $line + "`n", $enc)
    }
}

function Get-MetraLoomJournalEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ItemId,
        [datetime]$On
    )

    $path = Get-MetraLoomJournalPath -Root $Root -On $On
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }
    $enc = Get-LoomUtf8NoBomEncoding
    $lines = [System.IO.File]::ReadAllLines($path, $enc)
    $entries = @()
    foreach ($line in @($lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            if ($ItemId -and [string](Get-LoomProp -Object $obj -Name 'itemId' -Default '') -ne $ItemId) {
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

function Test-MetraLoomItemId {
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

function Resolve-MetraLoomItemPath {
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
    if (-not (Test-MetraLoomItemId -Id $Id -Kind $kind)) {
        throw ("Invalid Loom {0} id '{1}'." -f $kind, $Id)
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
        throw ("Invalid Loom path for id '{0}'." -f $Id)
    }
    if (-not (Test-LoomPathWithinRoot -Path $full -Root $rootFull)) {
        throw ("Loom path escapes root for id '{0}'." -f $Id)
    }
    return $full
}

function Get-MetraLoomQueueItemPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Id
    )
    return Resolve-MetraLoomItemPath -Root $Root -Id $Id -Subfolder 'queue'
}

function Get-MetraLoomQueueItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Status
    )

    $dir = Join-Path $Root 'queue'
    if (-not (Test-Path -LiteralPath $dir)) {
        return @()
    }
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

function Get-MetraLoomQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Id
    )

    $path = Get-MetraLoomQueueItemPath -Root $Root -Id $Id
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Save-MetraLoomQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Item
    )

    Test-MetraLoomQueueItemSchema -Item $Item | Out-Null
    $path = Get-MetraLoomQueueItemPath -Root $Root -Id ([string]$Item.id)
    Write-LoomAtomicUtf8Text -Path $path -Text (($Item | ConvertTo-Json -Depth 12) + "`n")
}

function Test-MetraLoomQueueItemSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item
    )

    Test-LoomContract -Schema 'queue-item' -Object $Item | Out-Null
    return $true
}

function New-MetraLoomQueueId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    return Invoke-LoomWithNamedMutex -Name 'loom_state' -Script {
        $state = Get-MetraLoomState -Root $Root
        $day = (Get-Date).ToString('yyyyMMdd')
        $seq = [int]$state.nextQueueSeq
        if ($seq -lt 1) { $seq = 1 }
        $id = 'AP-{0}-{1:D4}' -f $day, $seq
        $state.nextQueueSeq = $seq + 1
        Save-MetraLoomState -Root $Root -State $state
        return $id
    }
}

function New-MetraLoomCandidateId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    return Invoke-LoomWithNamedMutex -Name 'loom_state' -Script {
        $state = Get-MetraLoomState -Root $Root
        $day = (Get-Date).ToString('yyyyMMdd')
        $seq = [int]$state.nextCandidateSeq
        if ($seq -lt 1) { $seq = 1 }
        $id = 'CAND-{0}-{1:D4}' -f $day, $seq
        $state.nextCandidateSeq = $seq + 1
        Save-MetraLoomState -Root $Root -State $state
        return $id
    }
}

function Invoke-MetraLoomStateChange {
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

    $itemPreview = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
    $transitionFrom = if ($From) {
        $From
    }
    elseif ($itemPreview) {
        [string]$itemPreview.status
    }
    else {
        '@new'
    }
    if (-not (Test-MetraLoomTransition -From $transitionFrom -To $To)) {
        throw "Illegal Loom transition: '$transitionFrom' -> '$To' (Phase A)"
    }

    if ($transitionFrom -eq 'completed' -and $To -ne 'completed' -and -not $script:LoomDailyApproveActive) {
        throw "Illegal Loom transition: only Invoke-MetraLoomDailyApprove may exit 'completed' (attempted -> '$To')"
    }

    return Invoke-LoomWithNamedMutex -Name 'loom_queue' -Script {
        $item = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
        $priorStatus = '@new'
        if (-not $item -and $From -ne '@new' -and -not [string]::IsNullOrWhiteSpace($From)) {
            throw "Queue item not found: $ItemId"
        }
        if ($item) {
            $current = [string]$item.status
            $priorStatus = $current
            if ($From -and $From -ne '@new' -and $current -ne $From) {
                throw "Queue item $ItemId status is '$current', expected '$From'"
            }
            if (-not (Test-MetraLoomTransition -From $current -To $To)) {
                throw "Illegal Loom transition: '$current' -> '$To' (Phase A)"
            }
        }

        if ($Mutator) {
            $item = & $Mutator $item
        }
        if ($item) {
            if ($To -eq 'blocked') {
                $existingFrom = [string](Get-LoomProp -Object $item -Name 'blockedFrom' -Default '')
                if ([string]::IsNullOrWhiteSpace($existingFrom) -and $priorStatus -and $priorStatus -ne '@new') {
                    $item | Add-Member -NotePropertyName blockedFrom -NotePropertyValue $priorStatus -Force
                }
            }
            $item.status = $To
            $item.updatedAt = (Get-Date).ToString('o')
            Test-MetraLoomQueueItemSchema -Item $item | Out-Null
            Save-MetraLoomQueueItem -Root $Root -Item $item
        }

        $journalFrom = if ($From) {
            $From
        }
        elseif ($priorStatus -and $priorStatus -ne '@new') {
            $priorStatus
        }
        else {
            '@new'
        }

        Add-MetraLoomJournalEntry -Root $Root -Entry @{
            timestamp = (Get-Date).ToString('o')
            itemId    = $ItemId
            from      = $journalFrom
            to        = $To
            actor     = $Actor
            reason    = [string]$Reason
        }

        return $item
    }
}

function Get-MetraLoomPlanRoots {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($r in @(Get-LoomInspectPlanRoots -MetraRoot $MetraRoot)) {
        [void]$roots.Add([System.IO.Path]::GetFullPath($r))
    }
    # Loom handoff copies live under plans\; docs\ is legacy + human docs.
    foreach ($rel in @('docs', 'plans')) {
        $dir = Join-Path $MetraRoot $rel
        if (Test-Path -LiteralPath $dir) {
            [void]$roots.Add([System.IO.Path]::GetFullPath($dir))
        }
    }
    return @($roots | Select-Object -Unique)
}

function Test-MetraLoomFormalPlanPathAllowed {
    <#
    .SYNOPSIS
        True when Path is under an allowed formal plan root (inspect plan roots + Metra plans/docs).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    foreach ($root in @(Get-MetraLoomPlanRoots -MetraRoot $MetraRoot)) {
        if (Test-LoomPathWithinRoot -Path $full -Root $root) {
            return $true
        }
    }
    return $false
}

function Get-MetraLoomFormalPlans {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    $files = @()
    foreach ($root in @(Get-MetraLoomPlanRoots -MetraRoot $MetraRoot)) {
        $files += @(Get-ChildItem -LiteralPath $root -Filter '*.plan.md' -File -Recurse -ErrorAction SilentlyContinue)
    }
    $seen = @{}
    $plans = @()
    foreach ($f in ($files | Sort-Object LastWriteTimeUtc -Descending)) {
        $full = [System.IO.Path]::GetFullPath($f.FullName)
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        $parsed = Read-MetraLoomPlanFile -Path $full -MetraRoot $MetraRoot
        if ($parsed) { $plans += $parsed }
    }
    return @($plans)
}

function Read-MetraLoomPlanFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [System.IO.File]::ReadAllText($Path, (Get-LoomUtf8NoBomEncoding))
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
    $bingReviewed = $false
    $fmStatus = $null
    if ($text -match '(?ms)^---\r?\n(.*?)\r?\n---') {
        $yamlBlock = $Matches[1]
        if ($yamlBlock -match '(?m)^status:\s*(.+)$') {
            $fmStatus = $Matches[1].Trim().Trim('"').Trim("'")
        }
        if ($yamlBlock -match '(?m)^bingReviewed:\s*(true|yes)\s*$') {
            $bingReviewed = $true
        }
        elseif ($yamlBlock -match '(?m)^bingReviewed:\s*(false|no)\s*$') {
            $bingReviewed = $false
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($fmStatus)) {
        $planStatus = $fmStatus
    }
    elseif ($text -match '(?mi)\*\*Status:\*\*\s*(.+)') {
        $planStatus = $Matches[1].Trim()
    }
    $approved = ($planStatus -match '(?i)\bApproved\b') -and ($planStatus -notmatch '(?i)\bPending\b')
    if ($bingReviewed -and ($planStatus -match '(?i)^approved$')) {
        $approved = $true
    }

    $project = Resolve-MetraLoomPlanProject -Path $Path -MetraRoot $MetraRoot -Title $name -Overview $overview

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

    $patternIds = @(Get-MetraPlanPatternIds -PlanText $text)

    return [PSCustomObject]@{
        path           = $Path
        name           = $name
        overview       = $overview
        planStatus     = $planStatus
        bingReviewed   = [bool]$bingReviewed
        approved       = [bool]$approved
        todos          = @($todos)
        project        = $project
        verifyCommands = @($verifyCommands)
        doneWhen       = @($doneWhen)
        patterns       = @($patternIds)
        lastWriteUtc   = (Get-Item -LiteralPath $Path).LastWriteTimeUtc
    }
}

function Resolve-MetraLoomPlanProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$MetraRoot = (Get-LoomHostRoot),
        [string]$Title,
        [string]$Overview
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    $metraFull = [System.IO.Path]::GetFullPath($MetraRoot)
    if (Test-LoomPathWithinRoot -Path $full -Root $metraFull) {
        return [PSCustomObject]@{
            registryName      = 'Metra'
            root              = $metraFull
            routingConfidence = 0.99
            routingEvidence   = 'plan-path-under-metra-root'
        }
    }

    if (Test-LoomRoutingAdapterAvailable) {
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
            $amb = Get-LoomRoutingAmbiguity -Query $query -SkipTelemetry
            if ($amb.Mode -ne 'adapter-unavailable' -and $amb.Primary) {
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
    }

    return [PSCustomObject]@{
        registryName      = ''
        root              = ''
        routingConfidence = 0.0
        routingEvidence   = 'unresolved'
    }
}

function Get-MetraLoomReversibilityPenalty {
    param([string]$Reversibility)
    switch ([string]$Reversibility) {
        'code' { return 0 }
        'config' { return 4 }
        'docs' { return 2 }
        default { return 6 }
    }
}

function Get-MetraLoomRoutingAmbiguityPenalty {
    param([double]$RoutingConfidence)
    if ($RoutingConfidence -ge 0.95) { return 0 }
    if ($RoutingConfidence -ge 0.85) { return 2 }
    return 8
}

function Measure-MetraLoomTriageScore {
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
    $routingConfidence = [double](Get-LoomProp -Object $Project -Name 'routingConfidence' -Default 0)

    $priority = ($impact * 3) + ($confidence * 2) + ($autoVerifiable * 3) + $dependencyValue `
        - ($userTestBurden * 2) `
        - (Get-MetraLoomReversibilityPenalty -Reversibility ([string]$Classification.reversibility)) `
        - (Get-MetraLoomRoutingAmbiguityPenalty -RoutingConfidence $routingConfidence)

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

function Test-MetraLoomEligibility {
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
    if ([double]$Project.routingConfidence -lt (Get-MetraLoomMinimumRoutingConfidence)) {
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

function Save-MetraLoomCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Candidate
    )

    Test-LoomContract -Schema 'triage-candidate' -Object $Candidate | Out-Null
    $path = Resolve-MetraLoomItemPath -Root $Root -Id ([string]$Candidate.id) -Subfolder 'candidates'
    Write-LoomAtomicUtf8Text -Path $path -Text (($Candidate | ConvertTo-Json -Depth 12) + "`n")
    return $Candidate
}

function Get-MetraLoomCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Id
    )

    $path = Resolve-MetraLoomItemPath -Root $Root -Id $Id -Subfolder 'candidates'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Candidate not found: $Id"
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Add-MetraLoomQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Item,
        [string]$Reason = 'enqueue'
    )

    if (-not (Test-MetraLoomTransition -From '@new' -To 'queued')) {
        throw "Illegal Loom transition: '@new' -> 'queued' (Phase A)"
    }

    return Invoke-LoomWithNamedMutex -Name 'loom_queue' -Script {
        $Item.status = 'queued'
        $Item.updatedAt = (Get-Date).ToString('o')
        Test-MetraLoomQueueItemSchema -Item $Item | Out-Null
        Save-MetraLoomQueueItem -Root $Root -Item $Item
        Add-MetraLoomJournalEntry -Root $Root -Entry @{
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

function New-MetraLoomQueueItemFromCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Candidate
    )

    if (-not $Candidate.eligible) {
        throw ("Candidate {0} is ineligible: {1}" -f $Candidate.id, (($Candidate.ineligibleReasons) -join ', '))
    }

    $registry = [string](Get-LoomProp -Object $Candidate.project -Name 'registryName' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($registry)) {
        Assert-LoomProjectAcceptanceGate -Root $Root -RegistryName $registry
    }

    $id = New-MetraLoomQueueId -Root $Root
    $now = (Get-Date).ToString('o')
    $branchDay = (Get-Date).ToString('yyyy-MM-dd')
    $projSlug = [string]$Candidate.project.registryName
    if ([string]::IsNullOrWhiteSpace($projSlug)) { $projSlug = 'unknown' }
    $branch = ('loom/{0}/{1}/{2}' -f $projSlug.ToLowerInvariant(), $branchDay, $id).Replace('\', '/')

    $projectKey = [string]$registry.Trim()
    if ([string]::IsNullOrWhiteSpace($projectKey)) {
        $projectKey = [string](Get-LoomProp -Object $Candidate -Name 'projectKey' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($projectKey)) {
        throw 'Queue item requires canonical projectKey (or project.registryName).'
    }

    $item = [PSCustomObject]@{
        schemaVersion = Get-MetraLoomSchemaVersion
        id            = $id
        summary       = [string]$Candidate.summary
        source        = $Candidate.source
        project       = $Candidate.project
        projectKey    = $projectKey.Trim()
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

    return Add-MetraLoomQueueItem -Root $Root -Item $item -Reason 'enqueue-from-candidate'
}

function Invoke-MetraLoomTriage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-LoomHostRoot),
        [switch]$DryRun
    )

    Initialize-MetraLoomLayout -Root $Root
    $dry = $true
    if ($PSBoundParameters.ContainsKey('DryRun') -and -not $DryRun) { $dry = $false }
    # Phase A: triage is always dry-run (no auto-enqueue).

    $results = New-Object System.Collections.Generic.List[object]
    $plans = @(Get-MetraLoomFormalPlans -MetraRoot $MetraRoot)

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

        $score = Measure-MetraLoomTriageScore -Classification $classification -Scores $scoresIn -Project $plan.project
        $elig = Test-MetraLoomEligibility -Classification $classification -Project $plan.project -Contract $contract `
            -RequireApprovedPlan:(-not $plan.approved)

        $candId = New-MetraLoomCandidateId -Root $Root
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
        Save-MetraLoomCandidate -Root $Root -Candidate $candidate | Out-Null
        $results.Add($candidate)
    }

    # A4 ritual split: Capture no longer becomes a Loom candidate through normal triage.
    return [PSCustomObject]@{
        dryRun                  = $true
        candidates              = @($results | Sort-Object { [int]$_.scores.total } -Descending)
        planCount               = @($plans).Count
        captureCount            = 0
        captureTriageRemoved    = $true
        captureAdapterAvailable = (Test-LoomCaptureAdapterAvailable)
    }
}

function Get-MetraLoomHandoffContractVersion {
    return 1
}

function ConvertTo-MetraLoomNormalizedPlanPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    return $full.TrimEnd('\', '/')
}

function Get-MetraLoomYarnPlanIdentity {
    <#
    .SYNOPSIS
        Idempotency key: projectKey + Windows-normalized full plan path (case-insensitive).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectKey,
        [Parameter(Mandatory)][string]$PlanPath
    )
    $key = [string]$ProjectKey.Trim().ToLowerInvariant()
    $norm = (ConvertTo-MetraLoomNormalizedPlanPath -Path $PlanPath).ToLowerInvariant()
    return ('{0}|{1}' -f $key, $norm)
}

function Test-MetraLoomYarnApprovedPlanPathAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ProjectKey,
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    $full = ConvertTo-MetraLoomNormalizedPlanPath -Path $Path
    if (Test-MetraLoomFormalPlanPathAllowed -Path $full -MetraRoot $MetraRoot) {
        return $true
    }

    $key = [string]$ProjectKey.Trim()
    if ($key -match '[\\/]' -or $key -match '\.\.' -or $key -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        return $false
    }
    $parent = Split-Path -Parent $MetraRoot
    $projectRoot = [System.IO.Path]::GetFullPath((Join-Path $parent $key))
    foreach ($rel in @('docs', 'plans')) {
        $dir = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $rel))
        if (Test-LoomPathWithinRoot -Path $full -Root $dir) {
            return $true
        }
    }
    return $false
}

function Test-MetraLoomYarnRankSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RankSnapshot)

    if ($null -eq $RankSnapshot) {
        throw 'rankSnapshot is required for Yarn-approved plan ingest.'
    }
    foreach ($name in @('total', 'effectiveImpact', 'completionReady', 'rubricVersion', 'rankReasons')) {
        $prop = $RankSnapshot.PSObject.Properties[$name]
        if (-not $prop) {
            throw "rankSnapshot missing required field: $name"
        }
    }
    return $true
}

function Find-MetraLoomQueueItemByYarnHandoff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PlanIdentity,
        [Parameter(Mandatory)][string]$ApprovalRevision
    )

    foreach ($item in @(Get-MetraLoomQueueItems -Root $Root)) {
        $handoff = Get-LoomProp -Object $item -Name 'yarnHandoff' -Default $null
        if ($null -eq $handoff) { continue }
        $idMatch = [string](Get-LoomProp -Object $handoff -Name 'planIdentity' -Default '')
        $revMatch = [string](Get-LoomProp -Object $handoff -Name 'approvalRevision' -Default '')
        if ($idMatch -eq $PlanIdentity -and $revMatch -eq $ApprovalRevision) {
            return $item
        }
    }
    return $null
}

function Invoke-MetraLoomIngestApprovedPlan {
    <#
    .SYNOPSIS
        Yarn→Loom handoff: ingest an Approved formal plan with idempotent identity (A3).
        Does not change lane scheduling or Capture triage semantics.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$ProjectKey,
        [Parameter(Mandatory)][string]$ApprovalRevision,
        [Parameter(Mandatory)][string]$ApprovalId,
        [Parameter(Mandatory)]$RankSnapshot,
        [Parameter(Mandatory)][int]$HandoffContractVersion,
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    if ([string]::IsNullOrWhiteSpace($PlanPath)) { throw 'PlanPath is required.' }
    if ([string]::IsNullOrWhiteSpace($ProjectKey)) { throw 'ProjectKey is required.' }
    if ([string]::IsNullOrWhiteSpace($ApprovalRevision)) { throw 'ApprovalRevision is required.' }
    if ([string]::IsNullOrWhiteSpace($ApprovalId)) { throw 'ApprovalId is required.' }

    $expectedHandoff = Get-MetraLoomHandoffContractVersion
    if ([int]$HandoffContractVersion -ne [int]$expectedHandoff) {
        throw ("handoffContractVersion $HandoffContractVersion (expected $expectedHandoff)")
    }
    [void](Test-MetraLoomYarnRankSnapshot -RankSnapshot $RankSnapshot)

    $full = ConvertTo-MetraLoomNormalizedPlanPath -Path $PlanPath
    if (-not (Test-Path -LiteralPath $full)) {
        throw "Plan not found: $full"
    }
    if (-not (Test-MetraLoomYarnApprovedPlanPathAllowed -Path $full -ProjectKey $ProjectKey -MetraRoot $MetraRoot)) {
        throw "Plan path is not under an allowed formal plan root for projectKey '$ProjectKey': $full"
    }

    $plan = Read-MetraLoomPlanFile -Path $full -MetraRoot $MetraRoot
    if (-not $plan) { throw "Plan not found: $full" }
    if (-not $plan.approved) {
        throw "Plan is not Approved (status: $($plan.planStatus)). Yarn human approval required before ingest."
    }

    $planIdentity = Get-MetraLoomYarnPlanIdentity -ProjectKey $ProjectKey -PlanPath $full
    $existing = Find-MetraLoomQueueItemByYarnHandoff -Root $Root -PlanIdentity $planIdentity -ApprovalRevision $ApprovalRevision
    if ($existing) {
        return [PSCustomObject]@{
            outcome          = 'idempotent'
            queueItemId      = [string]$existing.id
            item             = $existing
            planIdentity     = $planIdentity
            approvalRevision = $ApprovalRevision
            approvalId       = $ApprovalId
        }
    }

    Initialize-MetraLoomLayout -Root $Root

    $project = $plan.project
    if ([string]::IsNullOrWhiteSpace([string](Get-LoomProp -Object $project -Name 'registryName' -Default ''))) {
        $project = [PSCustomObject]@{
            registryName      = $ProjectKey
            root              = ''
            routingConfidence = 0.95
            routingEvidence   = 'yarn-projectKey'
        }
    }
    elseif ([string]$project.registryName -ne $ProjectKey) {
        # Prefer Yarn's canonical projectKey for identity; keep routing metadata.
        $project = [PSCustomObject]@{
            registryName      = $ProjectKey
            root              = [string](Get-LoomProp -Object $project -Name 'root' -Default '')
            routingConfidence = [double](Get-LoomProp -Object $project -Name 'routingConfidence' -Default 0.9)
            routingEvidence   = ('yarn-projectKey-override:' + [string](Get-LoomProp -Object $project -Name 'routingEvidence' -Default ''))
        }
    }

    $classification = @{
        reversibility      = 'code'
        crossRoot          = $false
        productionTouch    = $false
        externalSideEffect = $false
        manualTestClass    = 'none'
    }
    $scoresIn = @{
        impact          = 4
        confidence      = 5
        userTestBurden  = 1
        autoVerifiable  = 5
        dependencyValue = 3
    }
    $contract = [PSCustomObject]@{
        objective      = [string]$plan.overview
        allowedPaths   = @('scripts', 'tests', 'docs')
        forbiddenPaths = @('docs/Decisions.md')
        doneWhen       = @($(if (@($plan.doneWhen).Count -gt 0) { $plan.doneWhen } else { 'Plan slice acceptance criteria met.' }))
        verifyCommands = @($(if (@($plan.verifyCommands).Count -gt 0) { $plan.verifyCommands } else { '.\metra.ps1 verify' }))
    }
    $score = Measure-MetraLoomTriageScore -Classification $classification -Scores $scoresIn -Project $project
    $elig = Test-MetraLoomEligibility -Classification $classification -Project $project -Contract $contract
    if (-not $elig.eligible) {
        throw ("Plan ineligible for ingest: {0}" -f (($elig.reasons) -join ', '))
    }

    $source = [PSCustomObject]@{
        type           = 'yarn-approved-plan'
        path           = $full
        planStatus     = [string]$plan.planStatus
        bingReviewed   = $true
        approvalId     = $ApprovalId
        approvalRevision = $ApprovalRevision
    }

    $cand = [PSCustomObject]@{
        id                = 'yarn-approved'
        summary           = [string]$plan.name
        source            = $source
        project           = $project
        classification    = $classification
        scores            = $score
        contract          = $contract
        eligible          = $true
        ineligibleReasons = @()
    }

    $item = New-MetraLoomQueueItemFromCandidate -Root $Root -Candidate $cand
    $item | Add-Member -NotePropertyName projectKey -NotePropertyValue ([string]$ProjectKey.Trim()) -Force
    $item | Add-Member -NotePropertyName yarnHandoff -NotePropertyValue ([PSCustomObject]@{
            planIdentity           = $planIdentity
            projectKey             = $ProjectKey
            approvalId             = $ApprovalId
            approvalRevision       = $ApprovalRevision
            handoffContractVersion = [int]$HandoffContractVersion
            rankSnapshot           = $RankSnapshot
            ingestedAt             = (Get-Date).ToUniversalTime().ToString('o')
        }) -Force
    if ($RankSnapshot -and $item.scores) {
        $ei = Get-LoomProp -Object $RankSnapshot -Name 'effectiveImpact' -Default $null
        if ($null -ne $ei) {
            $item.scores | Add-Member -NotePropertyName effectiveImpact -NotePropertyValue $ei -Force
        }
        $tot = Get-LoomProp -Object $RankSnapshot -Name 'total' -Default $null
        if ($null -ne $tot) {
            $item.scores | Add-Member -NotePropertyName total -NotePropertyValue $tot -Force
        }
    }
    Save-MetraLoomQueueItem -Root $Root -Item $item
    Add-MetraLoomJournalEntry -Root $Root -Entry @{
        timestamp = (Get-Date).ToString('o')
        itemId    = [string]$item.id
        from      = 'queued'
        to        = 'queued'
        actor     = 'yarn-handoff'
        reason    = ('ingest-approved-plan:' + $ApprovalRevision)
    }

    return [PSCustomObject]@{
        outcome          = 'enqueued'
        queueItemId      = [string]$item.id
        item             = $item
        planIdentity     = $planIdentity
        approvalRevision = $ApprovalRevision
        approvalId       = $ApprovalId
    }
}

function Invoke-MetraLoomEnqueueFromPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [string]$TodoId,
        [string]$Slice,
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-MetraLoomFormalPlanPathAllowed -Path $full -MetraRoot $MetraRoot)) {
        throw "Plan path is not under an allowed formal plan root: $full"
    }
    $plan = Read-MetraLoomPlanFile -Path $full -MetraRoot $MetraRoot
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
    $score = Measure-MetraLoomTriageScore -Classification $classification -Scores $scoresIn -Project $plan.project
    $elig = Test-MetraLoomEligibility -Classification $classification -Project $plan.project -Contract $contract
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
    return New-MetraLoomQueueItemFromCandidate -Root $Root -Candidate $cand
}

function Invoke-LoomCommand {
    <#
    .SYNOPSIS
        CLI: loom triage|enqueue|plans|status|show|block|run|review|loop|daily|pattern|migrate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-LoomHostRoot),
        [string]$Root
    )

    $explicitRoot = -not [string]::IsNullOrWhiteSpace($Root)
    if (-not $explicitRoot) {
        $Root = (Resolve-MetraLoomRoot).Path
    }
    else {
        $Root = (Resolve-MetraLoomRoot -OverrideRoot $Root).Path
    }

    $mutating = @('run', 'block', 'enqueue', 'migrate', 'review', 'daily', 'loop', 'pattern')
    if ($mutating -contains $Subcommand.ToLowerInvariant()) {
        Assert-LoomRootWritable -Root $Root -OverrideRoot $(if ($explicitRoot) { $Root } else { $null })
    }

    if ($Subcommand.ToLowerInvariant() -ne 'migrate') {
        $resolved = Resolve-MetraLoomRoot -OverrideRoot $(if ($explicitRoot) { $Root } else { $null })
        if (-not $resolved.IsReadOnly) {
            Initialize-MetraLoomLayout -Root $Root
        }
    }

    switch ($Subcommand.ToLowerInvariant()) {
        'status' {
            $items = @(Get-MetraLoomQueueItems -Root $Root)
            $byStatus = @{}
            foreach ($i in $items) {
                $s = [string]$i.status
                if (-not $byStatus.ContainsKey($s)) { $byStatus[$s] = 0 }
                $byStatus[$s]++
            }
            return [PSCustomObject]@{
                root       = $Root
                phase      = '3'
                totalItems = @($items).Count
                byStatus   = $byStatus
            }
        }
        'run' {
            $id = $null
            $dry = $false
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Id' -and ($i + 1) -lt $ArgsRest.Count) { $id = [string]$ArgsRest[$i + 1]; $i++ }
                elseif ($ArgsRest[$i] -eq '-DryRun') { $dry = $true }
            }
            if ([string]::IsNullOrWhiteSpace($id)) { throw 'loom run -Id <AP-...> [-DryRun] [-Confirm] [-NoChainReview]' }
            if ($dry) {
                return Invoke-MetraLoomRun -Root $Root -ItemId $id -MetraRoot $MetraRoot -DryRun
            }
            if ($ArgsRest -notcontains '-Confirm') {
                throw 'loom run requires -Confirm for live execution (git branch + implementer).'
            }
            return Invoke-MetraLoomRun -Root $Root -ItemId $id -MetraRoot $MetraRoot -Confirm -ChainReview:$(-not ($ArgsRest -contains '-NoChainReview'))
        }
        'review' {
            $id = $null
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Id' -and ($i + 1) -lt $ArgsRest.Count) { $id = [string]$ArgsRest[$i + 1]; $i++ }
            }
            if ([string]::IsNullOrWhiteSpace($id)) { throw 'loom review -Id <AP-...> [-Confirm]' }
            $live = $ArgsRest -contains '-Confirm'
            if ($live) {
                return Invoke-MetraLoomReview -Root $Root -ItemId $id -MetraRoot $MetraRoot -Confirm
            }
            return Invoke-MetraLoomReview -Root $Root -ItemId $id -MetraRoot $MetraRoot -DryRun
        }
        'show' {
            $id = $null
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Id' -and ($i + 1) -lt $ArgsRest.Count) {
                    $id = [string]$ArgsRest[$i + 1]
                }
            }
            if ([string]::IsNullOrWhiteSpace($id)) { throw 'loom show -Id <AP-...>' }
            $item = Get-MetraLoomQueueItem -Root $Root -Id $id
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
            if ([string]::IsNullOrWhiteSpace($id)) { throw 'loom block -Id <AP-...> [-Reason "..."]' }
            return Invoke-MetraLoomStateChange -Root $Root -ItemId $id -From 'queued' -To 'blocked' -Reason $reason
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
                if ([string]::IsNullOrWhiteSpace($planPath)) { throw 'loom enqueue -FromPlan -Path <plan.md> [-TodoId id] [-Slice name]' }
                return Invoke-MetraLoomEnqueueFromPlan -Root $Root -Path $planPath -TodoId $todoId -Slice $slice -MetraRoot $MetraRoot
            }
            if ([string]::IsNullOrWhiteSpace($candidateId)) {
                throw 'loom enqueue requires -CandidateId <id> or -FromPlan -Path <plan.md>'
            }
            $candidate = Get-MetraLoomCandidate -Root $Root -Id $candidateId
            return New-MetraLoomQueueItemFromCandidate -Root $Root -Candidate $candidate
        }
        'triage' {
            $explicitDry = $true
            if ($ArgsRest -contains '-DryRun') { $explicitDry = $true }
            return Invoke-MetraLoomTriage -Root $Root -MetraRoot $MetraRoot -DryRun:$explicitDry
        }
        'plans' {
            if ($ArgsRest.Count -eq 0) { throw 'loom plans requires list|show|pending' }
            $plansSub = [string]$ArgsRest[0]
            switch ($plansSub.ToLowerInvariant()) {
                'list' {
                    return ,@(Get-MetraLoomFormalPlans -MetraRoot $MetraRoot)
                }
                'pending' {
                    return ,@(
                        Get-MetraLoomFormalPlans -MetraRoot $MetraRoot |
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
                    if ([string]::IsNullOrWhiteSpace($planPath)) { throw 'loom plans show -Path <plan.md>' }
                    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($planPath)
                    $plan = Read-MetraLoomPlanFile -Path $full -MetraRoot $MetraRoot
                    if (-not $plan) { throw "Plan not found: $full" }
                    return $plan
                }
                default { throw "Unknown loom plans subcommand: $plansSub" }
            }
        }
        'daily' {
            if ($ArgsRest.Count -eq 0) {
                return Invoke-MetraLoomDailyBuild -Root $Root -MetraRoot $MetraRoot
            }
            $dailySub = [string]$ArgsRest[0]
            switch ($dailySub.ToLowerInvariant()) {
                'pack-diff' {
                    $reviewDate = $null
                    for ($i = 1; $i -lt $ArgsRest.Count; $i++) {
                        if ($ArgsRest[$i] -eq '-ReviewDate' -and ($i + 1) -lt $ArgsRest.Count) {
                            $reviewDate = [string]$ArgsRest[$i + 1]; $i++
                        }
                    }
                    return Invoke-MetraLoomDailyPackDiff -Root $Root -MetraRoot $MetraRoot -ReviewDate $reviewDate
                }
                'approve' {
                    $planPath = $null
                    $reviewDate = $null
                    $overrideReason = $null
                    for ($i = 1; $i -lt $ArgsRest.Count; $i++) {
                        if ($ArgsRest[$i] -eq '-PlanPath' -and ($i + 1) -lt $ArgsRest.Count) {
                            $planPath = [string]$ArgsRest[$i + 1]; $i++
                        }
                        elseif ($ArgsRest[$i] -eq '-ReviewDate' -and ($i + 1) -lt $ArgsRest.Count) {
                            $reviewDate = [string]$ArgsRest[$i + 1]; $i++
                        }
                        elseif ($ArgsRest[$i] -eq '-OverrideReason' -and ($i + 1) -lt $ArgsRest.Count) {
                            $overrideReason = [string]$ArgsRest[$i + 1]; $i++
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($planPath)) {
                        throw 'loom daily approve -PlanPath <path> [-Confirm] [-Merge] [-ReviewDate] [-OverrideManualTest] [-OverrideReason]'
                    }
                    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($planPath)
                    $params = @{
                        Root     = $Root
                        PlanPath = $full
                    }
                    if ($reviewDate) { $params['ReviewDate'] = $reviewDate }
                    if ($ArgsRest -contains '-Confirm') { $params['Confirm'] = $true }
                    if ($ArgsRest -contains '-Merge') { $params['Merge'] = $true }
                    if ($ArgsRest -contains '-OverrideManualTest') { $params['OverrideManualTest'] = $true }
                    if ($overrideReason) { $params['OverrideReason'] = $overrideReason }
                    return Invoke-MetraLoomDailyApprove @params
                }
                default {
                    throw "Unknown loom daily subcommand: $dailySub. Use daily | daily pack-diff | daily approve."
                }
            }
        }
        'loop' {
            $untilGate = $ArgsRest -contains '-UntilDailyGate'
            $dry = $ArgsRest -contains '-DryRun'
            if (-not $untilGate) {
                throw 'loom loop requires -UntilDailyGate [-DryRun] [-Confirm]'
            }
            $params = @{
                Root            = $Root
                MetraRoot       = $MetraRoot
                UntilDailyGate  = $true
            }
            if ($dry) { $params['DryRun'] = $true }
            if ($ArgsRest -contains '-Confirm') { $params['Confirm'] = $true }
            return Invoke-MetraLoomLoop @params
        }
        'migrate' {
            $apply = ($ArgsRest -contains '-Apply')
            $force = ($ArgsRest -contains '-Force')
            $params = @{}
            if ($apply) { $params['Apply'] = $true }
            if ($force) { $params['Force'] = $true }
            if ($ArgsRest -contains '-Confirm') { $params['Confirm'] = $true }
            return Invoke-MetraLoomMigrate @params
        }
        'pattern' {
            if ($ArgsRest.Count -eq 0) {
                throw 'loom pattern requires score|promote'
            }
            $patSub = [string]$ArgsRest[0]
            switch ($patSub.ToLowerInvariant()) {
                'score' {
                    $itemId = $null
                    for ($i = 1; $i -lt $ArgsRest.Count; $i++) {
                        if ($ArgsRest[$i] -eq '-ItemId' -and ($i + 1) -lt $ArgsRest.Count) {
                            $itemId = [string]$ArgsRest[$i + 1]; $i++
                        }
                    }
                    $params = @{ Root = $Root; MetraRoot = $MetraRoot }
                    if ($itemId) { $params['ItemId'] = $itemId }
                    return Invoke-MetraLoomPatternScore @params
                }
                'promote' {
                    $path = $null
                    $itemId = $null
                    for ($i = 1; $i -lt $ArgsRest.Count; $i++) {
                        if ($ArgsRest[$i] -eq '-Path' -and ($i + 1) -lt $ArgsRest.Count) {
                            $path = [string]$ArgsRest[$i + 1]; $i++
                        }
                        elseif ($ArgsRest[$i] -eq '-ItemId' -and ($i + 1) -lt $ArgsRest.Count) {
                            $itemId = [string]$ArgsRest[$i + 1]; $i++
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($path)) {
                        throw 'loom pattern promote -Path <one-pattern.md> [-ItemId AP-...] [-Preview|-Confirm] [-Publish]'
                    }
                    $params = @{
                        Root      = $Root
                        Path      = $path
                        MetraRoot = $MetraRoot
                    }
                    if ($itemId) { $params['ItemId'] = $itemId }
                    if ($ArgsRest -contains '-Preview') { $params['Preview'] = $true }
                    if ($ArgsRest -contains '-Confirm') { $params['Confirm'] = $true }
                    if ($ArgsRest -contains '-Publish') { $params['Publish'] = $true }
                    return Invoke-MetraLoomPatternPromote @params
                }
                default {
                    throw "Unknown loom pattern subcommand: $patSub. Use score|promote."
                }
            }
        }
        default {
            throw "Unknown loom subcommand: $Subcommand. Use triage|enqueue|plans|status|show|block|run|review|loop|daily|pattern|migrate."
        }
    }
}
