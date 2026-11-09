# MemoryBrief.ps1 - Bite 3 structured MDR project briefs (derived / non-authoritative).
# Authority: items.json. brief.md is render-only. Model ops are fail-closed.

$script:MetraBriefOpenCap = 40
$script:MetraBriefHistoryKeep = 10
$script:MetraBriefRenderBudget = 1500
$script:MetraBriefArchiveDays = 30
$script:MetraBriefFreshDays = 7
$script:MetraBriefStaleDays = 30
$script:MetraBriefKinds = @('thread', 'component', 'open_question', 'decision_link')

function Test-MetraAskBriefEnabled {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return [bool]((Get-MetraAskContinuitySettings -MetraRoot $MetraRoot).briefEnabled)
}

function Resolve-MetraBriefRootName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    try {
        $p = Get-MetraProject -Name $Project -MetraRoot $MetraRoot -ErrorAction SilentlyContinue
        $r = [string](Get-MetraProp -Object $p -Name 'Root' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($r)) { return $r.Trim().ToLowerInvariant() }
    }
    catch { }
    return 'work'
}

function New-MetraBriefItemId {
    [CmdletBinding()]
    param()
    return ('bi-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
}

function New-MetraBriefEmptyLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$RootName = 'work'
    )
    return [PSCustomObject]@{
        schemaVersion         = 1
        project               = $Project
        root                  = $RootName
        updatedAt             = (Get-Date).ToUniversalTime().ToString('o')
        lastBriefedSessionId  = ''
        lastBriefedThrough    = 0
        lastBriefedAt         = ''
        items                 = @()
    }
}

function Read-MetraBriefLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$RootName = '',
        [string]$MetraRoot = (Get-MetraRoot)
    )
    if ([string]::IsNullOrWhiteSpace($RootName)) {
        $RootName = Resolve-MetraBriefRootName -Project $Project -MetraRoot $MetraRoot
    }
    $path = Get-MetraMdrBriefItemsPath -Project $Project -RootName $RootName -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) {
        return (New-MetraBriefEmptyLedger -Project $Project -RootName $RootName)
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return (New-MetraBriefEmptyLedger -Project $Project -RootName $RootName)
    }
    $items = @()
    foreach ($it in @((Get-MetraProp -Object $raw -Name 'items' -Default @()))) {
        if ($null -eq $it) { continue }
        $items += , ([PSCustomObject]@{
                id             = [string](Get-MetraProp -Object $it -Name 'id' -Default '')
                kind           = [string](Get-MetraProp -Object $it -Name 'kind' -Default 'thread')
                state          = [string](Get-MetraProp -Object $it -Name 'state' -Default 'open')
                title          = [string](Get-MetraProp -Object $it -Name 'title' -Default '')
                body           = [string](Get-MetraProp -Object $it -Name 'body' -Default '')
                citation       = [string](Get-MetraProp -Object $it -Name 'citation' -Default '')
                pinned         = [bool](Get-MetraProp -Object $it -Name 'pinned' -Default $false)
                corrected      = [bool](Get-MetraProp -Object $it -Name 'corrected' -Default $false)
                needsReview    = [bool](Get-MetraProp -Object $it -Name 'needsReview' -Default $false)
                reviewReason   = [string](Get-MetraProp -Object $it -Name 'reviewReason' -Default '')
                lastChangedAt  = [string](Get-MetraProp -Object $it -Name 'lastChangedAt' -Default '')
                lastChangedTurn = [int](Get-MetraProp -Object $it -Name 'lastChangedTurn' -Default 0)
                decisionId     = [string](Get-MetraProp -Object $it -Name 'decisionId' -Default '')
                source         = [string](Get-MetraProp -Object $it -Name 'source' -Default '')
            })
    }
    return [PSCustomObject]@{
        schemaVersion        = [int](Get-MetraProp -Object $raw -Name 'schemaVersion' -Default 1)
        project              = [string](Get-MetraProp -Object $raw -Name 'project' -Default $Project)
        root                 = [string](Get-MetraProp -Object $raw -Name 'root' -Default $RootName)
        updatedAt            = [string](Get-MetraProp -Object $raw -Name 'updatedAt' -Default '')
        lastBriefedSessionId = [string](Get-MetraProp -Object $raw -Name 'lastBriefedSessionId' -Default '')
        lastBriefedThrough   = [int](Get-MetraProp -Object $raw -Name 'lastBriefedThrough' -Default 0)
        lastBriefedAt        = [string](Get-MetraProp -Object $raw -Name 'lastBriefedAt' -Default '')
        items                = @($items)
    }
}

function Save-MetraBriefLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ledger,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$SkipHistory
    )
    $project = [string](Get-MetraProp -Object $Ledger -Name 'project' -Default '')
    $rootName = [string](Get-MetraProp -Object $Ledger -Name 'root' -Default 'work')
    if ([string]::IsNullOrWhiteSpace($project)) {
        return [PSCustomObject]@{ Ok = $false; Reason = 'missing_project' }
    }
    $Ledger.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    $path = Get-MetraMdrBriefItemsPath -Project $project -RootName $rootName -MetraRoot $MetraRoot
    $dir = Split-Path -Parent $path
    if (-not $SkipHistory) {
        Save-MetraBriefHistorySnapshot -Ledger $Ledger -MetraRoot $MetraRoot | Out-Null
    }
    $json = ($Ledger | ConvertTo-Json -Depth 8)
    $tmp = $path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $path -Force
    $render = Render-MetraBriefMarkdown -Ledger $Ledger
    $renderPath = Get-MetraMdrBriefRenderPath -Project $project -RootName $rootName -MetraRoot $MetraRoot
    [System.IO.File]::WriteAllText($renderPath, $render.Text + "`n", [System.Text.UTF8Encoding]::new($false))
    return [PSCustomObject]@{
        Ok         = $true
        Reason     = 'saved'
        Path       = $path
        RenderPath = $renderPath
        Staleness  = $render.Staleness
        CharCount  = $render.CharCount
    }
}

function Save-MetraBriefHistorySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ledger,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $project = [string]$Ledger.project
    $rootName = [string]$Ledger.root
    $dir = Join-Path (Get-MetraMdrBriefProjectDir -Project $project -RootName $rootName -MetraRoot $MetraRoot) '.history'
    [void][System.IO.Directory]::CreateDirectory($dir)
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfff')
    $path = Join-Path $dir ("items-$stamp.json")
    $payload = [ordered]@{
        schemaVersion = 1
        capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
        project       = $project
        root          = $rootName
        items         = @($Ledger.items)
    }
    [System.IO.File]::WriteAllText(
        $path,
        (($payload | ConvertTo-Json -Depth 8) + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
    $files = @(Get-ChildItem -LiteralPath $dir -Filter 'items-*.json' -File | Sort-Object Name -Descending)
    if ($files.Count -gt $script:MetraBriefHistoryKeep) {
        foreach ($old in @($files | Select-Object -Skip $script:MetraBriefHistoryKeep)) {
            Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    return [PSCustomObject]@{ Ok = $true; Path = $path }
}

function Get-MetraBriefStaleness {
    [CmdletBinding()]
    param([AllowNull()][string]$UpdatedAt)
    if ([string]::IsNullOrWhiteSpace($UpdatedAt)) { return 'needs_revalidation' }
    try {
        $dt = [datetime]::Parse($UpdatedAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        $ageDays = ((Get-Date).ToUniversalTime() - $dt).TotalDays
        if ($ageDays -le $script:MetraBriefFreshDays) { return 'fresh' }
        if ($ageDays -le $script:MetraBriefStaleDays) { return 'likely_stale' }
        return 'needs_revalidation'
    }
    catch {
        return 'needs_revalidation'
    }
}

function Render-MetraBriefMarkdown {
    <#
    .SYNOPSIS
        Render brief.md from items (1500-char budget, locked drop order).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ledger,
        [int]$Budget = 0
    )
    if ($Budget -lt 1) { $Budget = $script:MetraBriefRenderBudget }
    $staleness = Get-MetraBriefStaleness -UpdatedAt ([string](Get-MetraProp -Object $Ledger -Name 'updatedAt' -Default ''))
    $header = "staleness: $staleness"
    $kindOrder = @('thread', 'open_question', 'component', 'decision_link')
    $open = @(
        @($Ledger.items) | Where-Object {
            [string](Get-MetraProp -Object $_ -Name 'state' -Default '') -eq 'open'
        }
    )
    $blocks = [System.Collections.Generic.List[string]]::new()
    foreach ($kind in $kindOrder) {
        $group = @(
            $open | Where-Object {
                [string](Get-MetraProp -Object $_ -Name 'kind' -Default '') -eq $kind
            } | Sort-Object {
                [string](Get-MetraProp -Object $_ -Name 'lastChangedAt' -Default '')
            } -Descending
        )
        foreach ($it in $group) {
            $title = [string](Get-MetraProp -Object $it -Name 'title' -Default '')
            if ([string]::IsNullOrWhiteSpace($title)) {
                $title = [string](Get-MetraProp -Object $it -Name 'body' -Default '')
            }
            $title = $title.Trim()
            if ($title.Length -gt 120) { $title = $title.Substring(0, 117) + '...' }
            $flags = @()
            if ([bool](Get-MetraProp -Object $it -Name 'pinned' -Default $false)) { $flags += 'pinned' }
            if ([bool](Get-MetraProp -Object $it -Name 'corrected' -Default $false)) { $flags += 'corrected' }
            if ([bool](Get-MetraProp -Object $it -Name 'needsReview' -Default $false)) { $flags += 'review' }
            $suffix = if ($flags.Count -gt 0) { ' [' + ($flags -join ',') + ']' } else { '' }
            [void]$blocks.Add("- ($kind) $title$suffix")
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add($header)
    $used = $header.Length + 1
    foreach ($b in $blocks) {
        $need = $b.Length + 1
        if (($used + $need) -gt $Budget) { break }
        [void]$lines.Add($b)
        $used += $need
    }
    $text = ($lines -join "`n").TrimEnd()
    if ($text.Length -gt $Budget) {
        $text = $text.Substring(0, $Budget)
    }
    return [PSCustomObject]@{
        Text      = $text
        Staleness = $staleness
        CharCount = $text.Length
    }
}

function Test-MetraBriefKind {
    [CmdletBinding()]
    param([string]$Kind)
    return ($script:MetraBriefKinds -contains [string]$Kind)
}

function Test-MetraBriefCitationResolves {
    <#
    .SYNOPSIS
        Fail-closed citation check for model ops. Empty AllowedCitations rejects (nothing valid to cite).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Citation,
        [string[]]$AllowedCitations = @()
    )
    if ([string]::IsNullOrWhiteSpace($Citation)) { return $false }
    # Empty allowlist = no resolvable citation exists; never fail-open for model mutations.
    if (@($AllowedCitations).Count -eq 0) { return $false }
    return ($AllowedCitations -contains $Citation)
}

function Test-MetraBriefDecisionIdExists {
    [CmdletBinding()]
    param(
        [string]$DecisionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    if ([string]::IsNullOrWhiteSpace($DecisionId)) { return $false }
    if (-not (Get-Command Get-MetraDecisionRegistryEntry -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        $entry = Get-MetraDecisionRegistryEntry -IdOrTitle $DecisionId -MetraRoot $MetraRoot -ErrorAction SilentlyContinue
        return ($null -ne $entry)
    }
    catch {
        return $false
    }
}

function Invoke-MetraBriefArchiveClosedItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ledger,
        [int]$ArchiveDays = 0
    )
    if ($ArchiveDays -lt 1) { $ArchiveDays = $script:MetraBriefArchiveDays }
    $kept = [System.Collections.Generic.List[object]]::new()
    $now = (Get-Date).ToUniversalTime()
    foreach ($it in @($Ledger.items)) {
        $state = [string](Get-MetraProp -Object $it -Name 'state' -Default 'open')
        if ($state -ne 'closed') {
            [void]$kept.Add($it)
            continue
        }
        $changed = [string](Get-MetraProp -Object $it -Name 'lastChangedAt' -Default '')
        $ageOk = $true
        if ($changed) {
            try {
                $dt = [datetime]::Parse($changed, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
                if (($now - $dt).TotalDays -ge $ArchiveDays) { $ageOk = $false }
            }
            catch { }
        }
        if ($ageOk) { [void]$kept.Add($it) }
    }
    $Ledger.items = @($kept)
    return $Ledger
}

function Apply-MetraBriefItemOps {
    <#
    .SYNOPSIS
        Apply schema-validated create/update/close ops. Fail-closed: invalid batch = no change.
    .NOTES
        Pinned/corrected items: model cannot mutate; may only set needsReview.
        At 40 open items, create is refused (Bing lock).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ledger,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Ops,
        [string[]]$AllowedCitations = @(),
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$FromModel
    )

    $priorItems = @($Ledger.items | ForEach-Object { $_ | ConvertTo-Json -Depth 6 | ConvertFrom-Json })
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($it in @($Ledger.items)) { [void]$items.Add($it) }

    $reject = {
        param([string]$Reason)
        $Ledger.items = @($priorItems)
        return [PSCustomObject]@{
            Ok      = $false
            Reason  = $Reason
            Changed = $false
            Ledger  = $Ledger
        }
    }

    if ($null -eq $Ops) { return (& $reject 'null_ops') }
    $opsList = @($Ops)
    if ($opsList.Count -eq 0) {
        return [PSCustomObject]@{ Ok = $true; Reason = 'no_ops'; Changed = $false; Ledger = $Ledger }
    }

    foreach ($op in $opsList) {
        $action = [string](Get-MetraProp -Object $op -Name 'op' -Default '').ToLowerInvariant()
        if ($action -notin @('create', 'update', 'close')) {
            return (& $reject 'invalid_op')
        }
        $citation = [string](Get-MetraProp -Object $op -Name 'citation' -Default '')
        if ($FromModel -and -not (Test-MetraBriefCitationResolves -Citation $citation -AllowedCitations $AllowedCitations)) {
            return (& $reject 'citation_unresolved')
        }

        if ($action -eq 'create') {
            $kind = [string](Get-MetraProp -Object $op -Name 'kind' -Default '')
            if (-not (Test-MetraBriefKind -Kind $kind)) { return (& $reject 'invalid_kind') }
            $openCount = @($items | Where-Object { [string]$_.state -eq 'open' }).Count
            if ($openCount -ge $script:MetraBriefOpenCap) {
                return (& $reject 'open_cap_refuse_create')
            }
            $decisionId = [string](Get-MetraProp -Object $op -Name 'decisionId' -Default '')
            if ($kind -eq 'decision_link') {
                if (-not (Test-MetraBriefDecisionIdExists -DecisionId $decisionId -MetraRoot $MetraRoot)) {
                    return (& $reject 'decision_id_missing')
                }
            }
            $title = [string](Get-MetraProp -Object $op -Name 'title' -Default '')
            $body = [string](Get-MetraProp -Object $op -Name 'body' -Default '')
            if (Get-Command Invoke-MetraAskSecretsScrubText -ErrorAction SilentlyContinue) {
                $title = [string](Get-MetraProp -Object (Invoke-MetraAskSecretsScrubText -Text $title) -Name 'Text' -Default $title)
                $body = [string](Get-MetraProp -Object (Invoke-MetraAskSecretsScrubText -Text $body) -Name 'Text' -Default $body)
            }
            [void]$items.Add([PSCustomObject]@{
                    id              = New-MetraBriefItemId
                    kind            = $kind
                    state           = 'open'
                    title           = $title
                    body            = $body
                    citation        = $citation
                    pinned          = $false
                    corrected       = $false
                    needsReview     = $false
                    reviewReason    = ''
                    lastChangedAt   = (Get-Date).ToUniversalTime().ToString('o')
                    lastChangedTurn = [int](Get-MetraProp -Object $op -Name 'turnIndex' -Default 0)
                    decisionId      = $decisionId
                    source          = $(if ($FromModel) { 'model' } else { 'operator' })
                })
            continue
        }

        $id = [string](Get-MetraProp -Object $op -Name 'id' -Default '')
        if ([string]::IsNullOrWhiteSpace($id)) { return (& $reject 'missing_id') }
        $idx = -1
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ([string]$items[$i].id -eq $id) { $idx = $i; break }
        }
        if ($idx -lt 0) { return (& $reject 'unknown_id') }
        $target = $items[$idx]
        $protected = [bool]$target.pinned -or [bool]$target.corrected

        if ($FromModel -and $protected) {
            # Model may only flag for review - never mutate body/state/kind.
            $target.needsReview = $true
            $reason = [string](Get-MetraProp -Object $op -Name 'reviewReason' -Default 'new_cited_source')
            if ([string]::IsNullOrWhiteSpace($reason)) { $reason = 'new_cited_source' }
            $target.reviewReason = $reason
            $items[$idx] = $target
            continue
        }

        if ($action -eq 'close') {
            $target.state = 'closed'
            $target.lastChangedAt = (Get-Date).ToUniversalTime().ToString('o')
            $items[$idx] = $target
            continue
        }

        # update
        $newTitle = Get-MetraProp -Object $op -Name 'title' -Default $null
        $newBody = Get-MetraProp -Object $op -Name 'body' -Default $null
        $newKind = Get-MetraProp -Object $op -Name 'kind' -Default $null
        $newDecisionId = Get-MetraProp -Object $op -Name 'decisionId' -Default $null
        if ($null -ne $newKind -and -not [string]::IsNullOrWhiteSpace([string]$newKind)) {
            if (-not (Test-MetraBriefKind -Kind ([string]$newKind))) { return (& $reject 'invalid_kind') }
            $target.kind = [string]$newKind
        }
        if ($null -ne $newDecisionId) {
            $target.decisionId = [string]$newDecisionId
        }
        $effectiveKind = [string](Get-MetraProp -Object $target -Name 'kind' -Default '')
        if ($effectiveKind -eq 'decision_link') {
            $effectiveDecisionId = [string](Get-MetraProp -Object $target -Name 'decisionId' -Default '')
            if (-not (Test-MetraBriefDecisionIdExists -DecisionId $effectiveDecisionId -MetraRoot $MetraRoot)) {
                return (& $reject 'decision_id_missing')
            }
        }
        if ($null -ne $newTitle) {
            $t = [string]$newTitle
            if (Get-Command Invoke-MetraAskSecretsScrubText -ErrorAction SilentlyContinue) {
                $t = [string](Get-MetraProp -Object (Invoke-MetraAskSecretsScrubText -Text $t) -Name 'Text' -Default $t)
            }
            $target.title = $t
        }
        if ($null -ne $newBody) {
            $b = [string]$newBody
            if (Get-Command Invoke-MetraAskSecretsScrubText -ErrorAction SilentlyContinue) {
                $b = [string](Get-MetraProp -Object (Invoke-MetraAskSecretsScrubText -Text $b) -Name 'Text' -Default $b)
            }
            $target.body = $b
        }
        if (-not [string]::IsNullOrWhiteSpace($citation)) { $target.citation = $citation }
        $target.lastChangedAt = (Get-Date).ToUniversalTime().ToString('o')
        $items[$idx] = $target
    }

    $Ledger.items = @($items)
    $Ledger = Invoke-MetraBriefArchiveClosedItems -Ledger $Ledger
    return [PSCustomObject]@{
        Ok      = $true
        Reason  = 'applied'
        Changed = $true
        Ledger  = $Ledger
    }
}

function Add-MetraBriefNoteItem {
    <#
    .SYNOPSIS
        Operator brief note: creates an item with explicit -Kind. Note text is untrusted data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][ValidateSet('thread', 'component', 'open_question', 'decision_link')][string]$Kind,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$DecisionId = '',
        [string]$SessionId = '',
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$EnqueueWorker
    )

    if (-not (Test-MetraAskBriefEnabled -MetraRoot $MetraRoot)) {
        return [PSCustomObject]@{ Ok = $false; Reason = 'disabled' }
    }
    $rootName = Resolve-MetraBriefRootName -Project $Project -MetraRoot $MetraRoot
    $mutexName = 'mdr-brief-' + ($Project -replace '[^A-Za-z0-9]', '')
    return Invoke-MetraWithNamedMutex -Name $mutexName -Script {
        $ledger = Read-MetraBriefLedger -Project $Project -RootName $rootName -MetraRoot $MetraRoot
        $citation = 'note:' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        # Frame note as quoted data - never as instructions for later model ops.
        $safeBody = ('OPERATOR_NOTE: """' + ($Text -replace '"', "'") + '"""')
        $op = [PSCustomObject]@{
            op         = 'create'
            kind       = $Kind
            title      = $(if ($Text.Length -gt 80) { $Text.Substring(0, 77) + '...' } else { $Text })
            body       = $safeBody
            citation   = $citation
            decisionId = $DecisionId
        }
        $applied = Apply-MetraBriefItemOps -Ledger $ledger -Ops @($op) -AllowedCitations @($citation) -MetraRoot $MetraRoot
        if (-not [bool]$applied.Ok) {
            return [PSCustomObject]@{ Ok = $false; Reason = [string]$applied.Reason; Changed = $false }
        }
        $saved = Save-MetraBriefLedger -Ledger $applied.Ledger -MetraRoot $MetraRoot
        if ($EnqueueWorker -and -not [string]::IsNullOrWhiteSpace($SessionId)) {
            Request-MetraProjectBriefRefresh -Project $Project -SessionId $SessionId -MetraRoot $MetraRoot -StartWorker | Out-Null
        }
        return [PSCustomObject]@{
            Ok     = [bool]$saved.Ok
            Reason = [string]$saved.Reason
            Ledger = $applied.Ledger
            ItemId = @($applied.Ledger.items | Where-Object { $_.citation -eq $citation } | Select-Object -First 1).id
        }
    }
}

function Set-MetraBriefItemCorrected {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$ItemId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Body,
        [string]$Title = '',
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $rootName = Resolve-MetraBriefRootName -Project $Project -MetraRoot $MetraRoot
    $mutexName = 'mdr-brief-' + ($Project -replace '[^A-Za-z0-9]', '')
    return Invoke-MetraWithNamedMutex -Name $mutexName -Script {
        $ledger = Read-MetraBriefLedger -Project $Project -RootName $rootName -MetraRoot $MetraRoot
        $found = $false
        $items = [System.Collections.Generic.List[object]]::new()
        $scrubBody = $Body
        $scrubTitle = $Title
        if (Get-Command Invoke-MetraAskSecretsScrubText -ErrorAction SilentlyContinue) {
            $scrubBody = [string](Get-MetraProp -Object (Invoke-MetraAskSecretsScrubText -Text $Body) -Name 'Text' -Default $Body)
            if (-not [string]::IsNullOrWhiteSpace($Title)) {
                $scrubTitle = [string](Get-MetraProp -Object (Invoke-MetraAskSecretsScrubText -Text $Title) -Name 'Text' -Default $Title)
            }
        }
        foreach ($it in @($ledger.items)) {
            if ([string]$it.id -eq $ItemId) {
                $found = $true
                $it.body = $scrubBody
                if (-not [string]::IsNullOrWhiteSpace($scrubTitle)) { $it.title = $scrubTitle }
                $it.corrected = $true
                $it.needsReview = $false
                $it.reviewReason = ''
                $it.lastChangedAt = (Get-Date).ToUniversalTime().ToString('o')
                $it.source = 'operator-correct'
            }
            [void]$items.Add($it)
        }
        if (-not $found) {
            return [PSCustomObject]@{ Ok = $false; Reason = 'not_found' }
        }
        $ledger.items = @($items)
        $saved = Save-MetraBriefLedger -Ledger $ledger -MetraRoot $MetraRoot
        return [PSCustomObject]@{ Ok = [bool]$saved.Ok; Reason = 'corrected'; Ledger = $ledger }
    }
}

function Set-MetraBriefItemPinned {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$ItemId,
        [bool]$Pinned = $true,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $rootName = Resolve-MetraBriefRootName -Project $Project -MetraRoot $MetraRoot
    $mutexName = 'mdr-brief-' + ($Project -replace '[^A-Za-z0-9]', '')
    return Invoke-MetraWithNamedMutex -Name $mutexName -Script {
        $ledger = Read-MetraBriefLedger -Project $Project -RootName $rootName -MetraRoot $MetraRoot
        $found = $false
        foreach ($it in @($ledger.items)) {
            if ([string]$it.id -eq $ItemId) {
                $it.pinned = [bool]$Pinned
                $it.lastChangedAt = (Get-Date).ToUniversalTime().ToString('o')
                $found = $true
            }
        }
        if (-not $found) { return [PSCustomObject]@{ Ok = $false; Reason = 'not_found' } }
        $saved = Save-MetraBriefLedger -Ledger $ledger -MetraRoot $MetraRoot
        return [PSCustomObject]@{ Ok = [bool]$saved.Ok; Reason = $(if ($Pinned) { 'pinned' } else { 'unpinned' }); Ledger = $ledger }
    }
}

function Get-MetraAskTurnProject {
    <#
    .SYNOPSIS
        Routed project for a journal turn (top-level project, else handoff.where).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Turn)
    $p = [string](Get-MetraProp -Object $Turn -Name 'project' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($p)) { return $p.Trim() }
    $h = Get-MetraProp -Object $Turn -Name 'handoff' -Default $null
    $w = [string](Get-MetraProp -Object $h -Name 'where' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($w)) { return $w.Trim() }
    return ''
}

function Select-MetraBriefSessionTurnsForProject {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Turns,
        [Parameter(Mandatory)][string]$Project
    )
    $want = $Project.Trim()
    return @(
        $Turns | Where-Object {
            $tp = Get-MetraAskTurnProject -Turn $_
            -not [string]::IsNullOrWhiteSpace($tp) -and
            [string]::Equals($tp, $want, [System.StringComparison]::OrdinalIgnoreCase)
        }
    )
}

function New-MetraBriefExtractiveOps {
    <#
    .SYNOPSIS
        Deterministic cited create ops from project-filtered turns (engine fallback / mocks).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Turns,
        [int]$MaxCreates = 3
    )
    $ops = [System.Collections.Generic.List[object]]::new()
    $take = @($Turns | Select-Object -Last ([Math]::Max(1, $MaxCreates)))
    foreach ($t in $take) {
        $ti = [int](Get-MetraProp -Object $t -Name 'turnIndex' -Default 0)
        if ($ti -lt 1) { continue }
        $prompt = [string](Get-MetraProp -Object $t -Name 'prompt' -Default '')
        if ([string]::IsNullOrWhiteSpace($prompt)) { continue }
        [void]$ops.Add([PSCustomObject]@{
                op        = 'create'
                kind      = 'thread'
                title     = $(if ($prompt.Length -gt 60) { $prompt.Substring(0, 57) + '...' } else { $prompt })
                body      = $prompt
                citation  = "turn:${ti}"
                turnIndex = $ti
            })
    }
    return @($ops)
}

function ConvertFrom-MetraBriefOpsJson {
    <#
    .SYNOPSIS
        Parse model JSON ops. Distinguishes intentional empty ([] / {ops:[]}) from parse failure.
    .OUTPUTS
        PSCustomObject with Ok, Ops, Reason (empty_ok | parsed | parse_error | no_ops_shape).
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [PSCustomObject]@{ Ok = $false; Ops = @(); Reason = 'empty_text' }
    }
    $raw = $Text.Trim()
    # Strip optional markdown fence.
    if ($raw -match '(?s)```(?:json)?\s*(.*?)```') {
        $raw = $Matches[1].Trim()
    }
    try {
        $parsed = $raw | ConvertFrom-Json
    }
    catch {
        return [PSCustomObject]@{ Ok = $false; Ops = @(); Reason = 'parse_error' }
    }
    if ($null -eq $parsed) {
        return [PSCustomObject]@{ Ok = $false; Ops = @(); Reason = 'null_json' }
    }
    # Intentional empty array [] (ConvertFrom-Json yields Object[] with Count 0).
    if ($parsed -is [System.Array] -and @($parsed).Count -eq 0) {
        return [PSCustomObject]@{ Ok = $true; Ops = @(); Reason = 'empty_ok' }
    }
    if ($parsed -is [System.Array] -or $parsed -is [System.Collections.IEnumerable]) {
        $list = @($parsed)
        if ($list.Count -eq 1 -and $null -ne (Get-MetraProp -Object $list[0] -Name 'op' -Default $null)) {
            return [PSCustomObject]@{ Ok = $true; Ops = @($list[0]); Reason = 'parsed' }
        }
        if ($list.Count -ge 1 -and $null -ne (Get-MetraProp -Object $list[0] -Name 'op' -Default $null)) {
            return [PSCustomObject]@{ Ok = $true; Ops = @($list); Reason = 'parsed' }
        }
        $inner = Get-MetraProp -Object $parsed -Name 'ops' -Default $null
        if ($null -ne $inner) {
            $innerList = @($inner)
            return [PSCustomObject]@{
                Ok     = $true
                Ops    = $innerList
                Reason = $(if ($innerList.Count -eq 0) { 'empty_ok' } else { 'parsed' })
            }
        }
    }
    if ($null -ne (Get-MetraProp -Object $parsed -Name 'op' -Default $null)) {
        return [PSCustomObject]@{ Ok = $true; Ops = @($parsed); Reason = 'parsed' }
    }
    $inner2 = Get-MetraProp -Object $parsed -Name 'ops' -Default $null
    if ($null -ne $inner2) {
        $innerList2 = @($inner2)
        return [PSCustomObject]@{
            Ok     = $true
            Ops    = $innerList2
            Reason = $(if ($innerList2.Count -eq 0) { 'empty_ok' } else { 'parsed' })
        }
    }
    return [PSCustomObject]@{ Ok = $false; Ops = @(); Reason = 'no_ops_shape' }
}

function Invoke-MetraAskBriefOpsFromEngine {
    <#
    .SYNOPSIS
        Inspect-pin (ask-fallback) JSON item ops for a project brief update.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Turns,
        [AllowNull()]$Ledger,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 90
    )

    if (@($Turns).Count -eq 0) {
        return [PSCustomObject]@{ Ok = $false; Reason = 'no_project_turns'; Ops = @() }
    }

    $selection = $null
    if (Get-Command Resolve-MetraInspectEngineSelection -ErrorAction SilentlyContinue) {
        $selection = Resolve-MetraInspectEngineSelection -MetraRoot $MetraRoot
    }
    $engine = 'ollama'
    $model = ''
    if ($null -ne $selection) {
        $engine = [string](Get-MetraProp -Object $selection -Name 'Engine' -Default 'ollama')
        $model = [string](Get-MetraProp -Object $selection -Name 'RequestedModel' -Default '')
    }

    $turnLines = foreach ($t in @($Turns)) {
        $ti = [int](Get-MetraProp -Object $t -Name 'turnIndex' -Default 0)
        $prompt = [string](Get-MetraProp -Object $t -Name 'prompt' -Default '')
        $msg = [string](Get-MetraProp -Object $t -Name 'message' -Default '')
        if (Get-Command Invoke-MetraAskSecretsScrubText -ErrorAction SilentlyContinue) {
            $prompt = [string](Get-MetraProp -Object (Invoke-MetraAskSecretsScrubText -Text $prompt) -Name 'Text' -Default $prompt)
            $msg = [string](Get-MetraProp -Object (Invoke-MetraAskSecretsScrubText -Text $msg) -Name 'Text' -Default $msg)
        }
        "Turn ${ti}: Q=$prompt | A=$msg"
    }
    $existing = foreach ($it in @((Get-MetraProp -Object $Ledger -Name 'items' -Default @()))) {
        $id = [string](Get-MetraProp -Object $it -Name 'id' -Default '')
        $kind = [string](Get-MetraProp -Object $it -Name 'kind' -Default '')
        $title = [string](Get-MetraProp -Object $it -Name 'title' -Default '')
        $state = [string](Get-MetraProp -Object $it -Name 'state' -Default '')
        $flags = @()
        if ([bool](Get-MetraProp -Object $it -Name 'pinned' -Default $false)) { $flags += 'pinned' }
        if ([bool](Get-MetraProp -Object $it -Name 'corrected' -Default $false)) { $flags += 'corrected' }
        "- id=$id kind=$kind state=$state title=$title flags=$($flags -join ',')"
    }
    $prompt = @"
You update a Metra MDR project brief for project '$Project' using JSON item operations only.
Return ONLY a JSON array of ops. No markdown fences. No prose.
Each op is one of:
{"op":"create","kind":"thread|component|open_question|decision_link","title":"...","body":"...","citation":"turn:N"}
{"op":"update","id":"bi-...","title":"...","body":"...","citation":"turn:N"}
{"op":"close","id":"bi-...","citation":"turn:N"}
Rules:
- citation must be turn:N for a turn listed below.
- Do not invent facts. Prefer durable project/routing threads.
- Never mutate pinned or corrected items (omit them; a later pass may flag review).
- Prefer at most 5 ops. Empty array [] is valid when nothing changed.

Existing items:
$((@($existing) -join "`n"))

Project turns:
$((@($turnLines) -join "`n"))
"@

    if (-not (Get-Command Invoke-MetraAskEngine -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{
            Ok     = $true
            Reason = 'engine_unavailable_extractive'
            Ops    = @(New-MetraBriefExtractiveOps -Turns $Turns)
            Path   = 'extractive'
        }
    }

    try {
        $engineResult = Invoke-MetraAskEngine -Prompt $prompt -Cwd $MetraRoot -MetraRoot $MetraRoot `
            -Context @{ purpose = 'metra-project-brief'; project = $Project } `
            -TimeoutSec $TimeoutSec -Engine $engine -Model $model
    }
    catch {
        return [PSCustomObject]@{
            Ok     = $true
            Reason = 'engine_throw_extractive'
            Ops    = @(New-MetraBriefExtractiveOps -Turns $Turns)
            Path   = 'extractive'
        }
    }

    if (-not [bool](Get-MetraProp -Object $engineResult -Name 'ok' -Default $false)) {
        return [PSCustomObject]@{
            Ok     = $true
            Reason = 'engine_failed_extractive'
            Ops    = @(New-MetraBriefExtractiveOps -Turns $Turns)
            Path   = 'extractive'
        }
    }

    $text = [string](Get-MetraProp -Object $engineResult -Name 'text' -Default '')
    if ([string]::IsNullOrWhiteSpace($text)) {
        $text = [string](Get-MetraProp -Object $engineResult -Name 'message' -Default '')
    }
    $parsedOps = ConvertFrom-MetraBriefOpsJson -Text $text
    if ([bool]$parsedOps.Ok -and [string]$parsedOps.Reason -eq 'empty_ok') {
        # Model intentionally returned [] / {ops:[]} - do not force extractive creates.
        return [PSCustomObject]@{
            Ok     = $true
            Reason = 'model_noop'
            Ops    = @()
            Path   = 'inspect-pin'
            Engine = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default $engine)
            Model  = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default $model)
        }
    }
    $ops = @($parsedOps.Ops)
    if (-not [bool]$parsedOps.Ok -or $ops.Count -eq 0) {
        return [PSCustomObject]@{
            Ok     = $true
            Reason = 'uncited_or_empty_extractive'
            Ops    = @(New-MetraBriefExtractiveOps -Turns $Turns)
            Path   = 'extractive'
        }
    }
    return [PSCustomObject]@{
        Ok     = $true
        Reason = 'model'
        Ops    = $ops
        Path   = 'inspect-pin'
        Engine = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default $engine)
        Model  = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default $model)
    }
}

function Test-MetraBriefAlreadyApplied {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ledger,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][int]$ThroughTurnIndex
    )
    $lastSid = [string](Get-MetraProp -Object $Ledger -Name 'lastBriefedSessionId' -Default '')
    $lastThrough = [int](Get-MetraProp -Object $Ledger -Name 'lastBriefedThrough' -Default 0)
    return (
        [string]::Equals($lastSid, $SessionId, [System.StringComparison]::OrdinalIgnoreCase) -and
        $lastThrough -ge $ThroughTurnIndex
    )
}

function Request-MetraProjectBriefRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$SessionId,
        [int]$ThroughTurnIndex = 0,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$StartWorker,
        [switch]$Force
    )
    if (-not (Test-MetraAskBriefEnabled -MetraRoot $MetraRoot)) {
        return [PSCustomObject]@{ Ok = $true; Reason = 'disabled'; Queued = $false }
    }
    $allTurns = @(Get-MetraDeskAskSessionTurns -SessionId $SessionId -MetraRoot $MetraRoot -Limit 0)
    $projTurns = @(Select-MetraBriefSessionTurnsForProject -Turns $allTurns -Project $Project)
    if ($ThroughTurnIndex -lt 1) {
        if ($projTurns.Count -gt 0) {
            $ThroughTurnIndex = [int](Get-MetraProp -Object ($projTurns | Select-Object -Last 1) -Name 'turnIndex' -Default $projTurns.Count)
        }
        elseif ($allTurns.Count -gt 0) {
            $ThroughTurnIndex = [int](Get-MetraProp -Object ($allTurns | Select-Object -Last 1) -Name 'turnIndex' -Default $allTurns.Count)
        }
        else {
            $ThroughTurnIndex = 1
        }
    }
    if ($projTurns.Count -eq 0 -and -not $Force) {
        return [PSCustomObject]@{ Ok = $true; Reason = 'no_project_turns'; Queued = $false }
    }

    $rootName = Resolve-MetraBriefRootName -Project $Project -MetraRoot $MetraRoot
    $ledger = Read-MetraBriefLedger -Project $Project -RootName $rootName -MetraRoot $MetraRoot
    if (-not $Force -and (Test-MetraBriefAlreadyApplied -Ledger $ledger -SessionId $SessionId -ThroughTurnIndex $ThroughTurnIndex)) {
        if (Get-Command Set-MetraAskSessionBriefedThrough -ErrorAction SilentlyContinue) {
            Set-MetraAskSessionBriefedThrough -SessionId $SessionId -Project $Project `
                -ThroughTurnIndex $ThroughTurnIndex -MetraRoot $MetraRoot | Out-Null
        }
        return [PSCustomObject]@{ Ok = $true; Reason = 'already_briefed'; Queued = $false }
    }

    $rev = "brief:${Project}:${SessionId}:${ThroughTurnIndex}"
    $item = New-MetraMemoryQueueItem -Type project-brief -SessionId $SessionId `
        -ThroughTurnIndex $ThroughTurnIndex -Project $Project -SourceRevision $rev
    $queued = Add-MetraMemoryQueueItem -Item $item -MetraRoot $MetraRoot
    if ($StartWorker -or [bool]$queued.Queued) {
        Start-MetraMemoryWorkerBestEffort -MetraRoot $MetraRoot | Out-Null
    }
    return $queued
}

function Request-MetraProjectBriefCatchUpIfDue {
    <#
    .SYNOPSIS
        Enqueue brief update for a prior idle session (>=15m) that still needs briefing.
    .NOTES
        Index-only scan: uses routedProjects / projectTurnMax / briefedThroughByProject on the
        ask-sessions index. Does not open session files for already-briefed or out-of-window rows.
        Bound to sessions with lastActivityAt within MaxAgeDays (default 7).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$CurrentSessionId = '',
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$IdleMinutes = 15,
        [int]$MaxAgeDays = 7,
        [switch]$StartWorker
    )
    if (-not (Test-MetraAskBriefEnabled -MetraRoot $MetraRoot)) {
        return [PSCustomObject]@{ Ok = $true; Reason = 'disabled'; Queued = $false }
    }
    if ($IdleMinutes -lt 1) { $IdleMinutes = 15 }
    if ($MaxAgeDays -lt 1) { $MaxAgeDays = 7 }
    $want = $Project.Trim()
    if ([string]::IsNullOrWhiteSpace($want)) {
        return [PSCustomObject]@{ Ok = $true; Reason = 'no_project'; Queued = $false }
    }

    Ensure-MetraAskJournalStore -MetraRoot $MetraRoot
    $index = Read-MetraAskSessionsIndex -MetraRoot $MetraRoot
    $sessions = @(
        @($index.sessions) | Sort-Object {
            [string](Get-MetraProp -Object $_ -Name 'lastActivityAt' -Default '')
        } -Descending
    )
    $now = (Get-Date).ToUniversalTime()
    foreach ($row in $sessions) {
        $sid = [string](Get-MetraProp -Object $row -Name 'sessionId' -Default '')
        if ([string]::IsNullOrWhiteSpace($sid)) { continue }
        if ($CurrentSessionId -and [string]::Equals($sid, $CurrentSessionId, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $atText = [string](Get-MetraProp -Object $row -Name 'lastActivityAt' -Default '')
        if ([string]::IsNullOrWhiteSpace($atText)) { continue }
        try {
            $at = [datetime]::Parse($atText, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        }
        catch { continue }
        # Newest-first: once past the age window, remaining rows are older.
        if (($now - $at).TotalDays -gt $MaxAgeDays) { break }
        if (($now - $at).TotalMinutes -lt $IdleMinutes) { continue }

        $routed = @(
            @((Get-MetraProp -Object $row -Name 'routedProjects' -Default @())) |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        # Legacy index rows without routedProjects: skip without opening session files.
        if ($routed.Count -eq 0) { continue }
        $hasProject = $false
        foreach ($rp in $routed) {
            if ([string]::Equals($rp, $want, [System.StringComparison]::OrdinalIgnoreCase)) {
                $hasProject = $true
                break
            }
        }
        if (-not $hasProject) { continue }

        $turnMax = Get-MetraAskIndexMapInt -Map (Get-MetraProp -Object $row -Name 'projectTurnMax' -Default $null) `
            -Key $want -Default 0
        if ($turnMax -lt 1) { continue }
        $briefedThrough = Get-MetraAskIndexMapInt -Map (Get-MetraProp -Object $row -Name 'briefedThroughByProject' -Default $null) `
            -Key $want -Default 0
        if ($briefedThrough -ge $turnMax) { continue }

        $queued = Request-MetraProjectBriefRefresh -Project $want -SessionId $sid `
            -ThroughTurnIndex $turnMax -MetraRoot $MetraRoot -StartWorker:$StartWorker
        if ([bool](Get-MetraProp -Object $queued -Name 'Queued' -Default $false)) {
            return $queued
        }
        $qReason = [string](Get-MetraProp -Object $queued -Name 'Reason' -Default '')
        if ($qReason -eq 'already_briefed') {
            # Ledger says briefed - sync index so later Ask turns stay index-only.
            if (Get-Command Set-MetraAskSessionBriefedThrough -ErrorAction SilentlyContinue) {
                Set-MetraAskSessionBriefedThrough -SessionId $sid -Project $want `
                    -ThroughTurnIndex $turnMax -MetraRoot $MetraRoot | Out-Null
            }
            continue
        }
        if ($qReason -in @('no_project_turns', 'no_turns', 'disabled')) {
            continue
        }
        return $queued
    }
    return [PSCustomObject]@{ Ok = $true; Reason = 'no_idle_session'; Queued = $false }
}

function Request-MetraProjectBriefClose {
    <#
    .SYNOPSIS
        Explicit session-end brief enqueue for a project.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$StartWorker
    )
    return Request-MetraProjectBriefRefresh -Project $Project -SessionId $SessionId `
        -MetraRoot $MetraRoot -StartWorker:$StartWorker -Force
}

function Invoke-MetraMemoryProjectBriefJob {
    <#
    .SYNOPSIS
        Drain handler for type=project-brief. Applies JSON ops (mock or live Inspect-pin).
    .NOTES
        Session turns are filtered to the queue item's project before any model/mock ops.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        [scriptblock]$OpsScript,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 0
    )

    $project = [string](Get-MetraProp -Object $Item -Name 'project' -Default '')
    $sid = [string](Get-MetraProp -Object $Item -Name 'sessionId' -Default '')
    $through = [int](Get-MetraProp -Object $Item -Name 'throughTurnIndex' -Default 0)
    if ([string]::IsNullOrWhiteSpace($project)) {
        return [PSCustomObject]@{ Ok = $false; Reason = 'bad_item'; Written = $false }
    }
    if ($TimeoutSec -lt 1) { $TimeoutSec = Get-MetraAskSummaryItemTimeoutSec }
    $rootName = Resolve-MetraBriefRootName -Project $project -MetraRoot $MetraRoot
    $allTurns = @(Get-MetraDeskAskSessionTurns -SessionId $sid -MetraRoot $MetraRoot -Limit 0)
    $turns = @(Select-MetraBriefSessionTurnsForProject -Turns $allTurns -Project $project)
    if ($through -gt 0) {
        $turns = @(
            $turns | Where-Object {
                [int](Get-MetraProp -Object $_ -Name 'turnIndex' -Default 0) -le $through
            }
        )
    }

    $allowed = @(
        $turns | ForEach-Object {
            $ti = [int](Get-MetraProp -Object $_ -Name 'turnIndex' -Default 0)
            if ($ti -gt 0) { "turn:${ti}" }
        }
    )
    $ledger = Read-MetraBriefLedger -Project $project -RootName $rootName -MetraRoot $MetraRoot
    foreach ($it in @($ledger.items)) {
        $c = [string](Get-MetraProp -Object $it -Name 'citation' -Default '')
        if ($c) { $allowed += $c }
    }

    $syncBriefedIndex = {
        param([int]$Through)
        if ($Through -lt 1) { return }
        if (Get-Command Set-MetraAskSessionBriefedThrough -ErrorAction SilentlyContinue) {
            Set-MetraAskSessionBriefedThrough -SessionId $sid -Project $project `
                -ThroughTurnIndex $Through -MetraRoot $MetraRoot | Out-Null
        }
    }

    if (Test-MetraBriefAlreadyApplied -Ledger $ledger -SessionId $sid -ThroughTurnIndex $through) {
        $mark = [Math]::Max($through, [int](Get-MetraProp -Object $ledger -Name 'lastBriefedThrough' -Default 0))
        & $syncBriefedIndex $mark
        return [PSCustomObject]@{ Ok = $true; Reason = 'already_briefed'; Written = $false }
    }

    $ops = @()
    $pathLabel = 'none'
    if ($null -ne $OpsScript) {
        # Tests may inject ops; still pass project-filtered turns only.
        $ops = @(& $OpsScript -Project $project -SessionId $sid -Turns $turns -Ledger $ledger)
        $pathLabel = 'mock'
    }
    else {
        $envMock = [string]$env:METRA_MEMORY_WORKER_MOCK
        if ($envMock -eq 'brief-noop') {
            return [PSCustomObject]@{ Ok = $true; Reason = 'env_mock_noop'; Written = $false }
        }
        if ($envMock -eq 'brief-ops' -or $envMock -eq 'cited' -or $envMock -eq 'hang') {
            if ($envMock -eq 'hang') {
                # Hard-bounded by worker item timeout when called under drain wrapper paths.
                Start-Sleep -Seconds ([Math]::Max(600, $TimeoutSec + 60))
            }
            $ops = @(New-MetraBriefExtractiveOps -Turns $turns)
            $pathLabel = 'env-mock'
        }
        else {
            $model = Invoke-MetraAskBriefOpsFromEngine -Project $project -Turns $turns `
                -Ledger $ledger -MetraRoot $MetraRoot -TimeoutSec $TimeoutSec
            $ops = @($model.Ops)
            $pathLabel = [string](Get-MetraProp -Object $model -Name 'Path' -Default 'model')
        }
    }

    $mutexName = 'mdr-brief-' + ($project -replace '[^A-Za-z0-9]', '')
    $jobResult = Invoke-MetraWithNamedMutex -Name $mutexName -Script {
        $current = Read-MetraBriefLedger -Project $project -RootName $rootName -MetraRoot $MetraRoot
        if (Test-MetraBriefAlreadyApplied -Ledger $current -SessionId $sid -ThroughTurnIndex $through) {
            return [PSCustomObject]@{ Ok = $true; Reason = 'already_briefed'; Written = $false; SyncThrough = [Math]::Max($through, [int](Get-MetraProp -Object $current -Name 'lastBriefedThrough' -Default 0)) }
        }
        $applied = Apply-MetraBriefItemOps -Ledger $current -Ops $ops -AllowedCitations $allowed `
            -MetraRoot $MetraRoot -FromModel
        if (-not [bool]$applied.Ok) {
            return [PSCustomObject]@{
                Ok      = $true
                Reason  = 'ops_rejected_' + [string]$applied.Reason
                Written = $false
                Path    = $pathLabel
            }
        }
        $outLedger = $applied.Ledger
        $outLedger | Add-Member -NotePropertyName lastBriefedSessionId -NotePropertyValue $sid -Force
        $outLedger | Add-Member -NotePropertyName lastBriefedThrough -NotePropertyValue $through -Force
        $outLedger | Add-Member -NotePropertyName lastBriefedAt -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
        if (-not [bool]$applied.Changed -and @($ops).Count -eq 0) {
            $savedNoop = Save-MetraBriefLedger -Ledger $outLedger -MetraRoot $MetraRoot -SkipHistory
            return [PSCustomObject]@{
                Ok          = [bool]$savedNoop.Ok
                Reason      = 'marked_briefed_no_ops'
                Written     = [bool]$savedNoop.Ok
                Path        = $pathLabel
                SyncThrough = $through
            }
        }
        if (-not [bool]$applied.Changed) {
            $savedMark = Save-MetraBriefLedger -Ledger $outLedger -MetraRoot $MetraRoot -SkipHistory
            return [PSCustomObject]@{
                Ok          = [bool]$savedMark.Ok
                Reason      = 'unchanged'
                Written     = [bool]$savedMark.Ok
                Path        = $pathLabel
                SyncThrough = $through
            }
        }
        $saved = Save-MetraBriefLedger -Ledger $outLedger -MetraRoot $MetraRoot
        return [PSCustomObject]@{
            Ok          = [bool]$saved.Ok
            Reason      = [string]$saved.Reason
            Written     = [bool]$saved.Ok
            Path        = $pathLabel
            SyncThrough = $(if ([bool]$saved.Ok) { $through } else { 0 })
        }
    }
    $syncThrough = [int](Get-MetraProp -Object $jobResult -Name 'SyncThrough' -Default 0)
    if ($syncThrough -gt 0) { & $syncBriefedIndex $syncThrough }
    return $jobResult
}

function Get-MetraBriefShow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $rootName = Resolve-MetraBriefRootName -Project $Project -MetraRoot $MetraRoot
    $ledger = Read-MetraBriefLedger -Project $Project -RootName $rootName -MetraRoot $MetraRoot
    $render = Render-MetraBriefMarkdown -Ledger $ledger
    return [PSCustomObject]@{
        project    = $Project
        root       = $rootName
        updatedAt  = [string]$ledger.updatedAt
        staleness  = $render.Staleness
        itemCount  = @($ledger.items).Count
        openCount  = @($ledger.items | Where-Object { $_.state -eq 'open' }).Count
        text       = $render.Text
        charCount  = $render.CharCount
        itemsPath  = (Get-MetraMdrBriefItemsPath -Project $Project -RootName $rootName -MetraRoot $MetraRoot)
        renderPath = (Get-MetraMdrBriefRenderPath -Project $Project -RootName $rootName -MetraRoot $MetraRoot)
        items      = @($ledger.items)
    }
}

function Invoke-MetraBriefRebuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $rootName = Resolve-MetraBriefRootName -Project $Project -MetraRoot $MetraRoot
    $ledger = Read-MetraBriefLedger -Project $Project -RootName $rootName -MetraRoot $MetraRoot
    $ledger = Invoke-MetraBriefArchiveClosedItems -Ledger $ledger
    return Save-MetraBriefLedger -Ledger $ledger -MetraRoot $MetraRoot
}

function Invoke-MetraBriefCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $parseKv = {
        param([string[]]$argsIn)
        $map = @{}
        $positional = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt @($argsIn).Count; $i++) {
            $a = [string]$argsIn[$i]
            if ($a -match '^-(Kind|DecisionId|SessionId|Title)$' -and ($i + 1) -lt $argsIn.Count) {
                $map[$Matches[1]] = [string]$argsIn[$i + 1]
                $i++
                continue
            }
            if ($a -eq '-Unpin') { $map['Unpin'] = $true; continue }
            [void]$positional.Add($a)
        }
        return [PSCustomObject]@{ Map = $map; Positional = @($positional) }
    }

    switch ($Subcommand.ToLowerInvariant()) {
        'show' {
            if ($ArgsRest.Count -lt 1) { throw "brief show requires a project. Example: .\metra.ps1 brief show Metra" }
            return Get-MetraBriefShow -Project ([string]$ArgsRest[0]) -MetraRoot $MetraRoot
        }
        'note' {
            $parsed = & $parseKv $ArgsRest
            if ($parsed.Positional.Count -lt 2) {
                throw 'brief note requires <project> -Kind <kind> "<text>".'
            }
            $kind = [string]$parsed.Map['Kind']
            if ([string]::IsNullOrWhiteSpace($kind)) {
                throw 'brief note requires -Kind thread|component|open_question|decision_link.'
            }
            $project = [string]$parsed.Positional[0]
            $text = [string]$parsed.Positional[1]
            $decisionId = [string]$parsed.Map['DecisionId']
            $sessionId = [string]$parsed.Map['SessionId']
            return Add-MetraBriefNoteItem -Project $project -Kind $kind -Text $text `
                -DecisionId $decisionId -SessionId $sessionId -MetraRoot $MetraRoot -EnqueueWorker:(-not [string]::IsNullOrWhiteSpace($sessionId))
        }
        'correct' {
            $parsed = & $parseKv $ArgsRest
            if ($parsed.Positional.Count -lt 3) {
                throw 'brief correct requires <project> <itemId> "<body>".'
            }
            return Set-MetraBriefItemCorrected -Project ([string]$parsed.Positional[0]) `
                -ItemId ([string]$parsed.Positional[1]) -Body ([string]$parsed.Positional[2]) `
                -Title ([string]$parsed.Map['Title']) -MetraRoot $MetraRoot
        }
        'pin' {
            $parsed = & $parseKv $ArgsRest
            if ($parsed.Positional.Count -lt 2) { throw 'brief pin requires <project> <itemId> [-Unpin].' }
            $unpin = [bool]$parsed.Map['Unpin']
            return Set-MetraBriefItemPinned -Project ([string]$parsed.Positional[0]) `
                -ItemId ([string]$parsed.Positional[1]) -Pinned:(-not $unpin) -MetraRoot $MetraRoot
        }
        'rebuild' {
            if ($ArgsRest.Count -lt 1) { throw 'brief rebuild requires a project.' }
            return Invoke-MetraBriefRebuild -Project ([string]$ArgsRest[0]) -MetraRoot $MetraRoot
        }
        'refresh' {
            $parsed = & $parseKv $ArgsRest
            if ($parsed.Positional.Count -lt 2) {
                throw 'brief refresh requires <project> <sessionId>.'
            }
            return Request-MetraProjectBriefRefresh -Project ([string]$parsed.Positional[0]) `
                -SessionId ([string]$parsed.Positional[1]) -MetraRoot $MetraRoot -StartWorker
        }
        'close' {
            if ($ArgsRest.Count -lt 2) {
                throw 'brief close requires <project> <sessionId>.'
            }
            return Request-MetraProjectBriefClose -Project ([string]$ArgsRest[0]) `
                -SessionId ([string]$ArgsRest[1]) -MetraRoot $MetraRoot -StartWorker
        }
        'catch-up' {
            $parsed = & $parseKv $ArgsRest
            if ($parsed.Positional.Count -lt 1) {
                throw 'brief catch-up requires <project> [-SessionId <current>].'
            }
            $cur = [string]$parsed.Map['SessionId']
            return Request-MetraProjectBriefCatchUpIfDue -Project ([string]$parsed.Positional[0]) `
                -CurrentSessionId $cur -MetraRoot $MetraRoot -StartWorker
        }
        default {
            throw "Unknown brief subcommand: $Subcommand. Use show|note|correct|pin|rebuild|refresh|close|catch-up."
        }
    }
}
