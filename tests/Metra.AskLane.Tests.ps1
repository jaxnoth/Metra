# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.AskLane.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Ask lane thresholds' {
    It 'exposes integer route confident score of 2' {
        InModuleScope Metra {
            $t = Get-MetraAskLaneThresholds
            $t.RouteConfidentScore | Should -Be 2
            $t.RouteNoneMax | Should -Be 0
            $t.IntentHigh | Should -BeGreaterOrEqual 0.8
        }
    }
}

Describe 'Ask lane - Bing activation fixtures' {
    It 'Greeting -> chat social_greeting Capture greeting answerType' {
        InModuleScope Metra {
            $r = Resolve-MetraAskLane -Prompt 'Good morning' -RouteScore 0 -EvidenceQuality 'none'
            $r.lane | Should -Be 'chat'
            $r.reason | Should -Be 'social_greeting'
            $r.responseObjective | Should -Be 'Capture'
            $r.answerType | Should -Be 'greeting'
            $r.routeScore | Should -Be 0
        }
    }

    It 'Ambiguous reminder -> chat capture_intent Capture capture_ack (not park regex)' {
        InModuleScope Metra {
            Test-MetraAskParkOrSaveIntent -Prompt 'Remind me to look at that tomorrow' | Should -BeFalse
            $r = Resolve-MetraAskLane -Prompt 'Remind me to look at that tomorrow' -RouteScore 0 -EvidenceQuality 'none'
            $r.lane | Should -Be 'chat'
            $r.reason | Should -Be 'capture_intent'
            $r.responseObjective | Should -Be 'Capture'
            $r.answerType | Should -Be 'capture_ack'
            $r.answerType | Should -Not -Be 'park'
        }
    }

    It 'Remember that for later -> chat capture_intent' {
        InModuleScope Metra {
            $r = Resolve-MetraAskLane -Prompt 'Remember that for later' -RouteScore 0 -EvidenceQuality 'none'
            $r.lane | Should -Be 'chat'
            $r.reason | Should -Be 'capture_intent'
            $r.responseObjective | Should -Be 'Capture'
            $r.answerType | Should -Be 'capture_ack'
        }
    }

    It 'Sparse ticket -> chat sparse_intake_clarify Clarify' {
        InModuleScope Metra {
            $r = Resolve-MetraAskLane -Prompt "My computer doesn't work" -RouteScore 0 -EvidenceQuality 'none'
            $r.lane | Should -Be 'chat'
            $r.reason | Should -Be 'sparse_intake_clarify'
            $r.responseObjective | Should -Be 'Clarify'
            $r.answerType | Should -Be 'clarify_draft'
        }
    }

    It 'Voice capture thin route -> chat adequate_route_thin_evidence Capture' {
        InModuleScope Metra {
            $r = Resolve-MetraAskLane -Prompt 'That Pharos export is still broken' -RouteScore 2 -EvidenceQuality 'thin'
            $r.lane | Should -Be 'chat'
            $r.reason | Should -Be 'adequate_route_thin_evidence'
            $r.responseObjective | Should -Be 'Capture'
            $r.routeScore | Should -Be 2
            $r.answerType | Should -Not -Be 'grounded'
        }
    }

    It 'Authority primary -> OperatorConfirm never write' {
        InModuleScope Metra {
            $r = Resolve-MetraAskLane -Prompt 'Go ahead and close that ticket' -RouteScore 3 -EvidenceQuality 'adequate'
            $r.lane | Should -Be 'chat'
            $r.reason | Should -Be 'authority_requires_confirm'
            $r.responseObjective | Should -Be 'OperatorConfirm'
            $r.answerType | Should -Be 'operator_confirm'
            $r.lane | Should -Not -Be 'routed'
        }
    }
}

Describe 'Ask lane - authority set fails toward OperatorConfirm' {
    It 'Post that to the ticket' {
        InModuleScope Metra {
            $r = Resolve-MetraAskLane -Prompt 'Post that to the ticket' -RouteScore 0 -EvidenceQuality 'none'
            $r.responseObjective | Should -Be 'OperatorConfirm'
            $r.reason | Should -Be 'authority_requires_confirm'
        }
    }

    It 'Just resolve it (ambiguous)' {
        InModuleScope Metra {
            $r = Resolve-MetraAskLane -Prompt 'Just resolve it' -RouteScore 1 -EvidenceQuality 'thin'
            $r.responseObjective | Should -Be 'OperatorConfirm'
            $r.reason | Should -Be 'authority_requires_confirm'
        }
    }

    It 'Recommend closing it' {
        InModuleScope Metra {
            $r = Resolve-MetraAskLane -Prompt 'Recommend closing that ticket' -RouteScore 2 -EvidenceQuality 'adequate'
            $r.responseObjective | Should -Be 'OperatorConfirm'
        }
    }
}

Describe 'Ask lane - honesty characterization (legacy answerTypes)' {
    It 'greeting short-circuit shape pins answerType greeting' {
        InModuleScope Metra {
            Test-MetraDeskGreeting -Query 'Hello' | Should -BeTrue
            $sc = New-MetraAskGreetingResult -Query 'Hello'
            $sc.answerType | Should -Be 'greeting'
            $sc.answered | Should -BeTrue
            $sc.evidenceQuality | Should -Be 'none'
            $lane = Resolve-MetraAskLane -Prompt 'Hello' -RouteScore 0 -EvidenceQuality 'none'
            $lane.answerType | Should -Be 'greeting'
            $lane.reason | Should -Be 'social_greeting'
        }
    }

    It 'park short-circuit shape pins answerType park' {
        InModuleScope Metra {
            Test-MetraAskParkOrSaveIntent -Prompt 'Save this for later' | Should -BeTrue
            $sc = New-MetraAskParkOrSaveResult -Query 'Save this for later'
            $sc.answerType | Should -Be 'park'
            $lane = Resolve-MetraAskLane -Prompt 'Save this for later' -RouteScore 0 -EvidenceQuality 'none'
            $lane.answerType | Should -Be 'park'
            $lane.reason | Should -Be 'capture_intent'
            $lane.legacyAnswerType | Should -Be 'park'
        }
    }

    It 'observation short-circuit shape pins answerType observation' {
        InModuleScope Metra {
            Test-MetraAskPersonalObservationIntent -Prompt 'What do you know about me?' | Should -BeTrue
            $sc = New-MetraAskPersonalObservationResult -Query 'What do you know about me?'
            $sc.answerType | Should -Be 'observation'
            $lane = Resolve-MetraAskLane -Prompt 'What do you know about me?' -RouteScore 0 -EvidenceQuality 'none'
            $lane.answerType | Should -Be 'observation'
            $lane.reason | Should -Be 'personal_observation'
        }
    }
}

Describe 'Ask lane - converter projection' {
    It 'maps reason+objective one-way without collapsing honesty kinds' {
        InModuleScope Metra {
            Convert-MetraResponseObjectiveToAnswerType -ResponseObjective Capture -Reason social_greeting -LegacyAnswerType greeting |
                Should -Be 'greeting'
            Convert-MetraResponseObjectiveToAnswerType -ResponseObjective Capture -Reason personal_observation -LegacyAnswerType observation |
                Should -Be 'observation'
            Convert-MetraResponseObjectiveToAnswerType -ResponseObjective Capture -Reason capture_intent -LegacyAnswerType park |
                Should -Be 'park'
            Convert-MetraResponseObjectiveToAnswerType -ResponseObjective Capture -Reason capture_intent |
                Should -Be 'capture_ack'
            Convert-MetraResponseObjectiveToAnswerType -ResponseObjective Clarify -Reason sparse_intake_clarify |
                Should -Be 'clarify_draft'
            Convert-MetraResponseObjectiveToAnswerType -ResponseObjective OperatorConfirm -Reason authority_requires_confirm |
                Should -Be 'operator_confirm'
            Convert-MetraResponseObjectiveToAnswerType -ResponseObjective GroundedAnswer -Reason evidence_adequate_routed |
                Should -Be 'grounded'
        }
    }
}

Describe 'Ask lane - routed adequate' {
    It 'routeScore 1 adequate stays chat (below RouteConfidentScore)' {
        InModuleScope Metra {
            $t = Get-MetraAskLaneThresholds
            $t.RouteConfidentScore | Should -Be 2
            $r = Resolve-MetraAskLane -Prompt 'How does TicketTracker brief work?' -RouteScore 1 -EvidenceQuality 'adequate'
            $r.lane | Should -Be 'chat'
            $r.lane | Should -Not -Be 'routed'
            $r.responseObjective | Should -Not -Be 'GroundedAnswer'
        }
    }

    It 'routeScore 2 adequate -> routed GroundedAnswer' {
        InModuleScope Metra {
            $r = Resolve-MetraAskLane -Prompt 'How does TicketTracker brief work?' -RouteScore 2 -EvidenceQuality 'adequate'
            $r.lane | Should -Be 'routed'
            $r.reason | Should -Be 'evidence_adequate_routed'
            $r.responseObjective | Should -Be 'GroundedAnswer'
            $r.answerType | Should -Be 'grounded'
        }
    }

    It 'routeScore 3 adequate -> routed GroundedAnswer' {
        InModuleScope Metra {
            $r = Resolve-MetraAskLane -Prompt 'How does TicketTracker brief work?' -RouteScore 3 -EvidenceQuality 'adequate'
            $r.lane | Should -Be 'routed'
            $r.reason | Should -Be 'evidence_adequate_routed'
            $r.responseObjective | Should -Be 'GroundedAnswer'
            $r.answerType | Should -Be 'grounded'
        }
    }
}

Describe 'Ask lane - voice schema invariants' {
    It 'rejects spoken without durable' {
        InModuleScope Metra {
            { New-MetraVoiceResponse -Spoken 'Got it.' -Durable '' } | Should -Throw
        }
    }

    It 'enforces durable contains spoken' {
        InModuleScope Metra {
            $v = New-MetraVoiceResponse -Spoken 'Got it.' -Display 'Got it.' -Durable 'Got it. Full journal turn about Pharos.'
            $v.spoken | Should -Be 'Got it.'
            Test-MetraVoiceDurableContainsSpoken -Spoken $v.spoken -Durable $v.durable | Should -BeTrue
        }
    }

    It 'merges spoken into durable when missing' {
        InModuleScope Metra {
            $v = New-MetraVoiceResponse -Spoken 'Saved for later.' -Durable 'Journal: capture reminder about hotels.'
            Test-MetraVoiceDurableContainsSpoken -Spoken $v.spoken -Durable $v.durable | Should -BeTrue
        }
    }
}

Describe 'Ask lane - Ops badge kinds stay distinct from capture_ack' {
    It 'honesty answerTypes remain in Ops hide list' {
        $hide = @('greeting', 'observation', 'park', 'capture_ack', 'clarify_draft', 'operator_confirm')
        InModuleScope Metra {
            foreach ($prompt in @('Good morning', 'What do you know about me?', 'Park this idea')) {
                $r = Resolve-MetraAskLane -Prompt $prompt -RouteScore 0 -EvidenceQuality 'none'
                $r.answerType | Should -BeIn @('greeting', 'observation', 'park')
            }
        }
        foreach ($k in @('greeting', 'observation', 'park', 'capture_ack', 'clarify_draft', 'operator_confirm')) {
            $hide | Should -Contain $k
        }
    }
}

Describe 'Ask lane Phase 2 - Get-MetraDeskAskResult wire' {
    It 'greeting keeps answerType greeting and lane chat; showWhere false' {
        InModuleScope Metra {
            Mock Invoke-MetraAskEngine {
                throw 'Invoke-MetraAskEngine should not run for greeting'
            }
            $ask = Get-MetraDeskAskResult -Prompt 'Hello Metra'
            $ask.lane | Should -Be 'chat'
            $ask.reason | Should -Be 'social_greeting'
            $ask.answerType | Should -Be 'greeting'
            $ask.responseObjective | Should -Be 'Capture'
            $ask.handoff.lane | Should -Be 'chat'
            $ask.handoff.chatLaneReason | Should -Be 'social_greeting'
            Test-MetraAskShowWhere -Handoff $ask.handoff -Lane $ask.lane -LaneReason $ask.reason | Should -BeFalse
            Should -Invoke Invoke-MetraAskEngine -Times 0
        }
    }

    It 'ambiguous reminder is capture_ack chat, not none-evidence router failure' {
        InModuleScope Metra {
            Mock Invoke-MetraAskEngine {
                throw 'Invoke-MetraAskEngine should not run for reminder capture'
            }
            $ask = Get-MetraDeskAskResult -Prompt 'Remind me to look at that tomorrow'
            $ask.lane | Should -Be 'chat'
            $ask.reason | Should -Be 'capture_intent'
            $ask.answerType | Should -Be 'capture_ack'
            $ask.answered | Should -BeTrue
            $ask.suggestCapture | Should -BeTrue
            $ask.message | Should -Not -Match '(?i)enough routed evidence'
            $ask.voice | Should -Not -BeNullOrEmpty
            Test-MetraAskShowWhere -Handoff $ask.handoff -Lane $ask.lane -LaneReason $ask.reason | Should -BeFalse
            Should -Invoke Invoke-MetraAskEngine -Times 0
        }
    }

    It 'authority intent is OperatorConfirm and showWhere false' {
        InModuleScope Metra {
            Mock Invoke-MetraAskEngine {
                throw 'Invoke-MetraAskEngine should not run for authority'
            }
            $ask = Get-MetraDeskAskResult -Prompt 'Go ahead and close that ticket'
            $ask.lane | Should -Be 'chat'
            $ask.reason | Should -Be 'authority_requires_confirm'
            $ask.responseObjective | Should -Be 'OperatorConfirm'
            $ask.answerType | Should -Be 'operator_confirm'
            Test-MetraAskShowWhere -Handoff $ask.handoff -Lane $ask.lane -LaneReason $ask.reason | Should -BeFalse
            Should -Invoke Invoke-MetraAskEngine -Times 0
        }
    }

    It 'showWhere hides for chat-lane reasons even when handoff score is confident' {
        InModuleScope Metra {
            $h = [PSCustomObject]@{
                where          = 'TicketTracker'
                kind           = 'route'
                ambiguous      = $false
                score          = 3
                lane           = 'chat'
                chatLaneReason = 'adequate_route_thin_evidence'
            }
            Test-MetraAskShowWhere -Handoff $h | Should -BeFalse
            Test-MetraAskShowWhere -Handoff $h -Lane 'chat' -LaneReason 'adequate_route_thin_evidence' | Should -BeFalse
        }
    }

    It 'chat-lane system prompt file loads' {
        InModuleScope Metra {
            $p = Get-MetraChatLaneSystemPrompt
            $p | Should -Match '(?i)secretary|chat lane|Metra'
            $p.Length | Should -BeGreaterThan 40
        }
    }
}
