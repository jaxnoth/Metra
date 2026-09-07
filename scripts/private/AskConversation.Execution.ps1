# Ask Conversation Execution - voice normalization glue + orchestrator entry.

function Add-MetraAskVoiceNormalization {
    <#
    .SYNOPSIS
        Ensure desk Ask results always carry filled voice with message == voice.display.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Result,
        [ValidateSet('success', 'refuse', 'authority', 'fallback', 'legacy')]
        [string]$PathKind = 'legacy',
        [string]$ReasonCode = 'ok'
    )

    if ($null -eq $Result) { return $Result }

    $existing = Get-MetraProp -Object $Result -Name 'voice' -Default $null
    $message = [string](Get-MetraProp -Object $Result -Name 'message' -Default '')
    $answered = [bool](Get-MetraProp -Object $Result -Name 'answered' -Default $false)
    $objective = [string](Get-MetraProp -Object $Result -Name 'responseObjective' -Default '')
    $secretsRefuse = [bool](Get-MetraProp -Object $Result -Name 'secretsRefuse' -Default $false)

    $kind = $PathKind
    if ($secretsRefuse -or [string](Get-MetraProp -Object $Result -Name 'answerType' -Default '') -eq 'refusal') {
        $kind = 'refuse'
    }
    elseif ($objective -eq 'OperatorConfirm' -or [string](Get-MetraProp -Object $Result -Name 'reason' -Default '') -eq 'authority_requires_confirm') {
        $kind = 'authority'
    }
    elseif (-not $answered -and $kind -eq 'legacy' -and [string]::IsNullOrWhiteSpace($message)) {
        $kind = 'fallback'
    }

    if ($null -ne $existing -and (Test-MetraAskVoiceContract -Result ([PSCustomObject]@{
                message = $message
                voice   = $existing
            }))) {
        # Keep existing voice but force message == display
        $display = [string](Get-MetraProp -Object $existing -Name 'display' -Default $message)
        $Result | Add-Member -NotePropertyName message -NotePropertyValue $display -Force
        $Result | Add-Member -NotePropertyName voice -NotePropertyValue $existing -Force
        return $Result
    }

    $voice = Format-MetraAskVoiceFromEngine -PathKind $kind -Text $message -ReasonCode $ReasonCode `
        -RefuseNotice ([string](Get-MetraProp -Object $Result -Name 'secretsNotice' -Default ''))
    $Result | Add-Member -NotePropertyName voice -NotePropertyValue $voice -Force
    $Result | Add-Member -NotePropertyName message -NotePropertyValue ([string]$voice.display) -Force
    if (-not $Result.PSObject.Properties['reasonCode']) {
        $Result | Add-Member -NotePropertyName reasonCode -NotePropertyValue $ReasonCode -Force
    }
    return $Result
}

function Invoke-MetraAskConversationExecution {
    <#
    .SYNOPSIS
        Full Conversation Execution path for Bounded Ops Ask (behind feature flag).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [string]$SessionId,
        [string]$RecallSessionId,
        [object[]]$Images = @(),
        [object[]]$JournalImages = @(),
        [switch]$Remote,
        [string]$Repo = '',
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$HeaderClient = '',
        [string]$BodyClient = '',
        [string]$ClientHint = '',
        [string]$RequestedPolicy = '',
        [bool]$TrustedClientContext = $false,
        [bool]$IsLoopback = $false,
        [bool]$IncidentActive = $false
    )

    $pre = Invoke-MetraAskConversationSecretsPreflight -Prompt $Prompt
    if ($pre.Disposition -eq 'refuse') {
        $voice = Format-MetraAskVoiceFromEngine -PathKind 'refuse' -RefuseNotice ([string]$pre.Notice) `
            -ReasonCode ([string]$pre.ReasonCode)
        $handoff = Get-MetraDeskHandoff -Query 'secrets blocked' -MetraRoot $MetraRoot
        $lane = Resolve-MetraAskLane -Prompt 'secrets blocked' -RouteScore 0 -EvidenceQuality 'none' -RouteWhere ''
        $cap = Get-MetraAskCapability -MetraRoot $MetraRoot
        return Add-MetraAskVoiceNormalization -PathKind 'refuse' -ReasonCode ([string]$pre.ReasonCode) -Result (
            Merge-MetraAskLaneIntoResult -Lane $lane -Result ([PSCustomObject]@{
                    handoff                      = $handoff
                    message                      = [string]$voice.display
                    voice                        = $voice
                    sessionId                    = $SessionId
                    capability                   = $cap
                    engine                       = $null
                    model                        = $null
                    answered                     = $false
                    answerType                   = 'refusal'
                    evidenceQuality              = 'none'
                    nextStep                     = 'Rephrase without private-key material.'
                    continuity                   = $null
                    secretsScrubbed              = $true
                    secretsRefuse                = $true
                    secretsNotice                = [string]$pre.Notice
                    secretsKinds                 = @($pre.Scrub.Kinds)
                    secretsReason                = [string](Get-MetraProp -Object $pre.Scrub -Name 'Reason' -Default '')
                    scrubbedPrompt               = ''
                    suggestCapture               = $false
                    images                       = @($JournalImages)
                    intentClass                  = 'refuse'
                    policy                       = 'DeskStrict'
                    policySource                 = 'secrets_preflight'
                    reasonCode                   = [string]$pre.ReasonCode
                    conversationExecutionEnabled = $true
                })
        )
    }

    $safePrompt = [string]$pre.Prompt
    $continuity = Get-MetraAskContinuityContext `
        -SessionId $SessionId `
        -RecallSessionId $RecallSessionId `
        -MetraRoot $MetraRoot
    # Vocative Metra is partner talk - strip before route scoring (not a route cue).
    $routePrompt = if (Get-Command Remove-MetraAskVocativeAddress -ErrorAction SilentlyContinue) {
        Remove-MetraAskVocativeAddress -Prompt $safePrompt
    }
    else {
        $safePrompt
    }
    $handoff = Get-MetraDeskHandoff -Query $routePrompt -MetraRoot $MetraRoot
    $routeScore = [int](Get-MetraProp -Object $handoff -Name 'score' -Default 0)
    $routeWhere = [string](Get-MetraProp -Object $handoff -Name 'where' -Default '')

    $intent = Resolve-MetraAskIntent -Prompt $safePrompt -RouteScore $routeScore
    $continuityEvidence = if (Get-Command New-MetraContinuityEvidence -ErrorAction SilentlyContinue) {
        New-MetraContinuityEvidence -Continuity $continuity -Handoff $handoff
    }
    else {
        $null
    }
    $portfolioShaped = $false
    if (Get-Command Test-MetraAskPortfolioShapedTurn -ErrorAction SilentlyContinue) {
        $portfolioShaped = [bool](Test-MetraAskPortfolioShapedTurn `
                -Prompt $safePrompt `
                -Intent $intent `
                -Handoff $handoff `
                -ContinuityEvidence $continuityEvidence `
                -RouteScore $routeScore)
    }
    $policy = Resolve-MetraConversationPolicy `
        -Intent $intent `
        -ClientHint $ClientHint `
        -HeaderClient $HeaderClient `
        -BodyClient $BodyClient `
        -RequestedPolicy $RequestedPolicy `
        -TrustedClientContext:$TrustedClientContext `
        -IsLoopback:$IsLoopback `
        -IncidentActive:$IncidentActive

    # Capture: phrase only - no free write
    if ([string]$intent.IntentClass -eq 'capture') {
        $laneCap = Resolve-MetraAskLane -Prompt $safePrompt -RouteScore $routeScore -EvidenceQuality 'none' -RouteWhere $routeWhere
        $capResult = New-MetraAskParkOrSaveResult -Query $safePrompt -Continuity $continuity -SessionId $SessionId
        $merged = Merge-MetraAskLaneIntoResult -Lane $laneCap -Result $capResult
        $merged | Add-Member -NotePropertyName intentClass -NotePropertyValue 'capture' -Force
        $merged | Add-Member -NotePropertyName policy -NotePropertyValue ([string]$policy.Policy) -Force
        $merged | Add-Member -NotePropertyName policySource -NotePropertyValue ([string]$policy.PolicySource) -Force
        $merged | Add-Member -NotePropertyName conversationExecutionEnabled -NotePropertyValue $true -Force
        return Add-MetraAskVoiceNormalization -Result $merged -PathKind 'success' -ReasonCode 'capture_phrase'
    }

    if ([string]$intent.IntentClass -eq 'authority_write' -or [string]$policy.ResponseObjective -eq 'OperatorConfirm') {
        $laneAuth = Resolve-MetraAskLane -Prompt $safePrompt -RouteScore $routeScore -EvidenceQuality 'none' -RouteWhere $routeWhere
        $authMsg = 'OperatorConfirm: confirm any Host write at the desk (recommend/post/resolve) before I treat it as done.'
        $voice = Format-MetraAskVoiceFromEngine -PathKind 'authority' -Text $authMsg -ReasonCode 'authority_requires_confirm'
        $cap = Get-MetraAskCapability -MetraRoot $MetraRoot
        return Add-MetraAskVoiceNormalization -PathKind 'authority' -ReasonCode 'authority_requires_confirm' -Result (
            Merge-MetraAskLaneIntoResult -Lane $laneAuth -Result ([PSCustomObject]@{
                    handoff                      = $handoff
                    message                      = [string]$voice.display
                    voice                        = $voice
                    sessionId                    = $SessionId
                    capability                   = $cap
                    engine                       = $null
                    model                        = $null
                    answered                     = $false
                    answerType                   = 'operator_confirm'
                    evidenceQuality              = 'none'
                    nextStep                     = 'Confirm at the desk before Host writes.'
                    continuity                   = $continuity
                    secretsScrubbed              = ($pre.Disposition -eq 'scrubbed')
                    secretsNotice                = [string]$pre.Notice
                    secretsKinds                 = @($pre.Scrub.Kinds)
                    secretsReason                = $null
                    scrubbedPrompt               = $safePrompt
                    suggestCapture               = $false
                    images                       = @($JournalImages)
                    intentClass                  = [string]$intent.IntentClass
                    policy                       = [string]$policy.Policy
                    policySource                 = [string]$policy.PolicySource
                    reasonCode                   = 'authority_requires_confirm'
                    conversationExecutionEnabled = $true
                })
        )
    }

    $depthInfo = Resolve-MetraAskEvidenceDepth -Intent $intent -Policy $policy
    $depth = [string]$depthInfo.Depth
    $capability = Get-MetraAskCapability -MetraRoot $MetraRoot
    if (-not $capability.available -and $capability.selected) {
        $capability = Start-MetraAskEngine -MetraRoot $MetraRoot
    }

    # status_query health gate (capability_only depth)
    if ([string]$intent.IntentClass -eq 'status_query') {
        $health = Get-MetraProp -Object $capability -Name 'runtimeHealthSnapshot' -Default $null
        if ($null -eq $health) { $health = Get-MetraProp -Object $capability -Name 'health' -Default $null }
        $healthOk = Test-MetraAskHealthObservationCurrent -Health $health
        if (-not $healthOk) {
            $msg = 'I cannot verify current runtime health from a fresh source observation, so I will not claim I am running well. Ask engine reachability alone is not a health proof.'
            $voice = Format-MetraAskVoiceFromEngine -PathKind 'success' -Text $msg -ReasonCode 'health_unverifiable' `
                -DurableDisposition 'status_query:inability_to_verify'
            $laneSt = Resolve-MetraAskLane -Prompt $safePrompt -RouteScore $routeScore -EvidenceQuality 'thin' -RouteWhere $routeWhere
            return Add-MetraAskVoiceNormalization -PathKind 'success' -ReasonCode 'health_unverifiable' -Result (
                Merge-MetraAskLaneIntoResult -Lane $laneSt -Result ([PSCustomObject]@{
                        handoff                      = $handoff
                        message                      = [string]$voice.display
                        voice                        = $voice
                        sessionId                    = $SessionId
                        capability                   = $capability
                        engine                       = $null
                        model                        = $null
                        answered                     = $true
                        answerType                   = 'provisional'
                        evidenceQuality              = 'thin'
                        nextStep                     = 'Check Ops/Ask engine health sources that publish freshness metadata.'
                        continuity                   = $continuity
                        secretsScrubbed              = ($pre.Disposition -eq 'scrubbed')
                        secretsNotice                = [string]$pre.Notice
                        secretsKinds                 = @($pre.Scrub.Kinds)
                        secretsReason                = $null
                        scrubbedPrompt               = $safePrompt
                        suggestCapture               = $false
                        images                       = @($JournalImages)
                        intentClass                  = 'status_query'
                        policy                       = [string]$policy.Policy
                        policySource                 = [string]$policy.PolicySource
                        reasonCode                   = 'health_unverifiable'
                        conversationExecutionEnabled = $true
                    })
            )
        }
    }

    # check_in / capability: plain answer without pack/engine when depth is capability_only
    if ([string]$intent.IntentClass -in @('check_in', 'capability') -and $depth -eq 'capability_only') {
        $laneGreet = Resolve-MetraAskLane -Prompt $safePrompt -RouteScore $routeScore -EvidenceQuality 'thin' -RouteWhere $routeWhere
        $who = ($safePrompt -match '(?i)\b(who are you|what are you)\b')
        $msg = if ([string]$intent.IntentClass -eq 'check_in' -or $who) {
            if (Get-Command New-MetraPartnerCheckInResponse -ErrorAction SilentlyContinue) {
                $postureForCheckIn = [string]$policy.Policy
                if ($postureForCheckIn -notin @('Desk', 'Company', 'Deliver', 'DeskStrict')) {
                    $postureForCheckIn = ''
                }
                $checkIn = New-MetraPartnerCheckInResponse `
                    -Surface Ask `
                    -Posture $postureForCheckIn `
                    -ContinuityEvidence $continuityEvidence `
                    -WhoAreYou:$who
                [string]$checkIn.Display
            }
            else {
                "I'm here."
            }
        }
        else {
            'I can route work, answer Bounded Ask questions, and hand off to project homes. I will not invent Host writes or ticket changes.'
        }
        $voice = Format-MetraAskVoiceFromEngine -PathKind 'success' -Text $msg -ReasonCode 'ok' `
            -DurableDisposition (ConvertTo-MetraPartnerNeutralArtifact -Text "intent:$($intent.IntentClass);depth=$depth")
        return Add-MetraAskVoiceNormalization -PathKind 'success' -ReasonCode 'ok' -Result (
            Merge-MetraAskLaneIntoResult -Lane $laneGreet -Result ([PSCustomObject]@{
                    handoff                      = $handoff
                    message                      = [string]$voice.display
                    voice                        = $voice
                    sessionId                    = $SessionId
                    capability                   = $capability
                    engine                       = $null
                    model                        = $null
                    answered                     = $true
                    answerType                   = 'greeting'
                    evidenceQuality              = 'thin'
                    nextStep                     = $null
                    continuity                   = $continuity
                    continuityEvidence           = $continuityEvidence
                    portfolioShaped              = $false
                    secretsScrubbed              = ($pre.Disposition -eq 'scrubbed')
                    secretsNotice                = [string]$pre.Notice
                    secretsKinds                 = @($pre.Scrub.Kinds)
                    secretsReason                = $null
                    scrubbedPrompt               = $safePrompt
                    suggestCapture               = $false
                    images                       = @($JournalImages)
                    intentClass                  = [string]$intent.IntentClass
                    policy                       = [string]$policy.Policy
                    policySource                 = [string]$policy.PolicySource
                    retentionClass               = [string](Get-MetraProp -Object $policy.Knobs -Name 'retentionClass' -Default 'auto')
                    reasonCode                   = 'ok'
                    conversationExecutionEnabled = $true
                    evidenceDepth                = $depth
                })
        )
    }

    try {
        $pack = New-MetraAskEvidencePack -Prompt $safePrompt -Handoff $handoff -Continuity $continuity `
            -Capability $capability -Images $Images -Remote:$Remote -Repo $Repo -MetraRoot $MetraRoot `
            -Depth $depth
    }
    catch {
        $voice = Format-MetraAskVoiceFromEngine -PathKind 'fallback' -Text 'I could not build evidence for that ask (not completed).' `
            -ReasonCode 'evidence_pack_failed' -DurableDisposition 'evidence_pack_failed'
        $laneFail = Resolve-MetraAskLane -Prompt $safePrompt -RouteScore $routeScore -EvidenceQuality 'none' -RouteWhere $routeWhere
        return Add-MetraAskVoiceNormalization -PathKind 'fallback' -ReasonCode 'evidence_pack_failed' -Result (
            Merge-MetraAskLaneIntoResult -Lane $laneFail -Result ([PSCustomObject]@{
                    handoff                      = $handoff
                    message                      = [string]$voice.display
                    voice                        = $voice
                    sessionId                    = $SessionId
                    capability                   = $capability
                    engine                       = $null
                    model                        = $null
                    answered                     = $false
                    answerType                   = 'degraded'
                    evidenceQuality              = 'none'
                    nextStep                     = 'Retry with a clearer route or local evidence.'
                    continuity                   = $continuity
                    secretsScrubbed              = ($pre.Disposition -eq 'scrubbed')
                    secretsNotice                = [string]$pre.Notice
                    secretsKinds                 = @($pre.Scrub.Kinds)
                    secretsReason                = $null
                    scrubbedPrompt               = $safePrompt
                    suggestCapture               = $false
                    images                       = @($JournalImages)
                    intentClass                  = [string]$intent.IntentClass
                    policy                       = [string]$policy.Policy
                    reasonCode                   = 'evidence_pack_failed'
                    conversationExecutionEnabled = $true
                })
        )
    }

    $quality = [string]$pack.quality
    $lane = Resolve-MetraAskLane -Prompt $safePrompt -RouteScore $routeScore -EvidenceQuality $quality -RouteWhere $routeWhere
    $cwd = Get-MetraAskRouteCwd -Where $routeWhere -MetraRoot $MetraRoot

    try {
        $postureForPrompt = [string]$policy.Policy
        if ($postureForPrompt -notin @('Desk', 'Company', 'Deliver', 'DeskStrict')) {
            $postureForPrompt = ''
        }
        $enginePrompt = New-MetraConversationPrompt `
            -Prompt $safePrompt `
            -Intent $intent `
            -Policy $policy `
            -Depth $depth `
            -Surface Ask `
            -Posture $postureForPrompt `
            -PortfolioShaped:$portfolioShaped `
            -ContinuityEvidence $continuityEvidence `
            -IncidentActive:$IncidentActive
    }
    catch {
        $voice = Format-MetraAskVoiceFromEngine -PathKind 'fallback' -ReasonCode 'policy_overlay_failed' `
            -Text 'I could not build the policy overlay for that ask (not completed).'
        return Add-MetraAskVoiceNormalization -PathKind 'fallback' -ReasonCode 'policy_overlay_failed' -Result (
            Merge-MetraAskLaneIntoResult -Lane $lane -Result ([PSCustomObject]@{
                    handoff         = $handoff
                    message         = [string]$voice.display
                    voice           = $voice
                    sessionId       = $SessionId
                    capability      = $capability
                    answered        = $false
                    answerType      = 'degraded'
                    evidenceQuality = $quality
                    continuity      = $continuity
                    scrubbedPrompt  = $safePrompt
                    images          = @($JournalImages)
                    reasonCode      = 'policy_overlay_failed'
                    conversationExecutionEnabled = $true
                })
        )
    }

    $ctxScrub = Invoke-MetraAskSecretsScrubObject -InputObject ([hashtable]$pack.context)
    $safeContext = if ($null -ne $ctxScrub.Value) { $ctxScrub.Value } else { @{} }

    $engine = Invoke-MetraAskConversationEngine `
        -Prompt $enginePrompt `
        -Context $safeContext `
        -Cwd $cwd `
        -SessionId $SessionId `
        -Images $Images `
        -MetraRoot $MetraRoot

    if (-not [bool]$engine.Succeeded) {
        $pathKind = if ([string]$engine.ReasonCode -eq 'secrets_refuse') { 'refuse' } else { 'fallback' }
        $text = if ([string]$engine.ReasonCode -eq 'secrets_refuse' -and [string]$engine.Text) {
            [string]$engine.Text
        }
        else {
            'I could not complete that Ask turn (not completed).'
        }
        $voice = Format-MetraAskVoiceFromEngine -PathKind $pathKind -Text $text -ReasonCode ([string]$engine.ReasonCode) `
            -DurableDisposition "engine:$($engine.ReasonCode)"
        $sem = Resolve-MetraAskAnswerSemantics `
            -EvidenceQuality $quality `
            -EngineUnavailable:($pathKind -ne 'refuse') `
            -SecretsRefuse:($pathKind -eq 'refuse') `
            -NextStep ([string](Get-MetraProp -Object $handoff -Name 'next' -Default ''))
        return Add-MetraAskVoiceNormalization -PathKind $pathKind -ReasonCode ([string]$engine.ReasonCode) -Result (
            Merge-MetraAskLaneIntoResult -Lane $lane -Result ([PSCustomObject]@{
                    handoff                      = $handoff
                    message                      = [string]$voice.display
                    voice                        = $voice
                    sessionId                    = [string]$engine.SessionId
                    capability                   = $capability
                    engine                       = [string]$engine.Engine
                    model                        = [string]$engine.Model
                    answered                     = $false
                    answerType                   = [string]$sem.answerType
                    evidenceQuality              = [string]$sem.evidenceQuality
                    nextStep                     = [string]$sem.nextStep
                    continuity                   = $continuity
                    secretsScrubbed              = ($pre.Disposition -eq 'scrubbed') -or ($pathKind -eq 'refuse')
                    secretsRefuse                = ($pathKind -eq 'refuse')
                    secretsNotice                = $(if ($pathKind -eq 'refuse' -and [string]$engine.Text) { [string]$engine.Text } else { [string]$pre.Notice })
                    secretsKinds                 = @($pre.Scrub.Kinds)
                    secretsReason                = $(if ($pathKind -eq 'refuse') { 'secrets_refuse' } else { $null })
                    scrubbedPrompt               = $(if ($pathKind -eq 'refuse') { '' } else { $safePrompt })
                    suggestCapture               = $false
                    images                       = @($JournalImages)
                    intentClass                  = [string]$intent.IntentClass
                    policy                       = [string]$policy.Policy
                    policySource                 = [string]$policy.PolicySource
                    reasonCode                   = [string]$engine.ReasonCode
                    conversationExecutionEnabled = $true
                    evidenceDepth                = $depth
                })
        )
    }

    $responseScrub = Invoke-MetraAskSecretsScrubText -Text ([string]$engine.Text)
    $cleanMessage = Remove-MetraAskUiChrome -Message ([string]$responseScrub.Text)
    $cleanMessage = Repair-MetraAskWritePromise -Message $cleanMessage
    if ($responseScrub.Refuse) {
        $voice = Format-MetraAskVoiceFromEngine -PathKind 'refuse' -RefuseNotice ([string]$responseScrub.Notice) `
            -ReasonCode 'secrets_refuse'
        return Add-MetraAskVoiceNormalization -PathKind 'refuse' -ReasonCode 'secrets_refuse' -Result (
            Merge-MetraAskLaneIntoResult -Lane $lane -Result ([PSCustomObject]@{
                    handoff         = $handoff
                    message         = [string]$voice.display
                    voice           = $voice
                    sessionId       = [string]$engine.SessionId
                    capability      = $capability
                    answered        = $false
                    answerType      = 'refusal'
                    evidenceQuality = $quality
                    continuity      = $continuity
                    secretsRefuse   = $true
                    secretsScrubbed = $true
                    secretsNotice   = [string]$responseScrub.Notice
                    scrubbedPrompt  = ''
                    images          = @($JournalImages)
                    reasonCode      = 'secrets_refuse'
                    conversationExecutionEnabled = $true
                })
        )
    }

    $preferred = if ($quality -eq 'adequate') { 'grounded' } else { 'provisional' }
    $sem = Resolve-MetraAskAnswerSemantics -EvidenceQuality $quality -PreferredType $preferred `
        -NextStep ([string](Get-MetraProp -Object $handoff -Name 'next' -Default ''))
    if ($quality -eq 'thin') {
        $prefix = New-MetraAskThinEvidencePrefix
        if ($cleanMessage -notmatch '(?i)thin routed evidence|provisional') {
            $cleanMessage = "$prefix`n`n$cleanMessage"
        }
    }
    $notice = Join-MetraAskSecretsNotices -Notices @(
        $(if ($pre.Disposition -eq 'scrubbed') { $pre.Notice }),
        $(if ($responseScrub.Matched) { $responseScrub.Notice })
    )
    $cleanMessage = Add-MetraAskSecretsNoticeToMessage -Message $cleanMessage -Notice $notice

    $voice = Format-MetraAskVoiceFromEngine -PathKind 'success' -Text $cleanMessage -ReasonCode 'ok' `
        -DurableDisposition "intent:$($intent.IntentClass);policy:$($policy.Policy);depth=$depth"
    return Add-MetraAskVoiceNormalization -PathKind 'success' -ReasonCode 'ok' -Result (
        Merge-MetraAskLaneIntoResult -Lane $lane -Result ([PSCustomObject]@{
                handoff                      = $handoff
                message                      = [string]$voice.display
                voice                        = $voice
                sessionId                    = [string]$engine.SessionId
                capability                   = $capability
                engine                       = [string]$engine.Engine
                model                        = [string]$engine.Model
                answered                     = [bool]$sem.answered
                answerType                   = [string]$sem.answerType
                evidenceQuality              = [string]$sem.evidenceQuality
                nextStep                     = [string]$sem.nextStep
                continuity                   = $continuity
                secretsScrubbed              = ($pre.Disposition -eq 'scrubbed') -or [bool]$responseScrub.Matched
                secretsNotice                = $notice
                secretsKinds                 = @($pre.Scrub.Kinds) + @($responseScrub.Kinds)
                secretsReason                = $null
                scrubbedPrompt               = $safePrompt
                suggestCapture               = $false
                images                       = @($JournalImages)
                intentClass                  = [string]$intent.IntentClass
                policy                       = [string]$policy.Policy
                policySource                 = [string]$policy.PolicySource
                retentionClass               = [string](Get-MetraProp -Object $policy.Knobs -Name 'retentionClass' -Default 'auto')
                overrideRejected             = [bool]$policy.OverrideRejected
                overrideRejectReason         = [string]$policy.OverrideRejectReason
                reasonCode                   = 'ok'
                conversationExecutionEnabled = $true
                evidenceDepth                = $depth
            })
    )
}
