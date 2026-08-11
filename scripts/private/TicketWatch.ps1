function Get-MetraTicketTrackerProject {
    <#
    .SYNOPSIS
        Resolves the TicketTracker companion path from the Metra registry (present on disk).
    #>
    [CmdletBinding()]
    param()

    $proj = @(Get-MetraProject -Name TicketTracker | Select-Object -First 1)
    if ($proj.Count -eq 0) { return $null }
    $path = [string]$proj[0].Path
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
    $module = Join-Path $path 'src\TicketTracker.psm1'
    if (-not (Test-Path -LiteralPath $module)) { return $null }
    return [PSCustomObject]@{
        Name       = 'TicketTracker'
        Path       = $path
        ModulePath = $module
    }
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
    # evidenceRouter: opt-in E1; after local analyze draft - Next evidence only (never recommend).
    # autoStoreRecommend: M3 Affirm A auto-write - stays false through Mine quality loop (revisit after M4).
    $defaults = [PSCustomObject]@{
        writeLocalDraft     = $false
        autoAnalyze         = $false
        evidenceRouter      = $false
        autoStoreRecommend  = $false
        top                 = 0
        syncOnScan          = $true
        syncOnSnapshot      = $false   # legacy; portfolio snapshot no longer runs ticket intake
        scope               = 'mine'
    }
    $cfgPath = Join-Path $MetraRoot 'docs\ticket-watch.local.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return $defaults }
    try {
        $raw = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -ne (Get-MetraProp -Object $raw -Name 'writeLocalDraft' -Default $null)) {
            $defaults.writeLocalDraft = [bool]$raw.writeLocalDraft
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'autoAnalyze' -Default $null)) {
            $defaults.autoAnalyze = [bool]$raw.autoAnalyze
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'evidenceRouter' -Default $null)) {
            $defaults.evidenceRouter = [bool]$raw.evidenceRouter
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'autoStoreRecommend' -Default $null)) {
            # Config may set true, but Mine policy keeps default false; still honor explicit true for later M4 experiments.
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

function Get-MetraTicketWatchProductCueList {
    <#
    .SYNOPSIS
        Known product/process tokens for ephemeral E1 product-cue detection (not a score ledger).
    #>
    @(
        'colleague', 'ellucian', 'webadvisor', 'wagc', 'wafm', 'prqm', 'edqm', 'unidata',
        'jitterbit', 'harmony', 'plansource', 'acadeum', 'folio', 'slate',
        'brightspace', 'd2l', 'pharos', 'thrive', 'orion', 'solarwinds',
        'powerbi', 'power bi', 'pbi', 'ssrs', 'openemr', 'm365', 'outlook', 'teams'
    )
}

function Get-MetraTicketWatchSubjectTokens {
    [CmdletBinding()]
    param([string]$Text = '')

    $parts = [regex]::Split(([string]$Text).ToLowerInvariant(), '[^a-z0-9]+') |
        Where-Object { $_ -and $_.Length -ge 3 } |
        Where-Object {
            $_ -notin @(
                'the', 'and', 'for', 'with', 'from', 'this', 'that', 'have', 'were', 'was',
                'are', 'you', 'your', 'not', 'can', 'unable', 'issue', 'help', 'please', 'need'
            )
        }
    return @($parts | Select-Object -Unique)
}

function Test-MetraTicketWatchHasProductCue {
    [CmdletBinding()]
    param(
        [string]$Subject = '',
        [string]$Description = ''
    )

    $blob = ('{0} {1}' -f $Subject, $Description).ToLowerInvariant()
    if (-not $blob.Trim()) { return $false }
    foreach ($cue in @(Get-MetraTicketWatchProductCueList)) {
        if ($blob.Contains($cue)) { return $true }
    }
    return $false
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
            operatorHint   = 'Evidence appears sufficient. Ready for recommendation (M3 store-as-review) - E1 does not write recommend.'
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
            operatorHint   = 'Run the suggested query yourself if useful. E1 does not fetch or scrape.'
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
    $lines += 'E1 suggests next evidence source only - not a recommendation and does not propose a solution.'
    return ($lines -join "`n")
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
        Mine-eligible only. Gates on E1 recommendable unless -Force.
        Preview never writes iSupport. Confirm supersedes single Metra AI Recommendation section.
        Affirm B (resolve/close) is never called.
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
        autoStoreRecommend = [bool]$cfg.autoStoreRecommend
    }

    $tt = Get-MetraTicketTrackerProject
    if (-not $tt) {
        $result.warning = 'TicketTracker project or module not present.'
        return $result
    }

    Import-Module $tt.ModulePath -Force
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

    $evidenceNote = Get-MetraTicketWatchLatestNoteText -TicketId $canonicalId -Tag 'evidence-next'
    $analyzeNote = Get-MetraTicketWatchLatestNoteText -TicketId $canonicalId -Tag 'analyze-draft'
    $isRecommendable = Test-MetraTicketWatchNoteIsRecommendable -NoteText $evidenceNote
    $result.recommendable = $isRecommendable

    if (-not $isRecommendable -and -not $Force) {
        $result.warning = 'E1 draftState is not recommendable. Gather evidence or use -Force to override.'
        return $result
    }

    $similarLines = @()
    $solutionLines = @()
    $evidenceHint = ''
    if ($analyzeNote) {
        if ($analyzeNote -match '(?s)Similar \(local cache\):\s*(.*?)\s*Solutions index hits:') {
            $similarLines = @($Matches[1] -split "`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ })
        }
        if ($analyzeNote -match '(?s)Solutions index hits:\s*(.*)$') {
            $solutionLines = @($Matches[1] -split "`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ })
        }
    }
    if ($evidenceNote -match '(?im)^\s*Action:\s*(\S+)') {
        $evidenceHint = $Matches[1]
    }

    $simCount = @($similarLines | Where-Object { $_ -match '^\s*-\s+' -and $_ -notmatch '(?i)\(none' }).Count
    $solCount = @($solutionLines | Where-Object { $_ -match '^\s*-\s+' -and $_ -notmatch '(?i)\(no solutions' }).Count
    $basis = New-MetraTicketWatchRecommendBasis `
        -SimilarCount $simCount `
        -SolutionsCount $solCount `
        -MailEvidence:($evidenceHint -eq 'm365Mail') `
        -WebSuggested:($evidenceHint -eq 'boundedWeb')

    $subject = [string](Get-MetraProp -Object $ticketObj -Name 'Subject' -Default '')
    $body = New-MetraTicketWatchRecommendBody `
        -Subject $subject `
        -SimilarLines $similarLines `
        -SolutionLines $solutionLines `
        -EvidenceHint $evidenceHint `
        -Basis $basis
    $result.body = $body

    if ($Preview) {
        $noteBody = Format-MetraTicketWatchRecommendDraftNote -Body $body -Basis $basis
        try {
            $note = Add-TrackedTicketNote -Id $canonicalId -Text $noteBody -Tags 'recommend-draft'
            $result.noteId = [string]$note.Id
            $result.ok = $true
            if (-not $Quiet) {
                Write-Host ''
                Write-Host 'M3 Preview: local recommend-draft written (no iSupport write).'
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
            Write-Host 'M3 Affirm A: Recommendation written (store-as-review). Re-run supersedes the same section.'
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

function New-MetraTicketAttentionEvidenceSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [string]$Updated = '',
        [string]$Status = ''
    )

    return ('ticket:{0}|updated:{1}|status:{2}' -f $TicketId.Trim(), ([string]$Updated).Trim(), ([string]$Status).Trim())
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

function Get-MetraTicketAttentionStatusRank {
    <#
    .SYNOPSIS
        Lower number = higher Attention priority. Waiting on Customer sorts below Open work.
    #>
    [CmdletBinding()]
    param([string]$Status = '')

    $s = ([string]$Status).Trim()
    if (-not $s) { return 1 }
    # Ball in operator court - surface first.
    if ($s -match '(?i)^open\b') { return 0 }
    if ($s -match '(?i)^update from\b') { return 0 }
    if ($s -match '(?i)^(in\s*progress|assigned|new|active)\b') { return 5 }
    # Ball with customer / parked - keep in queue but below Open work.
    if ($s -match '(?i)^waiting\b') { return 40 }
    if ($s -match '(?i)^(pending|on\s*hold)\b') { return 30 }
    return 20
}

function Get-MetraAttentionItemStatusRank {
    [CmdletBinding()]
    param($Item)

    if ([string]$Item.kind -ne 'ticket') { return 0 }
    $explicit = Get-MetraProp -Object $Item -Name 'statusRank' -Default $null
    if ($null -ne $explicit -and "$explicit" -ne '') {
        try { return [int]$explicit } catch { }
    }
    $status = [string](Get-MetraProp -Object $Item -Name 'ticketStatus' -Default '')
    if (-not $status) {
        $detail = [string](Get-MetraProp -Object $Item -Name 'detail' -Default '')
        if ($detail -match '(?i)^(Waiting on Customer|Open|In Progress|Pending|On Hold)') {
            $status = $Matches[1]
        }
        elseif ([string]$Item.evidenceSignature -match '(?i)\|status:([^|]+)') {
            $status = $Matches[1].Trim()
        }
    }
    return (Get-MetraTicketAttentionStatusRank -Status $status)
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

    return [PSCustomObject]@{
        id                = "ticket:$id"
        project           = 'TicketTracker'
        kind              = 'ticket'
        content           = $content
        detail            = ($detailParts -join ' - ')
        ticketStatus      = $status
        statusRank        = (Get-MetraTicketAttentionStatusRank -Status $status)
        command           = ".\TicketTracker.ps1 brief $id"
        source            = 'TicketTracker'
        evidenceSignature = (New-MetraTicketAttentionEvidenceSignature -TicketId $id -Updated $updated -Status $status)
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
    if ($hasSubject -and $detail) { return $MemItem }

    $tt = Get-MetraTicketTrackerProject
    if (-not $tt) { return $MemItem }

    try {
        Import-Module $tt.ModulePath -Force
        $getTickets = Get-Command Get-TrackedTickets -ErrorAction Stop
        $ticket = @(& $getTickets -Id $id | Select-Object -First 1)
        if ($ticket.Count -eq 0) { return $MemItem }
        $qi = ConvertTo-MetraTicketAttentionQueueItem -Ticket $ticket[0] -TicketTrackerPath $tt.Path
        if (-not $qi) { return $MemItem }
        $MemItem.content = [string]$qi.content
        if ($MemItem.PSObject.Properties['detail']) { $MemItem.detail = [string]$qi.detail }
        else { $MemItem | Add-Member -NotePropertyName detail -NotePropertyValue ([string]$qi.detail) -Force }
        $ticketStatus = [string](Get-MetraProp -Object $qi -Name 'ticketStatus' -Default '')
        $statusRank = Get-MetraProp -Object $qi -Name 'statusRank' -Default $null
        if ($MemItem.PSObject.Properties['ticketStatus']) { $MemItem.ticketStatus = $ticketStatus }
        else { $MemItem | Add-Member -NotePropertyName ticketStatus -NotePropertyValue $ticketStatus -Force }
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

    Import-Module $ModulePath -Force
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
        draftAvailable       = $false
        evidenceSuggestions  = 0
        evidenceRecommendable = 0
        nextEvidenceAvailable = $false
        readyForRecommendation = $false
        autoAnalyze          = $autoAnalyze
        evidenceRouter       = $evidenceRouter
        forceDraft           = $forceDraft
        coveredTicket        = $false
        queue                = @()
        iSupportWrites       = $false
    }

    $tt = Get-MetraTicketTrackerProject
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
    $memory = Update-MetraAttentionMemory `
        -Queue $queue `
        -CoveredKinds $coveredKinds `
        -ScanMode 'full' `
        -MetraRoot $MetraRoot
    $result.coveredTicket = -not $truncated
    $result.ok = $true
    if ($truncated -and -not $Quiet) {
        Write-Warning ("Ticket list capped at {0}; tickets past the cap stay in Attention untouched." -f $topN)
    }

    # Classify change kind per ticket id for M2 analyze trigger (Added/Refreshed vs Unchanged).
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

    # M2: TT New-TicketDraftAnalysis -> local analyze-draft note only. Fail-soft per ticket.
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

    $analyzeIds = @(
        foreach ($ticketId in @($changeByTicketId.Keys)) {
            $kind = [string]$changeByTicketId[$ticketId]
            if (Test-MetraTicketWatchShouldAnalyze -ChangeKind $kind -ForceDraft:$forceDraft -AutoAnalyze:$autoAnalyze) {
                $ticketId
            }
        }
    )
    if ($analyzeIds.Count -gt 0) {
        Import-Module $tt.ModulePath -Force
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
                        $null = Add-TrackedTicketNote -Id $id -Text $noteBody -Tags 'evidence-next'
                        $result.evidenceSuggestions++
                        if ([string]$suggestion.draftState -eq 'recommendable') {
                            $result.evidenceRecommendable++
                        }
                    }
                    catch {
                        if (-not $Quiet) {
                            Write-Warning ("Next evidence suggestion failed for {0}: {1}" -f $id, $_.Exception.Message)
                        }
                    }
                }
            }
            catch {
                if (-not $Quiet) {
                    Write-Warning ("Local analyze draft failed for {0}: {1}" -f $id, $_.Exception.Message)
                }
            }
        }
    }
    $result.draftAvailable = $result.draftsWritten -gt 0
    $result.nextEvidenceAvailable = $result.evidenceSuggestions -gt 0
    $result.readyForRecommendation = $result.evidenceRecommendable -gt 0

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
        if ($result.draftsWritten -gt 0) {
            Write-Host ("Draft available: {0} local analyze draft(s)." -f $result.draftsWritten)
        }
        elseif ($forceDraft -or $autoAnalyze) {
            Write-Host 'No analyze drafts written (nothing matched trigger, or all Unchanged).'
        }
        if ($result.evidenceSuggestions -gt 0) {
            Write-Host ("Next evidence: {0} suggestion(s)." -f $result.evidenceSuggestions)
            if ($result.evidenceRecommendable -gt 0) {
                Write-Host ("Evidence appears sufficient / Ready for recommendation: {0}." -f $result.evidenceRecommendable)
            }
        }
        elseif ($evidenceRouter -and ($forceDraft -or $autoAnalyze)) {
            Write-Host 'No Next evidence notes written (evidenceRouter on; no analyze drafts this scan).'
        }
        Write-Host ''
        Write-Host 'No iSupport writes performed.'
        Write-Host 'Next: open Ops Attention or run .\TicketTracker.ps1 brief <id>'
        Write-Host ''
    }

    return $result
}
