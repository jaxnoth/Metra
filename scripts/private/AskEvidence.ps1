# Ask evidence contract: pack builder, quality rubric, answer semantics helpers.

function Get-MetraAskEvidenceLimits {
    return [ordered]@{
        maxItems        = 6
        maxCharsPerItem = 400
        maxTotalChars   = 2400
    }
}

function Truncate-MetraAskEvidenceText {
    param(
        [AllowEmptyString()][string]$Text,
        [int]$Max = 400
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -le $Max) { return $t }
    if ($Max -le 3) { return $t.Substring(0, $Max) }
    return ($t.Substring(0, $Max - 3) + '...')
}

function New-MetraAskEvidenceItem {
    <#
    .SYNOPSIS
        One bounded evidence item for the Ask context contract.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('project', 'file', 'cmdlet', 'ticket', 'brief', 'journal', 'route', 'image')]
        [string]$Kind,
        [Parameter(Mandatory)][string]$Label,
        [string]$Source = '',
        [AllowEmptyString()][string]$Excerpt = '',
        [ValidateSet('high', 'medium', 'low')][string]$Confidence = 'medium',
        [switch]$FactualSupport
    )

    $limits = Get-MetraAskEvidenceLimits
    return [PSCustomObject]@{
        kind            = $Kind
        label           = Truncate-MetraAskEvidenceText -Text $Label -Max 120
        source          = Truncate-MetraAskEvidenceText -Text $Source -Max 240
        excerpt         = Truncate-MetraAskEvidenceText -Text $Excerpt -Max ([int]$limits.maxCharsPerItem)
        confidence      = $Confidence
        factualSupport  = [bool]$FactualSupport
    }
}

function Get-MetraAskAgentsExcerpt {
    param(
        [Parameter(Mandatory)][string]$AgentsPath,
        [int]$MaxChars = 400
    )

    if (-not (Test-Path -LiteralPath $AgentsPath)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($AgentsPath)
    }
    catch {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    $sections = @()
    foreach ($heading in @('## Start here', '## Route here when', '## Route here', '# Metra agent guide', '# ')) {
        $idx = $raw.IndexOf($heading, [StringComparison]::OrdinalIgnoreCase)
        if ($idx -lt 0) { continue }
        $chunk = $raw.Substring($idx)
        $next = $chunk.IndexOf("`n## ", 3)
        if ($next -gt 0) { $chunk = $chunk.Substring(0, $next) }
        $sections += Truncate-MetraAskEvidenceText -Text $chunk -Max $MaxChars
        if ($sections.Count -ge 2) { break }
    }
    if ($sections.Count -eq 0) {
        return Truncate-MetraAskEvidenceText -Text $raw -Max $MaxChars
    }
    return ($sections -join "`n")
}

function Get-MetraAskCliSurfacesFromAgents {
    param([string]$AgentsText)

    if ([string]::IsNullOrWhiteSpace($AgentsText)) { return @() }
    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($AgentsText, '(?m)^\s{0,3}(?:-\s+)?`([^`\r\n]{3,80})`')) {
        $cmd = [string]$m.Groups[1].Value.Trim()
        if ($cmd -match '(?i)^(Import-Module|Get-|Set-|Start-|Stop-|Invoke-|Test-|Find-|Clear-|.\w+\.ps1|python |cd )') {
            if (-not $hits.Contains($cmd)) { $hits.Add($cmd) }
        }
        if ($hits.Count -ge 4) { break }
    }
    return @($hits)
}

function Test-MetraAskLiveSystemIntent {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Prompt)

    $q = $Prompt.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) { return $false }
    return [bool]($q -match '(?i)\b(right now|currently|is .+ (down|up|outage|broken|working)|showing an outage|live status|are .+ (healthy|failing))\b')
}

function Find-MetraAskTicketIdInPrompt {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Prompt)

    $m = [regex]::Match($Prompt, '\b(\d{6,8})\b')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-MetraAskEvidenceQuality {
    <#
    .SYNOPSIS
        Deterministic evidence quality: adequate | thin | none.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Handoff,
        [object[]]$Items = @(),
        [switch]$LiveSystemWithoutToolEvidence
    )

    $where = [string](Get-MetraProp -Object $Handoff -Name 'where' -Default '')
    $score = [int](Get-MetraProp -Object $Handoff -Name 'score' -Default 0)
    $home = Get-MetraHomeDestinationName
    $hasRoute = -not [string]::IsNullOrWhiteSpace($where)

    $factual = @(
        $Items | Where-Object {
            $k = [string](Get-MetraProp -Object $_ -Name 'kind' -Default '')
            $fs = [bool](Get-MetraProp -Object $_ -Name 'factualSupport' -Default $false)
            ($k -ne 'journal') -and ($fs -or $k -in @('file', 'project', 'cmdlet', 'ticket', 'brief'))
        }
    )
    $nonJournal = @($Items | Where-Object { [string](Get-MetraProp -Object $_ -Name 'kind' -Default '') -ne 'journal' })

    if (-not $hasRoute) { return 'none' }
    if ($LiveSystemWithoutToolEvidence) {
        if ($nonJournal.Count -eq 0) { return 'none' }
        return 'thin'
    }
    if ($factual.Count -gt 0 -and ($score -ge 2 -or $where -eq $home)) {
        # Named supporting item + usable route -> adequate (Metra home score may be low).
        $strong = @(
            $factual | Where-Object {
                $k = [string](Get-MetraProp -Object $_ -Name 'kind' -Default '')
                $c = [string](Get-MetraProp -Object $_ -Name 'confidence' -Default '')
                $k -in @('file', 'project', 'ticket', 'brief') -or $c -eq 'high'
            }
        )
        if ($strong.Count -gt 0) { return 'adequate' }
    }
    if ($nonJournal.Count -gt 0 -or $hasRoute) {
        if ($factual.Count -eq 0 -and $score -lt 1 -and $where -ne $home) { return 'none' }
        return 'thin'
    }
    return 'none'
}

function New-MetraAskEvidencePack {
    <#
    .SYNOPSIS
        Build bounded Ask evidence items + quality for a routed handoff.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)]$Handoff,
        $Continuity,
        $Capability,
        [object[]]$Images = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $limits = Get-MetraAskEvidenceLimits
    $items = [System.Collections.Generic.List[object]]::new()
    $where = [string](Get-MetraProp -Object $Handoff -Name 'where' -Default '')
    $home = Get-MetraHomeDestinationName
    $cwd = Get-MetraAskRouteCwd -Where $where -MetraRoot $MetraRoot

    # 0) Image vision-read evidence (observations only - never factualSupport for live status)
    foreach ($img in @($Images)) {
        if ($null -eq $img) { continue }
        $label = [string](Get-MetraProp -Object $img -Name 'fileName' -Default '')
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = [string](Get-MetraProp -Object $img -Name 'id' -Default 'image')
        }
        $items.Add((New-MetraAskEvidenceItem -Kind 'image' -Label $label -Source 'place-quarantine' `
                -Excerpt 'Image attached for vision read' -Confidence 'medium'))
        if ($items.Count -ge [int]$limits.maxItems) { break }
    }

    # 1) Project / home metadata
    $purpose = [string](Get-MetraProp -Object $Handoff -Name 'what' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($where)) {
        $regPurpose = ''
        try {
            $reg = Get-MetraProjectRegistry
            $row = @($reg.projects | Where-Object { [string]$_.name -eq $where } | Select-Object -First 1)
            if ($row) {
                $regPurpose = [string](Get-MetraProp -Object $row -Name 'purpose' -Default '')
            }
        }
        catch { }
        $meta = if ($regPurpose) { $regPurpose } else { $purpose }
        if ($meta) {
            $items.Add((New-MetraAskEvidenceItem -Kind 'project' -Label "$where purpose" -Source $where `
                    -Excerpt $meta -Confidence 'high' -FactualSupport))
        }
    }

    # 2-3) AGENTS.md Start here / Route here + CLI surfaces
    $agentsPath = Join-Path $cwd 'AGENTS.md'
    $agentsText = Get-MetraAskAgentsExcerpt -AgentsPath $agentsPath -MaxChars ([int]$limits.maxCharsPerItem)
    if ($agentsText) {
        $items.Add((New-MetraAskEvidenceItem -Kind 'file' -Label 'AGENTS.md Start here / Route here' `
                -Source $agentsPath -Excerpt $agentsText -Confidence 'high' -FactualSupport))
        foreach ($cli in @(Get-MetraAskCliSurfacesFromAgents -AgentsText $agentsText)) {
            $items.Add((New-MetraAskEvidenceItem -Kind 'cmdlet' -Label 'AGENTS CLI surface' `
                    -Source $agentsPath -Excerpt $cli -Confidence 'medium' -FactualSupport))
            if ($items.Count -ge ([int]$limits.maxItems - 2)) { break }
        }
    }

    # 4) Ticket id only - bounded label, never full brief body
    $ticketId = Find-MetraAskTicketIdInPrompt -Prompt $Prompt
    if ($ticketId) {
        $items.Add((New-MetraAskEvidenceItem -Kind 'ticket' -Label "Ticket id $ticketId" `
                -Source 'prompt' -Excerpt "Ticket id $ticketId detected in Ask prompt. Use TicketTracker brief $ticketId for details - Ask does not embed full brief bodies." `
                -Confidence 'medium' -FactualSupport))
    }

    # 5) Journal continuity (not factual support)
    if ($Continuity) {
        $sum = [string](Get-MetraProp -Object $Continuity -Name 'sessionSummary' -Default '')
        $recent = @(Get-MetraProp -Object $Continuity -Name 'recentTurns' -Default @())
        if ($sum) {
            $items.Add((New-MetraAskEvidenceItem -Kind 'journal' -Label 'Session Journal summary' `
                    -Source 'continuity' -Excerpt $sum -Confidence 'low'))
        }
        elseif ($recent.Count -gt 0) {
            $snip = Truncate-MetraAskEvidenceText -Text ([string](Get-MetraProp -Object $recent[-1] -Name 'prompt' -Default '')) -Max 200
            if ($snip) {
                $items.Add((New-MetraAskEvidenceItem -Kind 'journal' -Label 'Recent Ask turn' `
                        -Source 'continuity' -Excerpt $snip -Confidence 'low'))
            }
        }
    }

    # 6) Fallback route labels
    if ($items.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($where)) {
        $items.Add((New-MetraAskEvidenceItem -Kind 'route' -Label "Routed home $where" `
                -Source 'handoff' -Excerpt ([string](Get-MetraProp -Object $Handoff -Name 'next' -Default "Stay in $where.")) `
                -Confidence 'low'))
    }

    # Enforce item count + total chars
    $bounded = [System.Collections.Generic.List[object]]::new()
    $total = 0
    foreach ($it in $items) {
        if ($bounded.Count -ge [int]$limits.maxItems) { break }
        $exLen = ([string](Get-MetraProp -Object $it -Name 'excerpt' -Default '')).Length
        if (($total + $exLen) -gt [int]$limits.maxTotalChars -and $bounded.Count -gt 0) { break }
        $bounded.Add($it)
        $total += $exLen
    }

    $liveIntent = Test-MetraAskLiveSystemIntent -Prompt $Prompt
    # AGENTS cmdlet labels are documentation, not live tool results. Only ticket/brief
    # counts as tool-bound evidence for live-status asks in this harness.
    $hasLiveToolEvidence = @($bounded | Where-Object {
            $k = [string](Get-MetraProp -Object $_ -Name 'kind' -Default '')
            $k -in @('ticket', 'brief') -and [bool](Get-MetraProp -Object $_ -Name 'factualSupport' -Default $false)
        }).Count -gt 0
    # Live-status asks without tool-bound evidence cannot be adequate.
    $liveCap = $liveIntent -and -not $hasLiveToolEvidence

    $quality = Get-MetraAskEvidenceQuality -Handoff $Handoff -Items @($bounded) -LiveSystemWithoutToolEvidence:$liveCap

    $capStatus = 'normal'
    $capReason = $null
    if ($Capability) {
        if (-not [bool](Get-MetraProp -Object $Capability -Name 'available' -Default $false)) {
            $capStatus = 'degraded'
            $capReason = [string](Get-MetraProp -Object $Capability -Name 'reason' -Default 'engine_unavailable')
        }
        elseif (-not [bool](Get-MetraProp -Object $Capability -Name 'selected' -Default $true)) {
            $capStatus = 'unsupported'
            $capReason = 'engine_not_selected'
        }
    }

    $hasJournal = $false
    if ($Continuity) {
        $hasJournal = [bool](Get-MetraProp -Object $Continuity -Name 'sessionSummary' -Default $null) `
            -or (@(Get-MetraProp -Object $Continuity -Name 'recentTurns' -Default @()).Count -gt 0)
    }

    $routeObj = [ordered]@{
        where   = $where
        what    = [string](Get-MetraProp -Object $Handoff -Name 'what' -Default '')
        why     = @(Get-MetraProp -Object $Handoff -Name 'why' -Default @())
        forWhom = @(Get-MetraProp -Object $Handoff -Name 'forWhom' -Default @())
        next    = [string](Get-MetraProp -Object $Handoff -Name 'next' -Default '')
        score   = [int](Get-MetraProp -Object $Handoff -Name 'score' -Default 0)
    }

    $evidence = [ordered]@{
        quality = $quality
        items   = $bounded
        limits  = [hashtable]$limits
    }

    $contBag = [ordered]@{
        sessionSummary    = $(if ($Continuity) { Get-MetraProp -Object $Continuity -Name 'sessionSummary' -Default $null } else { $null })
        hasJournalContext = $hasJournal
        recentTurns       = $(if ($Continuity) {
                $rt = [System.Collections.Generic.List[object]]::new()
                foreach ($t in @(Get-MetraProp -Object $Continuity -Name 'recentTurns' -Default @())) { [void]$rt.Add($t) }
                $rt
            } else { [System.Collections.Generic.List[object]]::new() })
        recallSummary     = $(if ($Continuity) { Get-MetraProp -Object $Continuity -Name 'recallSummary' -Default $null } else { $null })
        recallSessionId   = $(if ($Continuity) { Get-MetraProp -Object $Continuity -Name 'recallSessionId' -Default $null } else { $null })
    }

    $capBag = [ordered]@{
        status = $capStatus
        reason = $capReason
    }

    # Flat aliases for sidecar cutover. Keep List[object] for items so a single
    # evidence row survives hashtable assignment (object[] collapses to one object).
    $context = [ordered]@{
        route      = [hashtable]$routeObj
        evidence   = [hashtable]$evidence
        continuity = [hashtable]$contBag
        capability = [hashtable]$capBag
        where      = $routeObj.where
        what       = $routeObj.what
        why        = @($routeObj.why)
        forWhom    = @($routeObj.forWhom)
        next       = $routeObj.next
        score      = $routeObj.score
    }
    if ($contBag.sessionSummary) { $context['sessionSummary'] = [string]$contBag.sessionSummary }
    $recentForFlat = @(Get-MetraProp -Object $contBag -Name 'recentTurns' -Default @())
    if ($recentForFlat.Count -gt 0) {
        $rtFlat = [System.Collections.Generic.List[object]]::new()
        foreach ($t in $recentForFlat) { [void]$rtFlat.Add($t) }
        $context['recentTurns'] = $rtFlat
    }
    if ($contBag.recallSummary) {
        $context['recall'] = [string]$contBag.recallSummary
        $context['recallSessionId'] = [string]$contBag.recallSessionId
        $context['forceContinuity'] = $true
    }
    elseif ($hasJournal -and $Continuity -and [bool](Get-MetraProp -Object $Continuity -Name 'usedSummarization' -Default $false)) {
        $context['forceContinuity'] = $true
    }

    return [PSCustomObject]@{
        context          = [hashtable]$context
        quality          = $quality
        items            = @($bounded)
        limits           = [hashtable]$limits
        liveSystemIntent = $liveIntent
    }
}

function New-MetraAskNoneEvidenceReply {
    return 'I do not have enough routed evidence to answer that safely. Next check: open the routed home or attach a specific source so I can ground the answer instead of guessing.'
}

function New-MetraAskThinEvidencePrefix {
    return 'I only have thin routed evidence for this. Treat the following as provisional and verify against the routed source before relying on it.'
}

function Resolve-MetraAskAnswerSemantics {
    <#
    .SYNOPSIS
        Map evidence quality + capability path to answerType / answered / nextStep.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('adequate', 'thin', 'none')][string]$EvidenceQuality,
        [ValidateSet('grounded', 'provisional', 'refusal', 'degraded', 'greeting', 'observation', 'park')]
        [string]$PreferredType = 'provisional',
        [string]$NextStep = '',
        [switch]$EngineUnavailable,
        [switch]$SecretsRefuse,
        [switch]$HonestyShortCircuit,
        [string]$HonestyKind
    )

    if ($HonestyShortCircuit) {
        $kind = if ($HonestyKind) { $HonestyKind } else { 'greeting' }
        return [PSCustomObject]@{
            answered         = $true
            answerType       = $kind
            evidenceQuality  = 'none'
            nextStep         = $NextStep
        }
    }
    if ($SecretsRefuse) {
        return [PSCustomObject]@{
            answered         = $false
            answerType       = 'refusal'
            evidenceQuality  = $EvidenceQuality
            nextStep         = $(if ($NextStep) { $NextStep } else { 'Rephrase without private-key material.' })
        }
    }
    if ($EngineUnavailable) {
        return [PSCustomObject]@{
            answered         = $false
            answerType       = 'degraded'
            evidenceQuality  = $EvidenceQuality
            nextStep         = $(if ($NextStep) { $NextStep } else { 'Restore the Ask engine, then retry.' })
        }
    }

    switch ($EvidenceQuality) {
        'none' {
            return [PSCustomObject]@{
                answered         = $false
                answerType       = 'provisional'
                evidenceQuality  = 'none'
                nextStep         = $(if ($NextStep) { $NextStep } else { 'Open the routed home or attach a specific source.' })
            }
        }
        'thin' {
            return [PSCustomObject]@{
                answered         = $false
                answerType       = 'provisional'
                evidenceQuality  = 'thin'
                nextStep         = $(if ($NextStep) { $NextStep } else { 'Review the routed AGENTS.md or project metadata before treating this as grounded.' })
            }
        }
        default {
            # adequate - may be grounded only when PreferredType says so
            $type = if ($PreferredType -eq 'grounded') { 'grounded' } else { $PreferredType }
            if ($type -notin @('grounded', 'provisional', 'refusal', 'degraded')) { $type = 'grounded' }
            return [PSCustomObject]@{
                answered         = ($type -eq 'grounded')
                answerType       = $type
                evidenceQuality  = 'adequate'
                nextStep         = $NextStep
            }
        }
    }
}
