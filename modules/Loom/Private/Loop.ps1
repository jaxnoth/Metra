# Slice 6 — unattended loop (-UntilDailyGate): one eligible dequeue, run→review, stop at daily gate.

function Get-LoomItemCreatedUtc {
    param([Parameter(Mandatory)]$Item)
    $created = [string](Get-LoomProp -Object $Item -Name 'createdAt' -Default '')
    if ([string]::IsNullOrWhiteSpace($created)) {
        $created = [string](Get-LoomProp -Object $Item -Name 'createdUtc' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($created)) {
        $created = [string](Get-LoomProp -Object $Item -Name 'updatedAt' -Default '')
    }
    return $created
}

function Get-LoomLoopPauseState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    $state = Get-MetraLoomState -Root $Root
    $paused = [bool](Get-LoomProp -Object $state -Name 'loopPaused' -Default $false)
    return [PSCustomObject]@{
        loopPaused  = $paused
        pausedAtUtc = [string](Get-LoomProp -Object $state -Name 'pausedAtUtc' -Default '')
        pauseReason = [string](Get-LoomProp -Object $state -Name 'pauseReason' -Default '')
    }
}

function Set-LoomLoopPauseState {
    [CmdletBinding(DefaultParameterSetName = 'Set')]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory, ParameterSetName = 'Set')][bool]$Paused,
        [Parameter(ParameterSetName = 'Set')][string]$Reason = '',
        [Parameter(Mandatory, ParameterSetName = 'Clear')][switch]$Clear
    )

    $raw = Get-MetraLoomState -Root $Root
    $state = @{}
    foreach ($prop in $raw.PSObject.Properties) {
        $state[[string]$prop.Name] = $prop.Value
    }

    if ($PSCmdlet.ParameterSetName -eq 'Clear' -or -not $Paused) {
        $state['loopPaused'] = $false
        if ($state.ContainsKey('pausedAtUtc')) { $state.Remove('pausedAtUtc') }
        if ($state.ContainsKey('pauseReason')) { $state.Remove('pauseReason') }
    }
    else {
        $state['loopPaused'] = $true
        $state['pausedAtUtc'] = (Get-Date).ToUniversalTime().ToString('o')
        $state['pauseReason'] = [string]$Reason
    }

    Save-MetraLoomState -Root $Root -State ([PSCustomObject]$state)
    return Get-LoomLoopPauseState -Root $Root
}

function Get-LoomPauseAgeDescription {
    param([string]$PausedAtUtc)
    if ([string]::IsNullOrWhiteSpace($PausedAtUtc)) { return 'unknown' }
    try {
        $dt = [datetime]::Parse($PausedAtUtc, $null, [Globalization.DateTimeStyles]::RoundtripKind)
        if ($dt.Kind -eq [DateTimeKind]::Unspecified) {
            $dt = [datetime]::SpecifyKind($dt, [DateTimeKind]::Utc)
        }
        $span = (Get-Date).ToUniversalTime() - $dt.ToUniversalTime()
        if ($span.TotalHours -ge 1) {
            return ('{0:N0}h' -f [math]::Floor($span.TotalHours))
        }
        return ('{0:N0}m' -f [math]::Max(1, [math]::Floor($span.TotalMinutes)))
    }
    catch {
        return 'unknown'
    }
}

function Test-LoomClassificationPresent {
    param([Parameter(Mandatory)]$Item)

    $cls = $Item.classification
    if ($null -eq $cls) {
        return [PSCustomObject]@{ ok = $false; reason = 'missing-classification' }
    }
    if ($cls -is [hashtable]) {
        if ($cls.Count -eq 0) {
            return [PSCustomObject]@{ ok = $false; reason = 'missing-classification' }
        }
        foreach ($prop in @('reversibility', 'crossRoot', 'productionTouch', 'externalSideEffect')) {
            if (-not $cls.ContainsKey($prop)) {
                return [PSCustomObject]@{ ok = $false; reason = "missing-classification-$prop" }
            }
        }
        return [PSCustomObject]@{ ok = $true; reason = '' }
    }
    foreach ($prop in @('reversibility', 'crossRoot', 'productionTouch', 'externalSideEffect')) {
        if ($null -eq (Get-LoomProp -Object $cls -Name $prop -Default $null)) {
            return [PSCustomObject]@{ ok = $false; reason = "missing-classification-$prop" }
        }
    }
    return [PSCustomObject]@{ ok = $true; reason = '' }
}

function Test-LoomUnattendedPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Item
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    $clsCheck = Test-LoomClassificationPresent -Item $Item
    if (-not $clsCheck.ok) {
        [void]$reasons.Add([string]$clsCheck.reason)
    }

    $registry = [string](Get-LoomProp -Object $Item.project -Name 'registryName' -Default '')
    $projectKey = Get-MetraLoomQueueItemProjectKey -Item $Item
    if (-not [string]::IsNullOrWhiteSpace($projectKey) -or -not [string]::IsNullOrWhiteSpace($registry)) {
        $gate = Test-LoomProjectAcceptanceGate -Root $Root -RegistryName $registry -ProjectKey $projectKey
        if ($gate.blocked) {
            [void]$reasons.Add('lane-held')
        }
    }

    if ($reasons.Count -eq 0) {
        $cls = $Item.classification
        if ($cls -is [hashtable]) {
            $classification = $cls
        }
        else {
            $classification = @{
                reversibility      = [string](Get-LoomProp -Object $cls -Name 'reversibility' -Default '')
                crossRoot            = [bool](Get-LoomProp -Object $cls -Name 'crossRoot' -Default $false)
                productionTouch      = [bool](Get-LoomProp -Object $cls -Name 'productionTouch' -Default $false)
                externalSideEffect   = [bool](Get-LoomProp -Object $cls -Name 'externalSideEffect' -Default $false)
            }
        }
        $elig = Test-MetraLoomEligibility -Classification $classification -Project $Item.project -Contract $Item.contract
        foreach ($r in @($elig.reasons)) {
            [void]$reasons.Add([string]$r)
        }
    }

    return [PSCustomObject]@{
        eligible                = ($reasons.Count -eq 0)
        reasons                 = @($reasons)
        unattendedPolicyVersion = 1
    }
}

function Get-LoomEligibleQueuedItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    $busy = @(Get-MetraLoomBusyProjectKeys -Root $Root)
    $items = @(Get-MetraLoomEligibleQueuedForClaim -Root $Root -BusyProjectKeys $busy)
    $eligible = New-Object System.Collections.Generic.List[object]
    foreach ($item in $items) {
        [void]$eligible.Add([PSCustomObject]@{
                item    = $item
                score   = [double](Get-LoomProp -Object $item.scores -Name 'total' -Default 0)
                created = Get-LoomItemCreatedUtc -Item $item
                id      = [string]$item.id
            })
    }
    return @($eligible.ToArray())
}

function Test-LoomInspectEngineTier1Reason {
    param([string]$Reason)
    $tier1 = @(
        'key_missing', 'disabled', 'enterprise_key_missing', 'enterprise_unconfigured',
        'enterprise_forbidden', 'quota', 'billing', 'credentials'
    )
    foreach ($t in $tier1) {
        if ([string]$Reason -eq $t) { return $true }
    }
    if ([string]$Reason -like '*quota*' -or [string]$Reason -like '*billing*') { return $true }
    return $false
}

function Test-LoomInspectEngineHealthy {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    $cap = Invoke-LoomAskCapabilityAdapter -MetraRoot $MetraRoot
    if (-not $cap) {
        return [PSCustomObject]@{
            healthy    = $false
            tier       = 'stop'
            reason     = 'adapter-unavailable'
            message    = 'Ask capability adapter unavailable'
            capability = $null
        }
    }

    $available = [bool](Get-LoomProp -Object $cap -Name 'available' -Default $false)
    $engineHealthy = [bool](Get-LoomProp -Object $cap -Name 'engineHealthy' -Default $false)
    $capReason = [string](Get-LoomProp -Object $cap -Name 'reason' -Default '')

    if ($available -and $engineHealthy -and $capReason -eq 'ok') {
        return [PSCustomObject]@{
            healthy    = $true
            tier       = 'ok'
            reason     = 'ok'
            message    = [string](Get-LoomProp -Object $cap -Name 'message' -Default '')
            capability = $cap
        }
    }

    $tier = if (Test-LoomInspectEngineTier1Reason -Reason $capReason) { 'stop' } else { 'recover' }
    return [PSCustomObject]@{
        healthy    = $false
        tier       = $tier
        reason     = if ($capReason) { $capReason } else { 'engine-unhealthy' }
        message    = [string](Get-LoomProp -Object $cap -Name 'message' -Default '')
        capability = $cap
    }
}

function New-LoomLoopSessionDir {
    param(
        [Parameter(Mandatory)][string]$Root
    )
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $dir = Join-Path (Join-Path $Root 'runs') ("loop-$stamp")
    [void][System.IO.Directory]::CreateDirectory($dir)
    return $dir
}

function Save-LoomLoopSession {
    param(
        [Parameter(Mandatory)][string]$SessionDir,
        [Parameter(Mandatory)][object]$Payload
    )
    $path = Join-Path $SessionDir 'loop.json'
    Write-LoomAtomicUtf8Text -Path $path -Text (($Payload | ConvertTo-Json -Depth 10) + "`n")
    return $path
}

function Write-LoomLoopBlockerReport {
    param(
        [Parameter(Mandatory)][string]$SessionDir,
        [Parameter(Mandatory)][string]$Tier,
        [Parameter(Mandatory)][string]$Class,
        [Parameter(Mandatory)][string]$Message
    )
    $report = [ordered]@{
        schemaVersion    = 1
        tier             = $Tier
        class            = $Class
        message          = $Message
        recoveryAttempts = @()
    }
    $path = Join-Path $SessionDir 'blocker-report.json'
    Write-LoomAtomicUtf8Text -Path $path -Text (($report | ConvertTo-Json -Depth 6) + "`n")
    return $path
}

function Invoke-MetraLoomLoop {
    <#
    .SYNOPSIS
        Slice 6 unattended loop: one eligible queued item through run+review to completed; stop at daily gate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-LoomHostRoot),
        [switch]$DryRun,
        [switch]$Confirm,
        [switch]$UntilDailyGate,
        [scriptblock]$RunOverride
    )

    if (-not $UntilDailyGate) {
        throw 'loom loop requires -UntilDailyGate'
    }

    Initialize-MetraLoomLayout -Root $Root

    $pause = Get-LoomLoopPauseState -Root $Root
    if ($pause.loopPaused) {
        $age = Get-LoomPauseAgeDescription -PausedAtUtc $pause.pausedAtUtc
        if (-not $DryRun) {
            Add-MetraLoomJournalEntry -Root $Root -Entry @{
                itemId  = ''
                from    = 'loop'
                to      = 'paused'
                actor   = 'harness-loop'
                reason  = [string]$pause.pauseReason
                message = "loop-paused:$($pause.pauseReason);age=$age"
            }
        }
        return [PSCustomObject]@{
            outcome     = 'paused'
            loopPaused  = $true
            pauseReason = [string]$pause.pauseReason
            pausedAtUtc = [string]$pause.pausedAtUtc
            pauseAge    = $age
            message     = "Loop paused: $($pause.pauseReason) (${age})"
        }
    }

    if (-not $DryRun -and -not $Confirm) {
        throw 'loom loop requires -Confirm for live execution (or -DryRun for preview).'
    }

    $sessionDir = $null

    if (-not $DryRun) {
        $engine = Test-LoomInspectEngineHealthy -MetraRoot $MetraRoot
        if (-not $engine.healthy -and $engine.tier -eq 'recover') {
            $null = Invoke-LoomInspectEngineRecovery -Probe {
                (Test-LoomInspectEngineHealthy -MetraRoot $MetraRoot).healthy
            } -DelaySeconds @(2, 5, 10)
            $engine = Test-LoomInspectEngineHealthy -MetraRoot $MetraRoot
        }

        if (-not $engine.healthy) {
            $pauseReason = "inspect-$($engine.reason)"
            if ($engine.tier -eq 'stop') {
                if ($Confirm) {
                    $sessionDir = New-LoomLoopSessionDir -Root $Root
                    Set-LoomLoopPauseState -Root $Root -Paused $true -Reason $pauseReason | Out-Null
                    Write-LoomLoopBlockerReport -SessionDir $sessionDir -Tier 'stop' -Class $engine.reason -Message $engine.message | Out-Null
                }
                Add-MetraLoomJournalEntry -Root $Root -Entry @{
                    itemId  = ''
                    from    = 'loop'
                    to      = 'paused'
                    actor   = 'harness-loop'
                    reason  = $pauseReason
                    message = [string]$engine.message
                }
                $pause = Get-LoomLoopPauseState -Root $Root
                $age = Get-LoomPauseAgeDescription -PausedAtUtc $pause.pausedAtUtc
                return [PSCustomObject]@{
                    outcome     = 'engine-stop'
                    loopPaused  = [bool]$Confirm
                    pauseReason = $pauseReason
                    pausedAtUtc = [string]$pause.pausedAtUtc
                    pauseAge    = $age
                    engine      = $engine
                    sessionDir  = $sessionDir
                }
            }
            return [PSCustomObject]@{
                outcome    = 'engine-unhealthy'
                loopPaused = $false
                engine     = $engine
                message    = [string]$engine.message
                sessionDir = $sessionDir
            }
        }
    }
    else {
        $engine = [PSCustomObject]@{ healthy = $true; tier = 'ok'; reason = 'dry-run-skipped' }
    }

    $candidates = @(Get-LoomEligibleQueuedItems -Root $Root)
    if ($DryRun) {
        if (@($candidates).Count -eq 0) {
            return [PSCustomObject]@{
                outcome = 'idle'
                message = 'No eligible queued items'
            }
        }
        $selected = $candidates[0]
        $item = $selected.item
        $policy = Test-LoomUnattendedPolicy -Root $Root -Item $item
        return [PSCustomObject]@{
            outcome        = 'dry-run'
            selectedItemId = [string]$item.id
            score          = $selected.score
            created        = $selected.created
            policy         = $policy
            eligibleCount  = @($candidates).Count
        }
    }

    $claim = Invoke-MetraLoomClaimNextEligible -Root $Root -Actor 'harness-loop' -Reason 'until-daily-gate'
    if (-not $claim.claimed) {
        return [PSCustomObject]@{
            outcome = 'idle'
            message = ('No eligible queued items ({0})' -f [string]$claim.reason)
        }
    }

    $item = $claim.item
    $policy = Test-LoomUnattendedPolicy -Root $Root -Item $item
    $sessionDir = New-LoomLoopSessionDir -Root $Root

    Add-MetraLoomJournalEntry -Root $Root -Entry @{
        itemId  = [string]$item.id
        from    = 'loop'
        to      = 'dequeue'
        actor   = 'harness-loop'
        reason  = 'until-daily-gate'
        message = ("score={0};claim={1}" -f (Get-LoomProp -Object $item.scores -Name 'total' -Default 0), $claim.reason)
    }

    $runResult = $null
    $runError = $null
    try {
        if ($RunOverride) {
            $runResult = & $RunOverride @{
                Root          = $Root
                ItemId        = [string]$item.id
                MetraRoot     = $MetraRoot
                Confirm       = $true
                ChainReview   = $true
                AlreadyClaimed = $true
            }
        }
        else {
            $runResult = Invoke-MetraLoomRun -Root $Root -ItemId ([string]$item.id) -MetraRoot $MetraRoot -Confirm -ChainReview -AlreadyClaimed
        }
    }
    catch {
        $runError = $_
    }

    $finalItem = Get-MetraLoomQueueItem -Root $Root -Id ([string]$item.id)
    $terminal = if ($finalItem) { [string]$finalItem.status } else { 'error' }

    Save-LoomLoopSession -SessionDir $sessionDir -Payload ([ordered]@{
        schemaVersion  = 1
        selectedItemId = [string]$item.id
        policy         = $policy
        engineProbe    = $engine
        startedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
        terminalStatus = $terminal
        runResult      = $runResult
        runError       = if ($runError) { [string]$runError.Exception.Message } else { $null }
    }) | Out-Null

    Add-MetraLoomJournalEntry -Root $Root -Entry @{
        itemId  = [string]$item.id
        from    = 'loop'
        to      = $terminal
        actor   = 'harness-loop'
        reason  = if ($runError) { 'until-daily-gate-error' } else { 'until-daily-gate-complete' }
        message = if ($runError) { [string]$runError.Exception.Message } else { '' }
    }

    if ($runError) {
        throw $runError
    }

    return [PSCustomObject]@{
        outcome        = $terminal
        selectedItemId = [string]$item.id
        sessionDir     = $sessionDir
        runResult      = $runResult
        message        = "Loop finished: $terminal"
    }
}

function Format-LoomLoopPausedIntakeSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    $pause = Get-LoomLoopPauseState -Root $Root
    if (-not $pause.loopPaused) { return '' }

    $age = Get-LoomPauseAgeDescription -PausedAtUtc $pause.pausedAtUtc
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('## Loop paused')
    [void]$sb.AppendLine("Reason: $($pause.pauseReason)")
    [void]$sb.AppendLine("Age: $age")
    if (-not [string]::IsNullOrWhiteSpace($pause.pausedAtUtc)) {
        [void]$sb.AppendLine("Since: $($pause.pausedAtUtc)")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('_Clear pause: edit loom state.json (loopPaused false) or wait for Slice 6b loom loop resume._')
    [void]$sb.AppendLine('')
    return $sb.ToString()
}
