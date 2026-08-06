# Requires Pester 5+. Run via tests\Invoke-MetraTests.ps1 or:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.TicketWatch.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Ticket watch Attention helpers' {
    It 'ranks ticket above drift and git' {
        InModuleScope Metra {
            (Get-MetraAttentionKindPriority -Kind 'verify') | Should -Be 0
            (Get-MetraAttentionKindPriority -Kind 'ticket') | Should -Be 1
            (Get-MetraAttentionKindPriority -Kind 'drift') | Should -Be 2
            (Get-MetraAttentionKindPriority -Kind 'git') | Should -Be 3
            (Get-MetraAttentionKindPriority -Kind 'decision') | Should -Be 4
            (Get-MetraAttentionKindPriority -Kind 'contract') | Should -Be 5
        }
    }

    It 'builds evidence signatures from id, Updated, and Status only' {
        InModuleScope Metra {
            $a = New-MetraTicketAttentionEvidenceSignature -TicketId '123456' -Updated '2026-08-06T08:32:14' -Status 'Open'
            $b = New-MetraTicketAttentionEvidenceSignature -TicketId '123456' -Updated '2026-08-06T08:32:14' -Status 'Open'
            $c = New-MetraTicketAttentionEvidenceSignature -TicketId '123456' -Updated '2026-08-06T09:00:00' -Status 'Open'
            $d = New-MetraTicketAttentionEvidenceSignature -TicketId '123456' -Updated '2026-08-06T08:32:14' -Status 'Closed'
            $a | Should -Be $b
            $a | Should -Not -Be $c
            $a | Should -Not -Be $d
            $a | Should -Be 'ticket:123456|updated:2026-08-06T08:32:14|status:Open'
        }
    }

    It 'keeps Attention key stable while evidenceSignature changes on Updated' {
        InModuleScope Metra -Parameters @{ Drive = $TestDrive } {
            $tempRoot = Join-Path $Drive 'metra-ticket-watch'
            New-Item -ItemType Directory -Path (Join-Path $tempRoot 'docs') -Force | Out-Null

            $ticket = [PSCustomObject]@{
                Id       = '999001'
                Status   = 'Open'
                Updated  = '2026-08-06T08:00:00'
                Priority = 'High'
                Subject  = 'Test'
            }
            $q1 = ConvertTo-MetraTicketAttentionQueueItem -Ticket $ticket
            $null = Update-MetraAttentionMemory -Queue @($q1) -CoveredKinds @('ticket') -ScanMode 'full' -MetraRoot $tempRoot

            $mem1 = Get-MetraAttentionMemory -MetraRoot $tempRoot
            $item1 = @($mem1.items | Where-Object { $_.key -eq 'ticket:999001' })[0]
            $item1 | Should -Not -BeNullOrEmpty
            $item1.state | Should -Be 'active'
            $sig1 = [string]$item1.evidenceSignature

            $item1.state = 'dismissed'
            $item1.closedAt = (Get-Date).ToString('o')
            $item1.closedBy = 'operator'
            $mem1.items = @($item1)
            $null = Set-MetraAttentionMemory -Memory $mem1 -MetraRoot $tempRoot

            $null = Update-MetraAttentionMemory -Queue @($q1) -CoveredKinds @('ticket') -ScanMode 'full' -MetraRoot $tempRoot
            $still = @(Get-MetraAttentionMemory -MetraRoot $tempRoot | Select-Object -ExpandProperty items | Where-Object { $_.key -eq 'ticket:999001' })[0]
            $still.state | Should -Be 'dismissed'

            $ticket.Updated = '2026-08-06T10:00:00'
            $q2 = ConvertTo-MetraTicketAttentionQueueItem -Ticket $ticket
            $null = Update-MetraAttentionMemory -Queue @($q2) -CoveredKinds @('ticket') -ScanMode 'full' -MetraRoot $tempRoot
            $again = @(Get-MetraAttentionMemory -MetraRoot $tempRoot | Select-Object -ExpandProperty items | Where-Object { $_.key -eq 'ticket:999001' })[0]
            $again.state | Should -Be 'active'
            [string]$again.evidenceSignature | Should -Not -Be $sig1
            $again.key | Should -Be 'ticket:999001'
        }
    }

    It 'summarizes ticket Attention in plain language' {
        InModuleScope Metra {
            $s = Get-MetraAttentionPlainSummary -Project 'TicketTracker' -Kind 'ticket' -Content 'Ticket 123456 needs triage - High priority'
            $s | Should -Match '123456'
            $s | Should -Match 'triage'
        }
    }
}
