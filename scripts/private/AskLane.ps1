# Chat lane classifier: intent vs route, responseObjective, voice schema.
# Phase 1 - classify + fixtures only; Get-MetraDeskAskResult wire is Phase 2.

Set-StrictMode -Version Latest

# Named thresholds (fixtures assert against these - no buried magic numbers).
$script:MetraAskRouteConfidentScore = 2
$script:MetraAskIntentHigh = 0.80
$script:MetraAskRouteNoneMax = 0

function Get-MetraAskLaneThresholds {
    <#
    .SYNOPSIS
        Named classifier thresholds for Chat lane (integer routeScore; float intent).
    #>
    [CmdletBinding()]
    param()

    return [ordered]@{
        RouteConfidentScore = [int]$script:MetraAskRouteConfidentScore
        IntentHigh          = [double]$script:MetraAskIntentHigh
        RouteNoneMax        = [int]$script:MetraAskRouteNoneMax
    }
}

function Get-MetraChatLaneSystemPrompt {
    <#
    .SYNOPSIS
        Load engines/chat-lane/system.md (secretary posture for Chat lane).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Join-Path $MetraRoot 'engines\chat-lane\system.md'
    if (-not (Test-Path -LiteralPath $path)) {
        return 'You are Metra Chat lane: brief, human, no ticket ids or invented system state.'
    }
    try {
        return [System.IO.File]::ReadAllText($path).Trim()
    }
    catch {
        return 'You are Metra Chat lane: brief, human, no ticket ids or invented system state.'
    }
}

function New-MetraAskChatLaneTemplateMessage {
    <#
    .SYNOPSIS
        Deterministic Chat lane replies (fixtures / engine-unavailable fallback).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string]$ResponseObjective,
        [AllowEmptyString()][string]$Prompt = ''
    )

    switch ($Reason) {
        'authority_requires_confirm' {
            return 'I can draft that for you, but I will not close, post, or resolve anything from here - confirm at the desk when you are ready.'
        }
        'sparse_intake_clarify' {
            return 'I need a bit more to help. Could you send a screenshot of the error and what you were doing when it happened?'
        }
        'capture_intent' {
            return 'Got it - I will hold that for later. Use Save for portfolio when you want it preserved.'
        }
        'adequate_route_thin_evidence' {
            return 'I can see where this belongs, but the details are thin. Tell me what you noticed in plain terms, or Save for portfolio so the desk can pick it up.'
        }
        'high_intent_no_route' {
            return 'I am with you. Share a bit more, or Save for portfolio if you want this parked for later.'
        }
        'social_greeting' {
            return "Hey. I'm here at the Ask desk; what do you want to work through?"
        }
        'personal_observation' {
            return 'I do not have personal observations bound. Ask about portfolio work, or use Save for portfolio for durable notes.'
        }
        default {
            if ($ResponseObjective -eq 'Clarify') {
                return 'I need one clearer detail before I can help - what were you trying to do when it went wrong?'
            }
            if ($ResponseObjective -eq 'OperatorConfirm') {
                return 'Noted - Host writes need your confirm. I will not execute that from Ask.'
            }
            return 'Got it. Say more when you are ready, or Save for portfolio to keep this.'
        }
    }
}

function Merge-MetraAskLaneIntoResult {
    <#
    .SYNOPSIS
        Attach lane contract fields onto a Get-MetraDeskAskResult object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)]$Lane
    )

    if (-not $Result -or -not $Lane) { return $Result }

    $props = [ordered]@{
        lane              = [string](Get-MetraProp -Object $Lane -Name 'lane' -Default '')
        reason            = [string](Get-MetraProp -Object $Lane -Name 'reason' -Default '')
        responseObjective = [string](Get-MetraProp -Object $Lane -Name 'responseObjective' -Default '')
        intentConfidence  = [double](Get-MetraProp -Object $Lane -Name 'intentConfidence' -Default 0)
        routeScore        = [int](Get-MetraProp -Object $Lane -Name 'routeScore' -Default 0)
        turnMode          = [string](Get-MetraProp -Object $Lane -Name 'turnMode' -Default '')
    }

    $hash = [ordered]@{}
    foreach ($p in $Result.PSObject.Properties) {
        $hash[$p.Name] = $p.Value
    }
    foreach ($k in $props.Keys) { $hash[$k] = $props[$k] }

    # Stamp handoff for showWhere / journal consumers
    $h = Get-MetraProp -Object $Result -Name 'handoff' -Default $null
    if ($h) {
        $hHash = [ordered]@{}
        foreach ($p in $h.PSObject.Properties) { $hHash[$p.Name] = $p.Value }
        $hHash['lane'] = $props.lane
        $hHash['chatLaneReason'] = $props.reason
        $hHash['responseObjective'] = $props.responseObjective
        $hash['handoff'] = [PSCustomObject]$hHash
    }

    return [PSCustomObject]$hash
}

function New-MetraAskChatLaneResult {
    <#
    .SYNOPSIS
        Full Ask result for Chat lane turns (human-first; never grounded).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)]$Handoff,
        [Parameter(Mandatory)]$Lane,
        $Continuity,
        [string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$SuggestCapture
    )

    $reason = [string](Get-MetraProp -Object $Lane -Name 'reason' -Default '')
    $objective = [string](Get-MetraProp -Object $Lane -Name 'responseObjective' -Default 'Capture')
    $answerType = [string](Get-MetraProp -Object $Lane -Name 'answerType' -Default 'capture_ack')
    $msg = New-MetraAskChatLaneTemplateMessage -Reason $reason -ResponseObjective $objective -Prompt $Prompt

    $suggest = [bool]$SuggestCapture
    if ($reason -eq 'capture_intent' -or $objective -eq 'Capture') { $suggest = $true }

    $voice = New-MetraVoiceResponse -Spoken $msg -Display $msg -Durable $msg

    $result = [PSCustomObject]@{
        handoff          = $Handoff
        message          = $msg
        sessionId        = $(if (-not [string]::IsNullOrWhiteSpace($SessionId)) { $SessionId.Trim() } else { $null })
        capability       = $null
        engine           = $null
        model            = $null
        answered         = $true
        answerType       = $answerType
        evidenceQuality  = [string](Get-MetraProp -Object $Lane -Name 'evidenceQuality' -Default 'none')
        nextStep         = $(
            if ($objective -eq 'OperatorConfirm') { 'Confirm any Host write at the desk (recommend/post/resolve).' }
            elseif ($objective -eq 'Clarify') { 'Answer the clarifying question, or Save for portfolio.' }
            else { 'Save for portfolio or continue in plain language.' }
        )
        continuity       = $Continuity
        secretsScrubbed  = $false
        secretsNotice    = $null
        secretsKinds     = @()
        secretsReason    = $null
        scrubbedPrompt   = $Prompt
        suggestCapture   = $suggest
        images           = @()
        voice            = $voice
        chatLanePrompt   = (Get-MetraChatLaneSystemPrompt -MetraRoot $MetraRoot)
    }

    return Merge-MetraAskLaneIntoResult -Result $result -Lane $Lane
}

function Test-MetraAskOpsStatusIntent {
    <#
    .SYNOPSIS
        Metra/Ops desk health questions - answer from capability probes, not Chat capture landing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt
    )

    $q = $Prompt.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) { return $false }
    return [bool]($q -match '(?i)\b(running well|running ok|are you (ok|up|there|online|working)|you (ok|up|online|working)|ask engine|sidecar|ops desk|desk (status|health)|metra (status|health|running)|health check|doing ok|everything ok)\b')
}

function New-MetraAskOpsStatusResult {
    <#
    .SYNOPSIS
        Grounded Ops/Ask status from local capability + sidecar /health (no SDK completion).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)]$Handoff,
        [Parameter(Mandatory)]$Capability,
        $Continuity,
        [string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $cap = $Capability
    $engine = [string](Get-MetraProp -Object $cap -Name 'engine' -Default '')
    $provider = [string](Get-MetraProp -Object $cap -Name 'providerLabel' -Default $engine)
    $port = [int](Get-MetraProp -Object $cap -Name 'port' -Default 0)
    $available = [bool](Get-MetraProp -Object $cap -Name 'available' -Default $false)
    $healthy = [bool](Get-MetraProp -Object $cap -Name 'engineHealthy' -Default $false)
    $reason = [string](Get-MetraProp -Object $cap -Name 'reason' -Default '')
    $model = [string](Get-MetraProp -Object $cap -Name 'model' -Default '')

    $runHealth = $null
    if ($engine -eq 'cursor' -and $port -gt 0) {
        try {
            $runHealth = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -Method Get -TimeoutSec 2
        }
        catch { }
    }

    $lines = @('From the Ops desk:')
    $lines += '- Desk Ask path is up (this reply came from the local Ops server).'

    if (-not [bool](Get-MetraProp -Object $cap -Name 'selected' -Default $false)) {
        $lines += '- Ask engine: not selected or disabled.'
    }
    elseif ($available -and $healthy) {
        $lines += "- Ask engine ($provider): sidecar listening on port $port; /health ok."
        $consecutive = Get-MetraProp -Object $runHealth -Name 'consecutiveRunErrors' -Default $null
        $lastStatus = [string](Get-MetraProp -Object $runHealth -Name 'lastRunStatus' -Default '')
        if ($null -ne $consecutive -and [int]$consecutive -gt 0) {
            $lines += "- Recent completions: $consecutive consecutive run error(s) (last status: $(if ($lastStatus) { $lastStatus } else { 'unknown' }))."
            $lines += '  Try: .\metra.ps1 ask engine restart -Confirm:$false'
        }
        elseif ($lastStatus -eq 'error') {
            $lines += '- Last completion failed; sidecar is up but SDK runs may still error.'
            $lines += '  Try: .\metra.ps1 ask engine restart -Confirm:$false'
        }
        else {
            $lines += $(if ($model) { "- Model pin: $model." } else { '- Model pin: default.' })
        }
    }
    elseif ($reason) {
        $lines += "- Ask engine ($provider): not ready ($reason)."
        $capMsg = [string](Get-MetraProp -Object $cap -Name 'message' -Default '')
        if ($capMsg) {
            $first = ($capMsg -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
            if ($first) { $lines += "  $first" }
        }
    }
    else {
        $lines += '- Ask engine: unavailable.'
    }

    $lines += 'Stop with: .\metra.ps1 ops -Stop (stops Ops and Ask together).'

    $msg = ($lines -join "`n").Trim()
    $spoken = ($lines | Select-Object -First 3) -join ' '
    $voice = New-MetraVoiceResponse -Spoken $spoken -Display $msg -Durable $msg

    $lane = New-MetraAskLaneResultObject -Lane 'chat' -Reason 'ops_status_report' `
        -ResponseObjective 'GroundedAnswer' -IntentConfidence 1.0 `
        -RouteScore ([int](Get-MetraProp -Object $Handoff -Name 'score' -Default 0)) `
        -EvidenceQuality 'adequate' -TurnMode 'Query'

    $result = [PSCustomObject]@{
        handoff          = $Handoff
        message          = $msg
        sessionId        = $(if (-not [string]::IsNullOrWhiteSpace($SessionId)) { $SessionId.Trim() } else { $null })
        capability       = $cap
        engine           = $engine
        model            = $model
        answered         = $true
        answerType       = 'grounded'
        evidenceQuality  = 'adequate'
        nextStep         = 'Ask a portfolio question, or run .\metra.ps1 ask engine show if completions keep failing.'
        continuity       = $Continuity
        secretsScrubbed  = $false
        secretsNotice    = $null
        secretsKinds     = @()
        secretsReason    = $null
        scrubbedPrompt   = $Prompt
        suggestCapture   = $false
        images           = @()
        voice            = $voice
    }

    return Merge-MetraAskLaneIntoResult -Result $result -Lane $lane
}

function Test-MetraAskAmbiguousReminderIntent {
    <#
    .SYNOPSIS
        Remind / look-at-later without legacy park-this phrasing (park regex gap).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt
    )

    $q = $Prompt.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) { return $false }
    # Covered by Test-MetraAskParkOrSaveIntent - not ambiguous reminder.
    if (Test-MetraAskParkOrSaveIntent -Prompt $q) { return $false }
    return [bool]($q -match '(?i)\b(remind me|remind me to|look at that (tomorrow|later)|remember that for later|note that for later)\b')
}

function Test-MetraAskAuthorityIntent {
    <#
    .SYNOPSIS
        Write-adjacent Host intent - fail toward OperatorConfirm.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt
    )

    $q = $Prompt.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) { return $false }
    return [bool]($q -match '(?i)\b(go ahead and (close|resolve|post|recommend)|close that ticket|post that to the ticket|recommend closing|just resolve it|handle the write|resolve that ticket|post a recommend)\b')
}

function Test-MetraAskSparseIntakeIntent {
    <#
    .SYNOPSIS
        Sparse symptom ask - clarify, do not diagnose.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt
    )

    $q = $Prompt.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) { return $false }
    if ($q.Length -gt 240) { return $false }
    return [bool]($q -match '(?i)\b(doesn''t work|does not work|not working|broken|my computer|pc (is )?(broken|slow)|can''t (login|log in|print)|unable to)\b')
}

function Get-MetraAskTurnMode {
    <#
    .SYNOPSIS
        Chat / Capture / Query / Route heuristic (extends honesty detectors).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt
    )

    $q = $Prompt.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) { return 'Chat' }
    if (Test-MetraAskAuthorityIntent -Prompt $q) { return 'Route' }
    if (Test-MetraDeskGreeting -Query $q) { return 'Chat' }
    if (Test-MetraAskOpsStatusIntent -Prompt $q) { return 'Query' }
    if (Test-MetraAskPersonalObservationIntent -Prompt $q) { return 'Chat' }
    if (Test-MetraAskParkOrSaveIntent -Prompt $q) { return 'Capture' }
    if (Test-MetraAskAmbiguousReminderIntent -Prompt $q) { return 'Capture' }
    if (Test-MetraAskSparseIntakeIntent -Prompt $q) { return 'Query' }
    if ($q -match '(?i)\b(what|how|where|status|brief|ticket|which)\b') { return 'Query' }
    return 'Chat'
}

function Get-MetraAskIntentConfidence {
    <#
    .SYNOPSIS
        0-1 intent confidence, separate from integer routeScore.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt
    )

    $q = $Prompt.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) { return [double]0 }
    if (Test-MetraAskAuthorityIntent -Prompt $q) { return [double]1.0 }
    if (Test-MetraDeskGreeting -Query $q) { return [double]1.0 }
    if (Test-MetraAskPersonalObservationIntent -Prompt $q) { return [double]1.0 }
    if (Test-MetraAskParkOrSaveIntent -Prompt $q) { return [double]1.0 }
    if (Test-MetraAskAmbiguousReminderIntent -Prompt $q) { return [double]1.0 }
    if (Test-MetraAskSparseIntakeIntent -Prompt $q) { return [double]0.95 }
    if ($q -match '(?i)\b(pharos|colleague|orion|ticket|export|broken|still)\b') { return [double]0.95 }
    if ($q.Length -lt 12) { return [double]0.5 }
    return [double]0.7
}

function Convert-MetraResponseObjectiveToAnswerType {
    <#
    .SYNOPSIS
        One-way projection: responseObjective + reason (+ optional legacy) -> answerType.
        Preserves greeting/observation/park for Ops UI badge hide.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Clarify', 'Capture', 'GroundedAnswer', 'OperatorConfirm')]
        [string]$ResponseObjective,
        [Parameter(Mandatory)][string]$Reason,
        [ValidateSet('', 'greeting', 'observation', 'park')]
        [string]$LegacyAnswerType = ''
    )

    if ($LegacyAnswerType -in @('greeting', 'observation', 'park')) {
        return $LegacyAnswerType
    }

    switch ($Reason) {
        'social_greeting' { return 'greeting' }
        'personal_observation' { return 'observation' }
        'capture_intent' {
            # New capture (remind) -> capture_ack; legacy park uses LegacyAnswerType=park
            return 'capture_ack'
        }
        'sparse_intake_clarify' { return 'clarify_draft' }
        'adequate_route_thin_evidence' {
            if ($ResponseObjective -eq 'Clarify') { return 'clarify_draft' }
            return 'capture_ack'
        }
        'high_intent_no_route' {
            if ($ResponseObjective -eq 'Clarify') { return 'clarify_draft' }
            return 'capture_ack'
        }
        'authority_requires_confirm' { return 'operator_confirm' }
        'evidence_adequate_routed' { return 'grounded' }
        default {
            switch ($ResponseObjective) {
                'Clarify' { return 'clarify_draft' }
                'OperatorConfirm' { return 'operator_confirm' }
                'GroundedAnswer' { return 'grounded' }
                default { return 'capture_ack' }
            }
        }
    }
}

function Test-MetraVoiceDurableContainsSpoken {
    <#
    .SYNOPSIS
        Invariant: durable must contain spoken (durable ⊇ spoken).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Spoken,
        [AllowEmptyString()][string]$Durable
    )

    if ([string]::IsNullOrWhiteSpace($Spoken)) { return $true }
    if ([string]::IsNullOrWhiteSpace($Durable)) { return $false }
    return $Durable.Contains($Spoken.Trim())
}

function New-MetraVoiceResponse {
    <#
    .SYNOPSIS
        Voice response schema. Spoken never sole copy; durable must contain spoken.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Spoken = '',
        [AllowEmptyString()][string]$Display = '',
        [Parameter(Mandatory)][AllowEmptyString()][string]$Durable
    )

    $spokenTrim = if ($null -eq $Spoken) { '' } else { $Spoken.Trim() }
    $displayTrim = if ($null -eq $Display) { '' } else { $Display.Trim() }
    $durableTrim = if ($null -eq $Durable) { '' } else { $Durable.Trim() }

    if ([string]::IsNullOrWhiteSpace($durableTrim) -and -not [string]::IsNullOrWhiteSpace($spokenTrim)) {
        throw 'New-MetraVoiceResponse: durable is required when spoken is set (spoken never sole copy).'
    }
    if (-not [string]::IsNullOrWhiteSpace($spokenTrim) -and -not (Test-MetraVoiceDurableContainsSpoken -Spoken $spokenTrim -Durable $durableTrim)) {
        # Auto-merge: durable must be a superset of spoken
        if ($durableTrim -notlike "*$spokenTrim*") {
            $durableTrim = if ([string]::IsNullOrWhiteSpace($durableTrim)) { $spokenTrim } else { "$durableTrim`n$spokenTrim" }
        }
    }
    if ([string]::IsNullOrWhiteSpace($displayTrim)) { $displayTrim = $spokenTrim }
    if ([string]::IsNullOrWhiteSpace($displayTrim)) { $displayTrim = $durableTrim }

    return [PSCustomObject]@{
        spoken  = $spokenTrim
        display = $displayTrim
        durable = $durableTrim
    }
}

function New-MetraAskLaneResultObject {
    param(
        [Parameter(Mandatory)][ValidateSet('chat', 'routed')][string]$Lane,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)]
        [ValidateSet('Clarify', 'Capture', 'GroundedAnswer', 'OperatorConfirm')]
        [string]$ResponseObjective,
        [double]$IntentConfidence,
        [int]$RouteScore,
        [ValidateSet('adequate', 'thin', 'none')][string]$EvidenceQuality,
        [string]$TurnMode,
        [ValidateSet('', 'greeting', 'observation', 'park')]
        [string]$LegacyAnswerType = ''
    )

    $answerType = Convert-MetraResponseObjectiveToAnswerType `
        -ResponseObjective $ResponseObjective `
        -Reason $Reason `
        -LegacyAnswerType $LegacyAnswerType

    return [PSCustomObject]@{
        lane               = $Lane
        reason             = $Reason
        responseObjective  = $ResponseObjective
        intentConfidence   = [double]$IntentConfidence
        routeScore         = [int]$RouteScore
        evidenceQuality    = $EvidenceQuality
        turnMode           = $TurnMode
        answerType         = $answerType
        legacyAnswerType   = $(if ($LegacyAnswerType) { $LegacyAnswerType } else { $null })
    }
}

function Resolve-MetraAskLane {
    <#
    .SYNOPSIS
        Classify chat vs routed lane. Returns rich contract for tests and diagnostics.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [int]$RouteScore = 0,
        [ValidateSet('adequate', 'thin', 'none')][string]$EvidenceQuality = 'none',
        [string]$RouteWhere = ''
    )

    $thresholds = Get-MetraAskLaneThresholds
    $intent = Get-MetraAskIntentConfidence -Prompt $Prompt
    $turnMode = Get-MetraAskTurnMode -Prompt $Prompt
    $routeScore = [Math]::Max(0, [int]$RouteScore)
    $eq = $EvidenceQuality
    $home = Get-MetraHomeDestinationName
    $atHome = (-not [string]::IsNullOrWhiteSpace($RouteWhere) -and $RouteWhere -eq $home)

    $common = @{
        IntentConfidence = $intent
        RouteScore       = $routeScore
        EvidenceQuality  = $eq
        TurnMode         = $turnMode
    }

    # 1) Authority - fail toward OperatorConfirm
    if (Test-MetraAskAuthorityIntent -Prompt $Prompt) {
        return New-MetraAskLaneResultObject @common -Lane 'chat' -Reason 'authority_requires_confirm' -ResponseObjective 'OperatorConfirm'
    }

    # 2) Honesty early-path equivalents (characterization parity)
    if (Test-MetraDeskGreeting -Query $Prompt) {
        return New-MetraAskLaneResultObject @common -Lane 'chat' -Reason 'social_greeting' -ResponseObjective 'Capture' -LegacyAnswerType 'greeting'
    }
    if (Test-MetraAskPersonalObservationIntent -Prompt $Prompt) {
        return New-MetraAskLaneResultObject @common -Lane 'chat' -Reason 'personal_observation' -ResponseObjective 'Capture' -LegacyAnswerType 'observation'
    }
    if (Test-MetraAskParkOrSaveIntent -Prompt $Prompt) {
        return New-MetraAskLaneResultObject @common -Lane 'chat' -Reason 'capture_intent' -ResponseObjective 'Capture' -LegacyAnswerType 'park'
    }

    # 3) Ambiguous reminder (park regex gap)
    if (Test-MetraAskAmbiguousReminderIntent -Prompt $Prompt) {
        return New-MetraAskLaneResultObject @common -Lane 'chat' -Reason 'capture_intent' -ResponseObjective 'Capture'
    }

    # 4) Sparse intake clarify (only when route is not confident - else thin-route chat)
    if ($routeScore -lt [int]$thresholds.RouteConfidentScore -and (Test-MetraAskSparseIntakeIntent -Prompt $Prompt)) {
        return New-MetraAskLaneResultObject @common -Lane 'chat' -Reason 'sparse_intake_clarify' -ResponseObjective 'Clarify'
    }

    # 5) Route match + thin/none evidence -> chat
    if ($routeScore -ge [int]$thresholds.RouteConfidentScore -and $eq -in @('thin', 'none')) {
        $obj = 'Capture'
        return New-MetraAskLaneResultObject @common -Lane 'chat' -Reason 'adequate_route_thin_evidence' -ResponseObjective $obj
    }

    # 6) Route match + adequate -> routed
    if ($routeScore -ge [int]$thresholds.RouteConfidentScore -and $eq -eq 'adequate') {
        return New-MetraAskLaneResultObject @common -Lane 'routed' -Reason 'evidence_adequate_routed' -ResponseObjective 'GroundedAnswer'
    }

    # 6b) Metra home below confident score: pack-backed evidence uses the executor.
    if ($atHome -and $routeScore -lt [int]$thresholds.RouteConfidentScore -and $eq -in @('adequate', 'thin')) {
        return New-MetraAskLaneResultObject @common -Lane 'routed' -Reason 'evidence_adequate_routed' -ResponseObjective 'GroundedAnswer'
    }

    # 6c) Thin evidence + real question -> executor (provisional), not capture landing.
    if ($eq -eq 'thin' -and $turnMode -in @('Query', 'Route')) {
        return New-MetraAskLaneResultObject @common -Lane 'routed' -Reason 'evidence_adequate_routed' -ResponseObjective 'GroundedAnswer'
    }

    # 7) High intent, no route (or weak route) - chat landing zone
    return New-MetraAskLaneResultObject @common -Lane 'chat' -Reason 'high_intent_no_route' -ResponseObjective 'Capture'
}

function New-MetraTicketAssessDraft {
    <#
    .SYNOPSIS
        Chat-lane draft text for TicketTracker assess. Never GroundedAnswer.
        TicketTracker owns the gate; this only drafts customerAsk / recommendDraft.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INTAKE', 'CLARIFY', 'SOLVE-READY')]
        [string]$Gate,
        [Parameter(Mandatory)]
        [ValidateSet('Clarify', 'Capture', 'GroundedAnswer', 'OperatorConfirm')]
        [string]$ResponseObjective,
        [Parameter(Mandatory)]$Packet
    )

    $objective = $ResponseObjective
    if ($objective -eq 'GroundedAnswer') { $objective = 'OperatorConfirm' }

    # Clamp to gate mapping (TicketTracker ownership wins).
    switch ($Gate) {
        'INTAKE' { $objective = 'Clarify' }
        'CLARIFY' { $objective = 'Clarify' }
        'SOLVE-READY' { $objective = 'OperatorConfirm' }
    }

    $subject = ''
    try { $subject = [string](Get-MetraProp -Object $Packet -Name 'subject' -Default '') } catch { $subject = '' }

    $customerAsk = ''
    $recommendDraft = ''

    switch ($Gate) {
        'INTAKE' {
            $customerAsk = New-MetraAskChatLaneTemplateMessage -Reason 'sparse_intake_clarify' -ResponseObjective 'Clarify' -Prompt $subject
            $recommendDraft = @(
                'Assessment: INTAKE'
                'Questions:'
                "1. $customerAsk"
                'Notes: Increase information quality only - no diagnosis.'
            ) -join "`n"
        }
        'CLARIFY' {
            $customerAsk = 'Which application or URL were you using, and what is the full error text?'
            $recommendDraft = @(
                'Assessment: CLARIFY'
                "Subject context: $subject"
                'Questions:'
                "1. $customerAsk"
                'Notes: Questions only - no invented fix.'
            ) -join "`n"
        }
        'SOLVE-READY' {
            $customerAsk = ''
            $ack = New-MetraAskChatLaneTemplateMessage -Reason 'authority_requires_confirm' -ResponseObjective 'OperatorConfirm' -Prompt $subject
            $recommendDraft = @(
                'Assessment: SOLVE-READY'
                $ack
                'OperatorConfirm: investigate or cite only after operator confirm - not a grounded Ask answer.'
            ) -join "`n"
        }
    }

    return [PSCustomObject]@{
        lane              = 'chat'
        gate              = $Gate
        responseObjective = $objective
        customerAsk       = $customerAsk
        recommendDraft    = $recommendDraft
        systemPromptHint  = (Get-MetraChatLaneSystemPrompt)
    }
}
