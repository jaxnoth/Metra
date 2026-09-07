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

