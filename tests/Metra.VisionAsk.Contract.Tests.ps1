# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.VisionAsk.Contract.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Vision Ask contract models' {
    It 'exposes contract version 1 and known error codes' {
        InModuleScope Metra {
            Get-MetraVisionAskContractVersion | Should -Be '1'
            $codes = @(Get-MetraVisionAskErrorCodes)
            $codes | Should -Contain 'invalid_contract'
            $codes | Should -Contain 'vision_unavailable'
            $codes | Should -Contain 'desk_requires_connectivity'
            $codes | Should -Contain 'write_not_allowed'
            $codes | Should -Contain 'route_boundary_violation'
            $codes | Should -Contain 'engine_failure'
        }
    }

    It 'accepts valid surface/mode/intent combinations' {
        InModuleScope Metra {
            @(
                @{ surface = 'ios'; mode = 'vision'; intent = 'relational'; path = 'vision' }
                @{ surface = 'ios'; mode = 'bounded'; intent = 'desk'; path = 'desk' }
                @{ surface = 'ios'; mode = 'bounded'; intent = 'capture'; path = 'capture' }
                @{ surface = 'desk'; mode = 'bounded'; intent = 'desk'; path = 'desk' }
                @{ surface = 'desk'; mode = 'bounded'; intent = 'capture'; path = 'capture' }
            ) | ForEach-Object {
                $r = Test-MetraVisionAskFieldCombination -Surface $_.surface -Mode $_.mode -Intent $_.intent
                $r.ok | Should -BeTrue
                $r.path | Should -Be $_.path
            }
        }
    }

    It 'rejects invalid combinations without silent normalize' {
        InModuleScope Metra {
            $bad = Test-MetraVisionAskFieldCombination -Surface 'ios' -Mode 'vision' -Intent 'desk'
            $bad.ok | Should -BeFalse
            $bad.error | Should -Be 'invalid_contract'

            $req = ConvertTo-MetraVisionAskRequest -Body ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'capture'
                    message         = 'hi'
                })
            $v = Test-MetraVisionAskRequest -Request $req
            $v.ok | Should -BeFalse
            $v.error | Should -Be 'invalid_contract'
        }
    }

    It 'rejects unsupported contract version' {
        InModuleScope Metra {
            $req = ConvertTo-MetraVisionAskRequest -Body ([pscustomobject]@{
                    contractVersion = '99'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'hi'
                })
            $v = Test-MetraVisionAskRequest -Request $req
            $v.ok | Should -BeFalse
            $v.error | Should -Be 'unsupported_contract_version'
        }
    }

    It 'normalizes prompt into message even when contractVersion exists' {
        InModuleScope Metra {
            $raw = [pscustomobject]@{
                contractVersion = '1'
                mode            = 'vision'
                prompt          = 'hello'
            }
            $req = ConvertTo-MetraVisionAskRequest -Body $raw
            $req.message | Should -Be 'hello'
            $req.surface | Should -Be 'ios'
            $req.intent | Should -Be 'relational'
            $v = Test-MetraVisionAskRequest -Request $req -RequireVisionPath
            $v.ok | Should -BeTrue

            # Handler must still normalize when contractVersion is already on the object
            $invoker = {
                param($Prompt, $Root)
                [pscustomobject]@{ ok = $true; message = 'relational reply'; error = '' }
            }
            $out = Invoke-MetraVisionAskHandler -Request $raw -EngineInvoker $invoker -SkipTelemetry
            $out.status | Should -Be 'answered'
            $out.source | Should -Be 'ops-vision'
            $out.routing.askLaneUsed | Should -BeFalse
        }
    }

    It 'rejects Vision with durableWritesAllowed' {
        InModuleScope Metra {
            $req = ConvertTo-MetraVisionAskRequest -Body ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'hi'
                    capabilities    = @{ durableWritesAllowed = $true }
                })
            $v = Test-MetraVisionAskRequest -Request $req
            $v.ok | Should -BeFalse
            $v.error | Should -Be 'write_not_allowed'
        }
    }

    It 'ops-vision answered response forbids askLaneUsed or missing engine' {
        InModuleScope Metra {
            {
                New-MetraVisionAskAnsweredResponse `
                    -Text 'x' -Source 'ops-vision' -Mode 'vision' -Intent 'relational' `
                    -Handler 'vision-engine' -AskLaneUsed:$true -EngineInvoked:$true
            } | Should -Throw '*route_boundary_violation*'

            {
                New-MetraVisionAskAnsweredResponse `
                    -Text 'x' -Source 'ops-vision' -Mode 'vision' -Intent 'relational' `
                    -Handler 'vision-engine' -AskLaneUsed:$false -EngineInvoked:$false
            } | Should -Throw '*route_boundary_violation*'
        }
    }

    It 'offline desk fail-closed provenance never claims Ops success' {
        InModuleScope Metra {
            $r = New-MetraVisionAskOfflineDeskResponse
            $r.status | Should -Be 'unavailable'
            $r.source | Should -Be 'client'
            $r.reason | Should -Be 'desk_requires_connectivity'
            $r.grounding.opsReached | Should -BeFalse
            $r.grounding.portfolioGrounded | Should -BeFalse
            $r.routing.askLaneUsed | Should -BeFalse
            $r.writes.attempted | Should -BeFalse
        }
    }

    It 'local-assist provenance never claims Ops or portfolio grounding' {
        InModuleScope Metra {
            $r = New-MetraVisionAskLocalAssistProvenance -Text 'holding locally'
            $r.status | Should -Be 'answered'
            $r.source | Should -Be 'local-assist'
            $r.grounding.opsReached | Should -BeFalse
            $r.grounding.portfolioGrounded | Should -BeFalse
            $r.routing.askLaneUsed | Should -BeFalse
            $r.routing.engineInvoked | Should -BeFalse
            $r.writes.committed | Should -BeFalse
        }
    }
}

Describe 'Vision Ask HTTP dispatch' {
    It 'legacy /api/ask body without contract stays desk-legacy' {
        InModuleScope Metra {
            $d = Resolve-MetraAskHttpDispatch -Body ([pscustomobject]@{ prompt = 'hello desk' })
            $d.path | Should -Be 'desk-legacy'
        }
    }

    It 'vision contract dispatches to vision' {
        InModuleScope Metra {
            $d = Resolve-MetraAskHttpDispatch -Body ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'hey'
                })
            $d.path | Should -Be 'vision'
            $d.error | Should -BeNullOrEmpty
        }
    }

    It 'mode without contractVersion is rejected' {
        InModuleScope Metra {
            $d = Resolve-MetraAskHttpDispatch -Body ([pscustomobject]@{
                    mode    = 'vision'
                    message = 'hey'
                })
            $d.path | Should -Be 'reject'
            $d.error | Should -Be 'invalid_contract'
        }
    }
}

Describe 'Vision Ask handler seam' {
    It 'invokes engine with Vision prompt and never sets askLaneUsed' {
        InModuleScope Metra {
            $seen = @{ prompt = ''; root = '' }
            $invoker = {
                param($Prompt, $Root)
                $seen.prompt = [string]$Prompt
                $seen.root = [string]$Root
                [pscustomobject]@{ ok = $true; message = 'relational reply'; error = '' }
            }.GetNewClosure()

            $req = ConvertTo-MetraVisionAskRequest -Body ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'How are you?'
                    conversationId  = 'c1'
                    turnId          = 't1'
                })
            $out = Invoke-MetraVisionAskHandler -Request $req -EngineInvoker $invoker -SkipTelemetry
            $out.status | Should -Be 'answered'
            $out.source | Should -Be 'ops-vision'
            $out.routing.askLaneUsed | Should -BeFalse
            $out.routing.captureSuggested | Should -BeFalse
            $out.routing.engineInvoked | Should -BeTrue
            $out.writes.attempted | Should -BeFalse
            $out.grounding.portfolioGrounded | Should -BeFalse
            $seen.prompt | Should -Match 'User turn:'
            $seen.prompt | Should -Match 'How are you\?'
        }
    }

    It 'accepts hashtable EngineInvoker results (ok/message), not only PSCustomObject' {
        InModuleScope Metra {
            $invoker = {
                param($Prompt, $Root)
                @{ ok = $true; message = 'hashtable reply'; error = '' }
            }
            $req = ConvertTo-MetraVisionAskRequest -Body ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'hi'
                })
            $out = Invoke-MetraVisionAskHandler -Request $req -EngineInvoker $invoker -SkipTelemetry
            $out.status | Should -Be 'answered'
            $out.source | Should -Be 'ops-vision'
            $out.response.text | Should -Be 'hashtable reply'
            $out.routing.askLaneUsed | Should -BeFalse
            $out.routing.engineInvoked | Should -BeTrue
        }
    }

    It 'engine failure does not fall back to Desk or Capture' {
        InModuleScope Metra {
            $invoker = { param($Prompt, $Root) [pscustomobject]@{ ok = $false; message = ''; error = 'boom' } }
            $req = ConvertTo-MetraVisionAskRequest -Body ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'hi'
                })
            $out = Invoke-MetraVisionAskHandler -Request $req -EngineInvoker $invoker -SkipTelemetry
            $out.status | Should -Be 'unavailable'
            $out.reason | Should -Be 'engine_failure'
            $out.source | Should -Be 'ops-vision'
            $out.routing.askLaneUsed | Should -BeFalse
            $out.routing.captureSuggested | Should -BeFalse
        }
    }

    It 'emits metra.ask.routed telemetry with askLaneUsed false' {
        InModuleScope Metra {
            $path = Get-MetraAskRoutedTelemetryEventsPath
            $before = if (Test-Path -LiteralPath $path) { @(Get-Content -LiteralPath $path).Count } else { 0 }
            $invoker = { param($Prompt, $Root) [pscustomobject]@{ ok = $true; message = 'ok'; error = '' } }
            $req = ConvertTo-MetraVisionAskRequest -Body ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'telemetry check'
                    turnId          = 'turn-telemetry-1'
                })
            $null = Invoke-MetraVisionAskHandler -Request $req -EngineInvoker $invoker
            Test-Path -LiteralPath $path | Should -BeTrue
            $lines = @(Get-Content -LiteralPath $path)
            $lines.Count | Should -BeGreaterThan $before
            $last = $lines[-1] | ConvertFrom-Json
            $last.event | Should -Be 'metra.ask.routed'
            $last.askLaneUsed | Should -BeFalse
            $last.engineInvoked | Should -BeTrue
            $last.source | Should -Be 'ops-vision'
            $last.turnId | Should -Be 'turn-telemetry-1'
        }
    }
}

Describe 'Vision Ask boundary isolation' {
    It 'VisionAsk.ps1 source does not call Desk AskLane / DeskAsk / TT assess' {
        InModuleScope Metra {
            $b = Test-MetraVisionAskSourceFileBoundary
            $b.ok | Should -BeTrue -Because ($b.violations -join ', ')
        }
    }

    It 'handler path never touches Resolve-MetraAskLane (mocked throw)' {
        InModuleScope Metra {
            Mock Resolve-MetraAskLane { throw 'boundary: Resolve-MetraAskLane called from Vision' }
            Mock Get-MetraDeskAskResult { throw 'boundary: Get-MetraDeskAskResult called from Vision' }
            Mock New-MetraTicketAssessDraft { throw 'boundary: New-MetraTicketAssessDraft called from Vision' }

            $invoker = { param($Prompt, $Root) [pscustomobject]@{ ok = $true; message = 'isolated'; error = '' } }
            $req = ConvertTo-MetraVisionAskRequest -Body ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'boundary probe'
                })
            $out = Invoke-MetraVisionAskHandler -Request $req -EngineInvoker $invoker -SkipTelemetry
            $out.status | Should -Be 'answered'
            $out.routing.askLaneUsed | Should -BeFalse
            Should -Invoke Resolve-MetraAskLane -Times 0 -Exactly
            Should -Invoke Get-MetraDeskAskResult -Times 0 -Exactly
            Should -Invoke New-MetraTicketAssessDraft -Times 0 -Exactly
        }
    }

    It 'social Vision phrasing does not suggest Capture' {
        InModuleScope Metra {
            $invoker = { param($Prompt, $Root) [pscustomobject]@{ ok = $true; message = 'I am here with you.'; error = '' } }
            $req = ConvertTo-MetraVisionAskRequest -Body ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'Good morning - just checking in'
                })
            $out = Invoke-MetraVisionAskHandler -Request $req -EngineInvoker $invoker -SkipTelemetry
            $out.routing.captureSuggested | Should -BeFalse
            $out.routing.askLaneUsed | Should -BeFalse
            # Desk AskLane would Capture this greeting - Vision must not inherit that.
            $deskLane = Resolve-MetraAskLane -Prompt 'Good morning - just checking in' -RouteScore 0 -EvidenceQuality 'none'
            $deskLane.responseObjective | Should -Be 'Capture'
        }
    }
}
