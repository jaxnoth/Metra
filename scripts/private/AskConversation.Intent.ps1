# Ask Conversation Intent - deterministic intent class + confidence (sanitized prompt only).

function Resolve-MetraAskIntent {
    <#
    .SYNOPSIS
        Deterministic Ask intent class + confidence. Operates on sanitized prompt only.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Prompt = '',
        [double]$RouteScore = 0
    )

    $q = if ($null -eq $Prompt) { '' } else { $Prompt.Trim() }
    $source = 'heuristic'
    $confidence = 0.55
    $intentClass = 'work'
    $notes = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace($q)) {
        return [PSCustomObject]@{
            IntentClass = 'empty'
            Confidence  = 1.0
            Source      = 'empty'
            Notes       = @('empty_prompt')
        }
    }

    if (Get-Command Test-MetraAskAuthorityIntent -ErrorAction SilentlyContinue) {
        if (Test-MetraAskAuthorityIntent -Prompt $q) {
            return [PSCustomObject]@{
                IntentClass = 'authority_write'
                Confidence  = 0.9
                Source      = 'authority_detector'
                Notes       = @('authority_requires_confirm')
            }
        }
    }

    if (Get-Command Test-MetraAskParkOrSaveIntent -ErrorAction SilentlyContinue) {
        if (Test-MetraAskParkOrSaveIntent -Prompt $q) {
            return [PSCustomObject]@{
                IntentClass = 'capture'
                Confidence  = 0.85
                Source      = 'capture_detector'
                Notes       = @('capture_phrase_only')
            }
        }
    }

    if (Get-Command Test-MetraDeskGreeting -ErrorAction SilentlyContinue) {
        if (Test-MetraDeskGreeting -Query $q) {
            return [PSCustomObject]@{
                IntentClass = 'check_in'
                Confidence  = 0.95
                Source      = 'greeting_detector'
                Notes       = @('social_greeting')
            }
        }
    }

    # Vocative Metra is a check-in cue (plan fixture: "How are today Metra?") even when "you" is omitted.
    if ($q -match '(?i)\b(hi|hello|hey)\b[,!]?\s*metra\b' `
            -or $q -match '(?i)\bmetra\b[,!]?\s*(hi|hello|hey)\b' `
            -or $q -match '(?i)\bhow are( you)?(\s+today)?\b[,!]?\s*metra\b' `
            -or $q -match '(?i)\bmetra\b[,!]?\s*how are( you)?(\s+today)?\b' `
            -or $q -match '(?i)\b(checking in|check[- ]?in)\b[,!]?\s*(with\s+)?metra\b') {
        return [PSCustomObject]@{
            IntentClass = 'check_in'
            Confidence  = 0.85
            Source      = $source
            Notes       = @('check_in_address_metra')
        }
    }

    if ($q -match '(?i)\b(how are you|how.s it going|checking in|check[- ]?in)\b') {
        return [PSCustomObject]@{
            IntentClass = 'check_in'
            Confidence  = 0.8
            Source      = $source
            Notes       = @('check_in_phrase')
        }
    }

    if ($q -match '(?i)\b(what can you do|what do you (support|handle)|capabilities|what are you|who are you)\b') {
        return [PSCustomObject]@{
            IntentClass = 'capability'
            Confidence  = 0.85
            Source      = $source
            Notes       = @('capability_phrase')
        }
    }

    if (Get-Command Test-MetraAskOpsStatusIntent -ErrorAction SilentlyContinue) {
        if (Test-MetraAskOpsStatusIntent -Prompt $q) {
            return [PSCustomObject]@{
                IntentClass = 'status_query'
                Confidence  = 0.88
                Source      = 'ops_status_detector'
                Notes       = @('ops_status')
            }
        }
    }

    if ($q -match '(?i)\b(running well|healthy|health check|are you (up|ok|online)|is .+ (working|down|up))\b') {
        $intentClass = 'status_query'
        $confidence = 0.8
        [void]$notes.Add('status_phrase')
        if ($q -match '(?i)\b(tickettracker|orion|colleague|brightspace|jitterbit)\b') {
            $intentClass = 'component_status'
            $confidence = 0.82
            [void]$notes.Add('component_named')
        }
        return [PSCustomObject]@{
            IntentClass = $intentClass
            Confidence  = $confidence
            Source      = $source
            Notes       = @($notes)
        }
    }

    # Intimacy refuse bands (no model send; retention refuse)
    if ($q -match '(?i)\b(be my (girl|boy)friend|dating roleplay|i love you|make love|sexual|erotic|nsfw)\b' `
            -or $q -match '(?i)\b(act as|pretend (to be|you.?re)|roleplay as)\b.+\b(ani|girlfriend|boyfriend|lover)\b') {
        $band = 'intimacy_romance'
        if ($q -match '(?i)\b(sexual|erotic|nsfw|make love)\b') { $band = 'intimacy_sexual' }
        return [PSCustomObject]@{
            IntentClass = $band
            Confidence  = 0.92
            Source      = $source
            Notes       = @('intimacy_refuse')
        }
    }
    if ($q -match '(?i)\b(be ani|you are ani|act like ani)\b') {
        return [PSCustomObject]@{
            IntentClass = 'intimacy_romance'
            Confidence  = 0.9
            Source      = $source
            Notes       = @('identity_swap_refuse')
        }
    }

    # Urgent cues (evidence only - DeskStrict still requires IncidentActive)
    if ($q -match '(?i)\b(outage|sev[- ]?[01]|p[01]\b|production down|page me|war room|active incident)\b') {
        return [PSCustomObject]@{
            IntentClass = 'urgent'
            Confidence  = 0.85
            Source      = $source
            Notes       = @('urgent_phrase')
        }
    }

    # Personal support (support_*) - before generic companionship
    if ($q -match '(?i)\b(i(''|a)?m (stressed|lonely|overwhelmed|anxious|depressed)|feeling (down|alone|hopeless)|need (to talk|someone to talk)|having a hard time)\b') {
        $label = 'support_personal'
        if ($q -match '(?i)\b(stress|stressed|overwhelmed|anxious)\b') { $label = 'support_stress' }
        if ($q -match '(?i)\b(lonely|alone|isolated)\b') { $label = 'support_lonely' }
        return [PSCustomObject]@{
            IntentClass = $label
            Confidence  = 0.8
            Source      = $source
            Notes       = @('support_phrase')
        }
    }

    # Companionship / warm chat (not check_in greeting)
    if ($q -match '(?i)\b(just (wanted to )?chat|keep me company|hang out|how was your day|what.?s new with you)\b') {
        return [PSCustomObject]@{
            IntentClass = 'companionship'
            Confidence  = 0.78
            Source      = $source
            Notes       = @('companionship_phrase')
        }
    }

    # Artifact request (Deliver) vs explanatory "tell me about"
    # Prefer Desk for about/explain/how does; Deliver for write/tell me a / generate / draft.
    $explainDominant = ($q -match '(?i)\b(tell me about|explain|how does|what is|what are)\b')
    $artifactCue = ($q -match '(?i)\b(write|draft|generate|create|compose|make)\b.+\b(email|readme|proposal|script|slogan|poem|song|joke|story)\b' `
            -or $q -match '(?i)\b(tell|give|write) me a(n)?\b.+\b(story|poem|song|joke|email|readme)\b' `
            -or $q -match '(?i)^(write|draft|generate)\b.+\b(readme|email|proposal)\b')
    if ($artifactCue -and -not $explainDominant) {
        return [PSCustomObject]@{
            IntentClass = 'artifact_request'
            Confidence  = 0.86
            Source      = $source
            Notes       = @('artifact_phrase')
        }
    }
    # "Tell me a joke about SQL" is artifact; "Tell me about SQL injection" is work/question
    if ($q -match '(?i)^tell me a(n)?\b' -and -not $explainDominant) {
        return [PSCustomObject]@{
            IntentClass = 'artifact_request'
            Confidence  = 0.84
            Source      = $source
            Notes       = @('tell_me_a_artifact')
        }
    }

    if ($RouteScore -ge 2) {
        $confidence = [Math]::Min(0.9, 0.55 + (0.05 * [Math]::Min(6, [int]$RouteScore)))
        [void]$notes.Add('routed_work')
    }

    return [PSCustomObject]@{
        IntentClass = 'work'
        Confidence  = $confidence
        Source      = $source
        Notes       = @($notes)
    }
}
