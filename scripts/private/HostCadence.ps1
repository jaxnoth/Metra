# MetraHost-owned Yarn/Loom Pulse + Daily cadence (state + tick).
# Stage execution stays in Invoke-MetraYarnLoomSchedule. Host never exits on codes 1-4.

function Get-MetraHostCadenceStatePath {
    [CmdletBinding()]
    param([string]$MetraRoot)
    return (Join-Path (Get-MetraMachineDataRoot -MetraRoot $MetraRoot) 'host-cadence.json')
}

function Resolve-MetraHostCadenceStatePath {
    <#
    .SYNOPSIS
        Prefer explicit -Path; otherwise derive host-cadence.json under the MetraRoot-aware data root.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }
    return Get-MetraHostCadenceStatePath -MetraRoot $MetraRoot
}

function New-MetraHostCadenceState {
    [CmdletBinding()]
    param()
    return [ordered]@{
        schemaVersion          = 1
        enabled                = $false
        pulseEveryMinutes      = 15
        dailyAtLocal           = '02:00'
        nextPulseDueUtc        = $null
        lastDailyLocalDate     = $null
        lastDailyStartedUtc    = $null
        lastDailyCompletedUtc  = $null
        lastDailyOutcome       = $null
        lastPulseStartedUtc    = $null
        lastPulseCompletedUtc  = $null
        lastPulseOutcome       = $null
        pendingPulse           = $false
        pendingDaily           = $false
        activeRunKind          = $null
    }
}

function ConvertTo-MetraHostCadenceUtc {
    <#
    .SYNOPSIS
        Normalize cadence UTC stamps. ConvertFrom-Json turns ...Z ISO strings into
        Unspecified DateTime with UTC wall-clock digits; ToUniversalTime would wrongly
        treat those as local. Prefer round-trip UTC strings in state.
    #>
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        $dt = [datetime]$Value
        switch ($dt.Kind) {
            ([DateTimeKind]::Utc) { return $dt }
            ([DateTimeKind]::Local) { return $dt.ToUniversalTime() }
            default {
                # Unspecified from JSON ISO-with-Z: keep wall clock as UTC.
                return [datetime]::SpecifyKind($dt, [DateTimeKind]::Utc)
            }
        }
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        $parsed = [datetime]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if ($parsed.Kind -eq [DateTimeKind]::Unspecified) {
            return [datetime]::SpecifyKind($parsed, [DateTimeKind]::Utc)
        }
        return $parsed.ToUniversalTime()
    }
    catch {
        return $null
    }
}

function ConvertTo-MetraHostCadenceUtcString {
    [CmdletBinding()]
    param($Value)

    $utc = ConvertTo-MetraHostCadenceUtc -Value $Value
    if ($null -eq $utc) { return $null }
    return $utc.ToUniversalTime().ToString('o')
}

function Read-MetraHostCadenceState {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot

    $defaults = New-MetraHostCadenceState
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$defaults
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]$defaults
        }
        $parsed = $raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Host cadence state unreadable ($($_.Exception.Message)); using defaults."
        return [pscustomobject]$defaults
    }

    $utcKeys = @(
        'nextPulseDueUtc'
        'lastDailyStartedUtc'
        'lastDailyCompletedUtc'
        'lastPulseStartedUtc'
        'lastPulseCompletedUtc'
    )
    $o = [ordered]@{}
    foreach ($key in $defaults.Keys) {
        $val = Get-MetraProp -Object $parsed -Name $key -Default $defaults[$key]
        if ($utcKeys -contains $key) {
            $val = ConvertTo-MetraHostCadenceUtcString -Value $val
        }
        $o[$key] = $val
    }
    if ([int]$o.schemaVersion -lt 1) { $o.schemaVersion = 1 }
    $every = [int]$o.pulseEveryMinutes
    if ($every -lt 5 -or $every -gt 120) { $o.pulseEveryMinutes = 15 }
    if ([string]::IsNullOrWhiteSpace([string]$o.dailyAtLocal)) { $o.dailyAtLocal = '02:00' }
    return [pscustomobject]$o
}

function Save-MetraHostCadenceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [string]$Path,
        [string]$MetraRoot
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot

    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $json = ($State | ConvertTo-Json -Depth 6)
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8)
}

function Initialize-MetraHostCadenceState {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot

    if (Test-Path -LiteralPath $Path) {
        return Read-MetraHostCadenceState -Path $Path -MetraRoot $MetraRoot
    }
    $state = [pscustomobject](New-MetraHostCadenceState)
    Save-MetraHostCadenceState -State $state -Path $Path -MetraRoot $MetraRoot
    return $state
}

function Test-MetraHostCadenceLegacyTaskMismatch {
    <#
    .SYNOPSIS
        Detects MetraYarnLoomPulse/Daily Tasks that still reference the schedule runner.
        mismatch is true only when Host cadence is enabled (dual-owner conflict).
    #>
    [CmdletBinding()]
    param([bool]$HostEnabled)

    $details = [System.Collections.Generic.List[string]]::new()
    $pulsePresent = $false
    $dailyPresent = $false
    foreach ($pair in @(
            @{ Name = 'MetraYarnLoomPulse'; Mode = 'Pulse' },
            @{ Name = 'MetraYarnLoomDaily'; Mode = 'Daily' }
        )) {
        try {
            $task = Get-ScheduledTask -TaskName $pair.Name -ErrorAction Stop
            # State is authoritative (same idea as Get-YarnScheduleTaskStatusCore); skip Disabled.
            $taskState = [string]$task.State
            if ($taskState -match '(?i)^Disabled$') { continue }
            $action = @($task.Actions)[0]
            $args = [string]$action.Arguments
            $exec = [string]$action.Execute
            $refsRunner = ($args -like '*Invoke-MetraYarnLoomSchedule*') -or ($exec -like '*Invoke-MetraYarnLoomSchedule*')
            $refsMode = ($args -like ("*-Mode {0}*" -f $pair.Mode)) -or ($args -like ("*Mode $($pair.Mode)*"))
            if ($refsRunner -or $refsMode -or ($args -like '*yarn*schedule*')) {
                if ($pair.Mode -eq 'Pulse') { $pulsePresent = $true } else { $dailyPresent = $true }
                [void]$details.Add("$($pair.Name) still enabled")
            }
        }
        catch { }
    }

    $any = ($pulsePresent -or $dailyPresent)
    return [pscustomobject]@{
        legacyTaskMismatch = ($HostEnabled -and $any)
        pulsePresent       = $pulsePresent
        dailyPresent       = $dailyPresent
        details            = @($details.ToArray())
    }
}

function Get-MetraHostCadenceLocalDailyParts {
    [CmdletBinding()]
    param(
        [string]$DailyAtLocal = '02:00',
        [datetime]$Now
    )

    $hour = 2
    $minute = 0
    if ($DailyAtLocal -match '^\s*(\d{1,2}):(\d{2})\s*$') {
        $hour = [int]$Matches[1]
        $minute = [int]$Matches[2]
    }
    if ($hour -lt 0 -or $hour -gt 23) { $hour = 2 }
    if ($minute -lt 0 -or $minute -gt 59) { $minute = 0 }

    if ($PSBoundParameters.ContainsKey('Now')) {
        $dt = [datetime]$Now
        if ($dt.Kind -eq [DateTimeKind]::Utc) {
            $nowLocal = $dt.ToLocalTime()
        }
        elseif ($dt.Kind -eq [DateTimeKind]::Local) {
            $nowLocal = $dt
        }
        else {
            # Unspecified: treat as local wall clock for deterministic tests.
            $nowLocal = [datetime]::SpecifyKind($dt, [DateTimeKind]::Local)
        }
    }
    else {
        $nowLocal = Get-Date
    }

    $dateKey = $nowLocal.ToString('yyyy-MM-dd')
    $wall = Get-Date -Year $nowLocal.Year -Month $nowLocal.Month -Day $nowLocal.Day -Hour $hour -Minute $minute -Second 0
    return [pscustomobject]@{
        LocalNow     = $nowLocal
        LocalDateKey = $dateKey
        WallLocal    = $wall
        Hour         = $hour
        Minute       = $minute
    }
}

function Test-MetraHostCadencePulseDue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [datetime]$UtcNow = [datetime]::UtcNow,
        [int]$EarlySkewSeconds = 60
    )

    $due = ConvertTo-MetraHostCadenceUtc -Value (Get-MetraProp -Object $State -Name 'nextPulseDueUtc' -Default $null)
    if ($null -eq $due) {
        return $true
    }
    # Early by more than EarlySkewSeconds -> not due; overdue by any amount -> due.
    $earliest = $due.AddSeconds(-1 * [Math]::Abs($EarlySkewSeconds))
    return ($UtcNow -ge $earliest)
}

function Test-MetraHostCadenceDailyDue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [datetime]$UtcNow = [datetime]::UtcNow
    )

    $parts = Get-MetraHostCadenceLocalDailyParts `
        -DailyAtLocal ([string](Get-MetraProp -Object $State -Name 'dailyAtLocal' -Default '02:00')) `
        -Now $UtcNow
    $completedDate = [string](Get-MetraProp -Object $State -Name 'lastDailyLocalDate' -Default '')
    $completedUtc = [string](Get-MetraProp -Object $State -Name 'lastDailyCompletedUtc' -Default '')
    if ($completedDate -eq $parts.LocalDateKey -and -not [string]::IsNullOrWhiteSpace($completedUtc)) {
        return $false
    }
    return ($parts.LocalNow -ge $parts.WallLocal)
}

function Repair-MetraHostCadenceInterruptedRun {
    <#
    .SYNOPSIS
        Clear a stale activeRunKind only when the lease has expired (default 2h) or the run completed.
        Routine status calls must not clear an in-flight lease inside the max window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [string]$Path,
        [string]$MetraRoot,
        [int]$MaxLeaseHours = 2,
        [switch]$ForceClear
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot

    $kind = [string](Get-MetraProp -Object $State -Name 'activeRunKind' -Default '')
    if ([string]::IsNullOrWhiteSpace($kind)) {
        return $State
    }

    $startedKey = if ($kind -eq 'Daily') { 'lastDailyStartedUtc' } else { 'lastPulseStartedUtc' }
    $completedKey = if ($kind -eq 'Daily') { 'lastDailyCompletedUtc' } else { 'lastPulseCompletedUtc' }
    $s = ConvertTo-MetraHostCadenceUtc -Value (Get-MetraProp -Object $State -Name $startedKey -Default $null)
    $c = ConvertTo-MetraHostCadenceUtc -Value (Get-MetraProp -Object $State -Name $completedKey -Default $null)

    # Completed after start -> clear stale kind only.
    if ($null -ne $s -and $null -ne $c -and $c -ge $s) {
        $State.activeRunKind = $null
        Save-MetraHostCadenceState -State $State -Path $Path -MetraRoot $MetraRoot
        return $State
    }

    $expired = $ForceClear
    if (-not $expired) {
        if ($null -eq $s) {
            $expired = $true
        }
        elseif ([datetime]::UtcNow -gt $s.AddHours([Math]::Max(1, $MaxLeaseHours))) {
            $expired = $true
        }
    }

    if (-not $expired) {
        # In-flight within lease window - leave activeRunKind alone.
        return $State
    }

    # Stale lease; do not invent success. Daily catch-up remains possible if not completed today.
    $State.activeRunKind = $null
    Save-MetraHostCadenceState -State $State -Path $Path -MetraRoot $MetraRoot
    return $State
}

function Get-MetraHostCadenceStatus {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot

    $state = Initialize-MetraHostCadenceState -Path $Path -MetraRoot $MetraRoot
    $state = Repair-MetraHostCadenceInterruptedRun -State $state -Path $Path -MetraRoot $MetraRoot
    $enabled = [bool](Get-MetraProp -Object $state -Name 'enabled' -Default $false)
    $legacy = Test-MetraHostCadenceLegacyTaskMismatch -HostEnabled:$enabled
    $parts = Get-MetraHostCadenceLocalDailyParts -DailyAtLocal ([string]$state.dailyAtLocal)
    $owner = if ($enabled) { 'MetraHost' } else { 'legacy-or-absent' }
    $armedIdle = (-not $enabled)

    return [pscustomobject]@{
        schemaVersion         = 1
        enabled               = $enabled
        owner                 = $owner
        armedIdle             = $armedIdle
        pulseEveryMinutes     = [int]$state.pulseEveryMinutes
        dailyAtLocal          = [string]$state.dailyAtLocal
        nextPulseDueUtc       = $state.nextPulseDueUtc
        nextDailyDueLocal     = ($parts.WallLocal.ToString('o'))
        lastPulseStartedUtc   = $state.lastPulseStartedUtc
        lastPulseCompletedUtc = $state.lastPulseCompletedUtc
        lastPulseOutcome      = $state.lastPulseOutcome
        lastDailyLocalDate    = $state.lastDailyLocalDate
        lastDailyStartedUtc   = $state.lastDailyStartedUtc
        lastDailyCompletedUtc = $state.lastDailyCompletedUtc
        lastDailyOutcome      = $state.lastDailyOutcome
        pendingPulse          = [bool]$state.pendingPulse
        pendingDaily          = [bool]$state.pendingDaily
        activeRunKind         = $state.activeRunKind
        legacyTaskMismatch    = [bool]$legacy.legacyTaskMismatch
        legacyPulsePresent    = [bool]$legacy.pulsePresent
        legacyDailyPresent    = [bool]$legacy.dailyPresent
        legacyDetails         = @($legacy.details)
        statePath             = $Path
    }
}

function Enable-MetraHostCadence {
    [CmdletBinding()]
    param(
        [switch]$Confirm,
        [string]$Path,
        [string]$MetraRoot,
        [int]$PulseEveryMinutes = 15,
        [string]$DailyAtLocal = '02:00'
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot

    if (-not $Confirm) {
        throw 'yarn schedule host enable requires -Confirm'
    }
    $every = $PulseEveryMinutes
    if ($every -lt 5 -or $every -gt 120) {
        throw "Invalid -PulseEveryMinutes '$every' (allowed 5-120)."
    }
    $null = Get-MetraHostCadenceLocalDailyParts -DailyAtLocal $DailyAtLocal

    $state = Initialize-MetraHostCadenceState -Path $Path -MetraRoot $MetraRoot
    $state.enabled = $true
    $state.pulseEveryMinutes = $every
    $state.dailyAtLocal = $DailyAtLocal
    if ([string]::IsNullOrWhiteSpace([string]$state.nextPulseDueUtc)) {
        $state.nextPulseDueUtc = ([datetime]::UtcNow.ToString('o'))
    }
    Save-MetraHostCadenceState -State $state -Path $Path -MetraRoot $MetraRoot
    return Get-MetraHostCadenceStatus -Path $Path -MetraRoot $MetraRoot
}

function Disable-MetraHostCadence {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot

    $state = Initialize-MetraHostCadenceState -Path $Path -MetraRoot $MetraRoot
    $state.enabled = $false
    Save-MetraHostCadenceState -State $state -Path $Path -MetraRoot $MetraRoot
    return Get-MetraHostCadenceStatus -Path $Path -MetraRoot $MetraRoot
}

function Test-MetraHostCadenceOwned {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot
    $state = Read-MetraHostCadenceState -Path $Path -MetraRoot $MetraRoot
    return [bool](Get-MetraProp -Object $state -Name 'enabled' -Default $false)
}

function Assert-MetraHostCadenceAllowsLegacyInstall {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot
    if (Test-MetraHostCadenceOwned -Path $Path -MetraRoot $MetraRoot) {
        throw 'Host owns Yarn cadence (host-cadence.json enabled=true). Use yarn schedule host disable before installing legacy Tasks, or yarn schedule host migrate -Confirm to remove them.'
    }
}

function Invoke-MetraHostCadenceScheduleMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Pulse', 'Daily')][string]$Mode,
        [Parameter(Mandatory)][string]$MetraRoot
    )

    $yarnManifest = Join-Path $MetraRoot 'modules\Yarn\Yarn.psd1'
    if (-not (Test-Path -LiteralPath $yarnManifest)) {
        throw "Yarn module missing: $yarnManifest"
    }
    Import-Module $yarnManifest -Force -DisableNameChecking
    $cmd = Get-Command Invoke-MetraYarnLoomSchedule -ErrorAction Stop
    return (& $cmd -MetraRoot $MetraRoot -Mode $Mode)
}

function Complete-MetraHostCadenceRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][ValidateSet('Pulse', 'Daily')][string]$Mode,
        [Parameter(Mandatory)][int]$ExitCode,
        [string]$Path,
        [string]$MetraRoot,
        [datetime]$UtcNow = [datetime]::UtcNow
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot

    $stamp = $UtcNow.ToUniversalTime().ToString('o')
    if ($Mode -eq 'Pulse') {
        $State.lastPulseCompletedUtc = $stamp
        $State.lastPulseOutcome = $ExitCode
        $State.pendingPulse = $false
        $every = [int](Get-MetraProp -Object $State -Name 'pulseEveryMinutes' -Default 15)
        $State.nextPulseDueUtc = ($UtcNow.ToUniversalTime().AddMinutes($every).ToString('o'))
    }
    else {
        $parts = Get-MetraHostCadenceLocalDailyParts -DailyAtLocal ([string]$State.dailyAtLocal) -Now $UtcNow
        $State.lastDailyCompletedUtc = $stamp
        $State.lastDailyOutcome = $ExitCode
        $State.lastDailyLocalDate = $parts.LocalDateKey
        $State.pendingDaily = $false
    }
    $State.activeRunKind = $null
    Save-MetraHostCadenceState -State $State -Path $Path -MetraRoot $MetraRoot
    return $State
}

function Invoke-MetraHostCadenceTick {
    <#
    .SYNOPSIS
        Evaluate due Pulse/Daily under Host cadence. Runs at most one Invoke-MetraYarnLoomSchedule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MetraRoot,
        [string]$Path,
        [switch]$Execute
    )
    $Path = Resolve-MetraHostCadenceStatePath -Path $Path -MetraRoot $MetraRoot

    $state = Initialize-MetraHostCadenceState -Path $Path -MetraRoot $MetraRoot
    $state = Repair-MetraHostCadenceInterruptedRun -State $state -Path $Path -MetraRoot $MetraRoot
    $enabled = [bool]$state.enabled
    $utcNow = [datetime]::UtcNow

    if (-not $enabled) {
        $status = Get-MetraHostCadenceStatus -Path $Path -MetraRoot $MetraRoot
        return [pscustomobject]@{
            ok        = $true
            executed  = $false
            reason    = 'disabled'
            mode      = $null
            exitCode  = $null
            status    = $status
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$state.activeRunKind)) {
        $status = Get-MetraHostCadenceStatus -Path $Path -MetraRoot $MetraRoot
        return [pscustomobject]@{
            ok       = $true
            executed = $false
            reason   = 'lease-held'
            mode     = [string]$state.activeRunKind
            exitCode = $null
            status   = $status
        }
    }

    $pulseDue = Test-MetraHostCadencePulseDue -State $state -UtcNow $utcNow
    $dailyDue = Test-MetraHostCadenceDailyDue -State $state -UtcNow $utcNow
    if ($pulseDue) { $state.pendingPulse = $true }
    if ($dailyDue) { $state.pendingDaily = $true }
    # Capture before run - JSON round-trip must not drop coalesced Pulse after Daily.
    $runPendingPulse = [bool]$state.pendingPulse
    $runPendingDaily = [bool]$state.pendingDaily

    $mode = $null
    if ($runPendingDaily) {
        $mode = 'Daily'
    }
    elseif ($runPendingPulse) {
        $mode = 'Pulse'
    }

    if (-not $mode) {
        Save-MetraHostCadenceState -State $state -Path $Path -MetraRoot $MetraRoot
        $status = Get-MetraHostCadenceStatus -Path $Path -MetraRoot $MetraRoot
        return [pscustomobject]@{
            ok       = $true
            executed = $false
            reason   = 'not-due'
            mode     = $null
            exitCode = $null
            status   = $status
        }
    }

    if (-not $Execute) {
        Save-MetraHostCadenceState -State $state -Path $Path -MetraRoot $MetraRoot
        $status = Get-MetraHostCadenceStatus -Path $Path -MetraRoot $MetraRoot
        return [pscustomobject]@{
            ok       = $true
            executed = $false
            reason   = 'due-preview'
            mode     = $mode
            exitCode = $null
            status   = $status
        }
    }

    $stamp = $utcNow.ToUniversalTime().ToString('o')
    $state.activeRunKind = $mode
    if ($mode -eq 'Pulse') {
        $state.lastPulseStartedUtc = $stamp
    }
    else {
        $state.lastDailyStartedUtc = $stamp
    }
    Save-MetraHostCadenceState -State $state -Path $Path -MetraRoot $MetraRoot

    $exitCode = 1
    $outcome = $null
    try {
        $result = Invoke-MetraHostCadenceScheduleMode -Mode $mode -MetraRoot $MetraRoot
        $exitCode = [int](Get-MetraProp -Object $result -Name 'exitCode' -Default 1)
        $outcome = [string](Get-MetraProp -Object $result -Name 'outcome' -Default '')
    }
    catch {
        $exitCode = 1
        $outcome = $_.Exception.Message
        $state = Read-MetraHostCadenceState -Path $Path -MetraRoot $MetraRoot
        $null = Complete-MetraHostCadenceRun -State $state -Mode $mode -ExitCode $exitCode -Path $Path -MetraRoot $MetraRoot -UtcNow $utcNow
        $status = Get-MetraHostCadenceStatus -Path $Path -MetraRoot $MetraRoot
        return [pscustomobject]@{
            ok       = $true
            executed = $true
            reason   = 'run-failed'
            mode     = $mode
            exitCode = $exitCode
            outcome  = $outcome
            status   = $status
            error    = [string]$_.Exception.Message
        }
    }

    $state = Read-MetraHostCadenceState -Path $Path -MetraRoot $MetraRoot
    # Preserve coalesced Pulse across Daily completion write.
    if ($mode -eq 'Daily' -and $runPendingPulse) {
        $state.pendingPulse = $true
    }
    $null = Complete-MetraHostCadenceRun -State $state -Mode $mode -ExitCode $exitCode -Path $Path -MetraRoot $MetraRoot -UtcNow $utcNow

    # After Daily, run coalesced Pulse if it was pending (Pulse never overtakes Daily).
    $state = Read-MetraHostCadenceState -Path $Path -MetraRoot $MetraRoot
    $followMode = $null
    $followExit = $null
    if ($mode -eq 'Daily' -and $runPendingPulse -and [string]::IsNullOrWhiteSpace([string]$state.activeRunKind)) {
        $followMode = 'Pulse'
        $stamp2 = $utcNow.ToUniversalTime().ToString('o')
        $state.activeRunKind = 'Pulse'
        $state.lastPulseStartedUtc = $stamp2
        $state.pendingPulse = $true
        Save-MetraHostCadenceState -State $state -Path $Path -MetraRoot $MetraRoot
        try {
            $result2 = Invoke-MetraHostCadenceScheduleMode -Mode Pulse -MetraRoot $MetraRoot
            $followExit = [int](Get-MetraProp -Object $result2 -Name 'exitCode' -Default 1)
        }
        catch {
            $followExit = 1
        }
        $state = Read-MetraHostCadenceState -Path $Path -MetraRoot $MetraRoot
        $null = Complete-MetraHostCadenceRun -State $state -Mode Pulse -ExitCode ([int]$followExit) -Path $Path -MetraRoot $MetraRoot -UtcNow $utcNow
    }

    $status = Get-MetraHostCadenceStatus -Path $Path -MetraRoot $MetraRoot
    return [pscustomobject]@{
        ok             = $true
        executed       = $true
        reason         = 'ran'
        mode           = $mode
        exitCode       = $exitCode
        outcome        = $outcome
        followMode     = $followMode
        followExitCode = $followExit
        status         = $status
    }
}
