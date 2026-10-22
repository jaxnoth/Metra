# Metra host adapters for Loom. Domain code calls these only - never scripts/private/*.ps1.

$script:LoomHostRootOverride = $null
$script:LoomAtlasPutOverride = $null
$script:LoomPatternDiffOverride = $null
$script:LoomPatternBlobOverride = $null

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
    $plans = Join-Path $MetraRoot 'plans'
    if (Test-Path -LiteralPath $plans) { [void]$roots.Add($plans) }
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
    $cmd = Get-Command -Name Get-MetraRoutingAmbiguity -Module Metra -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $cmd = Get-Command Get-MetraRoutingAmbiguity -ErrorAction SilentlyContinue
    }
    if (-not $cmd) {
        return [PSCustomObject]@{
            Primary   = $null
            Ambiguous = $true
            Mode      = 'adapter-unavailable'
        }
    }
    return & $cmd -Query $Query -SkipTelemetry:$SkipTelemetry
}

function Test-LoomRoutingResultUnavailable {
    <#
    .SYNOPSIS
        True only for the explicit adapter-unavailable result.
    .DESCRIPTION
        Get-MetraRoutingAmbiguity does not set Mode. Reading a missing property under
        StrictMode throws; callers must use Get-LoomProp rather than $result.Mode.
    #>
    [CmdletBinding()]
    param($Result)
    $mode = [string](Get-LoomProp -Object $Result -Name 'Mode' -Default '')
    return ($mode -eq 'adapter-unavailable')
}

function Resolve-LoomRoutedProjectRoot {
    <#
    .SYNOPSIS
        Existing checkout directory for a scored routing row.
    .DESCRIPTION
        Registry rows use Root as the portfolio label (work, personal) and Path as the
        checkout. A label is not a project root. Prefer Path. Accept Root only when it
        is already a rooted directory that exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Route
    )

    $candidates = @(
        [string](Get-LoomProp -Object $Route -Name 'Path' -Default '')
        [string](Get-LoomProp -Object $Route -Name 'Root' -Default '')
    )
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (-not [System.IO.Path]::IsPathRooted($candidate)) { continue }
        try {
            $full = [System.IO.Path]::GetFullPath($candidate)
        }
        catch { continue }
        if (Test-Path -LiteralPath $full -PathType Container) {
            return $full
        }
    }
    return ''
}

$script:LoomRegistryPolicyOverride = $null

function Get-LoomEmptyRegistryPolicy {
    return [PSCustomObject]@{
        allowedPaths    = @()
        verifyCommands  = @()
        verifyInvalid   = $false
        cursorModel     = ''
    }
}

function ConvertTo-LoomRegistryPolicyStringList {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @($Value)
    }
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text)) { [void]$list.Add($text) }
    }
    return @($list.ToArray())
}

function ConvertTo-LoomRegistryRelativePath {
    <#
    .SYNOPSIS
        Relative repo prefix from a registry loomAllowedPaths entry, or null when unsafe.
    #>
    param([string]$Path)
    $raw = ([string]$Path).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    if ($raw -match '[\r\n\0]') { return $null }
    if ([System.IO.Path]::IsPathRooted($raw)) { return $null }
    if ($raw -match '^[A-Za-z]:' -or $raw.StartsWith('\\') -or $raw.StartsWith('/')) { return $null }
    $norm = ($raw -replace '\\', '/') -replace '^\./', ''
    $norm = $norm.Trim('/')
    if ([string]::IsNullOrWhiteSpace($norm)) { return $null }
    if ($norm -match ':') { return $null }
    foreach ($part in @($norm -split '/')) {
        if ([string]::IsNullOrWhiteSpace($part) -or $part -eq '.' -or $part -eq '..') { return $null }
    }
    return $norm
}

function ConvertTo-LoomRegistryVerifyCommand {
    param([string]$Command)
    $text = ([string]$Command).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    if ($text.Length -gt 240) { return $null }
    if ($text -match '[\r\n\0]') { return $null }
    return $text
}

function ConvertTo-LoomRegistryCursorModel {
    param([string]$Model)
    $text = ([string]$Model).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    if ($text.Length -gt 80) { return '' }
    if ($text -match '[\r\n\0]') { return '' }
    if ($text -match '\.\.') { return '' }
    if ($text -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]{0,79}$') { return '' }
    return $text
}

function Test-LoomRegistryPropertySpecified {
    param(
        $Entry,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Entry) { return $false }
    if ($Entry -is [System.Collections.IDictionary]) {
        foreach ($key in @($Entry.Keys)) {
            if ([string]::Equals([string]$key, $Name, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }
    foreach ($propName in @($Entry.PSObject.Properties.Name)) {
        if ([string]::Equals([string]$propName, $Name, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function ConvertTo-LoomRegistryPolicy {
    param($Entry)
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @(ConvertTo-LoomRegistryPolicyStringList -Value (Get-LoomProp -Object $Entry -Name 'loomAllowedPaths' -Default @()))) {
        $rel = ConvertTo-LoomRegistryRelativePath -Path $raw
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        $seen = $false
        foreach ($have in $paths) {
            if ([string]::Equals($have, $rel, [StringComparison]::OrdinalIgnoreCase)) { $seen = $true; break }
        }
        if (-not $seen) { [void]$paths.Add($rel) }
    }
    $verifySpecified = Test-LoomRegistryPropertySpecified -Entry $Entry -Name 'loomVerifyCommands'
    $commands = New-Object System.Collections.Generic.List[string]
    if ($verifySpecified) {
        foreach ($raw in @(ConvertTo-LoomRegistryPolicyStringList -Value (Get-LoomProp -Object $Entry -Name 'loomVerifyCommands' -Default @()))) {
            $cmd = ConvertTo-LoomRegistryVerifyCommand -Command $raw
            if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
            $seen = $false
            foreach ($have in $commands) {
                if ([string]::Equals($have, $cmd, [StringComparison]::OrdinalIgnoreCase)) { $seen = $true; break }
            }
            if (-not $seen) { [void]$commands.Add($cmd) }
        }
    }
    return [PSCustomObject]@{
        allowedPaths   = @($paths.ToArray())
        verifyCommands = @($commands.ToArray())
        verifyInvalid  = ($verifySpecified -and $commands.Count -eq 0)
        cursorModel    = (ConvertTo-LoomRegistryCursorModel -Model ([string](Get-LoomProp -Object $Entry -Name 'loomCursorModel' -Default '')))
    }
}

function Get-LoomRegistryLoomPolicy {
    <#
    .SYNOPSIS
        Operator Loom policy for one registry project (paths, verify, optional Cursor model).
    .DESCRIPTION
        Reads loomAllowedPaths, loomVerifyCommands, and loomCursorModel from the merged
        registry. Missing Metra or a missing entry yields an empty policy. Plan text cannot
        supply these values.
    #>
    [CmdletBinding()]
    param([string]$RegistryName)

    if ($null -ne $script:LoomRegistryPolicyOverride) {
        return ConvertTo-LoomRegistryPolicy -Entry $script:LoomRegistryPolicyOverride
    }
    if ([string]::IsNullOrWhiteSpace($RegistryName)) {
        return Get-LoomEmptyRegistryPolicy
    }
    $cmd = Get-Command -Name Get-MetraProjectRegistry -Module Metra -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $cmd = Get-Command Get-MetraProjectRegistry -ErrorAction SilentlyContinue
    }
    if (-not $cmd) { return Get-LoomEmptyRegistryPolicy }
    try {
        $registry = & $cmd
    }
    catch {
        return Get-LoomEmptyRegistryPolicy
    }
    $entry = $null
    foreach ($project in @($(Get-LoomProp -Object $registry -Name 'projects' -Default @()))) {
        $name = [string](Get-LoomProp -Object $project -Name 'name' -Default '')
        if ([string]::Equals($name, $RegistryName, [StringComparison]::OrdinalIgnoreCase)) {
            $entry = $project
            break
        }
    }
    if (-not $entry) { return Get-LoomEmptyRegistryPolicy }
    return ConvertTo-LoomRegistryPolicy -Entry $entry
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
    if (Test-LoomRoutingResultUnavailable -Result $amb) {
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
    $primary = Get-LoomProp -Object $amb -Name 'Primary' -Default $null
    if ($primary) {
        $score = [int](Get-LoomProp -Object $primary -Name 'Score' -Default 0)
        $conf = if ($score -ge 2) { 0.90 } elseif ($score -eq 1) { 0.75 } else { 0.50 }
        $root = Resolve-LoomRoutedProjectRoot -Route $primary
        $resolved = [PSCustomObject]@{
            schemaVersion     = 1
            registryName      = [string](Get-LoomProp -Object $primary -Name 'Name' -Default '')
            root              = $root
            routingConfidence = $conf
            routingEvidence   = 'routing-ambiguity-primary'
            minimumConfidence = $min
            eligible          = (($conf -ge $min) -and -not [string]::IsNullOrWhiteSpace($root))
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
        Slice 4 inspect adapter - evidence only; returns discriminated outcome.
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
        $metraRoot = Get-LoomHostRoot
        [void](Import-LoomMetraHostModule -MetraRoot $metraRoot)
        $cmd = Get-Command Invoke-MetraInspectReviewLoop -ErrorAction SilentlyContinue
    }
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
        Slice 3 implementer - Metra host delegate or test scriptblock. No direct scripts/private imports.
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

    try {
        $cmd = Get-Command Invoke-MetraLoomImplementer -ErrorAction SilentlyContinue
        if (-not $cmd) {
            $metraRoot = Get-LoomHostRoot
            $imported = $false
            try {
                $imported = [bool](Import-LoomMetraHostModule -MetraRoot $metraRoot)
            }
            catch {
                return [PSCustomObject]@{
                    schemaVersion = 1
                    status        = 'adapter-unavailable'
                    message       = ('Implementer adapter unavailable (Metra host import failed: {0}).' -f $_.Exception.Message)
                    exitCode      = 127
                }
            }
            if (-not $imported) {
                return [PSCustomObject]@{
                    schemaVersion = 1
                    status        = 'adapter-unavailable'
                    message       = 'Implementer adapter unavailable (Metra host import failed).'
                    exitCode      = 127
                }
            }
            $cmd = Get-Command Invoke-MetraLoomImplementer -ErrorAction SilentlyContinue
        }

        if (-not $cmd) {
            return [PSCustomObject]@{
                schemaVersion = 1
                status        = 'adapter-unavailable'
                message       = 'Implementer adapter unavailable (Invoke-MetraLoomImplementer not loaded).'
                exitCode      = 127
            }
        }

        return & $cmd -Request $Request -ProjectRoot $ProjectRoot -RunDir $RunDir
    }
    catch {
        return [PSCustomObject]@{
            schemaVersion = 1
            status        = 'failed'
            message       = ('Implementer adapter error: {0}' -f $_.Exception.Message)
            exitCode      = 1
        }
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
        Slice 4 verify adapter - structured contract commands from project root.
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
        $metraRoot = Get-LoomHostRoot
        [void](Import-LoomMetraHostModule -MetraRoot $metraRoot)
        $cmd = Get-Command Invoke-MetraInspectPackOnly -ErrorAction SilentlyContinue
    }
    if (-not $cmd) {
        return [PSCustomObject]@{
            outcome  = 'adapter-unavailable'
            packPath = ''
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
            packPath = ''
            message  = $_.Exception.Message
        }
    }
}

function Import-LoomMetraHostModule {
    <#
    .SYNOPSIS
        Ensure Metra host module is loaded so Ask/Inspect cmdlets resolve in Loom-only sessions.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-LoomHostRoot))

    if ([string]::IsNullOrWhiteSpace($MetraRoot)) { $MetraRoot = Get-LoomHostRoot }
    $manifest = Join-Path $MetraRoot 'scripts\Metra.psd1'
    if (-not (Test-Path -LiteralPath $manifest)) {
        return $false
    }
    Import-Module $manifest -Force -ErrorAction SilentlyContinue
    return $true
}

function Invoke-LoomAskCapabilityAdapter {
    <#
    .SYNOPSIS
        Adapter: Metra Ask/inspect engine capability (Slice 6 loop health probe).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    $cmd = Get-Command Get-MetraAskCapability -ErrorAction SilentlyContinue
    if (-not $cmd) {
        [void](Import-LoomMetraHostModule -MetraRoot $MetraRoot)
        $cmd = Get-Command Get-MetraAskCapability -ErrorAction SilentlyContinue
    }
    if (-not $cmd) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-LoomHostRoot
    }
    return & $cmd -MetraRoot $MetraRoot
}

function Get-LoomAtlasCliPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-LoomHostRoot))

    $metraFull = [System.IO.Path]::GetFullPath($MetraRoot)
    $candidates = @(
        (Join-Path (Split-Path -Parent $metraFull) 'Atlas')
        'C:\Projects\Atlas'
    )
    foreach ($c in $candidates) {
        $cli = Join-Path $c 'Atlas.ps1'
        if (Test-Path -LiteralPath $cli) {
            return (Resolve-Path -LiteralPath $cli).Path
        }
    }
    return $null
}

function Invoke-LoomAtlasPutAdapter {
    <#
    .SYNOPSIS
        Adapter: Atlas put (local unless -Publish). Overridable for Pester.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StableId,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$BodyPath,
        [string]$Kind = 'Doc',
        [switch]$Publish,
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    if ($script:LoomAtlasPutOverride) {
        return & $script:LoomAtlasPutOverride -StableId $StableId -Project $Project -Kind $Kind `
            -Title $Title -BodyPath $BodyPath -Publish:$Publish -MetraRoot $MetraRoot
    }

    $cli = Get-LoomAtlasCliPath -MetraRoot $MetraRoot
    if (-not $cli) {
        throw 'Atlas project not found (expected sibling Atlas with Atlas.ps1).'
    }

    $argList = @(
        'put'
        '-StableId', $StableId
        '-Project', $Project
        '-Kind', $Kind
        '-Title', $Title
        '-BodyPath', $BodyPath
        '-Confirm:$false'
    )
    if ($Publish) { $argList += '-Publish' }

    $prev = $ConfirmPreference
    $failed = $false
    $detail = ''
    try {
        $ConfirmPreference = 'None'
        $output = & $cli @argList 2>&1
        if (-not $?) {
            $failed = $true
            $detail = (($output | ForEach-Object { "$_" }) -join '; ').Trim()
        }
    }
    catch {
        $failed = $true
        $detail = $_.Exception.Message
    }
    finally {
        $ConfirmPreference = $prev
    }

    if ($failed) {
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'Atlas put failed' }
        return [PSCustomObject]@{
            ok        = $false
            stableId  = $StableId
            published = [bool]$Publish
            mode      = $(if ($Publish) { 'published' } else { 'local' })
            message   = $detail
        }
    }

    return [PSCustomObject]@{
        ok        = $true
        stableId  = $StableId
        published = [bool]$Publish
        mode      = $(if ($Publish) { 'published' } else { 'local' })
    }
}

function Invoke-LoomPlanBoardAcceptedNotify {
    <#
    .SYNOPSIS
      Fail-open Plan Board notify after verified Loom accepted (never accepted-pending-commit).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Item
    )

    try {
        $cursorPlan = $null
        foreach ($name in @('cursorPlan', 'CursorPlan', 'formalPlanPath', 'planPath', 'planFile', 'sourcePlan')) {
            if ($Item.PSObject.Properties[$name] -and $Item.$name) {
                $cursorPlan = [string]$Item.$name
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($cursorPlan)) {
            $src = $null
            if ($Item.PSObject.Properties['source']) { $src = $Item.source }
            if ($src -and $src.PSObject.Properties['path'] -and $src.path) {
                $cursorPlan = [string]$src.path
            }
        }

        if ([string]::IsNullOrWhiteSpace($cursorPlan)) {
            return
        }

        $cmd = Get-Command Invoke-YarnPlanBoardNotifyFailOpen -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Import-Module (Join-Path (Get-LoomHostRoot) 'modules\Yarn\Yarn.psd1') -Force -ErrorAction SilentlyContinue
            $cmd = Get-Command Invoke-YarnPlanBoardNotifyFailOpen -ErrorAction SilentlyContinue
        }
        if (-not $cmd) {
            return
        }

        $yarnRootCmd = Get-Command Get-MetraYarnRoot -ErrorAction SilentlyContinue
        $yarnRoot = if ($yarnRootCmd) { & $yarnRootCmd } else { $null }
        if ([string]::IsNullOrWhiteSpace($yarnRoot)) {
            return
        }

        & $cmd -Root $yarnRoot -MetraRoot (Get-LoomHostRoot) -CursorPlan $cursorPlan.Trim() -Reason 'LoomAccepted'
    }
    catch {
        Write-Warning ("Plan Board sync after Loom accepted failed (fail-open): {0}" -f $_.Exception.Message)
    }
}
