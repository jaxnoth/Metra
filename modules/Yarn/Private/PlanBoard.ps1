# Plan Board projection (Notion). Yarn/Loom remain authoritative. Fail-open; no Notion required.

$script:YarnPlanBoardOverride = $null
$script:YarnPlanBoardHttpTimeoutSec = 15
$script:YarnPlanBoardUnconfiguredWarned = $false

function Get-YarnPlanBoardStageLabels {
    # Regular Hashtable so integer lookup is by key (OrderedDictionary int indexer is by index).
    # v2: Backlog inserted at 2; Idea..Drop shift to 3..8.
    return @{
        1 = 'Inbox'
        2 = 'Backlog'
        3 = 'Idea'
        4 = 'Active'
        5 = 'Loom'
        6 = 'Shipped'
        7 = 'Parked'
        8 = 'Drop'
    }
}

function Get-YarnPlanBoardBoardToStage {
    $labels = Get-YarnPlanBoardStageLabels
    $map = @{}
    foreach ($k in $labels.Keys) {
        $map[[string]$labels[$k]] = [int]$k
    }
    return $map
}

function Test-YarnPlanBoardRecognizedBoard {
    param([string]$Board)
    if ([string]::IsNullOrWhiteSpace($Board)) { return $false }
    $map = Get-YarnPlanBoardBoardToStage
    return $map.ContainsKey($Board.Trim())
}

function Get-YarnPlanBoardStageForBoard {
    param([string]$Board)
    if (-not (Test-YarnPlanBoardRecognizedBoard -Board $Board)) { return $null }
    $map = Get-YarnPlanBoardBoardToStage
    return [int]$map[$Board.Trim()]
}

function Test-YarnPlanBoardSideTabBoard {
    param([string]$Board)
    $b = [string]$Board
    return ($b -in @('Inbox', 'Backlog', 'Drop'))
}

function New-YarnPlanBoardEmptySummary {
    <#
    .SYNOPSIS
        Stable public summary contract for sync and inventory apply.
    #>
    return [ordered]@{
        scanned           = 0
        proposed          = 0
        applied           = 0
        unchanged         = 0
        skippedReview     = 0
        skippedStale      = 0
        identityConflicts = 0
        failed            = 0
        notionUnavailable = $false
        DryRun            = $false
        Actions           = @()
        Updated           = 0
        Created           = 0
        Skipped           = 0
    }
}

function Get-YarnPlanBoardSettingsPath {
    param([Parameter(Mandatory)][string]$Root)
    # Default Root is Get-MetraYarnRoot => %LOCALAPPDATA%\Metra\yarn
    return Join-Path $Root 'plan-board.settings.json'
}

function Get-YarnPlanBoardSyncStatePath {
    param([Parameter(Mandatory)][string]$Root)
    return Join-Path $Root 'plan-board-sync.json'
}

function Get-YarnPlanBoardConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot
    )
    $path = Get-YarnPlanBoardSettingsPath -Root $Root
    $cfg = $null
    if (Test-Path -LiteralPath $path) {
        try {
            $cfg = Read-YarnJsonFile -Path $path
        }
        catch {
            $cfg = $null
        }
    }
    # Example JSON is documentation only - never used as a live runtime fallback
    # (example DatabaseId + Atlas token would otherwise look "configured").
    $databaseId = [string](Get-YarnProp -Object $cfg -Name 'DatabaseId' -Default '')
    $dataSourceId = [string](Get-YarnProp -Object $cfg -Name 'DataSourceId' -Default '')
    $timeout = Get-YarnProp -Object $cfg -Name 'HttpTimeoutSec' -Default 15
    try { $timeoutSec = [int]$timeout } catch { $timeoutSec = 15 }
    if ($timeoutSec -lt 1) { $timeoutSec = 15 }
    $token = Get-YarnPlanBoardNotionApiKey -MetraRoot $MetraRoot
    $configured = (-not [string]::IsNullOrWhiteSpace($databaseId)) -and (-not [string]::IsNullOrWhiteSpace($token))
    return [PSCustomObject]@{
        DatabaseId     = $databaseId.Trim()
        DataSourceId   = $dataSourceId.Trim()
        HttpTimeoutSec = $timeoutSec
        HasToken       = -not [string]::IsNullOrWhiteSpace($token)
        Configured     = $configured
        SettingsPath   = $path
    }
}

function Get-YarnPlanBoardNotionApiKey {
    [CmdletBinding()]
    param([string]$MetraRoot)
    if (-not [string]::IsNullOrWhiteSpace($env:METRA_NOTION_API_KEY)) {
        return ([string]$env:METRA_NOTION_API_KEY).Trim()
    }
    $atlas = Get-YarnAtlasProjectPath -MetraRoot $MetraRoot
    if ([string]::IsNullOrWhiteSpace($atlas)) { return $null }
    $settings = Join-Path $atlas 'config\settings.json'
    if (-not (Test-Path -LiteralPath $settings)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($settings, (Get-YarnUtf8NoBomEncoding))
        $j = $raw | ConvertFrom-Json
        $key = [string](Get-YarnProp -Object (Get-YarnProp -Object (Get-YarnProp -Object $j -Name 'providers' -Default $null) -Name 'notion' -Default $null) -Name 'apiKey' -Default '')
        if ([string]::IsNullOrWhiteSpace($key)) { return $null }
        return $key.Trim()
    }
    catch {
        return $null
    }
}

function Get-YarnPlanBoardCursorPlanName {
    param([string]$PathOrName)
    if ([string]::IsNullOrWhiteSpace($PathOrName)) { return '' }
    $s = $PathOrName.Trim().Trim('"')
    if ($s -match '[\\/]') {
        return [System.IO.Path]::GetFileName($s)
    }
    return $s
}

function Test-YarnPlanBoardCursorPlanMatch {
    param(
        [string]$Left,
        [string]$Right
    )
    $a = Get-YarnPlanBoardCursorPlanName -PathOrName $Left
    $b = Get-YarnPlanBoardCursorPlanName -PathOrName $Right
    if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)) {
        return $false
    }
    return [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-LoomPlanBoardActiveQueueStatus {
    param([string]$Status)
    $s = [string]$Status
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    $terminal = @('accepted', 'rejected', 'failed', 'superseded', '@new')
    if ($terminal -contains $s) { return $false }
    $active = @(
        'queued', 'claimed', 'implementing', 'reviewing', 'blocked',
        'completed', 'accepted-pending-commit', 'needsManualTest'
    )
    return ($active -contains $s)
}

function Test-LoomPlanBoardVerifiedAccepted {
    param($Item)
    if ($null -eq $Item) { return $false }
    if ([string](Get-YarnProp -Object $Item -Name 'status' -Default '') -ne 'accepted') { return $false }
    $cv = Get-YarnProp -Object $Item -Name 'commitVerification' -Default $null
    $state = [string](Get-YarnProp -Object $cv -Name 'state' -Default '')
    # Accepted is only persisted after local verify; treat status=accepted as verified.
    if ([string]::IsNullOrWhiteSpace($state)) { return $true }
    return ($state -eq 'verified')
}

function Resolve-YarnPlanBoardProjection {
    <#
    .SYNOPSIS
        Explicit precedence resolver (not integer max). Returns Board+Stage pair or Skip.
        v2 stages: Inbox/1, Backlog/2, Idea/3, Active/4, Loom/5, Shipped/6, Parked/7, Drop/8.
    #>
    [CmdletBinding()]
    param(
        [string]$CursorPlan,
        [string]$YarnStatus,
        [string]$YarnId,
        [bool]$HandoffSucceeded = $false,
        [bool]$HasActiveLoomQueue = $false,
        [bool]$VerifiedLoomAccepted = $false,
        [bool]$ExistingPlanBoardCard = $false,
        [string]$ExistingBoard = '',
        [bool]$HasFormalPlan = $false,
        [ValidateSet('', 'keep', 'drop', 'park')]
        [string]$InventoryDecision = '',
        [string]$Title
    )

    $name = Get-YarnPlanBoardCursorPlanName -PathOrName $CursorPlan
    $labels = Get-YarnPlanBoardStageLabels
    $ys = [string]$YarnStatus
    $inv = [string]$InventoryDecision

    function New-YarnPlanBoardProj {
        param($Stage, [string]$Signal, [string]$Action = 'project')
        $stageVal = $Stage
        $boardVal = $null
        if ($null -ne $Stage) {
            $stageVal = [int]$Stage
            $boardVal = [string]($labels[$stageVal])
        }
        return [PSCustomObject]@{
            action     = $Action
            CursorPlan = $name
            YarnId     = $YarnId
            Stage      = $stageVal
            Board      = $boardVal
            Title      = $Title
            signal     = $Signal
        }
    }

    # 1. Verified Loom accepted
    if ($VerifiedLoomAccepted) {
        return (New-YarnPlanBoardProj -Stage 6 -Signal 'verified-loom-accepted')
    }
    # 2. Authoritative Yarn rejected
    if ($ys -eq 'rejected') {
        return (New-YarnPlanBoardProj -Stage 8 -Signal 'yarn-rejected')
    }
    # 3. Affirmed inventory Drop
    if ($inv -eq 'drop') {
        return (New-YarnPlanBoardProj -Stage 8 -Signal 'inventory-drop')
    }
    # 4. Authoritative Yarn parked
    if ($ys -eq 'parked') {
        return (New-YarnPlanBoardProj -Stage 7 -Signal 'yarn-parked')
    }
    # 5. Affirmed inventory Park
    if ($inv -eq 'park') {
        return (New-YarnPlanBoardProj -Stage 7 -Signal 'inventory-park')
    }
    # 6. Handoff success or active Loom queue
    if ($HandoffSucceeded -or $HasActiveLoomQueue) {
        $sig = $(if ($HandoffSucceeded) { 'loom-handoff' } else { 'active-loom-queue' })
        return (New-YarnPlanBoardProj -Stage 5 -Signal $sig)
    }
    # 7. Yarn approved
    if ($ys -eq 'approved') {
        return (New-YarnPlanBoardProj -Stage 5 -Signal 'yarn-approved')
    }
    # 8. Yarn pending-bing or stale-pack
    if ($ys -in @('pending-bing', 'stale-pack')) {
        return (New-YarnPlanBoardProj -Stage 4 -Signal "yarn-$ys")
    }
    # 9-10. Yarn idea|ready with/without formal plan
    if ($ys -in @('idea', 'ready')) {
        if ($HasFormalPlan) {
            return (New-YarnPlanBoardProj -Stage 3 -Signal "yarn-$ys")
        }
        return (New-YarnPlanBoardProj -Stage 2 -Signal "yarn-$ys-backlog")
    }
    # 11-12. Affirmed inventory Keep
    if ($inv -eq 'keep') {
        if ($HasFormalPlan) {
            return (New-YarnPlanBoardProj -Stage 3 -Signal 'inventory-keep-formal')
        }
        return (New-YarnPlanBoardProj -Stage 2 -Signal 'inventory-keep-backlog')
    }
    # 13-14. Existing card only (no authoritative Yarn/Loom/inventory signal)
    if ($ExistingPlanBoardCard) {
        $eb = [string]$ExistingBoard
        if (Test-YarnPlanBoardSideTabBoard -Board $eb) {
            $stage = Get-YarnPlanBoardStageForBoard -Board $eb
            return [PSCustomObject]@{
                action     = 'project'
                CursorPlan = $name
                YarnId     = $YarnId
                Stage      = $stage
                Board      = $eb.Trim()
                Title      = $Title
                signal     = 'existing-side-tab-preserve'
            }
        }
        if ((Test-YarnPlanBoardRecognizedBoard -Board $eb) -and -not (Test-YarnPlanBoardSideTabBoard -Board $eb)) {
            # Recognized lean Board with no signal: still preserve label + normalize Stage
            $stage = Get-YarnPlanBoardStageForBoard -Board $eb
            return [PSCustomObject]@{
                action     = 'project'
                CursorPlan = $name
                YarnId     = $YarnId
                Stage      = $stage
                Board      = $eb.Trim()
                Title      = $Title
                signal     = 'existing-board-normalize'
            }
        }
        # Unresolved / unknown / empty Board
        return (New-YarnPlanBoardProj -Stage 1 -Signal 'existing-card-inbox')
    }
    # 15. No source and no existing card
    return (New-YarnPlanBoardProj -Stage $null -Signal 'no-authoritative-signal' -Action 'skip')
}

function Resolve-YarnPlanBoardHealProjection {
    <#
    .SYNOPSIS
        Apply Board-canonical heal rules for an existing card + resolved projection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Projection,
        [string]$ExistingBoard = '',
        [object]$ExistingStage = $null
    )
    if ([string]$Projection.action -ne 'project') { return $Projection }
    $labels = Get-YarnPlanBoardStageLabels
    $board = [string]$Projection.Board
    $stage = [int]$Projection.Stage

    # Authoritative projection already has Board+Stage from resolver; ensure Stage matches Board.
    if (Test-YarnPlanBoardRecognizedBoard -Board $board) {
        $expected = Get-YarnPlanBoardStageForBoard -Board $board
        if ($stage -ne $expected) {
            $stage = $expected
        }
        return [PSCustomObject]@{
            action     = $Projection.action
            CursorPlan = $Projection.CursorPlan
            YarnId     = $Projection.YarnId
            Stage      = $stage
            Board      = $board
            Title      = $Projection.Title
            signal     = $Projection.signal
        }
    }

    # Missing/unknown Board on projection should not happen for project action; heal to Inbox if needed.
    return [PSCustomObject]@{
        action     = 'project'
        CursorPlan = $Projection.CursorPlan
        YarnId     = $Projection.YarnId
        Stage      = 1
        Board      = [string]$labels[1]
        Title      = $Projection.Title
        signal     = 'heal-inbox'
    }
}

function Write-YarnPlanBoardSyncError {
    [CmdletBinding()]
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$CursorPlan,
        [string]$Message,
        [Parameter(Mandatory)][string]$Root
    )
    $msg = $Message
    if ([string]::IsNullOrWhiteSpace($msg) -and $ErrorRecord) {
        $msg = [string]$ErrorRecord.Exception.Message
    }
    # Never persist tokens / Authorization headers
    $msg = [regex]::Replace([string]$msg, '(?i)(Bearer\s+)\S+', '$1***')
    $msg = [regex]::Replace($msg, '(?i)(api[_-]?key["''\s:=]+)[^\s,"'']+', '$1***')
    $err = [PSCustomObject]@{
        operation  = 'plan-board-sync'
        message    = $msg
        cursorPlan = (Get-YarnPlanBoardCursorPlanName -PathOrName $CursorPlan)
        at         = (Get-Date).ToUniversalTime().ToString('o')
        retryable  = $true
    }
    try {
        Save-YarnPlanBoardSyncState -Root $Root -LastError $err -LastSuccessAt $null -MergeSuccess $false
    }
    catch { }
    Write-Warning ("Plan Board sync: {0}{1}" -f $(if ($err.cursorPlan) { "$($err.cursorPlan): " } else { '' }), $msg)
}

function Get-YarnPlanBoardSyncState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    $path = Get-YarnPlanBoardSyncStatePath -Root $Root
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{
            lastSuccessAt = $null
            lastError     = $null
            lastSummary   = $null
        }
    }
    try {
        return Read-YarnJsonFile -Path $path
    }
    catch {
        return [PSCustomObject]@{
            lastSuccessAt = $null
            lastError     = [PSCustomObject]@{ message = $_.Exception.Message }
            lastSummary   = $null
        }
    }
}

function Save-YarnPlanBoardSyncState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        $LastError = $null,
        $LastSuccessAt = $null,
        $LastSummary = $null,
        [bool]$MergeSuccess = $true
    )
    Initialize-MetraYarnLayout -Root $Root
    $path = Get-YarnPlanBoardSyncStatePath -Root $Root
    $prev = Get-YarnPlanBoardSyncState -Root $Root
    $successAt = $LastSuccessAt
    if ($MergeSuccess -and $null -eq $successAt) {
        $successAt = Get-YarnProp -Object $prev -Name 'lastSuccessAt' -Default $null
    }
    $summary = $LastSummary
    if ($null -eq $summary) {
        $summary = Get-YarnProp -Object $prev -Name 'lastSummary' -Default $null
    }
    $doc = [ordered]@{
        schemaVersion = Get-YarnSchemaVersion
        lastSuccessAt = $successAt
        lastError     = $LastError
        lastSummary   = $summary
        updatedAt     = (Get-Date).ToUniversalTime().ToString('o')
    }
    Invoke-YarnWithNamedMutex -Name 'yarn-plan-board-sync' -Script {
        Write-YarnAtomicUtf8Text -Path $path -Text (($doc | ConvertTo-Json -Depth 8) + "`n")
    }
}

function Invoke-YarnPlanBoardNotionRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Post', 'Patch')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ApiKey,
        [int]$TimeoutSec = 15,
        $Body = $null
    )
    if ($script:YarnPlanBoardOverride) {
        return & $script:YarnPlanBoardOverride @{
            Operation  = 'rest'
            Method     = $Method
            Path       = $Path
            Body       = $Body
            TimeoutSec = $TimeoutSec
            # ApiKey intentionally omitted from override payload (never log secrets)
        }
    }
    $headers = @{
        Authorization    = "Bearer $ApiKey"
        'Notion-Version' = '2022-06-28'
        'Content-Type'   = 'application/json'
    }
    $uri = if ($Path -match '^https://') { $Path } else { "https://api.notion.com/v1/$Path" }
    $params = @{
        Uri         = $uri
        Method      = $Method
        Headers     = $headers
        TimeoutSec  = $TimeoutSec
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
    }
    return Invoke-RestMethod @params
}

function ConvertFrom-YarnPlanBoardNotionProps {
    param($Page)
    if ($null -eq $Page) { return $null }
    $props = $Page.properties
    $title = ''
    try {
        $titleArr = $props.Name.title
        if ($titleArr -and $titleArr.Count -gt 0) {
            $title = [string]$titleArr[0].plain_text
        }
    }
    catch { }
    $cursorPlan = ''
    try {
        $rt = $props.CursorPlan.rich_text
        if ($rt -and $rt.Count -gt 0) { $cursorPlan = [string]$rt[0].plain_text }
    }
    catch { }
    $yarnId = ''
    try {
        $rt = $props.YarnId.rich_text
        if ($rt -and $rt.Count -gt 0) { $yarnId = [string]$rt[0].plain_text }
    }
    catch { }
    $board = ''
    try { $board = [string]$props.Board.select.name } catch { }
    $stage = $null
    try { $stage = $props.Stage.number } catch { }
    return [PSCustomObject]@{
        pageId     = [string]$Page.id
        Name       = $title
        CursorPlan = $cursorPlan
        YarnId     = $yarnId
        Board      = $board
        Stage      = $stage
    }
}

function Find-YarnPlanBoardCardsByCursorPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabaseId,
        [Parameter(Mandatory)][string]$CursorPlan,
        [Parameter(Mandatory)][string]$ApiKey,
        [int]$TimeoutSec = 15
    )
    $name = Get-YarnPlanBoardCursorPlanName -PathOrName $CursorPlan
    $body = @{
        filter = @{
            property  = 'CursorPlan'
            rich_text = @{ equals = $name }
        }
        page_size = 10
    }
    $resp = Invoke-YarnPlanBoardNotionRest -Method Post -Path "databases/$DatabaseId/query" -ApiKey $ApiKey -TimeoutSec $TimeoutSec -Body $body
    $cards = @()
    foreach ($r in @($resp.results)) {
        $c = ConvertFrom-YarnPlanBoardNotionProps -Page $r
        if ($c -and (Test-YarnPlanBoardCursorPlanMatch -Left $c.CursorPlan -Right $name)) {
            $cards += $c
        }
    }
    return @($cards)
}

function Find-YarnPlanBoardCardsByYarnId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabaseId,
        [Parameter(Mandatory)][string]$YarnId,
        [Parameter(Mandatory)][string]$ApiKey,
        [int]$TimeoutSec = 15,
        [object[]]$ExistingCards = $null
    )
    $id = [string]$YarnId
    if ([string]::IsNullOrWhiteSpace($id)) { return @() }
    if ($null -ne $ExistingCards) {
        $hits = @()
        foreach ($c in @($ExistingCards)) {
            if ([string]::Equals([string]$c.YarnId, $id, [StringComparison]::OrdinalIgnoreCase)) {
                $hits += $c
            }
        }
        return @($hits)
    }
    $body = @{
        filter = @{
            property  = 'YarnId'
            rich_text = @{ equals = $id }
        }
        page_size = 10
    }
    $resp = Invoke-YarnPlanBoardNotionRest -Method Post -Path "databases/$DatabaseId/query" -ApiKey $ApiKey -TimeoutSec $TimeoutSec -Body $body
    $cards = @()
    foreach ($r in @($resp.results)) {
        $c = ConvertFrom-YarnPlanBoardNotionProps -Page $r
        if ($c -and [string]::Equals([string]$c.YarnId, $id, [StringComparison]::OrdinalIgnoreCase)) {
            $cards += $c
        }
    }
    return @($cards)
}

function Resolve-YarnPlanBoardCardMatch {
    <#
    .SYNOPSIS
        Dual-identity match: CursorPlan first, else YarnId; split conflict reports neither.
    #>
    [CmdletBinding()]
    param(
        [string]$CursorPlan,
        [string]$YarnId,
        [object[]]$ExistingCards = $null,
        [Parameter(Mandatory)][string]$DatabaseId,
        [Parameter(Mandatory)][string]$ApiKey,
        [int]$TimeoutSec = 15
    )
    $name = Get-YarnPlanBoardCursorPlanName -PathOrName $CursorPlan
    $yarnId = [string]$YarnId

    $byPlan = @()
    if (-not [string]::IsNullOrWhiteSpace($name)) {
        if ($null -ne $ExistingCards) {
            foreach ($c in @($ExistingCards)) {
                if (Test-YarnPlanBoardCursorPlanMatch -Left $c.CursorPlan -Right $name) {
                    $byPlan += $c
                }
            }
        }
        else {
            $byPlan = @(Find-YarnPlanBoardCardsByCursorPlan -DatabaseId $DatabaseId -CursorPlan $name -ApiKey $ApiKey -TimeoutSec $TimeoutSec)
        }
    }

    $byYarn = @()
    if (-not [string]::IsNullOrWhiteSpace($yarnId)) {
        $byYarn = @(Find-YarnPlanBoardCardsByYarnId -DatabaseId $DatabaseId -YarnId $yarnId -ApiKey $ApiKey -TimeoutSec $TimeoutSec -ExistingCards $ExistingCards)
    }

    if ($byPlan.Count -gt 1) {
        return [PSCustomObject]@{
            status      = 'conflict'
            reason      = 'duplicate-cursor-plan'
            card        = $null
            populateCursorPlan = $false
            conflictCards = $byPlan
        }
    }
    if ($byYarn.Count -gt 1) {
        return [PSCustomObject]@{
            status      = 'conflict'
            reason      = 'duplicate-yarn-id'
            card        = $null
            populateCursorPlan = $false
            conflictCards = $byYarn
        }
    }

    $planCard = $(if ($byPlan.Count -eq 1) { $byPlan[0] } else { $null })
    $yarnCard = $(if ($byYarn.Count -eq 1) { $byYarn[0] } else { $null })

    if ($planCard -and $yarnCard) {
        if ([string]::Equals([string]$planCard.pageId, [string]$yarnCard.pageId, [StringComparison]::OrdinalIgnoreCase)) {
            return [PSCustomObject]@{
                status      = 'matched'
                reason      = 'cursor-plan-and-yarn-id'
                card        = $planCard
                populateCursorPlan = $false
                conflictCards = @()
            }
        }
        return [PSCustomObject]@{
            status      = 'conflict'
            reason      = 'split-identity'
            card        = $null
            populateCursorPlan = $false
            conflictCards = @($planCard, $yarnCard)
        }
    }

    if ($planCard) {
        return [PSCustomObject]@{
            status      = 'matched'
            reason      = 'cursor-plan'
            card        = $planCard
            populateCursorPlan = $false
            conflictCards = @()
        }
    }

    if ($yarnCard) {
        # Yarn-only card may mature into dual-identity when CursorPlan was empty.
        # Never strip or replace an existing CursorPlan merely because YarnId is present.
        $populate = (-not [string]::IsNullOrWhiteSpace($name)) -and
            [string]::IsNullOrWhiteSpace([string]$yarnCard.CursorPlan)
        return [PSCustomObject]@{
            status             = 'matched'
            reason             = 'yarn-id'
            card               = $yarnCard
            populateCursorPlan = $populate
            conflictCards      = @()
        }
    }

    return [PSCustomObject]@{
        status      = 'none'
        reason      = 'no-match'
        card        = $null
        populateCursorPlan = $false
        conflictCards = @()
    }
}

function Get-YarnPlanBoardAllCards {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabaseId,
        [Parameter(Mandatory)][string]$ApiKey,
        [int]$TimeoutSec = 15,
        [int]$MaxPages = 20
    )
    $cards = @()
    $cursor = $null
    for ($i = 0; $i -lt $MaxPages; $i++) {
        $body = @{ page_size = 100 }
        if ($cursor) { $body['start_cursor'] = $cursor }
        $resp = Invoke-YarnPlanBoardNotionRest -Method Post -Path "databases/$DatabaseId/query" -ApiKey $ApiKey -TimeoutSec $TimeoutSec -Body $body
        foreach ($r in @($resp.results)) {
            $c = ConvertFrom-YarnPlanBoardNotionProps -Page $r
            if ($c) { $cards += $c }
        }
        if (-not [bool]$resp.has_more) { break }
        $cursor = [string]$resp.next_cursor
        if ([string]::IsNullOrWhiteSpace($cursor)) { break }
    }
    return @($cards)
}

function New-YarnPlanBoardNotionProperties {
    param(
        [Parameter(Mandatory)]$Projection,
        [string]$Notes,
        [switch]$PreserveExistingCursorPlan
    )
    $title = [string](Get-YarnProp -Object $Projection -Name 'Title' -Default '')
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = [string]$Projection.CursorPlan
    }
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = [string](Get-YarnProp -Object $Projection -Name 'YarnId' -Default 'Untitled')
    }
    if ($title.Length -gt 200) { $title = $title.Substring(0, 200) }
    $props = @{
        Name  = @{ title = @(@{ text = @{ content = $title } }) }
        Board = @{ select = @{ name = [string]$Projection.Board } }
        Stage = @{ number = [double]$Projection.Stage }
    }
    $cursorPlan = [string](Get-YarnProp -Object $Projection -Name 'CursorPlan' -Default '')
    if (-not $PreserveExistingCursorPlan) {
        $props['CursorPlan'] = @{ rich_text = @(@{ text = @{ content = $cursorPlan } }) }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($cursorPlan)) {
        $props['CursorPlan'] = @{ rich_text = @(@{ text = @{ content = $cursorPlan } }) }
    }
    $yarnId = [string](Get-YarnProp -Object $Projection -Name 'YarnId' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($yarnId)) {
        $props['YarnId'] = @{ rich_text = @(@{ text = @{ content = $yarnId } }) }
    }
    if (-not [string]::IsNullOrWhiteSpace($Notes)) {
        $props['Notes'] = @{ rich_text = @(@{ text = @{ content = $Notes } }) }
    }
    return $props
}

function Write-YarnPlanBoardCard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabaseId,
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)]$Projection,
        [string]$PageId,
        [int]$TimeoutSec = 15,
        [string]$Notes,
        [switch]$PreserveExistingCursorPlan
    )
    $props = New-YarnPlanBoardNotionProperties -Projection $Projection -Notes $Notes -PreserveExistingCursorPlan:$PreserveExistingCursorPlan
    if ($PageId) {
        return Invoke-YarnPlanBoardNotionRest -Method Patch -Path "pages/$PageId" -ApiKey $ApiKey -TimeoutSec $TimeoutSec -Body @{
            properties = $props
        }
    }
    return Invoke-YarnPlanBoardNotionRest -Method Post -Path 'pages' -ApiKey $ApiKey -TimeoutSec $TimeoutSec -Body @{
        parent     = @{ database_id = $DatabaseId }
        properties = $props
    }
}

function Get-YarnPlanBoardLoomSignals {
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [string]$CursorPlan
    )
    $name = Get-YarnPlanBoardCursorPlanName -PathOrName $CursorPlan
    $result = [PSCustomObject]@{
        handoffSucceeded     = $false
        hasActiveLoomQueue   = $false
        verifiedLoomAccepted = $false
    }
    $cmdItems = Get-Command Get-MetraLoomQueueItems -ErrorAction SilentlyContinue
    $cmdRoot = Get-Command Get-MetraLoomRoot -ErrorAction SilentlyContinue
    if (-not $cmdItems -or -not $cmdRoot) {
        return $result
    }
    try {
        $loomRoot = & $cmdRoot
        $items = @(& $cmdItems -Root $loomRoot)
    }
    catch {
        return $result
    }
    foreach ($item in $items) {
        $src = Get-YarnProp -Object $item -Name 'source' -Default $null
        $path = [string](Get-YarnProp -Object $src -Name 'path' -Default '')
        if ([string]::IsNullOrWhiteSpace($path)) {
            $path = [string](Get-YarnProp -Object $item -Name 'planPath' -Default '')
        }
        if (-not (Test-YarnPlanBoardCursorPlanMatch -Left $path -Right $name)) { continue }
        if (Test-LoomPlanBoardVerifiedAccepted -Item $item) {
            $result.verifiedLoomAccepted = $true
        }
        $st = [string](Get-YarnProp -Object $item -Name 'status' -Default '')
        if (Test-LoomPlanBoardActiveQueueStatus -Status $st) {
            $result.hasActiveLoomQueue = $true
        }
        $yh = Get-YarnProp -Object $item -Name 'yarnHandoff' -Default $null
        # Loom ingest records yarnHandoff without a state field; Yarn plan-links use loomHandoff.state.
        # Never treat mere object presence as success (failed/superseded residue must not force Loom).
        $yhState = [string](Get-YarnProp -Object $yh -Name 'state' -Default '')
        if ($yhState -eq 'succeeded') {
            $result.handoffSucceeded = $true
        }
    }
    return $result
}

function Build-YarnPlanBoardSignalContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot,
        [string]$CursorPlan,
        $BacklogItem = $null,
        $PlanLink = $null,
        [bool]$ExistingPlanBoardCard = $false,
        [string]$ExistingBoard = ''
    )
    $name = Get-YarnPlanBoardCursorPlanName -PathOrName $CursorPlan
    $yarnStatus = ''
    $yarnId = ''
    $title = $name
    $handoffOk = $false
    $hasFormal = $false
    if ($BacklogItem) {
        $yarnStatus = [string](Get-YarnProp -Object $BacklogItem -Name 'status' -Default '')
        $yarnId = [string](Get-YarnProp -Object $BacklogItem -Name 'id' -Default '')
        $t = [string](Get-YarnProp -Object $BacklogItem -Name 'title' -Default '')
        if ($t) { $title = $t }
        $fp = [string](Get-YarnProp -Object $BacklogItem -Name 'formalPlanPath' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($fp)) {
            $hasFormal = $true
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = Get-YarnPlanBoardCursorPlanName -PathOrName $fp
            }
        }
    }
    if ($PlanLink) {
        $ho = Get-YarnProp -Object $PlanLink -Name 'loomHandoff' -Default $null
        if ([string](Get-YarnProp -Object $ho -Name 'state' -Default '') -eq 'succeeded') {
            $handoffOk = $true
        }
        if (-not $BacklogItem) {
            $yarnId = [string](Get-YarnProp -Object $PlanLink -Name 'backlogId' -Default $yarnId)
        }
        $fp = [string](Get-YarnProp -Object $PlanLink -Name 'formalPlanPath' -Default '')
        if ($fp) {
            $hasFormal = $true
            $leaf = Get-YarnPlanBoardCursorPlanName -PathOrName $fp
            if ($leaf) { $name = $leaf }
        }
    }
    $loom = Get-YarnPlanBoardLoomSignals -MetraRoot $MetraRoot -CursorPlan $name
    if ($loom.handoffSucceeded) { $handoffOk = $true }
    return [PSCustomObject]@{
        CursorPlan            = $name
        YarnStatus            = $yarnStatus
        YarnId                = $yarnId
        Title                 = $title
        HandoffSucceeded      = $handoffOk
        HasActiveLoomQueue    = [bool]$loom.hasActiveLoomQueue
        VerifiedLoomAccepted  = [bool]$loom.verifiedLoomAccepted
        ExistingPlanBoardCard = $ExistingPlanBoardCard
        ExistingBoard         = $ExistingBoard
        HasFormalPlan         = $hasFormal
    }
}

function Invoke-YarnPlanBoardUpsertProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Projection,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$ApiKey,
        [switch]$DryRun,
        [switch]$AllowCreate,
        [string]$Notes,
        [object[]]$ExistingCards = $null
    )
    if ([string]$Projection.action -ne 'project') {
        return [PSCustomObject]@{ outcome = 'skipped'; reason = [string]$Projection.signal }
    }
    $name = [string]$Projection.CursorPlan
    $yarnId = [string](Get-YarnProp -Object $Projection -Name 'YarnId' -Default '')
    if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($yarnId)) {
        return [PSCustomObject]@{ outcome = 'skipped'; reason = 'empty-identity' }
    }

    $proj = Resolve-YarnPlanBoardHealProjection -Projection $Projection

    if ($script:YarnPlanBoardOverride) {
        return & $script:YarnPlanBoardOverride @{
            Root        = $Root
            Projection  = $proj
            Config      = $Config
            DryRun      = [bool]$DryRun
            AllowCreate = [bool]$AllowCreate
            Notes       = $Notes
            Operation   = 'upsert'
            ExistingCards = $ExistingCards
        }
    }

    $match = Resolve-YarnPlanBoardCardMatch -CursorPlan $name -YarnId $yarnId -ExistingCards $ExistingCards `
        -DatabaseId $Config.DatabaseId -ApiKey $ApiKey -TimeoutSec $Config.HttpTimeoutSec

    if ($match.status -eq 'conflict') {
        return [PSCustomObject]@{
            outcome       = 'identity-conflict'
            reason        = [string]$match.reason
            conflictCards = @($match.conflictCards)
            projection    = $proj
        }
    }

    if ($match.status -eq 'matched') {
        $card = $match.card
        $writeCursor = [string]$card.CursorPlan
        if ($match.populateCursorPlan -and -not [string]::IsNullOrWhiteSpace($name)) {
            $writeCursor = $name
        }
        elseif ([string]::IsNullOrWhiteSpace($writeCursor)) {
            $writeCursor = $name
        }
        $writeYarnId = $(if ($yarnId) { $yarnId } else { [string]$card.YarnId })
        $writeProj = [PSCustomObject]@{
            action     = $proj.action
            CursorPlan = $writeCursor
            YarnId     = $writeYarnId
            Stage      = $proj.Stage
            Board      = $proj.Board
            Title      = $proj.Title
            signal     = $proj.signal
        }

        $sameBoard = [string]::Equals([string]$card.Board, [string]$writeProj.Board, [StringComparison]::OrdinalIgnoreCase)
        $sameStage = ($null -ne $card.Stage -and [int]$card.Stage -eq [int]$writeProj.Stage)
        $needYarnId = (-not [string]::IsNullOrWhiteSpace($writeYarnId)) -and
            (-not [string]::Equals([string]$card.YarnId, $writeYarnId, [StringComparison]::OrdinalIgnoreCase))
        $needCursor = [bool]$match.populateCursorPlan
        if ($sameBoard -and $sameStage -and -not $needYarnId -and -not $needCursor) {
            return [PSCustomObject]@{ outcome = 'unchanged'; pageId = $card.pageId; projection = $writeProj }
        }
        if ($DryRun) {
            return [PSCustomObject]@{ outcome = 'would-update'; pageId = $card.pageId; projection = $writeProj }
        }
        $preserve = (-not $needCursor) -and (-not [string]::IsNullOrWhiteSpace([string]$card.CursorPlan))
        [void](Write-YarnPlanBoardCard -DatabaseId $Config.DatabaseId -ApiKey $ApiKey -Projection $writeProj `
                -PageId $card.pageId -TimeoutSec $Config.HttpTimeoutSec -Notes $Notes -PreserveExistingCursorPlan:$preserve)
        return [PSCustomObject]@{ outcome = 'updated'; pageId = $card.pageId; projection = $writeProj }
    }

    # zero matches
    if (-not $AllowCreate) {
        return [PSCustomObject]@{ outcome = 'skipped'; reason = 'no-card-no-create' }
    }
    if ($DryRun) {
        return [PSCustomObject]@{ outcome = 'would-create'; projection = $proj }
    }
    $created = Write-YarnPlanBoardCard -DatabaseId $Config.DatabaseId -ApiKey $ApiKey -Projection $proj -TimeoutSec $Config.HttpTimeoutSec -Notes $Notes
    return [PSCustomObject]@{ outcome = 'created'; pageId = [string]$created.id; projection = $proj }
}

function Invoke-YarnPlanBoardNotifyFailOpen {
    <#
    .SYNOPSIS
        Best-effort inline Plan Board sync after a Yarn/Loom success path. Never throws.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot,
        [string]$CursorPlan,
        [string]$BacklogId,
        [string]$Reason = 'status'
    )
    try {
        if ([string]::IsNullOrWhiteSpace($MetraRoot)) { $MetraRoot = Get-YarnHostRoot }
        $cfg = Get-YarnPlanBoardConfig -Root $Root -MetraRoot $MetraRoot
        if (-not $cfg.Configured) {
            if (-not $script:YarnPlanBoardUnconfiguredWarned) {
                Write-Warning 'Plan Board sync skipped (unconfigured). Yarn/Loom continue. Further skips this session are silent.'
                $script:YarnPlanBoardUnconfiguredWarned = $true
            }
            return
        }
        $item = $null
        $link = $null
        if ($BacklogId) {
            $item = @(Get-MetraYarnBacklog -Root $Root) | Where-Object { [string]$_.id -eq $BacklogId } | Select-Object -First 1
            $link = @(Get-YarnPlanLinks -Root $Root) | Where-Object { [string]$_.backlogId -eq $BacklogId } | Select-Object -First 1
        }
        $name = Get-YarnPlanBoardCursorPlanName -PathOrName $CursorPlan
        if ([string]::IsNullOrWhiteSpace($name) -and $link) {
            $name = Get-YarnPlanBoardCursorPlanName -PathOrName ([string](Get-YarnProp -Object $link -Name 'formalPlanPath' -Default ''))
        }
        if ([string]::IsNullOrWhiteSpace($name) -and $item) {
            $name = Get-YarnPlanBoardCursorPlanName -PathOrName ([string](Get-YarnProp -Object $item -Name 'formalPlanPath' -Default ''))
        }
        $yarnIdHint = $BacklogId
        if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($yarnIdHint)) { return }

        $ctx = Build-YarnPlanBoardSignalContext -Root $Root -MetraRoot $MetraRoot -CursorPlan $name -BacklogItem $item -PlanLink $link -ExistingPlanBoardCard:$false
        if ($Reason -eq 'LoomAccepted') {
            $ctx | Add-Member -NotePropertyName VerifiedLoomAccepted -NotePropertyValue $true -Force
        }
        $hasYarnOrLoom = (-not [string]::IsNullOrWhiteSpace($ctx.YarnStatus)) -or $ctx.HandoffSucceeded -or $ctx.HasActiveLoomQueue -or $ctx.VerifiedLoomAccepted
        $proj = Resolve-YarnPlanBoardProjection -CursorPlan $ctx.CursorPlan -YarnStatus $ctx.YarnStatus -YarnId $ctx.YarnId `
            -HandoffSucceeded:$ctx.HandoffSucceeded -HasActiveLoomQueue:$ctx.HasActiveLoomQueue `
            -VerifiedLoomAccepted:$ctx.VerifiedLoomAccepted -ExistingPlanBoardCard:$false `
            -HasFormalPlan:$ctx.HasFormalPlan -Title $ctx.Title
        if ($proj.action -ne 'project') { return }

        $token = Get-YarnPlanBoardNotionApiKey -MetraRoot $MetraRoot
        $result = Invoke-YarnPlanBoardUpsertProjection -Root $Root -Projection $proj -Config $cfg -ApiKey $token -AllowCreate:$hasYarnOrLoom -Notes ("auto:$Reason")
        if ($result.outcome -in @('updated', 'created', 'unchanged')) {
            Save-YarnPlanBoardSyncState -Root $Root -LastError $null -LastSuccessAt ((Get-Date).ToUniversalTime().ToString('o')) -LastSummary $null
        }
    }
    catch {
        Write-YarnPlanBoardSyncError -ErrorRecord $_ -CursorPlan $CursorPlan -Root $Root
    }
}

function Set-YarnBacklogItemStatus {
    <#
    .SYNOPSIS
        Persist a mapped Yarn lifecycle status then notify Plan Board (fail-open).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BacklogId,
        [Parameter(Mandatory)][ValidateSet('idea', 'ready', 'pending-bing', 'stale-pack', 'approved', 'parked', 'rejected')][string]$Status,
        [string]$MetraRoot,
        [switch]$SkipPlanBoard
    )
    $items = @(Get-MetraYarnBacklog -Root $Root)
    $item = $items | Where-Object { [string]$_.id -eq $BacklogId } | Select-Object -First 1
    if (-not $item) { throw "Backlog item not found: $BacklogId" }
    $map = ConvertTo-YarnPropertyMap -Object $item
    $map['status'] = $Status
    $updated = (New-YarnPsObject -Map $map)
    $items = @($items | Where-Object { [string]$_.id -ne $BacklogId }) + @($updated)
    Save-MetraYarnBacklogItems -Root $Root -Items $items
    if (-not $SkipPlanBoard) {
        $path = [string](Get-YarnProp -Object $updated -Name 'formalPlanPath' -Default '')
        Invoke-YarnPlanBoardNotifyFailOpen -Root $Root -MetraRoot $MetraRoot -BacklogId $BacklogId -CursorPlan $path -Reason "yarn-status:$Status"
    }
    return $updated
}

function Invoke-MetraYarnPlanBoardSync {
    <#
    .SYNOPSIS
        Full catch-up recompute: all Yarn backlog items (with or without formalPlanPath),
        plan-links, Loom queue paths, and existing Plan Board cards.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot,
        [switch]$DryRun
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) { $MetraRoot = Get-YarnHostRoot }
    Initialize-MetraYarnLayout -Root $Root
    $summary = New-YarnPlanBoardEmptySummary
    $summary.DryRun = [bool]$DryRun
    $cfg = Get-YarnPlanBoardConfig -Root $Root -MetraRoot $MetraRoot
    if (-not $cfg.Configured) {
        throw 'Plan Board unconfigured (need DatabaseId in plan-board.settings.json under Yarn root + METRA_NOTION_API_KEY or Atlas notion apiKey).'
    }
    $token = Get-YarnPlanBoardNotionApiKey -MetraRoot $MetraRoot

    # Work set keyed by stable identity: plan:<name> or yarn:<id>
    $byKey = @{}
    $addWork = {
        param($Name, $Item, $Link, $YarnIdOnly)
        $n = Get-YarnPlanBoardCursorPlanName -PathOrName $Name
        $yid = ''
        if ($Item) { $yid = [string](Get-YarnProp -Object $Item -Name 'id' -Default '') }
        if ([string]::IsNullOrWhiteSpace($yid) -and $YarnIdOnly) { $yid = [string]$YarnIdOnly }
        if ([string]::IsNullOrWhiteSpace($n) -and [string]::IsNullOrWhiteSpace($yid)) { return }
        $k = if (-not [string]::IsNullOrWhiteSpace($n)) { 'plan:' + $n.ToLowerInvariant() } else { 'yarn:' + $yid.ToLowerInvariant() }
        if (-not $byKey.ContainsKey($k)) {
            $byKey[$k] = [PSCustomObject]@{
                CursorPlan = $n
                YarnId     = $yid
                Item       = $Item
                Link       = $Link
            }
        }
        else {
            $cur = $byKey[$k]
            if (-not $cur.Item -and $Item) { $cur | Add-Member -NotePropertyName Item -NotePropertyValue $Item -Force }
            if (-not $cur.Link -and $Link) { $cur | Add-Member -NotePropertyName Link -NotePropertyValue $Link -Force }
            if ([string]::IsNullOrWhiteSpace([string]$cur.CursorPlan) -and $n) {
                $cur | Add-Member -NotePropertyName CursorPlan -NotePropertyValue $n -Force
            }
            if ([string]::IsNullOrWhiteSpace([string]$cur.YarnId) -and $yid) {
                $cur | Add-Member -NotePropertyName YarnId -NotePropertyValue $yid -Force
            }
        }
    }

    $items = @(Get-MetraYarnBacklog -Root $Root)
    $links = @(Get-YarnPlanLinks -Root $Root)
    foreach ($it in $items) {
        $fp = [string](Get-YarnProp -Object $it -Name 'formalPlanPath' -Default '')
        $iid = [string](Get-YarnProp -Object $it -Name 'id' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($fp)) {
            & $addWork $fp $it $null $null
        }
        else {
            # YarnId-only Backlog path
            & $addWork '' $it $null $iid
        }
    }
    foreach ($lk in $links) {
        $fp = [string](Get-YarnProp -Object $lk -Name 'formalPlanPath' -Default '')
        $bid = [string](Get-YarnProp -Object $lk -Name 'backlogId' -Default '')
        $it = $items | Where-Object { [string]$_.id -eq $bid } | Select-Object -First 1
        & $addWork $fp $it $lk $bid
    }

    $cmdItems = Get-Command Get-MetraLoomQueueItems -ErrorAction SilentlyContinue
    $cmdRoot = Get-Command Get-MetraLoomRoot -ErrorAction SilentlyContinue
    if ($cmdItems -and $cmdRoot) {
        try {
            $loomRoot = & $cmdRoot
            foreach ($loomItem in @(& $cmdItems -Root $loomRoot)) {
                $src = Get-YarnProp -Object $loomItem -Name 'source' -Default $null
                $path = [string](Get-YarnProp -Object $src -Name 'path' -Default '')
                if ([string]::IsNullOrWhiteSpace($path)) {
                    $path = [string](Get-YarnProp -Object $loomItem -Name 'planPath' -Default '')
                }
                & $addWork $path $null $null $null
            }
        }
        catch { }
    }

    $existingCards = @()
    try {
        if ($script:YarnPlanBoardOverride) {
            $probe = & $script:YarnPlanBoardOverride @{
                Operation = 'rest'
                Method    = 'Post'
                Path      = "databases/$($cfg.DatabaseId)/query"
                Body      = @{ page_size = 100 }
            }
            foreach ($r in @($probe.results)) {
                $c = ConvertFrom-YarnPlanBoardNotionProps -Page $r
                if ($c) { $existingCards += $c }
            }
        }
        else {
            $existingCards = @(Get-YarnPlanBoardAllCards -DatabaseId $cfg.DatabaseId -ApiKey $token -TimeoutSec $cfg.HttpTimeoutSec)
        }
    }
    catch {
        $summary.notionUnavailable = $true
        if (-not $DryRun) {
            Write-YarnPlanBoardSyncError -ErrorRecord $_ -Root $Root
        }
        throw
    }
    foreach ($card in $existingCards) {
        if (-not [string]::IsNullOrWhiteSpace([string]$card.CursorPlan)) {
            & $addWork $card.CursorPlan $null $null $null
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$card.YarnId)) {
            & $addWork '' $null $null $card.YarnId
        }
    }

    foreach ($key in @($byKey.Keys)) {
        $work = $byKey[$key]
        $summary.scanned++
        try {
            $matchedCard = $null
            $matchInfo = Resolve-YarnPlanBoardCardMatch -CursorPlan $work.CursorPlan -YarnId $work.YarnId `
                -ExistingCards $existingCards -DatabaseId $cfg.DatabaseId -ApiKey $(if ($token) { $token } else { 'override' }) -TimeoutSec $cfg.HttpTimeoutSec
            if ($matchInfo.status -eq 'conflict') {
                $summary.identityConflicts++
                $summary.failed++
                $summary.Actions += [PSCustomObject]@{
                    CursorPlan = $work.CursorPlan
                    YarnId     = $work.YarnId
                    outcome    = 'identity-conflict'
                    reason     = $matchInfo.reason
                }
                continue
            }
            if ($matchInfo.status -eq 'matched') { $matchedCard = $matchInfo.card }

            $hasCard = $null -ne $matchedCard
            $existingBoard = if ($matchedCard) { [string]$matchedCard.Board } else { '' }
            $ctx = Build-YarnPlanBoardSignalContext -Root $Root -MetraRoot $MetraRoot -CursorPlan $work.CursorPlan `
                -BacklogItem $work.Item -PlanLink $work.Link -ExistingPlanBoardCard:$hasCard -ExistingBoard $existingBoard
            if ([string]::IsNullOrWhiteSpace($ctx.YarnId) -and $work.YarnId) {
                $ctx | Add-Member -NotePropertyName YarnId -NotePropertyValue $work.YarnId -Force
            }
            $proj = Resolve-YarnPlanBoardProjection -CursorPlan $ctx.CursorPlan -YarnStatus $ctx.YarnStatus -YarnId $ctx.YarnId `
                -HandoffSucceeded:$ctx.HandoffSucceeded -HasActiveLoomQueue:$ctx.HasActiveLoomQueue `
                -VerifiedLoomAccepted:$ctx.VerifiedLoomAccepted -ExistingPlanBoardCard:$ctx.ExistingPlanBoardCard `
                -ExistingBoard $ctx.ExistingBoard -HasFormalPlan:$ctx.HasFormalPlan -Title $ctx.Title
            $allowCreate = (-not [string]::IsNullOrWhiteSpace($ctx.YarnStatus)) -or $ctx.HandoffSucceeded -or $ctx.HasActiveLoomQueue -or $ctx.VerifiedLoomAccepted
            $r = Invoke-YarnPlanBoardUpsertProjection -Root $Root -Projection $proj -Config $cfg -ApiKey $(if ($token) { $token } else { 'override' }) `
                -DryRun:$DryRun -AllowCreate:$allowCreate -ExistingCards $existingCards
            $summary.Actions += [PSCustomObject]@{
                CursorPlan = $work.CursorPlan
                outcome    = $r.outcome
                signal     = $(if ($proj) { $proj.signal } else { '' })
                Board      = $proj.Board
                Stage      = $proj.Stage
                YarnStatus = $ctx.YarnStatus
                YarnId     = $ctx.YarnId
            }
            switch ($r.outcome) {
                'unchanged' { $summary.unchanged++ }
                'updated' { $summary.Updated++; $summary.applied++ }
                'created' { $summary.Created++; $summary.applied++ }
                'would-update' { $summary.Updated++; $summary.applied++ }
                'would-create' { $summary.Created++; $summary.applied++ }
                'identity-conflict' { $summary.identityConflicts++; $summary.failed++ }
                'skipped' { $summary.Skipped++ }
                default { $summary.Skipped++ }
            }
        }
        catch {
            $summary.failed++
            $summary.Actions += [PSCustomObject]@{
                CursorPlan = $work.CursorPlan
                YarnId     = $work.YarnId
                outcome    = 'failed'
                error      = $_.Exception.Message
            }
            if (-not $DryRun) {
                Write-YarnPlanBoardSyncError -ErrorRecord $_ -CursorPlan $work.CursorPlan -Root $Root
            }
        }
    }

    if (-not $DryRun) {
        $err = $null
        if ($summary.failed -gt 0) {
            $err = [PSCustomObject]@{
                operation = 'plan-board-sync'
                message   = "Completed with $($summary.failed) item failure(s)."
                at        = (Get-Date).ToUniversalTime().ToString('o')
                retryable = $true
            }
        }
        Save-YarnPlanBoardSyncState -Root $Root -LastError $err -LastSuccessAt ((Get-Date).ToUniversalTime().ToString('o')) -LastSummary ([PSCustomObject]$summary)
    }
    $out = [PSCustomObject]$summary
    $out | Add-Member -NotePropertyName Examined -NotePropertyValue $summary.scanned -Force
    return $out
}

function Get-YarnPlanBoardInventoryPaths {
    param([Parameter(Mandatory)][string]$Root)
    return [PSCustomObject]@{
        JsonPath = (Join-Path $Root 'plan-board-inventory.json')
        MdPath   = (Join-Path $Root 'plan-board-inventory.md')
    }
}

function Get-YarnPlanBoardInventoryHeuristic {
    param(
        [string]$Title,
        [string]$SourceType,
        [string]$YarnStatus,
        [bool]$HasFormalPlan,
        [string]$ExistingBoard
    )
    $t = ([string]$Title).ToLowerInvariant()
    $reasons = New-Object System.Collections.Generic.List[string]
    $proposed = 'review'
    $board = 'Inbox'
    $stage = 1

    if ($YarnStatus -eq 'parked' -or $t -match '\b(park|defer|later|someday)\b') {
        $proposed = 'park'
        $board = 'Parked'
        $stage = 7
        $reasons.Add('park-language') | Out-Null
    }
    elseif ($YarnStatus -eq 'rejected' -or $t -match '\b(drop|obsolete|superseded|done|shipped leftover)\b') {
        $proposed = 'drop'
        $board = 'Drop'
        $stage = 8
        $reasons.Add('drop-language') | Out-Null
    }
    elseif (-not [string]::IsNullOrWhiteSpace($YarnStatus) -or $HasFormalPlan) {
        $proposed = 'keep'
        if ($HasFormalPlan) {
            $board = 'Idea'
            $stage = 3
            $reasons.Add('formal-plan') | Out-Null
        }
        else {
            $board = 'Backlog'
            $stage = 2
            $reasons.Add('yarn-without-plan') | Out-Null
        }
    }
    elseif ($SourceType -in @('cursor-plan', 'meta-doc')) {
        $proposed = 'keep'
        $board = 'Backlog'
        $stage = 2
        $reasons.Add('discovered-plan-doc') | Out-Null
    }
    elseif ($ExistingBoard -in @('Inbox', 'Backlog', 'Drop')) {
        $proposed = 'review'
        $board = $ExistingBoard
        $stage = Get-YarnPlanBoardStageForBoard -Board $ExistingBoard
        $reasons.Add('existing-side-tab') | Out-Null
    }
    else {
        $proposed = 'review'
        $reasons.Add('unsure') | Out-Null
    }

    return [PSCustomObject]@{
        proposedDecision = $proposed
        decision         = 'review'
        proposedBoard    = $board
        proposedStage    = $stage
        reasonCodes      = @($reasons)
    }
}

function Invoke-MetraYarnPlanBoardInventory {
    <#
    .SYNOPSIS
        Scan locked inventory roots; write versioned Bing md+json pack. Zero Notion writes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) { $MetraRoot = Get-YarnHostRoot }
    Initialize-MetraYarnLayout -Root $Root
    $paths = Get-YarnPlanBoardInventoryPaths -Root $Root
    $generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    $inventoryId = [guid]::NewGuid().ToString('n')
    $userHome = if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $env:USERPROFILE
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:HOME)) {
        $env:HOME
    }
    else {
        [System.Environment]::GetFolderPath('UserProfile')
    }
    $cursorPlansDir = if (-not [string]::IsNullOrWhiteSpace($userHome)) {
        Join-Path $userHome '.cursor\plans'
    }
    else {
        $null
    }
    $roots = @(
        'yarn-backlog',
        $(if ($cursorPlansDir) { $cursorPlansDir } else { 'cursor-plans' }),
        (Join-Path $MetraRoot 'docs'),
        'loom-queue',
        'notion-existing-cards'
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $addRow = {
        param($Row)
        $cp = Get-YarnPlanBoardCursorPlanName -PathOrName ([string]$Row.cursorPlan)
        $yk = [string]$Row.yarnId
        $dedupeKey = if ($cp) { 'plan:' + $cp.ToLowerInvariant() } elseif ($yk) { 'yarn:' + $yk.ToLowerInvariant() } else { 'path:' + [string]$Row.sourcePath }
        if ($seen.ContainsKey($dedupeKey)) {
            $canon = $seen[$dedupeKey]
            $ev = @($canon.evidence) + @("duplicate-of:$($Row.rowId)")
            $canon | Add-Member -NotePropertyName evidence -NotePropertyValue $ev -Force
            $dupPage = [string](Get-YarnProp -Object $Row -Name 'notionPageId' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($dupPage) -and [string]::IsNullOrWhiteSpace([string](Get-YarnProp -Object $canon -Name 'notionPageId' -Default ''))) {
                $canon | Add-Member -NotePropertyName notionPageId -NotePropertyValue $dupPage -Force
            }
            $dupYarn = [string](Get-YarnProp -Object $Row -Name 'yarnId' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($dupYarn) -and [string]::IsNullOrWhiteSpace([string](Get-YarnProp -Object $canon -Name 'yarnId' -Default ''))) {
                $canon | Add-Member -NotePropertyName yarnId -NotePropertyValue $dupYarn -Force
            }
            $dupPlan = [string](Get-YarnProp -Object $Row -Name 'cursorPlan' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($dupPlan) -and [string]::IsNullOrWhiteSpace([string](Get-YarnProp -Object $canon -Name 'cursorPlan' -Default ''))) {
                $canon | Add-Member -NotePropertyName cursorPlan -NotePropertyValue $dupPlan -Force
            }
            return
        }
        $seen[$dedupeKey] = $Row
        $rows.Add($Row) | Out-Null
    }

    $items = @(Get-MetraYarnBacklog -Root $Root)
    foreach ($it in $items) {
        $fp = [string](Get-YarnProp -Object $it -Name 'formalPlanPath' -Default '')
        $id = [string](Get-YarnProp -Object $it -Name 'id' -Default '')
        $title = [string](Get-YarnProp -Object $it -Name 'title' -Default '')
        $st = [string](Get-YarnProp -Object $it -Name 'status' -Default '')
        $hasFormal = -not [string]::IsNullOrWhiteSpace($fp)
        $h = Get-YarnPlanBoardInventoryHeuristic -Title $title -SourceType 'yarn' -YarnStatus $st -HasFormalPlan:$hasFormal
        $row = [ordered]@{
            rowId            = "yarn:$id"
            proposedDecision = $h.proposedDecision
            decision         = $h.decision
            proposedBoard    = $h.proposedBoard
            proposedStage    = $h.proposedStage
            decisionReason   = $null
            cursorPlan       = $(if ($hasFormal) { Get-YarnPlanBoardCursorPlanName -PathOrName $fp } else { $null })
            yarnId           = $id
            notionPageId     = $null
            sourceType       = 'yarn'
            sourcePath       = $(if ($hasFormal) { $fp } else { $null })
            reasonCodes      = $h.reasonCodes
            evidence         = @("status:$st")
            title            = $title
        }
        & $addRow ([PSCustomObject]$row)
    }

    if ($cursorPlansDir -and (Test-Path -LiteralPath $cursorPlansDir)) {
        Get-ChildItem -LiteralPath $cursorPlansDir -Filter '*.plan.md' -File -ErrorAction SilentlyContinue | ForEach-Object {
            $leaf = $_.Name
            $h = Get-YarnPlanBoardInventoryHeuristic -Title $leaf -SourceType 'cursor-plan' -HasFormalPlan:$true
            $row = [ordered]@{
                rowId            = "cursor-plan:$leaf"
                proposedDecision = $h.proposedDecision
                decision         = $h.decision
                proposedBoard    = $h.proposedBoard
                proposedStage    = $h.proposedStage
                decisionReason   = $null
                cursorPlan       = $leaf
                yarnId           = $null
                notionPageId     = $null
                sourceType       = 'cursor-plan'
                sourcePath       = $_.FullName
                reasonCodes      = $h.reasonCodes
                evidence         = @()
                title            = $leaf
            }
            & $addRow ([PSCustomObject]$row)
        }
    }

    $metaDocs = Join-Path $MetraRoot 'docs'
    if (Test-Path -LiteralPath $metaDocs) {
        Get-ChildItem -LiteralPath $metaDocs -Filter '*.plan.md' -File -ErrorAction SilentlyContinue | ForEach-Object {
            $leaf = $_.Name
            $h = Get-YarnPlanBoardInventoryHeuristic -Title $leaf -SourceType 'meta-doc' -HasFormalPlan:$false
            $row = [ordered]@{
                rowId            = "meta-doc:$leaf"
                proposedDecision = $h.proposedDecision
                decision         = $h.decision
                proposedBoard    = $h.proposedBoard
                proposedStage    = $h.proposedStage
                decisionReason   = $null
                cursorPlan       = $leaf
                yarnId           = $null
                notionPageId     = $null
                sourceType       = 'meta-doc'
                sourcePath       = $_.FullName
                reasonCodes      = @($h.reasonCodes) + @('meta-plan-doc')
                evidence         = @()
                title            = $leaf
            }
            & $addRow ([PSCustomObject]$row)
        }
    }

    $cmdItems = Get-Command Get-MetraLoomQueueItems -ErrorAction SilentlyContinue
    $cmdRoot = Get-Command Get-MetraLoomRoot -ErrorAction SilentlyContinue
    if ($cmdItems -and $cmdRoot) {
        try {
            $loomRoot = & $cmdRoot
            foreach ($loomItem in @(& $cmdItems -Root $loomRoot)) {
                $src = Get-YarnProp -Object $loomItem -Name 'source' -Default $null
                $path = [string](Get-YarnProp -Object $src -Name 'path' -Default '')
                if ([string]::IsNullOrWhiteSpace($path)) {
                    $path = [string](Get-YarnProp -Object $loomItem -Name 'planPath' -Default '')
                }
                $leaf = Get-YarnPlanBoardCursorPlanName -PathOrName $path
                if ([string]::IsNullOrWhiteSpace($leaf)) { continue }
                $h = Get-YarnPlanBoardInventoryHeuristic -Title $leaf -SourceType 'loom' -HasFormalPlan:$true
                $row = [ordered]@{
                    rowId            = "loom:$leaf"
                    proposedDecision = 'keep'
                    decision         = 'review'
                    proposedBoard    = $h.proposedBoard
                    proposedStage    = $h.proposedStage
                    decisionReason   = $null
                    cursorPlan       = $leaf
                    yarnId           = $null
                    notionPageId     = $null
                    sourceType       = 'loom'
                    sourcePath       = $path
                    reasonCodes      = @('loom-queue')
                    evidence         = @("status:$((Get-YarnProp -Object $loomItem -Name 'status' -Default ''))")
                    title            = $leaf
                }
                & $addRow ([PSCustomObject]$row)
            }
        }
        catch { }
    }

    # Existing Notion cards (best-effort; fail-open if unconfigured)
    $cfg = Get-YarnPlanBoardConfig -Root $Root -MetraRoot $MetraRoot
    if ($cfg.Configured) {
        try {
            $token = Get-YarnPlanBoardNotionApiKey -MetraRoot $MetraRoot
            $cards = @()
            if ($script:YarnPlanBoardOverride) {
                $probe = & $script:YarnPlanBoardOverride @{
                    Operation = 'rest'; Method = 'Post'; Path = "databases/$($cfg.DatabaseId)/query"; Body = @{ page_size = 100 }
                }
                foreach ($r in @($probe.results)) {
                    $c = ConvertFrom-YarnPlanBoardNotionProps -Page $r
                    if ($c) { $cards += $c }
                }
            }
            else {
                $cards = @(Get-YarnPlanBoardAllCards -DatabaseId $cfg.DatabaseId -ApiKey $token -TimeoutSec $cfg.HttpTimeoutSec)
            }
            foreach ($c in $cards) {
                $h = Get-YarnPlanBoardInventoryHeuristic -Title $c.Name -SourceType 'notion' -ExistingBoard ([string]$c.Board)
                $row = [ordered]@{
                    rowId            = "notion:$($c.pageId)"
                    proposedDecision = $h.proposedDecision
                    decision         = $h.decision
                    proposedBoard    = $h.proposedBoard
                    proposedStage    = $h.proposedStage
                    decisionReason   = $null
                    cursorPlan       = $(if ($c.CursorPlan) { $c.CursorPlan } else { $null })
                    yarnId           = $(if ($c.YarnId) { $c.YarnId } else { $null })
                    notionPageId     = $c.pageId
                    sourceType       = 'notion'
                    sourcePath       = $null
                    reasonCodes      = $h.reasonCodes
                    evidence         = @("board:$($c.Board)", "stage:$($c.Stage)")
                    title            = $c.Name
                }
                & $addRow ([PSCustomObject]$row)
            }
        }
        catch { }
    }

    $rowArray = @($rows.ToArray())
    $doc = [ordered]@{
        schemaVersion = 2
        generatedAt   = $generatedAt
        inventoryId   = $inventoryId
        roots         = @($roots)
        rows          = $rowArray
    }
    Write-YarnAtomicUtf8Text -Path $paths.JsonPath -Text (($doc | ConvertTo-Json -Depth 10) + "`n")

    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine('# Plan Board inventory pack')
    [void]$md.AppendLine('')
    [void]$md.AppendLine("schemaVersion: 2")
    [void]$md.AppendLine("inventoryId: $inventoryId")
    [void]$md.AppendLine("generatedAt: $generatedAt")
    [void]$md.AppendLine("rows: $($rows.Count)")
    [void]$md.AppendLine('')
    [void]$md.AppendLine('Edit `decision` in the JSON sidecar to `keep` | `drop` | `park` (leave `review` to skip). Then:')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('```powershell')
    [void]$md.AppendLine('.\metra.ps1 plan-board inventory apply -Confirm')
    [void]$md.AppendLine('```')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('| rowId | proposed | decision | Board | Stage | source | title |')
    [void]$md.AppendLine('|-------|----------|----------|-------|------:|--------|-------|')
    foreach ($r in $rows) {
        [void]$md.AppendLine("| $($r.rowId) | $($r.proposedDecision) | $($r.decision) | $($r.proposedBoard) | $($r.proposedStage) | $($r.sourceType) | $($r.title) |")
    }
    Write-YarnAtomicUtf8Text -Path $paths.MdPath -Text $md.ToString()

    return [PSCustomObject]@{
        schemaVersion = 2
        inventoryId   = $inventoryId
        generatedAt   = $generatedAt
        scanned       = $rows.Count
        proposed      = $rows.Count
        jsonPath      = $paths.JsonPath
        mdPath        = $paths.MdPath
        roots         = $roots
    }
}

function Test-YarnPlanBoardInventoryBoardStagePair {
    param([string]$Board, $Stage)
    if (-not (Test-YarnPlanBoardRecognizedBoard -Board $Board)) { return $false }
    $expected = Get-YarnPlanBoardStageForBoard -Board $Board
    try {
        return ([int]$Stage -eq [int]$expected)
    }
    catch {
        return $false
    }
}

function Invoke-MetraYarnPlanBoardInventoryApply {
    <#
    .SYNOPSIS
        Affirmation gate: apply keep/drop/park rows from versioned inventory pack. Stale-safe.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot,
        [switch]$Confirm
    )
    if (-not $Confirm) {
        throw 'plan-board inventory apply requires -Confirm (affirmation gate). Nothing attempted.'
    }
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) { $MetraRoot = Get-YarnHostRoot }
    Initialize-MetraYarnLayout -Root $Root
    $paths = Get-YarnPlanBoardInventoryPaths -Root $Root
    if (-not (Test-Path -LiteralPath $paths.JsonPath)) {
        throw "Inventory pack not found: $($paths.JsonPath). Run plan-board inventory first."
    }
    $pack = Read-YarnJsonFile -Path $paths.JsonPath
    $schema = 0
    try { $schema = [int](Get-YarnProp -Object $pack -Name 'schemaVersion' -Default 0) } catch { $schema = 0 }
    if ($schema -ne 2) {
        throw "Unsupported inventory schemaVersion='$schema' (expected 2). Nothing attempted."
    }

    $summary = New-YarnPlanBoardEmptySummary
    $cfg = Get-YarnPlanBoardConfig -Root $Root -MetraRoot $MetraRoot
    if (-not $cfg.Configured) {
        $summary.notionUnavailable = $true
        Write-Warning 'Plan Board inventory apply: Notion unconfigured; nothing applied.'
        return [PSCustomObject]$summary
    }
    $token = Get-YarnPlanBoardNotionApiKey -MetraRoot $MetraRoot
    $existingCards = @()
    try {
        if ($script:YarnPlanBoardOverride) {
            $probe = & $script:YarnPlanBoardOverride @{
                Operation = 'rest'; Method = 'Post'; Path = "databases/$($cfg.DatabaseId)/query"; Body = @{ page_size = 100 }
            }
            foreach ($r in @($probe.results)) {
                $c = ConvertFrom-YarnPlanBoardNotionProps -Page $r
                if ($c) { $existingCards += $c }
            }
        }
        else {
            $existingCards = @(Get-YarnPlanBoardAllCards -DatabaseId $cfg.DatabaseId -ApiKey $token -TimeoutSec $cfg.HttpTimeoutSec)
        }
    }
    catch {
        $summary.notionUnavailable = $true
        Write-YarnPlanBoardSyncError -ErrorRecord $_ -Root $Root
        return [PSCustomObject]$summary
    }

    $items = @(Get-MetraYarnBacklog -Root $Root)
    $links = @(Get-YarnPlanLinks -Root $Root)
    $generatedAt = [string](Get-YarnProp -Object $pack -Name 'generatedAt' -Default '')

    foreach ($row in @($pack.rows)) {
        $summary.scanned++
        $decision = ([string](Get-YarnProp -Object $row -Name 'decision' -Default 'review')).ToLowerInvariant()
        $rowId = [string](Get-YarnProp -Object $row -Name 'rowId' -Default '')
        try {
            if ($decision -notin @('keep', 'drop', 'park')) {
                $summary.skippedReview++
                continue
            }

            $cursorPlan = Get-YarnPlanBoardCursorPlanName -PathOrName ([string](Get-YarnProp -Object $row -Name 'cursorPlan' -Default ''))
            $yarnId = [string](Get-YarnProp -Object $row -Name 'yarnId' -Default '')
            $pageId = [string](Get-YarnProp -Object $row -Name 'notionPageId' -Default '')
            if ($decision -eq 'drop' -and [string]::IsNullOrWhiteSpace($pageId)) {
                $summary.failed++
                $summary.Actions += [PSCustomObject]@{ rowId = $rowId; outcome = 'failed'; error = 'drop-requires-stable-identity' }
                continue
            }

            $item = $null
            $link = $null
            if ($yarnId) {
                $item = $items | Where-Object { [string]$_.id -eq $yarnId } | Select-Object -First 1
                $link = $links | Where-Object { [string]$_.backlogId -eq $yarnId } | Select-Object -First 1
            }
            if (-not $item -and $cursorPlan) {
                $item = $items | Where-Object {
                    Test-YarnPlanBoardCursorPlanMatch -Left ([string](Get-YarnProp -Object $_ -Name 'formalPlanPath' -Default '')) -Right $cursorPlan
                } | Select-Object -First 1
            }

            $matchedCard = $null
            if ($pageId) {
                $matchedCard = @($existingCards | Where-Object { [string]$_.pageId -eq $pageId }) | Select-Object -First 1
            }
            $matchInfo = Resolve-YarnPlanBoardCardMatch -CursorPlan $cursorPlan -YarnId $yarnId -ExistingCards $existingCards `
                -DatabaseId $cfg.DatabaseId -ApiKey $token -TimeoutSec $cfg.HttpTimeoutSec
            if ($matchInfo.status -eq 'conflict') {
                $summary.identityConflicts++
                $summary.skippedReview++
                $summary.Actions += [PSCustomObject]@{ rowId = $rowId; outcome = 'identity-conflict'; reason = $matchInfo.reason }
                continue
            }
            if (-not $matchedCard -and $matchInfo.status -eq 'matched') { $matchedCard = $matchInfo.card }

            $existingBoard = if ($matchedCard) { [string]$matchedCard.Board } else { '' }
            $ctx = Build-YarnPlanBoardSignalContext -Root $Root -MetraRoot $MetraRoot -CursorPlan $cursorPlan `
                -BacklogItem $item -PlanLink $link -ExistingPlanBoardCard:($null -ne $matchedCard) -ExistingBoard $existingBoard
            if ($yarnId -and [string]::IsNullOrWhiteSpace($ctx.YarnId)) {
                $ctx | Add-Member -NotePropertyName YarnId -NotePropertyValue $yarnId -Force
            }

            # Stale check: authoritative lifecycle without inventory decision
            $live = Resolve-YarnPlanBoardProjection -CursorPlan $ctx.CursorPlan -YarnStatus $ctx.YarnStatus -YarnId $ctx.YarnId `
                -HandoffSucceeded:$ctx.HandoffSucceeded -HasActiveLoomQueue:$ctx.HasActiveLoomQueue `
                -VerifiedLoomAccepted:$ctx.VerifiedLoomAccepted -ExistingPlanBoardCard:$ctx.ExistingPlanBoardCard `
                -ExistingBoard $ctx.ExistingBoard -HasFormalPlan:$ctx.HasFormalPlan -Title $ctx.Title

            $proposedBoard = [string](Get-YarnProp -Object $row -Name 'proposedBoard' -Default '')
            $proposedStage = Get-YarnProp -Object $row -Name 'proposedStage' -Default $null

            # If live authoritative lifecycle moved ahead of the inventory proposal, skip stale.
            # Do not use Stage integer alone: Drop/Park (7/8) outrank Active/Loom (4/5) numerically,
            # which would let a stale pack demote live approved/handoff work.
            $authoritativeSignals = @(
                'verified-loom-accepted', 'yarn-rejected', 'yarn-parked', 'loom-handoff',
                'active-loom-queue', 'yarn-approved', 'yarn-pending-bing', 'yarn-stale-pack'
            )
            $activeLifecycleSignals = @(
                'verified-loom-accepted', 'loom-handoff', 'active-loom-queue',
                'yarn-approved', 'yarn-pending-bing', 'yarn-stale-pack'
            )
            if ($live.action -eq 'project' -and ($authoritativeSignals -contains [string]$live.signal)) {
                if ($decision -in @('drop', 'park') -and ($activeLifecycleSignals -contains [string]$live.signal)) {
                    $summary.skippedStale++
                    $summary.Actions += [PSCustomObject]@{
                        rowId      = $rowId
                        outcome    = 'skipped-stale'
                        liveSignal = $live.signal
                        liveStage  = $live.Stage
                        reason     = 'inventory-cannot-demote-active-lifecycle'
                    }
                    continue
                }
                $invStage = switch ($decision) {
                    'drop' { 8 }
                    'park' { 7 }
                    'keep' {
                        if (Test-YarnPlanBoardInventoryBoardStagePair -Board $proposedBoard -Stage $proposedStage) {
                            [int]$proposedStage
                        }
                        elseif ($ctx.HasFormalPlan) { 3 } else { 2 }
                    }
                }
                if ([int]$live.Stage -ne $invStage -and [int]$live.Stage -gt $invStage) {
                    $summary.skippedStale++
                    $summary.Actions += [PSCustomObject]@{ rowId = $rowId; outcome = 'skipped-stale'; liveSignal = $live.signal; liveStage = $live.Stage }
                    continue
                }
                # Also stale if live Board differs from keep proposal while lifecycle moved
                if ($decision -eq 'keep' -and [string]$live.Board -ne $proposedBoard -and ($authoritativeSignals -contains [string]$live.signal)) {
                    $summary.skippedStale++
                    $summary.Actions += [PSCustomObject]@{ rowId = $rowId; outcome = 'skipped-stale'; liveSignal = $live.signal }
                    continue
                }
            }

            $invDecision = $decision
            $proj = Resolve-YarnPlanBoardProjection -CursorPlan $ctx.CursorPlan -YarnStatus $ctx.YarnStatus -YarnId $ctx.YarnId `
                -HandoffSucceeded:$ctx.HandoffSucceeded -HasActiveLoomQueue:$ctx.HasActiveLoomQueue `
                -VerifiedLoomAccepted:$ctx.VerifiedLoomAccepted -ExistingPlanBoardCard:$ctx.ExistingPlanBoardCard `
                -ExistingBoard $ctx.ExistingBoard -HasFormalPlan:$ctx.HasFormalPlan `
                -InventoryDecision $invDecision -Title $(if ($ctx.Title) { $ctx.Title } else { [string](Get-YarnProp -Object $row -Name 'title' -Default '') })

            if ($decision -eq 'keep') {
                if (-not (Test-YarnPlanBoardInventoryBoardStagePair -Board $proposedBoard -Stage $proposedStage)) {
                    # Malformed pair: re-resolve rather than trust Stage alone
                    if ($proj.action -ne 'project') {
                        $summary.failed++
                        $summary.Actions += [PSCustomObject]@{ rowId = $rowId; outcome = 'failed'; error = 'malformed-keep-pair' }
                        continue
                    }
                }
                else {
                    # Affirmed keep with consistent pair — use affirmed Board/Stage unless live superseded
                    $proj = [PSCustomObject]@{
                        action     = 'project'
                        CursorPlan = $ctx.CursorPlan
                        YarnId     = $ctx.YarnId
                        Stage      = [int]$proposedStage
                        Board      = $proposedBoard
                        Title      = $proj.Title
                        signal     = 'inventory-keep-affirmed'
                    }
                }
            }

            $allowCreate = ($decision -eq 'keep')
            $apiKey = if ($token) { $token } else { 'override' }
            $r = Invoke-YarnPlanBoardUpsertProjection -Root $Root -Projection $proj -Config $cfg -ApiKey $apiKey `
                -AllowCreate:$allowCreate -ExistingCards $existingCards -Notes "inventory:$rowId"
            $summary.Actions += [PSCustomObject]@{
                rowId      = $rowId
                outcome    = $r.outcome
                Board      = $proj.Board
                Stage      = $proj.Stage
                decision   = $decision
            }
            switch ($r.outcome) {
                'unchanged' { $summary.unchanged++ }
                'updated' { $summary.applied++; $summary.Updated++ }
                'created' { $summary.applied++; $summary.Created++ }
                'identity-conflict' { $summary.identityConflicts++; $summary.skippedReview++ }
                'skipped' { $summary.Skipped++ }
                default { $summary.Skipped++ }
            }
        }
        catch {
            $summary.failed++
            $summary.Actions += [PSCustomObject]@{ rowId = $rowId; outcome = 'failed'; error = $_.Exception.Message }
        }
    }

    $err = $null
    if ($summary.failed -gt 0) {
        $err = [PSCustomObject]@{
            operation = 'plan-board-inventory-apply'
            message   = "Completed with $($summary.failed) item failure(s)."
            at        = (Get-Date).ToUniversalTime().ToString('o')
            retryable = $true
        }
    }
    Save-YarnPlanBoardSyncState -Root $Root -LastError $err -LastSuccessAt ((Get-Date).ToUniversalTime().ToString('o')) -LastSummary ([PSCustomObject]$summary)
    return [PSCustomObject]$summary
}

function Get-MetraYarnPlanBoardStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) { $MetraRoot = Get-YarnHostRoot }
    $cfg = Get-YarnPlanBoardConfig -Root $Root -MetraRoot $MetraRoot
    $state = Get-YarnPlanBoardSyncState -Root $Root
    $access = 'unconfigured'
    $detail = 'DatabaseId or Notion token missing'
    if ($cfg.Configured) {
        $access = 'configured-inaccessible'
        $detail = 'Notion reachability not checked'
        try {
            if ($script:YarnPlanBoardOverride) {
                $probe = & $script:YarnPlanBoardOverride @{ Operation = 'status'; Config = $cfg; Root = $Root }
                $access = [string](Get-YarnProp -Object $probe -Name 'access' -Default 'accessible')
                $detail = [string](Get-YarnProp -Object $probe -Name 'detail' -Default 'override')
            }
            else {
                # Probe via the same query surface as sync/upsert (Notion-Version 2022-06-28).
                $token = Get-YarnPlanBoardNotionApiKey -MetraRoot $MetraRoot
                [void](Invoke-YarnPlanBoardNotionRest -Method Post -Path "databases/$($cfg.DatabaseId)/query" -ApiKey $token -TimeoutSec $cfg.HttpTimeoutSec -Body @{ page_size = 1 })
                $access = 'accessible'
                $detail = 'Plan Board database query reachable'
            }
        }
        catch {
            $access = 'configured-inaccessible'
            $detail = $_.Exception.Message
            $detail = [regex]::Replace([string]$detail, '(?i)(Bearer\s+)\S+', '$1***')
            $detail = [regex]::Replace([string]$detail, '(?i)(api[_-]?key["''\s:=]+)[^\s,"'']+', '$1***')
        }
    }
    $itemFailures = $false
    $lastErr = Get-YarnProp -Object $state -Name 'lastError' -Default $null
    if ($null -ne $lastErr) { $itemFailures = $true }
    return [PSCustomObject]@{
        configured            = [bool]$cfg.Configured
        hasToken              = [bool]$cfg.HasToken
        databaseIdPresent     = -not [string]::IsNullOrWhiteSpace($cfg.DatabaseId)
        access                = $access
        detail                = $detail
        lastSuccessAt         = Get-YarnProp -Object $state -Name 'lastSuccessAt' -Default $null
        lastError             = $lastErr
        lastSyncHadItemFailures = $itemFailures
        settingsPath          = $cfg.SettingsPath
    }
}
