# MetraHost-supervised Cursor My Machines worker (lifecycle + identity).
# Ensure detects ABI mismatch (RepairRequired). Operator repair is separate (never from ensure).

function Get-MetraCursorWorkerHostDir {
    [CmdletBinding()]
    param([string]$MetraRoot)
    $root = Join-Path (Get-MetraMachineDataRoot -MetraRoot $MetraRoot) 'host'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    return $root
}

function Get-MetraCursorWorkerConfigPath {
    [CmdletBinding()]
    param([string]$MetraRoot)
    return (Join-Path (Get-MetraCursorWorkerHostDir -MetraRoot $MetraRoot) 'cursor-worker.local.json')
}

function Get-MetraCursorWorkerRuntimePath {
    [CmdletBinding()]
    param([string]$MetraRoot)
    return (Join-Path (Get-MetraCursorWorkerHostDir -MetraRoot $MetraRoot) 'cursor-worker-runtime.json')
}

function Get-MetraCursorWorkerRepairPath {
    [CmdletBinding()]
    param([string]$MetraRoot)
    return (Join-Path (Get-MetraCursorWorkerHostDir -MetraRoot $MetraRoot) 'cursor-worker-repair.json')
}

function Get-MetraCursorWorkerCliPath {
    [CmdletBinding()]
    param([string]$CliPath)
    if (-not [string]::IsNullOrWhiteSpace($CliPath)) {
        return $CliPath
    }
    $candidate = Join-Path $env:LOCALAPPDATA 'cursor-agent\cursor-agent.ps1'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }
    return $null
}

function Get-MetraCursorWorkerCliVersionDir {
    [CmdletBinding()]
    param([string]$CliPath)
    $cli = Get-MetraCursorWorkerCliPath -CliPath $CliPath
    if ([string]::IsNullOrWhiteSpace($cli)) { return $null }
    $base = Split-Path -Parent $cli
    $versions = Join-Path $base 'versions'
    if (-not (Test-Path -LiteralPath $versions -PathType Container)) { return $null }
    $dir = Get-ChildItem -LiteralPath $versions -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}\.\d{1,2}\.\d{1,2}' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -eq $dir) { return $null }
    return $dir.FullName
}

function Get-MetraCursorWorkerCliVersionName {
    [CmdletBinding()]
    param([string]$CliPath)
    $dir = Get-MetraCursorWorkerCliVersionDir -CliPath $CliPath
    if ([string]::IsNullOrWhiteSpace($dir)) { return $null }
    return (Split-Path -Leaf $dir)
}

function ConvertTo-MetraCursorWorkerFullPath {
    [CmdletBinding()]
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        if ($full.Length -gt 3) {
            $full = $full.TrimEnd('\', '/')
        }
        return $full.ToLowerInvariant()
    }
    catch {
        return $null
    }
}

function New-MetraCursorWorkerConfig {
    [CmdletBinding()]
    param()
    return [ordered]@{
        schemaVersion              = 1
        enabled                    = $false
        name                       = 'metra-host'
        workerDirs                 = @()
        idleReleaseTimeoutSeconds  = 0
    }
}

function Read-MetraCursorWorkerConfig {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-MetraCursorWorkerConfigPath -MetraRoot $MetraRoot
    }
    $defaults = New-MetraCursorWorkerConfig
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]$defaults
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]$defaults
    }
    $dirs = @()
    foreach ($d in @(Get-MetraProp -Object $obj -Name 'workerDirs' -Default @())) {
        if (-not [string]::IsNullOrWhiteSpace([string]$d)) { $dirs += [string]$d }
    }
    $name = [string](Get-MetraProp -Object $obj -Name 'name' -Default 'metra-host')
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'metra-host' }
    $idle = [int](Get-MetraProp -Object $obj -Name 'idleReleaseTimeoutSeconds' -Default 0)
    return [pscustomobject]@{
        schemaVersion             = [int](Get-MetraProp -Object $obj -Name 'schemaVersion' -Default 1)
        enabled                   = [bool](Get-MetraProp -Object $obj -Name 'enabled' -Default $false)
        name                      = $name.Trim()
        workerDirs                = $dirs
        idleReleaseTimeoutSeconds = $idle
        configPath                = $Path
    }
}

function Get-MetraCursorWorkerExpectedWorkspace {
    [CmdletBinding()]
    param(
        $Config,
        [string]$MetraRoot
    )
    $dirs = @($Config.workerDirs)
    if ($dirs.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$dirs[0])) {
        return (ConvertTo-MetraCursorWorkerFullPath -Path ([string]$dirs[0]))
    }
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = $script:MetraModuleRoot
    }
    return (ConvertTo-MetraCursorWorkerFullPath -Path $MetraRoot)
}

function Read-MetraCursorWorkerRuntime {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-MetraCursorWorkerRuntimePath -MetraRoot $MetraRoot
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Save-MetraCursorWorkerRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Runtime,
        [string]$Path,
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-MetraCursorWorkerRuntimePath -MetraRoot $MetraRoot
    }
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Runtime | ConvertTo-Json -Depth 6)
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Clear-MetraCursorWorkerRuntime {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-MetraCursorWorkerRuntimePath -MetraRoot $MetraRoot
    }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

function Read-MetraCursorWorkerRepairLedger {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-MetraCursorWorkerRepairPath -MetraRoot $MetraRoot
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            schemaVersion        = 1
            lastRepairAttemptUtc = $null
            lastRepairVersion    = $null
            lastRepairOutcome    = $null
        }
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        return [pscustomobject]@{
            schemaVersion        = [int](Get-MetraProp -Object $raw -Name 'schemaVersion' -Default 1)
            lastRepairAttemptUtc = Get-MetraProp -Object $raw -Name 'lastRepairAttemptUtc' -Default $null
            lastRepairVersion    = Get-MetraProp -Object $raw -Name 'lastRepairVersion' -Default $null
            lastRepairOutcome    = Get-MetraProp -Object $raw -Name 'lastRepairOutcome' -Default $null
        }
    }
    catch {
        return [pscustomobject]@{
            schemaVersion        = 1
            lastRepairAttemptUtc = $null
            lastRepairVersion    = $null
            lastRepairOutcome    = $null
        }
    }
}

function Save-MetraCursorWorkerRepairLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ledger,
        [string]$Path,
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-MetraCursorWorkerRepairPath -MetraRoot $MetraRoot
    }
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $payload = [ordered]@{
        schemaVersion        = 1
        lastRepairAttemptUtc = [string](Get-MetraProp -Object $Ledger -Name 'lastRepairAttemptUtc' -Default $null)
        lastRepairVersion    = [string](Get-MetraProp -Object $Ledger -Name 'lastRepairVersion' -Default $null)
        lastRepairOutcome    = [string](Get-MetraProp -Object $Ledger -Name 'lastRepairOutcome' -Default $null)
    }
    $json = ($payload | ConvertTo-Json -Depth 4)
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Test-MetraCursorWorkerAbiErrorText {
    [CmdletBinding()]
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ($Text -match 'NODE_MODULE_VERSION') { return $true }
    if ($Text -match 'was compiled against a different Node\.js version') { return $true }
    if ($Text -match 'better[_-]sqlite3' -and $Text -match 'ERR_DLOPEN_FAILED|dlopen|ABI') { return $true }
    return $false
}

function Test-MetraCursorWorkerSqliteLoad {
    <#
    .SYNOPSIS
        Probe better-sqlite3 load under the packaged Node. Failure with ABI text => RepairRequired.
    #>
    [CmdletBinding()]
    param([string]$CliPath)
    $versionDir = Get-MetraCursorWorkerCliVersionDir -CliPath $CliPath
    if ([string]::IsNullOrWhiteSpace($versionDir)) {
        return [pscustomobject]@{ ok = $false; repairRequired = $false; error = 'No cursor-agent version directory' }
    }
    $nodeExe = Join-Path $versionDir 'node.exe'
    $modDir = Join-Path $versionDir 'node_modules\better-sqlite3'
    if (-not (Test-Path -LiteralPath $nodeExe -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; repairRequired = $false; error = 'Packaged node.exe missing' }
    }
    if (-not (Test-Path -LiteralPath $modDir -PathType Container)) {
        return [pscustomobject]@{ ok = $false; repairRequired = $false; error = 'better-sqlite3 package missing' }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $nodeExe
    $psi.Arguments = '-e "require(''better-sqlite3'')"'
    $psi.WorkingDirectory = $versionDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit(20000)) {
            try { $proc.Kill() } catch { }
            return [pscustomobject]@{ ok = $false; repairRequired = $false; error = 'better-sqlite3 probe timed out' }
        }
        [void][System.Threading.Tasks.Task]::WaitAll(@($stdoutTask, $stderrTask))
        $text = ($stdoutTask.Result + "`n" + $stderrTask.Result).Trim()
        if ($proc.ExitCode -eq 0) {
            return [pscustomobject]@{ ok = $true; repairRequired = $false; error = $null }
        }
        if (Test-MetraCursorWorkerAbiErrorText -Text $text) {
            return [pscustomobject]@{ ok = $false; repairRequired = $true; error = $text }
        }
        return [pscustomobject]@{ ok = $false; repairRequired = $false; error = $text }
    }
    catch {
        $msg = $_.Exception.Message
        if (Test-MetraCursorWorkerAbiErrorText -Text $msg) {
            return [pscustomobject]@{ ok = $false; repairRequired = $true; error = $msg }
        }
        return [pscustomobject]@{ ok = $false; repairRequired = $false; error = $msg }
    }
}

function Get-MetraCursorWorkerProcessSnapshots {
    <#
    .SYNOPSIS
        Best-effort scan for cursor-agent worker daemon processes (Win32 command lines).
    #>
    [CmdletBinding()]
    param()
    $rows = @()
    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $cl = [string]$_.CommandLine
                if ([string]::IsNullOrWhiteSpace($cl)) { return $false }
                if ($cl -notmatch '(?i)[\\/]cursor-agent[\\/]|cursor-agent\.ps1|index\.js') { return $false }
                return ($cl -match '(?i)(\s|^)worker(\s|$)') -and ($cl -match '(?i)(\s|^)start(\s|$)')
            }
    }
    catch {
        $procs = @()
    }
    foreach ($p in @($procs)) {
        $cl = [string]$p.CommandLine
        $name = $null
        $workspace = $null
        if ($cl -match '(?i)--name(?:\s+|=)(?:"([^"]+)"|''([^'']+)''|(\S+))') {
            $name = if ($Matches[1]) { $Matches[1] } elseif ($Matches[2]) { $Matches[2] } else { $Matches[3] }
        }
        if ($cl -match '(?i)--worker-dir(?:\s+|=)(?:"([^"]+)"|''([^'']+)''|(\S+))') {
            $workspace = if ($Matches[1]) { $Matches[1] } elseif ($Matches[2]) { $Matches[2] } else { $Matches[3] }
        }
        $rows += [pscustomobject]@{
            ProcessId     = [int]$p.ProcessId
            Name          = $name
            Workspace     = (ConvertTo-MetraCursorWorkerFullPath -Path $workspace)
            CommandLine   = $cl
        }
    }
    return $rows
}

function Test-MetraCursorWorkerProcessAlive {
    [CmdletBinding()]
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        return $null -ne $proc
    }
    catch {
        return $false
    }
}

function Resolve-MetraCursorWorkerIdentity {
    <#
    .SYNOPSIS
        Classify observed workers vs expected config identity (fail-closed for foreign/ambiguous).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [string]$MetraRoot,
        [string]$RuntimePath,
        [object[]]$Observed
    )
    $expectedName = [string]$Config.name
    $expectedWs = Get-MetraCursorWorkerExpectedWorkspace -Config $Config -MetraRoot $MetraRoot
    $runtime = Read-MetraCursorWorkerRuntime -Path $RuntimePath -MetraRoot $MetraRoot
    $observed = @($Observed)
    if ($null -eq $Observed) {
        $observed = @(Get-MetraCursorWorkerProcessSnapshots)
    }

    $ours = @()
    $foreign = @()
    foreach ($row in $observed) {
        $n = [string](Get-MetraProp -Object $row -Name 'Name' -Default $null)
        $w = ConvertTo-MetraCursorWorkerFullPath -Path ([string](Get-MetraProp -Object $row -Name 'Workspace' -Default $null))
        $pid = [int](Get-MetraProp -Object $row -Name 'ProcessId' -Default 0)
        $nameOk = (-not [string]::IsNullOrWhiteSpace($n)) -and ($n -eq $expectedName)
        $wsOk = (-not [string]::IsNullOrWhiteSpace($w)) -and ($w -eq $expectedWs)
        if ($nameOk -and $wsOk) {
            $ours += $row
        }
        elseif ([string]::IsNullOrWhiteSpace($n) -or [string]::IsNullOrWhiteSpace($w)) {
            # Ambiguous identity on a live worker process - fail closed.
            $foreign += $row
        }
        else {
            $foreign += $row
        }
    }

    # Runtime PID we started: if alive and listed under ours, prefer it.
    $runtimePid = 0
    $runtimeAlive = $false
    if ($null -ne $runtime) {
        $runtimePid = [int](Get-MetraProp -Object $runtime -Name 'processId' -Default 0)
        $runtimeAlive = Test-MetraCursorWorkerProcessAlive -ProcessId $runtimePid
        if ($runtimeAlive) {
            $rtName = [string](Get-MetraProp -Object $runtime -Name 'name' -Default '')
            $rtWs = ConvertTo-MetraCursorWorkerFullPath -Path ([string](Get-MetraProp -Object $runtime -Name 'workspace' -Default ''))
            if ($rtName -ne $expectedName -or $rtWs -ne $expectedWs) {
                # Runtime claims a different identity than config - treat as ambiguous/foreign.
                return [pscustomobject]@{
                    kind              = 'foreign'
                    identityOk        = $false
                    workerName        = $rtName
                    workspace         = $rtWs
                    expectedWorkspace = $expectedWs
                    processId         = $runtimePid
                    lastError         = 'Runtime PID alive but identity does not match config (fail-closed).'
                }
            }
            if ($ours.Count -eq 0) {
                $ours = @([pscustomobject]@{
                        ProcessId = $runtimePid
                        Name      = $rtName
                        Workspace = $rtWs
                    })
            }
        }
        elseif ($runtimePid -gt 0) {
            # Dead ours - clear stale runtime so ensure may restart.
            Clear-MetraCursorWorkerRuntime -Path $RuntimePath -MetraRoot $MetraRoot
        }
    }

    if ($foreign.Count -gt 0) {
        $f = $foreign[0]
        return [pscustomobject]@{
            kind              = 'foreign'
            identityOk        = $false
            workerName        = [string](Get-MetraProp -Object $f -Name 'Name' -Default $null)
            workspace         = [string](Get-MetraProp -Object $f -Name 'Workspace' -Default $null)
            expectedWorkspace = $expectedWs
            processId         = [int](Get-MetraProp -Object $f -Name 'ProcessId' -Default 0)
            lastError         = 'Foreign or ambiguous Cursor worker detected; fail-closed (no kill/takeover).'
        }
    }

    if ($ours.Count -gt 1) {
        # pwsh wrapper + child node often both match; reconcile via runtime PID or prefer node/index.js.
        $chosen = $null
        if ($runtimeAlive -and $runtimePid -gt 0) {
            $chosen = @($ours | Where-Object { [int]$_.ProcessId -eq $runtimePid } | Select-Object -First 1)
        }
        if ($null -eq $chosen -or $chosen.Count -eq 0) {
            $chosen = @($ours | Where-Object {
                    $cl = [string](Get-MetraProp -Object $_ -Name 'CommandLine' -Default '')
                    $cl -match '(?i)node\.exe|index\.js'
                } | Select-Object -First 1)
        }
        if ($null -eq $chosen -or $chosen.Count -eq 0) {
            $chosen = @($ours[0])
        }
        $ours = @($chosen)
    }

    if ($ours.Count -eq 1) {
        return [pscustomobject]@{
            kind              = 'ours'
            identityOk        = $true
            workerName        = $expectedName
            workspace         = $expectedWs
            expectedWorkspace = $expectedWs
            processId         = [int]$ours[0].ProcessId
            lastError         = $null
        }
    }

    return [pscustomobject]@{
        kind              = 'missing'
        identityOk        = $false
        workerName        = $null
        workspace         = $null
        expectedWorkspace = $expectedWs
        processId         = 0
        lastError         = $null
    }
}

function Invoke-MetraCursorWorkerDebugJson {
    [CmdletBinding()]
    param(
        [string]$CliPath,
        [int]$TimeoutMs = 45000
    )
    $cli = Get-MetraCursorWorkerCliPath -CliPath $CliPath
    if ([string]::IsNullOrWhiteSpace($cli)) {
        return [pscustomobject]@{ ok = $false; repairRequired = $false; error = 'cursor-agent CLI not found' }
    }
    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { (Get-Command pwsh).Source } else { (Get-Command powershell).Source }
    try {
        $cliQ = if ($cli -match '[\s"]') { '"' + ($cli -replace '"', '\"') + '"' } else { $cli }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $shell
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File $cliQ worker debug --json"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($TimeoutMs)) {
            try { $proc.Kill() } catch { }
            return [pscustomobject]@{ ok = $false; repairRequired = $false; error = "worker debug timed out after ${TimeoutMs}ms" }
        }
        [void][System.Threading.Tasks.Task]::WaitAll(@($stdoutTask, $stderrTask))
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        if (Test-MetraCursorWorkerAbiErrorText -Text ($stdout + "`n" + $stderr)) {
            return [pscustomobject]@{ ok = $false; repairRequired = $true; error = ($stderr + $stdout).Trim() }
        }
        $jsonStart = $stdout.IndexOf('{')
        $jsonEnd = $stdout.LastIndexOf('}')
        if ($jsonStart -lt 0 -or $jsonEnd -le $jsonStart) {
            return [pscustomobject]@{ ok = $false; repairRequired = $false; error = "worker debug returned no JSON. stderr=$stderr" }
        }
        $doc = $stdout.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json
        return [pscustomobject]@{ ok = $true; repairRequired = $false; report = $doc; stderr = $stderr }
    }
    catch {
        return [pscustomobject]@{ ok = $false; repairRequired = $false; error = $_.Exception.Message }
    }
}

function Test-MetraCursorWorkerAuthOk {
    [CmdletBinding()]
    param($DebugResult)
    if (-not $DebugResult -or -not $DebugResult.ok) { return $false }
    $auth = Get-MetraProp -Object $DebugResult.report -Name 'auth' -Default $null
    $identity = Get-MetraProp -Object $DebugResult.report -Name 'identity' -Default $null
    $authStatus = [string](Get-MetraProp -Object $auth -Name 'method' -Default '')
    $idStatus = [string](Get-MetraProp -Object $identity -Name 'status' -Default '')
    if ($idStatus -eq 'ok') { return $true }
    if ($authStatus -in @('api-key', 'login', 'token', 'auth-token')) { return $true }
    $probe = Get-MetraProp -Object $auth -Name 'apiKeyTypeProbe' -Default $null
    if ([string](Get-MetraProp -Object $probe -Name 'status' -Default '') -eq 'ok') { return $true }
    return $false
}

function New-MetraCursorWorkerStatusObject {
    [CmdletBinding()]
    param(
        [string]$State,
        [bool]$Enabled,
        [bool]$CliPresent,
        [bool]$Running,
        [string]$WorkerName,
        [string]$Workspace,
        [string]$ExpectedWorkspace,
        [bool]$IdentityOk,
        [string]$LastError,
        [bool]$AuthOk,
        $Repair,
        [int]$ProcessId = 0
    )
    return [pscustomobject]@{
        ok                = $true
        state             = $State
        enabled           = $Enabled
        cliPresent        = $CliPresent
        running           = $Running
        workerName        = $WorkerName
        workspace         = $Workspace
        expectedWorkspace = $ExpectedWorkspace
        identityOk        = $IdentityOk
        lastError         = $LastError
        authOk            = $AuthOk
        processId         = $ProcessId
        repair            = $Repair
    }
}

function Get-MetraCursorWorkerStatus {
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [string]$ConfigPath,
        [string]$RuntimePath,
        [string]$RepairPath,
        [string]$CliPath,
        [switch]$SkipDebug,
        [object[]]$Observed
    )
    $config = Read-MetraCursorWorkerConfig -Path $ConfigPath -MetraRoot $MetraRoot
    $expectedWs = Get-MetraCursorWorkerExpectedWorkspace -Config $config -MetraRoot $MetraRoot
    $cli = Get-MetraCursorWorkerCliPath -CliPath $CliPath
    $cliPresent = -not [string]::IsNullOrWhiteSpace($cli)
    $repair = Read-MetraCursorWorkerRepairLedger -Path $RepairPath -MetraRoot $MetraRoot

    if (-not $config.enabled) {
        return (New-MetraCursorWorkerStatusObject -State 'Disabled' -Enabled $false -CliPresent $cliPresent `
                -Running $false -WorkerName $null -Workspace $null -ExpectedWorkspace $expectedWs `
                -IdentityOk $false -LastError $null -AuthOk $false -Repair $repair)
    }
    if (-not $cliPresent) {
        return (New-MetraCursorWorkerStatusObject -State 'MissingCli' -Enabled $true -CliPresent $false `
                -Running $false -WorkerName $null -Workspace $null -ExpectedWorkspace $expectedWs `
                -IdentityOk $false -LastError 'cursor-agent CLI not found under %LOCALAPPDATA%\cursor-agent' `
                -AuthOk $false -Repair $repair)
    }

    # Injected -Observed is unit-test / classification mode: skip live CLI probes.
    $injectObserved = $PSBoundParameters.ContainsKey('Observed')
    if (-not $injectObserved) {
        $sqliteProbe = Test-MetraCursorWorkerSqliteLoad -CliPath $cli
        if ([bool](Get-MetraProp -Object $sqliteProbe -Name 'repairRequired' -Default $false)) {
            return (New-MetraCursorWorkerStatusObject -State 'RepairRequired' -Enabled $true -CliPresent $true `
                    -Running $false -WorkerName $null -Workspace $null -ExpectedWorkspace $expectedWs `
                    -IdentityOk $false -LastError ([string]$sqliteProbe.error) -AuthOk $false -Repair $repair)
        }
    }

    $authOk = $false
    if ($injectObserved -or $SkipDebug) {
        $authOk = $true
    }
    else {
        $dbg = Invoke-MetraCursorWorkerDebugJson -CliPath $cli
        if ([bool](Get-MetraProp -Object $dbg -Name 'repairRequired' -Default $false)) {
            return (New-MetraCursorWorkerStatusObject -State 'RepairRequired' -Enabled $true -CliPresent $true `
                    -Running $false -WorkerName $null -Workspace $null -ExpectedWorkspace $expectedWs `
                    -IdentityOk $false -LastError ([string]$dbg.error) -AuthOk $false -Repair $repair)
        }
        $authOk = Test-MetraCursorWorkerAuthOk -DebugResult $dbg
        if (-not $authOk) {
            $err = if ($dbg.ok) { 'No usable agent login / API key for worker auth' } else { [string]$dbg.error }
            return (New-MetraCursorWorkerStatusObject -State 'Unauthenticated' -Enabled $true -CliPresent $true `
                    -Running $false -WorkerName $null -Workspace $null -ExpectedWorkspace $expectedWs `
                    -IdentityOk $false -LastError $err -AuthOk $false -Repair $repair)
        }
    }

    $id = Resolve-MetraCursorWorkerIdentity -Config $config -MetraRoot $MetraRoot -RuntimePath $RuntimePath -Observed $Observed
    if ($id.kind -eq 'foreign') {
        return (New-MetraCursorWorkerStatusObject -State 'Error' -Enabled $true -CliPresent $true `
                -Running $false -WorkerName $id.workerName -Workspace $id.workspace -ExpectedWorkspace $expectedWs `
                -IdentityOk $false -LastError $id.lastError -AuthOk $authOk -Repair $repair -ProcessId ([int]$id.processId))
    }
    if ($id.kind -eq 'ours') {
        return (New-MetraCursorWorkerStatusObject -State 'Running' -Enabled $true -CliPresent $true `
                -Running $true -WorkerName $id.workerName -Workspace $id.workspace -ExpectedWorkspace $expectedWs `
                -IdentityOk $true -LastError $null -AuthOk $authOk -Repair $repair -ProcessId ([int]$id.processId))
    }

    return (New-MetraCursorWorkerStatusObject -State 'Error' -Enabled $true -CliPresent $true `
            -Running $false -WorkerName $null -Workspace $null -ExpectedWorkspace $expectedWs `
            -IdentityOk $false -LastError 'Worker not running (missing ours)' -AuthOk $authOk -Repair $repair)
}

function Start-MetraCursorWorkerDaemon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [string]$MetraRoot,
        [string]$CliPath,
        [string]$RuntimePath,
        [int]$SettleMs = 2500
    )
    $cli = Get-MetraCursorWorkerCliPath -CliPath $CliPath
    if ([string]::IsNullOrWhiteSpace($cli)) {
        throw 'cursor-agent CLI not found'
    }

    $probe = Test-MetraCursorWorkerSqliteLoad -CliPath $cli
    if ([bool](Get-MetraProp -Object $probe -Name 'repairRequired' -Default $false)) {
        return [pscustomobject]@{
            ok             = $false
            repairRequired = $true
            processId      = 0
            lastError      = [string]$probe.error
        }
    }

    $workspace = Get-MetraCursorWorkerExpectedWorkspace -Config $Config -MetraRoot $MetraRoot
    # Prefer original casing path for --worker-dir.
    $workerDir = if ($Config.workerDirs -and $Config.workerDirs.Count -gt 0) {
        [string]$Config.workerDirs[0]
    }
    else {
        if ([string]::IsNullOrWhiteSpace($MetraRoot)) { $script:MetraModuleRoot } else { $MetraRoot }
    }
    $workerDir = [System.IO.Path]::GetFullPath($workerDir)
    # Trim trailing separators except for drive-root paths like C:\
    if ($workerDir.Length -gt 3) {
        $workerDir = $workerDir.TrimEnd('\', '/')
    }
    $idle = [int]$Config.idleReleaseTimeoutSeconds
    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { (Get-Command pwsh).Source } else { (Get-Command powershell).Source }

    $quote = {
        param([string]$Value)
        if ($null -eq $Value) { return '""' }
        if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
        return $Value
    }

    $argParts = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        (& $quote $cli)
        'worker'
        '--name'
        (& $quote ([string]$Config.name))
        '--worker-dir'
        (& $quote $workerDir)
        '--idle-release-timeout'
        "$idle"
        'start'
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $shell
    $psi.Arguments = ($argParts -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.WorkingDirectory = $workerDir

    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $proc) { throw 'Failed to start cursor-agent worker process' }

    Start-Sleep -Milliseconds $SettleMs
    if ($proc.HasExited) {
        return [pscustomobject]@{
            ok             = $false
            repairRequired = $false
            processId      = 0
            lastError      = "Worker exited during start (code $($proc.ExitCode))."
        }
    }

    $runtime = [ordered]@{
        schemaVersion = 1
        processId     = [int]$proc.Id
        name          = [string]$Config.name
        workspace     = $workspace
        startedUtc    = [datetime]::UtcNow.ToString('o')
        cliPath       = $cli
    }
    Save-MetraCursorWorkerRuntime -Runtime ([pscustomobject]$runtime) -Path $RuntimePath -MetraRoot $MetraRoot
    return [pscustomobject]@{
        ok             = $true
        repairRequired = $false
        processId      = [int]$proc.Id
        lastError      = $null
    }
}

function Stop-MetraCursorWorkerDaemon {
    <#
    .SYNOPSIS
        Stop only an identity-validated owned worker. Never kills foreign/ambiguous workers.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [string]$ConfigPath,
        [string]$RuntimePath,
        [string]$CliPath,
        [switch]$SkipDebug,
        [object[]]$Observed
    )
    $status = Get-MetraCursorWorkerStatus -MetraRoot $MetraRoot -ConfigPath $ConfigPath `
        -RuntimePath $RuntimePath -CliPath $CliPath -SkipDebug:$SkipDebug -Observed $Observed
    if ($status.state -eq 'Disabled') {
        return [pscustomobject]@{ ok = $true; stopped = $false; state = 'Disabled'; message = 'Worker disabled' }
    }
    if ($status.state -eq 'Error' -and -not $status.identityOk -and $status.lastError -match 'Foreign|ambiguous') {
        return [pscustomobject]@{
            ok      = $false
            stopped = $false
            state   = 'Error'
            error   = 'Refusing to stop foreign/ambiguous worker (fail-closed).'
        }
    }
    if (-not $status.running -or -not $status.identityOk -or $status.processId -le 0) {
        Clear-MetraCursorWorkerRuntime -Path $RuntimePath -MetraRoot $MetraRoot
        return [pscustomobject]@{ ok = $true; stopped = $false; state = $status.state; message = 'No owned worker to stop' }
    }
    $stopPid = [int]$status.processId
    try {
        # Kill process tree so pwsh wrapper + node daemon both exit.
        $null = & taskkill.exe /PID $stopPid /T /F 2>&1
    }
    catch {
        try {
            Stop-Process -Id $stopPid -Force -ErrorAction Stop
        }
        catch {
            # Best-effort; clear runtime either way if process is gone.
        }
    }
    Clear-MetraCursorWorkerRuntime -Path $RuntimePath -MetraRoot $MetraRoot
    return [pscustomobject]@{ ok = $true; stopped = $true; state = 'Stopped'; message = 'Owned worker stopped'; processId = $stopPid }
}

function Invoke-MetraCursorWorkerEnsure {
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [string]$ConfigPath,
        [string]$RuntimePath,
        [string]$RepairPath,
        [string]$CliPath,
        [switch]$SkipDebug,
        [object[]]$Observed
    )
    $config = Read-MetraCursorWorkerConfig -Path $ConfigPath -MetraRoot $MetraRoot
    $status = Get-MetraCursorWorkerStatus -MetraRoot $MetraRoot -ConfigPath $ConfigPath `
        -RuntimePath $RuntimePath -RepairPath $RepairPath -CliPath $CliPath -SkipDebug:$SkipDebug -Observed $Observed

    if ($status.state -eq 'Disabled') { return $status }
    if ($status.state -eq 'MissingCli') { return $status }
    if ($status.state -eq 'Unauthenticated') { return $status }
    if ($status.state -eq 'RepairRequired') { return $status }
    if ($status.state -eq 'Running') { return $status }
    if ($status.state -eq 'Error' -and $status.lastError -match 'Foreign|ambiguous') {
        return $status
    }

    # missing ours -> start
    $started = Start-MetraCursorWorkerDaemon -Config $config -MetraRoot $MetraRoot -CliPath $CliPath -RuntimePath $RuntimePath
    if ([bool](Get-MetraProp -Object $started -Name 'repairRequired' -Default $false)) {
        $repair = Read-MetraCursorWorkerRepairLedger -Path $RepairPath -MetraRoot $MetraRoot
        return (New-MetraCursorWorkerStatusObject -State 'RepairRequired' -Enabled $true -CliPresent $true `
                -Running $false -WorkerName $null -Workspace $null `
                -ExpectedWorkspace $status.expectedWorkspace -IdentityOk $false `
                -LastError ([string]$started.lastError) -AuthOk $true -Repair $repair)
    }
    if (-not $started.ok) {
        $repair = Read-MetraCursorWorkerRepairLedger -Path $RepairPath -MetraRoot $MetraRoot
        return (New-MetraCursorWorkerStatusObject -State 'Error' -Enabled $true -CliPresent $true `
                -Running $false -WorkerName $null -Workspace $null `
                -ExpectedWorkspace $status.expectedWorkspace -IdentityOk $false `
                -LastError ([string]$started.lastError) -AuthOk $true -Repair $repair)
    }

    return (Get-MetraCursorWorkerStatus -MetraRoot $MetraRoot -ConfigPath $ConfigPath `
            -RuntimePath $RuntimePath -RepairPath $RepairPath -CliPath $CliPath -SkipDebug:$SkipDebug)
}

function Invoke-MetraCursorWorkerRepairSqlite {
    <#
    .SYNOPSIS
        Operator-initiated better-sqlite3 ABI repair. Never called from ensure.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [string]$RepairPath,
        [string]$CliPath,
        [switch]$Force,
        [scriptblock]$Downloader
    )
    $cliVersion = Get-MetraCursorWorkerCliVersionName -CliPath $CliPath
    if ([string]::IsNullOrWhiteSpace($cliVersion)) {
        return [pscustomobject]@{
            ok      = $false
            state   = 'MissingCli'
            error   = 'Could not resolve cursor-agent version directory'
            outcome = 'failed'
        }
    }
    $ledger = Read-MetraCursorWorkerRepairLedger -Path $RepairPath -MetraRoot $MetraRoot
    $prevOutcome = [string](Get-MetraProp -Object $ledger -Name 'lastRepairOutcome' -Default '')
    $prevVersion = [string](Get-MetraProp -Object $ledger -Name 'lastRepairVersion' -Default '')
    if (-not $Force -and $prevVersion -eq $cliVersion -and $prevOutcome -eq 'failed') {
        return [pscustomobject]@{
            ok      = $false
            state   = 'RepairRequired'
            error   = "Repair refused: last attempt for $cliVersion failed. Clear ledger or upgrade cursor-agent, or pass -Force."
            outcome = 'skipped'
            repair  = $ledger
        }
    }

    $versionDir = Get-MetraCursorWorkerCliVersionDir -CliPath $CliPath
    $pkgPath = Join-Path $versionDir 'node_modules\better-sqlite3\package.json'
    $targetNode = Join-Path $versionDir 'node_modules\better-sqlite3\build\Release\better_sqlite3.node'
    if (-not (Test-Path -LiteralPath $pkgPath -PathType Leaf)) {
        $ledger.lastRepairAttemptUtc = [datetime]::UtcNow.ToString('o')
        $ledger.lastRepairVersion = $cliVersion
        $ledger.lastRepairOutcome = 'failed'
        Save-MetraCursorWorkerRepairLedger -Ledger $ledger -Path $RepairPath -MetraRoot $MetraRoot
        return [pscustomobject]@{
            ok      = $false
            state   = 'Error'
            error   = "better-sqlite3 package.json missing under $versionDir"
            outcome = 'failed'
            repair  = $ledger
        }
    }
    $pkg = Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $pkgVer = [string]$pkg.version
    $nodeExe = Join-Path $versionDir 'node.exe'
    $abi = '137'
    if (Test-Path -LiteralPath $nodeExe -PathType Leaf) {
        try {
            $abi = & $nodeExe -p 'process.versions.modules' 2>$null
            $abi = ([string]$abi).Trim()
        }
        catch { $abi = '137' }
    }
    if ([string]::IsNullOrWhiteSpace($abi)) { $abi = '137' }

    $asset = "better-sqlite3-v$pkgVer-node-v$abi-win32-x64.tar.gz"
    $url = "https://github.com/WiseLibs/better-sqlite3/releases/download/v$pkgVer/$asset"
    $work = Join-Path ([IO.Path]::GetTempPath()) ('metra-cw-repair-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $archive = Join-Path $work $asset
    $ledger.lastRepairAttemptUtc = [datetime]::UtcNow.ToString('o')
    $ledger.lastRepairVersion = $cliVersion

    try {
        if ($Downloader) {
            & $Downloader $url $archive
        }
        else {
            Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
        }
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
            throw "Download produced no file: $url"
        }
        # tar.exe extracts .tar.gz on modern Windows.
        $extract = Join-Path $work 'extract'
        New-Item -ItemType Directory -Path $extract -Force | Out-Null
        & tar.exe -xzf $archive -C $extract
        if ($LASTEXITCODE -ne 0) { throw "tar extract failed with exit $LASTEXITCODE" }
        $found = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'better_sqlite3.node' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -eq $found) { throw 'Extracted archive did not contain better_sqlite3.node' }
        $destDir = Split-Path -Parent $targetNode
        if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $found.FullName -Destination $targetNode -Force
        $ledger.lastRepairOutcome = 'success'
        Save-MetraCursorWorkerRepairLedger -Ledger $ledger -Path $RepairPath -MetraRoot $MetraRoot
        return [pscustomobject]@{
            ok      = $true
            state   = 'Success'
            message = "Replaced better_sqlite3.node for $cliVersion (package $pkgVer, ABI $abi)"
            outcome = 'success'
            repair  = $ledger
            target  = $targetNode
        }
    }
    catch {
        $ledger.lastRepairOutcome = 'failed'
        Save-MetraCursorWorkerRepairLedger -Ledger $ledger -Path $RepairPath -MetraRoot $MetraRoot
        return [pscustomobject]@{
            ok      = $false
            state   = 'RepairRequired'
            error   = $_.Exception.Message
            outcome = 'failed'
            repair  = $ledger
        }
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

