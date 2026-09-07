# Ask Conversation Policy - knobs, hierarchy, evidence depth ceiling, health freshness.

function Get-MetraConversationPolicyKnobs {
    <#
    .SYNOPSIS
        Persona knobs for a resolved policy posture (no kernel re-host).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DeskStrict', 'Desk', 'Company', 'Deliver', 'Auto')]
        [string]$Policy
    )

    switch ($Policy) {
        'DeskStrict' {
            return [PSCustomObject]@{
                warmth            = 0
                humor             = $false
                maxClarifications = 0
                silenceOk         = $false
                plainEnglish      = $true
                retentionClass    = 'desk'
            }
        }
        'Deliver' {
            return [PSCustomObject]@{
                warmth            = 0
                humor             = $false
                maxClarifications = 0
                silenceOk         = $false
                plainEnglish      = $true
                retentionClass    = 'deliver'
            }
        }
        'Company' {
            return [PSCustomObject]@{
                warmth            = 1
                humor             = $true
                maxClarifications = 1
                silenceOk         = $true
                plainEnglish      = $true
                retentionClass    = 'company'
            }
        }
        'Desk' {
            return [PSCustomObject]@{
                warmth            = 0
                humor             = $false
                maxClarifications = 1
                silenceOk         = $false
                plainEnglish      = $true
                retentionClass    = 'desk'
            }
        }
        default {
            return [PSCustomObject]@{
                warmth            = 0
                humor             = $false
                maxClarifications = 1
                silenceOk         = $false
                plainEnglish      = $true
                retentionClass    = 'auto'
            }
        }
    }
}

function Resolve-MetraConversationPolicy {
    <#
    .SYNOPSIS
        Server-side policy trust hierarchy. Clients cannot weaken DeskStrict / hard gates.
    #>
    [CmdletBinding()]
    param(
        $Intent,
        [string]$ClientHint = '',
        [string]$HeaderClient = '',
        [string]$BodyClient = '',
        [string]$RequestedPolicy = '',
        [bool]$TrustedClientContext = $false,
        [bool]$IsLoopback = $false,
        [bool]$IncidentActive = $false,
        [string]$ServerEndpointPolicy = ''
    )

    $intentClass = [string](Get-MetraProp -Object $Intent -Name 'IntentClass' -Default 'work')
    $overrideRejected = $false
    $overrideRejectReason = $null
    $policySource = 'intent_auto'
    $policy = 'Auto'

    # Intent-derived Auto baseline
    switch ($intentClass) {
        'check_in' { $policy = 'Company'; $policySource = 'intent_check_in' }
        'capability' { $policy = 'Company'; $policySource = 'intent_capability' }
        'capture' { $policy = 'Desk'; $policySource = 'intent_capture' }
        'authority_write' { $policy = 'Deliver'; $policySource = 'intent_authority' }
        'status_query' { $policy = 'Desk'; $policySource = 'intent_status' }
        'component_status' { $policy = 'Desk'; $policySource = 'intent_component' }
        default { $policy = 'Auto'; $policySource = 'intent_auto' }
    }

    # Header/body mismatch - descriptive claims only; reject override authority
    $headerNorm = if ([string]::IsNullOrWhiteSpace($HeaderClient)) { '' } else { $HeaderClient.Trim().ToLowerInvariant() }
    $bodyNorm = if ([string]::IsNullOrWhiteSpace($BodyClient)) { '' } else { $BodyClient.Trim().ToLowerInvariant() }
    if ($headerNorm -and $bodyNorm -and $headerNorm -ne $bodyNorm) {
        $overrideRejected = $true
        $overrideRejectReason = 'policy_override_client_mismatch'
    }

    $canOverride = $TrustedClientContext -or $IsLoopback
    $req = if ([string]::IsNullOrWhiteSpace($RequestedPolicy)) { '' } else { $RequestedPolicy.Trim() }
    $allowedReq = @('DeskStrict', 'Desk', 'Company', 'Deliver', 'Auto')
    if ($req -and $req -in $allowedReq) {
        if (-not $canOverride -or $overrideRejectReason -eq 'policy_override_client_mismatch') {
            $overrideRejected = $true
            if (-not $overrideRejectReason) { $overrideRejectReason = 'policy_override_untrusted' }
        }
        else {
            # Overrides may only tighten (or equal), never relax DeskStrict/incident
            $rank = @{
                DeskStrict = 40
                Deliver    = 30
                Desk       = 20
                Company    = 10
                Auto       = 0
            }
            $cur = [int]$rank[$policy]
            $nxt = [int]$rank[$req]
            if ($nxt -ge $cur) {
                $policy = $req
                $policySource = 'trusted_override'
            }
            else {
                $overrideRejected = $true
                $overrideRejectReason = 'policy_override_relax_rejected'
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ServerEndpointPolicy) -and $ServerEndpointPolicy -in $allowedReq) {
        $rank = @{ DeskStrict = 40; Deliver = 30; Desk = 20; Company = 10; Auto = 0 }
        if ([int]$rank[$ServerEndpointPolicy] -ge [int]$rank[$policy]) {
            $policy = $ServerEndpointPolicy
            $policySource = 'server_endpoint'
        }
    }

    # Incident / DeskStrict from trusted sources only (caller must set IncidentActive)
    if ($IncidentActive) {
        $policy = 'DeskStrict'
        $policySource = 'trusted_incident'
    }

    # Natural language "incident" in clientHint alone does not activate DeskStrict (no-op here).

    if ($intentClass -eq 'authority_write' -and $policy -eq 'Deliver') {
        # Deliver changes objective, not authority - still OperatorConfirm downstream
        $policySource = if ($policySource -eq 'intent_authority') { $policySource } else { $policySource }
    }

    $knobs = Get-MetraConversationPolicyKnobs -Policy $policy
    if ($policy -eq 'DeskStrict') {
        $knobs = Get-MetraConversationPolicyKnobs -Policy 'DeskStrict'
    }

    return [PSCustomObject]@{
        Policy               = $policy
        PolicySource         = $policySource
        Knobs                = $knobs
        OverrideRejected     = [bool]$overrideRejected
        OverrideRejectReason = $overrideRejectReason
        ClientHint           = $(if ($ClientHint) { $ClientHint.Trim().ToLowerInvariant() } else { '' })
        TrustedClientContext = [bool]$TrustedClientContext
        IsLoopback           = [bool]$IsLoopback
        IncidentActive       = [bool]$IncidentActive
        ResponseObjective    = $(
            if ($intentClass -eq 'authority_write') { 'OperatorConfirm' }
            elseif ($policy -eq 'DeskStrict') { 'GroundedAnswer' }
            elseif ($intentClass -eq 'capture') { 'Capture' }
            elseif ($intentClass -eq 'check_in') { 'Clarify' }
            else { 'GroundedAnswer' }
        )
    }
}

function Resolve-MetraAskEvidenceDepth {
    <#
    .SYNOPSIS
        Evidence depth ceiling from intent (may return less later; never more than ceiling).
    #>
    [CmdletBinding()]
    param(
        $Intent,
        $Policy,
        [double]$IntentConfidence = 0.5
    )

    $intentClass = [string](Get-MetraProp -Object $Intent -Name 'IntentClass' -Default 'work')
    $conf = if ($null -ne (Get-MetraProp -Object $Intent -Name 'Confidence' -Default $null)) {
        [double](Get-MetraProp -Object $Intent -Name 'Confidence' -Default 0.5)
    }
    else { [double]$IntentConfidence }

    $ceiling = 'full'
    switch ($intentClass) {
        'check_in' { $ceiling = 'capability_only' }
        'capability' { $ceiling = 'capability_only' }
        'status_query' { $ceiling = 'capability_only' }
        'component_status' { $ceiling = 'route_summary' }
        'capture' { $ceiling = 'none' }
        'authority_write' { $ceiling = 'route_summary' }
        'empty' { $ceiling = 'none' }
        default { $ceiling = 'full' }
    }

    if ($conf -lt 0.45 -and $ceiling -eq 'full') {
        $ceiling = 'route_summary'
    }

    $policyName = [string](Get-MetraProp -Object $Policy -Name 'Policy' -Default 'Auto')
    if ($policyName -eq 'DeskStrict' -and $ceiling -eq 'full') {
        $ceiling = 'route_summary'
    }

    return [PSCustomObject]@{
        Depth   = $ceiling
        Ceiling = $ceiling
        Reason  = "intent:$intentClass;policy:$policyName;conf=$conf"
    }
}

function Test-MetraAskHealthObservationCurrent {
    <#
    .SYNOPSIS
        Source-owned freshness: affirmative health only when source marks current or inside its window.
    .NOTES
        Missing freshness metadata => unverifiable (false). No universal timeout here.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Health)

    if ($null -eq $Health) { return $false }

    $mark = Get-MetraProp -Object $Health -Name 'isCurrent' -Default $null
    if ($null -eq $mark) { $mark = Get-MetraProp -Object $Health -Name 'current' -Default $null }
    if ($null -eq $mark) { $mark = Get-MetraProp -Object $Health -Name 'fresh' -Default $null }
    if ($mark -is [bool]) { return [bool]$mark }
    if ("$mark" -match '^(?i)(1|true|yes)$') { return $true }
    if ("$mark" -match '^(?i)(0|false|no)$') { return $false }

    $until = [string](Get-MetraProp -Object $Health -Name 'freshUntilUtc' -Default '')
    if (-not $until) { $until = [string](Get-MetraProp -Object $Health -Name 'FreshUntilUtc' -Default '') }
    if ($until) {
        try {
            $dt = [datetime]::Parse($until, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if ($dt.Kind -eq [DateTimeKind]::Unspecified) { $dt = [DateTime]::SpecifyKind($dt, [DateTimeKind]::Utc) }
            return ([datetime]::UtcNow -le $dt.ToUniversalTime())
        }
        catch { }
    }

    $windowSec = Get-MetraProp -Object $Health -Name 'freshnessWindowSeconds' -Default $null
    $obs = [string](Get-MetraProp -Object $Health -Name 'observationTimestamp' -Default '')
    if (-not $obs) { $obs = [string](Get-MetraProp -Object $Health -Name 'ObservationTimestamp' -Default '') }
    if ($null -ne $windowSec -and "$windowSec" -match '^\d+$' -and $obs) {
        try {
            $obsDt = [datetime]::Parse($obs, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
            $age = ([datetime]::UtcNow - $obsDt).TotalSeconds
            return ($age -ge 0 -and $age -le [double]$windowSec)
        }
        catch { }
    }

    return $false
}

