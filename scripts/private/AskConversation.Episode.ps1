# Ephemeral episode boundaries + stale-route protection (ios-conversation-policy stale-episode).

function Test-MetraRetentionClassCompatible {
    <#
    .SYNOPSIS
        Whether a delayed response retentionClass may land on the active turn.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$ResponseRetentionClass = '',
        [AllowEmptyString()][string]$ActiveRetentionClass = ''
    )

    $resp = if ($null -eq $ResponseRetentionClass) { '' } else { $ResponseRetentionClass.Trim().ToLowerInvariant() }
    $active = if ($null -eq $ActiveRetentionClass) { '' } else { $ActiveRetentionClass.Trim().ToLowerInvariant() }

    if ([string]::IsNullOrWhiteSpace($resp) -or [string]::IsNullOrWhiteSpace($active)) {
        # Missing class on either side: accept when ids match (caller still checks ids).
        return $true
    }
    if ($resp -eq $active) { return $true }
    # Ephemeral must not land after the active turn left ephemeral (Desk/normal/refuse).
    if ($resp -eq 'ephemeral' -and $active -ne 'ephemeral') { return $false }
    if ($resp -eq 'refuse') { return $false }
    return $false
}

function Test-MetraAskStaleRoute {
    <#
    .SYNOPSIS
        Drop delayed replies when conversationId/turnId/retention/exec no longer match active.
    .OUTPUTS
        PSCustomObject Accept (bool), ReasonCode, Detail
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$ResponseConversationId = '',
        $ResponseTurnId = $null,
        [AllowEmptyString()][string]$ResponseRetentionClass = '',
        [AllowEmptyString()][string]$ResponseExecutionTarget = '',
        [AllowEmptyString()][string]$ActiveConversationId = '',
        $ActiveTurnId = $null,
        [AllowEmptyString()][string]$ActiveRetentionClass = '',
        [AllowEmptyString()][string]$ActiveExecutionTarget = ''
    )

    $respCid = if ($null -eq $ResponseConversationId) { '' } else { $ResponseConversationId.Trim() }
    $actCid = if ($null -eq $ActiveConversationId) { '' } else { $ActiveConversationId.Trim() }
    $respTid = if ($null -eq $ResponseTurnId) { '' } else { ([string]$ResponseTurnId).Trim() }
    $actTid = if ($null -eq $ActiveTurnId) { '' } else { ([string]$ActiveTurnId).Trim() }

    if ([string]::IsNullOrWhiteSpace($respCid) -or [string]::IsNullOrWhiteSpace($actCid)) {
        return [PSCustomObject]@{
            Accept     = $false
            ReasonCode = 'retention_stale_turn_drop'
            Detail     = 'missing_conversationId'
        }
    }
    if ($respCid -cne $actCid) {
        return [PSCustomObject]@{
            Accept     = $false
            ReasonCode = 'retention_stale_turn_drop'
            Detail     = 'conversationId_mismatch'
        }
    }
    if ([string]::IsNullOrWhiteSpace($respTid) -or [string]::IsNullOrWhiteSpace($actTid)) {
        return [PSCustomObject]@{
            Accept     = $false
            ReasonCode = 'retention_stale_turn_drop'
            Detail     = 'missing_turnId'
        }
    }
    if ($respTid -cne $actTid) {
        return [PSCustomObject]@{
            Accept     = $false
            ReasonCode = 'retention_stale_turn_drop'
            Detail     = 'turnId_mismatch'
        }
    }

    if (-not (Test-MetraRetentionClassCompatible `
            -ResponseRetentionClass $ResponseRetentionClass `
            -ActiveRetentionClass $ActiveRetentionClass)) {
        return [PSCustomObject]@{
            Accept     = $false
            ReasonCode = 'retention_stale_turn_drop'
            Detail     = 'retentionClass_incompatible'
        }
    }

    $respExec = if ($null -eq $ResponseExecutionTarget) { '' } else { $ResponseExecutionTarget.Trim().ToLowerInvariant() }
    $actExec = if ($null -eq $ActiveExecutionTarget) { '' } else { $ActiveExecutionTarget.Trim().ToLowerInvariant() }
    if (-not [string]::IsNullOrWhiteSpace($respExec) -and -not [string]::IsNullOrWhiteSpace($actExec) -and $respExec -ne $actExec) {
        return [PSCustomObject]@{
            Accept     = $false
            ReasonCode = 'retention_stale_turn_drop'
            Detail     = 'executionTarget_mismatch'
        }
    }

    return [PSCustomObject]@{
        Accept     = $true
        ReasonCode = 'ok'
        Detail     = 'match'
    }
}

function New-MetraEphemeralEpisode {
    <#
    .SYNOPSIS
        In-memory ephemeral episode state (support/companionship). No durable body store.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConversationId,
        [datetime]$StartedAt = [datetime]::UtcNow,
        [datetime]$LastActivityAt = [datetime]::UtcNow
    )

    return [PSCustomObject]@{
        ConversationId  = $ConversationId.Trim()
        StartedAtUtc    = $StartedAt.ToUniversalTime()
        LastActivityUtc = $LastActivityAt.ToUniversalTime()
        Active          = $true
        EndReason       = $null
    }
}

function Test-MetraEphemeralEpisodeEnded {
    <#
    .SYNOPSIS
        Whether an ephemeral episode must end under normative boundaries.
    .NOTES
        Ends on: leave support/companionship, leave Company (incl DeskStrict), 15m idle,
        background, explicit clear/new session.
    #>
    [CmdletBinding()]
    param(
        $Episode,
        [AllowEmptyString()][string]$IntentClass = '',
        [AllowEmptyString()][string]$Policy = '',
        [datetime]$NowUtc = [datetime]::UtcNow,
        [switch]$AppBackgrounded,
        [switch]$ExplicitClear
    )

    if ($null -eq $Episode) {
        return [PSCustomObject]@{
            Ended    = $true
            EndReason = 'no_episode'
        }
    }
    if (-not [bool](Get-MetraProp -Object $Episode -Name 'Active' -Default $false)) {
        return [PSCustomObject]@{
            Ended     = $true
            EndReason = [string](Get-MetraProp -Object $Episode -Name 'EndReason' -Default 'inactive')
        }
    }

    if ($ExplicitClear) {
        return [PSCustomObject]@{ Ended = $true; EndReason = 'explicit_clear' }
    }
    if ($AppBackgrounded) {
        return [PSCustomObject]@{ Ended = $true; EndReason = 'background' }
    }

    $policyName = if ($null -eq $Policy) { '' } else { $Policy.Trim() }
    if ($policyName -in @('Desk', 'DeskStrict', 'Deliver') -or $policyName -eq 'Auto') {
        # Leaving Company posture ends ephemeral episode when policy is known non-Company.
        if ($policyName -in @('Desk', 'DeskStrict', 'Deliver')) {
            return [PSCustomObject]@{ Ended = $true; EndReason = 'leave_company' }
        }
    }

    $ic = if ($null -eq $IntentClass) { '' } else { $IntentClass.Trim().ToLowerInvariant() }
    $stillRelational = ($ic -match '^support_') -or ($ic -eq 'companionship') -or ($ic -eq 'check_in')
    if (-not [string]::IsNullOrWhiteSpace($ic) -and -not $stillRelational) {
        return [PSCustomObject]@{ Ended = $true; EndReason = 'leave_support' }
    }

    $last = Get-MetraProp -Object $Episode -Name 'LastActivityUtc' -Default $null
    if ($null -ne $last) {
        $lastDt = [datetime]$last
        if ($lastDt.Kind -ne [DateTimeKind]::Utc) { $lastDt = $lastDt.ToUniversalTime() }
        $idle = $NowUtc.ToUniversalTime() - $lastDt
        if ($idle.TotalMinutes -ge 15) {
            return [PSCustomObject]@{ Ended = $true; EndReason = 'idle_15m' }
        }
    }

    return [PSCustomObject]@{ Ended = $false; EndReason = $null }
}

function Test-MetraEphemeralInFlightAfterBackground {
    <#
    .SYNOPSIS
        Acceptance edge: ephemeral Ask in flight, app backgrounds, episode ends,
        HTTP may finish, but display must be impossible (stale-route drop).
    .NOTES
        Models the iOS contract: background clears active turn correlation and ends
        the ephemeral episode; late response with prior turn ids must not Accept.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConversationId,
        [Parameter(Mandatory)]$TurnId,
        [ValidateSet('ephemeral', 'normal', 'light', 'refuse')]
        [string]$ResponseRetentionClass = 'ephemeral',
        [ValidateSet('local', 'ops')]
        [string]$ResponseExecutionTarget = 'local'
    )

    $ep = New-MetraEphemeralEpisode -ConversationId $ConversationId
    $ended = Test-MetraEphemeralEpisodeEnded `
        -Episode $ep `
        -Policy 'Company' `
        -IntentClass 'support_stress' `
        -AppBackgrounded
    if (-not $ended.Ended) {
        return [PSCustomObject]@{
            DisplayAllowed = $true
            ReasonCode     = 'episode_still_active'
            Detail         = 'background_did_not_end_episode'
            EpisodeEnded   = $false
        }
    }

    # iOS invalidateOnBackground clears activeTurn - no live correlation remains.
    $stale = Test-MetraAskStaleRoute `
        -ResponseConversationId $ConversationId `
        -ResponseTurnId $TurnId `
        -ResponseRetentionClass $ResponseRetentionClass `
        -ResponseExecutionTarget $ResponseExecutionTarget `
        -ActiveConversationId '' `
        -ActiveTurnId $null `
        -ActiveRetentionClass '' `
        -ActiveExecutionTarget ''

    return [PSCustomObject]@{
        DisplayAllowed = [bool]$stale.Accept
        ReasonCode     = [string]$stale.ReasonCode
        Detail         = [string]$stale.Detail
        EpisodeEnded   = $true
        EndReason      = [string]$ended.EndReason
    }
}

function Update-MetraEphemeralEpisode {
    <#
    .SYNOPSIS
        Touch or end an ephemeral episode; returns updated episode object.
    #>
    [CmdletBinding()]
    param(
        $Episode,
        [AllowEmptyString()][string]$IntentClass = '',
        [AllowEmptyString()][string]$Policy = '',
        [datetime]$NowUtc = [datetime]::UtcNow,
        [switch]$AppBackgrounded,
        [switch]$ExplicitClear,
        [switch]$TouchActivity
    )

    if ($null -eq $Episode) { return $null }

    $check = Test-MetraEphemeralEpisodeEnded `
        -Episode $Episode `
        -IntentClass $IntentClass `
        -Policy $Policy `
        -NowUtc $NowUtc `
        -AppBackgrounded:$AppBackgrounded `
        -ExplicitClear:$ExplicitClear

    if ($check.Ended) {
        $Episode | Add-Member -NotePropertyName Active -NotePropertyValue $false -Force
        $Episode | Add-Member -NotePropertyName EndReason -NotePropertyValue ([string]$check.EndReason) -Force
        return $Episode
    }

    if ($TouchActivity) {
        $Episode | Add-Member -NotePropertyName LastActivityUtc -NotePropertyValue $NowUtc.ToUniversalTime() -Force
    }
    return $Episode
}
