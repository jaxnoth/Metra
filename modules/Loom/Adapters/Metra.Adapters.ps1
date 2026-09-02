# Metra host adapters for Loom. Domain code calls these only — never scripts/private/*.ps1.

function Get-LoomHostRoot {
    [CmdletBinding()]
    param()
    if ($script:LoomHostRootOverride) {
        return [System.IO.Path]::GetFullPath([string]$script:LoomHostRootOverride)
    }
    $cmd = Get-Command Get-MetraRoot -ErrorAction SilentlyContinue
    if ($cmd) {
        return & $cmd
    }
    $modRoot = $PSScriptRoot
    while ($modRoot -and (Split-Path -Leaf $modRoot) -ne 'Loom') {
        $modRoot = Split-Path -Parent $modRoot
    }
    if ($modRoot) {
        $candidate = Split-Path -Parent (Split-Path -Parent $modRoot)
        if (Test-Path -LiteralPath (Join-Path $candidate 'metra.ps1')) {
            return $candidate
        }
    }
    throw 'Loom host root unavailable (Metra not loaded and metra.ps1 not found).'
}

function Get-LoomInspectPlanRoots {
    [CmdletBinding()]
    param(
        [string]$MetraRoot
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-LoomHostRoot
    }
    $cmd = Get-Command Get-MetraInspectPlanRoots -ErrorAction SilentlyContinue
    if ($cmd) {
        return @(& $cmd -MetraRoot $MetraRoot)
    }
    $roots = New-Object System.Collections.Generic.List[string]
    $cursor = Join-Path $env:USERPROFILE '.cursor\plans'
    if (Test-Path -LiteralPath $cursor) { [void]$roots.Add($cursor) }
    $docs = Join-Path $MetraRoot 'docs'
    if (Test-Path -LiteralPath $docs) { [void]$roots.Add($docs) }
    return @($roots)
}

function Test-LoomRoutingAdapterAvailable {
    [CmdletBinding()]
    param()
    return $null -ne (Get-Command Get-MetraRoutingAmbiguity -ErrorAction SilentlyContinue)
}

function Test-LoomCaptureAdapterAvailable {
    [CmdletBinding()]
    param()
    return $null -ne (Get-Command Get-MetraCaptureLedger -ErrorAction SilentlyContinue)
}

function Get-LoomRoutingAmbiguity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [switch]$SkipTelemetry
    )
    if (-not (Test-LoomRoutingAdapterAvailable)) {
        return [PSCustomObject]@{
            Primary   = $null
            Ambiguous = $true
            Mode      = 'adapter-unavailable'
        }
    }
    return & (Get-Command Get-MetraRoutingAmbiguity) -Query $Query -SkipTelemetry:$SkipTelemetry
}

function Get-LoomCaptureLedger {
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [int]$Limit = 40,
        [string]$Status = 'candidate'
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-LoomHostRoot
    }
    if (-not (Test-LoomCaptureAdapterAvailable)) {
        return @()
    }
    return @(& (Get-Command Get-MetraCaptureLedger) -MetraRoot $MetraRoot -Limit $Limit -Status $Status)
}

function Get-LoomRoutingContext {
    <#
    .SYNOPSIS
        Adapter: routing-context.result shape (Contracts/v1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request
    )
    $query = [string](Get-LoomProp -Object $Request -Name 'query' -Default '')
    $planPath = [string](Get-LoomProp -Object $Request -Name 'planPath' -Default '')
    $min = 0.85
    if (-not [string]::IsNullOrWhiteSpace($planPath) -and (Test-Path -LiteralPath $planPath)) {
        $hostRoot = Get-LoomHostRoot
        if (Test-LoomPathWithinRoot -Path $planPath -Root $hostRoot) {
            $fromPlan = [PSCustomObject]@{
                schemaVersion       = 1
                registryName        = 'Metra'
                root                = $hostRoot
                routingConfidence   = 0.99
                routingEvidence     = 'plan-path-under-metra-root'
                minimumConfidence   = $min
                eligible            = $true
            }
            Test-LoomContract -Schema 'routing-context.result' -Object $fromPlan | Out-Null
            return $fromPlan
        }
    }
    $amb = Get-LoomRoutingAmbiguity -Query $(if ($query) { $query } else { $planPath }) -SkipTelemetry
    if ($amb.Mode -eq 'adapter-unavailable') {
        $invalid = [PSCustomObject]@{
            schemaVersion     = 1
            registryName      = ''
            root              = ''
            routingConfidence = 0.0
            routingEvidence   = 'adapter-unavailable'
            minimumConfidence = $min
            eligible          = $false
        }
        Test-LoomContract -Schema 'routing-context.result' -Object $invalid | Out-Null
        return $invalid
    }
    if ($amb.Primary) {
        $score = [int]$amb.Primary.Score
        $conf = if ($score -ge 2) { 0.90 } elseif ($score -eq 1) { 0.75 } else { 0.50 }
        $resolved = [PSCustomObject]@{
            schemaVersion     = 1
            registryName      = [string]$amb.Primary.Name
            root              = [string]$amb.Primary.Root
            routingConfidence = $conf
            routingEvidence   = 'routing-ambiguity-primary'
            minimumConfidence = $min
            eligible          = ($conf -ge $min)
        }
        Test-LoomContract -Schema 'routing-context.result' -Object $resolved | Out-Null
        return $resolved
    }
    $unresolved = [PSCustomObject]@{
        schemaVersion     = 1
        registryName      = ''
        root              = ''
        routingConfidence = 0.0
        routingEvidence   = 'unresolved'
        minimumConfidence = $min
        eligible          = $false
    }
    Test-LoomContract -Schema 'routing-context.result' -Object $unresolved | Out-Null
    return $unresolved
}

function ConvertTo-LoomInspectOutcomeFromEngine {
    param(
        [object]$LoopResult,
        [string]$Message
    )
    $msg = [string]$Message
    if ($msg -match 'usage limit|quota|billing|authentication|licensing|unauthorized') {
        return 'terminal-engine-failure'
    }
    if ($msg -match 'timeout|unavailable|sidecar|connection|transient') {
        return 'transient-engine-failure'
    }
    if ($LoopResult) {
        $critical = [int](Get-LoomProp -Object $LoopResult -Name 'CriticalCount' -Default 0)
        $high = [int](Get-LoomProp -Object $LoopResult -Name 'HighCount' -Default 0)
        $medium = [int](Get-LoomProp -Object $LoopResult -Name 'MediumCount' -Default 0)
        $term = [string](Get-LoomProp -Object $LoopResult -Name 'TerminationReason' -Default '')
        if ($term -match 'regression') {
            return 'regression-reverted'
        }
        if ($critical -eq 0 -and $high -eq 0 -and $medium -le 2) {
            return 'passed'
        }
        return 'code-findings'
    }
    return 'invalid-result'
}

function Invoke-LoomInspectAdapter {
    <#
    .SYNOPSIS
        Slice 4 inspect adapter — evidence only; returns discriminated outcome.
    #>
    [CmdletBinding()]
    param(
        $Request,
        [string]$ProjectRoot,
        [string]$RunDir,
        [scriptblock]$InspectScript
    )

    if ($InspectScript) {
        $raw = & $InspectScript $Request $ProjectRoot $RunDir
        if ($raw.outcome) { return $raw }
        return [PSCustomObject]@{
            schemaVersion = 1
            outcome       = [string](Get-LoomProp -Object $raw -Name 'outcome' -Default 'invalid-result')
            status        = [string](Get-LoomProp -Object $raw -Name 'status' -Default '')
            goalMet       = [bool](Get-LoomProp -Object $raw -Name 'goalMet' -Default $false)
            message       = [string](Get-LoomProp -Object $raw -Name 'message' -Default '')
        }
    }

    $registry = [string](Get-LoomProp -Object $Request -Name 'registryName' -Default '')
    if ([string]::IsNullOrWhiteSpace($registry)) {
        $registry = [string](Get-LoomProp -Object $Request -Name 'projectName' -Default '')
    }
    $cmd = Get-Command Invoke-MetraInspectReviewLoop -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $result = [PSCustomObject]@{
            schemaVersion = 1
            outcome       = 'adapter-unavailable'
            status        = 'adapter-unavailable'
            goalMet       = $false
            message       = 'Inspect adapter unavailable (Invoke-MetraInspectReviewLoop not loaded).'
        }
        Test-LoomContract -Schema 'inspect-result' -Object $result | Out-Null
        return $result
    }

    try {
        $loop = & $cmd -Name $registry -RunAll -MaxLoops 5
        $outcome = ConvertTo-LoomInspectOutcomeFromEngine -LoopResult $loop -Message ''
        $critical = [int](Get-LoomProp -Object $loop -Name 'CriticalCount' -Default 0)
        $high = [int](Get-LoomProp -Object $loop -Name 'HighCount' -Default 0)
        $medium = [int](Get-LoomProp -Object $loop -Name 'MediumCount' -Default 0)
        $result = [PSCustomObject]@{
            schemaVersion = 1
            outcome       = $outcome
            status        = $outcome
            goalMet       = ($outcome -eq 'passed')
            message       = "inspect loop: C=$critical H=$high M=$medium"
            criticalCount = $critical
            highCount     = $high
            mediumCount   = $medium
        }
        if ($outcome -eq 'regression-reverted') {
            $result | Add-Member -NotePropertyName workspaceMutation -NotePropertyValue 'reverted' -Force
            if ($ProjectRoot) {
                $result | Add-Member -NotePropertyName afterCommit -NotePropertyValue (Get-LoomGitHeadCommit -ProjectRoot $ProjectRoot) -Force
            }
        }
        Test-LoomContract -Schema 'inspect-result' -Object $result | Out-Null
        return $result
    }
    catch {
        $msg = $_.Exception.Message
        $outcome = ConvertTo-LoomInspectOutcomeFromEngine -LoopResult $null -Message $msg
        $result = [PSCustomObject]@{
            schemaVersion = 1
            outcome       = $outcome
            status        = $outcome
            goalMet       = $false
            message       = $msg
        }
        Test-LoomContract -Schema 'inspect-result' -Object $result | Out-Null
        return $result
    }
}

function Invoke-LoomImplementerAdapter {
    <#
    .SYNOPSIS
        Slice 3 implementer — Metra host delegate or test scriptblock. No direct scripts/private imports.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$RunDir,
        [scriptblock]$ImplementerScript
    )

    if ($ImplementerScript) {
        return & $ImplementerScript $Request $ProjectRoot $RunDir
    }

    $cmd = Get-Command Invoke-MetraLoomImplementer -ErrorAction SilentlyContinue
    if ($cmd) {
        return & $cmd -Request $Request -ProjectRoot $ProjectRoot -RunDir $RunDir
    }

    return [PSCustomObject]@{
        schemaVersion = 1
        status        = 'adapter-unavailable'
        message       = 'Implementer adapter unavailable (Invoke-MetraLoomImplementer not loaded).'
        exitCode      = 127
    }
}

function Stop-LoomVerifyProcess {
    [CmdletBinding()]
    param([System.Diagnostics.Process]$Process)
    if (-not $Process) { return }
    try {
        if (-not $Process.HasExited) { $Process.Kill($true) }
    }
    catch {
        try {
            if (-not $Process.HasExited) { $Process.Kill() }
        }
        catch { }
    }
}

function Invoke-LoomVerifyAdapter {
    <#
    .SYNOPSIS
        Slice 4 verify adapter — structured contract commands from project root.
    #>
    [CmdletBinding()]
    param(
        $Request,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$RunDir,
        [scriptblock]$VerifyScript
    )

    if ($VerifyScript) {
        $raw = & $VerifyScript $Request $ProjectRoot $RunDir
        if ($raw.outcome) { return $raw }
        $passed = [bool](Get-LoomProp -Object $raw -Name 'passed' -Default $false)
        return [PSCustomObject]@{
            schemaVersion = 1
            outcome       = $(if ($passed) { 'passed' } else { 'command-failed' })
            passed        = $passed
            message       = [string](Get-LoomProp -Object $raw -Name 'message' -Default '')
        }
    }

    $rawCommands = @($(Get-LoomProp -Object $Request -Name 'verifyCommands' -Default @()))
    if ($rawCommands.Count -eq 0) {
        $contract = Get-LoomProp -Object $Request -Name 'contract' -Default $null
        if ($contract) {
            $rawCommands = @($(Get-LoomProp -Object $contract -Name 'verifyCommands' -Default @()))
        }
    }
    if ($rawCommands.Count -eq 0) {
        $result = [PSCustomObject]@{
            schemaVersion = 1
            outcome       = 'invalid-contract'
            passed        = $false
            message       = 'No verifyCommands in request.'
        }
        Test-LoomContract -Schema 'verify-result' -Object $result | Out-Null
        return $result
    }

    $structured = @()
    foreach ($c in $rawCommands) {
        $s = ConvertTo-LoomStructuredVerifyCommand -Command $c
        if (-not $s -or [string]::IsNullOrWhiteSpace($s.executable)) {
            $result = [PSCustomObject]@{
                schemaVersion = 1
                outcome       = 'invalid-contract'
                passed        = $false
                message       = 'Malformed verify command entry.'
            }
            Test-LoomContract -Schema 'verify-result' -Object $result | Out-Null
            return $result
        }
        $structured += $s
    }

    $cwdBefore = Get-Location
    $cmdIndex = 0
    try {
        foreach ($cmd in $structured) {
            $cmdIndex++
            $workDir = Resolve-LoomVerifyWorkingDirectory -ProjectRoot $ProjectRoot -WorkingDirectory ([string]$cmd.workingDirectory)
            $timeout = [int]$cmd.timeoutSeconds
            if ($timeout -le 0) { $timeout = 900 }

            $stdoutPath = Join-Path $RunDir ("verify-{0}-stdout.log" -f $cmdIndex)
            $stderrPath = Join-Path $RunDir ("verify-{0}-stderr.log" -f $cmdIndex)

            try {
                $proc = Start-Process -FilePath ([string]$cmd.executable) `
                    -ArgumentList @($cmd.arguments) `
                    -WorkingDirectory $workDir `
                    -RedirectStandardOutput $stdoutPath `
                    -RedirectStandardError $stderrPath `
                    -PassThru -NoNewWindow
            }
            catch {
                $result = [PSCustomObject]@{
                    schemaVersion = 1
                    outcome       = 'launch-failed'
                    passed        = $false
                    message       = $_.Exception.Message
                    failedCommand = [string]$cmd.executable
                }
                Test-LoomContract -Schema 'verify-result' -Object $result | Out-Null
                return $result
            }

            if (-not $proc.WaitForExit($timeout * 1000)) {
                Stop-LoomVerifyProcess -Process $proc
                $result = [PSCustomObject]@{
                    schemaVersion = 1
                    outcome       = 'command-timeout'
                    passed        = $false
                    message       = "Verify command timed out after ${timeout}s"
                    failedCommand = [string]$cmd.executable
                    stdoutPath    = $stdoutPath
                    stderrPath    = $stderrPath
                }
                Test-LoomContract -Schema 'verify-result' -Object $result | Out-Null
                return $result
            }

            if ($proc.ExitCode -ne 0) {
                $result = [PSCustomObject]@{
                    schemaVersion = 1
                    outcome       = 'command-failed'
                    passed        = $false
                    message       = "Verify command failed with exit $($proc.ExitCode)"
                    failedCommand = [string]$cmd.executable
                    exitCode      = $proc.ExitCode
                    stdoutPath    = $stdoutPath
                    stderrPath    = $stderrPath
                    logPath       = $stderrPath
                }
                Test-LoomContract -Schema 'verify-result' -Object $result | Out-Null
                return $result
            }
        }

        $ok = [PSCustomObject]@{
            schemaVersion = 1
            outcome       = 'passed'
            passed        = $true
            message       = 'All verify commands passed.'
        }
        Test-LoomContract -Schema 'verify-result' -Object $ok | Out-Null
        return $ok
    }
    finally {
        Set-Location -LiteralPath $cwdBefore.Path
    }
}

function Invoke-LoomInspectPackAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Base,
        [string]$ProjectRoot,
        [scriptblock]$PackScript
    )

    if ($PackScript) {
        return & $PackScript $Name $Base $ProjectRoot
    }

    $cmd = Get-Command Invoke-MetraInspectPackOnly -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [PSCustomObject]@{
            outcome  = 'adapter-unavailable'
            packPath = $null
            message  = 'Invoke-MetraInspectPackOnly not loaded.'
        }
    }

    try {
        $result = & $cmd -Mode diff -Name $Name -Base $Base
        $packPath = [string](Get-LoomProp -Object $result -Name 'packPath' -Default '')
        if ([string]::IsNullOrWhiteSpace($packPath)) {
            $packPath = [string](Get-LoomProp -Object $result -Name 'Path' -Default '')
        }
        return [PSCustomObject]@{
            outcome  = 'ok'
            packPath = $packPath
            message  = [string](Get-LoomProp -Object $result -Name 'message' -Default '')
            raw      = $result
        }
    }
    catch {
        return [PSCustomObject]@{
            outcome  = 'failed'
            packPath = $null
            message  = $_.Exception.Message
        }
    }
}
