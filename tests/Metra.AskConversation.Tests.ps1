# Requires Pester 5 preferred; script-scope import also works under Pester 4.
$script:MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force

Describe 'Ask Conversation Batch 1 - secrets preflight' {
    BeforeAll {
        if (-not (Get-Module Metra)) {
            Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
        }
    }
    It 'unchanged prompt when no secrets' {
        $pre = Invoke-MetraAskConversationSecretsPreflight -Prompt '  How are you today?  '
        $pre.Disposition | Should -Be 'unchanged'
        $pre.Prompt | Should -Be 'How are you today?'
        $pre.PSObject.Properties.Name | Should -Not -Contain 'RawPrompt'
    }

    It 'scrubbed disposition redacts API-style key and never returns raw' {
        InModuleScope Metra {
            $sk = 'sk-' + ('d' * 32)
            $pre = Invoke-MetraAskConversationSecretsPreflight -Prompt "please use $sk"
            $pre.Disposition | Should -Be 'scrubbed'
            $pre.Prompt | Should -Match '\[REDACTED:api_key\]'
            $pre.Prompt | Should -Not -Match ([regex]::Escape($sk))
            $pre.PSObject.Properties.Name | Should -Not -Contain 'RawPrompt'
        }
    }

    It 'refuse disposition for PEM and filled refuse voice has no key material' {
        InModuleScope Metra {
            $begin = '-----BEGIN ' + 'RSA PRIVATE KEY-----'
            $end = '-----END ' + 'RSA PRIVATE KEY-----'
            $pem = "$begin`nMIIEowIBAAKCAQEAexample`n$end"
            $r = New-MetraAskConversationBatch1Result -Prompt $pem -PathKind 'success' -EngineText 'should not appear'
            $r.pathKind | Should -Be 'refuse'
            $r.reasonCode | Should -Be 'secrets_refuse'
            Test-MetraAskVoiceContract -Result $r | Should -BeTrue
            $r.message | Should -Be $r.voice.display
            $r.message | Should -Match '(?i)private-key|blocked'
            $r.message | Should -Not -Match 'MIIEowIBAAKCAQEAexample'
            $r.voice.durable | Should -Match 'secrets_boundary'
            $r.voice.durable | Should -Not -Match 'MIIEowIBAAKCAQEAexample'
            $r.prompt | Should -Be ''
        }
    }
}

Describe 'Ask Conversation Batch 1 - voice invariants' {
    BeforeAll {
        if (-not (Get-Module Metra)) {
            Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
        }
    }
    It 'success: message equals voice.display and channels filled' {
        $r = New-MetraAskConversationBatch1Result `
            -Prompt 'status check' `
            -PathKind 'success' `
            -EngineText 'All quiet on the desk.' `
            -ReasonCode 'ok'
        # Default flag is false -> legacy path unless fixture enables it.
        # Force success path via Format directly for this fixture.
        $voice = Format-MetraAskVoiceFromEngine -PathKind 'success' -Text 'All quiet on the desk.' -ReasonCode 'ok'
        $r = New-MetraAskConversationResult -Voice $voice -ReasonCode 'ok' -PathKind 'success' -Answered:$true -Prompt 'status check'
        Test-MetraAskVoiceContract -Result $r | Should -BeTrue
        $r.message | Should -Be 'All quiet on the desk.'
        $r.voice.spoken | Should -Be 'All quiet on the desk.'
        $r.voice.durable | Should -Not -BeNullOrEmpty
    }

    It 'success spoken strips Markdown furniture' {
        $voice = Format-MetraAskVoiceFromEngine -PathKind 'success' -Text '**Bold** and `code` stay plain.'
        $voice.spoken | Should -Not -Match '\*\*'
        $voice.spoken | Should -Not -Match '`'
        $voice.spoken | Should -Match 'Bold'
        $voice.display | Should -Match 'Bold'
        $r = New-MetraAskConversationResult -Voice $voice -PathKind 'success'
        Test-MetraAskVoiceContract -Result $r | Should -BeTrue
    }

    It 'authority preserves OperatorConfirm on all channels' {
        $voice = Format-MetraAskVoiceFromEngine `
            -PathKind 'authority' `
            -Text 'I can draft a recommend.' `
            -ReasonCode 'authority_requires_confirm'
        $r = New-MetraAskConversationResult -Voice $voice -PathKind 'authority' -ReasonCode 'authority_requires_confirm' -Answered:$false
        Test-MetraAskVoiceContract -Result $r | Should -BeTrue
        $r.voice.spoken | Should -Match 'OperatorConfirm'
        $r.voice.display | Should -Match 'OperatorConfirm'
        $r.voice.durable | Should -Match 'OperatorConfirm'
        $r.message | Should -Be $r.voice.display
    }

    It 'fallback preserves not-completed semantics and never empty' {
        $voice = Format-MetraAskVoiceFromEngine -PathKind 'fallback' -Text '' -ReasonCode 'engine_timeout'
        $r = New-MetraAskConversationResult -Voice $voice -PathKind 'fallback' -ReasonCode 'engine_timeout' -Answered:$false
        Test-MetraAskVoiceContract -Result $r | Should -BeTrue
        $r.voice.spoken | Should -Match '(?i)not completed'
        $r.voice.durable | Should -Match 'not-completed'
        $r.message | Should -Not -Match '(?i)completed successfully'
    }

    It 'legacy (flag false) still fills voice with message == display' {
        $tmp = Join-Path $env:TEMP ('metra-ask-ce-' + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path $tmp -Force
            @{
                ask = @{
                    enabled               = $true
                    conversationExecution = @{ enabled = $false }
                }
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tmp 'metra.config.json') -Encoding utf8
            Test-MetraAskConversationExecutionEnabled -MetraRoot $tmp | Should -BeFalse
            $r = New-MetraAskConversationBatch1Result `
                -Prompt 'hello' `
                -PathKind 'success' `
                -EngineText 'Legacy branch reply.' `
                -MetraRoot $tmp
            $r.pathKind | Should -Be 'legacy'
            $r.conversationExecutionEnabled | Should -BeFalse
            Test-MetraAskVoiceContract -Result $r | Should -BeTrue
            $r.message | Should -Be $r.voice.display
            $r.voice.display | Should -Match 'Legacy branch reply'
        }
        finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'enabled flag true keeps success pathKind' {
        $tmp = Join-Path $env:TEMP ('metra-ask-ce-' + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path $tmp -Force
            @{
                ask = @{
                    enabled               = $true
                    conversationExecution = @{ enabled = $true }
                }
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tmp 'metra.config.json') -Encoding utf8
            Test-MetraAskConversationExecutionEnabled -MetraRoot $tmp | Should -BeTrue
            $r = New-MetraAskConversationBatch1Result `
                -Prompt 'hello' `
                -PathKind 'success' `
                -EngineText 'Conversation path reply.' `
                -MetraRoot $tmp
            $r.pathKind | Should -Be 'success'
            $r.conversationExecutionEnabled | Should -BeTrue
            Test-MetraAskVoiceContract -Result $r | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'empty engine text still yields filled voice contract' {
        $voice = Format-MetraAskVoiceFromEngine -PathKind 'success' -Text '   '
        $r = New-MetraAskConversationResult -Voice $voice -PathKind 'success'
        Test-MetraAskVoiceContract -Result $r | Should -BeTrue
        $r.message | Should -Not -BeNullOrEmpty
    }
}

Describe 'Ask Conversation - intent policy depth' {
    BeforeAll {
        if (-not (Get-Module Metra)) {
            Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
        }
    }
    It 'secrets refuse semantics are refusal not degraded' {
        $refuse = Resolve-MetraAskAnswerSemantics -EvidenceQuality 'thin' -SecretsRefuse
        $refuse.answerType | Should -Be 'refusal'
        $refuse.answered | Should -BeFalse

        $degraded = Resolve-MetraAskAnswerSemantics -EvidenceQuality 'thin' -EngineUnavailable
        $degraded.answerType | Should -Be 'degraded'
        $degraded.answered | Should -BeFalse
    }

    It 'evidence depth is a ceiling (intent maps; never exceeds full)' {
        $cases = @(
            @{ Prompt = 'How are you today?'; Expect = 'capability_only'; Class = 'check_in' }
            @{ Prompt = 'How are today Metra?'; Expect = 'capability_only'; Class = 'check_in' }
            @{ Prompt = 'what can you do'; Expect = 'capability_only'; Class = 'capability' }
            @{ Prompt = 'go ahead and resolve that ticket'; Expect = 'route_summary'; Class = 'authority_write' }
        )
        foreach ($c in $cases) {
            $intent = Resolve-MetraAskIntent -Prompt $c.Prompt
            $intent.IntentClass | Should -Be $c.Class
            $intent.PSObject.Properties.Name | Should -Contain 'Confidence'
            $intent.PSObject.Properties.Name | Should -Contain 'Source'
            $policy = Resolve-MetraConversationPolicy -Intent $intent
            $depth = Resolve-MetraAskEvidenceDepth -Intent $intent -Policy $policy
            $depth.Depth | Should -Be $c.Expect
            $depth.Ceiling | Should -Be $c.Expect
        }
    }

    It 'check_in intent maps to capability_only depth' {
        $intent = Resolve-MetraAskIntent -Prompt 'How are you today?'
        $intent.IntentClass | Should -Be 'check_in'
        $policy = Resolve-MetraConversationPolicy -Intent $intent
        $depth = Resolve-MetraAskEvidenceDepth -Intent $intent -Policy $policy
        $depth.Depth | Should -Be 'capability_only'
    }

    It 'untrusted policy override is rejected and does not relax' {
        $intent = Resolve-MetraAskIntent -Prompt 'Are you running well?'
        $policy = Resolve-MetraConversationPolicy -Intent $intent -RequestedPolicy 'Company' -TrustedClientContext:$false
        $policy.OverrideRejected | Should -BeTrue
        $policy.OverrideRejectReason | Should -Be 'policy_override_untrusted'
        $policy.Policy | Should -Not -Be 'Company'
    }

    It 'trusted override may tighten to DeskStrict' {
        $intent = Resolve-MetraAskIntent -Prompt 'list projects'
        $policy = Resolve-MetraConversationPolicy -Intent $intent -RequestedPolicy 'DeskStrict' -TrustedClientContext:$true
        $policy.Policy | Should -Be 'DeskStrict'
        $policy.OverrideRejected | Should -BeFalse
    }

    It 'header body mismatch rejects override' {
        $intent = Resolve-MetraAskIntent -Prompt 'hello'
        $policy = Resolve-MetraConversationPolicy -Intent $intent -HeaderClient 'ops-ios' -BodyClient 'ops-web' `
            -RequestedPolicy 'Company' -TrustedClientContext:$true
        $policy.OverrideRejected | Should -BeTrue
        $policy.OverrideRejectReason | Should -Be 'policy_override_client_mismatch'
    }

    It 'NL incident alone does not set DeskStrict without IncidentActive' {
        $intent = Resolve-MetraAskIntent -Prompt 'what would you do in an incident?'
        $policy = Resolve-MetraConversationPolicy -Intent $intent -IncidentActive:$false
        $policy.Policy | Should -Not -Be 'DeskStrict'
    }

    It 'IncidentActive forces DeskStrict and disables humor knob' {
        $intent = Resolve-MetraAskIntent -Prompt 'status'
        $policy = Resolve-MetraConversationPolicy -Intent $intent -IncidentActive:$true
        $policy.Policy | Should -Be 'DeskStrict'
        $policy.Knobs.humor | Should -BeFalse
        $policy.Knobs.warmth | Should -Be 0
    }

    It 'health freshness missing is unverifiable' {
        Test-MetraAskHealthObservationCurrent -Health $null | Should -BeFalse
        Test-MetraAskHealthObservationCurrent -Health ([PSCustomObject]@{ observationTimestamp = (Get-Date).ToString('o') }) | Should -BeFalse
        Test-MetraAskHealthObservationCurrent -Health ([PSCustomObject]@{ isCurrent = $true }) | Should -BeTrue
    }

    It 'evidence depth none returns empty items' {
        InModuleScope Metra {
            $h = Get-MetraDeskHandoff -Query 'x'
            $p = New-MetraAskEvidencePack -Prompt 'x' -Handoff $h -Depth none
            $p.evidenceDepth | Should -Be 'none'
            @($p.items).Count | Should -Be 0
            $p.quality | Should -Be 'none'
        }
    }

    It 'authority intent yields OperatorConfirm voice path without engine' {
        $tmp = Join-Path $env:TEMP ('metra-ask-ce-' + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path $tmp -Force
            @{ ask = @{ enabled = $true; conversationExecution = @{ enabled = $true } } } |
                ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $tmp 'metra.config.json') -Encoding utf8
            # Match Test-MetraAskAuthorityIntent patterns so the path never starts a sidecar under temp MetraRoot.
            $r = Invoke-MetraAskConversationExecution -Prompt 'go ahead and resolve that ticket and post the fix' -MetraRoot $tmp
            Test-MetraAskVoiceContract -Result $r | Should -BeTrue
            $r.reasonCode | Should -Be 'authority_requires_confirm'
            $r.answerType | Should -Be 'operator_confirm'
            $r.voice.display | Should -Match 'OperatorConfirm'
        }
        finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'flag false Get-MetraDeskAskResult still fills voice' {
        $tmp = Join-Path $env:TEMP ('metra-ask-ce-' + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path $tmp -Force
            @{ ask = @{ enabled = $true; conversationExecution = @{ enabled = $false } } } |
                ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $tmp 'metra.config.json') -Encoding utf8
            $r = Get-MetraDeskAskResult -Prompt 'hi' -MetraRoot $tmp
            Test-MetraAskVoiceContract -Result $r | Should -BeTrue
            $r.message | Should -Be $r.voice.display
        }
        finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
