# Ask Conversation Engine - policy overlay prompt + typed engine envelope.

function Test-MetraAskExplicitListPeersIntent {
    <#
    .SYNOPSIS
        True when the operator explicitly asked to list related/similar peers (synthesis off).
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Prompt = '')

    $q = if ($null -eq $Prompt) { '' } else { $Prompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($q)) { return $false }
    return [bool](
        $q -match '(?i)\b(list|show|dump|enumerate)\b.+\b(related|similar|peer|peers)\b' `
            -or $q -match '(?i)\b(related|similar)\b.+\b(tickets?|items?|peers?)\b.+\b(list|show|what are)\b' `
            -or $q -match '(?i)\b(list|show)\b.+\b(related|similar)\b.+\b(tickets?|items?)\b' `
            -or $q -match '(?i)^(list|show)\s+(related|similar|peers?)\b'
    )
}

function Test-MetraAskRecommendShapedIntent {
    <#
    .SYNOPSIS
        True when the ask is recommend / situation-read shaped (Evidence vs reader synthesis candidate).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Prompt = '',
        $Intent
    )

    if (Test-MetraAskExplicitListPeersIntent -Prompt $Prompt) { return $false }

    $intentClass = [string](Get-MetraProp -Object $Intent -Name 'IntentClass' -Default 'work')
    if ($intentClass -in @('check_in', 'capability', 'empty', 'capture', 'authority_write', 'artifact_request')) {
        return $false
    }
    if ($intentClass -match '^(intimacy_|support_|companionship)') { return $false }

    $q = if ($null -eq $Prompt) { '' } else { $Prompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($q)) { return $false }

    return [bool](
        $q -match '(?i)\b(what should i (do|say|recommend)|how should i (handle|triage|respond|proceed)|recommend(ation)?\b|advice on|next step(s)?\b|triage\b|situation (read|assessment)|what do you (think|recommend))\b' `
            -or $q -match '(?i)\b(should i|would you recommend)\b' `
            -or ($intentClass -eq 'work' -and $q -match '(?i)\b(ticket|incident|recommend|similar|brief)\b' -and $q -match '(?i)\b(do|handle|fix|resolve|next|advice|think)\b')
    )
}

function Resolve-MetraAskSynthesisMode {
    <#
    .SYNOPSIS
        None | Synthesize | Restraint for Desk CE Evidence vs reader synthesis addendum.
    .NOTES
        List-peer asks -> None. Recommend-shaped + factual related evidence -> Synthesize.
        Recommend-shaped + id-only / thin peer stubs -> Restraint (no invented verdict, no peer-list-as-answer).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Prompt = '',
        $Intent,
        $EvidencePack
    )

    if (Test-MetraAskExplicitListPeersIntent -Prompt $Prompt) {
        return [PSCustomObject]@{ Mode = 'None'; Reason = 'explicit_list_peers' }
    }
    if (-not (Test-MetraAskRecommendShapedIntent -Prompt $Prompt -Intent $Intent)) {
        return [PSCustomObject]@{ Mode = 'None'; Reason = 'not_recommend_shaped' }
    }

    $items = @($(Get-MetraProp -Object $EvidencePack -Name 'items' -Default @()) | ForEach-Object { $_ })
    $relatedKinds = @('ticket', 'brief')
    $related = @($items | Where-Object {
            $k = [string](Get-MetraProp -Object $_ -Name 'kind' -Default '')
            $k -in $relatedKinds
        })
    $withFacts = @($related | Where-Object {
            [bool](Get-MetraProp -Object $_ -Name 'factualSupport' -Default $false)
        })

    if ($withFacts.Count -gt 0) {
        return [PSCustomObject]@{
            Mode              = 'Synthesize'
            Reason            = 'recommend_with_related_facts'
            RelatedCount      = $related.Count
            FactualRelatedCount = $withFacts.Count
        }
    }
    if ($related.Count -gt 0) {
        return [PSCustomObject]@{
            Mode         = 'Restraint'
            Reason       = 'recommend_id_only_related'
            RelatedCount = $related.Count
            FactualRelatedCount = 0
        }
    }

    # Recommend-shaped but no ticket/brief peers in pack - still restrain peer-list-as-answer if context may grow.
    return [PSCustomObject]@{
        Mode         = 'Restraint'
        Reason       = 'recommend_without_related_facts'
        RelatedCount = 0
        FactualRelatedCount = 0
    }
}

function Get-MetraAskSynthesisAddendumLines {
    <#
    .SYNOPSIS
        CE policy-overlay lines for Evidence vs reader synthesis (chat voice only).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('None', 'Synthesize', 'Restraint')]
        [string]$Mode
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    switch ($Mode) {
        'Synthesize' {
            [void]$lines.Add('Evidence vs reader synthesis (required this turn): verdict first; pull relevant facts from brief/notes/similar evidence; cite related ticket/item IDs only as backing. Do not hand a related-item or peer list as the recommendation or answer.')
        }
        'Restraint' {
            [void]$lines.Add('Evidence vs reader synthesis (restraint this turn): do not invent a recommendation from id-only stubs or empty peer lists. Do not dump related IDs as the answer. Prefer one plain agency-visible hold when a firm verdict is not supported - capable of listing peers or guessing, choosing not to because evidence is thin - then stop. Prefer silence on the gap when the limit already reads clearly.')
        }
        default { }
    }
    return @($lines)
}

function New-MetraConversationPrompt {
    <#
    .SYNOPSIS
        Conversation Identity Stack (Ask/Vision Surface) + CE policy overlay + sanitized user prompt.
    .OUTPUTS
        PSCustomObject with Text (engine prompt) and identity metadata (IdentityHash, PacksIncluded, ...).
        Callers that need only the string use .Text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        $Intent,
        $Policy,
        [string]$Depth = 'full',
        [ValidateSet('Ask', 'Cursor', 'Vision', 'iOS', 'OpsPresence')]
        [string]$Surface = 'Ask',
        [ValidateSet('Desk', 'Company', 'Deliver', 'DeskStrict', '')]
        [string]$Posture = '',
        [switch]$PortfolioShaped,
        $ContinuityEvidence,
        [switch]$IncidentActive,
        [string]$MetraRoot = (Get-MetraRoot),
        [ValidateSet('', 'None', 'Synthesize', 'Restraint')]
        [string]$SynthesisMode = ''
    )

    $intentClass = [string](Get-MetraProp -Object $Intent -Name 'IntentClass' -Default 'work')
    $policyName = [string](Get-MetraProp -Object $Policy -Name 'Policy' -Default 'Auto')
    $objective = [string](Get-MetraProp -Object $Policy -Name 'ResponseObjective' -Default 'GroundedAnswer')
    $knobs = Get-MetraProp -Object $Policy -Name 'Knobs' -Default $null

    $resolvedPosture = $Posture
    if ([string]::IsNullOrWhiteSpace($resolvedPosture) -and -not [string]::IsNullOrWhiteSpace($policyName) -and $policyName -ne 'Auto') {
        $resolvedPosture = $policyName
    }

    $resolvedSynthesis = $SynthesisMode
    if ([string]::IsNullOrWhiteSpace($resolvedSynthesis)) { $resolvedSynthesis = 'None' }

    $identity = $null
    $lines = [System.Collections.Generic.List[string]]::new()
    # Desk CE / Ask: shared Conversation Identity loader (Surface=Ask omits vision system.md).
    # CE policy overlay stays after identity text - same path, not same words as Vision.
    if (Get-Command Get-MetraConversationIdentityPrompt -ErrorAction SilentlyContinue) {
        $identitySurface = if ($Surface -in @('Ask', 'Vision', 'Cursor', 'iOS', 'OpsPresence')) { $Surface } else { 'Ask' }
        $identity = Get-MetraConversationIdentityPrompt `
            -MetraRoot $MetraRoot `
            -Surface $identitySurface `
            -Posture $resolvedPosture `
            -PortfolioShaped:$PortfolioShaped `
            -IncidentActive:$IncidentActive `
            -ContinuityEvidence $ContinuityEvidence
        [void]$lines.Add([string]$identity.Text)
    }
    elseif (Get-Command New-MetraPartnerIdentityPreamble -ErrorAction SilentlyContinue) {
        $preamble = New-MetraPartnerIdentityPreamble `
            -Surface $Surface `
            -Posture $resolvedPosture `
            -PortfolioShaped:$PortfolioShaped `
            -ContinuityEvidence $ContinuityEvidence `
            -IncidentActive:$IncidentActive
        [void]$lines.Add($preamble)
    }
    [void]$lines.Add("Policy=$policyName; Objective=$objective; Intent=$intentClass; EvidenceDepth=$Depth.")
    [void]$lines.Add('Answer in plain English. Do not invent health. Do not claim Host writes completed.')
    if ($Surface -in @('Vision', 'iOS')) {
        [void]$lines.Add('Vision companion: converse naturally as Metra. Portfolio/ops context may be attached - use it when it helps the turn; do not dump routing, AGENTS.md, or infrastructure essays unsolicited. No canned greetings; no scripted one-liners.')
    }
    else {
        if ($objective -eq 'OperatorConfirm') {
            [void]$lines.Add('OperatorConfirm: investigate or cite only after operator confirm - not a grounded write.')
        }
        if ($intentClass -eq 'status_query') {
            [void]$lines.Add('Status questions require current health evidence or an explicit inability to verify.')
        }
        if ($intentClass -eq 'check_in') {
            [void]$lines.Add('Brief check-in only - no infrastructure essay.')
        }
    }
    if ($knobs -and -not [bool](Get-MetraProp -Object $knobs -Name 'humor' -Default $false)) {
        [void]$lines.Add('Humor off for this turn.')
    }
    if ($policyName -eq 'Deliver' -or $intentClass -eq 'artifact_request') {
        [void]$lines.Add('Deliver-first: produce the requested finished artifact before asking clarifying questions. Max clarifications for this turn is 0.')
    }
    if ($policyName -eq 'DeskStrict') {
        [void]$lines.Add('DeskStrict: no Company warmth, no silence sparks, no mood carryover from prior Company turns. Flat ops tone only.')
    }
    if ($knobs) {
        $maxClarify = [int](Get-MetraProp -Object $knobs -Name 'maxClarifications' -Default 1)
        if ($maxClarify -eq 0 -and $policyName -ne 'Deliver') {
            [void]$lines.Add('Do not ask clarifying questions this turn; answer with what you have or state the gap.')
        }
    }
    foreach ($synthLine in @(Get-MetraAskSynthesisAddendumLines -Mode $resolvedSynthesis)) {
        if (-not [string]::IsNullOrWhiteSpace($synthLine)) {
            [void]$lines.Add($synthLine)
        }
    }
    [void]$lines.Add('Policy is re-evaluated each user turn - do not carry Company mood or silence posture into Desk/Deliver/DeskStrict turns.')
    [void]$lines.Add('')
    [void]$lines.Add($Prompt)

    return [PSCustomObject]@{
        Text            = ($lines -join "`n")
        IdentityHash   = $(if ($identity) { [string](Get-MetraProp -Object $identity -Name 'IdentityHash' -Default '') } else { $null })
        PacksIncluded  = $(if ($identity) { @(Get-MetraProp -Object $identity -Name 'PacksIncluded' -Default @()) } else { @() })
        PacksOmitted   = $(if ($identity) { @(Get-MetraProp -Object $identity -Name 'PacksOmitted' -Default @()) } else { @() })
        TeachingActive = $(if ($identity) { [bool](Get-MetraProp -Object $identity -Name 'TeachingActive' -Default $false) } else { $false })
        HumorActive    = $(if ($identity) { [bool](Get-MetraProp -Object $identity -Name 'HumorActive' -Default $false) } else { $false })
        SynthesisMode  = $resolvedSynthesis
    }
}

function Invoke-MetraAskConversationEngine {
    <#
    .SYNOPSIS
        Typed engine envelope for Conversation Execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [hashtable]$Context = @{},
        [string]$Cwd = '',
        [string]$SessionId = '',
        [object[]]$Images = @(),
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 0
    )

    $capability = $null
    try {
        $capability = Get-MetraAskCapability -MetraRoot $MetraRoot
    }
    catch {
        return [PSCustomObject]@{
            Succeeded  = $false
            ReasonCode = 'engine_not_configured'
            Text       = ''
            Raw        = [string]$_.Exception.Message
            Engine     = $null
            Model      = $null
            SessionId  = $SessionId
        }
    }

    if (-not [bool](Get-MetraProp -Object $capability -Name 'enabled' -Default $true)) {
        return [PSCustomObject]@{
            Succeeded  = $false
            ReasonCode = 'engine_disabled'
            Text       = ''
            Raw        = 'ask.enabled=false'
            Engine     = [string](Get-MetraProp -Object $capability -Name 'engine' -Default '')
            Model      = $null
            SessionId  = $SessionId
        }
    }

    if (-not [bool](Get-MetraProp -Object $capability -Name 'available' -Default $false)) {
        $reason = [string](Get-MetraProp -Object $capability -Name 'reason' -Default 'engine_unreachable')
        $code = if ($reason -match 'timeout') { 'engine_timeout' }
        elseif ($reason -match 'config|not_configured|missing') { 'engine_not_configured' }
        else { 'engine_unreachable' }
        return [PSCustomObject]@{
            Succeeded  = $false
            ReasonCode = $code
            Text       = ''
            Raw        = $reason
            Engine     = [string](Get-MetraProp -Object $capability -Name 'engine' -Default '')
            Model      = $null
            SessionId  = $SessionId
        }
    }

    try {
        if ([string]::IsNullOrWhiteSpace($Cwd)) { $Cwd = $MetraRoot }
        $invokeParams = @{
            Prompt    = $Prompt
            Context   = $Context
            SessionId = $SessionId
            Images    = $Images
            MetraRoot = $MetraRoot
            Cwd       = $Cwd
        }
        if ($TimeoutSec -gt 0) { $invokeParams['TimeoutSec'] = $TimeoutSec }

        $engineResult = Invoke-MetraAskEngine @invokeParams

        if ([bool](Get-MetraProp -Object $engineResult -Name 'secretsRefuse' -Default $false) -or
            [string](Get-MetraProp -Object $engineResult -Name 'error' -Default '') -eq 'secrets_refuse') {
            return [PSCustomObject]@{
                Succeeded  = $false
                ReasonCode = 'secrets_refuse'
                Text       = [string](Get-MetraProp -Object $engineResult -Name 'secretsNotice' -Default '')
                Raw        = 'secrets_refuse'
                Engine     = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default '')
                Model      = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default '')
                SessionId  = [string](Get-MetraProp -Object $engineResult -Name 'sessionId' -Default $SessionId)
                EngineResult = $engineResult
            }
        }

        if (-not [bool](Get-MetraProp -Object $engineResult -Name 'ok' -Default $false)) {
            $err = [string](Get-MetraProp -Object $engineResult -Name 'error' -Default 'engine_invalid_response')
            $code = if ($err -match 'timeout') { 'engine_timeout' }
            elseif ($err -match 'unreachable|connect') { 'engine_unreachable' }
            elseif ($err -match 'context') { 'engine_context_rejected' }
            elseif ($err -match 'unsupported|image_vision') { 'engine_invalid_response' }
            else { 'engine_invalid_response' }
            return [PSCustomObject]@{
                Succeeded  = $false
                ReasonCode = $code
                Text       = ''
                Raw        = $err
                Engine     = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default '')
                Model      = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default '')
                SessionId  = [string](Get-MetraProp -Object $engineResult -Name 'sessionId' -Default $SessionId)
                EngineResult = $engineResult
            }
        }

        $text = [string](Get-MetraProp -Object $engineResult -Name 'message' -Default '')
        if ([string]::IsNullOrWhiteSpace($text)) {
            return [PSCustomObject]@{
                Succeeded  = $false
                ReasonCode = 'engine_empty_response'
                Text       = ''
                Raw        = 'empty_message'
                Engine     = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default '')
                Model      = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default '')
                SessionId  = [string](Get-MetraProp -Object $engineResult -Name 'sessionId' -Default $SessionId)
                EngineResult = $engineResult
            }
        }

        # Post-engine: block false completion language on authority paths handled by caller.
        return [PSCustomObject]@{
            Succeeded  = $true
            ReasonCode = 'ok'
            Text       = $text
            Raw        = $null
            Engine     = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default '')
            Model      = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default '')
            SessionId  = [string](Get-MetraProp -Object $engineResult -Name 'sessionId' -Default $SessionId)
            EngineResult = $engineResult
        }
    }
    catch {
        $msg = [string]$_.Exception.Message
        $code = if ($msg -match 'timeout') { 'engine_timeout' } else { 'engine_unreachable' }
        return [PSCustomObject]@{
            Succeeded  = $false
            ReasonCode = $code
            Text       = ''
            Raw        = $msg
            Engine     = $null
            Model      = $null
            SessionId  = $SessionId
        }
    }
}

