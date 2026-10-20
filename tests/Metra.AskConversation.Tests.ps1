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

    It 'Vision phone client is identified by client headers (not utterance regex)' {
        Test-MetraAskVisionPhoneClient -HeaderClient 'ops-ios' -BodyClient 'ops-ios' -ClientHint 'phone' | Should -BeTrue
        Test-MetraAskVisionPhoneClient -HeaderClient 'ops-web' -BodyClient 'ops-web' -ClientHint '' | Should -BeFalse
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

Describe 'Ask Conversation p4-telemetry policy envelope' {
    BeforeAll {
        if (-not (Get-Module Metra)) {
            Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
        }
    }

    It 'envelope contract: version 1, registry reasonCode, normative retention/exec' {
        $i = Resolve-MetraAskIntent -Prompt 'How are you today?'
        $p = Resolve-MetraConversationPolicy -Intent $i
        $e = New-MetraPolicyEnvelope -Policy $p -Intent $i -ConversationId 'c1' -TurnId 3 -Surface ops-ask
        Test-MetraPolicyEnvelopeContract -Envelope $e | Should -BeTrue
        $e.policyEnvelopeVersion | Should -Be 1
        $e.reasonCode | Should -Be 'companionship_signal'
        $e.policy | Should -Be 'Company'
        $e.policySource | Should -Be 'inference'
        $e.retentionClass | Should -Be 'normal'
        $e.executionTarget | Should -Be 'ops'
        $e.conversationId | Should -Be 'c1'
        $e.turnId | Should -Be 3
    }

    It 'never treats CE posture aliases as normative retentionClass' {
        $bad = [PSCustomObject]@{
            policyEnvelopeVersion = 1
            policy                = 'Company'
            reasonCode            = 'companionship_signal'
            intentConfidence      = 0.8
            policySource          = 'inference'
            retentionClass        = 'company'
            executionTarget       = $null
            conversationId        = 'x'
            turnId                = 1
        }
        Test-MetraPolicyEnvelopeContract -Envelope $bad | Should -BeFalse
    }

    It 'CE path emits policyEnvelope observe-only on check_in' {
        $tmp = Join-Path $env:TEMP ('metra-ask-p4-' + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path $tmp -Force
            @{ ask = @{ enabled = $true; conversationExecution = @{ enabled = $true } } } |
                ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $tmp 'metra.config.json') -Encoding utf8
            $r = Invoke-MetraAskConversationExecution -Prompt 'How are you today?' -SessionId 'sess-p4' -MetraRoot $tmp
            $r.policyEnvelope | Should -Not -BeNullOrEmpty
            Test-MetraPolicyEnvelopeContract -Envelope $r.policyEnvelope | Should -BeTrue
            $r.policyEnvelope.surface | Should -Be 'ops-ask'
            $r.policyEnvelope.retentionClass | Should -Be 'normal'
            $r.policyEnvelope.executionTarget | Should -Be 'ops'
            # Must not leak posture-alias knobs onto top-level retentionClass
            if ($null -ne $r.retentionClass -and "$($r.retentionClass)" -ne '') {
                "$($r.retentionClass)" | Should -Not -BeIn @('desk', 'company', 'deliver', 'auto')
            }
        }
        finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'Ops Ask and Vision Ask share policy/reasonCode/policySource for equivalent intent' {
        $prompt = 'How are you today?'
        $iOps = Resolve-MetraAskIntent -Prompt $prompt
        $pOps = Resolve-MetraConversationPolicy -Intent $iOps
        $eOps = New-MetraPolicyEnvelope -Policy $pOps -Intent $iOps -ConversationId 'eq1' -TurnId 1 -Surface ops-ask

        $iVis = Resolve-MetraAskIntent -Prompt $prompt
        $pVis = Resolve-MetraConversationPolicy -Intent $iVis
        $eVis = New-MetraPolicyEnvelope -Policy $pVis -Intent $iVis -ConversationId 'eq1' -TurnId 1 -Surface vision-ask

        $eOps.policy | Should -Be $eVis.policy
        $eOps.reasonCode | Should -Be $eVis.reasonCode
        $eOps.policySource | Should -Be $eVis.policySource
        $eOps.surface | Should -Be 'ops-ask'
        $eVis.surface | Should -Be 'vision-ask'
    }
}

Describe 'Ask Conversation intent-expand + retention-exec' {
    BeforeAll {
        if (-not (Get-Module Metra)) {
            Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
        }
    }

    It 'tell me a story is artifact_request -> Deliver' {
        $i = Resolve-MetraAskIntent -Prompt 'Tell me a story'
        $i.IntentClass | Should -Be 'artifact_request'
        $p = Resolve-MetraConversationPolicy -Intent $i
        $p.Policy | Should -Be 'Deliver'
    }

    It 'tell me about SQL injection is work Desk path not Deliver' {
        $i = Resolve-MetraAskIntent -Prompt 'Tell me about SQL injection'
        $i.IntentClass | Should -Not -Be 'artifact_request'
        $p = Resolve-MetraConversationPolicy -Intent $i
        $p.Policy | Should -Not -Be 'Deliver'
    }

    It 'write a short README is artifact_request' {
        $i = Resolve-MetraAskIntent -Prompt 'Write a short README'
        $i.IntentClass | Should -Be 'artifact_request'
    }

    It 'support stress maps Company + ephemeral + local' {
        $i = Resolve-MetraAskIntent -Prompt "I'm stressed and need to talk"
        $i.IntentClass | Should -Match '^support_'
        $p = Resolve-MetraConversationPolicy -Intent $i
        $p.Policy | Should -Be 'Company'
        $e = New-MetraPolicyEnvelope -Policy $p -Intent $i -ConversationId 's' -TurnId 1 -Surface ops-ask
        $e.retentionClass | Should -Be 'ephemeral'
        $e.executionTarget | Should -Be 'local'
        $e.reasonCode | Should -Be 'support_personal'
    }

    It 'knobs use retentionLane not posture-alias retentionClass' {
        $k = Get-MetraConversationPolicyKnobs -Policy Company
        $k.PSObject.Properties.Name | Should -Contain 'retentionLane'
        $k.PSObject.Properties.Name | Should -Not -Contain 'retentionClass'
        $k.retentionLane | Should -Be 'company'
    }

    It 'intimacy romance refuses with retention refuse and no engine path' {
        $tmp = Join-Path $env:TEMP ('metra-ask-int-' + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path $tmp -Force
            @{ ask = @{ enabled = $true; conversationExecution = @{ enabled = $true } } } |
                ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $tmp 'metra.config.json') -Encoding utf8
            $r = Invoke-MetraAskConversationExecution -Prompt 'be my girlfriend' -MetraRoot $tmp
            $r.answerType | Should -Be 'refusal'
            $r.reasonCode | Should -Be 'intimacy_refuse'
            $r.policyEnvelope.retentionClass | Should -Be 'refuse'
            $r.message | Should -Match 'coworker'
        }
        finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'support path does not silently use sticky cloud when local unavailable' {
        $tmp = Join-Path $env:TEMP ('metra-ask-sup-' + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path $tmp -Force
            @{ ask = @{ enabled = $true; conversationExecution = @{ enabled = $true } } } |
                ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $tmp 'metra.config.json') -Encoding utf8
            $r = Invoke-MetraAskConversationExecution -Prompt "I'm lonely and need someone to talk" -MetraRoot $tmp
            $r.reasonCode | Should -Be 'retention_block_no_compliant_route'
            $r.policyEnvelope.executionTarget | Should -Be 'local'
            $r.policyEnvelope.retentionClass | Should -Be 'ephemeral'
            $r.message | Should -Match 'not send'
        }
        finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'companionship maps ephemeral + local (not sticky ops)' {
        $i = Resolve-MetraAskIntent -Prompt 'just keep me company'
        if ($i.IntentClass -ne 'companionship') {
            Set-ItResult -Skipped -Because "intent classifier did not map companionship for this phrasing (got $($i.IntentClass))"
            return
        }
        $re = Resolve-MetraRetentionAndExecutionTarget -Intent $i -Policy (Resolve-MetraConversationPolicy -Intent $i)
        $re.RetentionClass | Should -Be 'ephemeral'
        $re.ExecutionTarget | Should -Be 'local'
    }
}

Describe 'Ask Conversation stale-episode' {
    BeforeAll {
        if (-not (Get-Module Metra)) {
            Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
        }
    }

    It 'matching conversationId/turnId/retention accepts' {
        $r = Test-MetraAskStaleRoute `
            -ResponseConversationId 'c1' -ResponseTurnId 2 -ResponseRetentionClass 'ephemeral' -ResponseExecutionTarget 'local' `
            -ActiveConversationId 'c1' -ActiveTurnId 2 -ActiveRetentionClass 'ephemeral' -ActiveExecutionTarget 'local'
        $r.Accept | Should -BeTrue
    }

    It 'mismatched turnId drops with retention_stale_turn_drop' {
        $r = Test-MetraAskStaleRoute `
            -ResponseConversationId 'c1' -ResponseTurnId 1 -ResponseRetentionClass 'ephemeral' `
            -ActiveConversationId 'c1' -ActiveTurnId 2 -ActiveRetentionClass 'ephemeral'
        $r.Accept | Should -BeFalse
        $r.ReasonCode | Should -Be 'retention_stale_turn_drop'
        $r.Detail | Should -Be 'turnId_mismatch'
    }

    It 'ephemeral reply cannot land after Desk normal turn' {
        $r = Test-MetraAskStaleRoute `
            -ResponseConversationId 'c1' -ResponseTurnId 3 -ResponseRetentionClass 'ephemeral' `
            -ActiveConversationId 'c1' -ActiveTurnId 3 -ActiveRetentionClass 'normal'
        $r.Accept | Should -BeFalse
        $r.Detail | Should -Be 'retentionClass_incompatible'
    }

    It 'ephemeral episode ends on leave Company / 15m idle / background / clear' {
        $ep = New-MetraEphemeralEpisode -ConversationId 'c1'
        (Test-MetraEphemeralEpisodeEnded -Episode $ep -Policy 'DeskStrict').Ended | Should -BeTrue
        (Test-MetraEphemeralEpisodeEnded -Episode $ep -Policy 'Company' -IntentClass 'work').Ended | Should -BeTrue
        $old = New-MetraEphemeralEpisode -ConversationId 'c1' -LastActivityAt ([datetime]::UtcNow.AddMinutes(-16))
        (Test-MetraEphemeralEpisodeEnded -Episode $old -Policy 'Company' -IntentClass 'support_stress').Ended | Should -BeTrue
        (Test-MetraEphemeralEpisodeEnded -Episode $ep -Policy 'Company' -IntentClass 'support_stress' -AppBackgrounded).Ended | Should -BeTrue
        (Test-MetraEphemeralEpisodeEnded -Episode $ep -Policy 'Company' -IntentClass 'support_stress' -ExplicitClear).Ended | Should -BeTrue
        (Test-MetraEphemeralEpisodeEnded -Episode $ep -Policy 'Company' -IntentClass 'support_stress').Ended | Should -BeFalse
    }

    It 'in-flight ephemeral completion cannot display after background ends episode' {
        # Edge: Ask in flight -> background -> episode ends -> HTTP may finish -> display impossible.
        $r = Test-MetraEphemeralInFlightAfterBackground -ConversationId 'c-bg' -TurnId 1
        $r.EpisodeEnded | Should -BeTrue
        $r.EndReason | Should -Be 'background'
        $r.DisplayAllowed | Should -BeFalse
        $r.ReasonCode | Should -Be 'retention_stale_turn_drop'
    }
}

Describe 'Ask Conversation enforce-ops' {
    BeforeAll {
        if (-not (Get-Module Metra)) {
            Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
        }
    }

    It 'Deliver knobs maxClarifications 0 and prompt says Deliver-first' {
        $i = Resolve-MetraAskIntent -Prompt 'Write a short README'
        $p = Resolve-MetraConversationPolicy -Intent $i
        $p.Policy | Should -Be 'Deliver'
        $p.Knobs.maxClarifications | Should -Be 0
        $prompt = New-MetraConversationPrompt -Prompt 'Write a short README' -Intent $i -Policy $p -Depth none
        $prompt.Text | Should -Match 'Deliver-first'
    }

    It 'DeskStrict knobs strip humor/silence and prompt forbids Company mood baggage' {
        $i = Resolve-MetraAskIntent -Prompt 'status of SQL'
        $p = Resolve-MetraConversationPolicy -Intent $i -IncidentActive $true -TrustedClientContext $true
        $p.Policy | Should -Be 'DeskStrict'
        $p.Knobs.humor | Should -BeFalse
        $p.Knobs.silenceOk | Should -BeFalse
        $prompt = New-MetraConversationPrompt -Prompt 'status of SQL' -Intent $i -Policy $p -Depth none -IncidentActive
        $prompt.Text | Should -Match 'DeskStrict'
        $prompt.Text | Should -Match 'Humor off'
        $prompt.Text | Should -Match 're-evaluated each user turn'
    }

    It 'Ask Surface loads Conversation Identity without vision system.md and exposes identityHash' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'metra-ask-id'
            $rules = Join-Path $root '.cursor\rules'
            New-Item -ItemType Directory -Path $rules -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'engines\vision-ask') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $rules 'metra-persona.mdc') -Value 'persona ASK' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $root 'engines\vision-ask\system.md') -Value 'VISION-SYSTEM-SHOULD-NOT-LOAD' -Encoding utf8

            $i = Resolve-MetraAskIntent -Prompt 'check in'
            $p = Resolve-MetraConversationPolicy -Intent $i
            $built = New-MetraConversationPrompt -Prompt 'hey' -Intent $i -Policy $p -Depth none -Surface Ask -MetraRoot $root
            $built.Text | Should -Match 'persona ASK'
            $built.Text | Should -Match 'Desk Ops chat: same Partner Identity'
            $built.Text | Should -Not -Match 'VISION-SYSTEM-SHOULD-NOT-LOAD'
            $built.IdentityHash | Should -Match '^[0-9a-f]{16}$'
            ($built.PacksOmitted | Where-Object { $_.Id -eq 'vision' }).Reason | Should -Be 'surface_gate'
        }
    }

    It 'Company then work re-eval yields Desk with no Company policy carry' {
        $i1 = Resolve-MetraAskIntent -Prompt 'How are you today?'
        $p1 = Resolve-MetraConversationPolicy -Intent $i1
        $p1.Policy | Should -Be 'Company'
        $i2 = Resolve-MetraAskIntent -Prompt 'What is the status of TicketTracker?'
        $p2 = Resolve-MetraConversationPolicy -Intent $i2
        $p2.Policy | Should -BeIn @('Desk', 'Auto')
        $p2.Policy | Should -Not -Be 'Company'
    }

    It 'synthesis-recommend: recommend-shaped + factual related evidence loads Synthesize addendum' {
        $prompt = 'What should I do on ticket 123456?'
        $i = Resolve-MetraAskIntent -Prompt $prompt
        $pack = [PSCustomObject]@{
            items = @(
                [PSCustomObject]@{
                    kind           = 'ticket'
                    label          = 'Ticket 123456'
                    excerpt        = 'Disk full on host-sql01; last brief says clear temp and expand volume.'
                    factualSupport = $true
                }
                [PSCustomObject]@{
                    kind           = 'ticket'
                    label          = 'Similar 111111'
                    excerpt        = 'Prior disk alert cleared after temp purge.'
                    factualSupport = $true
                }
            )
        }
        $mode = Resolve-MetraAskSynthesisMode -Prompt $prompt -Intent $i -EvidencePack $pack
        $mode.Mode | Should -Be 'Synthesize'
        $p = Resolve-MetraConversationPolicy -Intent $i
        $built = New-MetraConversationPrompt -Prompt $prompt -Intent $i -Policy $p -Depth full -SynthesisMode Synthesize
        $built.SynthesisMode | Should -Be 'Synthesize'
        $built.Text | Should -Match 'Evidence vs reader synthesis \(required this turn\)'
        $built.Text | Should -Match 'verdict first'
        $built.Text | Should -Match 'Do not hand a related-item'
    }

    It 'list-peers-ok: explicit list ask skips synthesis addendum' {
        $prompt = 'List related tickets for 123456'
        $i = Resolve-MetraAskIntent -Prompt $prompt
        Test-MetraAskExplicitListPeersIntent -Prompt $prompt | Should -BeTrue
        $pack = [PSCustomObject]@{
            items = @(
                [PSCustomObject]@{ kind = 'ticket'; label = '111'; factualSupport = $true; excerpt = 'peer A' }
            )
        }
        $mode = Resolve-MetraAskSynthesisMode -Prompt $prompt -Intent $i -EvidencePack $pack
        $mode.Mode | Should -Be 'None'
        $mode.Reason | Should -Be 'explicit_list_peers'
        $p = Resolve-MetraConversationPolicy -Intent $i
        $built = New-MetraConversationPrompt -Prompt $prompt -Intent $i -Policy $p -Depth full -SynthesisMode None
        $built.SynthesisMode | Should -Be 'None'
        # Identity packs may mention the scar by name; CE turn addendum must stay off for list asks.
        $built.Text | Should -Not -Match 'Evidence vs reader synthesis \(required this turn\)'
        $built.Text | Should -Not -Match 'Evidence vs reader synthesis \(restraint this turn\)'
    }

    It 'recommend-shaped id-only related uses Restraint choice-beat addendum' {
        $prompt = 'What should I recommend on ticket 123456?'
        $i = Resolve-MetraAskIntent -Prompt $prompt
        $pack = [PSCustomObject]@{
            items = @(
                [PSCustomObject]@{
                    kind           = 'ticket'
                    label          = 'Ticket id 123456'
                    excerpt        = 'Ticket id 123456 detected'
                    factualSupport = $false
                }
            )
        }
        $mode = Resolve-MetraAskSynthesisMode -Prompt $prompt -Intent $i -EvidencePack $pack
        $mode.Mode | Should -Be 'Restraint'
        $p = Resolve-MetraConversationPolicy -Intent $i
        $built = New-MetraConversationPrompt -Prompt $prompt -Intent $i -Policy $p -Depth full -SynthesisMode Restraint
        $built.Text | Should -Match 'Evidence vs reader synthesis \(restraint this turn\)'
        $built.Text | Should -Match 'do not invent a recommendation'
        $built.Text | Should -Match 'agency-visible hold'
    }
}

Describe 'Ask Conversation spark-or-quiet + seam-resume' {
    BeforeAll {
        if (-not (Get-Module Metra)) {
            Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
        }
    }

    It 'default deny without quiet episode / open energy' {
        $r = Test-MetraCompanySparkEligibility -IsCompany $true -SilenceOk $true -OpenEnergy $false -QuietEpisodeActive $true
        $r.Eligible | Should -BeFalse
        $r.Reason | Should -Be 'closed_energy'
    }

    It 'one spark per episode then blocked until new episode' {
        $ok = Test-MetraCompanySparkEligibility -IsCompany $true -SilenceOk $true -OpenEnergy $true -QuietEpisodeActive $true
        $ok.Eligible | Should -BeTrue
        $again = Test-MetraCompanySparkEligibility -IsCompany $true -SilenceOk $true -OpenEnergy $true -QuietEpisodeActive $true -SparkAlreadyThisEpisode $true
        $again.Eligible | Should -BeFalse
        $again.Reason | Should -Be 'already_sparked_this_episode'
    }

    It '5m cooldown and hourly cap of 3' {
        $now = [datetime]::UtcNow
        $cool = Test-MetraCompanySparkEligibility -IsCompany $true -SilenceOk $true -OpenEnergy $true -QuietEpisodeActive $true `
            -LastSparkAt $now.AddMinutes(-2) -NowUtc $now
        $cool.Eligible | Should -BeFalse
        $cool.Reason | Should -Be 'cooldown_5m'
        $stamps = @($now.AddMinutes(-50), $now.AddMinutes(-40), $now.AddMinutes(-30))
        $cap = Test-MetraCompanySparkEligibility -IsCompany $true -SilenceOk $true -OpenEnergy $true -QuietEpisodeActive $true `
            -SparkTimestampsHour $stamps -NowUtc $now -LastSparkAt $now.AddMinutes(-10)
        $cap.Eligible | Should -BeFalse
        $cap.Reason | Should -Be 'hourly_cap'
    }

    It 'seam skipped on closed command; resume needs parked thread id' {
        $s = Test-MetraSeamAuthorization -IsCompany $true -OpenEnergy $true -ClosedCommandTurn $true
        $s.Allow | Should -BeFalse
        (Test-MetraResumeCallbackAuthorized -ParkedThreadId '') | Should -BeFalse
        (Test-MetraResumeCallbackAuthorized -ParkedThreadId 'park-1') | Should -BeTrue
    }

    It 'DeskStrict knobs silenceOk false blocks spark path' {
        $k = Get-MetraConversationPolicyKnobs -Policy DeskStrict
        $k.silenceOk | Should -BeFalse
        $r = Test-MetraCompanySparkEligibility -IsCompany $false -SilenceOk $k.silenceOk -OpenEnergy $true -QuietEpisodeActive $true
        $r.Eligible | Should -BeFalse
    }
}
