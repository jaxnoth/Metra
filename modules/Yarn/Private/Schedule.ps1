# Yarn+Loom scheduled runners + Windows Scheduled Task install.
# Daily (MetraYarnLoomDaily): overnight scan -> reconcile -> loom until daily gate.
# Pulse (MetraYarnLoomPulse): frequent scan -> loom (no reconcile) so Approve is not stuck until 02:00.

function Get-YarnScheduleTaskName {
    return 'MetraYarnLoomDaily'
}

function Get-YarnPulseScheduleTaskName {
    return 'MetraYarnLoomPulse'
}

function Get-YarnScheduleLogDir {
    $dir = Join-Path $env:LOCALAPPDATA 'Metra\yarn\schedule-logs'
    [void][System.IO.Directory]::CreateDirectory($dir)
    return $dir
}

function Get-YarnScheduleLockPath {
    return (Join-Path $env:LOCALAPPDATA 'Metra\yarn\schedule.lock')
}

function Get-YarnScheduleRunnerPath {
    param([string]$MetraRoot = (Get-YarnHostRoot))
    return [System.IO.Path]::GetFullPath((Join-Path $MetraRoot 'scripts\Invoke-MetraYarnLoomSchedule.ps1'))
}

function Write-YarnScheduleLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$LogPath
    )
    $line = ('{0:o} {1}' -f (Get-Date).ToUniversalTime(), $Message)
    if ($LogPath) {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8
    }
    Write-Verbose $line
}

function Get-YarnSchedulePwshPath {
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCmd) { return $pwshCmd.Source }
    $psCmd = Get-Command powershell -ErrorAction SilentlyContinue
    if ($psCmd) { return $psCmd.Source }
    throw 'pwsh/powershell not found for scheduled task action.'
}

function Invoke-MetraYarnLoomSchedule {
    <#
    .SYNOPSIS
        Scheduled stages for Daily or Pulse mode.
        Daily: yarn scan -> yarn daily -Reconcile -> loom loop -UntilDailyGate -Confirm.
        Pulse: yarn scan -> loom loop -UntilDailyGate -Confirm (skips reconcile).
        Exit codes: 0 ok/daily-gate, 1 failure, 2 validation blocked, 3 unexpected loom pause, 4 lock held.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-YarnHostRoot),
        [string]$Root,
        [ValidateSet('Daily', 'Pulse')]
        [string]$Mode = 'Daily'
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = Get-MetraYarnRoot
    }
    else {
        $Root = Get-MetraYarnRoot -Override $Root
    }

    $logDir = Get-YarnScheduleLogDir
    $logPath = Join-Path $logDir (('run-{0:yyyyMMdd-HHmmss}-{1}.log' -f (Get-Date), $Mode.ToLowerInvariant()))
    $lockPath = Get-YarnScheduleLockPath
    $lockDir = Split-Path -Parent $lockPath
    [void][System.IO.Directory]::CreateDirectory($lockDir)

    # Shared lock so Daily and Pulse never overlap.
    $lockStream = $null
    try {
        $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    }
    catch {
        Write-YarnScheduleLog -LogPath $logPath -Message ("Stage=Lock Result=Held mode=$Mode")
        return [PSCustomObject]@{
            exitCode = 4
            outcome  = 'lock-held'
            mode     = $Mode
            logPath  = $logPath
        }
    }

    $exitCode = 0
    $outcome = 'completed'
    try {
        Write-YarnScheduleLog -LogPath $logPath -Message ("Stage=Start Result=Success mode=$Mode")

        Write-YarnScheduleLog -LogPath $logPath -Message 'Stage=YarnScan Result=Starting'
        try {
            $scan = Invoke-MetraYarnScan -Root $Root -MetraRoot $MetraRoot
            $blocked = [int](Get-YarnProp -Object $scan -Name 'validationBlocked' -Default 0)
            Write-YarnScheduleLog -LogPath $logPath -Message ("Stage=YarnScan Result=Success validationBlocked=$blocked")
            if ($blocked -gt 0) {
                $exitCode = 2
                $outcome = 'validation-blocked'
            }
        }
        catch {
            Write-YarnScheduleLog -LogPath $logPath -Message ("Stage=YarnScan Result=Failure error=$($_.Exception.Message)")
            return [PSCustomObject]@{ exitCode = 1; outcome = 'yarn-scan-failed'; mode = $Mode; logPath = $logPath; error = [string]$_.Exception.Message }
        }

        if ($Mode -eq 'Daily') {
            Write-YarnScheduleLog -LogPath $logPath -Message 'Stage=YarnDailyReconcile Result=Starting'
            try {
                $daily = Get-MetraYarnDaily -Root $Root -MetraRoot $MetraRoot -Reconcile
                $blocked2 = 0
                $recon = Get-YarnProp -Object $daily -Name 'reconcile' -Default $null
                if ($recon) {
                    $blocked2 = [int](Get-YarnProp -Object $recon -Name 'validationBlocked' -Default 0)
                }
                Write-YarnScheduleLog -LogPath $logPath -Message ("Stage=YarnDailyReconcile Result=Success validationBlocked=$blocked2")
                if ($blocked2 -gt 0 -and $exitCode -eq 0) {
                    $exitCode = 2
                    $outcome = 'validation-blocked'
                }
            }
            catch {
                Write-YarnScheduleLog -LogPath $logPath -Message ("Stage=YarnDailyReconcile Result=Failure error=$($_.Exception.Message)")
                return [PSCustomObject]@{ exitCode = 1; outcome = 'yarn-daily-failed'; mode = $Mode; logPath = $logPath; error = [string]$_.Exception.Message }
            }
        }
        else {
            Write-YarnScheduleLog -LogPath $logPath -Message 'Stage=YarnDailyReconcile Result=Skipped mode=Pulse'
        }

        Write-YarnScheduleLog -LogPath $logPath -Message 'Stage=LoomLoop Result=Starting'
        try {
            # Loom health/inspect adapters need Metra Ask/Inspect cmdlets (not Yarn-only).
            $metraManifest = Join-Path $MetraRoot 'scripts\Metra.psd1'
            if (Test-Path -LiteralPath $metraManifest) {
                Import-Module $metraManifest -Force -ErrorAction SilentlyContinue
            }
            $loomCmd = Get-Command Invoke-MetraLoomLoop -ErrorAction SilentlyContinue
            if (-not $loomCmd) {
                $loomManifest = Join-Path $MetraRoot 'modules\Loom\Loom.psd1'
                if (Test-Path -LiteralPath $loomManifest) {
                    Import-Module $loomManifest -Force
                    $loomCmd = Get-Command Invoke-MetraLoomLoop -ErrorAction SilentlyContinue
                }
            }
            if (-not $loomCmd) {
                throw 'Invoke-MetraLoomLoop unavailable'
            }
            $loomRootCmd = Get-Command Resolve-MetraLoomRoot -ErrorAction SilentlyContinue
            $loomRoot = if ($loomRootCmd) { [string]((& $loomRootCmd).Path) } else { $null }
            $loopParams = @{ UntilDailyGate = $true; Confirm = $true }
            if ($loomRoot) { $loopParams['Root'] = $loomRoot }
            $loop = & $loomCmd @loopParams
            $loopOutcome = [string](Get-YarnProp -Object $loop -Name 'outcome' -Default '')
            $stopReason = [string](Get-YarnProp -Object $loop -Name 'stopReason' -Default '')
            if ([string]::IsNullOrWhiteSpace($stopReason)) {
                $stopReason = [string](Get-YarnProp -Object $loop -Name 'reason' -Default $loopOutcome)
            }
            if ($stopReason -match '(?i)daily.?gate' -or $loopOutcome -match '(?i)daily.?gate') {
                Write-YarnScheduleLog -LogPath $logPath -Message 'Stage=LoomLoop Result=DailyGate'
                if ($exitCode -eq 0) { $outcome = 'daily-gate' }
            }
            elseif ($stopReason -match '(?i)pause' -or $loopOutcome -match '(?i)pause') {
                Write-YarnScheduleLog -LogPath $logPath -Message ("Stage=LoomLoop Result=UnexpectedPause reason=$stopReason")
                $exitCode = 3
                $outcome = 'loom-unexpected-pause'
            }
            else {
                Write-YarnScheduleLog -LogPath $logPath -Message ("Stage=LoomLoop Result=Success outcome=$loopOutcome")
                if ($exitCode -eq 0) { $outcome = 'completed' }
            }
        }
        catch {
            Write-YarnScheduleLog -LogPath $logPath -Message ("Stage=LoomLoop Result=Failure error=$($_.Exception.Message)")
            return [PSCustomObject]@{ exitCode = 1; outcome = 'loom-loop-failed'; mode = $Mode; logPath = $logPath; error = [string]$_.Exception.Message }
        }

        Write-YarnScheduleLog -LogPath $logPath -Message ("Stage=Complete Result=Success exitCode=$exitCode mode=$Mode")
        return [PSCustomObject]@{
            exitCode = $exitCode
            outcome  = $outcome
            mode     = $Mode
            logPath  = $logPath
        }
    }
    finally {
        if ($lockStream) {
            $lockStream.Dispose()
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-YarnScheduleAtTime {
    param([Parameter(Mandatory)][string]$At)
    if ($At -notmatch '^\s*(\d{1,2}):(\d{2})\s*$') {
        throw "Invalid -At time '$At' (expected HH:mm)."
    }
    $h = [int]$Matches[1]
    $m = [int]$Matches[2]
    if ($h -lt 0 -or $h -gt 23 -or $m -lt 0 -or $m -gt 59) {
        throw "Invalid -At time '$At' (hour 0-23, minute 0-59)."
    }
    return [PSCustomObject]@{ Hour = $h; Minute = $m; Display = ('{0:D2}:{1:D2}' -f $h, $m) }
}

function Test-YarnPulseEveryMinutes {
    param([Parameter(Mandatory)][int]$EveryMinutes)
    if ($EveryMinutes -lt 5 -or $EveryMinutes -gt 120) {
        throw "Invalid -EveryMinutes '$EveryMinutes' (allowed 5-120)."
    }
    return $EveryMinutes
}

function Get-YarnScheduleTaskStatusCore {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$RunnerPath,
        [Parameter(Mandatory)][string]$MetraRoot,
        [string]$ExpectedModeArg
    )

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        $action = @($task.Actions)[0]
        $exec = [string]$action.Execute
        $args = [string]$action.Arguments
        $cwd = [string]$action.WorkingDirectory
        $mismatch = $false
        $expectedRoot = [System.IO.Path]::GetFullPath($MetraRoot)
        if ($cwd -and ([System.IO.Path]::GetFullPath($cwd) -ne $expectedRoot)) { $mismatch = $true }
        if ($args -notmatch [regex]::Escape($RunnerPath) -and $exec -notmatch [regex]::Escape($RunnerPath)) {
            if ($args -notlike '*Invoke-MetraYarnLoomSchedule*') { $mismatch = $true }
        }
        if ($ExpectedModeArg -and $args -notlike "*$ExpectedModeArg*") {
            $mismatch = $true
        }
        $state = [string]$task.State
        $repetitionMinutes = $null
        $triggers = @($task.Triggers)
        foreach ($t in $triggers) {
            if ($t.Repetition -and $t.Repetition.Interval) {
                try {
                    $span = [System.Xml.XmlConvert]::ToTimeSpan([string]$t.Repetition.Interval)
                    $repetitionMinutes = [int][Math]::Round($span.TotalMinutes)
                }
                catch { }
            }
        }
        return [PSCustomObject]@{
            taskName         = $TaskName
            present          = $true
            state            = $state
            lastResult       = $(if ($info) { $info.LastTaskResult } else { $null })
            lastRunTime      = $(if ($info) { $info.LastRunTime } else { $null })
            nextRunTime      = $(if ($info) { $info.NextRunTime } else { $null })
            everyMinutes     = $repetitionMinutes
            workingDirectory = $cwd
            execute          = $exec
            arguments        = $args
            runnerPath       = $RunnerPath
            mismatch         = $mismatch
            status           = $(if ($mismatch) { 'mismatch' } elseif ($state -match '(?i)running') { 'running' } else { 'installed' })
        }
    }
    catch {
        return [PSCustomObject]@{
            taskName   = $TaskName
            present    = $false
            status     = 'absent'
            runnerPath = $RunnerPath
        }
    }
}

function Get-MetraYarnScheduleStatus {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-YarnHostRoot))

    $runner = Get-YarnScheduleRunnerPath -MetraRoot $MetraRoot
    $daily = Get-YarnScheduleTaskStatusCore -TaskName (Get-YarnScheduleTaskName) -RunnerPath $runner -MetraRoot $MetraRoot
    $pulse = Get-YarnScheduleTaskStatusCore -TaskName (Get-YarnPulseScheduleTaskName) -RunnerPath $runner -MetraRoot $MetraRoot -ExpectedModeArg '-Mode Pulse'
    return [PSCustomObject]@{
        daily = $daily
        pulse = $pulse
    }
}

function Install-MetraYarnSchedule {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-YarnHostRoot),
        [string]$At = '02:00',
        [switch]$Confirm
    )

    if (-not $Confirm) {
        throw 'yarn schedule install requires -Confirm'
    }

    $when = Test-YarnScheduleAtTime -At $At
    $name = Get-YarnScheduleTaskName
    $runner = Get-YarnScheduleRunnerPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "Schedule runner missing: $runner"
    }

    $pwsh = Get-YarnSchedulePwshPath
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$runner`" -Mode Daily"
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arg -WorkingDirectory $MetraRoot
    $trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.AddHours($when.Hour).AddMinutes($when.Minute))
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($existing) {
        Set-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
        $op = 'updated'
    }
    else {
        Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Metra Yarn scan/reconcile then Loom loop until daily gate' | Out-Null
        $op = 'installed'
    }

    return [PSCustomObject]@{
        outcome  = $op
        taskName = $name
        mode     = 'Daily'
        at       = $when.Display
        runner   = $runner
        status   = (Get-MetraYarnScheduleStatus -MetraRoot $MetraRoot).daily
    }
}

function Uninstall-MetraYarnSchedule {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-YarnHostRoot),
        [switch]$Confirm
    )

    if (-not $Confirm) {
        throw 'yarn schedule uninstall requires -Confirm'
    }

    $name = Get-YarnScheduleTaskName
    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if (-not $existing) {
        return [PSCustomObject]@{
            outcome  = 'already-absent'
            taskName = $name
            status   = (Get-MetraYarnScheduleStatus -MetraRoot $MetraRoot).daily
        }
    }
    Unregister-ScheduledTask -TaskName $name -Confirm:$false
    return [PSCustomObject]@{
        outcome  = 'uninstalled'
        taskName = $name
        status   = (Get-MetraYarnScheduleStatus -MetraRoot $MetraRoot).daily
    }
}

function Install-MetraYarnPulseSchedule {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-YarnHostRoot),
        [int]$EveryMinutes = 15,
        [switch]$Confirm
    )

    if (-not $Confirm) {
        throw 'yarn schedule pulse install requires -Confirm'
    }

    $minutes = Test-YarnPulseEveryMinutes -EveryMinutes $EveryMinutes
    $name = Get-YarnPulseScheduleTaskName
    $runner = Get-YarnScheduleRunnerPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "Schedule runner missing: $runner"
    }

    $pwsh = Get-YarnSchedulePwshPath
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$runner`" -Mode Pulse"
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arg -WorkingDirectory $MetraRoot
    # Once + repetition: Approve -> enroll/build within EveryMinutes without waiting for Daily 02:00.
    $start = (Get-Date).AddMinutes(1)
    $trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Minutes $minutes) -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($existing) {
        Set-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
        $op = 'updated'
    }
    else {
        Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Metra Yarn scan + Loom loop pulse (no daily reconcile); picks up Approve without waiting for MetraYarnLoomDaily' | Out-Null
        $op = 'installed'
    }

    return [PSCustomObject]@{
        outcome      = $op
        taskName     = $name
        mode         = 'Pulse'
        everyMinutes = $minutes
        runner       = $runner
        status       = (Get-MetraYarnScheduleStatus -MetraRoot $MetraRoot).pulse
    }
}

function Uninstall-MetraYarnPulseSchedule {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-YarnHostRoot),
        [switch]$Confirm
    )

    if (-not $Confirm) {
        throw 'yarn schedule pulse uninstall requires -Confirm'
    }

    $name = Get-YarnPulseScheduleTaskName
    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if (-not $existing) {
        return [PSCustomObject]@{
            outcome  = 'already-absent'
            taskName = $name
            status   = (Get-MetraYarnScheduleStatus -MetraRoot $MetraRoot).pulse
        }
    }
    Unregister-ScheduledTask -TaskName $name -Confirm:$false
    return [PSCustomObject]@{
        outcome  = 'uninstalled'
        taskName = $name
        status   = (Get-MetraYarnScheduleStatus -MetraRoot $MetraRoot).pulse
    }
}

function Invoke-YarnScheduleCommand {
    [CmdletBinding()]
    param(
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-YarnHostRoot),
        [string]$Root
    )

    if (-not $ArgsRest -or $ArgsRest.Count -eq 0) {
        throw 'yarn schedule requires install|uninstall|status|run|pulse'
    }
    $sub = $ArgsRest[0].ToLowerInvariant()
    $rest = @()
    if ($ArgsRest.Count -gt 1) { $rest = @($ArgsRest[1..($ArgsRest.Count - 1)]) }

    switch ($sub) {
        'status' {
            return Get-MetraYarnScheduleStatus -MetraRoot $MetraRoot
        }
        'install' {
            $at = '02:00'
            $confirm = $false
            for ($i = 0; $i -lt $rest.Count; $i++) {
                if ($rest[$i] -eq '-At' -and ($i + 1) -lt $rest.Count) { $at = [string]$rest[$i + 1]; $i++ }
                elseif ($rest[$i] -eq '-Confirm') { $confirm = $true }
            }
            return Install-MetraYarnSchedule -MetraRoot $MetraRoot -At $at -Confirm:$confirm
        }
        'uninstall' {
            $confirm = $rest -contains '-Confirm'
            return Uninstall-MetraYarnSchedule -MetraRoot $MetraRoot -Confirm:$confirm
        }
        'run' {
            return Invoke-MetraYarnLoomSchedule -MetraRoot $MetraRoot -Root $Root -Mode Daily
        }
        'pulse' {
            if ($rest.Count -eq 0) {
                throw 'yarn schedule pulse requires install|uninstall|run'
            }
            $pulseSub = $rest[0].ToLowerInvariant()
            $pulseRest = @()
            if ($rest.Count -gt 1) { $pulseRest = @($rest[1..($rest.Count - 1)]) }
            switch ($pulseSub) {
                'install' {
                    $every = 15
                    $confirm = $false
                    for ($i = 0; $i -lt $pulseRest.Count; $i++) {
                        if ($pulseRest[$i] -eq '-EveryMinutes' -and ($i + 1) -lt $pulseRest.Count) {
                            $every = [int]$pulseRest[$i + 1]
                            $i++
                        }
                        elseif ($pulseRest[$i] -eq '-Confirm') { $confirm = $true }
                    }
                    return Install-MetraYarnPulseSchedule -MetraRoot $MetraRoot -EveryMinutes $every -Confirm:$confirm
                }
                'uninstall' {
                    $confirm = $pulseRest -contains '-Confirm'
                    return Uninstall-MetraYarnPulseSchedule -MetraRoot $MetraRoot -Confirm:$confirm
                }
                'run' {
                    return Invoke-MetraYarnLoomSchedule -MetraRoot $MetraRoot -Root $Root -Mode Pulse
                }
                default {
                    throw "yarn schedule pulse: unknown subcommand '$pulseSub' (use install|uninstall|run)"
                }
            }
        }
        default {
            throw "yarn schedule: unknown subcommand '$sub' (use install|uninstall|status|run|pulse)"
        }
    }
}
