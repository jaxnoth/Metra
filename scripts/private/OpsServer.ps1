# HTML Ops local HTTP server (loopback only). Face = ops/dist; brain = desk payload helpers.

function Get-MetraOpsDistPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return Join-Path $MetraRoot 'ops\dist'
}

function Get-MetraOpsContentType {
    param([Parameter(Mandatory)][string]$Path)

    switch -Regex ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '^\.html?$' { return 'text/html; charset=utf-8' }
        '^\.js$' { return 'application/javascript; charset=utf-8' }
        '^\.css$' { return 'text/css; charset=utf-8' }
        '^\.json$' { return 'application/json; charset=utf-8' }
        '^\.svg$' { return 'image/svg+xml' }
        '^\.png$' { return 'image/png' }
        '^\.ico$' { return 'image/x-icon' }
        '^\.woff2?$' { return 'font/woff2' }
        default { return 'application/octet-stream' }
    }
}

function Read-MetraOpsRequestBody {
    param([Parameter(Mandatory)]$Request)

    if (-not $Request.HasEntityBody) { return '' }
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }
}

function Write-MetraOpsJsonResponse {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)]$Object,
        [int]$StatusCode = 200
    )

    $json = ($Object | ConvertTo-Json -Depth 10 -Compress)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.Headers['Cache-Control'] = 'no-store'
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Write-MetraOpsTextResponse {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$Text,
        [int]$StatusCode = 200,
        [string]$ContentType = 'text/plain; charset=utf-8'
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Write-MetraOpsFileResponse {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$FilePath
    )

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $Response.StatusCode = 200
    $Response.ContentType = Get-MetraOpsContentType -Path $FilePath
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Invoke-MetraOpsApi {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Response,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $method = $Request.HttpMethod.ToUpperInvariant()
    $path = $Request.Url.AbsolutePath.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($path)) { $path = '/' }

    try {
        if ($method -eq 'GET' -and $path -eq '/api/meta') {
            # Read the version without Import-PowerShellDataFile: that command does not always
            # resolve from module scope under Windows PowerShell, which 500s this endpoint.
            $manifestVersion = [string](Get-Module -Name Metra | Select-Object -First 1).Version
            if (-not $manifestVersion) {
                $psd1 = Join-Path $MetraRoot 'scripts\Metra.psd1'
                if (Test-Path -LiteralPath $psd1) {
                    $match = [regex]::Match((Get-Content -LiteralPath $psd1 -Raw), "ModuleVersion\s*=\s*'([^']+)'")
                    if ($match.Success) { $manifestVersion = $match.Groups[1].Value }
                }
            }
            Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                    version   = $manifestVersion
                    metraRoot = $MetraRoot
                    homeLabel = $MetraRoot
                })
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/snapshot') {
            $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot
            Write-MetraOpsJsonResponse -Response $Response -Object $payload
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/refresh') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $full = $false
            if ($body) {
                try {
                    $parsed = $body | ConvertFrom-Json
                    $full = [bool](Get-MetraProp -Object $parsed -Name 'full' -Default $false)
                }
                catch { }
            }
            $payload = Get-MetraDeskPayload -Refresh -Full:$full -MetraRoot $MetraRoot
            Write-MetraOpsJsonResponse -Response $Response -Object $payload
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/preferences') {
            Write-MetraOpsJsonResponse -Response $Response -Object (Get-MetraDeskPreferences -MetraRoot $MetraRoot)
            return
        }

        if ($method -eq 'PUT' -and $path -eq '/api/preferences') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $body | ConvertFrom-Json
            $mode = [string](Get-MetraProp -Object $parsed -Name 'deskMode' -Default 'general')
            if ($mode -notin @('general', 'advanced')) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'deskMode must be general or advanced' })
                return
            }
            $prefs = Set-MetraDeskPreferences -DeskMode $mode -MetraRoot $MetraRoot
            Write-MetraOpsJsonResponse -Response $Response -Object $prefs
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/ask') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            if ($body) { $parsed = $body | ConvertFrom-Json }
            $prompt = [string](Get-MetraProp -Object $parsed -Name 'prompt' -Default '')
            $sessionId = [string](Get-MetraProp -Object $parsed -Name 'sessionId' -Default '')
            if ([string]::IsNullOrWhiteSpace($prompt)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'prompt required' })
                return
            }
            $ask = Get-MetraDeskAskResult -Prompt $prompt -SessionId $sessionId -MetraRoot $MetraRoot
            $entry = Add-MetraDeskAskEntry -Prompt $prompt -Handoff $ask.handoff -MetraRoot $MetraRoot
            Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                    entry      = $entry
                    handoff    = $ask.handoff
                    message    = [string]$ask.message
                    sessionId  = $ask.sessionId
                    capability = $ask.capability
                    engine     = $ask.engine
                    model      = $ask.model
                    answered   = [bool]$ask.answered
                })
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/classify') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            if ($body) { $parsed = $body | ConvertFrom-Json }
            $query = [string](Get-MetraProp -Object $parsed -Name 'query' -Default '')
            if ([string]::IsNullOrWhiteSpace($query)) {
                $query = [string](Get-MetraProp -Object $parsed -Name 'prompt' -Default '')
            }
            $handoff = Get-MetraDeskHandoff -Query $query -MetraRoot $MetraRoot
            Write-MetraOpsJsonResponse -Response $Response -Object $handoff
            return
        }

        Write-MetraOpsJsonResponse -Response $Response -StatusCode 404 -Object ([PSCustomObject]@{ error = 'not found' })
    }
    catch {
        Write-MetraOpsJsonResponse -Response $Response -StatusCode 500 -Object ([PSCustomObject]@{
                error = [string]$_.Exception.Message
            })
    }
}

function Invoke-MetraOpsStatic {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$DistPath
    )

    $rel = [System.Uri]::UnescapeDataString($Request.Url.AbsolutePath.TrimStart('/'))
    if ([string]::IsNullOrWhiteSpace($rel) -or $rel -eq '/') {
        $rel = 'index.html'
    }
    $rel = $rel -replace '/', '\'
    if ($rel.Contains('..')) {
        Write-MetraOpsTextResponse -Response $Response -StatusCode 400 -Text 'Bad path'
        return
    }

    $candidate = Join-Path $DistPath $rel
    if (-not (Test-Path -LiteralPath $candidate) -or (Get-Item -LiteralPath $candidate) -isnot [System.IO.FileInfo]) {
        # SPA fallback
        $candidate = Join-Path $DistPath 'index.html'
    }
    if (-not (Test-Path -LiteralPath $candidate)) {
        Write-MetraOpsTextResponse -Response $Response -StatusCode 404 -Text 'Ops UI not built. Run npm run build in ops/ (contributors) or reinstall Metra.'
        return
    }

    Write-MetraOpsFileResponse -Response $Response -FilePath $candidate
}

function Get-MetraOpsPidFile {
    param([int]$Port = 7380)

    $dir = Join-Path $env:LOCALAPPDATA 'Metra'
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    return Join-Path $dir "ops-$Port.pid"
}

function Test-MetraOpsDeskResponding {
    <#
    .SYNOPSIS
        True when a Metra desk already answers on the loopback port.
    #>
    param(
        [int]$Port = 7380,
        [int]$TimeoutSec = 3
    )

    try {
        $api = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/meta" -UseBasicParsing -TimeoutSec $TimeoutSec
        if ($api.StatusCode -eq 200) { return $true }
    }
    catch { }

    # An API fault still means a desk owns the port, so fall back to the served shell.
    try {
        $root = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec $TimeoutSec
        return ($root.StatusCode -eq 200 -and $root.Content -match 'Metra Ops')
    }
    catch {
        return $false
    }
}

function Get-MetraOpsListenerProcessId {
    <#
    .SYNOPSIS
        Finds the process holding an HTTP.sys registration for the loopback port.
    .DESCRIPTION
        Get-NetTCPConnection reports PID 4 (System) for every HttpListener, so ask HTTP.sys
        which process owns the request queue that registered this URL. Recovers desks whose
        console died while the process kept the port.
    #>
    param([int]$Port = 7380)

    try {
        $lines = netsh http show servicestate view=requestq 2>$null
    }
    catch {
        return $null
    }
    if (-not $lines) { return $null }

    $ownerPid = $null
    foreach ($line in $lines) {
        # The Processes block precedes the URL groups it registered.
        $owner = [regex]::Match($line, 'ID:\s*(\d+),\s*image:')
        if ($owner.Success) {
            $ownerPid = [int]$owner.Groups[1].Value
            continue
        }
        if ($line -match ":$Port(:|/)") {
            if ($ownerPid -and $ownerPid -ne $PID) { return $ownerPid }
        }
    }
    return $null
}

function Stop-MetraOpsServer {
    <#
    .SYNOPSIS
        Stops a Metra Ops desk on a loopback port, including one orphaned by a closed console.
    #>
    [CmdletBinding()]
    param([int]$Port = 7380)

    $pidFile = Get-MetraOpsPidFile -Port $Port
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

    if (-not $target) {
        $target = Get-MetraOpsListenerProcessId -Port $Port
    }

    if (-not $target) {
        Write-Host "No Metra Ops desk found on port $Port." -ForegroundColor DarkGray
        return
    }

    try {
        Stop-Process -Id $target -Force -ErrorAction Stop
        Write-Host "Stopped Metra Ops desk on port $Port (process $target)." -ForegroundColor Green
        try { Stop-MetraAskEngine } catch { }
    }
    catch {
        throw "Could not stop process $target holding port $Port - $($_.Exception.Message)"
    }
}

function Start-MetraOpsServer {
    <#
    .SYNOPSIS
        Starts the HTML Ops localhost server and optionally opens the browser.
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 7380,
        [switch]$Quick,
        [switch]$Full,
        [switch]$NoBrowser,
        [switch]$NoRefresh,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "Invalid port: $Port"
    }

    $url = "http://127.0.0.1:$Port"
    if (Test-MetraOpsDeskResponding -Port $Port) {
        Write-Host ("Metra Ops desk already serving {0}" -f $url) -ForegroundColor Green
        Write-Host ("Restart it with: .\metra.ps1 ops -Stop -Port {0}" -f $Port) -ForegroundColor DarkGray
        if (-not $NoBrowser) {
            try { Start-Process $url | Out-Null } catch { }
        }
        return
    }

    $dist = Get-MetraOpsDistPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath (Join-Path $dist 'index.html'))) {
        Write-Warning "Missing ops/dist (expected index.html under $dist). Build with: cd ops; npm install; npm run build"
    }

    if (-not $NoRefresh) {
        Write-Host 'Refreshing desk snapshot...' -ForegroundColor Cyan
        $null = Get-MetraDeskPayload -Refresh -Full:$Full -MetraRoot $MetraRoot
    }

    $prefix = "http://127.0.0.1:$Port/"
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($prefix)
    try {
        $listener.Start()
    }
    catch {
        $held = Get-MetraOpsListenerProcessId -Port $Port
        $hint = if ($held) {
            "Process $held still holds it (a desk whose console closed?). Free it with: .\metra.ps1 ops -Stop -Port $Port"
        }
        else {
            "Try -Port with another number."
        }
        throw "Could not bind $prefix - $($_.Exception.Message). $hint"
    }

    $pidFile = Get-MetraOpsPidFile -Port $Port
    Set-Content -LiteralPath $pidFile -Value $PID -Encoding ASCII

    Write-Host ("Metra Ops desk: {0}" -f $url) -ForegroundColor Green
    Write-Host 'Loopback only. Press Ctrl+C to stop.' -ForegroundColor DarkGray

    # Operator-tier Ask engine (temporary until installer ships Node + sidecar).
    $askCap = Start-MetraAskEngine -MetraRoot $MetraRoot
    if ($askCap.available) {
        Write-Host ("Ask engine available ({0})." -f $askCap.providerLabel) -ForegroundColor DarkGray
    }
    elseif ($askCap.selected) {
        Write-Host ("Ask engine selected but unavailable ({0})." -f $askCap.reason) -ForegroundColor DarkYellow
    }

    if (-not $NoBrowser) {
        try {
            Start-Process $url | Out-Null
        }
        catch {
            Write-Warning "Could not open browser: $($_.Exception.Message)"
        }
    }

    # GetContext() blocks forever and swallows Ctrl+C, so poll BeginGetContext instead: the
    # timed waits give PowerShell statement boundaries where it can deliver its own Ctrl+C
    # (PipelineStopped) and run the finally block below.
    #
    # Do not register a [System.ConsoleCancelEventHandler] scriptblock here. .NET invokes that
    # delegate on the console control thread, and a scriptblock cannot run there while this
    # runspace is busy in the accept loop - the resulting exception is unhandled on a native
    # callback thread and takes the whole console host down instead of stopping the server.
    try {
        while ($listener.IsListening) {
            $async = $null
            try {
                $async = $listener.BeginGetContext($null, $null)
            }
            catch {
                break
            }

            while (-not $async.IsCompleted) {
                if (-not $listener.IsListening) { break }
                # Timed wait lets Ctrl+C / pipeline stop run between polls.
                if ($async.AsyncWaitHandle.WaitOne(250)) { break }
            }

            if (-not $listener.IsListening) { break }
            if (-not $async.IsCompleted) { continue }

            try {
                $context = $listener.EndGetContext($async)
            }
            catch {
                break
            }

            $req = $context.Request
            $res = $context.Response
            $res.Headers['Access-Control-Allow-Origin'] = '*'
            $res.Headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, OPTIONS'
            $res.Headers['Access-Control-Allow-Headers'] = 'Content-Type'

            if ($req.HttpMethod -eq 'OPTIONS') {
                $res.StatusCode = 204
                $res.Close()
                continue
            }

            if ($req.Url.AbsolutePath.StartsWith('/api/', [StringComparison]::OrdinalIgnoreCase)) {
                Invoke-MetraOpsApi -Request $req -Response $res -MetraRoot $MetraRoot
            }
            else {
                Invoke-MetraOpsStatic -Request $req -Response $res -DistPath $dist
            }
        }
    }
    finally {
        try { Stop-MetraAskEngine -MetraRoot $MetraRoot } catch { }
        try {
            if ($listener.IsListening) { $listener.Stop() }
        }
        catch { }
        try { $listener.Close() } catch { }
        try {
            if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force }
        }
        catch { }
        Write-Host 'Metra Ops stopped.' -ForegroundColor DarkGray
    }
}
