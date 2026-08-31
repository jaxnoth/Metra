# Metra Ops host: user-session tray supervisor.
# Ownership: Host -> Ops only. Never start/stop Ask directly (Ops owns Ask).
# Authority: browser can propose; host/session applies; Ops owns Ask; host owns supervision.

function Get-MetraOpsHostDataDir {
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = Join-Path $HOME 'AppData\Local'
    }

    $dir = Join-Path $base 'Metra'
    if (-not (Test-Path -LiteralPath $dir)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    return $dir
}

function Get-MetraOpsHostPidFile {
    return Join-Path (Get-MetraOpsHostDataDir) 'ops-host.pid'
}

function Get-MetraOpsHostStatePath {
    return Join-Path (Get-MetraOpsHostDataDir) 'ops-host-state.json'
}

function Get-MetraOpsHostLogPath {
    return Join-Path (Get-MetraOpsHostDataDir) 'ops-host.log'
}

function Write-MetraOpsHostLog {
    <#
    .SYNOPSIS
        Appends one supervision event to the host log so a desk that died overnight leaves a trace.
    .DESCRIPTION
        The tray runs hidden with no console, so restarts and failures are otherwise invisible.
        Rotates at 256 KB to one .old file. Never throws - logging must not break supervision.
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Level = 'info'
    )

    try {
        $path = Get-MetraOpsHostLogPath
        $existing = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if ($existing -and $existing.Length -gt 256KB) {
            Move-Item -LiteralPath $path -Destination "$path.old" -Force -ErrorAction SilentlyContinue
        }
        $stamp = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content -LiteralPath $path -Value ("{0} [{1}] pid {2} - {3}" -f $stamp, $Level, $PID, $Message) -Encoding UTF8
    }
    catch { }
}

function Get-MetraOpsHostStartupShortcutPath {
    $startup = [Environment]::GetFolderPath('Startup')
    return Join-Path $startup 'Metra Ops Tray Host.lnk'
}

function Remove-MetraOpsLegacyShortcut {
    param([Parameter(Mandatory)][string]$LinkPath)

    if (Test-Path -LiteralPath $LinkPath) {
        Remove-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-MetraOpsHostStartupEnabled {
    return (Test-Path -LiteralPath (Get-MetraOpsHostStartupShortcutPath))
}

function Get-MetraOpsHostIconPath {
    param([string]$MetraRoot = (Get-MetraRoot))

    $candidates = @(
        (Join-Path $MetraRoot 'docs\assets\metra.ico')
        (Join-Path $MetraRoot 'ops\public\metra.ico')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Get-MetraOpsHostNotifyIcon {
    <#
    .SYNOPSIS
        Loads the Metra brand tray icon, or falls back to the generic application icon.
    #>
    param([string]$MetraRoot = (Get-MetraRoot))

    $icoPath = Get-MetraOpsHostIconPath -MetraRoot $MetraRoot
    if ($icoPath) {
        try {
            return New-Object System.Drawing.Icon $icoPath
        }
        catch {
            Write-Warning "Could not load Metra tray icon from $icoPath - $($_.Exception.Message)"
        }
    }
    return [System.Drawing.SystemIcons]::Application.Clone()
}

function Get-MetraOpsStartMenuFolder {
    $programs = [Environment]::GetFolderPath('Programs')
    return Join-Path $programs 'Metra'
}

function New-MetraOpsShortcut {
    param(
        [Parameter(Mandatory)][string]$LinkPath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [string]$Description = 'Metra Ops',
        [string]$Arguments = '',
        [string]$IconPath = $null,
        [int]$WindowStyle = 1
    )

    $dir = Split-Path -Parent $LinkPath
    if (-not (Test-Path -LiteralPath $dir)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($dir)
    }

    $wsh = $null
    $shortcut = $null
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($LinkPath)
        $shortcut.TargetPath = $TargetPath
        $shortcut.WorkingDirectory = $WorkingDirectory
        $shortcut.WindowStyle = $WindowStyle
        $shortcut.Description = $Description
        if ($Arguments) {
            $shortcut.Arguments = $Arguments
        }
        if ($IconPath -and (Test-Path -LiteralPath $IconPath)) {
            $shortcut.IconLocation = "$IconPath,0"
        }
        $shortcut.Save()
    }
    finally {
        if ($shortcut) {
            try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) } catch { }
        }
        if ($wsh) {
            try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) } catch { }
        }
    }
}

function Install-MetraOpsStartMenuShortcuts {
    <#
    .SYNOPSIS
        Creates or refreshes per-user Start Menu shortcuts for Metra Ops with the brand icon.
    .DESCRIPTION
        Windows cannot brand a .cmd file itself - Start Menu needs .lnk files with IconLocation.
        Idempotent. Tray host only (-NoBrowser): starts the user-session supervisor and desk
        without forcing a browser window. Open the desk from the tray menu when you want it.
        Layout: Programs\Metra\Metra Ops Tray Host (+ console escape hatch) and a top-level
        Programs\Metra Ops Tray Host entry for Start search / pin.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $opsCmd = Join-Path $MetraRoot 'Metra-Ops.cmd'
    $consoleCmd = Join-Path $MetraRoot 'Metra-Ops-Console.cmd'
    if (-not (Test-Path -LiteralPath $opsCmd)) {
        throw "Missing Metra-Ops.cmd under $MetraRoot"
    }

    $icoPath = Get-MetraOpsHostIconPath -MetraRoot $MetraRoot
    $folder = Get-MetraOpsStartMenuFolder
    $programs = [Environment]::GetFolderPath('Programs')
    $links = [System.Collections.Generic.List[string]]::new()
    $trayArgs = '-NoBrowser'

    # Retire pre-tray-host naming (browser-first "Metra Ops" shortcuts).
    Remove-MetraOpsLegacyShortcut -LinkPath (Join-Path $folder 'Metra Ops.lnk')
    Remove-MetraOpsLegacyShortcut -LinkPath (Join-Path $programs 'Metra Ops.lnk')

    $mainFolderLink = Join-Path $folder 'Metra Ops Tray Host.lnk'
    New-MetraOpsShortcut `
        -LinkPath $mainFolderLink `
        -TargetPath $opsCmd `
        -WorkingDirectory $MetraRoot `
        -Arguments $trayArgs `
        -Description 'Metra Ops tray host (supervises desk; open browser from tray menu)' `
        -IconPath $icoPath `
        -WindowStyle 7
    [void]$links.Add($mainFolderLink)

    # Top-level Programs entry (Start search / pin-friendly).
    $topLink = Join-Path $programs 'Metra Ops Tray Host.lnk'
    New-MetraOpsShortcut `
        -LinkPath $topLink `
        -TargetPath $opsCmd `
        -WorkingDirectory $MetraRoot `
        -Arguments $trayArgs `
        -Description 'Metra Ops tray host (supervises desk; open browser from tray menu)' `
        -IconPath $icoPath `
        -WindowStyle 7
    [void]$links.Add($topLink)

    if (Test-Path -LiteralPath $consoleCmd) {
        $consoleLink = Join-Path $folder 'Metra Ops (console).lnk'
        New-MetraOpsShortcut `
            -LinkPath $consoleLink `
            -TargetPath $consoleCmd `
            -WorkingDirectory $MetraRoot `
            -Description 'Metra Ops console (operator debug)' `
            -IconPath $icoPath `
            -WindowStyle 1
        [void]$links.Add($consoleLink)
    }

    return [PSCustomObject]@{
        Folder   = $folder
        IconPath = $icoPath
        Links    = @($links.ToArray())
    }
}

function Set-MetraOpsHostStartup {
    <#
    .SYNOPSIS
        Enable or disable per-user Startup shortcut for the Ops host (tray menu only).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$Enabled,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $lnkPath = Get-MetraOpsHostStartupShortcutPath
    if (-not $Enabled) {
        if (Test-Path -LiteralPath $lnkPath) {
            Remove-Item -LiteralPath $lnkPath -Force
        }
        return
    }

    $cmd = Join-Path $MetraRoot 'Metra-Ops.cmd'
    if (-not (Test-Path -LiteralPath $cmd)) {
        throw "Missing Metra-Ops.cmd under $MetraRoot"
    }

    Remove-MetraOpsLegacyShortcut -LinkPath (Join-Path (Split-Path -Parent $lnkPath) 'Metra Ops.lnk')

    New-MetraOpsShortcut `
        -LinkPath $lnkPath `
        -TargetPath $cmd `
        -WorkingDirectory $MetraRoot `
        -Arguments '-NoBrowser' `
        -Description 'Metra Ops tray host (supervises desk; open browser from tray menu)' `
        -IconPath (Get-MetraOpsHostIconPath -MetraRoot $MetraRoot) `
        -WindowStyle 7
}

function Write-MetraOpsHostState {
    param(
        [Parameter(Mandatory)][string]$Status,
        [int]$OpsPort = 7380,
        [int]$RestartCount = 0,
        [string]$LastFailure = $null,
        [string]$StartedAt = $null,
        [int]$ChildPid = 0,
        [int]$ConsecutiveFailures = 0
    )

    $path = Get-MetraOpsHostStatePath
    $existing = $null
    if (Test-Path -LiteralPath $path) {
        try { $existing = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { }
    }

    if (-not $StartedAt) {
        $StartedAt = [string](Get-MetraProp -Object $existing -Name 'startedAt' -Default ([datetime]::UtcNow.ToString('o')))
    }
    if ($RestartCount -lt 0 -and $existing) {
        $RestartCount = [int](Get-MetraProp -Object $existing -Name 'restartCount' -Default 0)
    }

    $obj = [PSCustomObject]@{
        status              = $Status
        startedAt           = $StartedAt
        restartCount        = $RestartCount
        lastFailure         = $LastFailure
        opsPort             = $OpsPort
        childPid            = $ChildPid
        consecutiveFailures = $ConsecutiveFailures
        hostPid             = $PID
        updatedAt           = [datetime]::UtcNow.ToString('o')
    }
    ($obj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-MetraOpsHostRestartDelaySeconds {
    <#
    .SYNOPSIS
        Backoff delay before the next desk restart attempt, by consecutive failure count.
    .DESCRIPTION
        The supervisor never gives up permanently: a desk that cannot start right now (build in
        flight, port briefly held, machine waking) is retried on a widening interval instead.
    #>
    param([int]$FailureStreak)

    switch ($FailureStreak) {
        { $_ -le 1 } { return 5 }
        2 { return 15 }
        3 { return 60 }
        default { return 300 }
    }
}

function Update-MetraOpsHostHeartbeat {
    <#
    .SYNOPSIS
        Writes host state on change, or every 30 seconds, so an offline desk is observable.
    .DESCRIPTION
        Without a heartbeat the state file keeps the last transition forever and a desk that died
        hours ago still reads "running". Throttled to keep the tray cheap.
    #>
    param(
        [Parameter(Mandatory)][string]$Status,
        [int]$ChildPid = 0,
        [string]$LastFailure = $null
    )

    $now = [datetime]::UtcNow
    $changed = ($Status -ne $script:MetraOpsLastStatus) -or ($ChildPid -ne $script:MetraOpsLastHeartbeatChildPid)
    if (-not $changed -and $script:MetraOpsLastHeartbeatUtc -ne [datetime]::MinValue -and
        ($now - $script:MetraOpsLastHeartbeatUtc).TotalSeconds -lt 30) {
        return
    }

    $script:MetraOpsLastStatus = $Status
    $script:MetraOpsLastHeartbeatChildPid = $ChildPid
    $script:MetraOpsLastHeartbeatUtc = $now

    Write-MetraOpsHostState -Status $Status -OpsPort $script:MetraOpsHostPort `
        -RestartCount $script:MetraOpsRestartCount -LastFailure $LastFailure `
        -StartedAt $script:MetraOpsHostStartedAt -ChildPid $ChildPid `
        -ConsecutiveFailures $script:MetraOpsFailureStreak
}

function Get-MetraOpsHostState {
    $path = Get-MetraOpsHostStatePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Test-MetraOpsHostStateFresh {
    <#
    .SYNOPSIS
        True when host state.updatedAt is recent enough to trust against PID reuse.
    #>
    [CmdletBinding()]
    param(
        $State,
        [int]$MaxAgeSeconds = 120
    )

    if (-not $State) { return $false }

    $updatedRaw = Get-MetraProp -Object $State -Name 'updatedAt' -Default ''
    if ([string]::IsNullOrWhiteSpace($updatedRaw)) { return $false }

    $updated = [datetime]::MinValue
    if (-not [datetime]::TryParse(
            $updatedRaw,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$updated
        )) {
        return $false
    }

    if ($updated.Kind -ne [DateTimeKind]::Utc) {
        $updated = $updated.ToUniversalTime()
    }

    return (([datetime]::UtcNow - $updated).TotalSeconds -le $MaxAgeSeconds)
}

function Get-MetraOpsHostProcessId {
    <#
    .SYNOPSIS
        Returns the live Ops host PID when the pid file matches fresh Metra host state.
    .DESCRIPTION
        PID existence alone is not enough - Windows recycles PIDs. Require state.hostPid to match
        and state.updatedAt to be recent so a stale ops-host.pid cannot block startup.
    #>
    $pidFile = Get-MetraOpsHostPidFile
    if (-not (Test-Path -LiteralPath $pidFile)) { return $null }

    $recorded = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$recorded)) {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        return $null
    }

    if ($recorded -eq $PID) { return $recorded }

    $proc = Get-Process -Id $recorded -ErrorAction SilentlyContinue
    if (-not $proc) {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        return $null
    }

    $state = Get-MetraOpsHostState
    $stateHostPid = 0
    if ($state) {
        $stateHostPid = [int](Get-MetraProp -Object $state -Name 'hostPid' -Default 0)
    }
    if (
        $stateHostPid -eq $recorded -and
        (Test-MetraOpsHostStateFresh -State $state)
    ) {
        return $recorded
    }

    # PID exists but state is missing/stale or does not match Metra state.
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    return $null
}

function Test-MetraOpsHostRunning {
    $hostPid = Get-MetraOpsHostProcessId
    return [bool]($hostPid -and $hostPid -ne $PID)
}

function Open-MetraOpsDeskBrowser {
    param(
        [int]$Port = 0,
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$Url = $null
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        # Memorable ShareUrl/BrowserUrl when available + #metraLocalSession bootstrap.
        # Do not log the returned URL (token in fragment).
        if ($Port -gt 0) {
            $binding = Get-MetraOpsDeskBindingForPort -Port $Port -MetraRoot $MetraRoot
            $Url = Get-MetraOpsDeskOpenUrl -Binding $binding
        }
        else {
            $binding = Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot
            $Url = Get-MetraOpsDeskOpenUrl -Binding $binding
        }
    }
    try {
        Start-Process $Url | Out-Null
    }
    catch {
        # Omit URL from warning - may contain local-session hash bootstrap.
        Write-Warning "Could not open browser: $($_.Exception.Message)"
    }
}

function Stop-MetraOpsDesk {
    <#
    .SYNOPSIS
        Stops Metra Ops desk and the Ask sidecar together (one product lifecycle).
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 0,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($Port -le 0) {
        $Port = [int](Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot).Port
    }

    try {
        $null = Stop-MetraAskEngine -MetraRoot $MetraRoot -IncludePortListeners -Confirm:$false
    }
    catch {
        Write-Warning "Ask sidecar stop during desk stop: $($_.Exception.Message)"
    }

    Stop-MetraOpsServer -Port $Port
}

function Restart-MetraOpsDesk {
    <#
    .SYNOPSIS
        Recycles Ops desk + Ask sidecar (background child when desk was up).
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 0,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$NoRefresh,
        [switch]$Quick
    )

    if ($Port -le 0) {
        $Port = [int](Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot).Port
    }

    $wasUp = Test-MetraOpsDeskResponding -Port $Port -TimeoutSec 2
    Stop-MetraOpsDesk -Port $Port -MetraRoot $MetraRoot

    if (-not $wasUp) {
        return [PSCustomObject]@{
            restarted = $false
            reason    = 'desk_was_down'
            port      = $Port
        }
    }

    $child = Start-MetraOpsChildProcess -MetraRoot $MetraRoot -Port $Port -NoRefresh:$NoRefresh -Quick:$Quick
    return [PSCustomObject]@{
        restarted = $true
        childPid  = $child.Id
        port      = $Port
    }
}

function Start-MetraOpsDesk {
    <#
    .SYNOPSIS
        Starts Metra Ops + Ask in a detached background process (terminal can close safely).
    .DESCRIPTION
        Ops child runs Start-MetraOpsServer -Foreground, which owns the Ask sidecar for that session.
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 0,
        [switch]$Quick,
        [switch]$Full,
        [switch]$NoBrowser,
        [switch]$NoRefresh,
        [switch]$ForceLocal,
        [string]$OpsBaseUrl,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    Assert-MetraOpsMayStartLocally -ForceLocal:$ForceLocal -OpsBaseUrl $OpsBaseUrl -MetraRoot $MetraRoot

    if ($ForceLocal) {
        $env:METRA_OPS_FORCE_LOCAL = '1'
    }

    if ($Port -le 0) {
        $binding = Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot
        $Port = [int]$binding.Port
    }
    else {
        $binding = Get-MetraOpsDeskBindingForPort -Port $Port -MetraRoot $MetraRoot
    }

    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "Invalid port: $Port"
    }

    $shareUrl = [string](Get-MetraProp -Object $binding -Name 'ShareUrl' -Default ([string]$binding.BrowserUrl))
    if ([string]::IsNullOrWhiteSpace($shareUrl)) { $shareUrl = [string]$binding.BrowserUrl }
    $operatorUrl = Get-MetraOpsOperatorOpenUrl -Binding $binding
    $deskDisplay = if ($shareUrl -and (Test-MetraOpsMemorableDeskBaseUrl -Url $shareUrl -OperatorUrl $operatorUrl)) {
        $shareUrl
    }
    else { $operatorUrl }

    if (Test-MetraOpsDeskResponding -Port $Port) {
        Write-Host ("Metra Ops desk already serving: {0}" -f $deskDisplay) -ForegroundColor Green
        $askCap = Get-MetraAskCapability -MetraRoot $MetraRoot
        if ([bool]$askCap.selected) {
            if ([bool]$askCap.available) {
                Write-Host ("Ask engine: {0} on port {1} (healthy)." -f $askCap.providerLabel, $askCap.port) -ForegroundColor DarkGray
            }
            else {
                Write-Host ("Ask engine: selected but unavailable ({0})." -f $askCap.reason) -ForegroundColor DarkYellow
            }
        }
        if (-not $NoBrowser) {
            try {
                $authorizedOpenUrl = Get-MetraOpsDeskOpenUrl -Binding $binding
                Start-Process $authorizedOpenUrl | Out-Null
            }
            catch {
                Write-Warning "Could not open browser: $($_.Exception.Message)"
            }
        }
        Write-Host ("Restart with: .\metra.ps1 ops -Stop -Port {0}" -f $Port) -ForegroundColor DarkGray
        return
    }

    if (-not $NoRefresh) {
        Write-Host 'Refreshing desk snapshot...' -ForegroundColor Cyan
        $null = Get-MetraDeskPayload -Refresh -Full:$Full -MetraRoot $MetraRoot
    }

    $child = Start-MetraOpsChildProcess -MetraRoot $MetraRoot -Port $Port -NoRefresh -Quick:$Quick
    Write-Host ("Metra Ops desk started in background (process {0}): {1}" -f $child.Id, $deskDisplay) -ForegroundColor Green
    Write-Host 'Ops and Ask run together in that process; closing this terminal will not stop the desk.' -ForegroundColor DarkGray
    Write-Host ("Stop with: .\metra.ps1 ops -Stop -Port {0}" -f $Port) -ForegroundColor DarkGray

    if (-not $NoBrowser) {
        Open-MetraOpsDeskBrowser -Port $Port -MetraRoot $MetraRoot
    }
}

function Start-MetraOpsChildProcess {
    <#
    .SYNOPSIS
        Starts the hidden Ops child (Host -> Ops). Does not start Ask directly.
    .DESCRIPTION
        Passes -Port only. Listener prefixes (Tailscale / friendly / loopback) are resolved inside
        Start-MetraOpsServer via Get-MetraOpsDeskBindingForPort - not loopback-only.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Port = 0,
        [switch]$NoRefresh,
        [switch]$Quick
    )

    if ($Port -le 0) {
        $Port = [int](Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot).Port
    }

    $bootstrap = Join-Path $MetraRoot 'scripts\bootstrap\Start-MetraOps.ps1'
    if (-not (Test-Path -LiteralPath $bootstrap)) {
        throw "Missing Ops bootstrap: $bootstrap"
    }

    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-WindowStyle', 'Hidden'
        '-File', $bootstrap
        '-NoBrowser'
        '-Foreground'
        '-Port', "$Port"
    )
    if ($NoRefresh) { $argList += '-NoRefresh' }
    if ($Quick) { $argList += '-Quick' }
    if ($env:METRA_OPS_FORCE_LOCAL -match '^(?i)(1|true|yes)$') {
        $argList += '-ForceLocal'
    }

    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList `
        -WorkingDirectory $MetraRoot -PassThru -WindowStyle Hidden

    $deadline = [datetime]::UtcNow.AddSeconds(45)
    while ([datetime]::UtcNow -lt $deadline) {
        if (Test-MetraOpsDeskResponding -Port $Port -TimeoutSec 2) {
            return $proc
        }
        if ($proc.HasExited) {
            throw "Ops child exited early (pid $($proc.Id), code $($proc.ExitCode))."
        }
        Start-Sleep -Milliseconds 500
    }

    throw "Ops child started (pid $($proc.Id)) but desk did not answer on port $Port."
}

function Get-MetraOpsChildProcessId {
    <#
    .SYNOPSIS
        Process id of the running Ops desk child for a port, or null when none is alive.
    .DESCRIPTION
        Process liveness - not an HTTP probe - is the supervision signal. A desk serving a long
        Ask cannot answer /api/meta, and must never be mistaken for a dead desk.
    #>
    param([int]$Port = 7380)

    $pidFile = Get-MetraOpsPidFile -Port $Port
    if (-not (Test-Path -LiteralPath $pidFile)) { return $null }

    $recorded = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$recorded)) {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        return $null
    }

    if (Get-Process -Id $recorded -ErrorAction SilentlyContinue) {
        return $recorded
    }

    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    return $null
}

function Test-MetraOpsDeskAlive {
    <#
    .SYNOPSIS
        True when the desk process is alive or the port answers.
    #>
    param(
        [int]$Port = 7380,
        [int]$TimeoutSec = 3
    )

    if (Get-MetraOpsChildProcessId -Port $Port) { return $true }
    return (Test-MetraOpsDeskResponding -Port $Port -TimeoutSec $TimeoutSec)
}

function Start-MetraOpsDeskIfDown {
    <#
    .SYNOPSIS
        Ensures the Ops desk answers on the loopback port, starting the Ops child when needed.
    .DESCRIPTION
        Used by the tray before opening a browser so a dead desk never shows "can't reach this page".
        A live desk process counts as up even when it is too busy to answer a probe, so opening the
        browser never interrupts an Ask in flight. Host starts Ops only; Ops still owns the Ask engine.
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 7380,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if (Test-MetraOpsDeskAlive -Port $Port -TimeoutSec 2) {
        return [PSCustomObject]@{ Ok = $true; Started = $false; Error = $null }
    }

    try { Stop-MetraOpsServer -Port $Port } catch { }

    try {
        $child = Start-MetraOpsChildProcess -MetraRoot $MetraRoot -Port $Port -Quick
        return [PSCustomObject]@{ Ok = $true; Started = $true; ChildPid = $child.Id; Error = $null }
    }
    catch {
        return [PSCustomObject]@{ Ok = $false; Started = $false; Error = $_.Exception.Message }
    }
}

function Stop-MetraOpsHost {
    <#
    .SYNOPSIS
        Stops the Ops desk (via Ops helpers) and the tray host process if running.
    .DESCRIPTION
        The tray host is only stopped when it supervises the requested port (or -Force is passed),
        so stopping a scratch desk on another port cannot take down the operator's live tray.
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 7380,
        [switch]$Force
    )

    try { Stop-MetraOpsDesk -Port $Port } catch { Write-Warning $_.Exception.Message }

    $state = Get-MetraOpsHostState
    $statePort = if ($state) { [int](Get-MetraProp -Object $state -Name 'opsPort' -Default 0) } else { 0 }
    $ownsPort = $Force -or $statePort -eq 0 -or $statePort -eq $Port

    if (-not $ownsPort) {
        Write-Host "Metra Ops host supervises port $statePort - left running." -ForegroundColor Yellow
        return
    }

    $hostPid = Get-MetraOpsHostProcessId
    $stoppedHost = $false

    if ($hostPid -and $hostPid -ne $PID) {
        try {
            Stop-Process -Id $hostPid -Force -ErrorAction Stop
            $stoppedHost = $true
            Write-Host "Stopped Metra Ops host (process $hostPid)." -ForegroundColor Green
        }
        catch {
            Write-Warning "Could not stop Ops host process $hostPid - $($_.Exception.Message)"
        }
    }
    elseif ($hostPid -eq $PID) {
        $stoppedHost = $true
    }

    if ($stoppedHost -or -not $hostPid) {
        Remove-Item -LiteralPath (Get-MetraOpsHostPidFile) -Force -ErrorAction SilentlyContinue
        Write-MetraOpsHostState -Status 'stopped' -OpsPort $Port -RestartCount 0 -LastFailure $null -StartedAt ([datetime]::UtcNow.ToString('o'))
    }
}

function Start-MetraOpsHost {
    <#
    .SYNOPSIS
        Starts the user-session tray supervisor for Metra Ops (Host -> Ops -> Ask).
    .DESCRIPTION
        If the host is already running, opens the desk browser and returns.
        If the desk is already up, opens the browser and still runs the tray to supervise.
        Never starts the Ask sidecar directly - Ops owns Ask.
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 0,
        [switch]$NoBrowser,
        [switch]$NoRefresh,
        [switch]$Quick,
        [switch]$ForceLocal,
        [string]$OpsBaseUrl,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    Assert-MetraOpsMayStartLocally -ForceLocal:$ForceLocal -OpsBaseUrl $OpsBaseUrl -MetraRoot $MetraRoot

    if ($ForceLocal) {
        $env:METRA_OPS_FORCE_LOCAL = '1'
    }

    if ($Port -le 0) {
        $Port = [int](Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot).Port
    }

    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "Invalid port: $Port"
    }

    # Second click / idempotent: another host already owns the tray.
    $existingHost = Get-MetraOpsHostProcessId
    if ($existingHost -and $existingHost -ne $PID) {
        try { Install-MetraOpsStartMenuShortcuts -MetraRoot $MetraRoot | Out-Null } catch { }

        $openPort = $Port
        try {
            $state = Get-MetraOpsHostState
            $statePort = if ($state) { Get-MetraProp -Object $state -Name 'opsPort' -Default 0 } else { 0 }
            if ($statePort -gt 0) {
                $openPort = [int]$statePort
            }
        }
        catch { }

        Write-Host "Metra Ops host already running (process $existingHost)." -ForegroundColor Green
        if (-not $NoBrowser) {
            Open-MetraOpsDeskBrowser -Port $openPort -MetraRoot $MetraRoot
        }
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    try { Install-MetraOpsStartMenuShortcuts -MetraRoot $MetraRoot | Out-Null } catch {
        Write-Warning "Could not refresh Start Menu shortcuts: $($_.Exception.Message)"
    }
    $script:MetraOpsHostPort = $Port
    $script:MetraOpsHostRoot = $MetraRoot
    $script:MetraOpsChildPid = $null
    $script:MetraOpsOwnedChild = $false
    $script:MetraOpsRestartCount = 0
    $script:MetraOpsDeskStopped = $false
    $script:MetraOpsHostStartedAt = [datetime]::UtcNow.ToString('o')
    $script:MetraOpsFailureStreak = 0
    $script:MetraOpsLastError = $null
    $script:MetraOpsNextAttemptUtc = [datetime]::MinValue
    $script:MetraOpsNextUpdateCheckUtc = [datetime]::UtcNow
    $script:MetraOpsUpdateNotifiedKey = $null
    $script:MetraOpsLastHeartbeatUtc = [datetime]::MinValue
    $script:MetraOpsLastHeartbeatChildPid = 0
    $script:MetraOpsLastStatus = $null
    Write-MetraOpsHostLog "Ops host starting on port $Port (root $MetraRoot)."

    try {
        $session = Initialize-MetraOpsLocalSessionToken
        Write-MetraOpsHostLog "Local session token ready (created=$($session.Created))."
    }
    catch {
        Write-MetraOpsHostLog "Local session token init failed - $($_.Exception.Message)" 'warn'
    }

    Set-Content -LiteralPath (Get-MetraOpsHostPidFile) -Value $PID -Encoding ASCII
    # Claim hostPid in state immediately so single-instance checks cannot race a recycled PID.
    Write-MetraOpsHostState -Status 'starting' -OpsPort $Port -RestartCount 0 -StartedAt $script:MetraOpsHostStartedAt

    $deskUp = Test-MetraOpsDeskAlive -Port $Port -TimeoutSec 2
    if (-not $deskUp) {
        try {
            $child = Start-MetraOpsChildProcess -MetraRoot $MetraRoot -Port $Port -NoRefresh:$NoRefresh -Quick:$Quick
            $script:MetraOpsChildPid = $child.Id
            $script:MetraOpsOwnedChild = $true
            Write-MetraOpsHostState `
                -Status 'running' `
                -OpsPort $Port `
                -RestartCount 0 `
                -StartedAt $script:MetraOpsHostStartedAt `
                -ChildPid $(if ($script:MetraOpsChildPid) { [int]$script:MetraOpsChildPid } else { 0 })
        }
        catch {
            Write-MetraOpsHostLog "Initial desk start failed - $($_.Exception.Message)" 'error'
            Write-MetraOpsHostState -Status 'failed' -OpsPort $Port -RestartCount 0 -LastFailure $_.Exception.Message -StartedAt $script:MetraOpsHostStartedAt
            Remove-Item -LiteralPath (Get-MetraOpsHostPidFile) -Force -ErrorAction SilentlyContinue
            throw
        }
    }
    else {
        # Desk already up, e.g. console ops. Tray supervises health and adopts it.
        $script:MetraOpsChildPid = Get-MetraOpsChildProcessId -Port $Port
        $script:MetraOpsOwnedChild = $true

        Write-MetraOpsHostState `
            -Status 'running' `
            -OpsPort $Port `
            -RestartCount 0 `
            -StartedAt $script:MetraOpsHostStartedAt `
            -ChildPid $(if ($script:MetraOpsChildPid) { [int]$script:MetraOpsChildPid } else { 0 })
    }

    if (-not $NoBrowser) {
        Open-MetraOpsDeskBrowser -Port $Port
    }

    $notify = New-Object System.Windows.Forms.NotifyIcon
    $script:MetraOpsHostIcon = Get-MetraOpsHostNotifyIcon -MetraRoot $MetraRoot
    $notify.Icon = $script:MetraOpsHostIcon
    $notify.Text = 'Metra Ops'
    $notify.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $openItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $openItem.Text = 'Open Metra Ops'
    $openItem.Add_Click({
            $ensure = Start-MetraOpsDeskIfDown -Port $script:MetraOpsHostPort -MetraRoot $script:MetraOpsHostRoot
            if ($ensure.Ok) {
                if ($ensure.Started) {
                    if ($ensure.ChildPid) {
                        $script:MetraOpsChildPid = $ensure.ChildPid
                    }
                    else {
                        $script:MetraOpsChildPid = Get-MetraOpsChildProcessId -Port $script:MetraOpsHostPort
                    }
                    $script:MetraOpsOwnedChild = $true
                    $script:MetraOpsFailureStreak = 0
                    $script:MetraOpsNextAttemptUtc = [datetime]::MinValue
                    $script:MetraOpsDeskStopped = $false
                    Write-MetraOpsHostState `
                        -Status 'running' `
                        -OpsPort $script:MetraOpsHostPort `
                        -RestartCount $script:MetraOpsRestartCount `
                        -StartedAt $script:MetraOpsHostStartedAt `
                        -ChildPid $(if ($script:MetraOpsChildPid) { [int]$script:MetraOpsChildPid } else { 0 })
                }
                Open-MetraOpsDeskBrowser -Port $script:MetraOpsHostPort
            }
            else {
                Write-MetraOpsHostState -Status 'failed' -OpsPort $script:MetraOpsHostPort -RestartCount $script:MetraOpsRestartCount -LastFailure $ensure.Error -StartedAt $script:MetraOpsHostStartedAt
                $notify.ShowBalloonTip(5000, 'Metra Ops', 'Desk could not start. Try Restart desk, or run .\metra.ps1 ops to see the error.', [System.Windows.Forms.ToolTipIcon]::Warning)
            }
        })

    $restartItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $restartItem.Text = 'Restart desk'
    $restartItem.Add_Click({
            try { Stop-MetraOpsServer -Port $script:MetraOpsHostPort } catch { }
            $script:MetraOpsFailureStreak = 0
            $script:MetraOpsNextAttemptUtc = [datetime]::MinValue
            $script:MetraOpsDeskStopped = $false
            $ensure = Start-MetraOpsDeskIfDown -Port $script:MetraOpsHostPort -MetraRoot $script:MetraOpsHostRoot
            if ($ensure.Ok) {
                if ($ensure.Started -and $ensure.ChildPid) {
                    $script:MetraOpsChildPid = $ensure.ChildPid
                }
                else {
                    $script:MetraOpsChildPid = Get-MetraOpsChildProcessId -Port $script:MetraOpsHostPort
                }

                $script:MetraOpsOwnedChild = $true
                $script:MetraOpsRestartCount++

                Write-MetraOpsHostState `
                    -Status 'running' `
                    -OpsPort $script:MetraOpsHostPort `
                    -RestartCount $script:MetraOpsRestartCount `
                    -StartedAt $script:MetraOpsHostStartedAt `
                    -ChildPid $(if ($script:MetraOpsChildPid) { [int]$script:MetraOpsChildPid } else { 0 })
                $notify.ShowBalloonTip(3000, 'Metra Ops', 'Desk restarted.', [System.Windows.Forms.ToolTipIcon]::Info)
            }
            else {
                Write-MetraOpsHostState -Status 'failed' -OpsPort $script:MetraOpsHostPort -RestartCount $script:MetraOpsRestartCount -LastFailure $ensure.Error -StartedAt $script:MetraOpsHostStartedAt
                $notify.ShowBalloonTip(5000, 'Metra Ops', 'Desk restart failed.', [System.Windows.Forms.ToolTipIcon]::Warning)
            }
        })

    $startupItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $startupItem.Text = 'Start with Windows'
    $startupItem.Checked = Test-MetraOpsHostStartupEnabled
    $startupItem.Add_Click({
            $next = -not $startupItem.Checked
            try {
                Set-MetraOpsHostStartup -Enabled $next -MetraRoot $script:MetraOpsHostRoot
                $startupItem.Checked = $next
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    $_.Exception.Message,
                    'Metra Ops',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
            }
        })

    $stopItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $stopItem.Text = 'Stop desk'
    $stopItem.Add_Click({
            try { Stop-MetraOpsServer -Port $script:MetraOpsHostPort } catch { }
            $script:MetraOpsOwnedChild = $false
            $script:MetraOpsChildPid = $null
            $script:MetraOpsDeskStopped = $true
            Write-MetraOpsHostState -Status 'stopped' -OpsPort $script:MetraOpsHostPort -RestartCount $script:MetraOpsRestartCount -StartedAt $script:MetraOpsHostStartedAt
            $notify.ShowBalloonTip(3000, 'Metra Ops', 'Desk stopped. Exit the tray icon to leave Metra.', [System.Windows.Forms.ToolTipIcon]::Info)
        })

    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitItem.Text = 'Exit Metra Ops'
    $exitItem.Add_Click({
            # Exit leaves Metra: stop desk then leave the tray (not "exit tray, leave desk running").
            try { Stop-MetraOpsServer -Port $script:MetraOpsHostPort } catch { }
            Write-MetraOpsHostState -Status 'stopped' -OpsPort $script:MetraOpsHostPort -RestartCount $script:MetraOpsRestartCount -StartedAt $script:MetraOpsHostStartedAt
            $notify.Visible = $false
            [System.Windows.Forms.Application]::Exit()
        })

    [void]$menu.Items.Add($openItem)
    [void]$menu.Items.Add($restartItem)
    [void]$menu.Items.Add($startupItem)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$menu.Items.Add($stopItem)
    [void]$menu.Items.Add($exitItem)
    $notify.ContextMenuStrip = $menu
    $notify.Add_DoubleClick({ $openItem.PerformClick() })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 5000
    $timer.Add_Tick({
            # Operator chose Stop desk - do not fight that decision.
            if ($script:MetraOpsDeskStopped) { return }

            # Quiet product update check (cached 24h inside Get-MetraProductUpdates). Balloon only when new.
            if ([datetime]::UtcNow -ge $script:MetraOpsNextUpdateCheckUtc) {
                $script:MetraOpsNextUpdateCheckUtc = [datetime]::UtcNow.AddHours(6)
                try {
                    if (Get-Command Get-MetraProductUpdates -ErrorAction SilentlyContinue) {
                        $upd = Get-MetraProductUpdates -MetraRoot $script:MetraOpsHostRoot
                    }
                    else {
                        $upd = $null
                    }

                    if ($upd -and $upd.anyUpdate) {
                        $bits = @()
                        if ($upd.metra.updateAvailable) { $bits += "Metra $($upd.metra.available)" }
                        if ($upd.ollama.updateAvailable) { $bits += "Ollama $($upd.ollama.available)" }
                        $key = ($bits -join '|')
                        if ($key -and $key -ne $script:MetraOpsUpdateNotifiedKey) {
                            $script:MetraOpsUpdateNotifiedKey = $key
                            $notify.ShowBalloonTip(
                                6000,
                                'Metra Ops',
                                ("Update available: {0}. Open Settings to update." -f ($bits -join ', ')),
                                [System.Windows.Forms.ToolTipIcon]::Info
                            )
                        }
                    }
                }
                catch {
                    Write-MetraOpsHostLog "Update check failed - $($_.Exception.Message)" 'warn'
                }
            }

            # Host owns apply: poll pending proposals even if the desk is mid-Ask.
            try {
                if (Get-Command Sync-MetraProposalHostPending -ErrorAction SilentlyContinue) {
                    $applied = @(Sync-MetraProposalHostPending -MaxCount 1 -Surface browser)
                }
                else {
                    $applied = @()
                }

                foreach ($item in $applied) {
                    if ($item.Ok) {
                        $notify.ShowBalloonTip(4000, 'Metra Ops', "Applied proposal $($item.Proposal.Id).", [System.Windows.Forms.ToolTipIcon]::Info)
                    }
                    elseif ($item.ReasonCode -eq 'rejected') {
                        $notify.ShowBalloonTip(3000, 'Metra Ops', 'Proposal denied.', [System.Windows.Forms.ToolTipIcon]::Info)
                    }
                }
            }
            catch {
                Write-MetraOpsHostLog "Proposal apply poll failed - $($_.Exception.Message)" 'warn'
            }

            # Liveness is process-based on purpose: a desk serving a long Ask blocks its accept
            # loop and cannot answer /api/meta. Probing alone would kill work in flight.
            $childPid = Get-MetraOpsChildProcessId -Port $script:MetraOpsHostPort
            if (-not $childPid -and (Test-MetraOpsDeskResponding -Port $script:MetraOpsHostPort -TimeoutSec 3)) {
                $childPid = -1
            }

            if ($childPid) {
                # Adopt whatever desk is up, including one started by console ops. Declining to
                # supervise an unowned child is what let the board sit offline for hours.
                $livePid = if ($childPid -gt 0) { $childPid } else { 0 }
                if ($livePid) { $script:MetraOpsChildPid = $livePid }
                $script:MetraOpsOwnedChild = $true
                if ($script:MetraOpsFailureStreak -gt 0) {
                    Write-MetraOpsHostLog "Desk healthy again (child $livePid) after $($script:MetraOpsFailureStreak) failed attempt(s)."
                    $script:MetraOpsFailureStreak = 0
                }
                $script:MetraOpsNextAttemptUtc = [datetime]::MinValue
                Update-MetraOpsHostHeartbeat -Status 'running' -ChildPid $livePid
                return
            }

            if ([datetime]::UtcNow -lt $script:MetraOpsNextAttemptUtc) {
                Update-MetraOpsHostHeartbeat -Status 'restarting' -LastFailure $script:MetraOpsLastError
                return
            }

            $script:MetraOpsRestartCount++
            try {
                # Stop Ask only via Ops cleanup; never start the Ask engine from the host.
                try { Stop-MetraOpsServer -Port $script:MetraOpsHostPort } catch { }
                $child = Start-MetraOpsChildProcess -MetraRoot $script:MetraOpsHostRoot -Port $script:MetraOpsHostPort -Quick
                $script:MetraOpsChildPid = $child.Id
                $script:MetraOpsOwnedChild = $true
                $wasFailing = $script:MetraOpsFailureStreak -gt 0
                $script:MetraOpsFailureStreak = 0
                $script:MetraOpsNextAttemptUtc = [datetime]::MinValue
                $script:MetraOpsLastError = $null
                Write-MetraOpsHostLog "Restarted desk (child $($child.Id)); restart #$($script:MetraOpsRestartCount)."
                Update-MetraOpsHostHeartbeat -Status 'running' -ChildPid $child.Id
                if ($wasFailing) {
                    $notify.ShowBalloonTip(4000, 'Metra Ops', 'Desk is back online.', [System.Windows.Forms.ToolTipIcon]::Info)
                }
            }
            catch {
                $script:MetraOpsFailureStreak++
                $script:MetraOpsLastError = $_.Exception.Message
                $delay = Get-MetraOpsHostRestartDelaySeconds -FailureStreak $script:MetraOpsFailureStreak
                $script:MetraOpsNextAttemptUtc = [datetime]::UtcNow.AddSeconds($delay)
                Write-MetraOpsHostLog "Desk restart failed (attempt $($script:MetraOpsFailureStreak)); retrying in ${delay}s - $($script:MetraOpsLastError)" 'warn'
                Update-MetraOpsHostHeartbeat -Status 'restarting' -LastFailure $script:MetraOpsLastError
                # Balloon once per outage, not once per retry.
                if ($script:MetraOpsFailureStreak -eq 1) {
                    $notify.ShowBalloonTip(5000, 'Metra Ops', 'Desk went down. Retrying automatically.', [System.Windows.Forms.ToolTipIcon]::Warning)
                }
            }
        })
    $timer.Start()

    try {
        [System.Windows.Forms.Application]::Run()
    }
    finally {
        $timer.Stop()
        $timer.Dispose()
        $notify.Visible = $false
        $notify.Dispose()
        if ($script:MetraOpsHostIcon) {
            try { $script:MetraOpsHostIcon.Dispose() } catch { }
            $script:MetraOpsHostIcon = $null
        }
        # Do not stop the child here. Forced tray exit/crash should not kill a potentially busy desk.
        # Menu Stop/Exit paths stop Ops explicitly before Application.Exit().
        Remove-Item -LiteralPath (Get-MetraOpsHostPidFile) -Force -ErrorAction SilentlyContinue
        $state = Get-MetraOpsHostState
        if ($state -and [string]$state.status -eq 'running') {
            $childPid = 0
            try {
                $childPid = [int](Get-MetraProp -Object $state -Name 'childPid' -Default 0)
            }
            catch { }
            if (-not $childPid -and $script:MetraOpsChildPid) {
                $childPid = [int]$script:MetraOpsChildPid
            }

            Write-MetraOpsHostState `
                -Status 'unsupervised' `
                -OpsPort $Port `
                -RestartCount $script:MetraOpsRestartCount `
                -StartedAt $script:MetraOpsHostStartedAt `
                -ChildPid $childPid `
                -LastFailure 'Tray host exited; desk process may still be running.'
        }
    }
}
