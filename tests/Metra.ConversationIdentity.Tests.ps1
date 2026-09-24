# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.ConversationIdentity.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Conversation Identity Stack' {
    It 'manifest order is frozen and allowlist-only' {
        InModuleScope Metra {
            $ids = @(Get-MetraConversationIdentityManifest | ForEach-Object { $_.Id })
            $ids | Should -Be @('partner', 'persona', 'overlay', 'occ', 'humor', 'teaching', 'vision', 'narrative')
            $addons = @(Get-MetraConversationIdentityManifest | Where-Object { $_.AllowlistedAddon })
            $addons.Id | Should -Be @('humor', 'teaching')
        }
    }

    It 'sources walk manifest only - never discovers unknown metra-*.local.mdc' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'metra-id'
            $rules = Join-Path $root '.cursor\rules'
            New-Item -ItemType Directory -Path $rules -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'engines\vision-ask') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $rules 'metra-persona.mdc') -Value "persona body" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $rules 'metra-experimental.local.mdc') -Value "SHOULD NOT LOAD" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $root 'engines\vision-ask\system.md') -Value "vision brief" -Encoding utf8

            $prompt = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture Company
            $prompt.Text | Should -Not -Match 'SHOULD NOT LOAD'
            $prompt.Text | Should -Match 'persona body'
            $prompt.Text | Should -Match 'vision brief'
        }
    }

    It 'Company activates humor when file present; DeskStrict does not' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'metra-humor'
            $rules = Join-Path $root '.cursor\rules'
            New-Item -ItemType Directory -Path $rules -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'engines\vision-ask') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $rules 'metra-humor.local.mdc') -Value @"
---
alwaysApply: true
---
humor pack MARKER
"@ -Encoding utf8
            Set-Content -LiteralPath (Join-Path $root 'engines\vision-ask\system.md') -Value "vision" -Encoding utf8

            $co = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture Company
            $co.HumorActive | Should -BeTrue
            $co.PacksIncluded | Should -Contain 'humor'
            $co.Text | Should -Match 'humor pack MARKER'
            $co.Text | Should -Not -Match 'alwaysApply'

            $ds = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture DeskStrict
            $ds.HumorActive | Should -BeFalse
            $ds.PacksIncluded | Should -Not -Contain 'humor'
            ($ds.PacksOmitted | Where-Object { $_.Id -eq 'humor' }).Reason | Should -Be 'posture_gate'
        }
    }

    It 'teaching on Vision Company when installed; Desk needs teachingWanted; DeskStrict never' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'metra-teach'
            $rules = Join-Path $root '.cursor\rules'
            New-Item -ItemType Directory -Path $rules -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'engines\vision-ask') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $rules 'metra-teaching-gentle.local.mdc') -Value "teaching MARKER" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $root 'engines\vision-ask\system.md') -Value "vision" -Encoding utf8

            $co = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture Company
            $co.TeachingActive | Should -BeTrue
            $co.PacksIncluded | Should -Contain 'teaching'

            $deskNo = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture Desk
            $deskNo.TeachingActive | Should -BeFalse

            $deskYes = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture Desk -TeachingWanted
            $deskYes.TeachingActive | Should -BeTrue

            $ds = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture DeskStrict
            $ds.TeachingActive | Should -BeFalse
        }
    }

    It 'identityHash is stable for same inputs and flips when content changes' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'metra-hash'
            $rules = Join-Path $root '.cursor\rules'
            New-Item -ItemType Directory -Path $rules -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'engines\vision-ask') -Force | Out-Null
            $persona = Join-Path $rules 'metra-persona.mdc'
            Set-Content -LiteralPath $persona -Value "persona A" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $root 'engines\vision-ask\system.md') -Value "vision" -Encoding utf8

            $a1 = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture Company
            $a2 = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture Company
            $a1.IdentityHash | Should -Be $a2.IdentityHash
            $a1.IdentityHash | Should -Match '^[0-9a-f]{16}$'

            Set-Content -LiteralPath $persona -Value "persona B" -Encoding utf8
            $b = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture Company
            $b.IdentityHash | Should -Not -Be $a1.IdentityHash
        }
    }

    It 'budget truncates P3 before P0 and sets IdentityTruncated' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'metra-budget'
            $rules = Join-Path $root '.cursor\rules'
            New-Item -ItemType Directory -Path $rules -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'engines\vision-ask') -Force | Out-Null
            $big = 'X' * 4000
            Set-Content -LiteralPath (Join-Path $rules 'metra-humor.local.mdc') -Value "HUMOR-$big" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $root 'engines\vision-ask\system.md') -Value "VISION-CORE" -Encoding utf8

            $p = Get-MetraConversationIdentityPrompt -MetraRoot $root -Posture Company -BudgetBytes 2500
            $p.IdentityTruncated | Should -BeTrue
            $p.Text | Should -Match 'VISION-CORE'
            ($p.PacksOmitted | Where-Object { $_.Id -eq 'humor' -and $_.Reason -eq 'budget' }) | Should -Not -BeNullOrEmpty
        }
    }

    It 'Get-MetraVisionAskSystemPrompt returns loader object and does not invent teaching' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'metra-vision-sys'
            New-Item -ItemType Directory -Path (Join-Path $root 'engines\vision-ask') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'engines\vision-ask\system.md') -Value "vision only" -Encoding utf8

            $sys = Get-MetraVisionAskSystemPrompt -MetraRoot $root -Posture DeskStrict
            $sys.TeachingActive | Should -BeFalse
            $sys.HumorActive | Should -BeFalse
            $sys.Text | Should -Match 'vision only'
        }
    }

    It 'Vision answered envelope includes diagnostics and posture-derived mood' {
        InModuleScope Metra {
            $out = New-MetraVisionAskAnsweredResponse `
                -Text 'hello' `
                -Source 'ops-vision' `
                -Mode 'vision' `
                -Intent 'relational' `
                -Handler 'vision-engine' `
                -AskLaneUsed:$false `
                -EngineInvoked:$true `
                -Diagnostics ([ordered]@{ identityHash = 'abcd'; packsIncluded = @('humor'); teachingActive = $false; humorActive = $true }) `
                -PresentationMood (Get-MetraVisionAskPresentationMood -Posture Company)
            $out.response.text | Should -Be 'hello'
            $out.message | Should -Be 'hello'
            $out.voice.display | Should -Be 'hello'
            $out.diagnostics.humorActive | Should -BeTrue
            $out.presentation.mood | Should -Be 'company'
        }
    }

    It 'dispatch: Vision contract vs desk-legacy' {
        InModuleScope Metra {
            $legacy = Resolve-MetraAskHttpDispatch -Body ([pscustomobject]@{ prompt = 'hi'; client = 'ops-web' })
            $legacy.path | Should -Be 'desk-legacy'

            $phone = Resolve-MetraAskHttpDispatch -Body ([pscustomobject]@{ prompt = 'hi'; client = 'ops-ios'; clientHint = 'phone' })
            $phone.path | Should -Be 'vision'

            $vision = Resolve-MetraAskHttpDispatch -Body ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'hi'
                })
            $vision.path | Should -Be 'vision'
        }
    }

    It 'handler uses identity Text and askLaneUsed stays false' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'metra-handler'
            $rules = Join-Path $root '.cursor\rules'
            New-Item -ItemType Directory -Path $rules -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'engines\vision-ask') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $rules 'metra-humor.local.mdc') -Value "humor MARKER for engine" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $root 'engines\vision-ask\system.md') -Value "vision brief" -Encoding utf8

            $captured = [hashtable]@{ Prompt = ''; Identity = ''; Session = '' }
            $invoker = {
                param($Prompt, $Root, $SessionId, $IdentityPrefix)
                $captured.Prompt = [string]$Prompt
                $captured.Identity = [string]$IdentityPrefix
                $captured.Session = [string]$SessionId
                return @{ ok = $true; message = 'engine reply' }
            }.GetNewClosure()

            $req = [pscustomobject]@{
                contractVersion = '1'
                surface         = 'ios'
                mode            = 'vision'
                intent          = 'relational'
                message         = 'Whatcha doin?'
                conversationId  = 't1'
                capabilities    = [pscustomobject]@{ durableWritesAllowed = $false; localAssistAvailable = $false }
                context         = [pscustomobject]@{ teachingWanted = $false }
            }
            $out = Invoke-MetraVisionAskHandler -Request $req -MetraRoot $root -DeviceId 'phone-stub-1' -EngineInvoker $invoker -SkipTelemetry
            $out.status | Should -Be 'answered'
            $out.routing.askLaneUsed | Should -BeFalse
            $out.response.text | Should -Be 'engine reply'
            $captured.Identity | Should -Match 'humor MARKER'
            $captured.Prompt | Should -Not -Match 'humor MARKER'
            $captured.Prompt | Should -Match 'Whatcha doin'
            $captured.Session | Should -Be 'vision:phone-stub-1'
            $out.diagnostics.humorActive | Should -BeTrue
            $out.presentation.mood | Should -Be 'company'
        }
    }
}

Describe 'iOS Vision contract notes' {
    It 'documents client error mapping expectations (manual / Swift)' {
        # OpsAskClient always posts Vision contract. teachingWanted hardcoded false.
        # write_not_allowed / route_boundary_violation map to visible AskClientError cases.
        $true | Should -BeTrue
    }
}
