# Ask engine: capability discovery + loopback /v1/complete client (Cursor is implementer #1).

function Get-MetraAskSettings {
    <#
    .SYNOPSIS
        Reads ask.enabled / ask.engine / provider settings from metra.config.json.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $cfg = $null
    try { $cfg = Get-MetraConfig } catch { $cfg = $null }
    $ask = Get-MetraProp -Object $cfg -Name 'ask' -Default $null

    $enabled = $true
    $engine = 'cursor'
    if ($null -ne $ask) {
        $rawEnabled = Get-MetraProp -Object $ask -Name 'enabled' -Default $true
        $enabled = [bool]$rawEnabled
        $engine = [string](Get-MetraProp -Object $ask -Name 'engine' -Default 'cursor').Trim().ToLowerInvariant()
    }

    if ([string]::IsNullOrWhiteSpace($engine)) { $engine = 'none' }

    $cursor = Get-MetraProp -Object $ask -Name 'cursor' -Default $null
    $port = 7381
    $model = 'composer-2.5'
    if ($null -ne $cursor) {
        $p = Get-MetraProp -Object $cursor -Name 'port' -Default 7381
        if ($p -as [int]) { $port = [int]$p }
        $m = [string](Get-MetraProp -Object $cursor -Name 'model' -Default 'composer-2.5')
        if (-not [string]::IsNullOrWhiteSpace($m)) { $model = $m }
    }

    return [PSCustomObject]@{
        enabled     = $enabled
        engine      = $engine
        cursorPort  = $port
        cursorModel = $model
        metraRoot   = $MetraRoot
    }
}

function Get-MetraAskEngineBaseUrl {
    param([string]$MetraRoot = (Get-MetraRoot))

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    return "http://127.0.0.1:$($settings.cursorPort)"
}

function Get-MetraAskCursorSidecarPath {
    param([string]$MetraRoot = (Get-MetraRoot))

    $dir = Join-Path $MetraRoot 'engines\cursor'
    $candidates = @(
        (Join-Path $dir 'server.mjs'),
        (Join-Path $dir 'server.js'),
        (Join-Path $dir 'dist\server.js')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Get-MetraAskEnginePidFile {
    param([int]$Port = 7381)

    $dir = Join-Path $env:LOCALAPPDATA 'Metra'
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    return Join-Path $dir "ask-engine-$Port.pid"
}

function Test-MetraAskEngineHealth {
    <#
    .SYNOPSIS
        True when the selected Ask engine answers GET /health on loopback.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 2
    )

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if (-not $settings.enabled -or $settings.engine -eq 'none') { return $false }
    if ($settings.engine -ne 'cursor') { return $false }

    try {
        $url = "http://127.0.0.1:$($settings.cursorPort)/health"
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec $TimeoutSec
        return [bool](Get-MetraProp -Object $response -Name 'ok' -Default $false)
    }
    catch {
        return $false
    }
}

function Get-MetraAskCapability {
    <#
    .SYNOPSIS
        Discover Ask engine capability: selected vs available vs reason.
    .DESCRIPTION
        Distinguishes not-runnable / available / selected. Does not start the sidecar.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    $providerLabel = switch ($settings.engine) {
        'cursor' { 'Cursor' }
        'ollama' { 'Ollama' }
        default { $settings.engine }
    }

    $base = [PSCustomObject]@{
        enabled       = [bool]$settings.enabled
        selected      = $false
        available     = $false
        engine        = $settings.engine
        providerLabel = $providerLabel
        reason        = 'ok'
        message       = ''
        port          = $settings.cursorPort
        model         = $settings.cursorModel
    }

    if (-not $settings.enabled -or $settings.engine -eq 'none') {
        $base.reason = 'disabled'
        $base.message = @"
Ask engine unavailable.

Metra can still classify work and show routing,
but no AI engine is currently configured.
"@.Trim()
        return $base
    }

    $base.selected = $true

    if ($settings.engine -ne 'cursor') {
        $base.reason = 'engine_unsupported'
        $base.message = @"
Ask engine unavailable.

Engine '$($settings.engine)' is selected but not implemented yet.
Metra can still classify work and show routing.
"@.Trim()
        return $base
    }

    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        $base.reason = 'node_missing'
        $base.message = @"
Ask engine unavailable.

Node.js is required for the Cursor Ask engine on this machine (operator-tier until the installer ships it).
Metra can still classify work and show routing.
"@.Trim()
        return $base
    }

    $sidecar = Get-MetraAskCursorSidecarPath -MetraRoot $MetraRoot
    if (-not $sidecar) {
        $base.reason = 'sidecar_missing'
        $base.message = @"
Ask engine unavailable.

The Cursor Ask sidecar is not installed under engines/cursor.
Metra can still classify work and show routing.
"@.Trim()
        return $base
    }

    $key = Get-MetraCursorApiKey
    if ([string]::IsNullOrWhiteSpace($key)) {
        $base.reason = 'key_missing'
        $base.message = @"
Ask engine unavailable.

No CURSOR_API_KEY is set (process, User, or Machine).
Metra can still classify work and show routing.
"@.Trim()
        return $base
    }

    if (-not (Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 2)) {
        $base.reason = 'sidecar_down'
        $base.message = @"
Ask engine unavailable.

The Ask engine is selected but not running.
Metra can still classify work and show routing.
"@.Trim()
        return $base
    }

    $base.available = $true
    $base.reason = 'ok'
    $base.message = ''
    return $base
}

function Get-MetraAskRouteCwd {
    <#
    .SYNOPSIS
        Resolves the filesystem cwd for a routed project name (Metra home when unknown).
    #>
    [CmdletBinding()]
    param(
        [string]$Where,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Where) -or $Where -eq 'Metra') {
        return $MetraRoot
    }

    $projects = @(Get-MetraProjects -IncludeNonGit -ErrorAction SilentlyContinue)
    $match = $projects | Where-Object { $_.Name -eq $Where } | Select-Object -First 1
    if ($match -and $match.Path -and (Test-Path -LiteralPath $match.Path)) {
        return [string]$match.Path
    }
    return $MetraRoot
}

function Invoke-MetraAskEngine {
    <#
    .SYNOPSIS
        Calls the Ask engine loopback contract POST /v1/complete.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Cwd,
        [hashtable]$Context = @{},
        [string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 180
    )

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    $url = "http://127.0.0.1:$($settings.cursorPort)/v1/complete"
    $body = @{
        prompt    = $Prompt
        cwd       = $Cwd
        context   = $Context
        mode      = 'answer'
    }
    if ($SessionId) { $body.sessionId = $SessionId }

    $json = $body | ConvertTo-Json -Depth 6 -Compress
    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Body $json -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec
        return [PSCustomObject]@{
            ok        = $true
            message   = [string](Get-MetraProp -Object $response -Name 'message' -Default '')
            engine    = [string](Get-MetraProp -Object $response -Name 'engine' -Default $settings.engine)
            model     = [string](Get-MetraProp -Object $response -Name 'model' -Default $settings.cursorModel)
            sessionId = [string](Get-MetraProp -Object $response -Name 'sessionId' -Default $SessionId)
            status    = [string](Get-MetraProp -Object $response -Name 'status' -Default 'finished')
            error     = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            ok        = $false
            message   = ''
            engine    = $settings.engine
            model     = $settings.cursorModel
            sessionId = $SessionId
            status    = 'error'
            error     = [string]$_.Exception.Message
        }
    }
}

function Start-MetraAskEngine {
    <#
    .SYNOPSIS
        Starts the selected Ask engine sidecar when prerequisites are met (operator-tier).
    .DESCRIPTION
        Temporary until the installer ships Node + sidecar. Never throws for missing deps -
        returns a capability-shaped object so Ops can continue.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $cap = Get-MetraAskCapability -MetraRoot $MetraRoot
    if (-not $cap.selected) { return $cap }
    if ($cap.available) { return $cap }

    # Re-check prerequisites without requiring health (sidecar_down is expected before start).
    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if ($settings.engine -ne 'cursor') { return $cap }

    $node = Get-Command node -ErrorAction SilentlyContinue
    $sidecar = Get-MetraAskCursorSidecarPath -MetraRoot $MetraRoot
    $key = Get-MetraCursorApiKey
    if (-not $node -or -not $sidecar -or [string]::IsNullOrWhiteSpace($key)) {
        return Get-MetraAskCapability -MetraRoot $MetraRoot
    }

    if (Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 1) {
        return Get-MetraAskCapability -MetraRoot $MetraRoot
    }

    $pidFile = Get-MetraAskEnginePidFile -Port $settings.cursorPort

    try {
        $previous = $env:CURSOR_API_KEY
        $env:CURSOR_API_KEY = $key
        $env:METRA_ASK_PORT = "$($settings.cursorPort)"
        $env:METRA_ASK_MODEL = $settings.cursorModel
        $env:METRA_ASK_ENGINE = 'cursor'
        try {
            $proc = Start-Process -FilePath $node.Source -ArgumentList @($sidecar) `
                -WorkingDirectory (Split-Path -Parent $sidecar) `
                -PassThru -WindowStyle Hidden
        }
        finally {
            if ($null -eq $previous) { Remove-Item Env:CURSOR_API_KEY -ErrorAction SilentlyContinue }
            else { $env:CURSOR_API_KEY = $previous }
            Remove-Item Env:METRA_ASK_PORT -ErrorAction SilentlyContinue
            Remove-Item Env:METRA_ASK_MODEL -ErrorAction SilentlyContinue
            Remove-Item Env:METRA_ASK_ENGINE -ErrorAction SilentlyContinue
        }
        Set-Content -LiteralPath $pidFile -Value $proc.Id -Encoding ASCII

        $deadline = [datetime]::UtcNow.AddSeconds(20)
        while ([datetime]::UtcNow -lt $deadline) {
            if (Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 1) { break }
            Start-Sleep -Milliseconds 400
        }
    }
    catch {
        Write-Warning "Ask engine start failed: $($_.Exception.Message)"
    }

    return Get-MetraAskCapability -MetraRoot $MetraRoot
}

function Stop-MetraAskEngine {
    <#
    .SYNOPSIS
        Stops the Ask engine sidecar for the configured (or given) port.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Port = 0
    )

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if ($Port -le 0) { $Port = $settings.cursorPort }

    $pidFile = Get-MetraAskEnginePidFile -Port $Port
    $target = $null
    if (Test-Path -LiteralPath $pidFile) {
        $recorded = 0
        if ([int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$recorded)) {
            if ($recorded -ne $PID -and (Get-Process -Id $recorded -ErrorAction SilentlyContinue)) {
                $target = $recorded
            }
        }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }

    if ($target) {
        try {
            Stop-Process -Id $target -Force -ErrorAction Stop
            Write-Host "Stopped Ask engine on port $Port (process $target)." -ForegroundColor DarkGray
        }
        catch {
            Write-Warning "Could not stop Ask engine process $target - $($_.Exception.Message)"
        }
    }
}
