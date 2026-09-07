# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.PartnerIdentity.Tests.ps1"

$script:MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force

Describe 'Partner Identity Contract' {
    It 'exposes schema, surfaces, postures, and AppliesTo / DoesNotApplyTo' {
        $c = Get-MetraPartnerIdentityContract
        $c.SchemaVersion | Should -Be 1
        $c.Name | Should -Be 'Metra'
        $c.Surfaces | Should -Contain 'Vision'
        $c.Postures | Should -Contain 'Company'
        $c.AppliesTo | Should -Contain 'Vision'
        $c.DoesNotApplyTo | Should -Contain 'Inspect reviewer job'
        $c.SurfaceDefaults.Vision | Should -Be 'Company'
    }

    It 'Vision defaults to Company when unset; preserves SourcePosture null vs explicit' {
        $unset = Resolve-MetraPartnerPosture -Surface Vision
        $unset.ResolvedPosture | Should -Be 'Company'
        $unset.SourcePosture | Should -BeNullOrEmpty
        $unset.SourceKind | Should -Be 'unset'
        $unset.WasDefault | Should -BeTrue

        $explicit = Resolve-MetraPartnerPosture -Surface Vision -Posture Company
        $explicit.ResolvedPosture | Should -Be 'Company'
        $explicit.SourcePosture | Should -Be 'Company'
        $explicit.SourceKind | Should -Be 'explicit'
        $explicit.WasDefault | Should -BeFalse

        $desk = Resolve-MetraPartnerPosture -Surface Vision -Posture Desk
        $desk.ResolvedPosture | Should -Be 'Desk'
        $desk.SourceKind | Should -Be 'explicit'

        $inc = Resolve-MetraPartnerPosture -Surface OpsPresence -IncidentActive
        $inc.ResolvedPosture | Should -Be 'DeskStrict'
        $inc.SourceKind | Should -Be 'incident'
    }

    It 'preamble is posture-driven and identity-stable across surfaces' {
        $ask = New-MetraPartnerIdentityPreamble -Surface Ask -Posture Desk
        $vision = New-MetraPartnerIdentityPreamble -Surface Vision -Posture Company -PortfolioShaped
        $ask | Should -Match 'portfolio operations partner'
        $vision | Should -Match 'portfolio operations partner'
        $vision | Should -Match 'Posture=Company'
        $vision | Should -Match 'portfolio-shaped'
        $deskVision = New-MetraPartnerIdentityPreamble -Surface Vision -Posture Desk
        $deskVision | Should -Match 'Posture=Desk'
        $deskVision | Should -Not -Match 'warmer relational'
    }

    It 'self-description is identical across Who-are-you surfaces' {
        $a = Get-MetraPartnerIdentitySelfDescription
        $ask = New-MetraPartnerCheckInResponse -Surface Ask -WhoAreYou
        $vis = New-MetraPartnerCheckInResponse -Surface Vision -WhoAreYou
        $ask.Display | Should -Be $a
        $vis.Display | Should -Be $a
        $ask.IdentityName | Should -Be 'Metra'
    }
}

Describe 'Portfolio-shaped turn' {
    It 'rejects Vision/Company/vocative alone' {
        $intent = [PSCustomObject]@{ IntentClass = 'check_in' }
        Test-MetraAskPortfolioShapedTurn -Prompt 'Hello Metra' -Intent $intent | Should -BeFalse
        Test-MetraAskPortfolioShapedTurn -Prompt 'How are you?' -Intent $intent | Should -BeFalse
    }

    It 'rejects bare project/work/job/team alone (prefer false negative)' {
        $work = [PSCustomObject]@{ IntentClass = 'work' }
        Test-MetraAskPortfolioShapedTurn -Prompt 'project' -Intent $work | Should -BeFalse
        Test-MetraAskPortfolioShapedTurn -Prompt 'work' -Intent $work | Should -BeFalse
        Test-MetraAskPortfolioShapedTurn -Prompt 'job' -Intent $work | Should -BeFalse
        Test-MetraAskPortfolioShapedTurn -Prompt 'team' -Intent $work | Should -BeFalse
        Test-MetraAskPortfolioVocabulary -Prompt 'project' | Should -BeFalse
    }

    It 'accepts registry / ops vocabulary and ticket patterns' {
        $work = [PSCustomObject]@{ IntentClass = 'work' }
        Test-MetraAskPortfolioShapedTurn -Prompt 'What is wrong with Colleague WAGC?' -Intent $work | Should -BeTrue
        Test-MetraAskPortfolioShapedTurn -Prompt 'Status on ticket 123456' -Intent $work | Should -BeTrue
        Test-MetraAskPortfolioShapedTurn -Prompt 'What projects are active?' -Intent $work | Should -BeTrue
    }

    It 'accepts authority and component status intents' {
        Test-MetraAskPortfolioShapedTurn -Prompt 'x' -Intent ([PSCustomObject]@{ IntentClass = 'authority_write' }) | Should -BeTrue
        Test-MetraAskPortfolioShapedTurn -Prompt 'x' -Intent ([PSCustomObject]@{ IntentClass = 'component_status' }) | Should -BeTrue
    }

    It 'ambiguous relational + light portfolio hint can shape via continuity' {
        $cont = New-MetraContinuityEvidence -Continuity ([PSCustomObject]@{
                recentTurnCount = 2
                factualSupport  = $true
            }) -BoundProject 'Colleague'
        $intent = [PSCustomObject]@{ IntentClass = 'work' }
        Test-MetraAskPortfolioShapedTurn `
            -Prompt 'thinking about that Colleague thing later' `
            -Intent $intent `
            -ContinuityEvidence $cont | Should -BeTrue
    }
}

Describe 'Check-in and continuity' {
    It 'check-in is acknowledgement without fake recall' {
        $none = New-MetraContinuityEvidence -Continuity $null
        $none.ClaimScope | Should -Be 'none'
        $r = New-MetraPartnerCheckInResponse -Surface Ask -ContinuityEvidence $none `
            -Observation 'I remember where we left off'
        $r.Display | Should -Be "I'm here."
        $r.Observation | Should -Be ''
        Test-MetraContinuityClaimAllowed -ContinuityEvidence $none -ClaimKind 'unsupported_i_remember' | Should -BeFalse
    }

    It 'vocative strip leaves work text for routing' {
        Remove-MetraAskVocativeAddress -Prompt 'Hello Metra, Colleague stuck session' |
            Should -Match 'Colleague stuck session'
        Remove-MetraAskVocativeAddress -Prompt 'Hello Metra' | Should -Match 'Hello Metra'
    }
}

Describe 'Ops presence lines' {
    It 'empty snapshot is ack only - no all clear' {
        $p = Get-MetraPartnerPresenceLines -AttentionWaiting 0
        $p.Acknowledgement | Should -Be "I'm here."
        $p.HasObservation | Should -BeFalse
        $p.Display | Should -Not -Match '(?i)all clear|Clear for now'
    }

    It 'one Attention item yields ack plus observation' {
        $p = Get-MetraPartnerPresenceLines -AttentionWaiting 1
        $p.HasObservation | Should -BeTrue
        $p.Display | Should -Match 'One item ready for review'
        $p.Display | Should -Match "I'm here"
    }
}

Describe 'Authority and sink' {
    It 'authority gate requires confirm for execute, not advise' {
        $g = Test-MetraPartnerIdentityAuthorityGate -Intent ([PSCustomObject]@{ IntentClass = 'authority_write' })
        $g.RequiresConfirm | Should -BeTrue
        $g.Message | Should -Match 'OperatorConfirm'

        $close = Test-MetraPartnerIdentityAuthorityGate -Prompt 'Close ticket 123456 in iSupport'
        $close.RequiresConfirm | Should -BeTrue

        $advise = Test-MetraPartnerIdentityAuthorityGate -Prompt 'What do you recommend for ticket 123456?'
        $advise.RequiresConfirm | Should -BeFalse

        $route = Test-MetraPartnerIdentityAuthorityGate -Prompt 'Recommend a route for this Colleague stuck session'
        $route.RequiresConfirm | Should -BeFalse
    }

    It 'neutral artifact strips partner voice and maps advise phrasing' {
        ConvertTo-MetraPartnerNeutralArtifact -Text "I'm Metra, the portfolio operations partner. Ticket closed." |
            Should -Be 'Ticket closed.'
        ConvertTo-MetraPartnerNeutralArtifact -Text "I'm here. Noted." | Should -Be 'Noted.'
        ConvertTo-MetraPartnerNeutralArtifact -Text 'I think the issue is the listener is stuck.' |
            Should -Be 'Assessment: the listener is stuck.'
        ConvertTo-MetraPartnerNeutralArtifact -Text 'I recommend clearing the WAGC lock after confirm.' |
            Should -Be 'Recommendation: clearing the WAGC lock after confirm.'
        ConvertTo-MetraPartnerNeutralArtifact -Text 'I would recommend a DeskStrict posture.' |
            Should -Be 'Recommendation: a DeskStrict posture.'
    }
}

Describe 'Ask vs Vision identity and evidence parity fixtures' {
    It 'Who are you? yields same Metra on Ask check-in and Vision handler' {
        InModuleScope Metra {
            $self = Get-MetraPartnerIdentitySelfDescription
            $ask = New-MetraPartnerCheckInResponse -Surface Ask -WhoAreYou
            $ask.Display | Should -Be $self

            $invoker = {
                param($Prompt, $Root)
                [pscustomobject]@{ ok = $true; message = 'should not be used for who-are-you'; error = '' }
            }
            $out = Invoke-MetraVisionAskHandler -Request ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'Who are you?'
                }) -EngineInvoker $invoker -SkipTelemetry
            $out.status | Should -Be 'answered'
            $out.response.text | Should -Be $self
            $out.grounding.portfolioGrounded | Should -BeFalse
            $out.routing.engineInvoked | Should -BeFalse
            $out.routing.partnerIdentityShortCircuit | Should -BeTrue
        }
    }

    It 'Vision Close ticket requires OperatorConfirm without inventing write' {
        InModuleScope Metra {
            $out = Invoke-MetraVisionAskHandler -Request ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'Close ticket 123456 in iSupport'
                }) -EngineInvoker {
                param($Prompt, $Root)
                [pscustomobject]@{ ok = $true; message = 'closed'; error = '' }
            } -SkipTelemetry
            $out.status | Should -Be 'answered'
            $out.response.text | Should -Match 'OperatorConfirm'
            $out.response.text | Should -Not -Match '(?i)^closed$'
            $out.routing.partnerIdentityShortCircuit | Should -BeTrue
        }
    }

    It 'Vision portfolio-shaped turn may set portfolioGrounded when engine answers' {
        InModuleScope Metra {
            $out = Invoke-MetraVisionAskHandler -Request ([pscustomobject]@{
                    contractVersion = '1'
                    surface         = 'ios'
                    mode            = 'vision'
                    intent          = 'relational'
                    message         = 'What projects are active on the desk?'
                }) -EngineInvoker {
                param($Prompt, $Root)
                if ($Prompt -notmatch 'portfolio-shaped|Portfolio grounding') {
                    throw 'expected portfolio grounding in prompt'
                }
                [pscustomobject]@{ ok = $true; message = 'Grounded portfolio reply.'; error = '' }
            } -SkipTelemetry
            $out.status | Should -Be 'answered'
            $out.grounding.portfolioGrounded | Should -BeTrue
            $out.response.text | Should -Match 'Grounded portfolio'
        }
    }

    It 'thin-evidence prompt text does not invent health on either surface helper' {
        $preambleAsk = New-MetraPartnerIdentityPreamble -Surface Ask -Posture Desk
        $preambleVis = New-MetraPartnerIdentityPreamble -Surface Vision -Posture Desk
        $preambleAsk | Should -Match 'Do not invent biography'
        $preambleVis | Should -Match 'Do not invent biography'
        $preambleAsk | Should -Match 'execution authority'
        $preambleVis | Should -Match 'execution authority'
    }
}
