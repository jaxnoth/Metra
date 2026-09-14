# LoomImplementer.ps1 - Metra host for Loom Slice 3 implementer (one-shot Cursor SDK)

function Get-MetraLoomImplementerScriptPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return (Join-Path $MetraRoot 'engines\cursor\implementer-run.mjs')
}

function Get-MetraLoomImplementerAgentGuidance {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $path = Join-Path $MetraRoot '.cursor\agents\loom-implementer.md'
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    try {
        return [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        return ''
    }
}

function Protect-MetraLoomImplementerText {
    <#
    .SYNOPSIS
        Redact API-key-shaped secrets from diagnostics before return/log.
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $out = [string]$Text
    $key = $null
    try { $key = Get-MetraCursorApiKey -PreferUser } catch { $key = $null }
    if (-not [string]::IsNullOrWhiteSpace($key) -and $out.Contains($key)) {
        $out = $out.Replace($key, '[REDACTED_API_KEY]')
    }
    $out = [regex]::Replace($out, '(?i)(CURSOR_API_KEY\s*[=:]\s*)(\S+)', '${1}[REDACTED]')
    $out = [regex]::Replace($out, '(?i)\b(key_[A-Za-z0-9]{20,})\b', '[REDACTED_API_KEY]')
    return $out
}

function New-MetraLoomImplementerResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Status,
        [string]$Message = '',
        [int]$ExitCode = 1,
        [string]$Stdout = '',
        [string]$Stderr = ''
    )
    return [PSCustomObject]@{
        schemaVersion = 1
        status        = $Status
        message       = Protect-MetraLoomImplementerText -Text $Message
        exitCode      = $ExitCode
        stdout        = Protect-MetraLoomImplementerText -Text $Stdout
        stderr        = Protect-MetraLoomImplementerText -Text $Stderr
    }
}

function Save-MetraLoomImplementerRequestJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$RunDir,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ([string]::IsNullOrWhiteSpace($RunDir)) {
        throw 'RunDir is required.'
    }
    if (-not (Test-Path -LiteralPath $RunDir)) {
        [void][System.IO.Directory]::CreateDirectory($RunDir)
    }
    $reqPath = Join-Path $RunDir 'request.json'
    $guidance = Get-MetraLoomImplementerAgentGuidance -MetraRoot $MetraRoot

    if ($Request -is [string]) {
        $path = [string]$Request
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Request path not found: $path"
        }
        $abs = [System.IO.Path]::GetFullPath($path)
        if ($abs -ne [System.IO.Path]::GetFullPath($reqPath)) {
            Copy-Item -LiteralPath $abs -Destination $reqPath -Force
        }
        # Ensure agentGuidance is present for the Node runner.
        try {
            $obj = Get-Content -LiteralPath $reqPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($guidance -and -not $obj.agentGuidance) {
                $obj | Add-Member -NotePropertyName agentGuidance -NotePropertyValue $guidance -Force
                $json = ($obj | ConvertTo-Json -Depth 12) + "`n"
                [System.IO.File]::WriteAllText($reqPath, $json, [System.Text.UTF8Encoding]::new($false))
            }
        }
        catch { }
        return [System.IO.Path]::GetFullPath($reqPath)
    }

    $hash = [ordered]@{}
    foreach ($p in @($Request.PSObject.Properties)) {
        $hash[$p.Name] = $p.Value
    }
    if ($guidance) { $hash['agentGuidance'] = $guidance }
    if (-not $hash.Contains('schemaVersion')) { $hash['schemaVersion'] = 1 }
    $json = (($hash | ConvertTo-Json -Depth 12) + "`n")
    [System.IO.File]::WriteAllText($reqPath, $json, [System.Text.UTF8Encoding]::new($false))
    return [System.IO.Path]::GetFullPath($reqPath)
}

function Invoke-MetraLoomImplementerProcess {
    <#
    .SYNOPSIS
        Launch implementer-run.mjs with ProjectRoot cwd and child-only API key env.
    .NOTES
        Test seam: inject -Launcher to avoid live Node.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$NodePath,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$RequestPath,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)][string]$CursorModel,
        [Parameter(Mandatory)][string]$CursorOptimizeFor,
        [scriptblock]$Launcher
    )

    if ($Launcher) {
        return & $Launcher $NodePath $ScriptPath $RequestPath $ProjectRoot $ApiKey $CursorModel $CursorOptimizeFor
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $NodePath
    $psi.Arguments = ('"{0}" --request "{1}"' -f $ScriptPath, $RequestPath)
    $psi.WorkingDirectory = $ProjectRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    # EnvironmentVariables starts as a copy of the current process env; set key on child only.
    $psi.EnvironmentVariables['CURSOR_API_KEY'] = $ApiKey
    $psi.EnvironmentVariables['METRA_ASK_MODEL'] = $CursorModel
    $psi.EnvironmentVariables['METRA_ASK_OPTIMIZE_FOR'] = $CursorOptimizeFor

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    # Read stdout/stderr concurrently so a full stderr pipe cannot deadlock WaitForExit.
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $stdout = [string]$stdoutTask.GetAwaiter().GetResult()
    $stderr = [string]$stderrTask.GetAwaiter().GetResult()
    return [PSCustomObject]@{
        ExitCode = [int]$proc.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
        Arguments = [string]$psi.Arguments
        WorkingDirectory = [string]$psi.WorkingDirectory
    }
}

function Invoke-MetraLoomImplementer {
    <#
    .SYNOPSIS
        Loom Slice 3 host: one-shot mutating Cursor SDK implementer.
    .DESCRIPTION
        Persists request.json under RunDir, runs engines/cursor/implementer-run.mjs with
        WorkingDirectory = absolute ProjectRoot. Returns a contract-shaped object for all
        expected failures (does not throw past the Loom adapter for those cases).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$RunDir,
        [string]$MetraRoot = (Get-MetraRoot),
        [scriptblock]$Launcher
    )

    try {
        if ([string]::IsNullOrWhiteSpace($RunDir)) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message 'Missing RunDir.' -ExitCode 2
        }
        if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message 'Missing ProjectRoot.' -ExitCode 2
        }
        if ($null -eq $Request) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message 'Missing or invalid request.' -ExitCode 2
        }

        $projectAbs = $null
        try {
            if (-not (Test-Path -LiteralPath $ProjectRoot)) {
                return New-MetraLoomImplementerResult -Status 'failed' -Message ('ProjectRoot does not exist: {0}' -f $ProjectRoot) -ExitCode 2
            }
            $item = Get-Item -LiteralPath $ProjectRoot
            if (-not $item.PSIsContainer) {
                return New-MetraLoomImplementerResult -Status 'failed' -Message ('ProjectRoot is not a directory: {0}' -f $ProjectRoot) -ExitCode 2
            }
            $projectAbs = [System.IO.Path]::GetFullPath($item.FullName)
        }
        catch {
            return New-MetraLoomImplementerResult -Status 'failed' -Message ('Invalid ProjectRoot: {0}' -f $_.Exception.Message) -ExitCode 2
        }

        $requestPath = $null
        try {
            $requestPath = Save-MetraLoomImplementerRequestJson -Request $Request -RunDir $RunDir -MetraRoot $MetraRoot
        }
        catch {
            return New-MetraLoomImplementerResult -Status 'failed' -Message ('Failure to persist request.json: {0}' -f $_.Exception.Message) -ExitCode 2
        }

        $nodePath = Get-MetraAskNodePath -MetraRoot $MetraRoot
        if ([string]::IsNullOrWhiteSpace($nodePath) -or -not (Test-Path -LiteralPath $nodePath)) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message 'Node runtime missing (Get-MetraAskNodePath).' -ExitCode 127
        }

        $scriptPath = Get-MetraLoomImplementerScriptPath -MetraRoot $MetraRoot
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message ('Implementer script missing: {0}' -f $scriptPath) -ExitCode 127
        }

        $apiKey = Get-MetraCursorApiKey -PreferUser
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message 'CURSOR_API_KEY is missing (authentication error).' -ExitCode 1
        }

        $ask = $null
        try { $ask = Get-MetraAskSettings -MetraRoot $MetraRoot } catch { $ask = $null }
        $rawModel = if ($ask) { [string](Get-MetraProp -Object $ask -Name 'cursorModel' -Default '') } else { '' }
        $rawOpt = if ($ask) { [string](Get-MetraProp -Object $ask -Name 'cursorOptimizeFor' -Default 'cost') } else { 'cost' }
        $resolved = Resolve-MetraAskCursorModelSelection -Model $rawModel -OptimizeFor $rawOpt
        if (-not $resolved -or [string]::IsNullOrWhiteSpace([string]$resolved.cursorModel)) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message 'Model selection returned no usable model.' -ExitCode 1
        }

        $procResult = $null
        try {
            $procResult = Invoke-MetraLoomImplementerProcess `
                -NodePath $nodePath `
                -ScriptPath $scriptPath `
                -RequestPath $requestPath `
                -ProjectRoot $projectAbs `
                -ApiKey $apiKey `
                -CursorModel ([string]$resolved.cursorModel) `
                -CursorOptimizeFor ([string]$resolved.cursorOptimizeFor) `
                -Launcher $Launcher
        }
        catch {
            return New-MetraLoomImplementerResult -Status 'failed' -Message ('Node launch failure: {0}' -f $_.Exception.Message) -ExitCode 1
        }

        if ($null -eq $procResult) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message 'Node launch failure: empty process result.' -ExitCode 1
        }

        # Never echo API key via arguments or returned fields.
        $argsText = [string](Get-MetraProp -Object $procResult -Name 'Arguments' -Default '')
        if ($argsText -and $apiKey -and $argsText.Contains($apiKey)) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message 'API key leaked into process arguments (refused).' -ExitCode 1
        }

        $stdout = [string](Get-MetraProp -Object $procResult -Name 'StdOut' -Default '')
        $stderr = [string](Get-MetraProp -Object $procResult -Name 'StdErr' -Default '')
        $exitCode = [int](Get-MetraProp -Object $procResult -Name 'ExitCode' -Default 1)

        if ([string]::IsNullOrWhiteSpace($stdout)) {
            $msg = 'Empty stdout from implementer process.'
            if (-not [string]::IsNullOrWhiteSpace($stderr)) { $msg = "$msg $stderr" }
            return New-MetraLoomImplementerResult -Status 'failed' -Message $msg -ExitCode $exitCode -Stdout $stdout -Stderr $stderr
        }

        $parsed = $null
        try {
            $parsed = $stdout.Trim() | ConvertFrom-Json
        }
        catch {
            return New-MetraLoomImplementerResult -Status 'failed' -Message ('Malformed JSON stdout: {0}' -f $_.Exception.Message) -ExitCode $(if ($exitCode -ne 0) { $exitCode } else { 1 }) -Stdout $stdout -Stderr $stderr
        }

        if ($null -eq $parsed -or ($parsed -is [System.Array])) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message 'Malformed JSON stdout: expected a JSON object.' -ExitCode 1 -Stdout $stdout -Stderr $stderr
        }

        $status = [string](Get-MetraProp -Object $parsed -Name 'status' -Default '')
        $message = [string](Get-MetraProp -Object $parsed -Name 'message' -Default '')
        if ([string]::IsNullOrWhiteSpace($status)) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message 'Invalid result status (empty).' -ExitCode 1 -Stdout $stdout -Stderr $stderr
        }

        $allowedStatus = @('ok', 'completed', 'failed', 'adapter-unavailable')
        if ($status -notin $allowedStatus) {
            return New-MetraLoomImplementerResult -Status 'failed' -Message ("Unsupported status: $status") -ExitCode 1 -Stdout $stdout -Stderr $stderr
        }

        if ($exitCode -ne 0 -and $status -in @('ok', 'completed')) {
            # Prefer Node-reported failure semantics when exit nonzero.
            $status = 'failed'
            if ([string]::IsNullOrWhiteSpace($message)) {
                $message = "Implementer exited nonzero ($exitCode)."
            }
        }

        if ($status -in @('ok', 'completed') -and $exitCode -eq 0) {
            return New-MetraLoomImplementerResult -Status $status -Message $(if ($message) { $message } else { 'Implementation run completed.' }) -ExitCode 0 -Stdout $stdout -Stderr $stderr
        }

        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "Implementer failed (exit $exitCode)."
        }
        return New-MetraLoomImplementerResult -Status 'failed' -Message $message -ExitCode $(if ($exitCode -ne 0) { $exitCode } else { 1 }) -Stdout $stdout -Stderr $stderr
    }
    catch {
        return New-MetraLoomImplementerResult -Status 'failed' -Message ('Implementer host error: {0}' -f $_.Exception.Message) -ExitCode 1
    }
}
