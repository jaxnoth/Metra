# Pester: Attention Project vs Reconcile (Ops desk payload mutation boundary).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$module = Join-Path (Split-Path $here -Parent) 'scripts\Metra.psd1'
Import-Module $module -Force

Describe 'Attention Project vs Reconcile' {
    It 'Project does not write attention-memory.json (mtime and fingerprint stable)' {
        InModuleScope Metra {
            $tempRoot = Join-Path $TestDrive 'attn-project'
            $ops = Join-Path $tempRoot 'ops'
            New-Item -ItemType Directory -Path $ops -Force | Out-Null
            $attnPath = Join-Path $ops 'attention-memory.json'
            $seed = [PSCustomObject]@{
                version   = 1
                updatedAt = '2020-01-01T00:00:00.0000000Z'
                items     = @(
                    [PSCustomObject]@{
                        key               = 'drift:demo'
                        project           = 'Metra'
                        kind              = 'drift'
                        source            = 'snapshot'
                        content           = 'demo drift'
                        detail            = ''
                        ticketStatus      = ''
                        ticketAssignee    = ''
                        assigneeRank      = $null
                        assignedToMe      = $false
                        statusRank        = $null
                        command           = '.\metra.ps1 audit'
                        evidenceSignature = 'sig-demo'
                        state             = 'active'
                        confidence        = 'fresh'
                        firstSeenAt       = '2020-01-01T00:00:00.0000000Z'
                        lastSeenAt        = '2020-01-01T00:00:00.0000000Z'
                        lastScanMode      = 'quick'
                        notRecheckedSince = $null
                        snoozedUntil      = $null
                        closedAt          = $null
                        closedBy          = ''
                        note              = ''
                        events            = @()
                    }
                )
            }
            ($seed | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $attnPath -Encoding utf8

            $snap = [PSCustomObject]@{
                generatedAt   = (Get-Date).ToString('o')
                mode          = 'quick'
                gitChecked    = $false
                verifyChecked = $false
                projectCount  = 0
                driftCount    = 0
                driftProjects = 0
                missingAgents = 0
                todos         = @()
                projects      = @()
                decisions     = [PSCustomObject]@{ candidates = @() }
                contract      = [PSCustomObject]@{ candidates = @() }
            }

            Mock Get-MetraOpsAttentionPath { $attnPath }
            Mock Get-MetraDeskPreferences {
                [PSCustomObject]@{
                    deskMode = 'normal'; machineRole = 'hq'; opsPort = 7380
                    browserHost = 'localhost'; preferFriendlyUrl = $false; bindTailscale = $false
                    attentionVisibleCount = 1; editorCommand = 'auto'; ticketWatchEnabled = $false; updatedAt = $null
                }
            }
            Mock Get-MetraTicketWatchConfig { [PSCustomObject]@{ autoScanIntervalMinutes = 5 } }
            Mock Get-MetraDeskAskSessionSummaries { @() }
            Mock Get-MetraCaptureLedger { @() }
            Mock Get-MetraAskCapability {
                [PSCustomObject]@{
                    enabled = $false; selected = $false; available = $false
                    engine = ''; providerLabel = ''; reason = 'test'
                }
            }
            Mock Resolve-MetraOpsEditor {
                [PSCustomObject]@{ Preference = 'auto'; Kind = 'none'; Label = 'none' }
            }
            Mock Test-MetraCanvasSnapshotStale { $false }

            $beforeHash = (Get-FileHash -LiteralPath $attnPath -Algorithm SHA256).Hash
            $beforeMtime = (Get-Item -LiteralPath $attnPath).LastWriteTimeUtc
            $null = ConvertTo-MetraDeskPayload -Snapshot $snap -MetraRoot $tempRoot
            Start-Sleep -Milliseconds 50
            $afterHash = (Get-FileHash -LiteralPath $attnPath -Algorithm SHA256).Hash
            $afterMtime = (Get-Item -LiteralPath $attnPath).LastWriteTimeUtc
            $afterHash | Should -Be $beforeHash
            $afterMtime | Should -Be $beforeMtime
        }
    }

    It 'Reconcile persists new snapshot-derived observations' {
        InModuleScope Metra {
            $tempRoot = Join-Path $TestDrive 'attn-reconcile'
            $ops = Join-Path $tempRoot 'ops'
            New-Item -ItemType Directory -Path $ops -Force | Out-Null
            $attnPath = Join-Path $ops 'attention-memory.json'

            $snap = [PSCustomObject]@{
                generatedAt   = (Get-Date).ToString('o')
                mode          = 'quick'
                gitChecked    = $false
                verifyChecked = $false
                projectCount  = 0
                driftCount    = 0
                driftProjects = 0
                missingAgents = 0
                todos         = @(
                    [PSCustomObject]@{
                        id = 'drift:from-snap'; project = 'Metra'; content = 'new drift'; kind = 'drift'
                    }
                )
                projects      = @()
                decisions     = [PSCustomObject]@{ candidates = @() }
                contract      = [PSCustomObject]@{ candidates = @() }
            }

            Mock Get-MetraOpsAttentionPath { $attnPath }
            Mock Get-MetraDeskPreferences {
                [PSCustomObject]@{
                    deskMode = 'normal'; machineRole = 'hq'; opsPort = 7380
                    browserHost = 'localhost'; preferFriendlyUrl = $false; bindTailscale = $false
                    attentionVisibleCount = 1; editorCommand = 'auto'; ticketWatchEnabled = $false; updatedAt = $null
                }
            }
            Mock Get-MetraTicketWatchConfig { [PSCustomObject]@{ autoScanIntervalMinutes = 5 } }
            Mock Get-MetraDeskAskSessionSummaries { @() }
            Mock Get-MetraCaptureLedger { @() }
            Mock Get-MetraAskCapability {
                [PSCustomObject]@{
                    enabled = $false; selected = $false; available = $false
                    engine = ''; providerLabel = ''; reason = 'test'
                }
            }
            Mock Resolve-MetraOpsEditor {
                [PSCustomObject]@{ Preference = 'auto'; Kind = 'none'; Label = 'none' }
            }
            Mock Test-MetraCanvasSnapshotStale { $false }

            $null = ConvertTo-MetraDeskPayload -Snapshot $snap -Reconcile -MetraRoot $tempRoot
            Test-Path -LiteralPath $attnPath | Should -BeTrue
            $mem = Get-Content -LiteralPath $attnPath -Raw | ConvertFrom-Json
            @($mem.items).Count | Should -BeGreaterThan 0
        }
    }

    It 'Set-MetraAttentionMemory skips write when items unchanged' {
        InModuleScope Metra {
            $attnPath = Join-Path $TestDrive 'attention-memory-skip.json'
            Mock Get-MetraOpsAttentionPath { $attnPath }
            $memory = [PSCustomObject]@{
                version   = 1
                updatedAt = $null
                items     = @(
                    [PSCustomObject]@{
                        key = 'k1'; project = 'P'; kind = 'drift'; source = 'snapshot'
                        content = 'c'; detail = ''; ticketStatus = ''; ticketAssignee = ''
                        assigneeRank = $null; assignedToMe = $false; statusRank = $null
                        command = 'x'; evidenceSignature = 's'; state = 'active'; confidence = 'fresh'
                        firstSeenAt = '2020-01-01T00:00:00Z'; lastSeenAt = '2020-01-01T00:00:00Z'
                        lastScanMode = 'full'; notRecheckedSince = $null; snoozedUntil = $null
                        closedAt = $null; closedBy = ''; note = ''; events = @()
                    }
                )
            }
            $null = Set-MetraAttentionMemory -Memory $memory -MetraRoot $TestDrive
            $h1 = (Get-FileHash -LiteralPath $attnPath -Algorithm SHA256).Hash
            $m1 = (Get-Item -LiteralPath $attnPath).LastWriteTimeUtc
            Start-Sleep -Milliseconds 40
            # Second write uses disk-normalized items (same path Update→Set takes on no-op reconcile).
            $reloaded = Get-MetraAttentionMemory -MetraRoot $TestDrive
            $null = Set-MetraAttentionMemory -Memory $reloaded -MetraRoot $TestDrive
            $h2 = (Get-FileHash -LiteralPath $attnPath -Algorithm SHA256).Hash
            $m2 = (Get-Item -LiteralPath $attnPath).LastWriteTimeUtc
            $h2 | Should -Be $h1
            $m2 | Should -Be $m1
        }
    }
}
