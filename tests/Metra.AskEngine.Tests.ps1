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
            Mock Start-Process { throw 'Start-Process should not run when available' }
            $cap = Start-MetraAskEngine
            $cap.available | Should -BeTrue
        }
    }

    It 'restart stops then starts the sidecar' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings { [PSCustomObject]@{ engine = 'cursor'; cursorPort = 7381 } }
            Mock Stop-MetraAskEngine { $script:AskRestartStopped = $true }
            Mock Test-MetraAskEngineHealth { $false }
            Mock Get-MetraAskEngineRecordedProcessId { return $null }
            Mock Start-MetraAskEngine {
                $script:AskRestartStarted = $true
                return [PSCustomObject]@{ available = $true; engine = 'cursor'; reason = 'ok' }
            }
            $script:AskRestartStopped = $false
            $script:AskRestartStarted = $false
            $cap = Restart-MetraAskEngine -Confirm:$false
            $script:AskRestartStopped | Should -BeTrue
            $script:AskRestartStarted | Should -BeTrue
            $cap.available | Should -BeTrue
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
