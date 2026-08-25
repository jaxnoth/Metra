# Ask recommend / accept / install (Ollama-first consumer path).

function Get-MetraAskMachineSignals {
    [CmdletBinding()]
    param()

    $ramGb = $null
    $ramDetected = $false
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $ramGb = [math]::Round(([double]$cs.TotalPhysicalMemory) / 1GB, 1)
        $ramDetected = $true
    }
    catch { }

    $hasUsefulGpu = $false
    try {
        $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue)
        foreach ($g in $gpus) {
            $name = [string]$g.Name
            if ($name -match 'NVIDIA|AMD Radeon|Intel Arc|GeForce|Radeon RX') {
                $hasUsefulGpu = $true
                break
            }
            $vram = 0
            try { $vram = [int64]$g.AdapterRAM } catch { }
            if ($vram -gt 2GB) { $hasUsefulGpu = $true; break }
        }
    }
    catch { }

    $npuPresent = $null
    try {
        $pnps = @(Get-PnpDevice -Class System -ErrorAction SilentlyContinue | Where-Object {
                $_.FriendlyName -match 'NPU|Neural|AI Boost|Intel\(R\) AI|Qualcomm.*NPU|AMD.*NPU'
            })
        if ($pnps.Count -gt 0) { $npuPresent = $true }
    }
    catch { }

    return [PSCustomObject]@{
        ramGb         = $ramGb
        ramDetected   = $ramDetected
        hasUsefulGpu  = $hasUsefulGpu
        npuPresent    = $npuPresent
        ideInstalled  = (Test-MetraCursorInstall)
        apiKeyPresent = (-not [string]::IsNullOrWhiteSpace((Get-MetraCursorApiKey)))
    }
}

function Get-MetraAskEngineRecommendation {
    <#
    .SYNOPSIS
        Recommend Ollama + size band from machine signals (never llama.cpp / GPT4All).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [nullable[bool]]$NpuPresent
    )

    $signals = Get-MetraAskMachineSignals
    if ($PSBoundParameters.ContainsKey('NpuPresent') -and $null -ne $NpuPresent) {
        $signals.npuPresent = [bool]$NpuPresent
    }

    $pins = Get-MetraAskModelPinTable
    $sizeBand = 'medium'
    $reasons = [System.Collections.Generic.List[string]]::new()

    if (-not [bool]$signals.ramDetected -or $null -eq $signals.ramGb) {
        $sizeBand = 'medium'
        $reasons.Add('RAM not detected - default Balanced (medium pin)')
    }
    elseif ([double]$signals.ramGb -lt 12) {
        $sizeBand = 'small'
        $reasons.Add("RAM $($signals.ramGb) GB -> Modest (small pin)")
    }
    else {
        $sizeBand = 'medium'
        $reasons.Add("RAM $($signals.ramGb) GB -> Balanced (medium pin)")
    }
    if ($signals.hasUsefulGpu) { $reasons.Add('Useful GPU detected - still recommend Ollama (most likely success)') }
    if ($signals.npuPresent -eq $true) { $reasons.Add('NPU present - hardware signal only; engine stays Ollama') }
    if ($signals.npuPresent -eq $null) { $reasons.Add('NPU detection ambiguous - ask once in Setup if needed') }

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    $enterpriseNote = $null
    if ($settings.enterpriseConfigured) {
        $enterpriseNote = 'Enterprise endpoint configured - available as alternate; not overriding recommend'
        $reasons.Add($enterpriseNote)
    }

    $modelPin = [string]$pins[$sizeBand]
    return [PSCustomObject]@{
        engine           = 'ollama'
        sizeBand         = $sizeBand
        modelPin         = $modelPin
        reasons          = @($reasons)
        signals          = $signals
        enterpriseAlternate = $enterpriseNote
        cursorAdvanced   = $(if ($signals.ideInstalled -or $signals.apiKeyPresent) {
                'Cursor Ask available under Advanced (Needs API key until set)'
            } else { $null })
        summary          = "Recommended: Ollama + $modelPin ($sizeBand)"
    }
}

function Get-MetraAskOllamaExePath {
    <#
    .SYNOPSIS
        Resolves ollama.exe - PATH first, then common install folders (winget same-session PATH lag).
    #>
    [CmdletBinding()]
    param()

    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return [string]$cmd.Source
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe')
        (Join-Path ${env:ProgramFiles} 'Ollama\ollama.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Ollama\ollama.exe')
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }

    # Machine/User PATH may have the folder after winget while this process still has the old PATH.
    foreach ($scope in @('User', 'Machine')) {
        $raw = [Environment]::GetEnvironmentVariable('Path', $scope)
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        foreach ($dir in ($raw -split ';' | Where-Object { $_ })) {
            $exe = Join-Path $dir.Trim() 'ollama.exe'
            if (Test-Path -LiteralPath $exe) { return $exe }
        }
    }
    return $null
}

function Test-MetraAskOllamaInstallerSignature {
    <#
    .SYNOPSIS
        True when a file has a Valid Authenticode signature from O=Ollama Inc.
    .NOTES
        Matches Ollama's own install.ps1 trust rule (organization name with boundary anchors).
        Subject substring "Ollama" alone is not enough.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path
        if ($sig.Status -ne 'Valid') { return $false }
        if (-not $sig.SignerCertificate) { return $false }
        $subject = [string]$sig.SignerCertificate.Subject
        # Anchor O= to avoid "O=Not Ollama Inc." style false positives (same as ollama/scripts/install.ps1).
        return [bool]($subject -match '(^|, )O=Ollama Inc\.(,|$)')
    }
    catch {
        return $false
    }
}

function Merge-MetraAskOllamaConfigObject {
    <#
    .SYNOPSIS
        Build ask.ollama patch object while preserving unknown nested keys (shallow patch safety).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$BaseUrl = 'http://127.0.0.1:11434',
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$SizeBand
    )

    $merged = [ordered]@{
        baseUrl  = $BaseUrl
        model    = $Model
        sizeBand = $SizeBand
    }
    try {
        $path = Get-MetraAskConfigPath -MetraRoot $MetraRoot
        if (Test-Path -LiteralPath $path) {
            $cfg = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
            $ask = Get-MetraProp -Object $cfg -Name 'ask' -Default $null
            $existing = Get-MetraProp -Object $ask -Name 'ollama' -Default $null
            if ($null -ne $existing) {
                foreach ($p in @($existing.PSObject.Properties)) {
                    if ($p.Name -in @('baseUrl', 'model', 'sizeBand')) { continue }
                    $merged[$p.Name] = $p.Value
                }
            }
        }
    }
    catch { }
    return [PSCustomObject]$merged
}

function Set-MetraAskOllamaHiddenStartMarker {
    <#
    .SYNOPSIS
        Drops the Ollama 'upgraded' marker so the app starts hidden (tray/API, no Launch window).
    .DESCRIPTION
        Mirrors the official install script: %LOCALAPPDATA%\Ollama\upgraded tells the desktop app
        to start hidden on first launch and then removes it. Keeps silent installs from popping UI.
    #>
    [CmdletBinding()]
    param()

    try {
        $markerDir = Join-Path $env:LOCALAPPDATA 'Ollama'
        if (-not (Test-Path -LiteralPath $markerDir)) {
            New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
        }
        New-Item -ItemType File -Path (Join-Path $markerDir 'upgraded') -Force | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Install-MetraAskOllamaRuntime {
    <#
    .SYNOPSIS
        Ladder 1a - install Ollama silently (no Launch UI), preferring the signed setup, then winget.
    .DESCRIPTION
        Drops the 'upgraded' hidden-start marker so the desktop app does not pop its Launch window,
        then runs OllamaSetup.exe /VERYSILENT. Falls back to winget with silent overrides, then to
        teaching the download URL. Metra Ask only needs the local API, not the desktop UI.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$WhatIf
    )

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if (Test-MetraAskOpenAICompatHealth -BaseUrl $settings.ollamaBaseUrl -Kind ollama -TimeoutSec 2) {
        return [PSCustomObject]@{ ok = $true; step = 'runtime'; status = 'already_running' }
    }

    $ollamaExe = Get-MetraAskOllamaExePath
    if ($ollamaExe) {
        try {
            if (-not $WhatIf) {
                $serveProc = Start-Process -FilePath $ollamaExe -ArgumentList @('serve') `
                    -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
                $deadline = [datetime]::UtcNow.AddSeconds(30)
                while ([datetime]::UtcNow -lt $deadline) {
                    if (Test-MetraAskOpenAICompatHealth -BaseUrl $settings.ollamaBaseUrl -Kind ollama -TimeoutSec 1) {
                        return [PSCustomObject]@{ ok = $true; step = 'runtime'; status = 'started_existing' }
                    }
                    if ($serveProc -and $serveProc.HasExited) { break }
                    Start-Sleep -Seconds 1
                }
            }
            else {
                return [PSCustomObject]@{ ok = $true; step = 'runtime'; status = 'whatif_start_existing' }
            }
        }
        catch { }
    }

    if ($WhatIf) {
        return [PSCustomObject]@{ ok = $true; step = 'runtime'; status = 'whatif_silent_setup'; package = 'Ollama.Ollama' }
    }

    # Start hidden regardless of which installer path runs.
    $null = Set-MetraAskOllamaHiddenStartMarker

    # Preferred: signed OllamaSetup.exe run fully silent (no Launch UI).
    $installedSilently = $false
    $installStatus = 'silent_setup'
    $installMessage = $null
    $tempInstaller = Join-Path $env:TEMP 'MetraOllamaSetup.exe'
    try {
        Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile $tempInstaller -UseBasicParsing -TimeoutSec 600
        if (-not (Test-MetraAskOllamaInstallerSignature -Path $tempInstaller)) {
            Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
            $installMessage = 'OllamaSetup.exe signature not verified (need Valid + O=Ollama Inc.) - falling back to winget'
        }
        else {
            $setupArgs = @('/VERYSILENT', '/NORESTART', '/SUPPRESSMSGBOXES')
            $sp = Start-Process -FilePath $tempInstaller -ArgumentList $setupArgs -Wait -PassThru
            Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
            if ($sp.ExitCode -eq 0) {
                $installedSilently = $true
            }
            else {
                $installMessage = "OllamaSetup.exe exited $($sp.ExitCode) - falling back to winget"
            }
        }
    }
    catch {
        Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
        $installMessage = "Silent setup download failed ($($_.Exception.Message)) - falling back to winget"
    }

    if (-not $installedSilently) {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            return [PSCustomObject]@{
                ok      = $false
                step    = 'runtime'
                status  = 'winget_missing'
                message = 'Install Ollama from https://ollama.com/download then re-run ask accept'
                url     = 'https://ollama.com/download'
            }
        }
        # --silent plus /VERYSILENT override keeps the Launch UI from appearing.
        $args = @(
            'install', '-e', '--id', 'Ollama.Ollama',
            '--silent',
            '--accept-package-agreements', '--accept-source-agreements',
            '--override', '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES'
        )
        $p = Start-Process -FilePath $winget.Source -ArgumentList $args -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne -1978335189) {
            # -1978335189 often already installed
            return [PSCustomObject]@{
                ok       = $false
                step     = 'runtime'
                status   = 'winget_failed'
                exitCode = $p.ExitCode
                message  = 'winget install Ollama.Ollama failed - try https://ollama.com/download'
                url      = 'https://ollama.com/download'
            }
        }
        $installStatus = 'installed_winget'
    }

    # Make sure the local API is up (start the CLI hidden if the setup did not).
    $deadline2 = [datetime]::UtcNow.AddSeconds(120)
    $serveProc2 = $null
    $startedServe = $false
    while ([datetime]::UtcNow -lt $deadline2) {
        if (Test-MetraAskOpenAICompatHealth -BaseUrl $settings.ollamaBaseUrl -Kind ollama -TimeoutSec 2) {
            return [PSCustomObject]@{ ok = $true; step = 'runtime'; status = $installStatus; note = $installMessage }
        }
        if ($serveProc2 -and $serveProc2.HasExited) {
            $serveProc2 = $null
            $startedServe = $false
        }
        if (-not $startedServe) {
            $exe = Get-MetraAskOllamaExePath
            if ($exe) {
                $serveProc2 = Start-Process -FilePath $exe -ArgumentList @('serve') `
                    -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
                $startedServe = $true
            }
        }
        Start-Sleep -Seconds 2
    }

    return [PSCustomObject]@{
        ok      = $false
        step    = 'runtime'
        status  = 'not_healthy_after_install'
        message = 'Ollama installed but not reachable yet - open Ollama once, then re-run ask accept'
        url     = 'https://ollama.com/download'
    }
}

function Install-MetraAskOllamaModel {
    <#
    .SYNOPSIS
        Ladder 1b - ollama pull recommended model.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$Model,
        [switch]$WhatIf
    )

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if ([string]::IsNullOrWhiteSpace($Model)) { $Model = $settings.ollamaModel }

    if (Test-MetraAskOllamaModelPresent -BaseUrl $settings.ollamaBaseUrl -Model $Model) {
        return [PSCustomObject]@{ ok = $true; step = 'model'; status = 'already_present'; model = $Model }
    }

    $ollamaExe = Get-MetraAskOllamaExePath
    if (-not $ollamaExe) {
        return [PSCustomObject]@{ ok = $false; step = 'model'; status = 'ollama_cli_missing'; model = $Model }
    }

    if ($WhatIf) {
        return [PSCustomObject]@{ ok = $true; step = 'model'; status = 'whatif_pull'; model = $Model }
    }

    $p = Start-Process -FilePath $ollamaExe -ArgumentList @('pull', $Model) -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        return [PSCustomObject]@{ ok = $false; step = 'model'; status = 'pull_failed'; model = $Model; exitCode = $p.ExitCode }
    }

    $ok = Test-MetraAskOllamaModelPresent -BaseUrl $settings.ollamaBaseUrl -Model $Model -TimeoutSec 10
    return [PSCustomObject]@{
        ok     = $ok
        step   = 'model'
        status = $(if ($ok) { 'pulled' } else { 'pull_unverified' })
        model  = $Model
    }
}

function Invoke-MetraAskAcceptRecommended {
    <#
    .SYNOPSIS
        Write Ollama recommend to config, install runtime+model, verify ask health.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$SkipInstall,
        [switch]$RuntimeOnly,
        [switch]$WhatIf,
        [nullable[bool]]$NpuPresent
    )

    $recParams = @{ MetraRoot = $MetraRoot }
    if ($PSBoundParameters.ContainsKey('NpuPresent')) { $recParams['NpuPresent'] = $NpuPresent }
    $rec = Get-MetraAskEngineRecommendation @recParams

    if (-not $WhatIf) {
        # Preserve unknown ask.ollama.* keys (Save-MetraAskConfigPatch is a shallow merge).
        $ollamaObj = Merge-MetraAskOllamaConfigObject -MetraRoot $MetraRoot `
            -BaseUrl 'http://127.0.0.1:11434' -Model $rec.modelPin -SizeBand $rec.sizeBand
        Save-MetraAskConfigPatch -MetraRoot $MetraRoot -Patch @{
            enabled = $true
            engine  = 'ollama'
            ollama  = $ollamaObj
        }
    }

    $steps = [System.Collections.Generic.List[object]]::new()
    $steps.Add([PSCustomObject]@{ step = 'config'; ok = (-not $WhatIf); status = $(if ($WhatIf) { 'whatif' } else { 'written' }); recommendation = $rec.summary })

    if ($SkipInstall) {
        $cap = Get-MetraAskCapability -MetraRoot $MetraRoot
        return [PSCustomObject]@{
            ok             = [bool]$cap.available
            recommendation = $rec
            steps          = @($steps)
            capability     = $cap
            askTest        = $null
        }
    }

    $rt = Install-MetraAskOllamaRuntime -MetraRoot $MetraRoot -WhatIf:$WhatIf
    $steps.Add($rt)
    if (-not $rt.ok -and -not $WhatIf) {
        return [PSCustomObject]@{
            ok             = $false
            recommendation = $rec
            steps          = @($steps)
            capability     = (Get-MetraAskCapability -MetraRoot $MetraRoot)
            askTest        = $null
        }
    }

    if (-not $RuntimeOnly) {
        $md = Install-MetraAskOllamaModel -MetraRoot $MetraRoot -Model $rec.modelPin -WhatIf:$WhatIf
        $steps.Add($md)
        if (-not $md.ok -and -not $WhatIf) {
            return [PSCustomObject]@{
                ok             = $false
                recommendation = $rec
                steps          = @($steps)
                capability     = (Get-MetraAskCapability -MetraRoot $MetraRoot)
                askTest        = $null
            }
        }
    }

    if ($WhatIf) {
        return [PSCustomObject]@{
            ok             = $true
            recommendation = $rec
            steps          = @($steps)
            capability     = $null
            askTest        = $null
        }
    }

    $cap = Get-MetraAskCapability -MetraRoot $MetraRoot
    $askTest = $null
    if ($cap.available -and -not $RuntimeOnly) {
        $askTest = Invoke-MetraAskEngine -Prompt 'Reply with exactly: metra-ask-ok' -Cwd $MetraRoot -Context @{ smoke = $true } -TimeoutSec 120
        $ok = [bool]($askTest.ok -and ($askTest.message -match 'metra-ask-ok|ok'))
        if (-not $ok -and $askTest.ok -and -not [string]::IsNullOrWhiteSpace($askTest.message)) {
            # Soft pass: engine answered something
            $ok = $true
        }
        return [PSCustomObject]@{
            ok             = $ok
            recommendation = $rec
            steps          = @($steps)
            capability     = $cap
            askTest        = $askTest
        }
    }

    return [PSCustomObject]@{
        ok             = [bool]$cap.available
        recommendation = $rec
        steps          = @($steps)
        capability     = $cap
        askTest        = $askTest
    }
}

function Set-MetraAskEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ollama', 'cursor', 'enterprise', 'llamacpp', 'none')]
        [string]$Engine,
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$Model,
        [ValidateSet('small', 'medium', 'large')]
        [string]$SizeBand
    )

    $settings = Get-MetraAskSettings -MetraRoot $MetraRoot
    if ($Engine -eq 'enterprise' -and -not $settings.enterpriseConfigured) {
        throw 'Enterprise engine requires ask.enterprise.baseUrl and ask.enterprise.model in metra.config.json first.'
    }
    if ($Engine -eq 'gpt4all') {
        throw 'GPT4All is not a first-class Ask engine (watch/docs only). Use ollama.'
    }

    $patch = @{
        enabled = ($Engine -ne 'none')
        engine  = $Engine
    }
    if ($Engine -eq 'ollama') {
        $pins = Get-MetraAskModelPinTable
        $band = if ($SizeBand) { $SizeBand } else { $settings.ollamaSizeBand }
        $model = if ($Model) { $Model } else { [string]$pins[$band] }
        $patch['ollama'] = Merge-MetraAskOllamaConfigObject -MetraRoot $MetraRoot `
            -BaseUrl $settings.ollamaBaseUrl -Model $model -SizeBand $band
    }
    if ($Engine -eq 'cursor') {
        # Default pin composer-2.5; auto-* still maps to auto-smart router tiers.
        $resolved = Resolve-MetraAskCursorModelSelection -Model $Model -OptimizeFor 'cost'
        $cursorObj = [ordered]@{
            port  = $settings.cursorPort
            model = $resolved.cursorModel
        }
        if ($resolved.cursorModel -eq 'auto-smart') {
            $cursorObj['optimizeFor'] = $resolved.cursorOptimizeFor
        }
        $patch['cursor'] = [PSCustomObject]$cursorObj
    }
    if ($Engine -eq 'llamacpp') {
        $patch['llamacpp'] = [PSCustomObject]@{
            baseUrl = $settings.llamacppBaseUrl
            model   = $(if ($Model) { $Model } else { $settings.llamacppModel })
        }
    }

    Save-MetraAskConfigPatch -MetraRoot $MetraRoot -Patch $patch
    if ($Engine -eq 'cursor') {
        # Model/optimizeFor are process env at sidecar start - must recycle to apply.
        $null = Stop-MetraAskEngine -MetraRoot $MetraRoot
        $null = Start-MetraAskEngine -MetraRoot $MetraRoot
    }
    return Get-MetraAskCapability -MetraRoot $MetraRoot
}

function Invoke-MetraAskEngineCommand {
    <#
    .SYNOPSIS
        CLI router for ask engine|key|recommend|accept|menu (plus journal via Capture).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [object[]]$ArgsRest = @()
    )

    $shouldProcessParams = @{}
    if ($WhatIfPreference) { $shouldProcessParams['WhatIf'] = $true }
    if ($PSBoundParameters.ContainsKey('Confirm')) { $shouldProcessParams['Confirm'] = $PSBoundParameters['Confirm'] }

    $sub = $Subcommand.Trim().ToLowerInvariant()
    switch -Regex ($sub) {
        '^(engine)$' {
            $action = if ($ArgsRest.Count -gt 0) { [string]$ArgsRest[0] } else { 'show' }
            $action = $action.Trim().ToLowerInvariant()
            switch ($action) {
                'show' {
                    $s = Get-MetraAskSettings
                    $c = Get-MetraAskCapability
                    $inspSel = $null
                    try { $inspSel = Resolve-MetraInspectEngineSelection } catch { $inspSel = $null }
                    $askBlock = [PSCustomObject]@{
                        engine        = $s.engine
                        model         = $s.model
                        available     = $c.available
                        reason        = $c.reason
                        sizeBand      = $s.ollamaSizeBand
                        ideInstalled  = $c.ideInstalled
                        apiKeyPresent = $c.apiKeyPresent
                        nodeReady     = $c.nodeReady
                        sidecarReady  = $c.sidecarReady
                        engineHealthy = $c.engineHealthy
                        runtimeReady  = $c.runtimeReady
                        modelPresent  = $c.modelPresent
                    }
                    $inspBlock = if ($null -ne $inspSel) {
                        [PSCustomObject]@{
                            engine = $inspSel.Engine
                            model  = $inspSel.RequestedModel
                            source = $inspSel.ConfigurationSource
                        }
                    }
                    else { $null }
                    Write-Host 'Ask' -ForegroundColor Cyan
                    Write-Host ("  Engine:  {0}" -f $askBlock.engine)
                    Write-Host ("  Model:   {0}" -f $askBlock.model)
                    if ($null -ne $inspBlock) {
                        Write-Host 'Inspect' -ForegroundColor Cyan
                        Write-Host ("  Engine:  {0}" -f $inspBlock.engine)
                        Write-Host ("  Model:   {0}" -f $inspBlock.model)
                        $srcLabel = switch ([string]$inspBlock.source) {
                            'inspect' { 'inspect configuration' }
                            'ask-fallback' { 'ask fallback' }
                            default { [string]$inspBlock.source }
                        }
                        Write-Host ("  Source:  {0}" -f $srcLabel)
                    }
                    return [PSCustomObject]@{
                        ask     = $askBlock
                        inspect = $inspBlock
                        # Compat: keep flat Ask fields for existing callers
                        engine        = $s.engine
                        model         = $s.model
                        available     = $c.available
                        reason        = $c.reason
                        sizeBand      = $s.ollamaSizeBand
                        ideInstalled  = $c.ideInstalled
                        apiKeyPresent = $c.apiKeyPresent
                        nodeReady     = $c.nodeReady
                        sidecarReady  = $c.sidecarReady
                        engineHealthy = $c.engineHealthy
                        runtimeReady  = $c.runtimeReady
                        modelPresent  = $c.modelPresent
                    }
                }
                'set' {
                    if ($ArgsRest.Count -lt 2) { throw 'Usage: ask engine set <ollama|cursor|enterprise|llamacpp|none> [-Model x] [-SizeBand small|medium|large]' }
                    $eng = [string]$ArgsRest[1]
                    $model = $null
                    $band = $null
                    for ($i = 2; $i -lt $ArgsRest.Count; $i++) {
                        if ($ArgsRest[$i] -eq '-Model' -and ($i + 1) -lt $ArgsRest.Count) { $model = [string]$ArgsRest[++$i]; continue }
                        if ($ArgsRest[$i] -eq '-SizeBand' -and ($i + 1) -lt $ArgsRest.Count) { $band = [string]$ArgsRest[++$i]; continue }
                    }
                    $p = @{ Engine = $eng }
                    if ($model) { $p['Model'] = $model }
                    if ($band) { $p['SizeBand'] = $band }
                    return Set-MetraAskEngine @p
                }
                'restart' { return Restart-MetraAskEngine @shouldProcessParams }
                'recommend' { return Get-MetraAskEngineRecommendation }
                'menu' { return Get-MetraAskEngineMenu }
                default { throw "Unknown ask engine action: $action. Use show|set|restart|recommend|menu." }
            }
        }
        '^(key)$' {
            $action = if ($ArgsRest.Count -gt 0) { [string]$ArgsRest[0] } else { 'status' }
            $action = $action.Trim().ToLowerInvariant()
            switch ($action) {
                'status' {
                    $present = -not [string]::IsNullOrWhiteSpace((Get-MetraCursorApiKey))
                    return [PSCustomObject]@{ apiKeyPresent = $present }
                }
                'set' {
                    $key = $null
                    if ($ArgsRest.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace([string]$ArgsRest[1])) {
                        $key = [string]$ArgsRest[1]
                    }
                    else {
                        $sec = Read-Host -Prompt 'CURSOR_API_KEY' -AsSecureString
                        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
                        try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
                        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
                    }
                    return Set-MetraCursorApiKey -ApiKey $key
                }
                'clear' { return Set-MetraCursorApiKey -ApiKey 'x' -Clear }
                default { throw 'Usage: ask key status|set|clear' }
            }
        }
        '^(recommend)$' { return Get-MetraAskEngineRecommendation }
        '^(accept)$' {
            $runtimeOnly = $ArgsRest -contains '-RuntimeOnly'
            $skip = $ArgsRest -contains '-SkipInstall'
            $whatIf = $ArgsRest -contains '-WhatIf'
            return Invoke-MetraAskAcceptRecommended -RuntimeOnly:$runtimeOnly -SkipInstall:$skip -WhatIf:$whatIf
        }
        '^(menu)$' { return Get-MetraAskEngineMenu }
        default {
            throw "Unknown ask subcommand: $Subcommand. Use engine|key|recommend|accept|menu|log|sessions|get|recall."
        }
    }
}
