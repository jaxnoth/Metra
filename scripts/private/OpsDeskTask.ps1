# Ops desk Scheduled Task - unattended Ops+Ask reach (Host UX stays tray).
# Task Scheduler stores the run-as password in LSA when LogonType Password is used.
# Do not write the HQ account password into Metra config or User env (CURSOR_API_KEY home).

$script:MetraOpsDeskTaskName = 'MetraOpsDesk'

function Get-MetraOpsDeskTaskName {
    return $script:MetraOpsDeskTaskName
}

function Get-MetraOpsDeskTaskLauncherPath {
    <#
    .SYNOPSIS
        Path to the headless Ops launcher used by MetraOpsDesk.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return (Join-Path $MetraRoot 'scripts\bootstrap\Start-MetraOpsDeskTask.ps1')
}

function Get-MetraOpsDeskTaskStatus {
    <#
    .SYNOPSIS
        Status of the MetraOpsDesk Scheduled Task (reach layer).
    #>
    [CmdletBinding()]
    param()

    $name = Get-MetraOpsDeskTaskName
    $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if (-not $task) {
        return [PSCustomObject]@{
            Installed = $false
            TaskName  = $name
            State     = $null
            UserId    = $null
            LogonType = $null
            Message   = 'MetraOpsDesk is not installed.'
        }
    }

    $info = Get-ScheduledTaskInfo -TaskName $name -ErrorAction SilentlyContinue
    $principal = $task.Principal
    return [PSCustomObject]@{
        Installed     = $true
        TaskName      = $name
        State         = [string]$task.State
        LastRunTime   = $(if ($info) { $info.LastRunTime } else { $null })
        LastTaskResult = $(if ($info) { $info.LastTaskResult } else { $null })
        UserId        = [string]$principal.UserId
        LogonType     = [string]$principal.LogonType
        Message       = 'MetraOpsDesk is registered. Password (if any) is held by Task Scheduler/LSA - not in Metra files.'
    }
}

function Install-MetraOpsDeskTask {
    <#
    .SYNOPSIS
        Register MetraOpsDesk to start Ops headless at boot (whether user is logged on or not).
    .NOTES
        Prompts for HQ credentials once. Password goes only to Register-ScheduledTask (LSA).
        Never writes the password under %LOCALAPPDATA%\Metra or User environment.
        Requires Tailscale machine-service mode for Serve without a desktop session.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [PSCredential]$Credential,
        [switch]$Force
    )

    $name = Get-MetraOpsDeskTaskName
    $launcher = Get-MetraOpsDeskTaskLauncherPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $launcher)) {
        throw "Ops desk task launcher missing: $launcher"
    }

    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($existing -and -not $Force) {
        return Get-MetraOpsDeskTaskStatus
    }

    if (-not $PSCmdlet.ShouldProcess($name, 'Register Scheduled Task MetraOpsDesk')) {
        return [PSCustomObject]@{
            Installed = $false
            TaskName  = $name
            WhatIf    = $true
            Message   = 'WhatIf: would register MetraOpsDesk with Task Scheduler credential storage.'
        }
    }

    if (-not $Credential) {
        $Credential = Get-Credential -Message 'HQ account for MetraOpsDesk (password stored only in Task Scheduler/LSA, not Metra files)'
    }
    if (-not $Credential) {
        throw 'Credential required to register MetraOpsDesk (run whether logged on or not).'
    }

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd) {
        $pwshCmd = Get-Command powershell -ErrorAction SilentlyContinue
    }
    if (-not $pwshCmd -or [string]::IsNullOrWhiteSpace($pwshCmd.Source)) {
        throw 'pwsh or Windows PowerShell required to register MetraOpsDesk.'
    }
    $pwsh = [string]$pwshCmd.Source

    $arg = "-NoProfile -WindowStyle Hidden -File `"$launcher`""

    if ($existing) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }

    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arg -WorkingDirectory $MetraRoot
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)
    # Password goes only to Task Scheduler (LSA). Never write under Metra LOCALAPPDATA or User env.
    $plain = $Credential.GetNetworkCredential().Password
    try {
        Register-ScheduledTask `
            -TaskName $name `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -User $Credential.UserName `
            -Password $plain `
            -RunLevel Highest `
            -Description 'Metra Ops desk + Ask reach (headless). Host tray remains optional UX.' `
            -Force | Out-Null
    }
    finally {
        $plain = $null
    }

    return Get-MetraOpsDeskTaskStatus
}

function Uninstall-MetraOpsDeskTask {
    <#
    .SYNOPSIS
        Remove the MetraOpsDesk Scheduled Task.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param()

    $name = Get-MetraOpsDeskTaskName
    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if (-not $existing) {
        return [PSCustomObject]@{
            Removed  = $false
            TaskName = $name
            Message  = 'MetraOpsDesk was not installed.'
        }
    }

    if (-not $PSCmdlet.ShouldProcess($name, 'Unregister Scheduled Task MetraOpsDesk')) {
        return [PSCustomObject]@{
            Removed  = $false
            TaskName = $name
            WhatIf   = $true
            Message  = 'WhatIf: would unregister MetraOpsDesk.'
        }
    }

    Unregister-ScheduledTask -TaskName $name -Confirm:$false
    return [PSCustomObject]@{
        Removed  = $true
        TaskName = $name
        Message  = 'MetraOpsDesk unregistered.'
    }
}
