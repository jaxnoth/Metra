# Policy envelope (ios-conversation-policy p4-telemetry) - observe-only contract.
# Normative retentionClass / executionTarget stay null until retention-exec-target.
# Never copy CE posture-alias knobs (desk/company/deliver/auto) into retentionClass.

function Get-MetraPolicyChoiceReasonCodeRegistry {
    <#
    .SYNOPSIS
        Seed registry for policy-choice reasonCode (not free text).
    #>
    [CmdletBinding()]
    param()

    return @(
        'default_unclear'
        'work_task'
        'requested_artifact'
        'companionship_signal'
        'support_personal'
        'user_lock'
        'incident_override'
    )
}

function Test-MetraPolicyChoiceReasonCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$ReasonCode
    )

    $code = if ($null -eq $ReasonCode) { '' } else { $ReasonCode.Trim() }
    return $code -in (Get-MetraPolicyChoiceReasonCodeRegistry)
}

function Resolve-MetraPolicyEnvelopePolicySource {
    <#
    .SYNOPSIS
        Map Resolve-MetraConversationPolicy PolicySource to envelope policySource.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$PolicySource = '',
        [string]$Policy = ''
    )

    $src = if ($null -eq $PolicySource) { '' } else { $PolicySource.Trim().ToLowerInvariant() }
    if ($src -match 'incident' -or $Policy -eq 'DeskStrict') { return 'incident_override' }
    if ($src -match 'override|user_lock|trusted_override') { return 'user_lock' }
    if ($src -match 'deliver' -or $Policy -eq 'Deliver') { return 'deliver_override' }
    return 'inference'
}

function Resolve-MetraPolicyChoiceReasonCode {
    <#
    .SYNOPSIS
        Registry reasonCode for a policy choice from intent + policy resolution.
    #>
    [CmdletBinding()]
    param(
        $Intent,
        $Policy
    )

    $policyName = [string](Get-MetraProp -Object $Policy -Name 'Policy' -Default 'Auto')
    $policySource = [string](Get-MetraProp -Object $Policy -Name 'PolicySource' -Default '')
    $intentClass = [string](Get-MetraProp -Object $Intent -Name 'IntentClass' -Default 'work')

    if ($policySource -match 'secrets') {
        return 'work_task'
    }
    if ($policyName -eq 'DeskStrict' -or $policySource -match 'incident') {
        return 'incident_override'
    }
    if ($policySource -match 'override|user_lock|trusted_override') {
        return 'user_lock'
    }

    switch -Regex ($intentClass) {
        '^(support_|support$)' { return 'support_personal' }
        '^(companionship|check_in|capability)$' { return 'companionship_signal' }
        '^(artifact_request|creative_request)$' { return 'requested_artifact' }
        '^(authority_write)$' { return 'requested_artifact' }
        '^(work|status_query|component_status|capture)$' { return 'work_task' }
        '^(urgent)$' { return 'incident_override' }
        '^(empty)$' { return 'default_unclear' }
        default {
            if ($policyName -eq 'Auto' -or $policyName -eq 'Desk') {
                if ($intentClass -eq 'work' -or [string]::IsNullOrWhiteSpace($intentClass)) {
                    return 'default_unclear'
                }
            }
            if ($policyName -eq 'Deliver') { return 'requested_artifact' }
            if ($policyName -eq 'Company') { return 'companionship_signal' }
            return 'work_task'
        }
    }
}

function Resolve-MetraRetentionAndExecutionTarget {
    <#
    .SYNOPSIS
        Normative retentionClass + executionTarget from intent/policy (not CE posture aliases).
    #>
    [CmdletBinding()]
    param(
        $Intent,
        $Policy
    )

    $intentClass = [string](Get-MetraProp -Object $Intent -Name 'IntentClass' -Default 'work')
    $policyName = [string](Get-MetraProp -Object $Policy -Name 'Policy' -Default 'Auto')

    $retention = 'normal'
    $exec = 'ops'

    if ($intentClass -match '^intimacy_') {
        $retention = 'refuse'
        $exec = 'ops'
    }
    elseif ($intentClass -match '^support_' -or $intentClass -eq 'companionship') {
        # §3.7: companionship / support_* -> local + ephemeral
        $retention = 'ephemeral'
        $exec = 'local'
    }
    elseif ($policyName -eq 'DeskStrict' -or $intentClass -eq 'urgent') {
        $retention = 'normal'
        $exec = 'ops'
    }

    return [PSCustomObject]@{
        RetentionClass  = $retention
        ExecutionTarget = $exec
    }
}

function New-MetraPolicyEnvelope {
    <#
    .SYNOPSIS
        Build policyEnvelopeVersion 1 envelope (telemetry + normative retention/exec when known).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Policy,
        $Intent,
        [AllowEmptyString()][string]$ConversationId = '',
        $TurnId = $null,
        [ValidateSet('ops-ask', 'vision-ask')]
        [string]$Surface = 'ops-ask',
        [switch]$DeferRetentionExec
    )

    $policyName = [string](Get-MetraProp -Object $Policy -Name 'Policy' -Default 'Auto')
    if ($policyName -eq 'Auto') {
        $policyName = 'Auto'
    }

    $intentConfidence = 0.0
    if ($null -ne $Intent) {
        $intentConfidence = [double](Get-MetraProp -Object $Intent -Name 'Confidence' -Default 0)
    }

    $reasonCode = Resolve-MetraPolicyChoiceReasonCode -Intent $Intent -Policy $Policy
    if (-not (Test-MetraPolicyChoiceReasonCode -ReasonCode $reasonCode)) {
        $reasonCode = 'default_unclear'
    }

    $envelopePolicySource = Resolve-MetraPolicyEnvelopePolicySource `
        -PolicySource ([string](Get-MetraProp -Object $Policy -Name 'PolicySource' -Default '')) `
        -Policy $policyName

    $cid = if ([string]::IsNullOrWhiteSpace($ConversationId)) { $null } else { $ConversationId.Trim() }
    $tid = $TurnId
    if ($null -ne $tid -and $tid -is [string] -and [string]::IsNullOrWhiteSpace([string]$tid)) {
        $tid = $null
    }

    $retention = $null
    $exec = $null
    if (-not $DeferRetentionExec) {
        $re = Resolve-MetraRetentionAndExecutionTarget -Intent $Intent -Policy $Policy
        $retention = [string]$re.RetentionClass
        $exec = [string]$re.ExecutionTarget
    }

    return [PSCustomObject]@{
        policyEnvelopeVersion = 1
        policy                = $policyName
        reasonCode            = $reasonCode
        intentConfidence      = $intentConfidence
        policySource          = $envelopePolicySource
        retentionClass        = $retention
        executionTarget       = $exec
        conversationId        = $cid
        turnId                = $tid
        surface               = $Surface
    }
}

function Test-MetraPolicyEnvelopeContract {
    <#
    .SYNOPSIS
        Validate observe-only envelope shape (p4-telemetry).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Envelope
    )

    if ($null -eq $Envelope) { return $false }
    $ver = [int](Get-MetraProp -Object $Envelope -Name 'policyEnvelopeVersion' -Default 0)
    if ($ver -ne 1) { return $false }
    $policy = [string](Get-MetraProp -Object $Envelope -Name 'policy' -Default '')
    if ($policy -notin @('Desk', 'Company', 'Deliver', 'DeskStrict', 'Auto')) { return $false }
    $reason = [string](Get-MetraProp -Object $Envelope -Name 'reasonCode' -Default '')
    if (-not (Test-MetraPolicyChoiceReasonCode -ReasonCode $reason)) { return $false }
    $ps = [string](Get-MetraProp -Object $Envelope -Name 'policySource' -Default '')
    if ($ps -notin @('inference', 'user_lock', 'incident_override', 'deliver_override')) { return $false }

    # Normative retention/exec must not carry CE posture aliases
    $ret = Get-MetraProp -Object $Envelope -Name 'retentionClass' -Default $null
    $exec = Get-MetraProp -Object $Envelope -Name 'executionTarget' -Default $null
    if ($null -ne $ret) {
        $retStr = [string]$ret
        if ($retStr -in @('desk', 'company', 'deliver', 'auto')) { return $false }
        if ($retStr -notin @('normal', 'light', 'ephemeral', 'refuse')) { return $false }
    }
    if ($null -ne $exec) {
        $execStr = [string]$exec
        if ($execStr -notin @('ops', 'local')) { return $false }
    }
    return $true
}

function Add-MetraAskResultPolicyEnvelope {
    <#
    .SYNOPSIS
        Attach policyEnvelope to an Ask/Vision result. Does not change routing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)]$Envelope
    )

    if ($null -eq $Result) { return $Result }
    $Result | Add-Member -NotePropertyName policyEnvelope -NotePropertyValue $Envelope -Force
    $Result | Add-Member -NotePropertyName intentConfidence -NotePropertyValue (
        [double](Get-MetraProp -Object $Envelope -Name 'intentConfidence' -Default 0)
    ) -Force
    # Top-level policy mirrors envelope for OpsAskWorker; retention/exec stay normative (null in p4).
    if ($Result.PSObject.Properties['policy']) {
        $Result | Add-Member -NotePropertyName policy -NotePropertyValue (
            [string](Get-MetraProp -Object $Envelope -Name 'policy' -Default '')
        ) -Force
    }
    else {
        $Result | Add-Member -NotePropertyName policy -NotePropertyValue (
            [string](Get-MetraProp -Object $Envelope -Name 'policy' -Default '')
        ) -Force
    }
    $Result | Add-Member -NotePropertyName policySource -NotePropertyValue (
        [string](Get-MetraProp -Object $Envelope -Name 'policySource' -Default 'inference')
    ) -Force
    $Result | Add-Member -NotePropertyName policyReasonCode -NotePropertyValue (
        [string](Get-MetraProp -Object $Envelope -Name 'reasonCode' -Default 'default_unclear')
    ) -Force
    # Normative retention/exec from envelope only (never CE posture aliases)
    $Result | Add-Member -NotePropertyName retentionClass -NotePropertyValue (
        Get-MetraProp -Object $Envelope -Name 'retentionClass' -Default $null
    ) -Force
    $Result | Add-Member -NotePropertyName executionTarget -NotePropertyValue (
        Get-MetraProp -Object $Envelope -Name 'executionTarget' -Default $null
    ) -Force
    return $Result
}

function Get-MetraAskPolicyTurnIds {
    <#
    .SYNOPSIS
        conversationId + turnId for Ops Ask envelope (session + next turn index).
    #>
    [CmdletBinding()]
    param(
        [string]$SessionId = '',
        $Continuity = $null
    )

    $cid = if (-not [string]::IsNullOrWhiteSpace($SessionId)) { $SessionId.Trim() } else { $null }
    $prior = 0
    if ($null -ne $Continuity) {
        $prior = [int](Get-MetraProp -Object $Continuity -Name 'totalTurnCount' -Default 0)
    }
    return [PSCustomObject]@{
        ConversationId = $cid
        TurnId         = ($prior + 1)
    }
}
