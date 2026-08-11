# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.AskEvidence.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Ask evidence - ticket ids are not factual' {
    It 'ticket id items omit factualSupport' {
        InModuleScope Metra {
            $handoff = [PSCustomObject]@{
                where = 'TicketTracker'
                what  = 'Ticket-first helpdesk entry.'
                why   = @('ticket')
                next  = 'brief'
                score = 5
            }
            $pack = New-MetraAskEvidencePack -Prompt 'Look at ticket 1035096' -Handoff $handoff
            $tickets = @($pack.items | Where-Object { $_.kind -eq 'ticket' })
            $tickets.Count | Should -BeGreaterThan 0
            foreach ($t in $tickets) {
                [bool]$t.factualSupport | Should -BeFalse
            }
        }
    }

    It 'ticket id alone does not count as factual for quality' {
        InModuleScope Metra {
            $handoff = [PSCustomObject]@{
                where = 'TicketTracker'
                what  = 'tickets'
                why   = @()
                next  = 'n'
                score = 5
            }
            $idOnly = New-MetraAskEvidenceItem -Kind 'ticket' -Label 'Ticket id 1035096' `
                -Source 'prompt' -Excerpt 'Ticket id 1035096 detected' -Confidence 'medium'
            [bool]$idOnly.factualSupport | Should -BeFalse
            $q = Get-MetraAskEvidenceQuality -Handoff $handoff -Items @($idOnly)
            $q | Should -Be 'thin'
        }
    }

    It 'ticket brief with factualSupport can be adequate' {
        InModuleScope Metra {
            $handoff = [PSCustomObject]@{
                where = 'TicketTracker'
                what  = 'tickets'
                why   = @()
                next  = 'n'
                score = 5
            }
            $brief = New-MetraAskEvidenceItem -Kind 'brief' -Label 'Ticket brief 1035096' `
                -Source 'TicketTracker' -Excerpt 'Subject: disk full on host' -Confidence 'high' -FactualSupport
            $q = Get-MetraAskEvidenceQuality -Handoff $handoff -Items @($brief)
            $q | Should -Be 'adequate'
        }
    }
}

Describe 'Ask evidence - live system intent' {
    It 'matches expanded operator phrasings' {
        InModuleScope Metra {
            Test-MetraAskLiveSystemIntent -Prompt 'status of the gateway right now' | Should -BeTrue
            Test-MetraAskLiveSystemIntent -Prompt 'check health on prd-app13' | Should -BeTrue
            Test-MetraAskLiveSystemIntent -Prompt 'are we seeing failures on int?' | Should -BeTrue
            Test-MetraAskLiveSystemIntent -Prompt 'is sam alerting?' | Should -BeTrue
            Test-MetraAskLiveSystemIntent -Prompt 'are services healthy' | Should -BeTrue
            Test-MetraAskLiveSystemIntent -Prompt 'is prod down right now' | Should -BeTrue
        }
    }

    It 'does not treat doc questions as live status' {
        InModuleScope Metra {
            Test-MetraAskLiveSystemIntent -Prompt 'How does TicketTracker brief work?' | Should -BeFalse
            Test-MetraAskLiveSystemIntent -Prompt 'Where is AGENTS.md for Colleague?' | Should -BeFalse
            Test-MetraAskLiveSystemIntent -Prompt 'Update the routing status field in docs' | Should -BeFalse
        }
    }

    It 'live intent without tool-bound evidence caps quality at thin' {
        InModuleScope Metra {
            $handoff = [PSCustomObject]@{
                where = 'Solarwinds'
                what  = 'Orion'
                why   = @()
                next  = 'n'
                score = 5
            }
            $agents = New-MetraAskEvidenceItem -Kind 'file' -Label 'AGENTS.md' `
                -Source 'AGENTS.md' -Excerpt 'Start here with Get-OrionCatalog' -Confidence 'high' -FactualSupport
            $id = New-MetraAskEvidenceItem -Kind 'ticket' -Label 'Ticket id 1035096' `
                -Source 'prompt' -Excerpt 'id only' -Confidence 'medium'
            $q = Get-MetraAskEvidenceQuality -Handoff $handoff -Items @($agents, $id) -LiveSystemWithoutToolEvidence
            $q | Should -Be 'thin'
        }
    }
}

Describe 'Ask evidence - CLI surface cap' {
    It 'Get-MetraAskCliSurfacesFromAgents returns at most 2 by default' {
        InModuleScope Metra {
            $text = @'
## Start here
- `Get-One`
- `Get-Two`
- `Get-Three`
- `Get-Four`
- `Invoke-Five`
'@
            $hits = @(Get-MetraAskCliSurfacesFromAgents -AgentsText $text)
            $hits.Count | Should -BeLessOrEqual 2
            $hits.Count | Should -Be 2
        }
    }
}
