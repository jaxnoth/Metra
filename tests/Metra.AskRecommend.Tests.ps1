# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.AskRecommend.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Ask recommend machine signals' {
    It 'RAM detection failure does not invent 16 GB' {
        InModuleScope Metra {
            Mock Get-CimInstance { throw 'cim unavailable' }
            Mock Get-PnpDevice { @() }
            Mock Test-MetraCursorInstall { $false }
            Mock Get-MetraCursorApiKey { '' }
            $s = Get-MetraAskMachineSignals
            $s.ramDetected | Should -BeFalse
            $s.ramGb | Should -BeNullOrEmpty
        }
    }

    It 'NPU override parameter does not change recommended engine' {
        InModuleScope Metra {
            Mock Get-MetraAskMachineSignals {
                [PSCustomObject]@{
                    ramGb         = 16
                    ramDetected   = $true
                    hasUsefulGpu  = $false
                    npuPresent    = $false
                    ideInstalled  = $false
                    apiKeyPresent = $false
                }
            }
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{ enterpriseConfigured = $false }
            }
            $rec = Get-MetraAskEngineRecommendation -NpuPresent $true
            $rec.engine | Should -Be 'ollama'
            ($rec.reasons -join ' ') | Should -Match 'NPU present'
            $rec.engine | Should -Not -Be 'llamacpp'
        }
    }
}

Describe 'Ask recommend sizing' {
    It '8 GB => small' {
        InModuleScope Metra {
            Mock Get-MetraAskMachineSignals {
                [PSCustomObject]@{
                    ramGb = 8; ramDetected = $true; hasUsefulGpu = $false
                    npuPresent = $false; ideInstalled = $false; apiKeyPresent = $false
                }
            }
            Mock Get-MetraAskSettings { [PSCustomObject]@{ enterpriseConfigured = $false } }
            $rec = Get-MetraAskEngineRecommendation
            $rec.sizeBand | Should -Be 'small'
            $rec.modelPin | Should -Be ((Get-MetraAskModelPinTable)['small'])
        }
    }

    It '16 GB => medium' {
        InModuleScope Metra {
            Mock Get-MetraAskMachineSignals {
                [PSCustomObject]@{
                    ramGb = 16; ramDetected = $true; hasUsefulGpu = $false
                    npuPresent = $false; ideInstalled = $false; apiKeyPresent = $false
                }
            }
            Mock Get-MetraAskSettings { [PSCustomObject]@{ enterpriseConfigured = $false } }
            $rec = Get-MetraAskEngineRecommendation
            $rec.sizeBand | Should -Be 'medium'
            $rec.engine | Should -Be 'ollama'
        }
    }

    It 'undetected RAM defaults medium with explicit reason' {
        InModuleScope Metra {
            Mock Get-MetraAskMachineSignals {
                [PSCustomObject]@{
                    ramGb = $null; ramDetected = $false; hasUsefulGpu = $false
                    npuPresent = $null; ideInstalled = $false; apiKeyPresent = $false
                }
            }
            Mock Get-MetraAskSettings { [PSCustomObject]@{ enterpriseConfigured = $false } }
            $rec = Get-MetraAskEngineRecommendation
            $rec.sizeBand | Should -Be 'medium'
            ($rec.reasons -join ' ') | Should -Match 'RAM not detected'
        }
    }

    It 'enterprise configured still recommends ollama' {
        InModuleScope Metra {
            Mock Get-MetraAskMachineSignals {
                [PSCustomObject]@{
                    ramGb = 16; ramDetected = $true; hasUsefulGpu = $true
                    npuPresent = $false; ideInstalled = $false; apiKeyPresent = $false
                }
            }
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    enterpriseConfigured = $true
                    enterpriseBaseUrl    = 'https://llm.example'
                }
            }
            $rec = Get-MetraAskEngineRecommendation
            $rec.engine | Should -Be 'ollama'
            $rec.enterpriseAlternate | Should -Match 'Enterprise'
        }
    }
}

Describe 'Ask recommend installer trust and config merge' {
    It 'rejects invalid Authenticode status' {
        InModuleScope Metra {
            Mock Get-AuthenticodeSignature {
                [PSCustomObject]@{
                    Status            = 'NotSigned'
                    SignerCertificate = $null
                }
            }
            Test-MetraAskOllamaInstallerSignature -Path $PSCommandPath | Should -BeFalse
        }
    }

    It 'rejects Valid signature without O=Ollama Inc. organization' {
        InModuleScope Metra {
            Mock Get-AuthenticodeSignature {
                [PSCustomObject]@{
                    Status = 'Valid'
                    SignerCertificate = [PSCustomObject]@{
                        Subject = 'CN=Some Other Ollama Corporation LLC, O=Some Other Ollama Corporation LLC, C=US'
                    }
                }
            }
            Test-MetraAskOllamaInstallerSignature -Path $PSCommandPath | Should -BeFalse
        }
    }

    It 'accepts Valid signature with O=Ollama Inc.' {
        InModuleScope Metra {
            Mock Get-AuthenticodeSignature {
                [PSCustomObject]@{
                    Status = 'Valid'
                    SignerCertificate = [PSCustomObject]@{
                        Subject = 'CN=Ollama Inc., O=Ollama Inc., L=Toronto, S=Ontario, C=CA'
                    }
                }
            }
            Test-MetraAskOllamaInstallerSignature -Path $PSCommandPath | Should -BeTrue
        }
    }

    It 'Merge-MetraAskOllamaConfigObject preserves unknown nested keys' {
        InModuleScope Metra -Parameters @{ Drive = $TestDrive } {
            $root = Join-Path $Drive 'ask-rec-merge'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            @{
                ask = @{
                    enabled = $true
                    engine  = 'ollama'
                    ollama  = @{
                        baseUrl   = 'http://127.0.0.1:11434'
                        model     = 'old'
                        sizeBand  = 'small'
                        keepAlive = '5m'
                        numGpu    = 1
                    }
                }
            } | ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath (Join-Path $root 'metra.config.json') -Encoding UTF8

            $merged = Merge-MetraAskOllamaConfigObject -MetraRoot $root `
                -BaseUrl 'http://127.0.0.1:11434' -Model 'qwen2.5:7b' -SizeBand 'medium'
            $merged.model | Should -Be 'qwen2.5:7b'
            $merged.sizeBand | Should -Be 'medium'
            $merged.keepAlive | Should -Be '5m'
            $merged.numGpu | Should -Be 1
        }
    }

    It 'existing runtime start stops early when serve process exits' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{ ollamaBaseUrl = 'http://127.0.0.1:11434' }
            }
            Mock Test-MetraAskOpenAICompatHealth { $false }
            Mock Get-MetraAskOllamaExePath { 'C:\fake\ollama.exe' }
            Mock Start-Process {
                [PSCustomObject]@{
                    Id        = 1
                    HasExited = $true
                }
            }
            Mock Set-MetraAskOllamaHiddenStartMarker { $true }
            Mock Invoke-WebRequest { throw 'no download in test' }
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $r = Install-MetraAskOllamaRuntime
            $sw.Stop()
            $sw.Elapsed.TotalSeconds | Should -BeLessThan 15
            $r.ok | Should -BeFalse
            $r.status | Should -Be 'winget_missing'
        }
    }
}
