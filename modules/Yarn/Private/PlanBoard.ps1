# Plan Board projection (Notion). Yarn/Loom remain authoritative. Fail-open; no Notion required.

$script:YarnPlanBoardOverride = $null
$script:YarnPlanBoardHttpTimeoutSec = 15
$script:YarnPlanBoardUnconfiguredWarned = $false

function Get-YarnPlanBoardStageLabels {
    # Regular Hashtable so integer lookup is by key (OrderedDictionary int indexer is by index).
    return @{
        1 = 'Inbox'
        2 = 'Idea'
        3 = 'Active'
        4 = 'Loom'
        5 = 'Shipped'
        6 = 'Parked'
        7 = 'Drop'
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
        [string]$Title
    )

    $name = Get-YarnPlanBoardCursorPlanName -PathOrName $CursorPlan
    $labels = Get-YarnPlanBoardStageLabels
    $ys = [string]$YarnStatus

    if ($VerifiedLoomAccepted) {
        return [PSCustomObject]@{
            action     = 'project'
            CursorPlan = $name
            YarnId     = $YarnId
            Stage      = 5
            Board      = [string]($labels[5])
            Title      = $Title
            signal     = 'verified-loom-accepted'
        }
    }
    if ($ys -eq 'rejected') {
        return [PSCustomObject]@{
            action     = 'project'
            CursorPlan = $name
            YarnId     = $YarnId
            Stage      = 7
            Board      = [string]($labels[7])
            Title      = $Title
            signal     = 'yarn-rejected'
        }
    }
    if ($ys -eq 'parked') {
        return [PSCustomObject]@{
            action     = 'project'
            CursorPlan = $name
            YarnId     = $YarnId
            Stage      = 6
            Board      = [string]($labels[6])
            Title      = $Title
            signal     = 'yarn-parked'
        }
    }
    if ($HandoffSucceeded -or $HasActiveLoomQueue) {
        return [PSCustomObject]@{
            action     = 'project'
            CursorPlan = $name
            YarnId     = $YarnId
            Stage      = 4
            Board      = [string]($labels[4])
            Title      = $Title
            signal     = $(if ($HandoffSucceeded) { 'loom-handoff' } else { 'active-loom-queue' })
        }
    }
    if ($ys -eq 'approved') {
        return [PSCustomObject]@{
            action     = 'project'
            CursorPlan = $name
            YarnId     = $YarnId
            Stage      = 4
            Board      = [string]($labels[4])
            Title      = $Title
            signal     = 'yarn-approved'
        }
    }
    if ($ys -in @('pending-bing', 'stale-pack')) {
        return [PSCustomObject]@{
            action     = 'project'
            CursorPlan = $name
            YarnId     = $YarnId
            Stage      = 3
            Board      = [string]($labels[3])
            Title      = $Title
            signal     = "yarn-$ys"
        }
    }
    if ($ys -in @('idea', 'ready')) {
        return [PSCustomObject]@{
            action     = 'project'
            CursorPlan = $name
            YarnId     = $YarnId
            Stage      = 2
            Board      = [string]($labels[2])
            Title      = $Title
            signal     = "yarn-$ys"
        }
    }
    if ($ExistingPlanBoardCard -and -not [string]::IsNullOrWhiteSpace($name)) {
        return [PSCustomObject]@{
            action     = 'project'
            CursorPlan = $name
            YarnId     = $YarnId
            Stage      = 1
            Board      = [string]($labels[1])
            Title      = $Title
            signal     = 'existing-card-inbox'
        }
    }
    return [PSCustomObject]@{
        action     = 'skip'
        CursorPlan = $name
        YarnId     = $YarnId
        Stage      = $null
        Board      = $null
        Title      = $Title
        signal     = 'no-authoritative-signal'
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
        [string]$Notes
    )
    $title = [string](Get-YarnProp -Object $Projection -Name 'Title' -Default '')
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = [string]$Projection.CursorPlan
    }
    if ($title.Length -gt 200) { $title = $title.Substring(0, 200) }
    $props = @{
        Name       = @{ title = @(@{ text = @{ content = $title } }) }
        Board      = @{ select = @{ name = [string]$Projection.Board } }
        Stage      = @{ number = [double]$Projection.Stage }
        CursorPlan = @{ rich_text = @(@{ text = @{ content = [string]$Projection.CursorPlan } }) }
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
        [string]$Notes
    )
    $props = New-YarnPlanBoardNotionProperties -Projection $Projection -Notes $Notes
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
        [Parameter(Mandatory)][string]$CursorPlan,
        $BacklogItem = $null,
        $PlanLink = $null,
        [bool]$ExistingPlanBoardCard = $false
    )
    $name = Get-YarnPlanBoardCursorPlanName -PathOrName $CursorPlan
    $yarnStatus = ''
    $yarnId = ''
    $title = $name
    $handoffOk = $false
    if ($BacklogItem) {
        $yarnStatus = [string](Get-YarnProp -Object $BacklogItem -Name 'status' -Default '')
        $yarnId = [string](Get-YarnProp -Object $BacklogItem -Name 'id' -Default '')
        $t = [string](Get-YarnProp -Object $BacklogItem -Name 'title' -Default '')
        if ($t) { $title = $t }
        $fp = [string](Get-YarnProp -Object $BacklogItem -Name 'formalPlanPath' -Default '')
        if ($fp -and [string]::IsNullOrWhiteSpace($name)) {
            $name = Get-YarnPlanBoardCursorPlanName -PathOrName $fp
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
            $leaf = Get-YarnPlanBoardCursorPlanName -PathOrName $fp
            if ($leaf) { $name = $leaf }
        }
    }
    $loom = Get-YarnPlanBoardLoomSignals -MetraRoot $MetraRoot -CursorPlan $name
    if ($loom.handoffSucceeded) { $handoffOk = $true }
    return [PSCustomObject]@{
        CursorPlan             = $name
        YarnStatus             = $yarnStatus
        YarnId                 = $yarnId
        Title                  = $title
        HandoffSucceeded       = $handoffOk
        HasActiveLoomQueue     = [bool]$loom.hasActiveLoomQueue
        VerifiedLoomAccepted   = [bool]$loom.verifiedLoomAccepted
        ExistingPlanBoardCard  = $ExistingPlanBoardCard
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
    if ([string]::IsNullOrWhiteSpace($name)) {
        return [PSCustomObject]@{ outcome = 'skipped'; reason = 'empty-cursor-plan' }
    }

    if ($script:YarnPlanBoardOverride) {
        return & $script:YarnPlanBoardOverride @{
            Root       = $Root
            Projection = $Projection
            Config     = $Config
            DryRun     = [bool]$DryRun
            AllowCreate = [bool]$AllowCreate
            Notes      = $Notes
            Operation  = 'upsert'
        }
    }

    $cards = @()
    if ($null -ne $ExistingCards) {
        foreach ($c in @($ExistingCards)) {
            if (Test-YarnPlanBoardCursorPlanMatch -Left $c.CursorPlan -Right $name) {
                $cards += $c
            }
        }
    }
    else {
        $cards = @(Find-YarnPlanBoardCardsByCursorPlan -DatabaseId $Config.DatabaseId -CursorPlan $name -ApiKey $ApiKey -TimeoutSec $Config.HttpTimeoutSec)
    }
    if ($cards.Count -gt 1) {
        throw "Duplicate Plan Board cards for CursorPlan='$name' (count=$($cards.Count))"
    }
    if ($cards.Count -eq 1) {
        $card = $cards[0]
        $sameBoard = [string]::Equals([string]$card.Board, [string]$Projection.Board, [StringComparison]::OrdinalIgnoreCase)
        $sameStage = ($null -ne $card.Stage -and [int]$card.Stage -eq [int]$Projection.Stage)
        $needYarnId = (-not [string]::IsNullOrWhiteSpace([string]$Projection.YarnId)) -and
            (-not [string]::Equals([string]$card.YarnId, [string]$Projection.YarnId, [StringComparison]::OrdinalIgnoreCase))
        if ($sameBoard -and $sameStage -and -not $needYarnId) {
            return [PSCustomObject]@{ outcome = 'unchanged'; pageId = $card.pageId; projection = $Projection }
        }
        if ($DryRun) {
            return [PSCustomObject]@{ outcome = 'would-update'; pageId = $card.pageId; projection = $Projection }
        }
        [void](Write-YarnPlanBoardCard -DatabaseId $Config.DatabaseId -ApiKey $ApiKey -Projection $Projection -PageId $card.pageId -TimeoutSec $Config.HttpTimeoutSec -Notes $Notes)
        return [PSCustomObject]@{ outcome = 'updated'; pageId = $card.pageId; projection = $Projection }
    }

    # zero matches
    if (-not $AllowCreate) {
        return [PSCustomObject]@{ outcome = 'skipped'; reason = 'no-card-no-create' }
    }
    if ($DryRun) {
        return [PSCustomObject]@{ outcome = 'would-create'; projection = $Projection }
    }
    $created = Write-YarnPlanBoardCard -DatabaseId $Config.DatabaseId -ApiKey $ApiKey -Projection $Projection -TimeoutSec $Config.HttpTimeoutSec -Notes $Notes
    return [PSCustomObject]@{ outcome = 'created'; pageId = [string]$created.id; projection = $Projection }
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
        if ([string]::IsNullOrWhiteSpace($name)) { return }

        $ctx = Build-YarnPlanBoardSignalContext -Root $Root -MetraRoot $MetraRoot -CursorPlan $name -BacklogItem $item -PlanLink $link -ExistingPlanBoardCard:$false
        if ($Reason -eq 'LoomAccepted') {
            $ctx | Add-Member -NotePropertyName VerifiedLoomAccepted -NotePropertyValue $true -Force
        }
        $hasYarnOrLoom = (-not [string]::IsNullOrWhiteSpace($ctx.YarnStatus)) -or $ctx.HandoffSucceeded -or $ctx.HasActiveLoomQueue -or $ctx.VerifiedLoomAccepted
        $proj = Resolve-YarnPlanBoardProjection -CursorPlan $ctx.CursorPlan -YarnStatus $ctx.YarnStatus -YarnId $ctx.YarnId `
            -HandoffSucceeded:$ctx.HandoffSucceeded -HasActiveLoomQueue:$ctx.HasActiveLoomQueue `
            -VerifiedLoomAccepted:$ctx.VerifiedLoomAccepted -ExistingPlanBoardCard:$false -Title $ctx.Title
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
        Full catch-up recompute: Yarn backlog + plan-links + Loom queue paths + existing Plan Board cards.
        Event notifies are optional; scan uses -SkipPlanBoard and relies on this (or later lifecycle events).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot,
        [switch]$DryRun
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) { $MetraRoot = Get-YarnHostRoot }
    Initialize-MetraYarnLayout -Root $Root
    $summary = [ordered]@{
        Examined  = 0
        Unchanged = 0
        Updated   = 0
        Created   = 0
        Skipped   = 0
        Failed    = 0
        DryRun    = [bool]$DryRun
        Actions   = @()
    }
    $cfg = Get-YarnPlanBoardConfig -Root $Root -MetraRoot $MetraRoot
    if (-not $cfg.Configured) {
        throw 'Plan Board unconfigured (need DatabaseId in plan-board.settings.json under Yarn root + METRA_NOTION_API_KEY or Atlas notion apiKey).'
    }
    $token = Get-YarnPlanBoardNotionApiKey -MetraRoot $MetraRoot

    $byName = @{}
    $addWork = {
        param($Name, $Item, $Link)
        $n = Get-YarnPlanBoardCursorPlanName -PathOrName $Name
        if ([string]::IsNullOrWhiteSpace($n)) { return }
        $k = $n.ToLowerInvariant()
        if (-not $byName.ContainsKey($k)) {
            $byName[$k] = [PSCustomObject]@{
                CursorPlan = $n
                Item       = $Item
                Link       = $Link
            }
        }
        else {
            $cur = $byName[$k]
            if (-not $cur.Item -and $Item) { $cur | Add-Member -NotePropertyName Item -NotePropertyValue $Item -Force }
            if (-not $cur.Link -and $Link) { $cur | Add-Member -NotePropertyName Link -NotePropertyValue $Link -Force }
        }
    }

    $items = @(Get-MetraYarnBacklog -Root $Root)
    $links = @(Get-YarnPlanLinks -Root $Root)
    foreach ($it in $items) {
        $fp = [string](Get-YarnProp -Object $it -Name 'formalPlanPath' -Default '')
        & $addWork $fp $it $null
    }
    foreach ($lk in $links) {
        $fp = [string](Get-YarnProp -Object $lk -Name 'formalPlanPath' -Default '')
        $bid = [string](Get-YarnProp -Object $lk -Name 'backlogId' -Default '')
        $it = $items | Where-Object { [string]$_.id -eq $bid } | Select-Object -First 1
        & $addWork $fp $it $lk
    }

    # Loom queue paths: include plans that reached Loom even if Yarn formalPlanPath is thin
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
                & $addWork $path $null $null
            }
        }
        catch { }
    }

    # Existing cards for Stage 1 reconciliation
    $existingCards = @()
    try {
        $existingCards = @(Get-YarnPlanBoardAllCards -DatabaseId $cfg.DatabaseId -ApiKey $token -TimeoutSec $cfg.HttpTimeoutSec)
    }
    catch {
        if (-not $DryRun) {
            Write-YarnPlanBoardSyncError -ErrorRecord $_ -Root $Root
        }
        throw
    }
    foreach ($card in $existingCards) {
        & $addWork $card.CursorPlan $null $null
    }

    foreach ($key in @($byName.Keys)) {
        $work = $byName[$key]
        $summary.Examined++
        try {
            $hasCard = $false
            foreach ($c in $existingCards) {
                if (Test-YarnPlanBoardCursorPlanMatch -Left $c.CursorPlan -Right $work.CursorPlan) {
                    $hasCard = $true
                    break
                }
            }
            $ctx = Build-YarnPlanBoardSignalContext -Root $Root -MetraRoot $MetraRoot -CursorPlan $work.CursorPlan `
                -BacklogItem $work.Item -PlanLink $work.Link -ExistingPlanBoardCard:$hasCard
            $proj = Resolve-YarnPlanBoardProjection -CursorPlan $ctx.CursorPlan -YarnStatus $ctx.YarnStatus -YarnId $ctx.YarnId `
                -HandoffSucceeded:$ctx.HandoffSucceeded -HasActiveLoomQueue:$ctx.HasActiveLoomQueue `
                -VerifiedLoomAccepted:$ctx.VerifiedLoomAccepted -ExistingPlanBoardCard:$ctx.ExistingPlanBoardCard -Title $ctx.Title
            $allowCreate = (-not [string]::IsNullOrWhiteSpace($ctx.YarnStatus)) -or $ctx.HandoffSucceeded -or $ctx.HasActiveLoomQueue -or $ctx.VerifiedLoomAccepted
            $r = Invoke-YarnPlanBoardUpsertProjection -Root $Root -Projection $proj -Config $cfg -ApiKey $token -DryRun:$DryRun -AllowCreate:$allowCreate -ExistingCards $existingCards
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
                'unchanged' { $summary.Unchanged++ }
                'updated' { $summary.Updated++ }
                'created' { $summary.Created++ }
                'would-update' { $summary.Updated++ }
                'would-create' { $summary.Created++ }
                'skipped' { $summary.Skipped++ }
                default { $summary.Skipped++ }
            }
        }
        catch {
            $summary.Failed++
            $summary.Actions += [PSCustomObject]@{
                CursorPlan = $work.CursorPlan
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
        if ($summary.Failed -gt 0) {
            $err = [PSCustomObject]@{
                operation = 'plan-board-sync'
                message   = "Completed with $($summary.Failed) item failure(s)."
                at        = (Get-Date).ToUniversalTime().ToString('o')
                retryable = $true
            }
        }
        Save-YarnPlanBoardSyncState -Root $Root -LastError $err -LastSuccessAt ((Get-Date).ToUniversalTime().ToString('o')) -LastSummary ([PSCustomObject]$summary)
    }
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
