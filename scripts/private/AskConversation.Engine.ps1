# Ask Conversation Engine - policy overlay prompt + typed engine envelope.

function New-MetraConversationPrompt {
    <#
    .SYNOPSIS
        Partner Identity preamble + policy overlay + objective text for the engine (sanitized prompt only).
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
        [switch]$IncidentActive
    )

    $intentClass = [string](Get-MetraProp -Object $Intent -Name 'IntentClass' -Default 'work')
    $policyName = [string](Get-MetraProp -Object $Policy -Name 'Policy' -Default 'Auto')
    $objective = [string](Get-MetraProp -Object $Policy -Name 'ResponseObjective' -Default 'GroundedAnswer')
    $knobs = Get-MetraProp -Object $Policy -Name 'Knobs' -Default $null

    $resolvedPosture = $Posture
    if ([string]::IsNullOrWhiteSpace($resolvedPosture) -and -not [string]::IsNullOrWhiteSpace($policyName) -and $policyName -ne 'Auto') {
        $resolvedPosture = $policyName
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Get-Command New-MetraPartnerIdentityPreamble -ErrorAction SilentlyContinue) {
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
    if ($objective -eq 'OperatorConfirm') {
        [void]$lines.Add('OperatorConfirm: investigate or cite only after operator confirm - not a grounded write.')
    }
    if ($intentClass -eq 'status_query') {
        [void]$lines.Add('Status questions require current health evidence or an explicit inability to verify.')
    }
    if ($intentClass -eq 'check_in') {
        [void]$lines.Add('Brief check-in only - no infrastructure essay.')
    }
    if ($knobs -and -not [bool](Get-MetraProp -Object $knobs -Name 'humor' -Default $false)) {
        [void]$lines.Add('Humor off for this turn.')
    }
    [void]$lines.Add('')
    [void]$lines.Add($Prompt)

    return ($lines -join "`n")
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

