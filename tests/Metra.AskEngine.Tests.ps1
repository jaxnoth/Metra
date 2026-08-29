# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.AskEngine.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Ask engine settings' {
    It 'normalizes gpt4all engine to none' {
        InModuleScope Metra -Parameters @{ Drive = $TestDrive } {
            $root = Join-Path $Drive 'ask-gpt4all'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            @{ ask = @{ enabled = $true; engine = 'gpt4all' } } |
                ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $root 'metra.config.json') -Encoding UTF8
            $s = Get-MetraAskSettings -MetraRoot $root
            $s.engine | Should -Be 'none'
        }
    }

    It 'defaults cursor model to composer-2.5 when omitted' {
        InModuleScope Metra -Parameters @{ Drive = $TestDrive } {
            $root = Join-Path $Drive 'ask-cursor-default'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            @{
                ask = @{
                    enabled = $true
                    engine  = 'cursor'
                    cursor  = @{ port = 7381 }
                }
            } | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $root 'metra.config.json') -Encoding UTF8
            $s = Get-MetraAskSettings -MetraRoot $root
            $s.cursorModel | Should -Be 'composer-2.5'
            $s.model | Should -Be 'composer-2.5'
        }
    }

    It 'aliases composer-2.5-fast to composer-2.5' {
        InModuleScope Metra -Parameters @{ Drive = $TestDrive } {
            $root = Join-Path $Drive 'ask-composer-fast'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            @{
                ask = @{
                    enabled = $true
                    engine  = 'cursor'
                    cursor  = @{ model = 'composer-2.5-fast'; port = 7381 }
                }
            } | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $root 'metra.config.json') -Encoding UTF8
            $s = Get-MetraAskSettings -MetraRoot $root
            $s.cursorModel | Should -Be 'composer-2.5'
            $s.model | Should -Be 'composer-2.5'
        }
    }

    It 'normalizes cursor auto-cost to auto-smart/cost' {
        InModuleScope Metra -Parameters @{ Drive = $TestDrive } {
            $root = Join-Path $Drive 'ask-auto-cost'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            @{
                ask = @{
                    enabled = $true
                    engine  = 'cursor'
                    cursor  = @{ model = 'auto-cost'; port = 7381 }
                }
            } | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $root 'metra.config.json') -Encoding UTF8
            $s = Get-MetraAskSettings -MetraRoot $root
            $s.cursorModel | Should -Be 'auto-smart'
            $s.cursorOptimizeFor | Should -Be 'cost'
            $s.model | Should -Be 'auto-smart/cost'
        }
    }

    It 'defaults ollama model to medium pin when model omitted' {
        InModuleScope Metra -Parameters @{ Drive = $TestDrive } {
            $root = Join-Path $Drive 'ask-ollama-pin'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $pins = Get-MetraAskModelPinTable
            @{
                ask = @{
                    enabled = $true
                    engine  = 'ollama'
                    ollama  = @{ sizeBand = 'medium' }
                }
            } | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $root 'metra.config.json') -Encoding UTF8
            $s = Get-MetraAskSettings -MetraRoot $root
            $s.ollamaModel | Should -Be ([string]$pins['medium'])
        }
    }

    It 'enterpriseConfigured requires baseUrl and model' {
        InModuleScope Metra -Parameters @{ Drive = $TestDrive } {
            $root = Join-Path $Drive 'ask-ent'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            @{
                ask = @{
                    enabled    = $true
                    engine     = 'enterprise'
                    enterprise = @{ baseUrl = 'https://llm.example' }
                }
            } | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $root 'metra.config.json') -Encoding UTF8
            $s = Get-MetraAskSettings -MetraRoot $root
            $s.enterpriseConfigured | Should -BeFalse

            @{
                ask = @{
                    enabled    = $true
                    engine     = 'enterprise'
                    enterprise = @{ baseUrl = 'https://llm.example'; model = 'gpt-4o' }
                }
            } | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $root 'metra.config.json') -Encoding UTF8
            $s2 = Get-MetraAskSettings -MetraRoot $root
            $s2.enterpriseConfigured | Should -BeTrue
        }
    }

    It 'Save-MetraAskConfigPatch shallow-merges and preserves nested ask objects' {
        InModuleScope Metra -Parameters @{ Drive = $TestDrive } {
            $root = Join-Path $Drive 'ask-patch'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            @{
                ask = @{
                    enabled = $true
                    engine  = 'ollama'
                    ollama  = @{ baseUrl = 'http://127.0.0.1:11434'; model = 'keep-me' }
                }
            } | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $root 'metra.config.json') -Encoding UTF8

            Save-MetraAskConfigPatch -MetraRoot $root -Patch @{ engine = 'cursor' }
            $cfg = Get-Content -Raw -LiteralPath (Join-Path $root 'metra.config.json') | ConvertFrom-Json
            $cfg.ask.engine | Should -Be 'cursor'
            $cfg.ask.ollama.model | Should -Be 'keep-me'
        }
    }
}

Describe 'Ask engine capability' {
    It 'disabled engine returns selected=false available=false' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled = $false
                    engine  = 'ollama'
                    model   = 'x'
                    cursorPort = 7381
                    ollamaSizeBand = 'medium'
                    enterpriseConfigured = $false
                }
            }
            $cap = Get-MetraAskCapability
            $cap.selected | Should -BeFalse
            $cap.available | Should -BeFalse
            $cap.reason | Should -Be 'disabled'
        }
    }

    It 'cursor missing node returns node_missing' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled = $true
                    engine  = 'cursor'
                    model   = 'auto-smart/cost'
                    cursorPort = 7381
                    ollamaSizeBand = 'medium'
                    enterpriseConfigured = $false
                }
            }
            Mock Test-MetraCursorInstall { $true }
            Mock Get-MetraCursorApiKey { 'fake' }
            Mock Get-MetraAskNodePath { '' }
            Mock Get-MetraAskCursorSidecarPath { 'C:\fake\server.mjs' }
            Mock Test-MetraAskCursorSidecarDeps { $true }
            $cap = Get-MetraAskCapability
            $cap.selected | Should -BeTrue
            $cap.available | Should -BeFalse
            $cap.reason | Should -Be 'node_missing'
        }
    }

    It 'cursor missing key returns key_missing' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled = $true
                    engine  = 'cursor'
                    model   = 'auto-smart/cost'
                    cursorPort = 7381
                    ollamaSizeBand = 'medium'
                    enterpriseConfigured = $false
                }
            }
            Mock Test-MetraCursorInstall { $true }
            Mock Get-MetraCursorApiKey { '' }
            Mock Get-MetraAskNodePath { 'C:\fake\node.exe' }
            Mock Get-MetraAskCursorSidecarPath { 'C:\fake\server.mjs' }
            Mock Test-MetraAskCursorSidecarDeps { $true }
            $cap = Get-MetraAskCapability
            $cap.reason | Should -Be 'key_missing'
            $cap.available | Should -BeFalse
        }
    }

    It 'ollama runtime missing returns runtime_missing' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled = $true
                    engine  = 'ollama'
                    model   = 'qwen2.5:7b'
                    ollamaBaseUrl = 'http://127.0.0.1:11434'
                    ollamaModel = 'qwen2.5:7b'
                    cursorPort = 7381
                    ollamaSizeBand = 'medium'
                    enterpriseConfigured = $false
                }
            }
            Mock Test-MetraCursorInstall { $false }
            Mock Get-MetraCursorApiKey { '' }
            Mock Get-MetraAskNodePath { '' }
            Mock Get-MetraAskCursorSidecarPath { $null }
            Mock Test-MetraAskCursorSidecarDeps { $false }
            Mock Test-MetraAskOpenAICompatHealth { $false }
            $cap = Get-MetraAskCapability
            $cap.reason | Should -Be 'runtime_missing'
        }
    }

    It 'ollama model missing returns model_missing' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled = $true
                    engine  = 'ollama'
                    model   = 'missing:tag'
                    ollamaBaseUrl = 'http://127.0.0.1:11434'
                    ollamaModel = 'missing:tag'
                    cursorPort = 7381
                    ollamaSizeBand = 'medium'
                    enterpriseConfigured = $false
                }
            }
            Mock Test-MetraCursorInstall { $false }
            Mock Get-MetraCursorApiKey { '' }
            Mock Get-MetraAskNodePath { '' }
            Mock Get-MetraAskCursorSidecarPath { $null }
            Mock Test-MetraAskCursorSidecarDeps { $false }
            Mock Test-MetraAskOpenAICompatHealth { $true }
            Mock Test-MetraAskOllamaModelPresent { $false }
            $cap = Get-MetraAskCapability
            $cap.reason | Should -Be 'model_missing'
        }
    }

    It 'enterprise missing base/model returns enterprise_unconfigured' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled = $true
                    engine  = 'enterprise'
                    model   = ''
                    cursorPort = 7381
                    ollamaSizeBand = 'medium'
                    enterpriseConfigured = $false
                    enterpriseRequireApiKey = $false
                    enterpriseApiKeyEnv = 'METRA_ASK_ENTERPRISE_KEY'
                }
            }
            Mock Test-MetraCursorInstall { $false }
            Mock Get-MetraCursorApiKey { '' }
            Mock Get-MetraAskNodePath { '' }
            Mock Get-MetraAskCursorSidecarPath { $null }
            Mock Test-MetraAskCursorSidecarDeps { $false }
            $cap = Get-MetraAskCapability
            $cap.reason | Should -Be 'enterprise_unconfigured'
        }
    }

    It 'enterprise requireApiKey without key returns enterprise_key_missing' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled = $true
                    engine  = 'enterprise'
                    model   = 'gpt-4o'
                    enterpriseBaseUrl = 'https://llm.example'
                    enterpriseModel = 'gpt-4o'
                    cursorPort = 7381
                    ollamaSizeBand = 'medium'
                    enterpriseConfigured = $true
                    enterpriseRequireApiKey = $true
                    enterpriseApiKeyEnv = 'METRA_ASK_ENTERPRISE_KEY_TEST'
                }
            }
            Mock Test-MetraCursorInstall { $false }
            Mock Get-MetraCursorApiKey { '' }
            Mock Get-MetraAskNodePath { '' }
            Mock Get-MetraAskCursorSidecarPath { $null }
            Mock Test-MetraAskCursorSidecarDeps { $false }
            Mock Get-MetraAskEnterpriseApiKey { $null }
            $cap = Get-MetraAskCapability
            $cap.reason | Should -Be 'enterprise_key_missing'
            $cap.enterpriseKeyPresent | Should -BeFalse
            $cap.available | Should -BeFalse
        }
    }
}

Describe 'Ask engine invoke' {
    It 'prompt secret refusal never calls engine' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{ enabled = $true; engine = 'ollama'; model = 'x' }
            }
            Mock Invoke-MetraAskSecretsScrubText {
                [PSCustomObject]@{
                    Refuse = $true; Reason = 'pem_private_key'; Notice = 'blocked'
                    Matched = $true; Text = ''; Kinds = @('pem')
                }
            }
            Mock Invoke-MetraAskOpenAICompatComplete { throw 'should not call openai compat' }
            Mock Invoke-RestMethod { throw 'should not call rest' }
            $r = Invoke-MetraAskEngine -Prompt 'secret' -Cwd (Get-MetraRoot)
            $r.secretsRefuse | Should -BeTrue
            $r.error | Should -Be 'secrets_refuse'
        }
    }

    It 'image + non-cursor returns image_vision_unsupported' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{ enabled = $true; engine = 'ollama'; model = 'qwen' }
            }
            Mock Invoke-MetraAskSecretsScrubText {
                [PSCustomObject]@{
                    Refuse = $false; Reason = $null; Notice = $null
                    Matched = $false; Text = 'hi'; Kinds = @()
                }
            }
            Mock Invoke-MetraAskSecretsScrubObject {
                [PSCustomObject]@{
                    Refuse = $false; Reason = $null; Notice = $null
                    Matched = $false; Value = @{}; Kinds = @()
                }
            }
            Mock Invoke-MetraAskOpenAICompatComplete { throw 'should not call openai compat' }
            $img = [PSCustomObject]@{ id = 'img1'; fileName = 'a.png'; path = 'C:\q\a.png' }
            $r = Invoke-MetraAskEngine -Prompt 'hi' -Cwd (Get-MetraRoot) -Images @($img)
            $r.error | Should -Be 'image_vision_unsupported'
            $r.status | Should -Be 'degraded'
        }
    }

    It 'unsupported engine returns safe error result' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{ enabled = $true; engine = 'weird'; model = '' }
            }
            Mock Invoke-MetraAskSecretsScrubText {
                [PSCustomObject]@{
                    Refuse = $false; Reason = $null; Notice = $null
                    Matched = $false; Text = 'hi'; Kinds = @()
                }
            }
            Mock Invoke-MetraAskSecretsScrubObject {
                [PSCustomObject]@{
                    Refuse = $false; Reason = $null; Notice = $null
                    Matched = $false; Value = @{}; Kinds = @()
                }
            }
            $r = Invoke-MetraAskEngine -Prompt 'hi' -Cwd (Get-MetraRoot)
            $r.error | Should -Be 'engine_unsupported:weird'
            $r.ok | Should -BeFalse
        }
    }

    It 'raw exception messages become engine_request_failed' {
        InModuleScope Metra {
            $safe = ConvertTo-MetraAskEngineSafeError -ErrorMessage 'The remote server returned an error: (401) Unauthorized at https://internal-gw.corp/v1'
            $safe.Code | Should -Be 'engine_request_failed'
            $safe.Message | Should -Be 'Ask engine request failed.'
        }
    }
}

Describe 'Ask engine lifecycle and routing' {
    It 'stop ignores missing pid file' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{ cursorPort = 17999; engine = 'cursor' }
            }
            Mock Get-MetraAskEnginePidFile { Join-Path $env:TEMP ('metra-ask-missing-pid-' + [guid]::NewGuid().ToString('N') + '.pid') }
            { Stop-MetraAskEngine -Port 17999 } | Should -Not -Throw
        }
    }

    It 'stop does not kill current process from stale pid file' {
        $pidPath = Join-Path $TestDrive ('metra-ask-self-pid.pid')
        Set-Content -LiteralPath $pidPath -Value $PID -Encoding ASCII
        InModuleScope Metra -Parameters @{ PidPath = $pidPath } {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{ cursorPort = 17998; engine = 'cursor' }
            }
            Mock Get-MetraAskEnginePidFile { $PidPath }
            { Stop-MetraAskEngine -Port 17998 } | Should -Not -Throw
            (Test-Path -LiteralPath $PidPath) | Should -BeFalse
        }
    }

    It 'Test-MetraAskCursorSidecarProcessId rejects own PID' {
        InModuleScope Metra {
            Test-MetraAskCursorSidecarProcessId -ProcessId $PID | Should -BeFalse
        }
    }

    It 'Test-MetraAskCursorSidecarProcessId fails closed when CommandLine is unavailable' {
        InModuleScope Metra {
            Mock Get-Process { [PSCustomObject]@{ ProcessName = 'node' } }
            Mock Get-CimInstance { return $null }
            Test-MetraAskCursorSidecarProcessId -ProcessId 4242 | Should -BeFalse
        }
    }

    It 'Stop-MetraAskEngine -WhatIf does not stop orphan port listeners or remove PID file' {
        InModuleScope Metra {
            $pidFile = Join-Path $env:TEMP ("ask-engine-" + [guid]::NewGuid().ToString('n') + '.pid')
            Set-Content -LiteralPath $pidFile -Value '4242' -Encoding ASCII
            Mock Get-MetraAskEnginePidFile { $pidFile }
            Mock Get-MetraAskSettings { [PSCustomObject]@{ engine = 'cursor'; cursorPort = 7381 } }
            Mock Get-MetraAskCursorSidecarListenerProcessIds { return @(4242) }
            Mock Test-MetraAskCursorSidecarProcessId { param($ProcessId) $ProcessId -eq 4242 }
            Mock Stop-Process { throw 'Stop-Process should not run under WhatIf' }
            try {
                { Stop-MetraAskEngine -IncludePortListeners -WhatIf } | Should -Not -Throw
                Should -Invoke Stop-Process -Times 0
                Test-Path -LiteralPath $pidFile | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Get-MetraAskRouteCwd matches project names case-insensitively' {
        $projPath = Join-Path $TestDrive 'TicketTrackerProj'
        New-Item -ItemType Directory -Path $projPath -Force | Out-Null
        InModuleScope Metra -Parameters @{ ProjPath = $projPath } {
            Mock Get-MetraProjects {
                @([PSCustomObject]@{ Name = 'TicketTracker'; Path = $ProjPath })
            }
            $cwd = Get-MetraAskRouteCwd -Where 'tickettracker' -MetraRoot 'C:\Projects\_meta'
            $cwd | Should -Be $ProjPath
        }
    }

    It 'cursor selected + healthy start does not Start-Process' {
        InModuleScope Metra {
            Mock Get-MetraAskCapability {
                [PSCustomObject]@{
                    selected = $true
                    available = $true
                    engine = 'cursor'
                    reason = 'ok'
                }
            }
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    engine = 'cursor'; cursorPort = 7381
                    cursorModel = 'auto-smart'; cursorOptimizeFor = 'cost'
                }
            }
            Mock Invoke-MetraAskCursorSidecarEnsure { $true }
            Mock Start-Process { throw 'Start-Process should not run when Ensure is mocked' }
            $cap = Start-MetraAskEngine
            $cap.available | Should -BeTrue
            Should -Invoke Invoke-MetraAskCursorSidecarEnsure -Times 1
            Should -Invoke Start-Process -Times 0
        }
    }

    It 'Initialize-MetraAskEngineSpawnLogs rotates non-empty stderr to .1' {
        $drive = $TestDrive
        InModuleScope Metra -Parameters @{ Drive = $drive } {
            $dir = Join-Path $Drive 'ask-log-rotate'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $err = Join-Path $dir 'ask-engine-17381.err.log'
            $out = Join-Path $dir 'ask-engine-17381.out.log'
            Set-Content -LiteralPath $err -Value "EADDRINUSE prior" -Encoding utf8
            # Truly empty stdout (Set-Content '' still writes a newline / BOM on Windows).
            [System.IO.File]::WriteAllBytes($out, [byte[]]@())
            Mock Get-MetraAskEngineLogPath {
                param($Port, $Stream)
                if ($Stream -eq 'stdout') { return $out }
                return $err
            }
            Initialize-MetraAskEngineSpawnLogs -Port 17381
            (Test-Path -LiteralPath "$err.1") | Should -BeTrue
            (Get-Content -LiteralPath "$err.1" -Raw) | Should -Match 'EADDRINUSE'
            (Test-Path -LiteralPath $err) | Should -BeFalse
            (Test-Path -LiteralPath "$out.1") | Should -BeFalse
            (Test-Path -LiteralPath $out) | Should -BeTrue
        }
    }

    It 'Sync-MetraAskEnginePidFile writes the live listener PID' {
        $pidFile = Join-Path $TestDrive 'ask-engine-sync.pid'
        Set-Content -LiteralPath $pidFile -Value '111' -Encoding ASCII
        InModuleScope Metra -Parameters @{ PidFile = $pidFile } {
            Mock Get-MetraAskEnginePidFile { $PidFile }
            Mock Get-MetraAskCursorSidecarListenerProcessIds { return @(26164) }
            $chosen = Sync-MetraAskEnginePidFile -Port 7381
            $chosen | Should -Be 26164
            (Get-Content -LiteralPath $PidFile -Raw).Trim() | Should -Be '26164'
        }
    }

    It 'Clear-MetraAskEngineStalePidFile removes dead recorded PID' {
        $pidFile = Join-Path $TestDrive 'ask-engine-stale.pid'
        Set-Content -LiteralPath $pidFile -Value '55496' -Encoding ASCII
        InModuleScope Metra -Parameters @{ PidFile = $pidFile } {
            Mock Get-MetraAskEnginePidFile { $PidFile }
            Mock Get-Process { $null }
            Clear-MetraAskEngineStalePidFile -Port 7381
            (Test-Path -LiteralPath $PidFile) | Should -BeFalse
        }
    }

    It 'Ensure adopts healthy port without Start-Process and syncs PID' {
        InModuleScope Metra {
            Mock Test-MetraAskCursorPortHealth { $true }
            Mock Sync-MetraAskEnginePidFile { return 26164 }
            Mock Start-Process { throw 'Start-Process should not run when port is healthy' }
            $ok = Invoke-MetraAskCursorSidecarEnsure -CursorPort 7381
            $ok | Should -BeTrue
            Should -Invoke Sync-MetraAskEnginePidFile -Times 1
            Should -Invoke Start-Process -Times 0
        }
    }

    It 'Ensure does not write PID before health when spawn stays unhealthy' {
        $pidFile = Join-Path $TestDrive 'ask-engine-no-premature-pid.pid'
        $drive = $TestDrive
        if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force }
        InModuleScope Metra -Parameters @{ PidFile = $pidFile; Drive = $drive } {
            Mock Test-MetraAskCursorPortHealth { $false }
            Mock Wait-MetraAskCursorPortHealth { $false }
            Mock Get-MetraAskCursorSidecarListenerProcessIds { return @() }
            Mock Get-MetraAskNodePath { 'C:\fake\node.exe' }
            Mock Get-MetraAskCursorSidecarPath { 'C:\fake\server.mjs' }
            Mock Get-MetraCursorApiKey { 'test-key' }
            Mock Test-MetraAskCursorSidecarDeps { $true }
            Mock Clear-MetraAskEngineStalePidFile { }
            Mock Initialize-MetraAskEngineSpawnLogs { }
            Mock Get-MetraAskEngineLogPath {
                param($Port, $Stream)
                Join-Path $Drive ("spawn-$Stream.log")
            }
            Mock Get-MetraAskEnginePidFile { $PidFile }
            Mock Write-MetraAskEnginePidFile { throw 'PID must not be written before health' }
            Mock Sync-MetraAskEnginePidFile { return $null }
            Mock Start-Process {
                [PSCustomObject]@{ Id = 99901; HasExited = $true }
            }
            Mock Test-MetraAskCursorSidecarProcessId { $false }
            $ok = Invoke-MetraAskCursorSidecarEnsure -CursorPort 17382
            $ok | Should -BeFalse
            Should -Invoke Write-MetraAskEnginePidFile -Times 0
            (Test-Path -LiteralPath $PidFile) | Should -BeFalse
        }
    }

    It 'Ensure adopts when spawn loses the port race to an existing Metra listener' {
        $drive = $TestDrive
        InModuleScope Metra -Parameters @{ Drive = $drive } {
            Mock Test-MetraAskCursorPortHealth { $false }
            Mock Wait-MetraAskCursorPortHealth {
                param($Port, $TimeoutSec)
                # First wait (after spawn) fails; second wait (adopt) succeeds.
                if ($TimeoutSec -le 5) { return $true }
                return $false
            }
            $script:ListenerPhase = 0
            Mock Get-MetraAskCursorSidecarListenerProcessIds {
                $script:ListenerPhase++
                if ($script:ListenerPhase -le 1) { return @() }
                return @(26164)
            }
            Mock Get-MetraAskNodePath { 'C:\fake\node.exe' }
            Mock Get-MetraAskCursorSidecarPath { 'C:\fake\server.mjs' }
            Mock Get-MetraCursorApiKey { 'test-key' }
            Mock Test-MetraAskCursorSidecarDeps { $true }
            Mock Clear-MetraAskEngineStalePidFile { }
            Mock Initialize-MetraAskEngineSpawnLogs { }
            Mock Get-MetraAskEngineLogPath { Join-Path $Drive 'race.log' }
            Mock Sync-MetraAskEnginePidFile { return 26164 }
            Mock Start-Process {
                [PSCustomObject]@{ Id = 55496; HasExited = $true }
            }
            Mock Test-MetraAskCursorSidecarProcessId { param($ProcessId) $ProcessId -eq 26164 }
            Mock Stop-Process { throw 'Stop-Process should not run for exited loser' }
            $ok = Invoke-MetraAskCursorSidecarEnsure -CursorPort 17383
            $ok | Should -BeTrue
            Should -Invoke Sync-MetraAskEnginePidFile -Times 1
        }
    }

    It 'restart stops then starts the sidecar' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings { [PSCustomObject]@{ engine = 'cursor'; cursorPort = 7381 } }
            Mock Stop-MetraAskEngine { param($IncludePortListeners) $script:AskRestartStopped = $true; $script:AskRestartIncludePort = [bool]$IncludePortListeners }
            Mock Test-MetraAskEngineHealth { $false }
            Mock Get-MetraAskEngineRecordedProcessId { return $null }
            Mock Start-MetraAskEngine {
                $script:AskRestartStarted = $true
                return [PSCustomObject]@{ available = $true; engine = 'cursor'; reason = 'ok' }
            }
            $script:AskRestartStopped = $false
            $script:AskRestartStarted = $false
            $script:AskRestartIncludePort = $false
            $cap = Restart-MetraAskEngine -Confirm:$false
            $script:AskRestartStopped | Should -BeTrue
            $script:AskRestartIncludePort | Should -BeTrue
            $script:AskRestartStarted | Should -BeTrue
            $cap.available | Should -BeTrue
        }
    }

    It 'Stop-MetraAskEngine can stop orphan port listeners when PID file is missing' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings { [PSCustomObject]@{ engine = 'cursor'; cursorPort = 7381 } }
            Mock Get-MetraAskCursorSidecarListenerProcessIds { return @(4242) }
            Mock Test-MetraAskCursorSidecarProcessId { param($ProcessId) $ProcessId -eq 4242 }
            Mock Stop-Process { param($Id) $script:AskStoppedPid = $Id }
            $script:AskStoppedPid = $null
            Stop-MetraAskEngine -IncludePortListeners
            $script:AskStoppedPid | Should -Be 4242
        }
    }

    It 'restart is a no-op when Ask engine is not cursor' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings { [PSCustomObject]@{ engine = 'ollama'; cursorPort = 7381 } }
            Mock Get-MetraAskCapability { [PSCustomObject]@{ available = $true; engine = 'ollama'; reason = 'ok' } }
            Mock Stop-MetraAskEngine { throw 'Stop-MetraAskEngine should not run for non-cursor restart' }
            Mock Start-MetraAskEngine { throw 'Start-MetraAskEngine should not run for non-cursor restart' }
            $cap = Restart-MetraAskEngine -Confirm:$false
            $cap.engine | Should -Be 'ollama'
            Should -Invoke Stop-MetraAskEngine -Times 0
            Should -Invoke Start-MetraAskEngine -Times 0
        }
    }

    It 'ask engine restart routes through Invoke-MetraAskEngineCommand' {
        InModuleScope Metra {
            Mock Restart-MetraAskEngine {
                return [PSCustomObject]@{ available = $true; engine = 'cursor'; reason = 'ok' }
            }
            $r = Invoke-MetraAskEngineCommand -Subcommand 'engine' -ArgsRest @('restart')
            $r.available | Should -BeTrue
            Should -Invoke Restart-MetraAskEngine -Times 1
        }
    }

    It 'ask engine restart -WhatIf forwards ShouldProcess without stopping the sidecar' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled = $true; engine = 'cursor'; model = 'composer-2.5'
                    cursorPort = 7381; cursorModel = 'composer-2.5'; cursorOptimizeFor = 'cost'
                    ollamaBaseUrl = 'http://127.0.0.1:11434'; ollamaModel = 'qwen'; ollamaSizeBand = 'medium'
                    enterpriseBaseUrl = ''; enterpriseModel = ''; enterpriseApiKeyEnv = 'X'; enterpriseRequireApiKey = $false
                    enterpriseConfigured = $false; llamacppBaseUrl = 'http://127.0.0.1:8080'; llamacppModel = 'x'
                    metraRoot = (Get-MetraRoot)
                }
            }
            Mock Stop-MetraAskEngine { throw 'Stop-MetraAskEngine should not run under WhatIf' }
            Mock Start-MetraAskEngine { throw 'Start-MetraAskEngine should not run under WhatIf' }
            Mock Get-MetraAskCapability { [PSCustomObject]@{ available = $true; reason = 'ok' } }
            $r = Invoke-MetraAskEngineCommand -Subcommand 'engine' -ArgsRest @('restart') -WhatIf
            $r.reason | Should -Be 'restart_cancelled'
            $r.available | Should -BeFalse
            Should -Invoke Stop-MetraAskEngine -Times 0
            Should -Invoke Start-MetraAskEngine -Times 0
        }
    }
}

Describe 'Ask cursor response conversion' {
    It 'maps sidecar status error to ok false' {
        InModuleScope Metra {
            $settings = [PSCustomObject]@{ engine = 'cursor'; model = 'composer-2.5' }
            $response = [PSCustomObject]@{
                status  = 'error'
                message = 'The Ask engine run failed. Try again, or use Classify for routing only.'
                engine  = 'cursor'
                model   = 'composer-2.5'
                sessionId = 's1'
            }
            $promptScrub = [PSCustomObject]@{ Matched = $false; Text = 'test'; Notice = $null; Kinds = @() }
            $ctxScrub = [PSCustomObject]@{ Matched = $false; Notice = $null; Kinds = @() }
            $r = Convert-MetraAskCursorResponse -Response $response -Settings $settings -SessionId 's1' -PromptScrub $promptScrub -CtxScrub $ctxScrub
            $r.ok | Should -BeFalse
            $r.status | Should -Be 'error'
            $r.error | Should -Be 'engine_request_failed'
            $r.message | Should -Match 'Ask engine run failed'
        }
    }

    It 'maps sidecar status finished to ok true' {
        InModuleScope Metra {
            $settings = [PSCustomObject]@{ engine = 'cursor'; model = 'composer-2.5' }
            $response = [PSCustomObject]@{
                status  = 'finished'
                message = '{"findings":[]}'
                engine  = 'cursor'
                model   = 'composer-2.5'
                sessionId = 's1'
            }
            $promptScrub = [PSCustomObject]@{ Matched = $false; Text = 'test'; Notice = $null; Kinds = @(); Refuse = $false }
            $ctxScrub = [PSCustomObject]@{ Matched = $false; Notice = $null; Kinds = @(); Refuse = $false }
            Mock Invoke-MetraAskSecretsScrubText { param($Text) [PSCustomObject]@{ Text = $Text; Matched = $false; Notice = $null; Kinds = @(); Refuse = $false; Reason = $null } }
            $r = Convert-MetraAskCursorResponse -Response $response -Settings $settings -SessionId 's1' -PromptScrub $promptScrub -CtxScrub $ctxScrub
            $r.ok | Should -BeTrue
            $r.status | Should -Be 'finished'
        }
    }

    It 'refuses when output scrub detects private-key material on finished status' {
        InModuleScope Metra {
            $settings = [PSCustomObject]@{ engine = 'cursor'; model = 'composer-2.5' }
            $response = [PSCustomObject]@{
                status    = 'finished'
                message   = '-----BEGIN PRIVATE KEY-----'
                engine    = 'cursor'
                model     = 'composer-2.5'
                sessionId = 's1'
            }
            $promptScrub = [PSCustomObject]@{ Matched = $false; Text = 'test'; Notice = $null; Kinds = @(); Refuse = $false }
            $ctxScrub = [PSCustomObject]@{ Matched = $false; Notice = $null; Kinds = @(); Refuse = $false }
            Mock Invoke-MetraAskSecretsScrubText {
                param($Text)
                if ($Text -match 'PRIVATE KEY') {
                    return [PSCustomObject]@{
                        Text   = ''
                        Matched = $true
                        Notice = 'blocked output key'
                        Kinds  = @('pem_private_key')
                        Refuse = $true
                        Reason = 'pem_private_key'
                    }
                }
                return [PSCustomObject]@{ Text = $Text; Matched = $false; Notice = $null; Kinds = @(); Refuse = $false; Reason = $null }
            }
            $r = Convert-MetraAskCursorResponse -Response $response -Settings $settings -SessionId 's1' -PromptScrub $promptScrub -CtxScrub $ctxScrub
            $r.ok | Should -BeFalse
            $r.status | Should -Be 'refused'
            $r.error | Should -Be 'secrets_refuse'
        }
    }

    It 'maps missing sidecar status to ok false' {
        InModuleScope Metra {
            $settings = [PSCustomObject]@{ engine = 'cursor'; model = 'composer-2.5' }
            $response = [PSCustomObject]@{
                message = 'partial payload'
                engine  = 'cursor'
                model   = 'composer-2.5'
                sessionId = 's1'
            }
            $promptScrub = [PSCustomObject]@{ Matched = $false; Text = 'test'; Notice = $null; Kinds = @() }
            $ctxScrub = [PSCustomObject]@{ Matched = $false; Notice = $null; Kinds = @() }
            $r = Convert-MetraAskCursorResponse -Response $response -Settings $settings -SessionId 's1' -PromptScrub $promptScrub -CtxScrub $ctxScrub
            $r.ok | Should -BeFalse
            $r.status | Should -Be 'unknown'
            $r.error | Should -Be 'engine_request_failed'
        }
    }
}

Describe 'Ask engine selection overrides' {
It 'Engine Model overrides do not mutate Get-MetraAskSettings and pass ollama model' {
        InModuleScope Metra {
            $base = [PSCustomObject]@{
                enabled = $true; engine = 'ollama'; model = 'qwen2.5:7b'
                cursorPort = 7381; cursorModel = 'composer-2.5'; cursorOptimizeFor = 'cost'
                ollamaBaseUrl = 'http://127.0.0.1:11434'; ollamaModel = 'qwen2.5:7b'; ollamaSizeBand = 'medium'
                enterpriseBaseUrl = ''; enterpriseModel = ''; enterpriseApiKeyEnv = 'X'; enterpriseRequireApiKey = $false
                enterpriseConfigured = $false; llamacppBaseUrl = 'http://127.0.0.1:8080'; llamacppModel = 'x'
                metraRoot = (Get-MetraRoot)
            }
            Mock Get-MetraAskSettings { $base }
            Mock Invoke-MetraAskSecretsScrubText {
                [PSCustomObject]@{ Refuse = $false; Reason = $null; Notice = $null; Matched = $false; Text = 'hi'; Kinds = @() }
            }
            Mock Invoke-MetraAskSecretsScrubObject {
                [PSCustomObject]@{ Refuse = $false; Reason = $null; Notice = $null; Matched = $false; Value = @{}; Kinds = @() }
            }
            $captured = $null
            Mock Invoke-MetraAskOpenAICompatComplete {
                param($Settings)
                $script:captured = $Settings
                [PSCustomObject]@{ ok = $true; message = '{}'; engine = $Settings.engine; model = $Settings.model; status = 'finished' }
            }
            $r = Invoke-MetraAskEngine -Prompt 'hi' -Cwd (Get-MetraRoot) -Engine ollama -Model 'inspect-pin:7b'
            $r.ok | Should -BeTrue
            $script:captured.engine | Should -Be 'ollama'
            $script:captured.model | Should -Be 'inspect-pin:7b'
            $base.engine | Should -Be 'ollama'
            $base.ollamaModel | Should -Be 'qwen2.5:7b'
        }
    }

    It 'omitted Engine Model uses ask settings unchanged' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled = $true; engine = 'ollama'; model = 'qwen2.5:7b'
                    cursorPort = 7381; cursorModel = 'composer-2.5'; cursorOptimizeFor = 'cost'
                    ollamaBaseUrl = 'http://127.0.0.1:11434'; ollamaModel = 'qwen2.5:7b'; ollamaSizeBand = 'medium'
                    enterpriseBaseUrl = ''; enterpriseModel = ''; enterpriseApiKeyEnv = 'X'; enterpriseRequireApiKey = $false
                    enterpriseConfigured = $false; llamacppBaseUrl = 'http://127.0.0.1:8080'; llamacppModel = 'x'
                    metraRoot = (Get-MetraRoot)
                }
            }
            Mock Invoke-MetraAskSecretsScrubText {
                [PSCustomObject]@{ Refuse = $false; Reason = $null; Notice = $null; Matched = $false; Text = 'hi'; Kinds = @() }
            }
            Mock Invoke-MetraAskSecretsScrubObject {
                [PSCustomObject]@{ Refuse = $false; Reason = $null; Notice = $null; Matched = $false; Value = @{}; Kinds = @() }
            }
            $captured = $null
            Mock Invoke-MetraAskOpenAICompatComplete {
                param($Settings)
                $script:captured = $Settings
                [PSCustomObject]@{ ok = $true; message = 'ok'; engine = $Settings.engine; model = $Settings.model; status = 'finished' }
            }
            $null = Invoke-MetraAskEngine -Prompt 'hi' -Cwd (Get-MetraRoot)
            $script:captured.engine | Should -Be 'ollama'
            $script:captured.model | Should -Be 'qwen2.5:7b'
        }
    }
}
