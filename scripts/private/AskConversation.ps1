# Ask Conversation Execution - Batch 1: secrets preflight + voice envelope.
# Intent/policy/engine rewiring lands in later bites. Do not retain raw prompts.

function Normalize-MetraAskInput {
    <#
    .SYNOPSIS
        Trim and normalize Ask prompt text before secrets preflight.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Prompt
    )

    if ($null -eq $Prompt) { return '' }
    $t = [string]$Prompt
    # Normalize newlines; collapse runs of spaces/tabs but keep paragraph breaks.
    $t = $t -replace "`r`n", "`n" -replace "`r", "`n"
    $t = $t.Trim()
    return $t
}

function Test-MetraAskConversationExecutionEnabled {
    <#
    .SYNOPSIS
        Feature flag ask.conversationExecution.enabled (default false until Batch fixtures pass).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $cfg = $null
    $configPath = Get-MetraAskConfigPath -MetraRoot $MetraRoot
    $moduleRoot = Get-MetraRoot
    if ($MetraRoot -eq $moduleRoot) {
        try { $cfg = Get-MetraConfig } catch { $cfg = $null }
    }
    if ($null -eq $cfg -and (Test-Path -LiteralPath $configPath)) {
        try { $cfg = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json } catch { $cfg = $null }
    }
    $ask = Get-MetraProp -Object $cfg -Name 'ask' -Default $null
    $ce = Get-MetraProp -Object $ask -Name 'conversationExecution' -Default $null
    $raw = Get-MetraProp -Object $ce -Name 'enabled' -Default $false
    if ($raw -is [bool]) { return [bool]$raw }
    $s = [string]$raw
    if ($s -match '^(?i)(1|true|yes)$') { return $true }
    return $false
}

function Invoke-MetraAskConversationSecretsPreflight {
    <#
    .SYNOPSIS
        Secrets disposition before intent/policy/evidence/engine. Returns sanitized prompt only.
    .OUTPUTS
        Disposition: refuse | scrubbed | unchanged. Prompt is never the raw secret-bearing original when matched.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Prompt
    )

    $normalized = Normalize-MetraAskInput -Prompt $Prompt
    $scrub = Invoke-MetraAskSecretsScrubText -Text $normalized

    $disposition = 'unchanged'
    $reasonCode = 'secrets_unchanged'
    if ([bool]$scrub.Refuse) {
        $disposition = 'refuse'
        $reasonCode = 'secrets_refuse'
    }
    elseif ([bool]$scrub.Matched) {
        $disposition = 'scrubbed'
        $reasonCode = 'secrets_scrubbed'
    }

    # Downstream may only see approved text - never attach RawPrompt.
    return [PSCustomObject]@{
        Disposition = $disposition
        ReasonCode  = $reasonCode
        Prompt      = [string]$scrub.Text
        Scrub       = $scrub
        Notice      = [string](Get-MetraProp -Object $scrub -Name 'Notice' -Default '')
    }
}

function ConvertTo-MetraAskSpokenText {
    <#
    .SYNOPSIS
        Strip Markdown / routing furniture from spoken channel. Does not remove OperatorConfirm.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    $t = if ($null -eq $Text) { '' } else { [string]$Text }
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }

    # Links [label](url) -> label
    $t = [regex]::Replace($t, '\[([^\]]+)\]\([^)]+\)', '$1')
    # Fenced / inline code markers
    $t = $t -replace '```[a-zA-Z0-9_-]*', '' -replace '```', ''
    $t = $t -replace '`', ''
    # Bold/italic markers (opening and closing; strip leftovers)
    $t = $t -replace '\*\*', '' -replace '__', ''
    $t = [regex]::Replace($t, '\*([^*\n]+)\*', '$1')
    $t = [regex]::Replace($t, '_([^_\n]+)_', '$1')
    $t = $t -replace '\*', '' -replace '(?<!\w)_(?!\w)', ''
    # Heading markers at line starts
    $t = [regex]::Replace($t, '(?m)^\s{0,3}#{1,6}\s+', '')
    # Collapse whitespace
    $t = ($t -replace '[ \t]+', ' ').Trim()
    return $t
}

function Repair-MetraAskSemanticMarkers {
    <#
    .SYNOPSIS
        Ensure required semantic markers survive formatting (OperatorConfirm, not-completed, refusal).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text,
        [string[]]$RequiredMarkers = @()
    )

    $out = if ($null -eq $Text) { '' } else { [string]$Text }
    foreach ($m in @($RequiredMarkers)) {
        if ([string]::IsNullOrWhiteSpace($m)) { continue }
        if ($out -notmatch [regex]::Escape($m)) {
            if ([string]::IsNullOrWhiteSpace($out)) { $out = $m }
            else { $out = "$out $m" }
        }
    }
    return $out.Trim()
}

function New-MetraAskVoiceObject {
    <#
    .SYNOPSIS
        Build filled voice channels; scrub each; enforce non-empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Spoken,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Display,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Durable,
        [string]$FallbackSpoken = 'I could not complete that request.',
        [string]$FallbackDisplay = 'I could not complete that request.',
        [string]$FallbackDurable = 'disposition:empty_voice_fallback'
    )

    $sp = ConvertTo-MetraAskSpokenText -Text $Spoken
    $dp = if ($null -eq $Display) { '' } else { [string]$Display }
    $du = if ($null -eq $Durable) { '' } else { [string]$Durable }

    $spScrub = Invoke-MetraAskSecretsScrubText -Text $sp
    $dpScrub = Invoke-MetraAskSecretsScrubText -Text $dp
    $duScrub = Invoke-MetraAskSecretsScrubText -Text $du

    $spOut = [string]$spScrub.Text
    $dpOut = [string]$dpScrub.Text
    $duOut = [string]$duScrub.Text

    if ([string]::IsNullOrWhiteSpace($spOut)) { $spOut = $FallbackSpoken }
    if ([string]::IsNullOrWhiteSpace($dpOut)) { $dpOut = $FallbackDisplay }
    if ([string]::IsNullOrWhiteSpace($duOut)) { $duOut = $FallbackDurable }

    # Spoken must stay free of Markdown furniture after scrub.
    $spOut = ConvertTo-MetraAskSpokenText -Text $spOut
    if ([string]::IsNullOrWhiteSpace($spOut)) { $spOut = $FallbackSpoken }

    return [PSCustomObject]@{
        spoken  = $spOut.Trim()
        display = $dpOut.Trim()
        durable = $duOut.Trim()
    }
}

function Format-MetraAskVoiceFromEngine {
    <#
    .SYNOPSIS
        Always-filled scrubbed voice for Conversation Execution return paths (Batch 1).
    .NOTES
        PathKind maps acceptance paths: success, refuse, authority, fallback, legacy (flag false).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('success', 'refuse', 'authority', 'fallback', 'legacy')]
        [string]$PathKind,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text = '',

        [string]$DurableDisposition = '',

        [string]$ReasonCode = 'ok',

        [string]$RefuseNotice = ''
    )

    $raw = if ($null -eq $Text) { '' } else { [string]$Text }
    $markers = [System.Collections.Generic.List[string]]::new()
    $spoken = ''
    $display = ''
    $durable = ''
    $fbSp = 'I could not complete that request.'
    $fbDp = 'I could not complete that request.'
    $fbDu = "disposition:$PathKind"

    switch ($PathKind) {
        'refuse' {
            $notice = if (-not [string]::IsNullOrWhiteSpace($RefuseNotice)) {
                $RefuseNotice.Trim()
            }
            else {
                'Private-key material was blocked and not sent to the Ask engine. Rephrase without the key block.'
            }
            $spoken = $notice
            $display = $notice
            $durable = if (-not [string]::IsNullOrWhiteSpace($DurableDisposition)) {
                $DurableDisposition.Trim()
            }
            else {
                "secrets_boundary:refuse:$ReasonCode"
            }
            # Durable must never carry secret material - scrub already applied in New-MetraAskVoiceObject.
            $fbSp = $notice
            $fbDp = $notice
            $fbDu = 'secrets_boundary:refuse'
        }
        'authority' {
            [void]$markers.Add('OperatorConfirm')
            $base = if (-not [string]::IsNullOrWhiteSpace($raw)) { $raw.Trim() } else {
                'OperatorConfirm: confirm any Host write at the desk before I proceed.'
            }
            $spoken = Repair-MetraAskSemanticMarkers -Text $base -RequiredMarkers @($markers)
            $display = Repair-MetraAskSemanticMarkers -Text $base -RequiredMarkers @($markers)
            $durable = if (-not [string]::IsNullOrWhiteSpace($DurableDisposition)) {
                Repair-MetraAskSemanticMarkers -Text $DurableDisposition -RequiredMarkers @($markers)
            }
            else {
                "authority_gate:OperatorConfirm:$ReasonCode"
            }
            $fbSp = 'OperatorConfirm: confirm any Host write at the desk before I proceed.'
            $fbDp = $fbSp
            $fbDu = 'authority_gate:OperatorConfirm'
        }
        'fallback' {
            [void]$markers.Add('not completed')
            $base = if (-not [string]::IsNullOrWhiteSpace($raw)) { $raw.Trim() } else {
                'I could not complete that request (not completed).'
            }
            $spoken = Repair-MetraAskSemanticMarkers -Text $base -RequiredMarkers @($markers)
            $display = Repair-MetraAskSemanticMarkers -Text $base -RequiredMarkers @($markers)
            $durable = if (-not [string]::IsNullOrWhiteSpace($DurableDisposition)) {
                Repair-MetraAskSemanticMarkers -Text $DurableDisposition -RequiredMarkers @('not-completed')
            }
            else {
                "execution_fallback:not-completed:$ReasonCode"
            }
            $fbSp = 'I could not complete that request (not completed).'
            $fbDp = $fbSp
            $fbDu = 'execution_fallback:not-completed'
        }
        'legacy' {
            # Flag false / prior branch - still normalize into filled voice.
            $base = if (-not [string]::IsNullOrWhiteSpace($raw)) { $raw.Trim() } else {
                'No Ask reply text was available.'
            }
            $spoken = $base
            $display = $base
            $durable = if (-not [string]::IsNullOrWhiteSpace($DurableDisposition)) {
                $DurableDisposition.Trim()
            }
            else {
                "legacy_normalize:$ReasonCode"
            }
            $fbSp = 'No Ask reply text was available.'
            $fbDp = $fbSp
            $fbDu = 'legacy_normalize'
        }
        default {
            # success
            $base = if (-not [string]::IsNullOrWhiteSpace($raw)) { $raw.Trim() } else {
                'No answer text.'
            }
            $spoken = $base
            $display = $base
            $durable = if (-not [string]::IsNullOrWhiteSpace($DurableDisposition)) {
                $DurableDisposition.Trim()
            }
            else {
                "success:$ReasonCode"
            }
            $fbSp = 'No answer text.'
            $fbDp = $fbSp
            $fbDu = 'success'
        }
    }

    $voice = New-MetraAskVoiceObject `
        -Spoken $spoken `
        -Display $display `
        -Durable $durable `
        -FallbackSpoken $fbSp `
        -FallbackDisplay $fbDp `
        -FallbackDurable $fbDu

    # Re-assert markers after scrub/spoken strip (authority / fallback).
    if ($markers.Count -gt 0) {
        $durableMarkers = @($markers)
        if ($PathKind -eq 'fallback') {
            $durableMarkers = @('not-completed') + @($markers)
        }
        $voice = [PSCustomObject]@{
            spoken  = (Repair-MetraAskSemanticMarkers -Text $voice.spoken -RequiredMarkers @($markers))
            display = (Repair-MetraAskSemanticMarkers -Text $voice.display -RequiredMarkers @($markers))
            durable = (Repair-MetraAskSemanticMarkers -Text $voice.durable -RequiredMarkers $durableMarkers)
        }
        if ([string]::IsNullOrWhiteSpace($voice.spoken)) {
            $voice = [PSCustomObject]@{ spoken = $fbSp; display = $voice.display; durable = $voice.durable }
        }
        if ([string]::IsNullOrWhiteSpace($voice.display)) {
            $voice = [PSCustomObject]@{ spoken = $voice.spoken; display = $fbDp; durable = $voice.durable }
        }
        if ([string]::IsNullOrWhiteSpace($voice.durable)) {
            $voice = [PSCustomObject]@{ spoken = $voice.spoken; display = $voice.display; durable = $fbDu }
        }
    }

    return $voice
}

function New-MetraAskConversationResult {
    <#
    .SYNOPSIS
        Canonical Conversation Execution result: message == voice.display; filled voice.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Voice,

        [string]$ReasonCode = 'ok',

        [ValidateSet('success', 'refuse', 'authority', 'fallback', 'legacy')]
        [string]$PathKind = 'success',

        [bool]$Answered = $true,

        [bool]$ConversationExecutionEnabled = $true,

        [string]$SecretsDisposition = 'unchanged',

        [string]$Prompt = '',

        [hashtable]$Extra = @{}
    )

    $spoken = [string](Get-MetraProp -Object $Voice -Name 'spoken' -Default '')
    $display = [string](Get-MetraProp -Object $Voice -Name 'display' -Default '')
    $durable = [string](Get-MetraProp -Object $Voice -Name 'durable' -Default '')

    if ([string]::IsNullOrWhiteSpace($spoken) -or
        [string]::IsNullOrWhiteSpace($display) -or
        [string]::IsNullOrWhiteSpace($durable)) {
        $Voice = Format-MetraAskVoiceFromEngine -PathKind $PathKind -Text $display -ReasonCode $ReasonCode
        $spoken = [string]$Voice.spoken
        $display = [string]$Voice.display
        $durable = [string]$Voice.durable
    }

    $result = [ordered]@{
        message                       = $display
        voice                         = [PSCustomObject]@{
            spoken  = $spoken
            display = $display
            durable = $durable
        }
        reasonCode                    = $ReasonCode
        pathKind                      = $PathKind
        answered                      = [bool]$Answered
        conversationExecutionEnabled  = [bool]$ConversationExecutionEnabled
        secretsDisposition            = $SecretsDisposition
        # Approved sanitized prompt only (may be empty on refuse paths that discard work).
        prompt                        = [string]$Prompt
        ok                            = ($PathKind -eq 'success' -or $PathKind -eq 'legacy')
        status                        = $(
            switch ($PathKind) {
                'refuse' { 'refused' }
                'authority' { 'operator_confirm' }
                'fallback' { 'fallback' }
                'legacy' { 'legacy' }
                default { 'ok' }
            }
        )
    }

    foreach ($key in @($Extra.Keys)) {
        $result[$key] = $Extra[$key]
    }

    return [PSCustomObject]$result
}

function Test-MetraAskVoiceContract {
    <#
    .SYNOPSIS
        True when message == voice.display and all voice channels are non-empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Result
    )

    $message = [string](Get-MetraProp -Object $Result -Name 'message' -Default '')
    $voice = Get-MetraProp -Object $Result -Name 'voice' -Default $null
    if ($null -eq $voice) { return $false }
    $spoken = [string](Get-MetraProp -Object $voice -Name 'spoken' -Default '')
    $display = [string](Get-MetraProp -Object $voice -Name 'display' -Default '')
    $durable = [string](Get-MetraProp -Object $voice -Name 'durable' -Default '')

    if ([string]::IsNullOrWhiteSpace($spoken)) { return $false }
    if ([string]::IsNullOrWhiteSpace($display)) { return $false }
    if ([string]::IsNullOrWhiteSpace($durable)) { return $false }
    if ($message -cne $display) { return $false }
    return $true
}

function New-MetraAskConversationBatch1Result {
    <#
    .SYNOPSIS
        Batch 1 helper: secrets preflight then voice envelope for a path kind (no engine).
    .DESCRIPTION
        Used by tests and later rewiring. On secrets refuse, forces PathKind=refuse regardless of requested path.
        Does not invoke intent, policy, evidence, or engine.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Prompt = '',

        [ValidateSet('success', 'refuse', 'authority', 'fallback', 'legacy')]
        [string]$PathKind = 'success',

        [AllowEmptyString()][string]$EngineText = '',

        [string]$ReasonCode = 'ok',

        [string]$DurableDisposition = '',

        [string]$MetraRoot = (Get-MetraRoot)
    )

    $enabled = Test-MetraAskConversationExecutionEnabled -MetraRoot $MetraRoot
    $pre = Invoke-MetraAskConversationSecretsPreflight -Prompt $Prompt

    if ($pre.Disposition -eq 'refuse') {
        $voice = Format-MetraAskVoiceFromEngine `
            -PathKind 'refuse' `
            -RefuseNotice ([string]$pre.Notice) `
            -ReasonCode ([string]$pre.ReasonCode) `
            -DurableDisposition $(if ($DurableDisposition) { $DurableDisposition } else { "secrets_boundary:$($pre.ReasonCode)" })

        return New-MetraAskConversationResult `
            -Voice $voice `
            -ReasonCode ([string]$pre.ReasonCode) `
            -PathKind 'refuse' `
            -Answered:$false `
            -ConversationExecutionEnabled:$enabled `
            -SecretsDisposition 'refuse' `
            -Prompt '' `
            -Extra @{
                secretsRefuse = $true
                secretsReason = [string](Get-MetraProp -Object $pre.Scrub -Name 'Reason' -Default '')
                secretsNotice = [string]$pre.Notice
            }
    }

    $effectivePath = $PathKind
    if (-not $enabled -and $PathKind -eq 'success') {
        # Flag false still normalizes through legacy voice path.
        $effectivePath = 'legacy'
    }

    $textForVoice = if (-not [string]::IsNullOrWhiteSpace($EngineText)) {
        $EngineText
    }
    elseif ($effectivePath -eq 'success' -or $effectivePath -eq 'legacy') {
        # Success/legacy without engine text can acknowledge scrubbed prompt briefly (Batch 1 only).
        if (-not [string]::IsNullOrWhiteSpace([string]$pre.Prompt)) { [string]$pre.Prompt }
        else { 'No answer text.' }
    }
    else { '' }

    $voice = Format-MetraAskVoiceFromEngine `
        -PathKind $effectivePath `
        -Text $textForVoice `
        -ReasonCode $ReasonCode `
        -DurableDisposition $DurableDisposition `
        -RefuseNotice ([string]$pre.Notice)

    $answered = ($effectivePath -eq 'success' -or $effectivePath -eq 'legacy')
    return New-MetraAskConversationResult `
        -Voice $voice `
        -ReasonCode $ReasonCode `
        -PathKind $effectivePath `
        -Answered:$answered `
        -ConversationExecutionEnabled:$enabled `
        -SecretsDisposition ([string]$pre.Disposition) `
        -Prompt ([string]$pre.Prompt)
}
