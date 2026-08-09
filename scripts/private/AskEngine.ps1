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

function Get-MetraAskConfigPath {
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
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $cfg = $null
    try { $cfg = Get-MetraConfig } catch { $cfg = $null }
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
    # Default: Cursor Router Auto Cost (legacy Auto - Cursor Models pool).
    $cursorModel = 'auto-smart'
    $cursorOptimizeFor = 'cost'
    if ($null -ne $cursor) {
        $p = Get-MetraProp -Object $cursor -Name 'port' -Default 7381
        if ($p -as [int]) { $cursorPort = [int]$p }
        $m = [string](Get-MetraProp -Object $cursor -Name 'model' -Default 'auto-smart')
        if (-not [string]::IsNullOrWhiteSpace($m)) { $cursorModel = $m.Trim() }
        $of = [string](Get-MetraProp -Object $cursor -Name 'optimizeFor' -Default 'cost')
        if (-not [string]::IsNullOrWhiteSpace($of)) { $cursorOptimizeFor = $of.Trim().ToLowerInvariant() }
    }
    $cursorModelLower = $cursorModel.ToLowerInvariant()
    if ($cursorModelLower -in @('auto-cost', 'auto cost', 'cost', 'auto')) {
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
    if ($null -ne $enterprise) {
        $entBase = [string](Get-MetraProp -Object $enterprise -Name 'baseUrl' -Default '').Trim().TrimEnd('/')
        $entModel = [string](Get-MetraProp -Object $enterprise -Name 'model' -Default '').Trim()
        $ek = [string](Get-MetraProp -Object $enterprise -Name 'apiKeyEnv' -Default 'METRA_ASK_ENTERPRISE_KEY')
        if (-not [string]::IsNullOrWhiteSpace($ek)) { $entApiKeyEnv = $ek.Trim() }
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
        Merges a hashtable into ask.* in metra.config.json and clears config cache.
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
                return [bool](Get-MetraProp -Object $response -Name 'ok' -Default $false)
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
    $apiKeyPresent = -not [string]::IsNullOrWhiteSpace((Get-MetraCursorApiKey))
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
            $runtime = Test-MetraAskOpenAICompatHealth -BaseUrl $settings.enterpriseBaseUrl -Kind openai -TimeoutSec 3
            $base.runtimeReady = $runtime
            $base.modelPresent = $runtime
            if (-not $runtime) {
                $base.reason = 'enterprise_unreachable'
                $base.message = @"
Ask engine unavailable.

Enterprise endpoint is configured but not reachable.
Metra can still classify work and show routing.
"@.Trim()
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
    $match = $projects | Where-Object { $_.Name -eq $Where } | Select-Object -First 1
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

function Invoke-MetraAskEngine {
    <#
    .SYNOPSIS
        Calls the selected Ask engine (cursor loopback or openai_compat).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Cwd,
        [hashtable]$Context = @{},
        [string]$SessionId,
        [object[]]$Images = @(),
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 180
    )

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot

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
        $url = "http://127.0.0.1:$($settings.cursorPort)/v1/complete"
        $body = @{
            prompt  = [string]$promptScrub.Text
            cwd     = $Cwd
            context = $safeContext
            mode    = 'answer'
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

    $status = [string](Get-MetraProp -Object $Response -Name 'status' -Default 'finished')
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
    $notice = Join-MetraAskSecretsNotices -Notices @(
        $(if ($PromptScrub.Matched) { $PromptScrub.Notice }),
        $(if ($CtxScrub.Matched) { $CtxScrub.Notice }),
        $(if ($msgScrub.Matched) { $msgScrub.Notice })
    )
    return [PSCustomObject]@{
        ok              = $true
        message         = [string]$msgScrub.Text
        engine          = [string](Get-MetraProp -Object $Response -Name 'engine' -Default $Settings.engine)
        model           = [string](Get-MetraProp -Object $Response -Name 'model' -Default $Settings.model)
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

function New-MetraAskEngineErrorResult {
    param($Settings, [string]$SessionId, [string]$ErrorMessage, $PromptScrub, $CtxScrub)
    return [PSCustomObject]@{
        ok              = $false
        message         = ''
        engine          = $Settings.engine
        model           = $Settings.model
        sessionId       = $SessionId
        status          = 'error'
        error           = $ErrorMessage
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

function Start-MetraAskEngine {
    <#
    .SYNOPSIS
        Starts Cursor sidecar when selected; openai_compat engines need no Metra process.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $cap = Get-MetraAskCapability -MetraRoot $MetraRoot
    if (-not $cap.selected) { return $cap }
    if ($cap.available) { return $cap }

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if ($settings.engine -ne 'cursor') {
        return Get-MetraAskCapability -MetraRoot $MetraRoot
    }

    $nodePath = Get-MetraAskNodePath -MetraRoot $MetraRoot
    $sidecar = Get-MetraAskCursorSidecarPath -MetraRoot $MetraRoot
    $key = Get-MetraCursorApiKey
    if (-not $nodePath -or -not $sidecar -or [string]::IsNullOrWhiteSpace($key) -or -not (Test-MetraAskCursorSidecarDeps -MetraRoot $MetraRoot)) {
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
        $env:METRA_ASK_OPTIMIZE_FOR = $settings.cursorOptimizeFor
        $env:METRA_ASK_ENGINE = 'cursor'
        try {
            $proc = Start-Process -FilePath $nodePath -ArgumentList @($sidecar) `
                -WorkingDirectory (Split-Path -Parent $sidecar) `
                -PassThru -WindowStyle Hidden
        }
        finally {
            if ($null -eq $previous) { Remove-Item Env:CURSOR_API_KEY -ErrorAction SilentlyContinue }
            else { $env:CURSOR_API_KEY = $previous }
            Remove-Item Env:METRA_ASK_PORT -ErrorAction SilentlyContinue
            Remove-Item Env:METRA_ASK_MODEL -ErrorAction SilentlyContinue
            Remove-Item Env:METRA_ASK_OPTIMIZE_FOR -ErrorAction SilentlyContinue
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

function Set-MetraCursorApiKey {
    <#
    .SYNOPSIS
        Sets CURSOR_API_KEY in User environment (never prints the value).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiKey,
        [switch]$Clear
    )

    if ($Clear) {
        [Environment]::SetEnvironmentVariable('CURSOR_API_KEY', $null, 'User')
        Remove-Item Env:CURSOR_API_KEY -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ status = 'cleared' }
    }
    $trimmed = $ApiKey.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'ApiKey is empty. Pass -Clear to remove the User-scope key.'
    }
    [Environment]::SetEnvironmentVariable('CURSOR_API_KEY', $trimmed, 'User')
    $env:CURSOR_API_KEY = $trimmed
    return [PSCustomObject]@{ status = 'set'; scope = 'User' }
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
