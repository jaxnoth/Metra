# Ask engine: multi-engine settings, capability, invoke, start/stop.
# Implementers: cursor (Node sidecar) + openai_compat (PowerShell) for ollama / enterprise / llamacpp.

function Get-MetraAskModelPinTable {
    # Frozen 2026-08-08 from Accept / desk smoke (medium = qwen2.5:7b).
    return [ordered]@{
        small  = 'qwen2.5:3b'
        medium = 'qwen2.5:7b'
        large  = 'qwen2.5:14b'
    }
}

function Resolve-MetraAskCursorModelSelection {
    <#
    .SYNOPSIS
        Normalizes Cursor Ask model + optimizeFor from config or CLI input.
    .NOTES
        Default pin is composer-2.5 (Ask API slug). IDE agent names like
        composer-2.5-fast are aliased. auto-* tokens still map to auto-smart.
    #>
    [CmdletBinding()]
    param(
        [string]$Model,
        [string]$OptimizeFor = 'cost'
    )

    $cursorModel = if ([string]::IsNullOrWhiteSpace($Model)) { 'composer-2.5' } else { $Model.Trim() }
    $cursorOptimizeFor = if ([string]::IsNullOrWhiteSpace($OptimizeFor)) { 'cost' } else { $OptimizeFor.Trim().ToLowerInvariant() }
    $cursorModelLower = $cursorModel.ToLowerInvariant()

    if ($cursorModelLower -eq 'composer-2.5-fast') {
        $cursorModel = 'composer-2.5'
    }
    elseif ($cursorModelLower -in @('auto-cost', 'auto cost', 'cost', 'auto')) {
        $cursorModel = 'auto-smart'
        $cursorOptimizeFor = 'cost'
    }
    elseif ($cursorModelLower -in @('auto-balance', 'auto balance', 'balance', 'balanced')) {
        $cursorModel = 'auto-smart'
        $cursorOptimizeFor = 'balanced'
    }
    elseif ($cursorModelLower -in @('auto-intelligence', 'auto intelligence', 'intelligence')) {
        $cursorModel = 'auto-smart'
        $cursorOptimizeFor = 'intelligence'
    }
    if ($cursorModel -eq 'auto-smart' -and $cursorOptimizeFor -notin @('cost', 'balanced', 'intelligence')) {
        $cursorOptimizeFor = 'cost'
    }

    $displayModel = if ($cursorModel -eq 'auto-smart') { "auto-smart/$cursorOptimizeFor" } else { $cursorModel }
    return [PSCustomObject]@{
        cursorModel       = $cursorModel
        cursorOptimizeFor = $cursorOptimizeFor
        model             = $displayModel
    }
}

function Get-MetraAskConfigPath {
    <#
    .SYNOPSIS
        Resolves metra.config.json (or legacy meta.config.json) for Ask read/write.
    .NOTES
        Same preferred/legacy order as Get-MetraConfig / Get-MetraConfigFilePath.
        Returns the preferred path when neither file exists (Save throws separately).
    #>
    param([string]$MetraRoot = (Get-MetraRoot))
    $preferred = Join-Path $MetraRoot 'metra.config.json'
    $legacy = Join-Path $MetraRoot 'meta.config.json'
    if (Test-Path -LiteralPath $preferred) { return $preferred }
    if (Test-Path -LiteralPath $legacy) { return $legacy }
    return $preferred
}

function Get-MetraAskSettings {
    <#
    .SYNOPSIS
        Reads ask.* settings from metra.config.json (multi-engine).
    .NOTES
        Loads via Get-MetraAskConfigPath under MetraRoot so Save-MetraAskConfigPatch
        and settings share preferred/legacy path rules. Default MetraRoot uses Get-MetraConfig cache.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $cfg = $null
    $configPath = Get-MetraAskConfigPath -MetraRoot $MetraRoot
    $moduleRoot = Get-MetraRoot
    if ($MetraRoot -eq $moduleRoot) {
        try { $cfg = Get-MetraConfig } catch { $cfg = $null }
    }
    if ($null -eq $cfg -and (Test-Path -LiteralPath $configPath)) {
        try { $cfg = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json } catch { $cfg = $null }
    }
    $ask = Get-MetraProp -Object $cfg -Name 'ask' -Default $null

    $enabled = $true
    $engine = 'ollama'
    if ($null -ne $ask) {
        $rawEnabled = Get-MetraProp -Object $ask -Name 'enabled' -Default $true
        $enabled = [bool]$rawEnabled
        $engine = [string](Get-MetraProp -Object $ask -Name 'engine' -Default 'ollama').Trim().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($engine)) { $engine = 'none' }
    if ($engine -eq 'gpt4all') {
        # Cut from first-class ladder 1 - treat as unsupported.
        $engine = 'none'
    }

    $pins = Get-MetraAskModelPinTable
    $cursor = Get-MetraProp -Object $ask -Name 'cursor' -Default $null
    $cursorPort = 7381
    $rawCursorModel = $null
    $rawCursorOptimizeFor = 'cost'
    if ($null -ne $cursor) {
        $p = Get-MetraProp -Object $cursor -Name 'port' -Default 7381
        if ($p -as [int]) { $cursorPort = [int]$p }
        $m = [string](Get-MetraProp -Object $cursor -Name 'model' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($m)) { $rawCursorModel = $m.Trim() }
        $of = [string](Get-MetraProp -Object $cursor -Name 'optimizeFor' -Default 'cost')
        if (-not [string]::IsNullOrWhiteSpace($of)) { $rawCursorOptimizeFor = $of.Trim().ToLowerInvariant() }
    }
    $cursorResolved = Resolve-MetraAskCursorModelSelection -Model $rawCursorModel -OptimizeFor $rawCursorOptimizeFor
    $cursorModel = $cursorResolved.cursorModel
    $cursorOptimizeFor = $cursorResolved.cursorOptimizeFor

    $ollama = Get-MetraProp -Object $ask -Name 'ollama' -Default $null
    $ollamaBase = 'http://127.0.0.1:11434'
    $ollamaModel = [string]$pins['medium']
    $sizeBand = 'medium'
    if ($null -ne $ollama) {
        $b = [string](Get-MetraProp -Object $ollama -Name 'baseUrl' -Default $ollamaBase)
        if (-not [string]::IsNullOrWhiteSpace($b)) { $ollamaBase = $b.TrimEnd('/') }
        $sb = [string](Get-MetraProp -Object $ollama -Name 'sizeBand' -Default 'medium').Trim().ToLowerInvariant()
        if ($sb -in @('small', 'medium', 'large')) { $sizeBand = $sb }
        $om = [string](Get-MetraProp -Object $ollama -Name 'model' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($om)) { $ollamaModel = $om.Trim() }
        else { $ollamaModel = [string]$pins[$sizeBand] }
    }

    $enterprise = Get-MetraProp -Object $ask -Name 'enterprise' -Default $null
    $entBase = ''
    $entModel = ''
    $entApiKeyEnv = 'METRA_ASK_ENTERPRISE_KEY'
    $entRequireApiKey = $false
    if ($null -ne $enterprise) {
        $entBase = [string](Get-MetraProp -Object $enterprise -Name 'baseUrl' -Default '').Trim().TrimEnd('/')
        $entModel = [string](Get-MetraProp -Object $enterprise -Name 'model' -Default '').Trim()
        $ek = [string](Get-MetraProp -Object $enterprise -Name 'apiKeyEnv' -Default 'METRA_ASK_ENTERPRISE_KEY')
        if (-not [string]::IsNullOrWhiteSpace($ek)) { $entApiKeyEnv = $ek.Trim() }
        # apiKeyEnv is optional for internal unauthenticated endpoints unless requireApiKey is true.
        $entRequireApiKey = [bool](Get-MetraProp -Object $enterprise -Name 'requireApiKey' -Default $false)
    }

    $llamacpp = Get-MetraProp -Object $ask -Name 'llamacpp' -Default $null
    $llamaBase = 'http://127.0.0.1:8080'
    $llamaModel = [string]$pins['large']
    if ($null -ne $llamacpp) {
        $lb = [string](Get-MetraProp -Object $llamacpp -Name 'baseUrl' -Default $llamaBase)
        if (-not [string]::IsNullOrWhiteSpace($lb)) { $llamaBase = $lb.TrimEnd('/') }
        $lm = [string](Get-MetraProp -Object $llamacpp -Name 'model' -Default $llamaModel)
        if (-not [string]::IsNullOrWhiteSpace($lm)) { $llamaModel = $lm.Trim() }
    }

    $activeModel = switch ($engine) {
        'cursor' {
            if ($cursorModel -eq 'auto-smart') { "auto-smart/$cursorOptimizeFor" }
            else { $cursorModel }
        }
        'ollama' { $ollamaModel }
        'enterprise' { $entModel }
        'llamacpp' { $llamaModel }
        default { '' }
    }

    return [PSCustomObject]@{
        enabled            = $enabled
        engine             = $engine
        cursorPort         = $cursorPort
        cursorModel        = $cursorModel
        cursorOptimizeFor  = $cursorOptimizeFor
        ollamaBaseUrl      = $ollamaBase
        ollamaModel        = $ollamaModel
        ollamaSizeBand     = $sizeBand
        enterpriseBaseUrl  = $entBase
        enterpriseModel    = $entModel
        enterpriseApiKeyEnv = $entApiKeyEnv
        enterpriseRequireApiKey = $entRequireApiKey
        enterpriseConfigured = (-not [string]::IsNullOrWhiteSpace($entBase) -and -not [string]::IsNullOrWhiteSpace($entModel))
        llamacppBaseUrl    = $llamaBase
        llamacppModel      = $llamaModel
        model              = $activeModel
        metraRoot          = $MetraRoot
    }
}

function Save-MetraAskConfigPatch {
    <#
    .SYNOPSIS
        Shallow-merges a hashtable into ask.* in metra.config.json and clears config cache.
    .DESCRIPTION
        Performs a shallow merge into ask.* only. Top-level keys in Patch replace ask.<key>
        wholesale. Nested engine settings (ask.ollama, ask.cursor, ask.enterprise, ask.llamacpp)
        must be passed as complete objects - this function does not deep-merge nested hashtables.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Patch,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $path = Get-MetraAskConfigPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing config: $path"
    }
    $cfg = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    # StrictMode: never read $cfg.ask when the note property is absent.
    $ask = Get-MetraProp -Object $cfg -Name 'ask' -Default $null
    if ($null -eq $ask) {
        $ask = [PSCustomObject]@{}
        $cfg | Add-Member -NotePropertyName ask -NotePropertyValue $ask -Force
    }
    # Shallow merge only - nested objects replace, they do not deep-merge.
    foreach ($key in $Patch.Keys) {
        $val = $Patch[$key]
        if ($null -eq $ask.PSObject.Properties[$key]) {
            $ask | Add-Member -NotePropertyName $key -NotePropertyValue $val -Force
        }
        else {
            $ask.$key = $val
        }
    }
    # Keep $cfg.ask pointing at the mutated object (Add-Member -Force already set it).
    $cfg.ask = $ask
    $json = $cfg | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
    if ($script:MetraCache) {
        $script:MetraCache.Config = $null
        $script:MetraCache.ConfigPath = $null
        $script:MetraCache.ConfigLwt = $null
    }
}

function Test-MetraCursorInstall {
    <#
    .SYNOPSIS
        True when Cursor.exe is present (IDE probe - not Ask readiness).
    #>
    [CmdletBinding()]
    param()
    foreach ($p in @(Get-MetraEditorCandidatePaths -Editor cursor)) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $true }
    }
    return $false
}

function Get-MetraAskNodePath {
    <#
    .SYNOPSIS
        Resolves Node for Cursor Ask - private runtime first, then PATH.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $private = Join-Path $MetraRoot 'runtimes\node\node.exe'
    if (Test-Path -LiteralPath $private) { return $private }
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if ($cmd) { return [string]$cmd.Source }
    return $null
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

function Test-MetraAskCursorSidecarDeps {
    param([string]$MetraRoot = (Get-MetraRoot))
    $dir = Join-Path $MetraRoot 'engines\cursor'
    $sdk = Join-Path $dir 'node_modules\@cursor\sdk'
    return (Test-Path -LiteralPath $sdk)
}

function Get-MetraAskEnginePidFile {
    param([int]$Port = 7381)

    $dir = Join-Path $env:LOCALAPPDATA 'Metra'
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    return Join-Path $dir "ask-engine-$Port.pid"
}

function Get-MetraAskEngineLogPath {
    param(
        [int]$Port = 7381,
        [ValidateSet('stderr', 'stdout', 'runs', 'base')]
        [string]$Stream = 'stderr'
    )

    $dir = Join-Path $env:LOCALAPPDATA 'Metra\logs'
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    switch ($Stream) {
        'stdout' { return Join-Path $dir "ask-engine-$Port.out.log" }
        'runs' { return Join-Path $dir "ask-engine-$Port.runs.log" }
        'base' { return Join-Path $dir "ask-engine-$Port" }
        default { return Join-Path $dir "ask-engine-$Port.err.log" }
    }
}

function Write-MetraAskEnginePidFile {
    <#
    .SYNOPSIS
        Writes the Ask Cursor sidecar PID file (ASCII digits only).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][int]$ProcessId
    )

    if ($ProcessId -le 0) { return }
    $pidFile = Get-MetraAskEnginePidFile -Port $Port
    Set-Content -LiteralPath $pidFile -Value $ProcessId -Encoding ASCII
}

function Sync-MetraAskEnginePidFile {
    <#
    .SYNOPSIS
        Aligns ask-engine-PORT.pid with a live Metra Cursor sidecar listener on the port.
    .OUTPUTS
        [int] Chosen listener PID, or $null when none.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port
    )

    $listeners = @(Get-MetraAskCursorSidecarListenerProcessIds -Port $Port)
    if ($listeners.Count -eq 0) { return $null }

    $pidFile = Get-MetraAskEnginePidFile -Port $Port
    $recorded = 0
    $hasRecorded = $false
    if (Test-Path -LiteralPath $pidFile) {
        $hasRecorded = [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$recorded)
    }

    $chosen = $listeners[0]
    if ($hasRecorded -and $recorded -gt 0 -and $listeners -contains $recorded) {
        $chosen = $recorded
    }

    Write-MetraAskEnginePidFile -Port $Port -ProcessId $chosen
    return $chosen
}

function Clear-MetraAskEngineStalePidFile {
    <#
    .SYNOPSIS
        Removes the PID file when it points at a dead process (or unreadable content).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port
    )

    $pidFile = Get-MetraAskEnginePidFile -Port $Port
    if (-not (Test-Path -LiteralPath $pidFile)) { return }
    $recorded = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$recorded) -or $recorded -le 0) {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        return
    }
    if ($recorded -eq $PID) {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        return
    }
    if (-not (Get-Process -Id $recorded -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-MetraAskCursorHealthResponseOk {
    <#
    .SYNOPSIS
        True only when health JSON has Boolean ok -eq $true (not string "false" / missing).
    #>
    [CmdletBinding()]
    param($Response)

    if ($null -eq $Response) { return $false }
    $ok = Get-MetraProp -Object $Response -Name 'ok' -Default $null
    if ($ok -is [bool]) { return ($ok -eq $true) }
    # Reject string/"1"/missing - operational health must be a real Boolean true.
    return $false
}

function Test-MetraAskCursorPortHealth {
    <#
    .SYNOPSIS
        True when GET /health on the Cursor Ask loopback port returns ok Boolean true.
    .NOTES
        ok means operationally usable (sidecar consecutive-run gate), not merely HTTP 200.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutSec = 1
    )

    try {
        $url = "http://127.0.0.1:$Port/health"
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec $TimeoutSec
        return [bool](Test-MetraAskCursorHealthResponseOk -Response $response)
    }
    catch {
        return $false
    }
}

function Wait-MetraAskCursorPortHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutSec = 20
    )

    $deadline = [datetime]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutSec))
    while ([datetime]::UtcNow -lt $deadline) {
        if (Test-MetraAskCursorPortHealth -Port $Port -TimeoutSec 1) { return $true }
        Start-Sleep -Milliseconds 400
    }
    return (Test-MetraAskCursorPortHealth -Port $Port -TimeoutSec 1)
}

function Initialize-MetraAskEngineSpawnLogs {
    <#
    .SYNOPSIS
        Rotates non-empty sidecar stdout/stderr logs to *.1 before Start-Process truncates them.
    .NOTES
        Start-Process -RedirectStandard* always truncates the target file. Keep one previous
        generation so EADDRINUSE / SDK errors survive a failed second start.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port
    )

    foreach ($stream in @('stdout', 'stderr')) {
        $path = Get-MetraAskEngineLogPath -Port $Port -Stream $stream
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $item -or $item.Length -le 0) { continue }
        $prev = "$path.1"
        if (Test-Path -LiteralPath $prev) {
            Remove-Item -LiteralPath $prev -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $path -Destination $prev -Force -ErrorAction SilentlyContinue
    }
}

function Get-MetraAskCursorSidecarListenerProcessIds {
    <#
    .SYNOPSIS
        Returns Metra Cursor sidecar node PIDs listening on the Ask port (orphan recovery).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port
    )

    $pids = New-Object System.Collections.Generic.List[int]
    try {
        $conns = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop)
        foreach ($conn in $conns) {
            $localAddress = [string]$conn.LocalAddress
            if ($localAddress -notin @('127.0.0.1', '::1')) { continue }
            $listenerPid = [int]$conn.OwningProcess
            if ($listenerPid -le 0 -or $listenerPid -eq $PID) { continue }
            if (-not (Test-MetraAskCursorSidecarProcessId -ProcessId $listenerPid)) { continue }
            if (-not $pids.Contains($listenerPid)) {
                [void]$pids.Add($listenerPid)
            }
        }
    }
    catch {
        $patterns = @(
            "127\.0\.0\.1:$Port\s+0\.0\.0\.0:0\s+LISTENING\s+(\d+)",
            "\[\:\:1\]:$Port\s+\[\:\:\]:0\s+LISTENING\s+(\d+)"
        )
        foreach ($pattern in $patterns) {
            foreach ($line in @(netstat -ano | Select-String -Pattern $pattern)) {
                $m = [regex]::Match([string]$line, $pattern)
                if (-not $m.Success) { continue }
                $listenerPid = [int]$m.Groups[1].Value
                if ($listenerPid -le 0 -or $listenerPid -eq $PID) { continue }
                if (-not (Test-MetraAskCursorSidecarProcessId -ProcessId $listenerPid)) { continue }
                if (-not $pids.Contains($listenerPid)) {
                    [void]$pids.Add($listenerPid)
                }
            }
        }
    }
    return @($pids)
}

function Get-MetraAskEngineBaseUrl {
    param([string]$MetraRoot = (Get-MetraRoot))

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    switch ($settings.engine) {
        'cursor' { return "http://127.0.0.1:$($settings.cursorPort)" }
        'ollama' { return $settings.ollamaBaseUrl }
        'enterprise' { return $settings.enterpriseBaseUrl }
        'llamacpp' { return $settings.llamacppBaseUrl }
        default { return '' }
    }
}

function Test-MetraAskEngineHealth {
    <#
    .SYNOPSIS
        True when the selected Ask engine is reachable for completions.
    .NOTES
        enterprise / llamacpp use Get-MetraAskOpenAICompatHealthResult (GET /v1/models, /health).
        Only HTTP 2xx is healthy; 401/403/404 are distinct reachable-but-not-ready states.
        Endpoints that only expose chat completions may still look unhealthy here.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 2
    )

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if (-not $settings.enabled -or $settings.engine -eq 'none') { return $false }

    switch ($settings.engine) {
        'cursor' {
            try {
                $url = "http://127.0.0.1:$($settings.cursorPort)/health"
                $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec $TimeoutSec
                return [bool](Test-MetraAskCursorHealthResponseOk -Response $response)
            }
            catch { return $false }
        }
        'ollama' {
            return [bool](Test-MetraAskOpenAICompatHealth -BaseUrl $settings.ollamaBaseUrl -Kind ollama -TimeoutSec $TimeoutSec)
        }
        'enterprise' {
            if (-not $settings.enterpriseConfigured) { return $false }
            return [bool](Test-MetraAskOpenAICompatHealth -BaseUrl $settings.enterpriseBaseUrl -Kind openai -TimeoutSec $TimeoutSec)
        }
        'llamacpp' {
            return [bool](Test-MetraAskOpenAICompatHealth -BaseUrl $settings.llamacppBaseUrl -Kind openai -TimeoutSec $TimeoutSec)
        }
        default { return $false }
    }
}

function Get-MetraAskCapability {
    <#
    .SYNOPSIS
        Discover Ask engine capability: selected vs available vs reason.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    $providerLabel = switch ($settings.engine) {
        'cursor' { 'Cursor' }
        'ollama' { 'Ollama' }
        'enterprise' { 'Enterprise' }
        'llamacpp' { 'llama.cpp' }
        default { $settings.engine }
    }

    $ideInstalled = Test-MetraCursorInstall
    $apiKeyPresent = -not [string]::IsNullOrWhiteSpace((Get-MetraCursorApiKey -PreferUser))
    $nodePath = Get-MetraAskNodePath -MetraRoot $MetraRoot
    $nodeReady = -not [string]::IsNullOrWhiteSpace($nodePath)
    $sidecar = Get-MetraAskCursorSidecarPath -MetraRoot $MetraRoot
    $sidecarReady = ($null -ne $sidecar) -and (Test-MetraAskCursorSidecarDeps -MetraRoot $MetraRoot)

    $base = [PSCustomObject]@{
        enabled          = [bool]$settings.enabled
        selected         = $false
        available        = $false
        engine           = $settings.engine
        providerLabel    = $providerLabel
        reason           = 'ok'
        message          = ''
        port             = $settings.cursorPort
        model            = $settings.model
        ideInstalled     = $ideInstalled
        apiKeyPresent    = $apiKeyPresent
        nodeReady        = $nodeReady
        sidecarReady     = $sidecarReady
        engineHealthy    = $false
        runtimeReady     = $false
        modelPresent     = $false
        enterpriseConfigured = [bool]$settings.enterpriseConfigured
        enterpriseKeyPresent = $false
        sizeBand         = $settings.ollamaSizeBand
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

    switch ($settings.engine) {
        'cursor' {
            if (-not $nodeReady) {
                $base.reason = 'node_missing'
                $base.message = @"
Ask engine unavailable.

Cursor Ask needs the bundled Node runtime under runtimes/node (or a repair via Setup).
Metra can still classify work and show routing.
"@.Trim()
                return $base
            }
            if (-not $sidecar) {
                $base.reason = 'sidecar_missing'
                $base.message = @"
Ask engine unavailable.

The Cursor Ask sidecar is not installed under engines/cursor.
Metra can still classify work and show routing.
"@.Trim()
                return $base
            }
            if (-not $sidecarReady) {
                $base.reason = 'sidecar_deps_missing'
                $base.message = @"
Ask engine unavailable.

Cursor Ask sidecar dependencies are missing (engines/cursor/node_modules).
Repair Cursor Ask via Setup or reinstall the Cursor Ask component.
Metra can still classify work and show routing.
"@.Trim()
                return $base
            }
            if (-not $apiKeyPresent) {
                $base.reason = 'key_missing'
                $base.message = @"
Ask engine unavailable.

No CURSOR_API_KEY is set (process, User, or Machine).
Use: .\metra.ps1 ask key set
Metra can still classify work and show routing.
"@.Trim()
                return $base
            }
            $healthy = Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 2
            $base.engineHealthy = $healthy
            $base.runtimeReady = $true
            $base.modelPresent = $true
            if (-not $healthy) {
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
            return $base
        }
        'ollama' {
            $runtime = Test-MetraAskOpenAICompatHealth -BaseUrl $settings.ollamaBaseUrl -Kind ollama -TimeoutSec 2
            $base.runtimeReady = $runtime
            if (-not $runtime) {
                $base.reason = 'runtime_missing'
                $base.message = @"
Ask engine unavailable.

Ollama is not reachable at $($settings.ollamaBaseUrl).
Accept recommended settings or run: .\metra.ps1 ask accept
Metra can still classify work and show routing.
"@.Trim()
                return $base
            }
            $modelOk = Test-MetraAskOllamaModelPresent -BaseUrl $settings.ollamaBaseUrl -Model $settings.ollamaModel -TimeoutSec 5
            $base.modelPresent = $modelOk
            if (-not $modelOk) {
                $base.reason = 'model_missing'
                $base.message = @"
Ask engine unavailable.

Ollama is running but model '$($settings.ollamaModel)' is not pulled yet.
Run: .\metra.ps1 ask accept
Metra can still classify work and show routing.
"@.Trim()
                return $base
            }
            $base.engineHealthy = $true
            $base.available = $true
            $base.reason = 'ok'
            return $base
        }
        'enterprise' {
            if (-not $settings.enterpriseConfigured) {
                $base.reason = 'enterprise_unconfigured'
                $base.message = @"
Ask engine unavailable.

Enterprise Ask needs ask.enterprise.baseUrl and ask.enterprise.model in metra.config.json.
Metra can still classify work and show routing.
"@.Trim()
                return $base
            }
            $entKey = Get-MetraAskEnterpriseApiKey -Settings $settings
            $base.enterpriseKeyPresent = -not [string]::IsNullOrWhiteSpace($entKey)
            # apiKeyEnv is optional for internal endpoints; requireApiKey makes missing cred a distinct reason.
            if ([bool]$settings.enterpriseRequireApiKey -and -not $base.enterpriseKeyPresent) {
                $base.reason = 'enterprise_key_missing'
                $base.message = @"
Ask engine unavailable.

Enterprise Ask requires an API key in env '$($settings.enterpriseApiKeyEnv)' (ask.enterprise.requireApiKey).
Metra can still classify work and show routing.
"@.Trim()
                return $base
            }
            $healthHeaders = @{}
            if ($base.enterpriseKeyPresent) {
                $healthHeaders['Authorization'] = "Bearer $entKey"
            }
            $health = Get-MetraAskOpenAICompatHealthResult -BaseUrl $settings.enterpriseBaseUrl -Kind openai `
                -TimeoutSec 3 -Headers $healthHeaders
            # Reachable diagnostics (401/403/404) still mean the host answered.
            $base.runtimeReady = [string]$health.status -in @('ok', 'auth_required', 'forbidden', 'not_found')
            $base.modelPresent = [bool]$health.ok
            if (-not $health.ok) {
                switch ([string]$health.status) {
                    'auth_required' {
                        $base.reason = 'enterprise_key_missing'
                        $base.message = @"
Ask engine unavailable.

Enterprise endpoint responded unauthorized - set env '$($settings.enterpriseApiKeyEnv)' or fix the API key.
Metra can still classify work and show routing.
"@.Trim()
                    }
                    'forbidden' {
                        $base.reason = 'enterprise_forbidden'
                        $base.message = @"
Ask engine unavailable.

Enterprise endpoint refused the health probe (forbidden).
Metra can still classify work and show routing.
"@.Trim()
                    }
                    'not_found' {
                        $base.reason = 'enterprise_api_missing'
                        $base.message = @"
Ask engine unavailable.

Enterprise OpenAI-compatible API path was not found (check baseUrl /v1/models).
Metra can still classify work and show routing.
"@.Trim()
                    }
                    default {
                        $base.reason = 'enterprise_unreachable'
                        $base.message = @"
Ask engine unavailable.

Enterprise endpoint is configured but not reachable.
Metra can still classify work and show routing.
"@.Trim()
                    }
                }
                return $base
            }
            $base.engineHealthy = $true
            $base.available = $true
            $base.reason = 'ok'
            return $base
        }
        'llamacpp' {
            $runtime = Test-MetraAskOpenAICompatHealth -BaseUrl $settings.llamacppBaseUrl -Kind openai -TimeoutSec 2
            $base.runtimeReady = $runtime
            $base.modelPresent = $runtime
            if (-not $runtime) {
                $base.reason = 'runtime_missing'
                $base.message = @"
Ask engine unavailable.

llama.cpp server is not reachable at $($settings.llamacppBaseUrl) (Advanced / experimental).
Metra can still classify work and show routing.
"@.Trim()
                return $base
            }
            $base.engineHealthy = $true
            $base.available = $true
            $base.reason = 'ok'
            return $base
        }
        default {
            $base.reason = 'engine_unsupported'
            $base.message = @"
Ask engine unavailable.

Engine '$($settings.engine)' is selected but not implemented.
Metra can still classify work and show routing.
"@.Trim()
            return $base
        }
    }
}

function Get-MetraAskRouteCwd {
    [CmdletBinding()]
    param(
        [string]$Where,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Where) -or $Where -eq 'Metra') {
        return $MetraRoot
    }

    $projects = @(Get-MetraProjects -IncludeNonGit -ErrorAction SilentlyContinue)
    $match = $projects | Where-Object { [string]$_.Name -ieq $Where } | Select-Object -First 1
    if ($match -and $match.Path -and (Test-Path -LiteralPath $match.Path)) {
        return [string]$match.Path
    }
    return $MetraRoot
}

function New-MetraAskEngineRefuseResult {
    param(
        $Settings,
        [string]$SessionId,
        $Scrub,
        [string]$Source = 'prompt'
    )
    return [PSCustomObject]@{
        ok              = $false
        message         = ''
        engine          = $Settings.engine
        model           = $Settings.model
        sessionId       = $SessionId
        status          = 'refused'
        error           = 'secrets_refuse'
        secretsRefuse   = $true
        secretsReason   = [string]$Scrub.Reason
        secretsNotice   = [string]$Scrub.Notice
        secretsScrubbed = $true
        secretsKinds    = @($Scrub.Kinds)
        scrubbedPrompt  = $(if ($Source -eq 'prompt') { [string]$Scrub.Text } else { '' })
    }
}

function New-MetraAskSettingsWithOverrides {
    <#
    .SYNOPSIS
        Returns a copy of Ask settings with optional engine/model overrides (no mutation of source).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Settings,
        [string]$Engine,
        [string]$Model
    )

    $eng = [string](Get-MetraProp -Object $Settings -Name 'engine' -Default 'ollama')
    if (-not [string]::IsNullOrWhiteSpace($Engine)) {
        $eng = $Engine.Trim().ToLowerInvariant()
    }

    $cursorModel = [string](Get-MetraProp -Object $Settings -Name 'cursorModel' -Default 'composer-2.5')
    $cursorOptimizeFor = [string](Get-MetraProp -Object $Settings -Name 'cursorOptimizeFor' -Default 'cost')
    $ollamaModel = [string](Get-MetraProp -Object $Settings -Name 'ollamaModel' -Default '')
    $entModel = [string](Get-MetraProp -Object $Settings -Name 'enterpriseModel' -Default '')
    $llamaModel = [string](Get-MetraProp -Object $Settings -Name 'llamacppModel' -Default '')

    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $m = $Model.Trim()
        switch ($eng) {
            'cursor' {
                $sel = Resolve-MetraAskCursorModelSelection -Model $m -OptimizeFor $cursorOptimizeFor
                $cursorModel = $sel.cursorModel
                $cursorOptimizeFor = $sel.cursorOptimizeFor
            }
            'ollama' { $ollamaModel = $m }
            'enterprise' { $entModel = $m }
            'llamacpp' { $llamaModel = $m }
        }
    }

    $activeModel = switch ($eng) {
        'cursor' {
            if ($cursorModel -eq 'auto-smart') { "auto-smart/$cursorOptimizeFor" }
            else { $cursorModel }
        }
        'ollama' { $ollamaModel }
        'enterprise' { $entModel }
        'llamacpp' { $llamaModel }
        default { '' }
    }

    return [PSCustomObject]@{
        enabled                 = [bool](Get-MetraProp -Object $Settings -Name 'enabled' -Default $true)
        engine                  = $eng
        cursorPort              = [int](Get-MetraProp -Object $Settings -Name 'cursorPort' -Default 7381)
        cursorModel             = $cursorModel
        cursorOptimizeFor       = $cursorOptimizeFor
        ollamaBaseUrl           = [string](Get-MetraProp -Object $Settings -Name 'ollamaBaseUrl' -Default 'http://127.0.0.1:11434')
        ollamaModel             = $ollamaModel
        ollamaSizeBand          = [string](Get-MetraProp -Object $Settings -Name 'ollamaSizeBand' -Default 'medium')
        enterpriseBaseUrl       = [string](Get-MetraProp -Object $Settings -Name 'enterpriseBaseUrl' -Default '')
        enterpriseModel         = $entModel
        enterpriseApiKeyEnv     = [string](Get-MetraProp -Object $Settings -Name 'enterpriseApiKeyEnv' -Default 'METRA_ASK_ENTERPRISE_KEY')
        enterpriseRequireApiKey = [bool](Get-MetraProp -Object $Settings -Name 'enterpriseRequireApiKey' -Default $false)
        enterpriseConfigured    = (-not [string]::IsNullOrWhiteSpace([string](Get-MetraProp -Object $Settings -Name 'enterpriseBaseUrl' -Default '')) -and -not [string]::IsNullOrWhiteSpace($entModel))
        llamacppBaseUrl         = [string](Get-MetraProp -Object $Settings -Name 'llamacppBaseUrl' -Default 'http://127.0.0.1:8080')
        llamacppModel           = $llamaModel
        model                   = $activeModel
        metraRoot               = [string](Get-MetraProp -Object $Settings -Name 'metraRoot' -Default '')
    }
}

function Get-MetraAskCursorForeignListenerProcessIds {
    <#
    .SYNOPSIS
        Returns PIDs listening on the Ask port that are NOT proven Metra Cursor sidecars.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port
    )

    $owned = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($id in @(Get-MetraAskCursorSidecarListenerProcessIds -Port $Port)) {
        [void]$owned.Add([int]$id)
    }

    $foreign = New-Object System.Collections.Generic.List[int]
    # Any bind on the Ask port counts (loopback, 0.0.0.0, ::, *). Owned Metra PIDs are excluded above.
    try {
        $conns = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop)
        foreach ($conn in $conns) {
            $listenerPid = [int]$conn.OwningProcess
            if ($listenerPid -le 0 -or $listenerPid -eq $PID) { continue }
            if ($owned.Contains($listenerPid)) { continue }
            if (-not $foreign.Contains($listenerPid)) {
                [void]$foreign.Add($listenerPid)
            }
        }
    }
    catch {
        $patterns = @(
            "127\.0\.0\.1:$Port\s+\S+\s+LISTENING\s+(\d+)",
            "0\.0\.0\.0:$Port\s+\S+\s+LISTENING\s+(\d+)",
            "\[\:\:1\]:$Port\s+\S+\s+LISTENING\s+(\d+)",
            "\[\:\:\]:$Port\s+\S+\s+LISTENING\s+(\d+)",
            "\*\:$Port\s+\S+\s+LISTENING\s+(\d+)"
        )
        foreach ($pattern in $patterns) {
            foreach ($line in @(netstat -ano | Select-String -Pattern $pattern)) {
                $m = [regex]::Match([string]$line, $pattern)
                if (-not $m.Success) { continue }
                $listenerPid = [int]$m.Groups[1].Value
                if ($listenerPid -le 0 -or $listenerPid -eq $PID) { continue }
                if ($owned.Contains($listenerPid)) { continue }
                if (-not $foreign.Contains($listenerPid)) {
                    [void]$foreign.Add($listenerPid)
                }
            }
        }
    }
    return @($foreign)
}

function Invoke-MetraAskCursorSidecarEnsure {
    <#
    .SYNOPSIS
        Ensures one healthy Cursor Ask sidecar on the port: adopt listeners first, spawn only if needed.
    .NOTES
        Writes the PID file only after /health succeeds (or after adopting a live Metra listener).
        Failed second starts no longer overwrite a good PID with a dead process id.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$CursorPort = 7381,
        [string]$CursorModel = 'composer-2.5',
        [string]$CursorOptimizeFor = 'cost'
    )

    if (Test-MetraAskCursorPortHealth -Port $CursorPort -TimeoutSec 1) {
        $null = Sync-MetraAskEnginePidFile -Port $CursorPort
        return $true
    }

    $existing = @(Get-MetraAskCursorSidecarListenerProcessIds -Port $CursorPort)
    if ($existing.Count -gt 0) {
        if (Wait-MetraAskCursorPortHealth -Port $CursorPort -TimeoutSec 2) {
            $null = Sync-MetraAskEnginePidFile -Port $CursorPort
            return $true
        }
        # Owned Metra listener present but health not ok - recycle (do not adopt wedged process).
        Write-Warning ("Ask Cursor sidecar listener(s) on port {0} unhealthy; recycling owned process. See {1}" -f `
            $CursorPort, (Get-MetraAskEngineLogPath -Port $CursorPort -Stream stderr))
        try {
            $null = Stop-MetraAskEngine -MetraRoot $MetraRoot -Port $CursorPort -IncludePortListeners -Confirm:$false
        }
        catch {
            Write-Warning "Ask Cursor sidecar stop failed before recycle spawn: $($_.Exception.Message)"
            return $false
        }
        $stillOwned = @(Get-MetraAskCursorSidecarListenerProcessIds -Port $CursorPort)
        if ($stillOwned.Count -gt 0) {
            Write-Warning ("Ask Cursor sidecar still listening after stop on port {0}; not spawning. See {1}" -f `
                $CursorPort, (Get-MetraAskEngineLogPath -Port $CursorPort -Stream stderr))
            return $false
        }
        # Fall through to cold spawn below (foreign check is shared with no-owned path).
    }

    # Before any cold spawn (including after owned recycle): fail closed on non-Metra occupants.
    $foreign = @(Get-MetraAskCursorForeignListenerProcessIds -Port $CursorPort)
    if ($foreign.Count -gt 0) {
        Write-Warning ("Port {0} is in use by non-Metra process(es) ({1}); not starting Ask sidecar." -f `
            $CursorPort, ($foreign -join ','))
        return $false
    }

    $nodePath = Get-MetraAskNodePath -MetraRoot $MetraRoot
    $sidecar = Get-MetraAskCursorSidecarPath -MetraRoot $MetraRoot
    $key = Get-MetraCursorApiKey -PreferUser
    if (-not $nodePath -or -not $sidecar -or [string]::IsNullOrWhiteSpace($key) -or -not (Test-MetraAskCursorSidecarDeps -MetraRoot $MetraRoot)) {
        return $false
    }

    Clear-MetraAskEngineStalePidFile -Port $CursorPort
    Initialize-MetraAskEngineSpawnLogs -Port $CursorPort

    $logOut = Get-MetraAskEngineLogPath -Port $CursorPort -Stream stdout
    $logErr = Get-MetraAskEngineLogPath -Port $CursorPort -Stream stderr
    $logDir = Split-Path -Parent $logOut
    $proc = $null
    $prevPort = $env:METRA_ASK_PORT
    $prevModel = $env:METRA_ASK_MODEL
    $prevOpt = $env:METRA_ASK_OPTIMIZE_FOR
    $prevEng = $env:METRA_ASK_ENGINE
    $prevLogDir = $env:METRA_ASK_LOG_DIR
    try {
        $previous = $env:CURSOR_API_KEY
        $env:CURSOR_API_KEY = $key
        $env:METRA_ASK_PORT = "$CursorPort"
        $env:METRA_ASK_MODEL = $CursorModel
        $env:METRA_ASK_OPTIMIZE_FOR = $CursorOptimizeFor
        $env:METRA_ASK_ENGINE = 'cursor'
        $env:METRA_ASK_LOG_DIR = $logDir
        try {
            # Temporary process environment: Windows PowerShell Start-Process lacks per-child -Environment.
            $proc = Start-Process -FilePath $nodePath -ArgumentList @($sidecar) `
                -WorkingDirectory (Split-Path -Parent $sidecar) `
                -PassThru -WindowStyle Hidden `
                -RedirectStandardOutput $logOut `
                -RedirectStandardError $logErr
        }
        finally {
            if ($null -eq $previous) { Remove-Item Env:CURSOR_API_KEY -ErrorAction SilentlyContinue }
            else { $env:CURSOR_API_KEY = $previous }
            if ($null -eq $prevPort) { Remove-Item Env:METRA_ASK_PORT -ErrorAction SilentlyContinue } else { $env:METRA_ASK_PORT = $prevPort }
            if ($null -eq $prevModel) { Remove-Item Env:METRA_ASK_MODEL -ErrorAction SilentlyContinue } else { $env:METRA_ASK_MODEL = $prevModel }
            if ($null -eq $prevOpt) { Remove-Item Env:METRA_ASK_OPTIMIZE_FOR -ErrorAction SilentlyContinue } else { $env:METRA_ASK_OPTIMIZE_FOR = $prevOpt }
            if ($null -eq $prevEng) { Remove-Item Env:METRA_ASK_ENGINE -ErrorAction SilentlyContinue } else { $env:METRA_ASK_ENGINE = $prevEng }
            if ($null -eq $prevLogDir) { Remove-Item Env:METRA_ASK_LOG_DIR -ErrorAction SilentlyContinue } else { $env:METRA_ASK_LOG_DIR = $prevLogDir }
        }
    }
    catch {
        Write-Warning "Ask Cursor sidecar start failed: $($_.Exception.Message)"
        return $false
    }

    if (-not $proc) {
        Write-Warning 'Ask Cursor sidecar Start-Process returned no process handle.'
        return $false
    }

    # Do not write the PID file until /health succeeds - a failed bind (EADDRINUSE) must not replace a good PID.
    if (Wait-MetraAskCursorPortHealth -Port $CursorPort -TimeoutSec 20) {
        $synced = Sync-MetraAskEnginePidFile -Port $CursorPort
        if ($null -eq $synced -and -not $proc.HasExited -and (Test-MetraAskCursorSidecarProcessId -ProcessId $proc.Id)) {
            Write-MetraAskEnginePidFile -Port $CursorPort -ProcessId $proc.Id
        }
        return $true
    }

    $listenersNow = @(Get-MetraAskCursorSidecarListenerProcessIds -Port $CursorPort)
    if ($listenersNow.Count -gt 0 -and (Wait-MetraAskCursorPortHealth -Port $CursorPort -TimeoutSec 5)) {
        $null = Sync-MetraAskEnginePidFile -Port $CursorPort
        if (-not $proc.HasExited -and -not ($listenersNow -contains $proc.Id) -and (Test-MetraAskCursorSidecarProcessId -ProcessId $proc.Id)) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch { }
        }
        return $true
    }

    if ($proc -and -not $proc.HasExited) {
        Write-Warning ("Ask Cursor sidecar started (PID {0}) but health is still false on port {1}. Port may be held by another process - not killing automatically. See {2} (and {2}.1 if rotated)." -f `
            $proc.Id, $CursorPort, $logErr)
    }
    else {
        Write-Warning ("Ask Cursor sidecar exited before health on port {0}. See {1} (and {1}.1 if rotated)." -f $CursorPort, $logErr)
    }
    return $false
}

function Start-MetraAskCursorSidecar {
    <#
    .SYNOPSIS
        Starts the Cursor Ask sidecar for a port/model regardless of ask.engine (Inspect override path).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$CursorPort = 7381,
        [string]$CursorModel = 'composer-2.5',
        [string]$CursorOptimizeFor = 'cost'
    )

    return (Invoke-MetraAskCursorSidecarEnsure -MetraRoot $MetraRoot -CursorPort $CursorPort `
            -CursorModel $CursorModel -CursorOptimizeFor $CursorOptimizeFor)
}

function Invoke-MetraAskEngine {
    <#
    .SYNOPSIS
        Calls the selected Ask engine (cursor loopback or openai_compat).
    .NOTES
        Optional -Engine / -Model override the loaded ask.* selection for this call only
        (Inspect reviewer pin). Does not mutate metra.config.json or process Ask settings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Cwd,
        [hashtable]$Context = @{},
        [string]$SessionId,
        [object[]]$Images = @(),
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 180,
        [string]$Engine,
        [string]$Model
    )

    $baseSettings = Get-MetraAskSettings -MetraRoot $MetraRoot
    $hasEngineOverride = $PSBoundParameters.ContainsKey('Engine') -and -not [string]::IsNullOrWhiteSpace($Engine)
    $hasModelOverride = $PSBoundParameters.ContainsKey('Model') -and -not [string]::IsNullOrWhiteSpace($Model)
    $settings = if ($hasEngineOverride -or $hasModelOverride) {
        New-MetraAskSettingsWithOverrides -Settings $baseSettings -Engine $(if ($hasEngineOverride) { $Engine } else { '' }) -Model $(if ($hasModelOverride) { $Model } else { '' })
    }
    else {
        $baseSettings
    }

    $promptScrub = Invoke-MetraAskSecretsScrubText -Text $Prompt
    if ($promptScrub.Refuse) {
        return New-MetraAskEngineRefuseResult -Settings $settings -SessionId $SessionId -Scrub $promptScrub -Source prompt
    }
    $ctxScrub = Invoke-MetraAskSecretsScrubObject -InputObject $Context
    if ($ctxScrub.Refuse) {
        return New-MetraAskEngineRefuseResult -Settings $settings -SessionId $SessionId -Scrub $ctxScrub -Source context
    }

    $safeContext = if ($null -ne $ctxScrub.Value) { $ctxScrub.Value } else { @{} }

    # MVP: Cursor sidecar only for vision. Ollama/enterprise/llamacpp always degrade before call.
    $imageRefs = @(
        foreach ($img in @($Images)) {
            if ($null -eq $img) { continue }
            $id = [string](Get-MetraProp -Object $img -Name 'id' -Default '')
            $fileName = [string](Get-MetraProp -Object $img -Name 'fileName' -Default '')
            $path = [string](Get-MetraProp -Object $img -Name 'path' -Default '')
            if ([string]::IsNullOrWhiteSpace($id) -and [string]::IsNullOrWhiteSpace($path)) { continue }
            [ordered]@{
                id       = $id
                fileName = $fileName
                path     = $path
            }
        }
    )
    if ($imageRefs.Count -gt 0 -and $settings.engine -ne 'cursor') {
        $deg = "Ask image intake needs the Cursor Ask engine for vision in this release. Current engine is '$($settings.engine)'. Switch Ask to Cursor, or remove the image and ask in text."
        return [PSCustomObject]@{
            ok              = $false
            message         = $deg
            engine          = $settings.engine
            model           = $settings.model
            sessionId       = $SessionId
            status          = 'degraded'
            error           = 'image_vision_unsupported'
            secretsRefuse   = $false
            secretsReason   = $null
            secretsNotice   = $(if ($promptScrub.Matched -or $ctxScrub.Matched) {
                    Join-MetraAskSecretsNotices -Notices @($promptScrub.Notice, $ctxScrub.Notice)
                } else { $null })
            secretsScrubbed = [bool]($promptScrub.Matched -or $ctxScrub.Matched)
            secretsKinds    = @($promptScrub.Kinds) + @($ctxScrub.Kinds)
            scrubbedPrompt  = [string]$promptScrub.Text
        }
    }

    if ($settings.engine -eq 'cursor') {
        $null = Start-MetraAskCursorSidecar -MetraRoot $MetraRoot -CursorPort $settings.cursorPort `
            -CursorModel $settings.cursorModel -CursorOptimizeFor $settings.cursorOptimizeFor
        $url = "http://127.0.0.1:$($settings.cursorPort)/v1/complete"
        $body = @{
            prompt  = [string]$promptScrub.Text
            cwd     = $Cwd
            context = $safeContext
            mode    = 'answer'
            model   = [string]$settings.model
        }
        if ($SessionId) { $body.sessionId = $SessionId }
        if ($imageRefs.Count -gt 0) {
            # Path/id only - sidecar reads quarantine bytes. Never put base64 in this JSON.
            $body.images = @($imageRefs)
        }
        $json = $body | ConvertTo-Json -Depth 8 -Compress
        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -Body $json -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec
            return Convert-MetraAskCursorResponse -Response $response -Settings $settings -SessionId $SessionId -PromptScrub $promptScrub -CtxScrub $ctxScrub
        }
        catch {
            return New-MetraAskEngineErrorResult -Settings $settings -SessionId $SessionId -ErrorMessage $_.Exception.Message -PromptScrub $promptScrub -CtxScrub $ctxScrub
        }
    }

    if ($settings.engine -in @('ollama', 'enterprise', 'llamacpp')) {
        return Invoke-MetraAskOpenAICompatComplete `
            -Settings $settings `
            -Prompt ([string]$promptScrub.Text) `
            -Cwd $Cwd `
            -Context $safeContext `
            -SessionId $SessionId `
            -PromptScrub $promptScrub `
            -CtxScrub $ctxScrub `
            -TimeoutSec $TimeoutSec
    }

    return New-MetraAskEngineErrorResult -Settings $settings -SessionId $SessionId -ErrorMessage "engine_unsupported:$($settings.engine)" -PromptScrub $promptScrub -CtxScrub $ctxScrub
}

function Convert-MetraAskCursorResponse {
    param($Response, $Settings, [string]$SessionId, $PromptScrub, $CtxScrub)

    $statusRaw = [string](Get-MetraProp -Object $Response -Name 'status' -Default '')
    $status = if ([string]::IsNullOrWhiteSpace($statusRaw)) { 'unknown' } else { $statusRaw.Trim() }
    $resolvedRaw = Get-MetraProp -Object $Response -Name 'resolvedModel' -Default $null
    $resolvedModel = if ($null -eq $resolvedRaw -or [string]::IsNullOrWhiteSpace([string]$resolvedRaw)) { $null } else { [string]$resolvedRaw }
    if ($status -eq 'refused' -or [bool](Get-MetraProp -Object $Response -Name 'secretsRefuse' -Default $false)) {
        $refuseNotice = [string](Get-MetraProp -Object $Response -Name 'message' -Default '')
        if ([string]::IsNullOrWhiteSpace($refuseNotice)) {
            $refuseNotice = 'Private-key material was blocked and not sent to the Ask engine. Rephrase without the key block.'
        }
        return [PSCustomObject]@{
            ok              = $false
            message         = ''
            engine          = [string](Get-MetraProp -Object $Response -Name 'engine' -Default $Settings.engine)
            model           = [string](Get-MetraProp -Object $Response -Name 'model' -Default $Settings.model)
            resolvedModel   = $resolvedModel
            sessionId       = [string](Get-MetraProp -Object $Response -Name 'sessionId' -Default $SessionId)
            status          = 'refused'
            error           = 'secrets_refuse'
            secretsRefuse   = $true
            secretsReason   = [string](Get-MetraProp -Object $Response -Name 'secretsReason' -Default 'pem_private_key')
            secretsNotice   = $refuseNotice
            secretsScrubbed = $true
            secretsKinds    = @($PromptScrub.Kinds) + @($CtxScrub.Kinds)
            scrubbedPrompt  = [string]$PromptScrub.Text
        }
    }
    $rawMessage = [string](Get-MetraProp -Object $Response -Name 'message' -Default '')
    $msgScrub = Invoke-MetraAskSecretsScrubText -Text $rawMessage
    if ($msgScrub.Refuse) {
        return New-MetraAskEngineRefuseResult -Settings $settings -SessionId $SessionId -Scrub $msgScrub -Source output
    }
    $notice = Join-MetraAskSecretsNotices -Notices @(
        $(if ($PromptScrub.Matched) { $PromptScrub.Notice }),
        $(if ($CtxScrub.Matched) { $CtxScrub.Notice }),
        $(if ($msgScrub.Matched) { $msgScrub.Notice })
    )
    if ($status -ne 'finished') {
        $errMsg = [string]$msgScrub.Text
        if ([string]::IsNullOrWhiteSpace($errMsg)) {
            $errMsg = 'Ask engine request failed.'
        }
        $errorDetail = [string](Get-MetraProp -Object $Response -Name 'errorDetail' -Default '')
        $errorCode = [string](Get-MetraProp -Object $Response -Name 'errorCode' -Default '')
        $retryClass = [string](Get-MetraProp -Object $Response -Name 'retryClass' -Default '')
        if ([string]::IsNullOrWhiteSpace($errorCode)) { $errorCode = 'engine_request_failed' }
        if ([string]::IsNullOrWhiteSpace($retryClass) -and [string]::IsNullOrWhiteSpace($errorDetail)) {
            $retryClass = 'opaque_sdk_failure'
        }
        elseif ([string]::IsNullOrWhiteSpace($retryClass)) {
            $retryClass = 'sdk_run_error'
        }
        return [PSCustomObject]@{
            ok              = $false
            message         = $errMsg
            engine          = [string](Get-MetraProp -Object $Response -Name 'engine' -Default $Settings.engine)
            model           = [string](Get-MetraProp -Object $Response -Name 'model' -Default $Settings.model)
            resolvedModel   = $resolvedModel
            sessionId       = [string](Get-MetraProp -Object $Response -Name 'sessionId' -Default $SessionId)
            status          = $status
            error           = 'engine_request_failed'
            errorCode       = $errorCode
            errorDetail     = $errorDetail
            retryClass      = $retryClass
            secretsRefuse   = $false
            secretsReason   = $null
            secretsNotice   = $notice
            secretsScrubbed = [bool]($PromptScrub.Matched -or $CtxScrub.Matched -or $msgScrub.Matched)
            secretsKinds    = @($PromptScrub.Kinds) + @($CtxScrub.Kinds) + @($msgScrub.Kinds)
            scrubbedPrompt  = [string]$PromptScrub.Text
        }
    }
    return [PSCustomObject]@{
        ok              = $true
        message         = [string]$msgScrub.Text
        engine          = [string](Get-MetraProp -Object $Response -Name 'engine' -Default $Settings.engine)
        model           = [string](Get-MetraProp -Object $Response -Name 'model' -Default $Settings.model)
        resolvedModel   = $resolvedModel
        sessionId       = [string](Get-MetraProp -Object $Response -Name 'sessionId' -Default $SessionId)
        status          = $status
        error           = $null
        secretsRefuse   = $false
        secretsReason   = $null
        secretsNotice   = $notice
        secretsScrubbed = [bool]($PromptScrub.Matched -or $CtxScrub.Matched -or $msgScrub.Matched)
        secretsKinds    = @($PromptScrub.Kinds) + @($CtxScrub.Kinds) + @($msgScrub.Kinds)
        scrubbedPrompt  = [string]$PromptScrub.Text
    }
}

function ConvertTo-MetraAskEngineSafeError {
    <#
    .SYNOPSIS
        Maps raw engine exceptions to operator-safe error codes / messages.
    .NOTES
        Stable reason codes pass through with generic operator messages.
        Raw HTTP / host / auth exception text becomes engine_request_failed.
    #>
    [CmdletBinding()]
    param([string]$ErrorMessage)

    $raw = [string]$ErrorMessage
    if ($raw -match '^(engine_unsupported:|image_vision_unsupported$|secrets_refuse$)') {
        return [PSCustomObject]@{
            Code    = $raw
            Message = ''
        }
    }
    $known = @{
        enterprise_request_failed = 'Enterprise Ask request failed.'
        enterprise_auth_failed    = 'Enterprise Ask authentication failed.'
        ollama_unreachable        = 'Ollama Ask request failed.'
        llamacpp_unreachable      = 'llama.cpp Ask request failed.'
        engine_request_failed     = 'Ask engine request failed.'
    }
    if ($known.ContainsKey($raw)) {
        return [PSCustomObject]@{
            Code    = $raw
            Message = [string]$known[$raw]
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        Write-Verbose "Ask engine error detail: $raw"
    }
    return [PSCustomObject]@{
        Code    = 'engine_request_failed'
        Message = 'Ask engine request failed.'
    }
}

function New-MetraAskEngineErrorResult {
    param($Settings, [string]$SessionId, [string]$ErrorMessage, $PromptScrub, $CtxScrub)
    $safe = ConvertTo-MetraAskEngineSafeError -ErrorMessage $ErrorMessage
    return [PSCustomObject]@{
        ok              = $false
        message         = [string]$safe.Message
        engine          = $Settings.engine
        model           = $Settings.model
        sessionId       = $SessionId
        status          = 'error'
        error           = [string]$safe.Code
        secretsRefuse   = $false
        secretsReason   = $null
        secretsNotice   = $(if ($PromptScrub.Matched -or $CtxScrub.Matched) {
                Join-MetraAskSecretsNotices -Notices @($PromptScrub.Notice, $CtxScrub.Notice)
            } else { $null })
        secretsScrubbed = [bool]($PromptScrub.Matched -or $CtxScrub.Matched)
        secretsKinds    = @($PromptScrub.Kinds) + @($CtxScrub.Kinds)
        scrubbedPrompt  = [string]$PromptScrub.Text
    }
}

function Test-MetraAskCursorSidecarProcessId {
    <#
    .SYNOPSIS
        True when a PID is provably the Metra Cursor Ask node sidecar (fail closed when CommandLine is unavailable).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ProcessId)

    if ($ProcessId -le 0 -or $ProcessId -eq $PID) { return $false }
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    if ([string]$p.ProcessName -notmatch '^(?i)node(\.exe)?$') { return $false }

    try {
        $cim = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
        $cmd = if ($cim) { [string]$cim.CommandLine } else { '' }
        if ([string]::IsNullOrWhiteSpace($cmd)) { return $false }
        return [bool]($cmd -match '(?i)(engines[\\/]+cursor|server\.mjs)')
    }
    catch { return $false }
}

function Start-MetraAskEngine {
    <#
    .SYNOPSIS
        Starts Cursor sidecar when selected; openai_compat engines need no Metra process.
    .NOTES
        When ask.engine is cursor, always runs adopt/ensure so a stale PID file is repaired
        even if /health is already ok.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $cap = Get-MetraAskCapability -MetraRoot $MetraRoot
    if (-not $cap.selected) { return $cap }

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if ($settings.engine -ne 'cursor') {
        return Get-MetraAskCapability -MetraRoot $MetraRoot
    }

    $null = Invoke-MetraAskCursorSidecarEnsure -MetraRoot $MetraRoot -CursorPort $settings.cursorPort `
        -CursorModel $settings.cursorModel -CursorOptimizeFor $settings.cursorOptimizeFor

    return Get-MetraAskCapability -MetraRoot $MetraRoot
}

function Stop-MetraAskEngine {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Port = 0,
        [switch]$IncludePortListeners
    )

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if ($Port -le 0) { $Port = $settings.cursorPort }

    $pidFile = Get-MetraAskEnginePidFile -Port $Port
    $targets = New-Object System.Collections.Generic.List[int]
    $recordedPid = $null
    $removeStalePidFile = $false
    if (Test-Path -LiteralPath $pidFile) {
        $recorded = 0
        if ([int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$recorded)) {
            if ($recorded -ne $PID -and (Test-MetraAskCursorSidecarProcessId -ProcessId $recorded)) {
                [void]$targets.Add($recorded)
                $recordedPid = $recorded
            }
            elseif ($recorded -ne $PID -and (Get-Process -Id $recorded -ErrorAction SilentlyContinue)) {
                Write-Warning "Ask engine PID file $recorded is not a Metra Cursor sidecar node process; not stopping it."
                $removeStalePidFile = $true
            }
            else {
                $removeStalePidFile = $true
            }
        }
        else {
            $removeStalePidFile = $true
        }
    }

    if ($IncludePortListeners) {
        foreach ($listenerPid in @(Get-MetraAskCursorSidecarListenerProcessIds -Port $Port)) {
            if (-not $targets.Contains($listenerPid)) {
                [void]$targets.Add($listenerPid)
            }
        }
    }

    $stoppedRecorded = $false
    foreach ($target in @($targets)) {
        if (-not $PSCmdlet.ShouldProcess("Ask engine process $target on port $Port", 'Stop')) { continue }
        try {
            Stop-Process -Id $target -Force -ErrorAction Stop
            Write-Host "Stopped Ask engine on port $Port (process $target)." -ForegroundColor DarkGray
            if ($null -ne $recordedPid -and $target -eq $recordedPid) {
                $stoppedRecorded = $true
            }
        }
        catch {
            Write-Warning "Could not stop Ask engine process $target - $($_.Exception.Message)"
        }
    }

    if ($stoppedRecorded -and (Test-Path -LiteralPath $pidFile)) {
        if ($PSCmdlet.ShouldProcess($pidFile, 'Remove Ask engine PID file')) {
            Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        }
    }
    elseif ($removeStalePidFile -and (Test-Path -LiteralPath $pidFile)) {
        if ($PSCmdlet.ShouldProcess($pidFile, 'Remove stale Ask engine PID file')) {
            Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-MetraAskCursorSidecarGeneration {
    <#
    .SYNOPSIS
        Sidecar generation identity: owned listener PID + process StartTime (or recorded PID).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Port = 0
    )

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if ($Port -le 0) { $Port = [int]$settings.cursorPort }
    $listenerIds = @(Get-MetraAskCursorSidecarListenerProcessIds -Port $Port)
    $pidValue = if ($listenerIds.Count -gt 0) { [int]$listenerIds[0] } else { Get-MetraAskEngineRecordedProcessId -MetraRoot $MetraRoot }
    if (-not $pidValue -or $pidValue -le 0) {
        return [PSCustomObject]@{ ProcessId = $null; StartTimeUtc = $null; Token = 'none' }
    }
    $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    $start = if ($proc -and $proc.StartTime) { $proc.StartTime.ToUniversalTime().ToString('o') } else { 'unknown' }
    return [PSCustomObject]@{
        ProcessId     = $pidValue
        StartTimeUtc  = $start
        Token         = "$pidValue|$start"
    }
}

function Test-MetraAskOpaqueSdkFailure {
    <#
    .SYNOPSIS
        True when a cursor engine result is classified as opaque_sdk_failure (structured fields).
    #>
    [CmdletBinding()]
    param($EngineResult)

    if ($null -eq $EngineResult) { return $false }
    if ([bool](Get-MetraProp -Object $EngineResult -Name 'ok' -Default $false)) { return $false }
    if ([bool](Get-MetraProp -Object $EngineResult -Name 'secretsRefuse' -Default $false)) { return $false }
    $status = [string](Get-MetraProp -Object $EngineResult -Name 'status' -Default '')
    if ($status -eq 'finished' -or $status -eq 'refused' -or $status -eq 'degraded') { return $false }
    $retryClass = [string](Get-MetraProp -Object $EngineResult -Name 'retryClass' -Default '')
    if ($retryClass -eq 'opaque_sdk_failure') { return $true }
    $error = [string](Get-MetraProp -Object $EngineResult -Name 'error' -Default '')
    $detail = [string](Get-MetraProp -Object $EngineResult -Name 'errorDetail' -Default '')
    if ($error -eq 'engine_request_failed' -and [string]::IsNullOrWhiteSpace($detail)) { return $true }
    return $false
}

if (-not (Get-Variable -Name MetraAskSidecarRestartLock -Scope Script -ErrorAction SilentlyContinue)) {
    $script:MetraAskSidecarRestartLock = New-Object object
    $script:MetraAskSidecarRestartGate = @{
        InFlightToken  = $null
        CompletedToken = $null
        CompletedOk    = $null
        CompletedAt    = $null
    }
}

function Invoke-MetraAskCursorSingleFlightRestart {
    <#
    .SYNOPSIS
        Restarts the Cursor sidecar at most once per generation (PID+start). Concurrent callers wait or skip.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FailedGenerationToken,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $gate = $script:MetraAskSidecarRestartGate
    $lock = $script:MetraAskSidecarRestartLock
    $current = Get-MetraAskCursorSidecarGeneration -MetraRoot $MetraRoot
    # 'none' is not a reusable generation - each dead-sidecar failure must attempt restart.
    if ($FailedGenerationToken -ne 'none' -and $current.Token -ne $FailedGenerationToken -and $current.Token -ne 'none') {
        # Another caller already recycled; skip restart.
        return [PSCustomObject]@{
            restarted = $false
            skipped   = $true
            reason    = 'generation_changed'
            ok        = [bool](Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 2)
            capability = Get-MetraAskCapability -MetraRoot $MetraRoot
        }
    }

    $ownRestart = $false
    $deadline = [datetime]::UtcNow.AddSeconds(90)
    $flightToken = if ($FailedGenerationToken -eq 'none') {
        "none|$([guid]::NewGuid().ToString('n'))"
    } else {
        $FailedGenerationToken
    }
    while ([datetime]::UtcNow -lt $deadline) {
        $shouldStart = $false
        [System.Threading.Monitor]::Enter($lock)
        try {
            if ($FailedGenerationToken -ne 'none' -and $gate.CompletedToken -eq $FailedGenerationToken -and $null -ne $gate.CompletedOk) {
                $okDone = [bool]$gate.CompletedOk
                return [PSCustomObject]@{
                    restarted  = $true
                    skipped    = $false
                    reason     = 'joined_completed'
                    ok         = $okDone
                    capability = Get-MetraAskCapability -MetraRoot $MetraRoot
                }
            }
            if ([string]::IsNullOrWhiteSpace([string]$gate.InFlightToken)) {
                $gate.InFlightToken = $flightToken
                $gate.CompletedToken = $null
                $gate.CompletedOk = $null
                $shouldStart = $true
                $ownRestart = $true
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($lock)
        }

        if ($shouldStart) { break }

        $nowGen = Get-MetraAskCursorSidecarGeneration -MetraRoot $MetraRoot
        if ($FailedGenerationToken -ne 'none' -and $nowGen.Token -ne $FailedGenerationToken -and $nowGen.Token -ne 'none') {
            return [PSCustomObject]@{
                restarted  = $false
                skipped    = $true
                reason     = 'generation_changed_while_waiting'
                ok         = [bool](Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 2)
                capability = Get-MetraAskCapability -MetraRoot $MetraRoot
            }
        }
        Start-Sleep -Milliseconds 200
    }

    if (-not $ownRestart) {
        return [PSCustomObject]@{
            restarted  = $false
            skipped    = $true
            reason     = 'restart_wait_timeout'
            ok         = [bool](Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 2)
            capability = Get-MetraAskCapability -MetraRoot $MetraRoot
        }
    }

    try {
        $cap = Restart-MetraAskEngine -MetraRoot $MetraRoot -Confirm:$false
        $ok = [bool](Get-MetraProp -Object $cap -Name 'available' -Default $false) -and `
            [bool](Get-MetraProp -Object $cap -Name 'engineHealthy' -Default $false)
        if (-not $ok) {
            $ok = [bool](Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 2)
        }
        [System.Threading.Monitor]::Enter($lock)
        try {
            # Never persist CompletedToken='none' - that would short-circuit future dead-sidecar restarts.
            $gate.CompletedToken = $(if ($FailedGenerationToken -eq 'none') { $null } else { $FailedGenerationToken })
            $gate.CompletedOk = $ok
            $gate.CompletedAt = [datetime]::UtcNow
            $gate.InFlightToken = $null
        }
        finally {
            [System.Threading.Monitor]::Exit($lock)
        }
        return [PSCustomObject]@{
            restarted  = $true
            skipped    = $false
            reason     = $(if ($ok) { 'restart_ok' } else { 'restart_failed' })
            ok         = $ok
            capability = $cap
        }
    }
    catch {
        [System.Threading.Monitor]::Enter($lock)
        try {
            $gate.CompletedToken = $(if ($FailedGenerationToken -eq 'none') { $null } else { $FailedGenerationToken })
            $gate.CompletedOk = $false
            $gate.CompletedAt = [datetime]::UtcNow
            $gate.InFlightToken = $null
        }
        finally {
            [System.Threading.Monitor]::Exit($lock)
        }
        return [PSCustomObject]@{
            restarted  = $true
            skipped    = $false
            reason     = 'restart_threw'
            ok         = $false
            capability = Get-MetraAskCapability -MetraRoot $MetraRoot
            error      = $_.Exception.Message
        }
    }
}

function Invoke-MetraAskCursorOpaqueRecovery {
    <#
    .SYNOPSIS
        One Restart (single-flight) + one retry for opaque Cursor SDK failures.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$EngineResult,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Cwd,
        [hashtable]$Context = @{},
        [string]$SessionId,
        [object[]]$Images = @(),
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 180
    )

    if (-not (Test-MetraAskOpaqueSdkFailure -EngineResult $EngineResult)) {
        return [PSCustomObject]@{
            attempted = $false
            result    = $EngineResult
        }
    }

    $failedGen = Get-MetraAskCursorSidecarGeneration -MetraRoot $MetraRoot
    $restart = Invoke-MetraAskCursorSingleFlightRestart -FailedGenerationToken $failedGen.Token -MetraRoot $MetraRoot

    $safeContext = @{}
    if ($null -ne $Context) {
        foreach ($k in @($Context.Keys)) {
            $safeContext[$k] = $Context[$k]
        }
    }
    $safeContext['forceContinuity'] = $true

    if (-not [bool]$restart.ok -and -not [bool]$restart.skipped) {
        $trail = "Cursor Ask failed after one sidecar recycle attempt. Initial failure: opaque SDK error. Restart: $($restart.reason)."
        $failed = $EngineResult | Select-Object *
        $failed | Add-Member -NotePropertyName message -NotePropertyValue $trail -Force
        $failed | Add-Member -NotePropertyName recoveryTrail -NotePropertyValue $trail -Force
        $failed | Add-Member -NotePropertyName restartReason -NotePropertyValue $restart.reason -Force
        return [PSCustomObject]@{
            attempted = $true
            result    = $failed
            restart   = $restart
        }
    }

    $retry = Invoke-MetraAskEngine -Prompt $Prompt -Cwd $Cwd -Context $safeContext `
        -SessionId $SessionId -Images $Images -MetraRoot $MetraRoot -TimeoutSec $TimeoutSec

    if ([bool](Get-MetraProp -Object $retry -Name 'ok' -Default $false)) {
        $retry | Add-Member -NotePropertyName recoveryTrail -NotePropertyValue 'opaque_sdk_failure: recycled once and retry succeeded' -Force
        return [PSCustomObject]@{
            attempted = $true
            result    = $retry
            restart   = $restart
        }
    }

    $detail = [string](Get-MetraProp -Object $retry -Name 'errorDetail' -Default '')
    if ([string]::IsNullOrWhiteSpace($detail)) {
        $detail = [string](Get-MetraProp -Object $retry -Name 'message' -Default 'engine_request_failed')
    }
    $trail = @(
        'Cursor Ask failed after one sidecar recycle and retry.'
        'Initial failure: opaque SDK error'
        "Restart: $($restart.reason)"
        "Retry: $(Get-MetraProp -Object $retry -Name 'error' -Default 'engine_request_failed'), detail: $detail"
    ) -join "`n"
    $retry | Add-Member -NotePropertyName recoveryTrail -NotePropertyValue $trail -Force
    $retry | Add-Member -NotePropertyName message -NotePropertyValue $trail -Force
    return [PSCustomObject]@{
        attempted = $true
        result    = $retry
        restart   = $restart
    }
}

function Restart-MetraAskEngine {
    <#
    .SYNOPSIS
        Stops then starts the Cursor Ask sidecar (no-op start path for non-cursor engines).
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param([string]$MetraRoot = (Get-MetraRoot))

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if ($settings.engine -ne 'cursor') {
        return Get-MetraAskCapability -MetraRoot $MetraRoot
    }

    if (-not $PSCmdlet.ShouldProcess('Ask Cursor sidecar', 'Restart')) {
        $cancelled = Get-MetraAskCapability -MetraRoot $MetraRoot
        $cancelled | Add-Member -NotePropertyName available -NotePropertyValue $false -Force
        $cancelled | Add-Member -NotePropertyName reason -NotePropertyValue 'restart_cancelled' -Force
        return $cancelled
    }

    $port = [int](Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot).Port
    if (Test-MetraOpsDeskResponding -Port $port -TimeoutSec 2) {
        $null = Restart-MetraOpsDesk -Port $port -MetraRoot $MetraRoot -NoRefresh
        return Get-MetraAskCapability -MetraRoot $MetraRoot
    }

    $pidBefore = Get-MetraAskEngineRecordedProcessId -MetraRoot $MetraRoot

    $null = Stop-MetraAskEngine -MetraRoot $MetraRoot -IncludePortListeners -Confirm:$false

    $deadline = [datetime]::UtcNow.AddSeconds(10)
    while ([datetime]::UtcNow -lt $deadline) {
        if (-not (Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 1)) { break }
        Start-Sleep -Milliseconds 250
    }
    if (Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 1) {
        Write-Warning 'Ask sidecar still healthy after stop; forcing port listener recycle.'
        $null = Stop-MetraAskEngine -MetraRoot $MetraRoot -IncludePortListeners -Confirm:$false
        $deadline = [datetime]::UtcNow.AddSeconds(10)
        while ([datetime]::UtcNow -lt $deadline) {
            if (-not (Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 1)) { break }
            Start-Sleep -Milliseconds 250
        }
    }
    if (Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 1) {
        $logErr = Get-MetraAskEngineLogPath -Port $settings.cursorPort -Stream stderr
        Write-Warning "Ask sidecar still healthy after forced stop; restart did not recycle the process. See $logErr (and matching .out.log)"
        $stale = Get-MetraAskCapability -MetraRoot $MetraRoot
        $stale | Add-Member -NotePropertyName reason -NotePropertyValue 'restart_stale_process' -Force
        $stale | Add-Member -NotePropertyName available -NotePropertyValue $false -Force
        return $stale
    }

    $cap = Start-MetraAskEngine -MetraRoot $MetraRoot
    $pidAfter = Get-MetraAskEngineRecordedProcessId -MetraRoot $MetraRoot
    if ($cap.available -and $null -ne $pidBefore -and $null -ne $pidAfter -and $pidBefore -eq $pidAfter) {
        Write-Warning "Ask sidecar restart completed but PID unchanged ($pidAfter)."
        $cap | Add-Member -NotePropertyName reason -NotePropertyValue 'restart_same_pid' -Force
        $cap | Add-Member -NotePropertyName available -NotePropertyValue $false -Force
    }
    return $cap
}

function Get-MetraAskEngineRecordedProcessId {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    $pidFile = Get-MetraAskEnginePidFile -Port $settings.cursorPort
    if (-not (Test-Path -LiteralPath $pidFile)) { return $null }
    $recorded = 0
    if ([int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$recorded) -and $recorded -gt 0) {
        return $recorded
    }
    return $null
}

function Get-MetraAskEngineFailureMessage {
    <#
    .SYNOPSIS
        Operator-safe Ask engine failure text (surfaces licensing/quota when present).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$EngineResult,
        [string]$HandoffNext = ''
    )

    $engineErr = [string](Get-MetraProp -Object $EngineResult -Name 'message' -Default '')
    $errorCode = [string](Get-MetraProp -Object $EngineResult -Name 'errorCode' -Default '')
    $errorDetail = [string](Get-MetraProp -Object $EngineResult -Name 'errorDetail' -Default '')

    if ($errorCode -eq 'cursor_usage_limit' -or $errorCode -eq 'cursor_billing_limit') {
        $detail = if (-not [string]::IsNullOrWhiteSpace($errorDetail)) { $errorDetail } else { $engineErr }
        $detail = ($detail -replace '^The Ask engine run failed:\s*', '').Trim()
        $detail = ($detail -replace '^Ask engine could not start:\s*', '').Trim()
        return @"
Cursor Ask billing or usage limit:

$detail

Metra can still route work and recommend durable homes. Switch Ask to Ollama (.\metra.ps1 ask recommend) or use a personal API key with quota remaining.
"@.Trim()
    }

    if ($errorCode -eq 'cursor_model_unavailable') {
        $detail = if (-not [string]::IsNullOrWhiteSpace($errorDetail)) { $errorDetail } else { $engineErr }
        $detail = ($detail -replace '^The Ask engine run failed:\s*', '').Trim()
        $detail = ($detail -replace '^Ask engine could not start:\s*', '').Trim()
        return @"
Ask model not available for this API key:

$detail

Pin a supported model: .\metra.ps1 ask engine set cursor -Model default
(or gemini-3.7-flash, composer-2.5). Team keys usually support auto-smart; when auto-smart is missing, Metra falls back to a concrete catalog id. gemini-3.7-flash is valid on personal keys when listed for the key.
"@.Trim()
    }

    if ($errorCode -eq 'cursor_auth_error') {
        $detail = if (-not [string]::IsNullOrWhiteSpace($errorDetail)) { $errorDetail } else { $engineErr }
        $detail = ($detail -replace '^The Ask engine run failed:\s*', '').Trim()
        $detail = ($detail -replace '^Ask engine could not start:\s*', '').Trim()
        return @"
Cursor Ask authentication failed (key or session), not a model restriction:

$detail

Re-set the User key and recycle Ask: .\metra.ps1 ask key set <key>
Then: .\metra.ps1 ask engine restart -Confirm:`$false
Inspect may keep pinning gemini-3.7-flash on personal keys.
"@.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($engineErr)) {
        return $engineErr.Trim()
    }

    $next = if (-not [string]::IsNullOrWhiteSpace($HandoffNext)) { $HandoffNext } else { 'Try .\metra.ps1 ops -Stop then .\metra.ps1 ops -NoBrowser, or .\metra.ps1 ask engine restart -Confirm:$false.' }
    return @"
Ask engine unavailable.

The Ask engine returned an error. Metra can still route work and recommend durable homes.

$next
"@.Trim()
}

function Restart-MetraAskDeskAfterKeyChange {
    <#
    .SYNOPSIS
        Recycles Ops desk + Ask sidecar after CURSOR_API_KEY change (one product lifecycle).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    $port = [int](Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot).Port

    if (Test-MetraOpsDeskResponding -Port $port -TimeoutSec 2) {
        try {
            $deskResult = Restart-MetraOpsDesk -Port $port -MetraRoot $MetraRoot -NoRefresh
            return [PSCustomObject]@{
                sidecarRestarted      = $true
                sidecarRestartWarning = $null
                deskRestarted         = [bool]$deskResult.restarted
                deskRestartWarning    = $(if ($deskResult.restarted) { $null } else { [string]$deskResult.reason })
            }
        }
        catch {
            return [PSCustomObject]@{
                sidecarRestarted      = $false
                sidecarRestartWarning = $_.Exception.Message
                deskRestarted         = $false
                deskRestartWarning    = $_.Exception.Message
            }
        }
    }

    if ($settings.engine -ne 'cursor') {
        return [PSCustomObject]@{
            sidecarRestarted      = $null
            sidecarRestartWarning = $null
            deskRestarted         = $null
            deskRestartWarning    = 'Ops desk was not running.'
        }
    }

    try {
        $pidBefore = Get-MetraAskEngineRecordedProcessId -MetraRoot $MetraRoot
        $cap = Restart-MetraAskEngine -MetraRoot $MetraRoot -Confirm:$false
        $pidAfter = Get-MetraAskEngineRecordedProcessId -MetraRoot $MetraRoot
        $restarted = [bool]$cap.available
        if ($restarted -and $null -ne $pidBefore -and $null -ne $pidAfter -and $pidBefore -eq $pidAfter) {
            $restarted = $false
        }
        return [PSCustomObject]@{
            sidecarRestarted      = $restarted
            sidecarRestartWarning = $(if ($restarted) { $null } else { [string]$cap.reason })
            deskRestarted         = $null
            deskRestartWarning    = 'Ops desk was not running; sidecar-only recycle.'
        }
    }
    catch {
        $msg = 'Ask sidecar restart failed after key change.'
        Write-Warning $msg
        Write-Verbose $_.Exception.Message
        return [PSCustomObject]@{
            sidecarRestarted      = $false
            sidecarRestartWarning = $msg
            deskRestarted         = $null
            deskRestartWarning    = $null
        }
    }
}

function Restart-MetraAskSidecarAfterKeyChange {
    <#
    .SYNOPSIS
        Recycles the Cursor Ask sidecar when ask.engine is cursor (key is process env at start).
    .NOTES
        Prefer Restart-MetraAskDeskAfterKeyChange for operator key set (Ops + Ask together).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return Restart-MetraAskDeskAfterKeyChange -MetraRoot $MetraRoot
}

function Set-MetraCursorApiKey {
    <#
    .SYNOPSIS
        Sets CURSOR_API_KEY in User environment (never prints the value).
    .NOTES
        Restarts the Cursor Ask sidecar when ask.engine is cursor. Use -WhatIf to preview.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Set')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Set')][string]$ApiKey,
        [Parameter(Mandatory, ParameterSetName = 'Clear')][switch]$Clear
    )

    if ($PSCmdlet.ParameterSetName -eq 'Clear') {
        if (-not $PSCmdlet.ShouldProcess('User CURSOR_API_KEY', 'Clear and restart Ask sidecar')) {
            return [PSCustomObject]@{ status = 'cancelled' }
        }
        if ($WhatIfPreference) {
            return [PSCustomObject]@{ status = 'whatif'; action = 'clear'; sidecarRestarted = $null }
        }
        $priorKey = [Environment]::GetEnvironmentVariable('CURSOR_API_KEY', 'User')
        [Environment]::SetEnvironmentVariable('CURSOR_API_KEY', $null, 'User')
        Remove-Item Env:CURSOR_API_KEY -ErrorAction SilentlyContinue
        $result = [PSCustomObject]@{ status = 'cleared' }
        $restart = Restart-MetraAskSidecarAfterKeyChange
        if ($null -ne $restart.sidecarRestarted -and -not $restart.sidecarRestarted) {
            if ($priorKey) {
                [Environment]::SetEnvironmentVariable('CURSOR_API_KEY', $priorKey, 'User')
                $env:CURSOR_API_KEY = $priorKey
                $rollbackRestart = Restart-MetraAskSidecarAfterKeyChange
                $result | Add-Member -NotePropertyName keyRollback -NotePropertyValue $true -Force
                $result.status = 'rolled_back'
                if ($rollbackRestart.sidecarRestartWarning) {
                    $restart.sidecarRestartWarning = "$($rollbackRestart.sidecarRestartWarning) Rolled back to prior key."
                }
                elseif ($restart.sidecarRestartWarning) {
                    $restart.sidecarRestartWarning = "$($restart.sidecarRestartWarning) Rolled back to prior key."
                }
            }
            elseif ($restart.sidecarRestartWarning) {
                try { $null = Stop-MetraAskEngine -IncludePortListeners -Confirm:$false } catch { }
                try { $null = Start-MetraAskEngine } catch { }
                $result.status = 'failed'
                $restart.sidecarRestarted = $false
                $restart.sidecarRestartWarning = "$($restart.sidecarRestartWarning) Ask sidecar recycle attempted; verify Ask before use."
            }
        }
        $result | Add-Member -NotePropertyName sidecarRestarted -NotePropertyValue $restart.sidecarRestarted -Force
        if ($null -ne $restart.deskRestarted) {
            $result | Add-Member -NotePropertyName deskRestarted -NotePropertyValue $restart.deskRestarted -Force
        }
        if ($restart.sidecarRestartWarning) {
            $result | Add-Member -NotePropertyName sidecarRestartWarning -NotePropertyValue $restart.sidecarRestartWarning -Force
        }
        if ($restart.deskRestartWarning) {
            $result | Add-Member -NotePropertyName deskRestartWarning -NotePropertyValue $restart.deskRestartWarning -Force
        }
        return $result
    }
    $trimmed = $ApiKey.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'ApiKey is empty. Pass -Clear to remove the User-scope key.'
    }
    if (-not $PSCmdlet.ShouldProcess('User CURSOR_API_KEY', 'Set and restart Ask sidecar')) {
        return [PSCustomObject]@{ status = 'cancelled' }
    }
    if ($WhatIfPreference) {
        return [PSCustomObject]@{ status = 'whatif'; action = 'set'; scope = 'User'; sidecarRestarted = $null }
    }
    $priorKey = [Environment]::GetEnvironmentVariable('CURSOR_API_KEY', 'User')
    [Environment]::SetEnvironmentVariable('CURSOR_API_KEY', $trimmed, 'User')
    $env:CURSOR_API_KEY = $trimmed
    $result = [PSCustomObject]@{ status = 'set'; scope = 'User' }
    $restart = Restart-MetraAskSidecarAfterKeyChange
    if ($null -ne $restart.sidecarRestarted -and -not $restart.sidecarRestarted) {
        if ($priorKey) {
            [Environment]::SetEnvironmentVariable('CURSOR_API_KEY', $priorKey, 'User')
            $env:CURSOR_API_KEY = $priorKey
        }
        else {
            [Environment]::SetEnvironmentVariable('CURSOR_API_KEY', $null, 'User')
            Remove-Item Env:CURSOR_API_KEY -ErrorAction SilentlyContinue
        }
        $rollbackRestart = Restart-MetraAskSidecarAfterKeyChange
        $result | Add-Member -NotePropertyName keyRollback -NotePropertyValue $true -Force
        $result.status = 'rolled_back'
        if ($rollbackRestart.sidecarRestartWarning) {
            $restart.sidecarRestartWarning = "$($restart.sidecarRestartWarning) Rolled back to prior key."
        }
        elseif ($restart.sidecarRestartWarning) {
            $restart.sidecarRestartWarning = "$($restart.sidecarRestartWarning) Rolled back to prior key."
        }
        else {
            $restart.sidecarRestartWarning = 'Ask sidecar restart failed; rolled back to prior key.'
        }
    }
    if ($null -ne $restart.sidecarRestarted) {
        $result | Add-Member -NotePropertyName sidecarRestarted -NotePropertyValue $restart.sidecarRestarted -Force
    }
    if ($null -ne $restart.deskRestarted) {
        $result | Add-Member -NotePropertyName deskRestarted -NotePropertyValue $restart.deskRestarted -Force
    }
    if ($restart.sidecarRestartWarning) {
        $result | Add-Member -NotePropertyName sidecarRestartWarning -NotePropertyValue $restart.sidecarRestartWarning -Force
    }
    if ($restart.deskRestartWarning) {
        $result | Add-Member -NotePropertyName deskRestartWarning -NotePropertyValue $restart.deskRestartWarning -Force
    }
    return $result
}

function Get-MetraAskEngineMenu {
    <#
    .SYNOPSIS
        Engine options for Advanced UI / CLI (enterprise hidden unless configured).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    $cap = Get-MetraAskCapability -MetraRoot $MetraRoot
    $items = @(
        [PSCustomObject]@{ id = 'ollama'; label = 'Ollama (recommended)'; kind = 'recommended'; disabled = $false; note = "Pin: $($settings.ollamaModel)" }
        [PSCustomObject]@{ id = 'llamacpp'; label = 'llama.cpp (experimental)'; kind = 'advanced'; disabled = $false; note = 'Never auto-recommended' }
        [PSCustomObject]@{
            id       = 'cursor'
            label    = $(if ($cap.apiKeyPresent) { 'Cursor Ask' } else { 'Cursor Ask - Needs API key' })
            kind     = 'premium'
            disabled = $false
            note     = $(if ($cap.ideInstalled) { 'IDE detected' } else { 'IDE optional' })
        }
    )
    if ($settings.enterpriseConfigured) {
        $items += [PSCustomObject]@{ id = 'enterprise'; label = 'Enterprise'; kind = 'it'; disabled = $false; note = $settings.enterpriseBaseUrl }
    }
    return $items
}
