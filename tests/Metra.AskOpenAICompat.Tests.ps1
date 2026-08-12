# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.AskOpenAICompat.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'OpenAI-compat health status mapping' {
    It '200 => healthy' {
        InModuleScope Metra {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 200 }
            }
            $h = Get-MetraAskOpenAICompatHealthResult -BaseUrl 'https://llm.example' -Kind openai
            $h.ok | Should -BeTrue
            $h.status | Should -Be 'ok'
            Test-MetraAskOpenAICompatHealth -BaseUrl 'https://llm.example' -Kind openai | Should -BeTrue
        }
    }

    It '401 => auth_required not healthy' {
        InModuleScope Metra {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 401 }
            }
            $h = Get-MetraAskOpenAICompatHealthResult -BaseUrl 'https://llm.example' -Kind openai
            $h.ok | Should -BeFalse
            $h.status | Should -Be 'auth_required'
            Test-MetraAskOpenAICompatHealth -BaseUrl 'https://llm.example' -Kind openai | Should -BeFalse
        }
    }

    It '403 => forbidden' {
        InModuleScope Metra {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 403 }
            }
            $h = Get-MetraAskOpenAICompatHealthResult -BaseUrl 'https://llm.example' -Kind openai
            $h.status | Should -Be 'forbidden'
            $h.ok | Should -BeFalse
        }
    }

    It '404 => not_found' {
        InModuleScope Metra {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 404 }
            }
            $h = Get-MetraAskOpenAICompatHealthResult -BaseUrl 'https://llm.example' -Kind openai
            $h.status | Should -Be 'not_found'
        }
    }

    It 'timeout/exception => unreachable' {
        InModuleScope Metra {
            Mock Invoke-WebRequest { throw 'The operation has timed out.' }
            $h = Get-MetraAskOpenAICompatHealthResult -BaseUrl 'https://llm.example' -Kind openai
            $h.status | Should -Be 'unreachable'
            $h.ok | Should -BeFalse
        }
    }

    It 'does not probe base URL root for openai kind' {
        InModuleScope Metra {
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-WebRequest {
                param($Uri)
                $uris.Add([string]$Uri)
                [PSCustomObject]@{ StatusCode = 404 }
            }
            $null = Get-MetraAskOpenAICompatHealthResult -BaseUrl 'https://llm.example' -Kind openai
            ($uris -join ' ') | Should -Match '/v1/models'
            ($uris -join ' ') | Should -Match '/health'
            @($uris | Where-Object { $_ -eq 'https://llm.example' }).Count | Should -Be 0
        }
    }
}

Describe 'OpenAI-compat enterprise capability' {
    It 'configured + health 401 => enterprise_key_missing' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled                 = $true
                    engine                  = 'enterprise'
                    model                   = 'gpt-4o'
                    enterpriseBaseUrl       = 'https://llm.example'
                    enterpriseModel         = 'gpt-4o'
                    enterpriseConfigured    = $true
                    enterpriseRequireApiKey = $false
                    enterpriseApiKeyEnv     = 'METRA_ASK_ENTERPRISE_KEY'
                    cursorPort              = 7381
                    ollamaSizeBand          = 'medium'
                }
            }
            Mock Test-MetraCursorInstall { $false }
            Mock Get-MetraCursorApiKey { '' }
            Mock Get-MetraAskNodePath { '' }
            Mock Get-MetraAskCursorSidecarPath { $null }
            Mock Test-MetraAskCursorSidecarDeps { $false }
            Mock Get-MetraAskEnterpriseApiKey { $null }
            Mock Get-MetraAskOpenAICompatHealthResult {
                [PSCustomObject]@{ ok = $false; status = 'auth_required'; statusCode = 401; url = 'https://llm.example/v1/models' }
            }
            $cap = Get-MetraAskCapability
            $cap.reason | Should -Be 'enterprise_key_missing'
            $cap.available | Should -BeFalse
            $cap.runtimeReady | Should -BeTrue
        }
    }

    It 'configured + health not_found => enterprise_api_missing' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled                 = $true
                    engine                  = 'enterprise'
                    model                   = 'gpt-4o'
                    enterpriseBaseUrl       = 'https://llm.example'
                    enterpriseModel         = 'gpt-4o'
                    enterpriseConfigured    = $true
                    enterpriseRequireApiKey = $false
                    enterpriseApiKeyEnv     = 'METRA_ASK_ENTERPRISE_KEY'
                    cursorPort              = 7381
                    ollamaSizeBand          = 'medium'
                }
            }
            Mock Test-MetraCursorInstall { $false }
            Mock Get-MetraCursorApiKey { '' }
            Mock Get-MetraAskNodePath { '' }
            Mock Get-MetraAskCursorSidecarPath { $null }
            Mock Test-MetraAskCursorSidecarDeps { $false }
            Mock Get-MetraAskEnterpriseApiKey { 'k' }
            Mock Get-MetraAskOpenAICompatHealthResult {
                [PSCustomObject]@{ ok = $false; status = 'not_found'; statusCode = 404; url = 'https://llm.example/v1/models' }
            }
            $cap = Get-MetraAskCapability
            $cap.reason | Should -Be 'enterprise_api_missing'
        }
    }

    It 'configured + health ok => available' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enabled                 = $true
                    engine                  = 'enterprise'
                    model                   = 'gpt-4o'
                    enterpriseBaseUrl       = 'https://llm.example'
                    enterpriseModel         = 'gpt-4o'
                    enterpriseConfigured    = $true
                    enterpriseRequireApiKey = $false
                    enterpriseApiKeyEnv     = 'METRA_ASK_ENTERPRISE_KEY'
                    cursorPort              = 7381
                    ollamaSizeBand          = 'medium'
                }
            }
            Mock Test-MetraCursorInstall { $false }
            Mock Get-MetraCursorApiKey { '' }
            Mock Get-MetraAskNodePath { '' }
            Mock Get-MetraAskCursorSidecarPath { $null }
            Mock Test-MetraAskCursorSidecarDeps { $false }
            Mock Get-MetraAskEnterpriseApiKey { 'k' }
            Mock Get-MetraAskOpenAICompatHealthResult {
                [PSCustomObject]@{ ok = $true; status = 'ok'; statusCode = 200; url = 'https://llm.example/v1/models' }
            }
            $cap = Get-MetraAskCapability
            $cap.available | Should -BeTrue
            $cap.reason | Should -Be 'ok'
        }
    }
}

Describe 'OpenAI-compat completion helpers' {
    It 'context ceiling derives from evidence maxTotalChars * 5' {
        InModuleScope Metra {
            Get-MetraAskOpenAICompatContextJsonMaxChars | Should -Be 12000
        }
    }

    It 'maps enterprise auth exceptions to enterprise_auth_failed' {
        InModuleScope Metra {
            $settings = [PSCustomObject]@{ engine = 'enterprise'; model = 'x' }
            $ex = [System.Exception]::new('Response status code does not indicate success: 401 (Unauthorized).')
            Resolve-MetraAskOpenAICompatErrorCode -Settings $settings -Exception $ex | Should -Be 'enterprise_auth_failed'
        }
    }

    It 'safe error codes keep operator messages without raw URLs' {
        InModuleScope Metra {
            $safe = ConvertTo-MetraAskEngineSafeError -ErrorMessage 'enterprise_request_failed'
            $safe.Code | Should -Be 'enterprise_request_failed'
            $safe.Message | Should -Match 'Enterprise Ask'
            $safe.Message | Should -Not -Match 'https://'
        }
    }

    It 'enterprise system prompt uses project leaf not full CWD' {
        InModuleScope Metra {
            $script:CapturedBody = $null
            Mock Get-MetraAskEnterpriseApiKey { 'k' }
            Mock Invoke-RestMethod {
                param($Body)
                $script:CapturedBody = [string]$Body
                [PSCustomObject]@{
                    model   = 'gpt-4o'
                    choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = 'ok' } })
                }
            }
            Mock Invoke-MetraAskSecretsScrubText {
                param($Text)
                [PSCustomObject]@{
                    Refuse = $false; Matched = $false; Text = $Text; Notice = $null; Kinds = @(); Reason = $null
                }
            }
            $settings = [PSCustomObject]@{
                engine            = 'enterprise'
                enterpriseBaseUrl = 'https://llm.example'
                enterpriseModel   = 'gpt-4o'
                model             = 'gpt-4o'
            }
            $scrub = [PSCustomObject]@{ Matched = $false; Text = 'hi'; Notice = $null; Kinds = @() }
            $null = Invoke-MetraAskOpenAICompatComplete -Settings $settings -Prompt 'hi' `
                -Cwd 'C:\Users\Stephen\Projects\TicketTracker' -Context @{} -PromptScrub $scrub -CtxScrub $scrub
            $script:CapturedBody | Should -Match 'Project: TicketTracker'
            $script:CapturedBody | Should -Not -Match 'C:\\\\Users\\\\Stephen'
        }
    }

    It 'metra-inspect context enables json_object response_format and inspect system prompt' {
        InModuleScope Metra {
            $script:CapturedBody = $null
            Mock Invoke-RestMethod {
                param($Body)
                $script:CapturedBody = [string]$Body
                [PSCustomObject]@{
                    model   = 'qwen2.5:14b'
                    choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '{"findings":[]}' } })
                }
            }
            Mock Invoke-MetraAskSecretsScrubText {
                param($Text)
                [PSCustomObject]@{
                    Refuse = $false; Matched = $false; Text = $Text; Notice = $null; Kinds = @(); Reason = $null
                }
            }
            $settings = [PSCustomObject]@{
                engine        = 'ollama'
                ollamaBaseUrl = 'http://127.0.0.1:11434'
                ollamaModel   = 'qwen2.5:14b'
                model         = 'qwen2.5:14b'
            }
            $scrub = [PSCustomObject]@{ Matched = $false; Text = 'review'; Notice = $null; Kinds = @() }
            $ctx = @{ purpose = 'metra-inspect' }
            $null = Invoke-MetraAskOpenAICompatComplete -Settings $settings -Prompt 'review diff' `
                -Cwd 'C:\Projects\_meta' -Context $ctx -PromptScrub $scrub -CtxScrub $scrub
            $script:CapturedBody | Should -Match '"response_format"'
            $script:CapturedBody | Should -Match 'json_object'
            $script:CapturedBody | Should -Match '"format":"json"'
            $script:CapturedBody | Should -Match 'Metra Inspect'
            $script:CapturedBody | Should -Match 'Never return plan summaries'
            $script:CapturedBody | Should -Not -Match 'Metra Ask'
            $script:CapturedBody | Should -Match '"temperature":0.1'
        }
    }

    It 'retries inspect without response_format or format when endpoint rejects json hints' {
        InModuleScope Metra {
            $script:CallCount = 0
            $script:CapturedBodies = New-Object System.Collections.Generic.List[string]
            Mock Invoke-RestMethod {
                param($Body)
                $script:CapturedBodies.Add([string]$Body)
                $script:CallCount++
                if ($script:CallCount -eq 1) {
                    throw 'unknown field format'
                }
                [PSCustomObject]@{
                    model   = 'qwen2.5:14b'
                    choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '{"findings":[]}' } })
                }
            }
            Mock Invoke-MetraAskSecretsScrubText {
                param($Text)
                [PSCustomObject]@{
                    Refuse = $false; Matched = $false; Text = $Text; Notice = $null; Kinds = @(); Reason = $null
                }
            }
            $settings = [PSCustomObject]@{
                engine        = 'ollama'
                ollamaBaseUrl = 'http://127.0.0.1:11434'
                ollamaModel   = 'qwen2.5:14b'
                model         = 'qwen2.5:14b'
            }
            $scrub = [PSCustomObject]@{ Matched = $false; Text = 'review'; Notice = $null; Kinds = @() }
            $r = Invoke-MetraAskOpenAICompatComplete -Settings $settings -Prompt 'review diff' `
                -Cwd 'C:\Projects\_meta' -Context @{ purpose = 'metra-inspect' } -PromptScrub $scrub -CtxScrub $scrub
            $r.ok | Should -BeTrue
            $script:CallCount | Should -Be 2
            $script:CapturedBodies[0] | Should -Match '"format"'
            $script:CapturedBodies[1] | Should -Not -Match '"format"'
            $script:CapturedBodies[1] | Should -Not -Match 'response_format'
        }
    }

    It 'retries inspect without response_format when endpoint rejects json_object only' {
        InModuleScope Metra {
            $script:CallCount = 0
            Mock Invoke-RestMethod {
                $script:CallCount++
                if ($script:CallCount -eq 1) {
                    throw 'unknown field response_format'
                }
                [PSCustomObject]@{
                    model   = 'qwen2.5:14b'
                    choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '{"findings":[]}' } })
                }
            }
            Mock Invoke-MetraAskSecretsScrubText {
                param($Text)
                [PSCustomObject]@{
                    Refuse = $false; Matched = $false; Text = $Text; Notice = $null; Kinds = @(); Reason = $null
                }
            }
            $settings = [PSCustomObject]@{
                engine        = 'ollama'
                ollamaBaseUrl = 'http://127.0.0.1:11434'
                ollamaModel   = 'qwen2.5:14b'
                model         = 'qwen2.5:14b'
            }
            $scrub = [PSCustomObject]@{ Matched = $false; Text = 'review'; Notice = $null; Kinds = @() }
            $r = Invoke-MetraAskOpenAICompatComplete -Settings $settings -Prompt 'review diff' `
                -Cwd 'C:\Projects\_meta' -Context @{ purpose = 'metra-inspect' } -PromptScrub $scrub -CtxScrub $scrub
            $r.ok | Should -BeTrue
            $script:CallCount | Should -Be 2
        }
    }
}

Describe 'Ollama model name match' {
    It 'exact and latest-equivalent match' {
        InModuleScope Metra {
            Test-MetraAskOllamaModelNameMatch -Want 'qwen2.5:7b' -Have 'qwen2.5:7b' | Should -BeTrue
            Test-MetraAskOllamaModelNameMatch -Want 'qwen2.5:7b' -Have 'qwen2.5:latest' | Should -BeTrue
        }
    }

    It 'size-band mismatch does not match' {
        InModuleScope Metra {
            Test-MetraAskOllamaModelNameMatch -Want 'qwen2.5:7b' -Have 'qwen2.5:1.5b' | Should -BeFalse
            Test-MetraAskOllamaModelNameMatch -Want 'qwen2.5:7b' -Have 'qwen2.5:14b' | Should -BeFalse
        }
    }

    It 'untagged want fuzzy-matches tagged inventory' {
        InModuleScope Metra {
            Test-MetraAskOllamaModelNameMatch -Want 'qwen2.5' -Have 'qwen2.5:7b' | Should -BeTrue
        }
    }

    It 'tagged want accepts untagged inventory of same base' {
        InModuleScope Metra {
            Test-MetraAskOllamaModelNameMatch -Want 'qwen2.5:7b' -Have 'qwen2.5' | Should -BeTrue
        }
    }
}
