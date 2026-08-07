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
            $s | Should -Match '^Ticket 123456'
            $s | Should -Match 'triage'

            $withSubject = Get-MetraAttentionPlainSummary -Project 'TicketTracker' -Kind 'ticket' -Content 'Ticket 123456: Brightspace grades not syncing'
            $withSubject | Should -Be 'Ticket 123456: Brightspace grades not syncing'
        }
    }

    It 'carries ticket subject, status, and priority into the Attention item' {
        InModuleScope Metra {
            $ticket = [PSCustomObject]@{
                Id       = '1034794'
                Subject  = 'Brightspace grades not syncing'
                Status   = 'Open'
                Priority = 'High'
                Customer = 'Jane Doe'
                Assignee = 'Stephen'
                Updated  = (Get-Date).ToString('o')
            }
            $q = ConvertTo-MetraTicketAttentionQueueItem -Ticket $ticket
            $q.content | Should -Be 'Ticket 1034794: Brightspace grades not syncing'
            $q.detail | Should -Match 'Open'
            $q.detail | Should -Match 'High priority'
            $q.detail | Should -Match 'Jane Doe'
            $q.detail | Should -Match 'updated '
            $q.statusRank | Should -Be 0
            $q.ticketStatus | Should -Be 'Open'
            $q.command | Should -Be '.\TicketTracker.ps1 brief 1034794'
        }
    }

    It 'defaults to no cap and no iSupport sync during desk snapshots' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-ticketcfg-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                $cfg = Get-MetraTicketWatchConfig -MetraRoot $root
                $cfg.top | Should -Be 0
                $cfg.syncOnScan | Should -BeTrue
                $cfg.syncOnSnapshot | Should -BeFalse

                @{ syncOnSnapshot = $true; top = 25 } | ConvertTo-Json |
                    Set-Content -LiteralPath (Join-Path $root 'docs\ticket-watch.local.json')
                $cfg2 = Get-MetraTicketWatchConfig -MetraRoot $root
                $cfg2.syncOnSnapshot | Should -BeTrue
                $cfg2.top | Should -Be 25
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'does not auto-close tickets dropped by a list cap' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-ticketcap-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                $a = ConvertTo-MetraTicketAttentionQueueItem -Ticket ([PSCustomObject]@{
                        Id = '111111'; Subject = 'First'; Status = 'Open'; Updated = (Get-Date).ToString('o')
                    })
                $b = ConvertTo-MetraTicketAttentionQueueItem -Ticket ([PSCustomObject]@{
                        Id = '222222'; Subject = 'Second'; Status = 'Open'; Updated = (Get-Date).ToString('o')
                    })

                $null = Update-MetraAttentionMemory -Queue @($a, $b) -CoveredKinds @('ticket') -ScanMode full -MetraRoot $root

                # Second scan sees only one ticket because the list was capped.
                $mem = Update-MetraAttentionMemory -Queue @($a) -CoveredKinds @() -ScanMode full -MetraRoot $root
                $dropped = @($mem.items) | Where-Object { $_.key -eq 'ticket:222222' } | Select-Object -First 1
                $dropped.state | Should -Be 'active'

                # Genuine full coverage still auto-closes what is gone.
                $mem2 = Update-MetraAttentionMemory -Queue @($a) -CoveredKinds @('ticket') -ScanMode full -MetraRoot $root
                $gone = @($mem2.items) | Where-Object { $_.key -eq 'ticket:222222' } | Select-Object -First 1
                $gone.state | Should -Be 'autoClosed'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'stores operator feedback on Attention and includes it in Ask prompts' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-attn-note-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                Mock Write-MetraTicketAttentionLocalNote { }
                $qi = ConvertTo-MetraTicketAttentionQueueItem -Ticket ([PSCustomObject]@{
                        Id = '1035509'; Subject = 'Folio notifications'; Status = 'Open'
                        Priority = '1'; Customer = 'A'; Assignee = 'S'
                        Updated = (Get-Date).ToString('o')
                    })
                $null = Update-MetraAttentionMemory -Queue @($qi) -CoveredKinds @('ticket') -ScanMode full -MetraRoot $root
                $null = Invoke-MetraAttentionMutation -Key 'ticket:1035509' -Action note -Note 'Email says resolved.' -MetraRoot $root
                $mem = Get-MetraAttentionMemory -MetraRoot $root
                $item = @($mem.items) | Where-Object { $_.key -eq 'ticket:1035509' } | Select-Object -First 1
                $item.note | Should -Be 'Email says resolved.'
                $view = ConvertTo-MetraDeskAttentionView -MemItem $item -RankIndex 0 -ActiveCount 1
                $view.askPrompt | Should -Match 'Email says resolved'
                $view.askPrompt | Should -Match 'Operator feedback'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'ranks Waiting on Customer below Open tickets' {
        InModuleScope Metra {
            (Get-MetraTicketAttentionStatusRank -Status 'Open') |
                Should -BeLessThan (Get-MetraTicketAttentionStatusRank -Status 'Waiting on Customer')

            $open = ConvertTo-MetraTicketAttentionQueueItem -Ticket ([PSCustomObject]@{
                    Id = '1'; Subject = 'Open work'; Status = 'Open'; Priority = '2'
                    Customer = 'A'; Assignee = 'S'; Updated = (Get-Date).ToString('o')
                })
            $waiting = ConvertTo-MetraTicketAttentionQueueItem -Ticket ([PSCustomObject]@{
                    Id = '2'; Subject = 'Waiting work'; Status = 'Waiting on Customer'; Priority = '1'
                    Customer = 'B'; Assignee = 'S'; Updated = (Get-Date).AddHours(1).ToString('o')
                })
            $mem = [PSCustomObject]@{
                items = @(
                    [PSCustomObject]@{
                        key = 'ticket:2'; kind = 'ticket'; content = $waiting.content; detail = $waiting.detail
                        ticketStatus = $waiting.ticketStatus; statusRank = $waiting.statusRank
                        confidence = 'fresh'; state = 'active'; notRecheckedSince = $null
                    }
                    [PSCustomObject]@{
                        key = 'ticket:1'; kind = 'ticket'; content = $open.content; detail = $open.detail
                        ticketStatus = $open.ticketStatus; statusRank = $open.statusRank
                        confidence = 'fresh'; state = 'active'; notRecheckedSince = $null
                    }
                )
            }
            $ranked = Get-MetraAttentionActiveItems -Memory $mem
            $ranked[0].key | Should -Be 'ticket:1'
            $ranked[1].key | Should -Be 'ticket:2'
        }
    }

    It 'enriches thin ticket Attention rows at desk view time' {
        InModuleScope Metra {
            $qi = ConvertTo-MetraTicketAttentionQueueItem -Ticket ([PSCustomObject]@{
                    Id       = '1034794'
                    Subject  = 'Request to expedite patch install'
                    Status   = 'Waiting on Customer'
                    Priority = '1'
                    Customer = 'Yeoman, Angie'
                    Assignee = 'Swan, Stephen'
                    Updated  = '2026-07-23T13:31:32'
                })
            Mock Update-MetraTicketAttentionDisplayFields {
                param($MemItem)
                $MemItem.content = [string]$qi.content
                if ($MemItem.PSObject.Properties['detail']) { $MemItem.detail = [string]$qi.detail }
                else { $MemItem | Add-Member -NotePropertyName detail -NotePropertyValue ([string]$qi.detail) -Force }
                $MemItem
            }

            $mem = [PSCustomObject]@{
                key               = 'ticket:1034794'
                project           = 'TicketTracker'
                kind              = 'ticket'
                content           = 'Ticket 1034794 needs triage - 1 priority'
                detail            = ''
                command           = '.\TicketTracker.ps1 brief 1034794'
                source            = 'TicketTracker'
                confidence        = 'fresh'
                state             = 'active'
                evidenceSignature = 'ticket:1034794|updated:|status:'
                firstSeenAt       = (Get-Date).ToString('o')
                lastSeenAt        = (Get-Date).ToString('o')
                lastScanMode      = 'full'
                notRecheckedSince = $null
                snoozedUntil      = $null
                closedAt          = $null
                closedBy          = ''
                note              = ''
            }
            $view = ConvertTo-MetraDeskAttentionView -MemItem $mem -RankIndex 0 -ActiveCount 1
            $view.summary | Should -Match 'Request to expedite'
            $view.detail | Should -Match 'Waiting on Customer'
            $view.detail | Should -Match 'Priority 1'
            $view.detail | Should -Match 'Yeoman'
        }
    }

    It 'points ticket Attention at TicketTracker instead of the editor' {
        InModuleScope Metra {
            $mem = [PSCustomObject]@{
                key               = 'ticket:1034794'
                project           = 'TicketTracker'
                kind              = 'ticket'
                content           = 'Ticket 1034794: Brightspace grades not syncing'
                detail            = 'Open - High priority - for Jane Doe'
                command           = '.\TicketTracker.ps1 brief 1034794'
                source            = 'TicketTracker'
                confidence        = 'fresh'
                state             = 'active'
                evidenceSignature = 'ticket:1034794|updated:|status:Open'
                firstSeenAt       = (Get-Date).ToString('o')
                lastSeenAt        = (Get-Date).ToString('o')
                lastScanMode      = 'full'
                notRecheckedSince = $null
                snoozedUntil      = $null
                closedAt          = $null
                closedBy          = ''
                note              = ''
            }
            $view = ConvertTo-MetraDeskAttentionView -MemItem $mem -RankIndex 0 -ActiveCount 3
            $view.detail | Should -Be 'Open - High priority - for Jane Doe'
            $view.resolveCopy | Should -Match 'brief 1034794'
            $view.resolveCopy | Should -Not -Match 'in your editor'
            $view.askPrompt | Should -Match 'brief 1034794'
            $view.doneWhen | Should -Match 'iSupport'
        }
    }

    It 'ranks ticket Attention ahead of git for Ops Next' {
        InModuleScope Metra {
            (Get-MetraAttentionKindPriority -Kind 'ticket') | Should -BeLessThan (Get-MetraAttentionKindPriority -Kind 'git')
            $git = Get-MetraAttentionPlainSummary -Project 'TicketTracker' -Kind 'git' -Content 'TicketTracker - git dirty 1'
            $git | Should -Match '^Git:'
            $git | Should -Match 'TicketTracker'
        }
    }
}
