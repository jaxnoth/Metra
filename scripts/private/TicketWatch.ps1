$script:MetraTicketWatchCorpusCache = $null

# Routing.ps1 owns Get-MetraTicketTrackerProject (project row + ModulePath).
# TicketWatch callers prefer Resolve-MetraTicketTrackerModule + Import-MetraTicketTrackerModule.

function Resolve-MetraTicketTrackerModule {
    <#
    .SYNOPSIS
        TicketWatch-facing TicketTracker resolver (usable module on disk).
    .DESCRIPTION
        Wraps Get-MetraTicketTrackerProject from Routing.ps1. Use this in TicketWatch so
        the name means "importable TicketTracker module," not a routing project-row lookup.
    #>
    [CmdletBinding()]
    param()

    return Get-MetraTicketTrackerProject
}

function Import-MetraTicketTrackerModule {
    <#
    .SYNOPSIS
        Import TicketTracker.psm1 without force-reloading when already loaded from the same path.
    .NOTES
        Does not preflight Test-Path so Pester can mock Import-Module against fixture paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModulePath,
        [switch]$Force
    )

    $resolved = $ModulePath
    if (Test-Path -LiteralPath $ModulePath) {
        try {
            $resolved = [string](Resolve-Path -LiteralPath $ModulePath).Path
        }
        catch { }
    }

    $loaded = @(Get-Module -Name TicketTracker -ErrorAction SilentlyContinue) | Where-Object {
        $p = [string]$_.Path
        [string]::Equals($p, $resolved, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($p, $ModulePath, [StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1

    if ($loaded -and -not $Force) {
        return $loaded
    }

    return Import-Module -Name $ModulePath -Force:$Force -PassThru -ErrorAction Stop
}

function Get-MetraTicketWatchConfig {
    <#
    .SYNOPSIS
        Local ticket-watch preferences (default: no local draft notes; scope mine).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    # top = 0 means all attention-eligible tickets. A cap would silently drop tickets
    # from a full scan, and anything missing from a full scan gets auto-closed.
    # scope mine: TT cache may be broader; Attention stays person-filter only.
    # autoAnalyze: opt-in M2; Scan tickets / CLI only - never Portfolio refresh.
    # autoAssess: opt-in; Added/Refreshed => Invoke-TicketAssess (local draft only, never iSupport).
    # assessMaxAgeHours: skip autoAssess when a fresh assessment artifact exists.
    # evidenceRouter: opt-in E1; after local analyze draft - Next evidence only (never recommend).
    # autoStoreRecommend: reserved / unused for auto-write through Mine quality loop.
    # Config may set true for experiments, but TicketWatch never auto-writes iSupport from it (M4+).
    $defaults = [PSCustomObject]@{
        writeLocalDraft     = $false
        autoAnalyze         = $false
        autoAssess          = $false
        assessMaxAgeHours   = 24
        evidenceRouter      = $false
        autoStoreRecommend  = $false
        top                 = 0
        syncOnScan          = $true
        syncOnSnapshot      = $false   # legacy; portfolio snapshot no longer runs ticket intake
        autoScanIntervalMinutes = 5    # Ops desk polls when Ticket Watch is on (0 = manual only)
        scope               = 'mine'
        productCues              = @()      # local escape hatch; not a TicketWatch catalog
        vocabularyMinSightings   = 2        # subject-DF floor for non-acronym proposals
        vocabularyMaxSubjectShare = 0.40    # drop tokens that appear in too many subjects
    }
    $cfgPath = Get-MetraTicketWatchConfigPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $cfgPath)) { return $defaults }
    try {
        $raw = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -ne (Get-MetraProp -Object $raw -Name 'writeLocalDraft' -Default $null)) {
            $defaults.writeLocalDraft = [bool]$raw.writeLocalDraft
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'autoAnalyze' -Default $null)) {
            $defaults.autoAnalyze = [bool]$raw.autoAnalyze
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'autoAssess' -Default $null)) {
            $defaults.autoAssess = [bool]$raw.autoAssess
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'assessMaxAgeHours' -Default $null)) {
            $hrs = [int]$raw.assessMaxAgeHours
            if ($hrs -ge 0) { $defaults.assessMaxAgeHours = $hrs }
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'evidenceRouter' -Default $null)) {
            $defaults.evidenceRouter = [bool]$raw.evidenceRouter
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'autoStoreRecommend' -Default $null)) {
            # Surface the flag only - never used to auto-write Affirm A (Confirm remains explicit).
            $defaults.autoStoreRecommend = [bool]$raw.autoStoreRecommend
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'top' -Default $null)) {
            $t = [int]$raw.top
            if ($t -gt 0) { $defaults.top = $t }
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'syncOnScan' -Default $null)) {
            $defaults.syncOnScan = [bool]$raw.syncOnScan
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'syncOnSnapshot' -Default $null)) {
            $defaults.syncOnSnapshot = [bool]$raw.syncOnSnapshot
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'autoScanIntervalMinutes' -Default $null)) {
            $mins = [int]$raw.autoScanIntervalMinutes
            if ($mins -ge 0) { $defaults.autoScanIntervalMinutes = $mins }
        }
        $scopeRaw = [string](Get-MetraProp -Object $raw -Name 'scope' -Default '')
        if ($scopeRaw) {
            $scopeNorm = $scopeRaw.Trim().ToLowerInvariant()
            if ($scopeNorm -eq 'mine') {
                $defaults.scope = 'mine'
            }
            else {
                # M1 only allows mine; unknown scopes fail closed to mine.
                $defaults.scope = 'mine'
            }
        }
        $cuesRaw = Get-MetraProp -Object $raw -Name 'productCues' -Default $null
        if ($null -ne $cuesRaw) {
            $defaults.productCues = @($cuesRaw | ForEach-Object { [string]$_ } | Where-Object { $_ })
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'vocabularyMinSightings' -Default $null)) {
            $ms = [int]$raw.vocabularyMinSightings
            if ($ms -ge 1) { $defaults.vocabularyMinSightings = $ms }
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'vocabularyMaxSubjectShare' -Default $null)) {
            $share = [double]$raw.vocabularyMaxSubjectShare
            if ($share -gt 0 -and $share -le 1) { $defaults.vocabularyMaxSubjectShare = $share }
        }
    }
    catch { }
    return $defaults
}

function Test-MetraTicketWatchShouldAnalyze {
    <#
    .SYNOPSIS
        M2 analyze trigger contract (local draft only - never iSupport).
    .DESCRIPTION
        -Draft / forceDraft => always analyze (mine-eligible ticket in this scan).
        autoAnalyze + Added/Refreshed => analyze.
        Unchanged => never (hard rule - no draft churn).
        Portfolio refresh never calls this path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('added', 'refreshed', 'unchanged')]
        [string]$ChangeKind,
        [bool]$ForceDraft = $false,
        [bool]$AutoAnalyze = $false
    )

    if ($ForceDraft) { return $true }
    if (-not $AutoAnalyze) { return $false }
    if ($ChangeKind -eq 'unchanged') { return $false }
    return ($ChangeKind -eq 'added' -or $ChangeKind -eq 'refreshed')
}

function Test-MetraTicketWatchHasRecentAssess {
    <#
    .SYNOPSIS
        True when data/assessments/<id>.json exists and assessedAtUtc is within MaxAgeHours.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [int]$MaxAgeHours = 24,
        [string]$TicketTrackerPath = ''
    )

    if ($MaxAgeHours -le 0) { return $false }
    $root = $TicketTrackerPath
    if ([string]::IsNullOrWhiteSpace($root)) {
        $tt = Resolve-MetraTicketTrackerModule
        if (-not $tt) { return $false }
        $root = [string]$tt.Path
    }
    $path = Join-Path $root ("data\assessments\{0}.json" -f $TicketId)
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
        $at = [string](Get-MetraProp -Object $raw -Name 'assessedAtUtc' -Default '')
        if ([string]::IsNullOrWhiteSpace($at)) { return $true }
        $when = [datetime]::Parse($at, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        $age = ([datetime]::UtcNow) - $when
        return ($age.TotalHours -lt $MaxAgeHours)
    }
    catch {
        return $false
    }
}

function Test-MetraTicketWatchShouldAssess {
    <#
    .SYNOPSIS
        Queue assess trigger (local assess draft only - never iSupport recommend).
    .DESCRIPTION
        autoAssess + Added/Refreshed only (does not ride on -Draft / writeLocalDraft - that stays analyze).
        Skips when a fresh assessment artifact exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('added', 'refreshed', 'unchanged')]
        [string]$ChangeKind,
        [bool]$AutoAssess = $false,
        [string]$TicketId = '',
        [int]$AssessMaxAgeHours = 24,
        [string]$TicketTrackerPath = ''
    )

    if (-not $AutoAssess) { return $false }
    if ($ChangeKind -eq 'unchanged') { return $false }
    if ($ChangeKind -notin @('added', 'refreshed')) { return $false }
    if ($TicketId) {
        if (Test-MetraTicketWatchHasRecentAssess -TicketId $TicketId -MaxAgeHours $AssessMaxAgeHours -TicketTrackerPath $TicketTrackerPath) {
            return $false
        }
    }
    return $true
}

function Update-MetraTicketAttentionFromAssess {
    <#
    .SYNOPSIS
        Stamp assess gate onto a ticket Attention queue item (Metra Attention only).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$QueueItem,
        [Parameter(Mandatory)]$AssessResult
    )

    if (-not $QueueItem) { return $QueueItem }
    $gate = [string](Get-MetraProp -Object $AssessResult -Name 'gate' -Default '')
    $ask = [string](Get-MetraProp -Object $AssessResult -Name 'customerAsk' -Default '')
    $obj = [string](Get-MetraProp -Object $AssessResult -Name 'responseObjective' -Default '')
    $id = [string](Get-MetraProp -Object $AssessResult -Name 'ticketId' -Default '')

    $summary = if ($gate) { "Assess: $gate" } else { 'Assess complete' }
    $why = switch ($gate) {
        'INTAKE' { 'Needs intake details before routing.' }
        'CLARIFY' { 'Needs clarifying questions from the requester.' }
        'SOLVE-READY' { 'Solve-ready - confirm before recommend or investigate.' }
        default { 'Assessment available (local draft only).' }
    }

    $detail = [string](Get-MetraProp -Object $QueueItem -Name 'detail' -Default '')
    if ($detail -and $detail -notmatch '(?i)\bAssess:') {
        $detail = "$detail - $summary"
    }
    elseif (-not $detail) {
        $detail = $summary
    }

    foreach ($pair in @(
            @{ Name = 'assessGate'; Value = $gate },
            @{ Name = 'summary'; Value = $summary },
            @{ Name = 'whyNext'; Value = $why },
            @{ Name = 'askPrompt'; Value = $(if ($ask) { $ask } else { "Review assess for ticket $id" }) },
            @{ Name = 'responseObjective'; Value = $obj },
            @{ Name = 'command'; Value = ".\TicketTracker.ps1 assess $id" },
            @{ Name = 'detail'; Value = $detail }
        )) {
        if ($QueueItem.PSObject.Properties[$pair.Name]) {
            $QueueItem.($pair.Name) = $pair.Value
        }
        else {
            $QueueItem | Add-Member -NotePropertyName $pair.Name -NotePropertyValue $pair.Value -Force
        }
    }
    return $QueueItem
}

function Get-MetraTicketWatchProductCueStopList {
    <#
    .SYNOPSIS
        Generic routing/ops tokens excluded from registry-derived product cues.
    .DESCRIPTION
        TicketWatch may filter generic routing triggers when deriving product cues from the
        registry. That filter is not a vocabulary proposal blacklist and must not grow in
        response to ticket-subject noise. Solutions keywords and local productCues are not
        filtered by this list (only length-gated during normalize).
    #>
    [CmdletBinding()]
    param()

    return [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@(
            'ticket', 'tickets', 'helpdesk', 'incident', 'incidents', 'report', 'reports',
            'sql', 'data', 'integration', 'server', 'servers', 'database', 'databases',
            'monitoring', 'project', 'projects', 'ops', 'metra', 'isupport', 'work',
            'item', 'items', 'change', 'changes', 'alert', 'alerts', 'disk', 'email',
            'mail', 'chat', 'chats', 'note', 'notes', 'draft', 'sync', 'scan'
        ),
        [StringComparer]::OrdinalIgnoreCase
    )
}

function ConvertTo-MetraTicketWatchNormalizedProductCues {
    <#
    .SYNOPSIS
        Deterministic product-cue union: trim, lowercase, length gate, unique, sort.
    .DESCRIPTION
        Solutions keywords (primary) and local productCues (escape hatch) are length-gated.
        Registry triggers (secondary) are also filtered by the generic stop list.
        TicketWatch consumes vocabulary; it does not author a portfolio product catalog.
    #>
    [CmdletBinding()]
    param(
        [string[]]$SolutionsKeywords = @(),
        [string[]]$RegistryTriggers = @(),
        [string[]]$LocalProductCues = @(),
        [int]$MinLength = 3
    )

    if ($MinLength -lt 1) { $MinLength = 3 }
    $stop = Get-MetraTicketWatchProductCueStopList
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    foreach ($raw in @($SolutionsKeywords)) {
        $n = ([string]$raw).Trim().ToLowerInvariant()
        if ($n.Length -lt $MinLength) { continue }
        if ($n -match '^\d{6,8}$') { continue }
        [void]$set.Add($n)
    }
    foreach ($raw in @($LocalProductCues)) {
        $n = ([string]$raw).Trim().ToLowerInvariant()
        if ($n.Length -lt $MinLength) { continue }
        if ($n -match '^\d{6,8}$') { continue }
        [void]$set.Add($n)
    }
    foreach ($raw in @($RegistryTriggers)) {
        $n = ([string]$raw).Trim().ToLowerInvariant()
        if ($n.Length -lt $MinLength) { continue }
        if ($n -match '^\d{6,8}$') { continue }
        if ($stop.Contains($n)) { continue }
        [void]$set.Add($n)
    }

    return @($set | Sort-Object)
}

function Get-MetraTicketWatchProductCueList {
    <#
    .SYNOPSIS
        Portfolio-derived product cues for ephemeral E1 recognition (not a score ledger).
    .DESCRIPTION
        Union of TicketTracker solutions keywords (primary), filtered registry triggers
        (secondary), and ticket-watch.local.json productCues (escape hatch). Pass source
        arrays to unit-test the builder without depending on a live portfolio catalog.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [string[]]$SolutionsKeywords,
        [string[]]$RegistryTriggers,
        [string[]]$LocalProductCues
    )

    $solutions = if ($PSBoundParameters.ContainsKey('SolutionsKeywords')) {
        @($SolutionsKeywords)
    }
    else {
        try { @(Get-MetraTicketTrackerSolutionsKeywords) } catch { @() }
    }

    $registry = if ($PSBoundParameters.ContainsKey('RegistryTriggers')) {
        @($RegistryTriggers)
    }
    else {
        $collected = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($row in @(Get-MetraRoutingTable)) {
                if (-not [bool](Get-MetraProp -Object $row -Name 'Present' -Default $false)) { continue }
                foreach ($t in @(Get-MetraProp -Object $row -Name 'Triggers' -Default @())) {
                    if ($t) { [void]$collected.Add([string]$t) }
                }
            }
        }
        catch { }
        @($collected)
    }

    $local = if ($PSBoundParameters.ContainsKey('LocalProductCues')) {
        @($LocalProductCues)
    }
    else {
        try {
            $cfg = Get-MetraTicketWatchConfig -MetraRoot $MetraRoot
            @($cfg.productCues)
        }
        catch { @() }
    }

    return @(
        ConvertTo-MetraTicketWatchNormalizedProductCues `
            -SolutionsKeywords $solutions `
            -RegistryTriggers $registry `
            -LocalProductCues $local
    )
}

function Get-MetraTicketWatchSubjectTokens {
    <#
    .SYNOPSIS
        Tokenize ticket subject text using Routing language stopwords (not TicketWatch policy).
    #>
    [CmdletBinding()]
    param([string]$Text = '')

    $stop = Get-MetraRoutingStopWords
    $parts = [regex]::Split(([string]$Text).ToLowerInvariant(), '[^a-z0-9]+') |
        Where-Object { $_ -and $_.Length -ge 3 } |
        Where-Object { -not $stop.Contains($_) }
    return @($parts | Select-Object -Unique)
}

function Get-MetraTicketWatchSubjectTokenSpans {
    <#
    .SYNOPSIS
        Subject tokens with original casing preserved for acronym detection.
    #>
    [CmdletBinding()]
    param([string]$Text = '')

    $stop = Get-MetraRoutingStopWords
    $spans = [System.Collections.Generic.List[object]]::new()
    foreach ($raw in @([regex]::Split([string]$Text, '[^A-Za-z0-9]+'))) {
        if (-not $raw) { continue }
        $lower = $raw.ToLowerInvariant()
        if ($lower.Length -lt 3) { continue }
        if ($stop.Contains($lower)) { continue }
        [void]$spans.Add([PSCustomObject]@{
                Raw   = $raw
                Token = $lower
            })
    }
    return @($spans)
}

function Test-MetraTicketWatchTokenLooksAcronymLike {
    <#
    .SYNOPSIS
        True for acronym-shaped tokens (OCLC, MSAL, ASFTN). Vendor title-case is false.
    #>
    [CmdletBinding()]
    param([string]$RawToken = '')

    $t = ([string]$RawToken).Trim()
    if ($t.Length -lt 3 -or $t.Length -gt 8) { return $false }
    if ($t -notmatch '^[A-Za-z]+$') { return $false }
    # All caps: OCLC, MSAL, SSO
    if ($t -ceq $t.ToUpperInvariant()) { return $true }
    # Mostly uppercase letters (at least 75%)
    $letters = @($t.ToCharArray())
    $upper = @($letters | Where-Object { [char]::IsUpper($_) }).Count
    return ($upper / [double]$letters.Count) -ge 0.75
}

function Get-MetraTicketWatchDfValue {
    <#
    .SYNOPSIS
        Read a token's subject-DF from a hashtable / IDictionary / note property bag.
    #>
    [CmdletBinding()]
    param(
        $Map,
        [string]$Token
    )

    if (-not $Map -or -not $Token) { return 0 }

    if ($Map -is [System.Collections.IDictionary]) {
        if ($Map.Contains($Token)) { return [int]$Map[$Token] }
        return 0
    }

    $prop = $Map.PSObject.Properties[$Token]
    if ($prop) { return [int]$prop.Value }
    return 0
}

function Test-MetraTicketWatchTextHasCue {
    <#
    .SYNOPSIS
        True when text contains a product cue (phrase substring or token-boundary match).
    #>
    [CmdletBinding()]
    param(
        [string]$Text = '',
        [string]$Cue = ''
    )

    $blob = ([string]$Text).ToLowerInvariant()
    $c = ([string]$Cue).Trim().ToLowerInvariant()
    if (-not $blob.Trim() -or -not $c) { return $false }

    # Multi-word cues keep phrase substring (e.g. "plan source", "power bi").
    if ($c -match '\s') {
        return $blob.Contains($c)
    }

    $escaped = [regex]::Escape($c)
    return [bool]($blob -match "(^|[^a-z0-9])$escaped([^a-z0-9]|$)")
}

function Get-MetraTicketWatchSubjectCorpusStats {
    <#
    .SYNOPSIS
        Subject-level document frequency over ticket subjects (not term frequency).
    .DESCRIPTION
        Pass -Subjects for fixtures. Pass -UseLiveTickets to read TicketTracker cache.
        Without either, returns an empty corpus (fail soft).
    #>
    [CmdletBinding()]
    param(
        [string[]]$Subjects,
        [switch]$UseLiveTickets
    )

    $list = [System.Collections.Generic.List[string]]::new()
    $maxUpdated = [datetime]::MinValue
    $injected = $PSBoundParameters.ContainsKey('Subjects')
    if ($injected) {
        foreach ($s in @($Subjects)) {
            if ($s) { [void]$list.Add([string]$s) }
        }
    }
    elseif ($UseLiveTickets) {
        try {
            $tt = Resolve-MetraTicketTrackerModule
            if ($tt) {
                $null = Import-MetraTicketTrackerModule -ModulePath $tt.ModulePath
                foreach ($t in @(Get-TrackedTickets)) {
                    $subj = [string](Get-MetraProp -Object $t -Name 'Subject' -Default '')
                    if ($subj) { [void]$list.Add($subj) }
                    $upd = Get-MetraProp -Object $t -Name 'Updated' -Default $null
                    if ($upd) {
                        try {
                            $dt = [datetime]$upd
                            if ($dt -gt $maxUpdated) { $maxUpdated = $dt }
                        }
                        catch { }
                    }
                }
            }
        }
        catch { }
    }

    # Include a cheap subject fingerprint so subject-only edits invalidate the corpus cache.
    $subjectFingerprint = ''
    if ($list.Count -gt 0) {
        $joined = ($list -join "`n")
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha.ComputeHash($bytes)
            $subjectFingerprint = [BitConverter]::ToString($hash).Replace('-', '').Substring(0, 16)
        }
        finally {
            $sha.Dispose()
        }
    }
    $cacheKey = '{0}|{1}|{2}' -f $list.Count, $maxUpdated.ToUniversalTime().Ticks, $subjectFingerprint
    if (
        -not $injected -and
        $script:MetraTicketWatchCorpusCache -and
        $script:MetraTicketWatchCorpusCache.Key -eq $cacheKey -and
        $null -ne $script:MetraTicketWatchCorpusCache.Stats
    ) {
        return $script:MetraTicketWatchCorpusCache.Stats
    }

    $df = @{}
    foreach ($subj in $list) {
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($tok in @(Get-MetraTicketWatchSubjectTokens -Text $subj)) {
            if (-not $seen.Add($tok)) { continue }
            if (-not $df.ContainsKey($tok)) { $df[$tok] = 0 }
            $df[$tok]++
        }
    }

    $stats = [PSCustomObject]@{
        SubjectCount           = $list.Count
        TokenDocumentFrequency = $df
        CacheKey               = $cacheKey
    }
    if (-not $injected) {
        $script:MetraTicketWatchCorpusCache = @{
            Key   = $cacheKey
            Stats = $stats
        }
    }
    return $stats
}

function Test-MetraTicketWatchHasProductCue {
    [CmdletBinding()]
    param(
        [string]$Subject = '',
        [string]$Description = '',
        [string[]]$CueList
    )

    $blob = ('{0} {1}' -f $Subject, $Description).ToLowerInvariant()
    if (-not $blob.Trim()) { return $false }
    $cues = if ($PSBoundParameters.ContainsKey('CueList')) {
        @($CueList)
    }
    else {
        @(Get-MetraTicketWatchProductCueList)
    }
    foreach ($cue in $cues) {
        if (Test-MetraTicketWatchTextHasCue -Text $blob -Cue ([string]$cue)) { return $true }
    }
    return $false
}

function Get-MetraTicketWatchSuggestedVocabulary {
    <#
    .SYNOPSIS
        Evidence-driven vocabulary proposals - propose only (never auto-write).
    .DESCRIPTION
        Drops tokens already in portfolio cue union. Proposes tokens with subject-DF
        evidence: df >= minSightings, or df == 1 and strong acronym (length >= 4).
        Common language dies via max subject-share. TicketWatch does not maintain a
        product/noise blacklist.
    #>
    [CmdletBinding()]
    param(
        [string]$Subject = '',
        [string[]]$CueList,
        $CorpusStats = $null,
        [int]$MinSightings = -1,
        [double]$MaxSubjectShare = -1,
        [int]$MaxSuggestions = 3,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($MaxSuggestions -lt 1) { $MaxSuggestions = 3 }
    if (-not $Subject.Trim()) { return @() }

    $cfg = $null
    try { $cfg = Get-MetraTicketWatchConfig -MetraRoot $MetraRoot } catch { }
    if ($MinSightings -lt 1) {
        $MinSightings = if ($cfg) { [int]$cfg.vocabularyMinSightings } else { 2 }
    }
    if ($MaxSubjectShare -le 0) {
        $MaxSubjectShare = if ($cfg) { [double]$cfg.vocabularyMaxSubjectShare } else { 0.40 }
    }

    $known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $knownSource = if ($PSBoundParameters.ContainsKey('CueList')) {
        @($CueList)
    }
    else {
        @(Get-MetraTicketWatchProductCueList)
    }
    foreach ($cue in $knownSource) {
        $nCue = ([string]$cue).Trim().ToLowerInvariant()
        if ($nCue) { [void]$known.Add($nCue) }
    }

    $stats = if ($null -ne $CorpusStats) {
        $CorpusStats
    }
    else {
        Get-MetraTicketWatchSubjectCorpusStats -UseLiveTickets
    }
    $total = [int](Get-MetraProp -Object $stats -Name 'SubjectCount' -Default 0)
    $dfMap = Get-MetraProp -Object $stats -Name 'TokenDocumentFrequency' -Default @{}
    $emptyCorpus = $total -lt 1
    if ($emptyCorpus) { $total = 1 }

    $candidates = [System.Collections.Generic.List[object]]::new()
    $seenTok = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($span in @(Get-MetraTicketWatchSubjectTokenSpans -Text $Subject)) {
        $n = [string]$span.Token
        $raw = [string]$span.Raw
        if (-not $seenTok.Add($n)) { continue }
        if ($known.Contains($n)) { continue }
        if ($n -match '^\d{6,8}$' -or $n -match '^pr\d') { continue }

        $isAcronym = Test-MetraTicketWatchTokenLooksAcronymLike -RawToken $raw
        $minLen = if ($isAcronym) { 3 } else { 4 }
        if ($n.Length -lt $minLen) { continue }

        $dfVal = Get-MetraTicketWatchDfValue -Map $dfMap -Token $n
        # Current subject counts as one sighting when absent from the corpus map.
        if ($dfVal -lt 1) { $dfVal = 1 }

        if (-not $emptyCorpus) {
            $share = $dfVal / [double]$total
            if ($share -gt $MaxSubjectShare) { continue }
        }

        # Single-sighting path: strong acronym only (length >= 4) - OCLC/MSAL yes; SSO noise no.
        $strongAcronym = $isAcronym -and ($raw.Length -ge 4)
        $passesSighting = ($dfVal -ge $MinSightings) -or ($dfVal -eq 1 -and $strongAcronym)
        if (-not $passesSighting) { continue }

        [void]$candidates.Add([PSCustomObject]@{
                Token        = $n
                SubjectCount = $dfVal
            })
    }

    return @(
        $candidates |
            Sort-Object SubjectCount -Descending |
            Select-Object -First $MaxSuggestions
    )
}

function Get-MetraTicketWatchEvidenceSignals {
    <#
    .SYNOPSIS
        Ephemeral E1 evidence signals (uncertainty / likelihood cues) - not sources, not scores.
    .DESCRIPTION
        Pure / fail-soft. Thin description alone is recorded but must not drive askOperator.
        No persisted probability or confidence ledger.
    #>
    [CmdletBinding()]
    param(
        [string]$Subject = '',
        [string]$Description = '',
        [int]$SimilarCount = 0,
        [int]$SolutionsCount = 0,
        [int]$PersonPriorCount = 0,
        [bool]$MailCue = $false,
        [bool]$InstitutionalExhausted = $false
    )

    $tokens = @(Get-MetraTicketWatchSubjectTokens -Text $Subject)
    $descLen = ([string]$Description).Trim().Length
    $subjectLen = ([string]$Subject).Trim().Length
    $thinBody = ($descLen -lt 80 -and $subjectLen -lt 48)
    $productCue = Test-MetraTicketWatchHasProductCue -Subject $Subject -Description $Description
    $priorSubjectLikely = ($tokens.Count -ge 2) -or $productCue
    $priorPersonLikely = $PersonPriorCount -ge 1

    return [PSCustomObject]@{
        Subject                 = [string]$Subject
        DescriptionLength       = $descLen
        ThinBody                = [bool]$thinBody
        ProductCue              = [bool]$productCue
        SubjectTokenCount       = $tokens.Count
        SubjectTokens           = $tokens
        SimilarCount            = [math]::Max(0, $SimilarCount)
        SolutionsCount          = [math]::Max(0, $SolutionsCount)
        PersonPriorCount        = [math]::Max(0, $PersonPriorCount)
        PriorSubjectLikely      = [bool]$priorSubjectLikely
        PriorPersonLikely       = [bool]$priorPersonLikely
        MailCue                 = [bool]$MailCue
        InstitutionalExhausted  = [bool]$InstitutionalExhausted
    }
}

function Get-MetraTicketWatchEvidenceSuggestion {
    <#
    .SYNOPSIS
        E1: map signals -> one next evidence source (or recommendable / none).
    .DESCRIPTION
        Suggests the most promising next evidence source - not the most likely solution.
        Optimizes quality guidance, not confidence. No Top-N, scores, or likely-solution text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Signals
    )

    $similar = [int](Get-MetraProp -Object $Signals -Name 'SimilarCount' -Default 0)
    $solutions = [int](Get-MetraProp -Object $Signals -Name 'SolutionsCount' -Default 0)
    $productCue = [bool](Get-MetraProp -Object $Signals -Name 'ProductCue' -Default $false)
    $tokenCount = [int](Get-MetraProp -Object $Signals -Name 'SubjectTokenCount' -Default 0)
    $priorSubject = [bool](Get-MetraProp -Object $Signals -Name 'PriorSubjectLikely' -Default $false)
    $priorPerson = [bool](Get-MetraProp -Object $Signals -Name 'PriorPersonLikely' -Default $false)
    $mailCue = [bool](Get-MetraProp -Object $Signals -Name 'MailCue' -Default $false)
    $exhausted = [bool](Get-MetraProp -Object $Signals -Name 'InstitutionalExhausted' -Default $false)
    $subject = [string](Get-MetraProp -Object $Signals -Name 'Subject' -Default '')

    # Recommendable: enough to write a recommend worth reading - not a confidence %.
    if ($solutions -ge 1 -or $similar -ge 2) {
        return [PSCustomObject]@{
            draftState     = 'recommendable'
            action         = 'none'
            reason         = 'Existing information appears sufficient for a recommendation draft.'
            operatorHint   = 'Evidence appears sufficient. Ready for recommendation (M3 store-as-review). This step does not write recommend.'
            suggestedQuery = ''
            deskLabel      = 'Evidence appears sufficient'
        }
    }

    # 1. Institutional knowledge not exhausted?
    if (-not $exhausted -and ($productCue -or $priorSubject -or $priorPerson -or $tokenCount -ge 1 -or $subject.Trim())) {
        $reason = if ($productCue) {
            'Known product cue with likely institutional history.'
        }
        elseif ($priorPerson) {
            'Requester has prior tickets; check institutional solutions first.'
        }
        else {
            'Subject tokens suggest possible solutions / similar history.'
        }
        return [PSCustomObject]@{
            draftState     = 'needsEvidence'
            action         = 'solutionsKb'
            reason         = $reason
            operatorHint   = 'Review TicketTracker solutions references before drafting a recommendation.'
            suggestedQuery = ''
            deskLabel      = 'Next evidence: Check solutions KB'
        }
    }

    # 2. Internal organizational evidence likely?
    if ($mailCue) {
        return [PSCustomObject]@{
            draftState     = 'needsEvidence'
            action         = 'm365Mail'
            reason         = 'Mail/Teams cue present; internal evidence may help.'
            operatorHint   = 'Search Outlook/Teams via M365 CLI; cite findings into a local note - do not auto-ingest.'
            suggestedQuery = ''
            deskLabel      = 'Next evidence: Search M365'
        }
    }

    # 3. Human fact required (blocked - not merely thin)?
    $blocked = (-not $productCue) -and ($tokenCount -lt 2) -and ($similar -eq 0) -and ($solutions -eq 0)
    if ($blocked) {
        return [PSCustomObject]@{
            draftState     = 'needsEvidence'
            action         = 'askOperator'
            reason         = 'Unable to identify platform or workflow from given information.'
            operatorHint   = 'Request product name, affected user/group, and expected behavior.'
            suggestedQuery = ''
            deskLabel      = 'Next evidence: Ask operator'
        }
    }

    # 4. External evidence after local/org miss?
    if ($productCue -or $tokenCount -ge 2) {
        $q = ($subject -replace '\s+', ' ').Trim()
        if ($q.Length -gt 120) { $q = $q.Substring(0, 120).Trim() }
        return [PSCustomObject]@{
            draftState     = 'needsEvidence'
            action         = 'boundedWeb'
            reason         = 'Institutional look exhausted or sparse; external docs may help.'
            operatorHint   = 'Run the suggested query yourself if useful. Metra does not fetch or scrape the web.'
            suggestedQuery = $q
            deskLabel      = 'Next evidence: Bounded web search'
        }
    }

    # 5. Otherwise
    return [PSCustomObject]@{
        draftState     = 'needsEvidence'
        action         = 'none'
        reason         = 'No high-value next evidence source identified.'
        operatorHint   = 'Leave as draft; do not invent a recommendation.'
        suggestedQuery = ''
        deskLabel      = 'Next evidence: none'
    }
}

function Format-MetraTicketWatchEvidenceNextNote {
    <#
    .SYNOPSIS
        Local note body for E1 Next evidence / recommendable handoff (never a likely solution).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Suggestion
    )

    $action = [string](Get-MetraProp -Object $Suggestion -Name 'action' -Default 'none')
    $draftState = [string](Get-MetraProp -Object $Suggestion -Name 'draftState' -Default 'needsEvidence')
    $reason = [string](Get-MetraProp -Object $Suggestion -Name 'reason' -Default '')
    $hint = [string](Get-MetraProp -Object $Suggestion -Name 'operatorHint' -Default '')
    $query = [string](Get-MetraProp -Object $Suggestion -Name 'suggestedQuery' -Default '')
    $label = [string](Get-MetraProp -Object $Suggestion -Name 'deskLabel' -Default '')

    $lines = @(
        '[evidence-next]'
        ''
        ("Draft state: {0}" -f $draftState)
        ("Action: {0}" -f $action)
        ("Desk: {0}" -f $label)
        ("Reason: {0}" -f $reason)
        ("Operator hint: {0}" -f $hint)
    )
    if ($action -eq 'boundedWeb' -and $query) {
        $lines += ("Suggested query: {0}" -f $query)
    }
    $lines += ''
    $lines += 'Next evidence only - not a recommendation and does not propose a solution.'
    return ($lines -join "`n")
}

function New-MetraTicketWatchNextEvidenceBody {
    <#
    .SYNOPSIS
        Honest thin-evidence Preview body. Not a recommendation; no fake Findings/investigation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [string]$Subject = '',
        $Suggestion = $null,
        [int]$SimilarCount = 0,
        [int]$SolutionsCount = 0,
        [string[]]$SimilarLines = @(),
        [string[]]$SolutionLines = @(),
        [string[]]$CueList,
        $CorpusStats = $null
    )

    $action = [string](Get-MetraProp -Object $Suggestion -Name 'action' -Default 'none')
    $reason = [string](Get-MetraProp -Object $Suggestion -Name 'reason' -Default '')
    $hint = [string](Get-MetraProp -Object $Suggestion -Name 'operatorHint' -Default '')
    $query = [string](Get-MetraProp -Object $Suggestion -Name 'suggestedQuery' -Default '')
    $label = [string](Get-MetraProp -Object $Suggestion -Name 'deskLabel' -Default 'Next evidence')

    $checked = [System.Collections.Generic.List[string]]::new()
    $checked.Add(("- Local similar tickets: {0}" -f $SimilarCount))
    $checked.Add(("- Solutions index matches: {0}" -f $SolutionsCount))
    foreach ($line in @($SolutionLines | Where-Object { $_ -and $_ -notmatch '(?i)\(no solutions' })) {
        $checked.Add(($line -replace '^\s*-\s*', '- Solutions: ').Trim())
    }
    foreach ($line in @($SimilarLines | Where-Object { $_ -and $_ -notmatch '(?i)\(none' })) {
        $checked.Add(($line -replace '^\s*-\s*', '- Similar: ').Trim())
    }

    $next = [System.Collections.Generic.List[string]]::new()
    if ($label) { $next.Add("- $label") }
    if ($reason) { $next.Add("- Why: $reason") }
    if ($hint) { $next.Add("- Next: $hint") }
    switch -Regex ($action) {
        '^(?i)solutionsKb$' {
            $next.Add('- Try: open TicketTracker solutions/ or run brief, then Save note with what you found.')
        }
        '^(?i)m365Mail$' {
            $next.Add('- Try: M365 mail/Teams search for the requester, cite into a local note.')
        }
        '^(?i)boundedWeb$' {
            if ($query) { $next.Add("- Try web search: $query") }
            else { $next.Add('- Try a bounded vendor/docs search for the product symptom.') }
        }
        '^(?i)askOperator$' {
            $next.Add('- Ask requester for product, environment, and expected vs actual behavior; Save note here.')
        }
        default {
            if ($next.Count -eq 0) {
                $next.Add('- Run brief, check similar/notes, then Discuss if you want Metra to dig further.')
            }
        }
    }
    $next.Add(("- Command: .\TicketTracker.ps1 brief {0}" -f $TicketId))
    $next.Add('- Discuss / Ask Metra after you have one concrete clue - do not Force-write empty Gaps.')

    $vocabParams = @{ Subject = $Subject }
    if ($PSBoundParameters.ContainsKey('CueList')) { $vocabParams.CueList = $CueList }
    if ($null -ne $CorpusStats) { $vocabParams.CorpusStats = $CorpusStats }
    $vocab = @(Get-MetraTicketWatchSuggestedVocabulary @vocabParams)
    if ($vocab.Count -gt 0) {
        $bits = @(
            $vocab | ForEach-Object {
                $tok = [string](Get-MetraProp -Object $_ -Name 'Token' -Default $_)
                $n = [int](Get-MetraProp -Object $_ -Name 'SubjectCount' -Default 0)
                if ($n -gt 0) { '{0} ({1} subjects)' -f $tok, $n } else { $tok }
            }
        )
        $next.Add(
            ("- Vocabulary gap (propose only): {0} - add to solutions/README keywords or ticket-watch.local.json productCues" -f ($bits -join ', '))
        )
    }

    $subjLine = if ($Subject) { "Ticket $TicketId`: $Subject" } else { "Ticket $TicketId" }
    $parts = @(
        'Not a recommendation yet - local evidence is thin.'
        ''
        $subjLine
        ''
        'What we checked (local only):'
        ($checked -join "`n")
        ''
        'Next evidence:'
        ($next -join "`n")
        ''
        'Write recommendation stays blocked until similar/solutions (or your note) improve - or Force intentionally.'
    )
    return ($parts -join "`n").Trim()
}

function ConvertFrom-MetraTicketWatchAnalyzeNote {
    <#
    .SYNOPSIS
        Fallback parser for analyze-draft note text when structured analysis is unavailable.
    #>
    [CmdletBinding()]
    param(
        [string]$NoteText
    )

    $similarLines = @()
    $solutionLines = @()
    if ([string]::IsNullOrWhiteSpace($NoteText)) {
        return [PSCustomObject]@{
            SimilarLines   = @()
            SolutionLines  = @()
            SimilarCount   = 0
            SolutionsCount = 0
        }
    }

    if ($NoteText -match '(?s)Similar \(local cache\):\s*(.*?)\s*Solutions index hits:') {
        $similarLines = @($Matches[1] -split "`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ })
    }
    if ($NoteText -match '(?s)Solutions index hits:\s*(.*)$') {
        $solutionLines = @($Matches[1] -split "`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ })
    }

    return [PSCustomObject]@{
        SimilarLines   = $similarLines
        SolutionLines  = $solutionLines
        SimilarCount   = @($similarLines | Where-Object { $_ -match '^\s*-\s+' -and $_ -notmatch '(?i)\(none' }).Count
        SolutionsCount = @($solutionLines | Where-Object { $_ -match '^\s*-\s+' -and $_ -notmatch '(?i)\(no solutions' }).Count
    }
}

function Invoke-MetraTicketWatchEnsureAnalyzeEvidence {
    <#
    .SYNOPSIS
        Refresh local analyze-draft + evidence-next for Affirm A Preview/Confirm.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ticket,
        [Parameter(Mandatory)][string]$TicketId,
        [switch]$RefreshAnalyze
    )

    $analyzeNote = Get-MetraTicketWatchLatestNoteText -TicketId $TicketId -Tag 'analyze-draft'
    $priorEvidenceNote = Get-MetraTicketWatchLatestNoteText -TicketId $TicketId -Tag 'evidence-next'
    $similarN = 0
    $solutionsN = 0
    $similarLines = @()
    $solutionLines = @()
    $fromStructured = $false

    if ($RefreshAnalyze -or -not $analyzeNote) {
        $analysis = New-TicketDraftAnalysis -Id $TicketId
        if ($analysis) {
            $similarLines = @(foreach ($s in @($analysis.Similar)) {
                    '- {0}: {1}' -f $s.Id, $s.Subject
                })
            $solutionLines = @(foreach ($h in @($analysis.Solutions)) {
                    '- {0} ({1})' -f $h.Title, $h.File
                })
            $similarN = @($analysis.Similar).Count
            $solutionsN = @($analysis.Solutions).Count
            $fromStructured = $true
        }
        $analyzeNote = Get-MetraTicketWatchLatestNoteText -TicketId $TicketId -Tag 'analyze-draft'
    }

    # Prefer structured analysis objects; parse analyze-draft text only as fallback.
    if (-not $fromStructured) {
        $parsed = ConvertFrom-MetraTicketWatchAnalyzeNote -NoteText $analyzeNote
        $similarLines = @($parsed.SimilarLines)
        $solutionLines = @($parsed.SolutionLines)
        $similarN = [int]$parsed.SimilarCount
        $solutionsN = [int]$parsed.SolutionsCount
    }

    $subject = [string](Get-MetraProp -Object $Ticket -Name 'Subject' -Default '')
    $desc = [string](Get-MetraProp -Object $Ticket -Name 'Description' -Default '')
    # Analyze already queried similar + solutions - mark institutional checked for router.
    $signals = Get-MetraTicketWatchEvidenceSignals `
        -Subject $subject `
        -Description $desc `
        -SimilarCount $similarN `
        -SolutionsCount $solutionsN `
        -PersonPriorCount 0 `
        -MailCue:$false `
        -InstitutionalExhausted:$true
    $suggestion = Get-MetraTicketWatchEvidenceSuggestion -Signals $signals
    $evidenceNote = Format-MetraTicketWatchEvidenceNextNote -Suggestion $suggestion
    if ($evidenceNote.Trim() -ne ([string]$priorEvidenceNote).Trim()) {
        $null = Add-TrackedTicketNote -Id $TicketId -Text $evidenceNote -Tags 'evidence-next'
    }

    return [PSCustomObject]@{
        AnalyzeNote    = $analyzeNote
        EvidenceNote   = $evidenceNote
        Suggestion     = $suggestion
        SimilarCount   = $similarN
        SolutionsCount = $solutionsN
        SimilarLines   = $similarLines
        SolutionLines  = $solutionLines
        Recommendable  = Test-MetraTicketWatchNoteIsRecommendable -NoteText $evidenceNote
        Subject        = $subject
    }
}

function New-MetraTicketWatchRecommendBasis {
    <#
    .SYNOPSIS
        Ephemeral M3 authoring Basis (not a score ledger / not persisted as Attention memory).
    #>
    [CmdletBinding()]
    param(
        [int]$SimilarCount = 0,
        [int]$SolutionsCount = 0,
        [bool]$MailEvidence = $false,
        [bool]$WebSuggested = $false
    )

    return [PSCustomObject]@{
        SimilarCount   = [math]::Max(0, $SimilarCount)
        SolutionsCount = [math]::Max(0, $SolutionsCount)
        MailEvidence   = [bool]$MailEvidence
        WebSuggested   = [bool]$WebSuggested
    }
}

function New-MetraTicketWatchRecommendBody {
    <#
    .SYNOPSIS
        M3 recommendation body: Findings / Suggested investigation / Gaps. No Metra AI heading.
    .DESCRIPTION
        Professional sink. Never invents completed Live actions. Grounded in similar/solutions lines.
    #>
    [CmdletBinding()]
    param(
        [string]$Subject = '',
        [string[]]$SimilarLines = @(),
        [string[]]$SolutionLines = @(),
        [string]$EvidenceHint = '',
        $Basis = $null
    )

    $similar = @($SimilarLines | Where-Object { $_ -and ($_ -notmatch '(?i)\(none') })
    $solutions = @($SolutionLines | Where-Object { $_ -and ($_ -notmatch '(?i)\(no solutions') })
    $findings = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $solutions) {
        $clean = ($line -replace '^\s*-\s*', '').Trim()
        if ($clean) { $findings.Add("- Solutions index: $clean") }
    }
    foreach ($line in $similar) {
        $clean = ($line -replace '^\s*-\s*', '').Trim()
        if ($clean) { $findings.Add("- Similar ticket: $clean") }
    }
    if ($findings.Count -eq 0 -and $Subject) {
        $findings.Add("- Subject under review: $Subject")
    }
    if ($findings.Count -eq 0) {
        $findings.Add('- Limited local similar/solutions evidence in cache.')
    }

    $checks = [System.Collections.Generic.List[string]]::new()
    if ($solutions.Count -gt 0) {
        $checks.Add('- Review matching TicketTracker solutions write-ups before changing Live state.')
    }
    if ($similar.Count -gt 0) {
        $checks.Add('- Compare requester/symptom pattern against listed similar tickets.')
    }
    if ($EvidenceHint -match '(?i)m365') {
        $checks.Add('- Search Outlook/Teams via M365 for related cites.')
    }
    if ($EvidenceHint -match '(?i)boundedWeb|web') {
        $checks.Add('- If needed, run a bounded web search (operator-directed); do not invent vendor steps.')
    }
    if ($checks.Count -eq 0) {
        $checks.Add('- Confirm product/environment and expected vs actual behavior with the requester if still unclear.')
        $checks.Add('- Re-check TicketTracker solutions index after clarifying product cues.')
    }

    $gaps = [System.Collections.Generic.List[string]]::new()
    if ($solutions.Count -eq 0) {
        $gaps.Add('- No solutions index keyword hits in the current draft.')
    }
    if ($similar.Count -eq 0) {
        $gaps.Add('- No strong similar-ticket matches in the local cache.')
    }
    if ($Basis -and -not [bool](Get-MetraProp -Object $Basis -Name 'MailEvidence' -Default $false)) {
        $gaps.Add('- No M365 mail/Teams evidence attached yet.')
    }
    if ($gaps.Count -eq 0) {
        $gaps.Add('- Root cause not confirmed; treat this as a review artifact, not a completed fix.')
    }

    $basisLines = @()
    if ($Basis) {
        $basisLines = @(
            'Basis (authoring only - not a confidence score):'
            ("- Similar tickets: {0}" -f [int](Get-MetraProp -Object $Basis -Name 'SimilarCount' -Default 0))
            ("- Solutions matches: {0}" -f [int](Get-MetraProp -Object $Basis -Name 'SolutionsCount' -Default 0))
            ("- M365 evidence: {0}" -f $(if ([bool](Get-MetraProp -Object $Basis -Name 'MailEvidence' -Default $false)) { 'yes' } else { 'no' }))
            ("- Web suggested: {0}" -f $(if ([bool](Get-MetraProp -Object $Basis -Name 'WebSuggested' -Default $false)) { 'yes' } else { 'no' }))
            ''
        )
    }

    $parts = @()
    if ($basisLines.Count -gt 0) { $parts += ($basisLines -join "`n") }
    $parts += @(
        'Findings:'
        ($findings -join "`n")
        ''
        'Suggested investigation:'
        ($checks -join "`n")
        ''
        'Gaps:'
        ($gaps -join "`n")
    )
    return ($parts -join "`n").Trim()
}

function Test-MetraTicketWatchNoteIsRecommendable {
    <#
    .SYNOPSIS
        True when latest evidence-next note declares draftState recommendable.
    #>
    [CmdletBinding()]
    param([string]$NoteText = '')

    if (-not $NoteText) { return $false }
    return ($NoteText -match '(?im)^\s*Draft state:\s*recommendable\s*$')
}

function Get-MetraTicketWatchRecommendBlockedMessage {
    <#
    .SYNOPSIS
        Operator-facing next steps when Affirm A is gated (no E1 jargon).
    #>
    [CmdletBinding()]
    param(
        [string]$EvidenceNote = '',
        [string]$AnalyzeNote = '',
        [ValidateSet('preview', 'confirm')]
        [string]$Mode = 'preview'
    )

    $draftState = ''
    $action = ''
    $hint = ''
    $reason = ''
    $query = ''
    $desk = ''
    if ($EvidenceNote) {
        if ($EvidenceNote -match '(?im)^\s*Draft state:\s*(.+)\s*$') { $draftState = $Matches[1].Trim() }
        if ($EvidenceNote -match '(?im)^\s*Action:\s*(\S+)') { $action = $Matches[1].Trim() }
        if ($EvidenceNote -match '(?im)^\s*Operator hint:\s*(.+)\s*$') { $hint = $Matches[1].Trim() }
        if ($EvidenceNote -match '(?im)^\s*Reason:\s*(.+)\s*$') { $reason = $Matches[1].Trim() }
        if ($EvidenceNote -match '(?im)^\s*Suggested query:\s*(.+)\s*$') { $query = $Matches[1].Trim() }
        if ($EvidenceNote -match '(?im)^\s*Desk:\s*(.+)\s*$') { $desk = $Matches[1].Trim() }
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($Mode -eq 'confirm') {
        $parts.Add('Write to iSupport is blocked until local evidence looks sufficient.')
    }
    else {
        $parts.Add('Evidence is still thin for an iSupport recommendation.')
    }

    if (-not $AnalyzeNote) {
        $parts.Add('No local analyze draft yet. Next: run Scan tickets with analyze/draft on, or Discuss / brief this ticket first.')
    }
    elseif (-not $EvidenceNote) {
        $parts.Add('No next-evidence note yet. Re-scan with evidence router on, or check similar/solutions yourself via brief.')
    }
    else {
        if ($desk) { $parts.Add($desk) }
        elseif ($reason) { $parts.Add("Why: $reason") }
        if ($hint) { $parts.Add("Next: $hint") }
        switch -Regex ($action) {
            '^(?i)solutionsKb$' {
                $parts.Add('Try: TicketTracker solutions/ (or brief) for product keywords on this subject.')
            }
            '^(?i)m365Mail$' {
                $parts.Add('Try: M365 mail search for related requester mail, then cite back with a local note.')
            }
            '^(?i)boundedWeb$' {
                if ($query) { $parts.Add("Try web search: $query") }
                else { $parts.Add('Try a bounded web search for the product symptom, then add a local note.') }
            }
            '^(?i)askOperator$' {
                $parts.Add('Ask the requester or assignee for the missing detail, then Save note here.')
            }
        }
        if ($draftState -and $draftState -ne 'recommendable') {
            $parts.Add("(Local draft state: $draftState.)")
        }
    }

    if ($Mode -eq 'preview') {
        $parts.Add('Preview still saves a local draft for review. Write recommendation stays blocked until evidence improves (or Force).')
    }
    else {
        $parts.Add('Preview first, gather the next evidence step, then Write - or Force only if you intentionally override.')
    }

    return (($parts | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' ')
}

function Format-MetraTicketWatchRecommendDraftNote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Body,
        $Basis = $null
    )

    $lines = @(
        '[recommend-draft]'
        ''
        'M3 Preview - local only. Affirm A store requires Confirm / Write recommendation.'
        ''
        $Body.Trim()
    )
    return ($lines -join "`n")
}

function Get-MetraTicketWatchLatestNoteText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$Tag
    )

    $notes = @(Get-TrackedTicketNotes -TicketId $TicketId | Sort-Object CreatedUtc -Descending)
    foreach ($n in $notes) {
        $tags = [string](Get-MetraProp -Object $n -Name 'Tags' -Default '')
        if ($tags -match [regex]::Escape($Tag)) {
            return [string](Get-MetraProp -Object $n -Name 'Text' -Default '')
        }
    }
    return ''
}

function Invoke-MetraTicketWatchStoreRecommend {
    <#
    .SYNOPSIS
        M3: Preview local recommend-draft, or Confirm TT recommend (Affirm A store-as-review).
    .DESCRIPTION
        Mine-eligible only. Confirm (Write) gates on evidence recommendable unless -Force.
        Preview is local-only and always drafts when Mine-eligible; thin evidence yields
        actionable nextSteps instead of a hard fail.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$Preview,
        [switch]$Confirm,
        [switch]$Force,
        [int]$Minutes = 15,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Quiet
    )

    if (-not $Preview -and -not $Confirm) { $Preview = $true }
    if ($Confirm) { $Preview = $false }

    $cfg = Get-MetraTicketWatchConfig -MetraRoot $MetraRoot
    $result = [PSCustomObject]@{
        ok                 = $false
        id                 = $Id
        preview            = [bool]$Preview
        confirm            = [bool]$Confirm
        force              = [bool]$Force
        mineEligible       = $false
        recommendable      = $false
        body               = ''
        noteId             = ''
        iSupportWrite      = $false
        recommendationWritten = $false
        warning            = ''
        nextSteps          = ''
        autoStoreRecommend = [bool]$cfg.autoStoreRecommend
    }

    $tt = Resolve-MetraTicketTrackerModule
    if (-not $tt) {
        $result.warning = 'TicketTracker project or module not present.'
        return $result
    }

    $null = Import-MetraTicketTrackerModule -ModulePath $tt.ModulePath
    $ticket = @(Get-TrackedTickets -Id $Id | Select-Object -First 1)
    if ($ticket.Count -eq 0) {
        $result.warning = "Ticket '$Id' not found in local cache. Sync or pull first."
        return $result
    }
    $ticketObj = $ticket[0]
    $canonicalId = [string]$ticketObj.Id

    $meFilter = ''
    $assigneeFilter = ''
    try {
        $settings = Get-TicketTrackerSettings
        if ($settings.PSObject.Properties['meFilter'] -and $settings.meFilter) {
            $meFilter = [string]$settings.meFilter
        }
        if ($settings.PSObject.Properties['assigneeFilter'] -and $settings.assigneeFilter) {
            $assigneeFilter = [string]$settings.assigneeFilter
        }
    }
    catch {
        $result.warning = "TicketTracker settings unavailable: $($_.Exception.Message)"
        return $result
    }

    if (-not (Test-MetraTicketAttentionEligible -Ticket $ticketObj -Scope mine -MeFilter $meFilter -AssigneeFilter $assigneeFilter)) {
        $result.warning = 'Ticket is not Mine Attention-eligible; Affirm A store refused (fail closed).'
        return $result
    }
    $result.mineEligible = $true

    # Preview refreshes local analyze + next-evidence so the desk is not a subject echo.
    # Confirm uses existing notes unless analyze is missing (then one refresh).
    $hadAnalyze = [bool](Get-MetraTicketWatchLatestNoteText -TicketId $canonicalId -Tag 'analyze-draft')
    $refreshAnalyze = [bool]$Preview -or (-not $hadAnalyze)
    $ev = $null
    if ($Preview -or (-not $hadAnalyze)) {
        try {
            $ev = Invoke-MetraTicketWatchEnsureAnalyzeEvidence `
                -Ticket $ticketObj `
                -TicketId $canonicalId `
                -RefreshAnalyze:$refreshAnalyze
        }
        catch {
            $result.warning = "Local analyze failed: $($_.Exception.Message). Sync/pull the ticket, then Preview again."
            if ($Confirm) { return $result }
        }
    }

    $evidenceNote = if ($ev) { [string]$ev.EvidenceNote } else {
        Get-MetraTicketWatchLatestNoteText -TicketId $canonicalId -Tag 'evidence-next'
    }
    $analyzeNote = if ($ev) { [string]$ev.AnalyzeNote } else {
        Get-MetraTicketWatchLatestNoteText -TicketId $canonicalId -Tag 'analyze-draft'
    }
    $isRecommendable = if ($ev) { [bool]$ev.Recommendable } else {
        Test-MetraTicketWatchNoteIsRecommendable -NoteText $evidenceNote
    }
    $result.recommendable = $isRecommendable

    # Confirm (Write) stays hard-gated unless -Force. Preview soft-gates with an honest next-evidence body.
    if (-not $isRecommendable -and -not $Force) {
        $blockedMsg = Get-MetraTicketWatchRecommendBlockedMessage `
            -EvidenceNote $evidenceNote `
            -AnalyzeNote $analyzeNote `
            -Mode $(if ($Confirm) { 'confirm' } else { 'preview' })
        $result.nextSteps = $blockedMsg
        if ($Confirm) {
            $result.warning = $blockedMsg
            return $result
        }
        $result.warning = $blockedMsg
    }

    $similarLines = @()
    $solutionLines = @()
    $evidenceHint = ''
    $simCount = 0
    $solCount = 0
    $subject = [string](Get-MetraProp -Object $ticketObj -Name 'Subject' -Default '')
    if ($ev) {
        $similarLines = @($ev.SimilarLines)
        $solutionLines = @($ev.SolutionLines)
        $simCount = [int]$ev.SimilarCount
        $solCount = [int]$ev.SolutionsCount
        if ($ev.Subject) { $subject = [string]$ev.Subject }
    }
    elseif ($analyzeNote) {
        $parsed = ConvertFrom-MetraTicketWatchAnalyzeNote -NoteText $analyzeNote
        $similarLines = @($parsed.SimilarLines)
        $solutionLines = @($parsed.SolutionLines)
        $simCount = [int]$parsed.SimilarCount
        $solCount = [int]$parsed.SolutionsCount
    }
    if ($evidenceNote -match '(?im)^\s*Action:\s*(\S+)') {
        $evidenceHint = $Matches[1]
    }

    $basis = New-MetraTicketWatchRecommendBasis `
        -SimilarCount $simCount `
        -SolutionsCount $solCount `
        -MailEvidence:($evidenceHint -eq 'm365Mail') `
        -WebSuggested:($evidenceHint -eq 'boundedWeb')

    $useNextEvidenceBody = $Preview -and (-not $isRecommendable) -and (-not $Force)
    if ($useNextEvidenceBody) {
        $body = New-MetraTicketWatchNextEvidenceBody `
            -TicketId $canonicalId `
            -Subject $subject `
            -Suggestion $(if ($ev) { $ev.Suggestion } else { $null }) `
            -SimilarCount $simCount `
            -SolutionsCount $solCount `
            -SimilarLines $similarLines `
            -SolutionLines $solutionLines
    }
    else {
        $body = New-MetraTicketWatchRecommendBody `
            -Subject $subject `
            -SimilarLines $similarLines `
            -SolutionLines $solutionLines `
            -EvidenceHint $evidenceHint `
            -Basis $basis
    }
    $forceOverride = [bool]($Force -and -not $isRecommendable)
    if ($forceOverride -and -not $useNextEvidenceBody) {
        $overrideLine = 'Operator override: recommendation written despite thin local evidence.'
        $body = ($overrideLine + "`n`n" + $body).Trim()
        $result.warning = 'Force override used; evidence was not recommendable.'
    }
    $result.body = $body

    if ($Preview) {
        $noteBody = Format-MetraTicketWatchRecommendDraftNote -Body $body -Basis $basis
        try {
            $note = Add-TrackedTicketNote -Id $canonicalId -Text $noteBody -Tags 'recommend-draft'
            $result.noteId = [string]$note.Id
            $result.ok = $true
            if (-not $Quiet) {
                Write-Host ''
                if ($useNextEvidenceBody) {
                    Write-Host 'M3 Preview: next-evidence brief (not a recommendation; no iSupport write).'
                }
                else {
                    Write-Host 'M3 Preview: local recommend-draft written (no iSupport write).'
                }
                if ($result.warning) {
                    Write-Host $result.warning
                }
                Write-Host $body
                Write-Host ''
            }
        }
        catch {
            $result.warning = "Failed to write recommend-draft note: $($_.Exception.Message)"
        }
        return $result
    }

    # Confirm - Affirm A store-as-review
    try {
        $null = Set-ISupportAiRecommendation -Id $canonicalId -Recommendation $body -TimeWorkedMinutes $Minutes
        $result.iSupportWrite = $true
        $result.recommendationWritten = $true
        $result.ok = $true
        if (-not $Quiet) {
            Write-Host ''
            if ($forceOverride) {
                Write-Host 'M3 Affirm A: Force override write (thin local evidence). Re-run supersedes the same section.'
            }
            else {
                Write-Host 'M3 Affirm A: Recommendation written (store-as-review). Re-run supersedes the same section.'
            }
            Write-Host ''
        }
    }
    catch {
        $result.warning = "TT recommend failed: $($_.Exception.Message)"
    }
    return $result
}

function Test-MetraTicketAttentionEligible {
    <#
    .SYNOPSIS
        Attention eligibility under TicketWatch scope (cache != Attention).
    .DESCRIPTION
        Under scope mine: active + matches meFilter/assigneeFilter via
        Test-TicketMatchesPersonFilter (or equivalent). Does not OR queueInclude.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ticket,
        [ValidateSet('mine')]
        [string]$Scope = 'mine',
        [string]$MeFilter = '',
        [string]$AssigneeFilter = ''
    )

    $status = [string](Get-MetraProp -Object $Ticket -Name 'Status' -Default '')
    if (-not $status) { $status = [string](Get-MetraProp -Object $Ticket -Name 'status' -Default '') }
    if (-not (Test-MetraTicketStatusIsActive -Status $status)) { return $false }

    if ($Scope -eq 'mine') {
        if (-not $MeFilter -and -not $AssigneeFilter) { return $false }
        $matchCmd = Get-Command Test-TicketMatchesPersonFilter -ErrorAction SilentlyContinue
        if ($matchCmd) {
            return [bool](& $matchCmd -Ticket $Ticket -MeFilter $MeFilter -AssigneeFilter $AssigneeFilter)
        }
        # Fallback when TT helper is not loaded (unit tests / thin hosts).
        if ($MeFilter) {
            $assignee = [string](Get-MetraProp -Object $Ticket -Name 'Assignee' -Default '')
            if (-not $assignee) { $assignee = [string](Get-MetraProp -Object $Ticket -Name 'assignee' -Default '') }
            $customer = [string](Get-MetraProp -Object $Ticket -Name 'Customer' -Default '')
            if (-not $customer) { $customer = [string](Get-MetraProp -Object $Ticket -Name 'customer' -Default '') }
            return ($assignee -like $MeFilter) -or ($customer -like $MeFilter)
        }
        if ($AssigneeFilter) {
            $assignee = [string](Get-MetraProp -Object $Ticket -Name 'Assignee' -Default '')
            if (-not $assignee) { $assignee = [string](Get-MetraProp -Object $Ticket -Name 'assignee' -Default '') }
            return ($assignee -like $AssigneeFilter)
        }
        return $false
    }

    return $false
}

function Get-MetraTicketTrackerPersonFilters {
    <#
    .SYNOPSIS
        Reads TicketTracker meFilter / assigneeFilter for Attention assignee ranking.
    #>
    [CmdletBinding()]
    param()

    $meFilter = ''
    $assigneeFilter = ''
    try {
        $settings = Get-TicketTrackerSettings
        if ($settings.PSObject.Properties['meFilter'] -and $settings.meFilter) {
            $meFilter = [string]$settings.meFilter
        }
        if ($settings.PSObject.Properties['assigneeFilter'] -and $settings.assigneeFilter) {
            $assigneeFilter = [string]$settings.assigneeFilter
        }
    }
    catch { }

    return [PSCustomObject]@{
        MeFilter       = $meFilter
        AssigneeFilter = $assigneeFilter
    }
}

function Test-MetraTicketAssigneeMatchesMe {
    <#
    .SYNOPSIS
        True when the ticket assignee matches meFilter (assignee only, not customer).
        When meFilter is empty, falls back to assigneeFilter.
    #>
    [CmdletBinding()]
    param(
        [string]$Assignee = '',
        [string]$MeFilter = '',
        [string]$AssigneeFilter = ''
    )

    $assignee = ([string]$Assignee).Trim()
    if (-not $assignee) { return $false }
    if ($MeFilter -and ($assignee -like $MeFilter)) { return $true }
    if (-not $MeFilter -and $AssigneeFilter -and ($assignee -like $AssigneeFilter)) { return $true }
    return $false
}

function Get-MetraTicketAttentionAssigneeRank {
    <#
    .SYNOPSIS
        Lower number = higher Attention priority. Assigned-to-me tickets sort above others.
    #>
    [CmdletBinding()]
    param(
        [string]$Assignee = '',
        [string]$MeFilter = '',
        [string]$AssigneeFilter = ''
    )

    if (-not $MeFilter -and -not $AssigneeFilter) { return 1 }
    if (Test-MetraTicketAssigneeMatchesMe -Assignee $Assignee -MeFilter $MeFilter -AssigneeFilter $AssigneeFilter) {
        return 0
    }
    return 1
}

function Get-MetraAttentionItemAssigneeRank {
    [CmdletBinding()]
    param($Item)

    if ([string]$Item.kind -ne 'ticket') { return 0 }

    $explicit = Get-MetraProp -Object $Item -Name 'assigneeRank' -Default $null
    if ($null -ne $explicit -and "$explicit" -ne '') {
        try { return [int]$explicit } catch { }
    }

    $assignee = [string](Get-MetraProp -Object $Item -Name 'ticketAssignee' -Default '')
    if (-not $assignee) {
        $detail = [string](Get-MetraProp -Object $Item -Name 'detail' -Default '')
        if ($detail -match '(?i)\bassigned to (.+?)(?:\s*-\s*updated|\s*-\s*Has Metra|\s*$)') {
            $assignee = $Matches[1].Trim()
        }
    }

    $filters = Get-MetraTicketTrackerPersonFilters
    return (Get-MetraTicketAttentionAssigneeRank -Assignee $assignee `
        -MeFilter ([string]$filters.MeFilter) -AssigneeFilter ([string]$filters.AssigneeFilter))
}

function ConvertTo-MetraTicketWatchNormalizedTicket {
    <#
    .SYNOPSIS
        Bind TT sensor contract (ConvertTo-TicketSensorObject) plus display fields for Attention.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ticket
    )

    $sensor = $null
    $convertCmd = Get-Command ConvertTo-TicketSensorObject -ErrorAction SilentlyContinue
    if ($convertCmd) {
        try { $sensor = & $convertCmd -Ticket $Ticket } catch { $sensor = $null }
    }

    $id = if ($sensor) { [string]$sensor.id } else { '' }
    if (-not $id) { $id = [string](Get-MetraProp -Object $Ticket -Name 'Id' -Default '') }
    if (-not $id) { $id = [string](Get-MetraProp -Object $Ticket -Name 'id' -Default '') }

    $status = if ($sensor) { [string]$sensor.status } else { '' }
    if (-not $status) { $status = [string](Get-MetraProp -Object $Ticket -Name 'Status' -Default '') }
    if (-not $status) { $status = [string](Get-MetraProp -Object $Ticket -Name 'status' -Default '') }

    $updated = if ($sensor) { [string]$sensor.updatedUtc } else { '' }
    if (-not $updated) { $updated = [string](Get-MetraProp -Object $Ticket -Name 'Updated' -Default '') }
    if (-not $updated) { $updated = [string](Get-MetraProp -Object $Ticket -Name 'updatedUtc' -Default '') }

    $subject = if ($sensor) { [string]$sensor.subject } else { '' }
    if (-not $subject) { $subject = [string](Get-MetraProp -Object $Ticket -Name 'Subject' -Default '') }
    if (-not $subject) { $subject = [string](Get-MetraProp -Object $Ticket -Name 'subject' -Default '') }

    $assignee = if ($sensor) { [string]$sensor.assignee } else { '' }
    if (-not $assignee) { $assignee = [string](Get-MetraProp -Object $Ticket -Name 'Assignee' -Default '') }
    if (-not $assignee) { $assignee = [string](Get-MetraProp -Object $Ticket -Name 'assignee' -Default '') }

    $number = if ($sensor) { [string]$sensor.number } else { '' }
    if (-not $number) { $number = [string](Get-MetraProp -Object $Ticket -Name 'Number' -Default '') }
    if (-not $number) { $number = [string](Get-MetraProp -Object $Ticket -Name 'number' -Default '') }

    $customer = [string](Get-MetraProp -Object $Ticket -Name 'Customer' -Default '')
    if (-not $customer) { $customer = [string](Get-MetraProp -Object $Ticket -Name 'customer' -Default '') }
    $priority = [string](Get-MetraProp -Object $Ticket -Name 'Priority' -Default '')
    if (-not $priority) { $priority = [string](Get-MetraProp -Object $Ticket -Name 'priority' -Default '') }

    return [PSCustomObject]@{
        Id       = $id
        Number   = $number
        Subject  = $subject
        Status   = $status
        Updated  = $updated
        Assignee = $assignee
        Customer = $customer
        Priority = $priority
        Source   = if ($sensor -and $sensor.source) { [string]$sensor.source } else { 'TicketTracker' }
    }
}

function Get-MetraTicketWatchRecommendationFingerprint {
    <#
    .SYNOPSIS
        Stable fingerprint for evidenceSignature (SHA-256 of normalized body).
    #>
    [CmdletBinding()]
    param([string]$Recommendation = '')

    $text = ([string]$Recommendation).Trim()
    if (-not $text) { return '' }
    $norm = ($text -replace '\s+', ' ').Trim()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($norm)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Get-MetraTicketWatchLocalRecommendDraftBody {
    [CmdletBinding()]
    param([string]$NoteText = '')

    if ([string]::IsNullOrWhiteSpace($NoteText)) { return '' }
    $body = [string]$NoteText
    if ($body -match '(?is)^\s*\[recommend-draft\]\s*\r?\n(.*)$') {
        $body = $Matches[1]
    }
    $body = [regex]::Replace($body, '(?im)^\s*M3 Preview[^\r\n]*\r?\n', '')
    $body = [regex]::Replace($body, '(?im)^\s*Affirm A[^\r\n]*\r?\n', '')
    return $body.Trim()
}

function Get-MetraTicketWatchScrubbedRecommendationText {
    [CmdletBinding()]
    param([string]$Text)

    $text = ([string]$Text).Trim()
    if (-not $text) { return '' }
    try {
        $scrub = Invoke-MetraAskSecretsScrubText -Text $text
        return [string]$scrub.Text
    }
    catch {
        Write-Warning "Recommendation scrub failed: $($_.Exception.Message)"
        return ''
    }
}

function Get-MetraTicketWatchExistingRecommendation {
    <#
    .SYNOPSIS
        Returns iSupport description recommendation and/or local recommend-draft (iSupport wins).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ticket,
        [string]$TicketId = ''
    )

    $id = [string]$TicketId
    if (-not $id) {
        $id = [string](Get-MetraProp -Object $Ticket -Name 'Id' -Default '')
        if (-not $id) { $id = [string](Get-MetraProp -Object $Ticket -Name 'id' -Default '') }
    }

    $isupport = ''
    $getRec = Get-Command Get-ISupportAiRecommendation -ErrorAction SilentlyContinue
    if ($getRec) {
        $desc = [string](Get-MetraProp -Object $Ticket -Name 'Description' -Default '')
        if (-not $desc) { $desc = [string](Get-MetraProp -Object $Ticket -Name 'description' -Default '') }
        if ($desc) {
            try { $isupport = [string](& $getRec -ExistingProblem $desc) } catch { $isupport = '' }
        }
    }

    $local = ''
    if ($id) {
        try {
            $draftNote = Get-MetraTicketWatchLatestNoteText -TicketId $id -Tag 'recommend-draft'
            $local = Get-MetraTicketWatchLocalRecommendDraftBody -NoteText $draftNote
        }
        catch { $local = '' }
    }

    if ($isupport) {
        $isupport = Get-MetraTicketWatchScrubbedRecommendationText -Text $isupport
        if ($isupport) {
            return [PSCustomObject]@{
                Text   = $isupport
                Source = 'isupport'
            }
        }
    }
    if ($local) {
        $local = Get-MetraTicketWatchScrubbedRecommendationText -Text $local
        return [PSCustomObject]@{
            Text   = $local
            Source = 'local-draft'
        }
    }
    return [PSCustomObject]@{
        Text   = ''
        Source = ''
    }
}

function New-MetraTicketAttentionEvidenceSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [string]$Updated = '',
        [string]$Status = '',
        [string]$RecommendationFingerprint = ''
    )

    $rec = Get-MetraTicketWatchRecommendationFingerprint -Recommendation $RecommendationFingerprint
    return ('ticket:{0}|updated:{1}|status:{2}|rec:{3}' -f $TicketId.Trim(), ([string]$Updated).Trim(), ([string]$Status).Trim(), $rec)
}

function Format-MetraTicketPriorityLabel {
    [CmdletBinding()]
    param([string]$Priority = '')

    $p = ([string]$Priority).Trim()
    if (-not $p) { return '' }
    if ($p -match '^(?i)(critical|high|medium|low)$') {
        return (Get-Culture).TextInfo.ToTitleCase($p.ToLowerInvariant()) + ' priority'
    }
    if ($p -match '^\d+$') { return "Priority $p" }
    return $p
}

function Test-MetraTicketStatusIsActive {
    [CmdletBinding()]
    param([string]$Status = '')

    $s = ([string]$Status).Trim()
    if (-not $s) { return $true }
    return ($s -notmatch '(?i)^(closed|resolved|cancelled|canceled)\b')
}

function Get-MetraTicketAttentionStatusCode {
    <#
    .SYNOPSIS
        Short iSupport status code for Attention list rows (O, W, UR, etc.).
    #>
    [CmdletBinding()]
    param([string]$Status = '')

    $s = ([string]$Status).Trim()
    if (-not $s) { return '' }
    if ($s -match '(?i)^update from representative') { return 'UR' }
    if ($s -match '(?i)^update from customer') { return 'UC' }
    if ($s -match '(?i)^waiting on customer') { return 'W' }
    if ($s -match '(?i)^open\b') { return 'O' }
    if ($s -match '(?i)^reopened\b') { return 'R' }
    if ($s -match '(?i)^in\s*progress\b') { return 'IP' }
    if ($s -match '(?i)^pending\b') { return 'P' }
    if ($s -match '(?i)^on\s*hold\b') { return 'H' }
    if ($s -match '(?i)^assigned\b') { return 'A' }
    if ($s -match '(?i)^new\b') { return 'N' }
    if ($s -match '(?i)^active\b') { return 'A' }
    if ($s -match '(?i)^scheduled\b') { return 'S' }
    if ($s -match '(?i)^closed\b') { return 'C' }
    if ($s -match '^(\w)') { return $Matches[1].ToUpperInvariant() }
    return ''
}

function Get-MetraTicketAttentionStatusRank {
    <#
    .SYNOPSIS
        Lower number = higher Attention priority.
        Update from Representative/Customer sorts above Open; Waiting on Customer below Open.
    #>
    [CmdletBinding()]
    param([string]$Status = '')

    $s = ([string]$Status).Trim()
    if (-not $s) { return 15 }
    # New inbound signal - surface before steady Open work.
    if ($s -match '(?i)^update from\b') { return 0 }
    # Ball in operator court.
    if ($s -match '(?i)^open\b') { return 10 }
    if ($s -match '(?i)^reopened\b') { return 10 }
    if ($s -match '(?i)^(in\s*progress|assigned|new|active)\b') { return 20 }
    # Ball with customer / parked - keep in queue but below Open work.
    if ($s -match '(?i)^waiting\b') { return 40 }
    if ($s -match '(?i)^(pending|on\s*hold)\b') { return 30 }
    return 25
}

function Get-MetraAttentionItemUpdatedUtcTicks {
    <#
    .SYNOPSIS
        Newer ticket updates sort first within the same statusRank (descending ticks).
    #>
    [CmdletBinding()]
    param($Item)

    if ([string]$Item.kind -ne 'ticket') { return [long]0 }
    $sig = [string](Get-MetraProp -Object $Item -Name 'evidenceSignature' -Default '')
    if ($sig -match '(?i)\|updated:([^|]+)') {
        $raw = $Matches[1].Trim()
        if ($raw) {
            try {
                $dt = [datetime]::Parse($raw, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                return $dt.ToUniversalTime().Ticks
            }
            catch {
                try { return ([datetime]$raw).ToUniversalTime().Ticks } catch { }
            }
        }
    }
    $lastSeen = [string](Get-MetraProp -Object $Item -Name 'lastSeenAt' -Default '')
    if ($lastSeen) {
        try {
            $dt = [datetime]::Parse($lastSeen, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            return $dt.ToUniversalTime().Ticks
        }
        catch { }
    }
    return [long]0
}

function Get-MetraAttentionItemStatusRank {
    [CmdletBinding()]
    param($Item)

    if ([string]$Item.kind -ne 'ticket') { return 0 }
    $status = [string](Get-MetraProp -Object $Item -Name 'ticketStatus' -Default '')
    if (-not $status) {
        $detail = [string](Get-MetraProp -Object $Item -Name 'detail' -Default '')
        if ($detail -match '(?i)^(Update from (?:Representative|Customer)|Waiting on Customer|Open|Reopened|In Progress|Pending|On Hold)') {
            $status = $Matches[1]
        }
        elseif ([string]$Item.evidenceSignature -match '(?i)\|status:([^|]+)') {
            $status = $Matches[1].Trim()
        }
    }
    if ($status) {
        return (Get-MetraTicketAttentionStatusRank -Status $status)
    }
    $explicit = Get-MetraProp -Object $Item -Name 'statusRank' -Default $null
    if ($null -ne $explicit -and "$explicit" -ne '') {
        try { return [int]$explicit } catch { }
    }
    return (Get-MetraTicketAttentionStatusRank -Status '')
}

function ConvertTo-MetraTicketAttentionQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ticket,
        [string]$TicketTrackerPath = ''
    )

    $norm = ConvertTo-MetraTicketWatchNormalizedTicket -Ticket $Ticket
    $id = [string]$norm.Id
    if (-not $id) { return $null }

    $status = [string]$norm.Status
    $updated = [string]$norm.Updated
    $priority = [string]$norm.Priority
    $subject = ([string]$norm.Subject).Trim()
    $customer = ([string]$norm.Customer).Trim()
    $assignee = ([string]$norm.Assignee).Trim()

    $priorityLabel = Format-MetraTicketPriorityLabel -Priority $priority
    $content = if ($subject) { "Ticket $id`: $subject" } else { "Ticket $id needs triage" }
    if (-not $subject -and $priorityLabel) { $content = "$content - $priorityLabel" }

    $recInfo = Get-MetraTicketWatchExistingRecommendation -Ticket $Ticket -TicketId $id
    $recText = [string](Get-MetraProp -Object $recInfo -Name 'Text' -Default '')
    $recSource = [string](Get-MetraProp -Object $recInfo -Name 'Source' -Default '')

    $detailParts = @()
    if ($status) { $detailParts += $status }
    if ($priorityLabel) { $detailParts += $priorityLabel }
    if ($customer) { $detailParts += "for $customer" }
    if ($assignee) { $detailParts += "assigned to $assignee" }
    if ($updated) {
        $updatedText = $updated
        try {
            $u = [datetime]::Parse($updated, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $updatedText = $u.ToLocalTime().ToString('MMM d, h:mm tt')
        }
        catch {
            try {
                $u = [datetime]$updated
                $updatedText = $u.ToString('MMM d, h:mm tt')
            }
            catch { }
        }
        $detailParts += "updated $updatedText"
    }
    if ($recText) {
        $detailParts += 'Has Metra AI recommendation'
    }

    $filters = Get-MetraTicketTrackerPersonFilters
    $assigneeRank = Get-MetraTicketAttentionAssigneeRank -Assignee $assignee `
        -MeFilter ([string]$filters.MeFilter) -AssigneeFilter ([string]$filters.AssigneeFilter)
    $assignedToMe = Test-MetraTicketAssigneeMatchesMe -Assignee $assignee `
        -MeFilter ([string]$filters.MeFilter) -AssigneeFilter ([string]$filters.AssigneeFilter)

    return [PSCustomObject]@{
        id                = "ticket:$id"
        project           = 'TicketTracker'
        kind              = 'ticket'
        content           = $content
        detail            = ($detailParts -join ' - ')
        ticketStatus      = $status
        ticketStatusCode  = (Get-MetraTicketAttentionStatusCode -Status $status)
        ticketAssignee    = $assignee
        assigneeRank      = $assigneeRank
        assignedToMe      = $assignedToMe
        statusRank        = (Get-MetraTicketAttentionStatusRank -Status $status)
        command           = ".\TicketTracker.ps1 brief $id"
        source            = 'TicketTracker'
        existingRecommendation = $recText
        recommendationSource = $recSource
        evidenceSignature = (New-MetraTicketAttentionEvidenceSignature -TicketId $id -Updated $updated -Status $status -RecommendationFingerprint $recText)
    }
}

function Update-MetraTicketAttentionDisplayFields {
    <#
    .SYNOPSIS
        Fills subject/status/priority/customer on a ticket Attention item from TicketTracker.
        Used at desk-view time so Ops is not stuck on thin pre-subject memory rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$MemItem
    )

    if ([string]$MemItem.kind -ne 'ticket') { return $MemItem }

    $id = ''
    $key = [string]$MemItem.key
    $content = [string]$MemItem.content
    if ($key -match '(?i)^ticket:(\d+)') { $id = $Matches[1] }
    elseif ($content -match '(?i)\b(\d{6,8})\b') { $id = $Matches[1] }
    if (-not $id) { return $MemItem }

    $detail = [string](Get-MetraProp -Object $MemItem -Name 'detail' -Default '')
    $hasSubject = $content -match '(?i)^Ticket\s+\d+\s*:'

    $tt = Resolve-MetraTicketTrackerModule
    if (-not $tt) { return $MemItem }

    try {
        $null = Import-MetraTicketTrackerModule -ModulePath $tt.ModulePath
        $getTickets = Get-Command Get-TrackedTickets -ErrorAction Stop
        $ticket = @(& $getTickets -Id $id | Select-Object -First 1)
        if ($ticket.Count -eq 0) { return $MemItem }
        $qi = ConvertTo-MetraTicketAttentionQueueItem -Ticket $ticket[0] -TicketTrackerPath $tt.Path
        if (-not $qi) { return $MemItem }
        if (-not ($hasSubject -and $detail)) {
            $MemItem.content = [string]$qi.content
            if ($MemItem.PSObject.Properties['detail']) { $MemItem.detail = [string]$qi.detail }
            else { $MemItem | Add-Member -NotePropertyName detail -NotePropertyValue ([string]$qi.detail) -Force }
        }
        $recText = [string](Get-MetraProp -Object $qi -Name 'existingRecommendation' -Default '')
        $recSource = [string](Get-MetraProp -Object $qi -Name 'recommendationSource' -Default '')
        if ($MemItem.PSObject.Properties['existingRecommendation']) { $MemItem.existingRecommendation = $recText }
        else { $MemItem | Add-Member -NotePropertyName existingRecommendation -NotePropertyValue $recText -Force }
        if ($MemItem.PSObject.Properties['recommendationSource']) { $MemItem.recommendationSource = $recSource }
        else { $MemItem | Add-Member -NotePropertyName recommendationSource -NotePropertyValue $recSource -Force }
        $ticketStatus = [string](Get-MetraProp -Object $qi -Name 'ticketStatus' -Default '')
        $ticketStatusCode = [string](Get-MetraProp -Object $qi -Name 'ticketStatusCode' -Default '')
        if (-not $ticketStatusCode -and $ticketStatus) {
            $ticketStatusCode = Get-MetraTicketAttentionStatusCode -Status $ticketStatus
        }
        $statusRank = Get-MetraProp -Object $qi -Name 'statusRank' -Default $null
        if ($MemItem.PSObject.Properties['ticketStatus']) { $MemItem.ticketStatus = $ticketStatus }
        else { $MemItem | Add-Member -NotePropertyName ticketStatus -NotePropertyValue $ticketStatus -Force }
        if ($MemItem.PSObject.Properties['ticketStatusCode']) { $MemItem.ticketStatusCode = $ticketStatusCode }
        else { $MemItem | Add-Member -NotePropertyName ticketStatusCode -NotePropertyValue $ticketStatusCode -Force }
        $ticketAssignee = [string](Get-MetraProp -Object $qi -Name 'ticketAssignee' -Default '')
        $filters = Get-MetraTicketTrackerPersonFilters
        $assigneeRank = Get-MetraProp -Object $qi -Name 'assigneeRank' -Default $null
        if ($null -eq $assigneeRank -or "$assigneeRank" -eq '') {
            $assigneeRank = Get-MetraTicketAttentionAssigneeRank -Assignee $ticketAssignee `
                -MeFilter ([string]$filters.MeFilter) -AssigneeFilter ([string]$filters.AssigneeFilter)
        }
        $assignedToMe = Test-MetraTicketAssigneeMatchesMe -Assignee $ticketAssignee `
            -MeFilter ([string]$filters.MeFilter) -AssigneeFilter ([string]$filters.AssigneeFilter)
        if ($MemItem.PSObject.Properties['ticketAssignee']) { $MemItem.ticketAssignee = $ticketAssignee }
        else { $MemItem | Add-Member -NotePropertyName ticketAssignee -NotePropertyValue $ticketAssignee -Force }
        if ($MemItem.PSObject.Properties['assigneeRank']) { $MemItem.assigneeRank = $assigneeRank }
        else { $MemItem | Add-Member -NotePropertyName assigneeRank -NotePropertyValue $assigneeRank -Force }
        if ($MemItem.PSObject.Properties['assignedToMe']) { $MemItem.assignedToMe = $assignedToMe }
        else { $MemItem | Add-Member -NotePropertyName assignedToMe -NotePropertyValue $assignedToMe -Force }
        if ($MemItem.PSObject.Properties['statusRank']) { $MemItem.statusRank = $statusRank }
        else { $MemItem | Add-Member -NotePropertyName statusRank -NotePropertyValue $statusRank -Force }
        if ($qi.command) { $MemItem.command = [string]$qi.command }
        if ($qi.evidenceSignature) { $MemItem.evidenceSignature = [string]$qi.evidenceSignature }
    }
    catch { }

    return $MemItem
}

function Get-MetraTicketWatchCandidates {
    <#
    .SYNOPSIS
        Reads TicketTracker cache, then applies Metra Attention eligibility (cache != Attention).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModulePath,
        [int]$Top = 10,
        [bool]$DoSync = $false,
        [ValidateSet('mine')]
        [string]$Scope = 'mine'
    )

    $null = Import-MetraTicketTrackerModule -ModulePath $ModulePath
    $synced = $false
    $syncError = ''
    $scopeWarning = ''
    if ($DoSync) {
        try {
            $null = Sync-TrackedTickets
            $synced = $true
        }
        catch {
            $syncError = $_.Exception.Message
        }
    }

    $meFilter = ''
    $assigneeFilter = ''
    try {
        $settings = Get-TicketTrackerSettings
        if ($settings.PSObject.Properties['meFilter'] -and $settings.meFilter) {
            $meFilter = [string]$settings.meFilter
        }
        if ($settings.PSObject.Properties['assigneeFilter'] -and $settings.assigneeFilter) {
            $assigneeFilter = [string]$settings.assigneeFilter
        }
    }
    catch {
        $scopeWarning = "TicketTracker settings unavailable; mine Attention skipped. $($_.Exception.Message)"
        return [PSCustomObject]@{
            Tickets      = @()
            Synced       = $synced
            SyncError    = $syncError
            Scanned      = 0
            Truncated    = $false
            Scope        = $Scope
            ScopeWarning = $scopeWarning
            FailClosed   = $true
        }
    }

    if ($Scope -eq 'mine' -and -not $meFilter -and -not $assigneeFilter) {
        $scopeWarning = 'ticketWatch.scope=mine requires TicketTracker meFilter or assigneeFilter; Attention candidates are empty (fail closed).'
        return [PSCustomObject]@{
            Tickets      = @()
            Synced       = $synced
            SyncError    = $syncError
            Scanned      = 0
            Truncated    = $false
            Scope        = $Scope
            ScopeWarning = $scopeWarning
            FailClosed   = $true
        }
    }

    $byId = @{}
    # Include Waiting on Customer and other non-closed statuses - Open* alone misses active work.
    $activeTickets = @(
        Get-TrackedTickets | Where-Object {
            $st = [string](Get-MetraProp -Object $_ -Name 'Status' -Default '')
            Test-MetraTicketStatusIsActive -Status $st
        }
    )
    foreach ($t in $activeTickets) {
        $id = [string](Get-MetraProp -Object $t -Name 'Id' -Default '')
        if ($id) { $byId[$id] = $t }
    }
    # Avoid TicketTracker Get-TrackedTickets -Watched: local $watched overwrites [switch]$Watched (case-insensitive).
    # Watched-but-not-mine is still collected here, then dropped by eligibility (pull != Attention subscription).
    $ttModule = Get-Module TicketTracker
    if ($ttModule) {
        $watchedIds = @(& $ttModule { @((Get-StateStore).Data.watched) })
        foreach ($wid in $watchedIds) {
            if (-not $wid) { continue }
            $widText = [string]$wid
            if ($byId.ContainsKey($widText)) { continue }
            $t = @(Get-TrackedTickets -Id $widText | Select-Object -First 1)
            if ($t.Count -gt 0) { $byId[$widText] = $t[0] }
        }
    }

    $eligible = @(
        foreach ($t in $byId.Values) {
            if (-not (Test-MetraTicketAttentionEligible -Ticket $t -Scope $Scope -MeFilter $meFilter -AssigneeFilter $assigneeFilter)) {
                continue
            }
            ConvertTo-MetraTicketWatchNormalizedTicket -Ticket $t
        }
    )

    $sorted = @(
        $eligible | Sort-Object -Property @{
            Expression = {
                Get-MetraTicketAttentionAssigneeRank -Assignee ([string](Get-MetraProp -Object $_ -Name 'Assignee' -Default '')) `
                    -MeFilter $meFilter -AssigneeFilter $assigneeFilter
            }
            Descending = $false
        }, @{
            Expression = {
                Get-MetraTicketAttentionStatusRank -Status ([string](Get-MetraProp -Object $_ -Name 'Status' -Default ''))
            }
            Descending = $false
        }, @{
            Expression = {
                $u = Get-MetraProp -Object $_ -Name 'Updated' -Default $null
                if ($u) {
                    try { return [datetime]$u } catch { return [datetime]::MinValue }
                }
                return [datetime]::MinValue
            }
            Descending = $true
        }, @{
            Expression = { [string](Get-MetraProp -Object $_ -Name 'Priority' -Default '') }
            Descending = $false
        }
    )
    $truncated = $false
    if ($Top -gt 0 -and $sorted.Count -gt $Top) {
        $truncated = $true
        $sorted = @($sorted | Select-Object -First $Top)
    }

    return [PSCustomObject]@{
        Tickets      = $sorted
        Synced       = $synced
        SyncError    = $syncError
        Scanned      = $sorted.Count
        Truncated    = $truncated
        Scope        = $Scope
        ScopeWarning = $scopeWarning
        FailClosed   = $false
    }
}

$script:MetraTicketWatchScanLeaseId = $null

function Get-MetraTicketWatchScanLeasePath {
    Join-Path $env:LOCALAPPDATA 'Metra\ticket-watch-scan.lease'
}

function Test-MetraTicketWatchScanLeaseActive {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $lease = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
        $untilText = [string](Get-MetraProp -Object $lease -Name 'untilUtc' -Default '')
        if (-not $untilText) { return $false }
        $until = [datetime]::Parse($untilText, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if ([datetime]::UtcNow -ge $until.ToUniversalTime()) { return $false }
        $holderPid = [int](Get-MetraProp -Object $lease -Name 'pid' -Default 0)
        if ($holderPid -le 0) { return $true }
        $alive = $false
        try { $null = Get-Process -Id $holderPid -ErrorAction Stop; $alive = $true } catch { }
        return $alive
    }
    catch {
        return $false
    }
}

function Enter-MetraTicketWatchScanLease {
    [CmdletBinding()]
    param([int]$Minutes = 15)

    $path = Get-MetraTicketWatchScanLeasePath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (Test-MetraTicketWatchScanLeaseActive -Path $path) {
        return $false
    }
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    $leaseId = [guid]::NewGuid().ToString('D')
    $payload = (@{
        leaseId  = $leaseId
        pid      = $PID
        untilUtc = [datetime]::UtcNow.AddMinutes($Minutes).ToString('o')
    } | ConvertTo-Json -Compress)
    try {
        $fs = [System.IO.File]::Open(
            $path,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None)
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
            $fs.Write($bytes, 0, $bytes.Length)
        }
        finally {
            $fs.Dispose()
        }
        $script:MetraTicketWatchScanLeaseId = $leaseId
        return $true
    }
    catch [System.IO.IOException] {
        return $false
    }
}

function Exit-MetraTicketWatchScanLease {
    param([string]$LeaseId)

    $expected = if ($LeaseId) { $LeaseId } else { $script:MetraTicketWatchScanLeaseId }
    if (-not $expected) { return }

    $path = Get-MetraTicketWatchScanLeasePath
    if (-not (Test-Path -LiteralPath $path)) {
        if ($script:MetraTicketWatchScanLeaseId -eq $expected) {
            $script:MetraTicketWatchScanLeaseId = $null
        }
        return
    }
    try {
        $lease = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        $currentId = [string](Get-MetraProp -Object $lease -Name 'leaseId' -Default '')
        if ($currentId) {
            if ($currentId -ne $expected) { return }
        }
        else {
            $holderPid = [int](Get-MetraProp -Object $lease -Name 'pid' -Default 0)
            if ($holderPid -ne $PID) { return }
        }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    catch {
        return
    }
    finally {
        if ($script:MetraTicketWatchScanLeaseId -eq $expected) {
            $script:MetraTicketWatchScanLeaseId = $null
        }
    }
}

function Invoke-MetraTicketWatchScan {
    <#
    .SYNOPSIS
        Ticket-first watch intake: TicketTracker read signals -> Attention observations.
        No iSupport recommend/post/resolve. Optional local analyze drafts (M2).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Draft,
        [switch]$SkipSync,
        [switch]$Quiet,
        [int]$Top = 0
    )

    $cfg = Get-MetraTicketWatchConfig -MetraRoot $MetraRoot
    $topN = if ($Top -gt 0) { $Top } else { [int]$cfg.top }
    # Force draft: -Draft switch or writeLocalDraft config (always analyze mine-eligible in scan).
    $forceDraft = [bool]$Draft -or [bool]$cfg.writeLocalDraft
    $autoAnalyze = [bool]$cfg.autoAnalyze
    $autoAssess = [bool]$cfg.autoAssess
    $assessMaxAgeHours = [int]$cfg.assessMaxAgeHours
    $evidenceRouter = [bool]$cfg.evidenceRouter
    $doSync = [bool]$cfg.syncOnScan -and -not $SkipSync
    $scope = [string]$cfg.scope
    if ($scope -ne 'mine') { $scope = 'mine' }

    $result = [PSCustomObject]@{
        ok                   = $false
        available            = $false
        synced               = $false
        syncError            = ''
        warning              = ''
        scope                = $scope
        scanned              = 0
        added                = 0
        refreshed            = 0
        unchanged            = 0
        draftsWritten        = 0
        assessmentsWritten   = 0
        draftAvailable       = $false
        evidenceSuggestions  = 0
        evidenceRecommendable = 0
        nextEvidenceAvailable = $false
        readyForRecommendation = $false
        autoAnalyze          = $autoAnalyze
        autoAssess           = $autoAssess
        assessMaxAgeHours    = $assessMaxAgeHours
        evidenceRouter       = $evidenceRouter
        forceDraft           = $forceDraft
        coveredTicket        = $false
        queue                = @()
        iSupportWrites       = $false
    }

    $tt = Resolve-MetraTicketTrackerModule
    if (-not $tt) {
        $result.warning = 'TicketTracker project or module not present; ticket watch skipped.'
        if (-not $Quiet) {
            Write-Warning $result.warning
        }
        return $result
    }

    $result.available = $true
    try {
        $candidates = Get-MetraTicketWatchCandidates `
            -ModulePath $tt.ModulePath `
            -Top $topN `
            -DoSync $doSync `
            -Scope $scope
    }
    catch {
        $result.warning = "Ticket watch scan skipped: $($_.Exception.Message)"
        if (-not $Quiet) { Write-Warning $result.warning }
        return $result
    }

    $result.synced = [bool]$candidates.Synced
    $result.syncError = [string]$candidates.SyncError
    $result.scanned = [int]$candidates.Scanned
    $scopeWarning = [string](Get-MetraProp -Object $candidates -Name 'ScopeWarning' -Default '')
    if ($scopeWarning) {
        $result.warning = $scopeWarning
        if (-not $Quiet) { Write-Warning $scopeWarning }
    }
    if ($result.syncError -and -not $Quiet) {
        Write-Warning ("TicketTracker sync failed; using local cache. {0}" -f $result.syncError)
    }

    $before = Get-MetraAttentionMemory -MetraRoot $MetraRoot
    $beforeByKey = @{}
    foreach ($item in @($before.items)) {
        if ($item.key) { $beforeByKey[[string]$item.key] = $item }
    }

    $queue = @(
        foreach ($t in @($candidates.Tickets)) {
            ConvertTo-MetraTicketAttentionQueueItem -Ticket $t -TicketTrackerPath $tt.Path
        }
    ) | Where-Object { $null -ne $_ }

    $result.queue = $queue
    # A truncated list is not full coverage - auto-close would kill live tickets past the cap.
    $truncated = [bool](Get-MetraProp -Object $candidates -Name 'Truncated' -Default $false)
    $coveredKinds = if ($truncated) { @() } else { @('ticket') }
    $result.coveredTicket = -not $truncated
    if ($truncated -and -not $Quiet) {
        Write-Warning ("Ticket list capped at {0}; tickets past the cap stay in Attention untouched." -f $topN)
    }

    # Classify change kind per ticket id for M2 analyze / assess trigger (Added/Refreshed vs Unchanged).
    $changeByTicketId = @{}
    foreach ($q in $queue) {
        $key = [string]$q.id
        $ticketId = if ($key -match '^ticket:(.+)$') { $Matches[1] } else { '' }
        if (-not $ticketId) { continue }
        $prev = $beforeByKey[$key]
        if (-not $prev) {
            $result.added++
            $changeByTicketId[$ticketId] = 'added'
            continue
        }
        $prevSig = [string]$prev.evidenceSignature
        $newSig = [string]$q.evidenceSignature
        if ($prevSig -eq $newSig -and [string]$prev.state -eq 'active') {
            $result.unchanged++
            $changeByTicketId[$ticketId] = 'unchanged'
        }
        else {
            $result.refreshed++
            $changeByTicketId[$ticketId] = 'refreshed'
        }
    }

    # Assess (preferred) or analyze: local drafts only. Fail-soft per ticket.
    # E1: optional evidenceRouter after analyze - Next evidence note only (never recommend/iSupport).
    $ticketsById = @{}
    foreach ($t in @($candidates.Tickets)) {
        $nid = [string](Get-MetraProp -Object $t -Name 'Id' -Default '')
        if (-not $nid) { $nid = [string](Get-MetraProp -Object $t -Name 'id' -Default '') }
        if ($nid) { $ticketsById[$nid] = $t }
    }
    $personPriorByCustomer = @{}
    foreach ($t in @($candidates.Tickets)) {
        $cust = [string](Get-MetraProp -Object $t -Name 'Customer' -Default '')
        if (-not $cust) { $cust = [string](Get-MetraProp -Object $t -Name 'customer' -Default '') }
        $custKey = $cust.Trim().ToLowerInvariant()
        if (-not $custKey) { continue }
        if (-not $personPriorByCustomer.ContainsKey($custKey)) { $personPriorByCustomer[$custKey] = 0 }
        $personPriorByCustomer[$custKey]++
    }

    $queueByTicketId = @{}
    foreach ($q in $queue) {
        $key = [string]$q.id
        if ($key -match '^ticket:(.+)$') { $queueByTicketId[$Matches[1]] = $q }
    }

    $assessIds = @(
        foreach ($ticketId in @($changeByTicketId.Keys)) {
            $kind = [string]$changeByTicketId[$ticketId]
            if (Test-MetraTicketWatchShouldAssess -ChangeKind $kind -AutoAssess:$autoAssess `
                    -TicketId $ticketId -AssessMaxAgeHours $assessMaxAgeHours -TicketTrackerPath $tt.Path) {
                $ticketId
            }
        }
    )
    $analyzeIds = @(
        foreach ($ticketId in @($changeByTicketId.Keys)) {
            if ($assessIds -contains $ticketId) { continue }
            $kind = [string]$changeByTicketId[$ticketId]
            if (Test-MetraTicketWatchShouldAnalyze -ChangeKind $kind -ForceDraft:$forceDraft -AutoAnalyze:$autoAnalyze) {
                $ticketId
            }
        }
    )

    if ($assessIds.Count -gt 0 -or $analyzeIds.Count -gt 0) {
        $null = Import-MetraTicketTrackerModule -ModulePath $tt.ModulePath
    }

    foreach ($id in $assessIds) {
        try {
            $assessCmd = Get-Command Invoke-TicketAssess -ErrorAction Stop
            $assessment = & $assessCmd -Id $id -DraftRecommend
            $result.assessmentsWritten++
            $result.draftsWritten++
            if ($queueByTicketId.ContainsKey($id)) {
                $queueByTicketId[$id] = Update-MetraTicketAttentionFromAssess -QueueItem $queueByTicketId[$id] -AssessResult $assessment
            }
        }
        catch {
            if (-not $Quiet) {
                Write-Warning ("Ticket assess skipped for {0}: {1}" -f $id, $_.Exception.Message)
            }
        }
    }

    foreach ($id in $analyzeIds) {
        try {
            $analysis = New-TicketDraftAnalysis -Id $id
            $result.draftsWritten++

            if ($evidenceRouter) {
                try {
                    $ticketObj = $ticketsById[$id]
                    $subject = if ($ticketObj) {
                        [string](Get-MetraProp -Object $ticketObj -Name 'Subject' -Default '')
                    } else { '' }
                    if (-not $subject -and $analysis) {
                        $subject = [string](Get-MetraProp -Object $analysis -Name 'Subject' -Default '')
                    }
                    $desc = ''
                    if ($ticketObj) {
                        $desc = [string](Get-MetraProp -Object $ticketObj -Name 'Description' -Default '')
                    }
                    $customer = ''
                    if ($ticketObj) {
                        $customer = [string](Get-MetraProp -Object $ticketObj -Name 'Customer' -Default '')
                    }
                    $custKey = $customer.Trim().ToLowerInvariant()
                    $personPrior = 0
                    if ($custKey -and $personPriorByCustomer.ContainsKey($custKey)) {
                        $personPrior = [math]::Max(0, ([int]$personPriorByCustomer[$custKey]) - 1)
                    }
                    $similarN = @($analysis.Similar).Count
                    $solutionsN = @($analysis.Solutions).Count
                    $signals = Get-MetraTicketWatchEvidenceSignals `
                        -Subject $subject `
                        -Description $desc `
                        -SimilarCount $similarN `
                        -SolutionsCount $solutionsN `
                        -PersonPriorCount $personPrior `
                        -MailCue:$false `
                        -InstitutionalExhausted:$true
                    $suggestion = Get-MetraTicketWatchEvidenceSuggestion -Signals $signals
                    $noteBody = Format-MetraTicketWatchEvidenceNextNote -Suggestion $suggestion
                    $priorEvidence = Get-MetraTicketWatchLatestNoteText -TicketId $id -Tag 'evidence-next'
                    if ($noteBody.Trim() -ne ([string]$priorEvidence).Trim()) {
                        $null = Add-TrackedTicketNote -Id $id -Text $noteBody -Tags 'evidence-next'
                    }
                    $result.evidenceSuggestions++
                    if (Test-MetraTicketWatchNoteIsRecommendable -NoteText $noteBody) {
                        $result.evidenceRecommendable++
                    }
                }
                catch {
                    if (-not $Quiet) {
                        Write-Warning ("Evidence router skipped for {0}: {1}" -f $id, $_.Exception.Message)
                    }
                }
            }
        }
        catch {
            if (-not $Quiet) {
                Write-Warning ("Ticket analyze skipped for {0}: {1}" -f $id, $_.Exception.Message)
            }
        }
    }

    # Rebuild queue array from stamped map (assess fields) then reconcile Attention.
    $queue = @(
        foreach ($q in $queue) {
            $key = [string]$q.id
            if ($key -match '^ticket:(.+)$' -and $queueByTicketId.ContainsKey($Matches[1])) {
                $queueByTicketId[$Matches[1]]
            }
            else { $q }
        }
    )
    $result.queue = $queue
    $memory = Update-MetraAttentionMemory `
        -Queue $queue `
        -CoveredKinds $coveredKinds `
        -ScanMode 'full' `
        -MetraRoot $MetraRoot
    $result.ok = $true
    $result.nextEvidenceAvailable = ($result.evidenceSuggestions -gt 0)
    $result.readyForRecommendation = ($result.evidenceRecommendable -gt 0)
    $result.draftAvailable = ($result.draftsWritten -gt 0)

    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Metra ticket watch scan'
        Write-Host ''
        if ($result.synced) {
            Write-Host 'Synced TicketTracker.'
        }
        elseif ($doSync) {
            Write-Host 'TicketTracker sync skipped or failed; used local cache.'
        }
        else {
            Write-Host 'Skipped TicketTracker sync (-SkipSync or config).'
        }
        Write-Host ("Scope: {0}." -f $result.scope)
        Write-Host ("Scanned {0} attention-eligible tickets." -f $result.scanned)
        Write-Host 'Attention updated:'
        Write-Host ("  Added: {0}" -f $result.added)
        Write-Host ("  Refreshed: {0}" -f $result.refreshed)
        Write-Host ("  Unchanged: {0}" -f $result.unchanged)
        if ($result.assessmentsWritten -gt 0) {
            Write-Host ("Assess drafts: {0} local assess draft(s)." -f $result.assessmentsWritten)
        }
        elseif ($autoAssess) {
            Write-Host 'No assess drafts written (nothing matched trigger, recent assess skip, or Unchanged).'
        }
        $analyzeDrafts = [math]::Max(0, $result.draftsWritten - $result.assessmentsWritten)
        if ($analyzeDrafts -gt 0) {
            Write-Host ("Analyze drafts: {0} local analyze draft(s)." -f $analyzeDrafts)
        }
        elseif ($forceDraft -or $autoAnalyze) {
            Write-Host 'No analyze drafts written (assess preferred, nothing matched, or Unchanged).'
        }
        if ($result.evidenceSuggestions -gt 0) {
            Write-Host ("Next evidence: {0} suggestion(s)." -f $result.evidenceSuggestions)
            if ($result.evidenceRecommendable -gt 0) {
                Write-Host ("Evidence appears sufficient / Ready for recommendation: {0}." -f $result.evidenceRecommendable)
            }
        }
        elseif ($evidenceRouter -and ($forceDraft -or $autoAnalyze -or $autoAssess)) {
            Write-Host 'No Next evidence notes written (evidenceRouter on; no analyze drafts this scan).'
        }
        Write-Host ''
        Write-Host 'No iSupport writes performed.'
        Write-Host 'Next: open Ops Attention or run .\TicketTracker.ps1 brief <id> / assess <id>'
        Write-Host ''
    }

    return $result
}
