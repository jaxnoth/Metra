# Metra.DeskFamiliarity.Tests.ps1
Describe 'Desk familiarity ledger' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\scripts\Metra.psd1') -Force
    }

    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive ('metra-desk-fam-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:TestRoot 'docs') -Force | Out-Null
    }

    It 'show uses Warming default when ledger missing' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            $r = Show-MetraDeskFamiliarity -MetraRoot $TestRoot
            $r.DurableBand | Should -Be 'Warming'
            $r.Score | Should -Be 3
            $r.WarmingDefaultActive | Should -Be $true
            $r.LedgerExists | Should -Be $false
            Test-Path -LiteralPath $r.LedgerPath | Should -Be $false
        }
    }

    It 'ticket-only analyze-nudge is neutral and writes nothing' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            $r = Invoke-MetraDeskFamiliarityAnalyzeNudge -SessionPeak Familiar -SessionFloor Warming -Direction Up -Sustained -TicketOnly -MetraRoot $TestRoot
            $r.Outcome | Should -Be 'neutral'
            $r.Reason | Should -Be 'ticket-only-excluded'
            $r.WroteLedger | Should -Be $false
        }
    }

    It 'insufficient without -Sustained' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            $r = Invoke-MetraDeskFamiliarityAnalyzeNudge -SessionPeak Warming -SessionFloor Warming -Direction Up -MetraRoot $TestRoot
            $r.Outcome | Should -Be 'insufficient-pattern'
            $r.WroteLedger | Should -Be $false
        }
    }

    It 'adjacent up nudges +1 and rate-limits same UTC day' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            $r1 = Invoke-MetraDeskFamiliarityAnalyzeNudge -SessionPeak Warming -SessionFloor Warming -Direction Up -Sustained -Note 'sustained collaborative project brainstorming' -MetraRoot $TestRoot
            $r1.Outcome | Should -Be 'nudged-up'
            $r1.Score | Should -Be 4
            $r1.WroteLedger | Should -Be $true

            $r2 = Invoke-MetraDeskFamiliarityAnalyzeNudge -SessionPeak Familiar -SessionFloor Warming -Direction Up -Sustained -Note 'second attempt same day' -MetraRoot $TestRoot
            $r2.Outcome | Should -Be 'rate-limited'
            $r2.Score | Should -Be 4
        }
    }

    It 'two-band outlier nudges after prior evidence-only day' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            $prior = [pscustomobject]@{
                version      = 1
                durableBand  = 'Cold'
                score        = 1
                updatedUtc   = '2026-08-01T12:00:00.0000000Z'
                lastNudgeUtc = $null
                evidence     = @(
                    [pscustomobject]@{
                        utc          = '2026-08-01T12:00:00.0000000Z'
                        sessionPeak  = 'Familiar'
                        sessionFloor = 'Warming'
                        direction    = 'up'
                        qualifying   = $true
                        note         = 'sustained collaborative project brainstorming'
                        outcome      = 'evidence-only'
                    }
                )
            }
            Save-MetraDeskFamiliarityLedger -Ledger $prior -MetraRoot $TestRoot

            $r = Invoke-MetraDeskFamiliarityAnalyzeNudge -SessionPeak Familiar -SessionFloor Warming -Direction Up -Sustained -Note 'sustained collaborative project brainstorming' -MetraRoot $TestRoot
            $r.Outcome | Should -Be 'nudged-up'
            $r.Score | Should -Be 2
        }
    }

    It 'two-band outlier first day is evidence-only' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            $seed = [pscustomobject]@{
                version      = 1
                durableBand  = 'Cold'
                score        = 1
                updatedUtc   = '2026-08-01T12:00:00.0000000Z'
                lastNudgeUtc = $null
                evidence     = @()
            }
            Save-MetraDeskFamiliarityLedger -Ledger $seed -MetraRoot $TestRoot

            $r = Invoke-MetraDeskFamiliarityAnalyzeNudge -SessionPeak Familiar -SessionFloor Warming -Direction Up -Sustained -Note 'sustained collaborative project brainstorming' -MetraRoot $TestRoot
            $r.Outcome | Should -Be 'evidence-only'
            $r.Score | Should -Be 1
            $r.Reason | Should -Be 'two-band-outlier-first-day'
        }
    }

    It 'corrupt ledger fails closed without overwrite' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            $paths = Get-MetraDeskFamiliarityPaths -MetraRoot $TestRoot
            [System.IO.File]::WriteAllText($paths.LedgerPath, '{ not json', [System.Text.UTF8Encoding]::new($false))
            $show = Show-MetraDeskFamiliarity -MetraRoot $TestRoot
            $show.LedgerCorrupt | Should -Be $true
            $show.WarmingDefaultActive | Should -Be $true
            $show.DurableBand | Should -Be 'Warming'

            $r = Invoke-MetraDeskFamiliarityAnalyzeNudge -SessionPeak Familiar -SessionFloor Warming -Direction Up -Sustained -MetraRoot $TestRoot
            $r.Outcome | Should -Be 'neutral'
            $r.Reason | Should -Be 'ledger-corrupt-fail-closed'
            $r.WroteLedger | Should -Be $false
            ([System.IO.File]::ReadAllText($paths.LedgerPath)) | Should -Be '{ not json'
        }
    }

    It 'score stays within 0..8' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            $high = [pscustomobject]@{
                version      = 1
                durableBand  = 'Familiar'
                score        = 8
                updatedUtc   = '2026-08-01T12:00:00.0000000Z'
                lastNudgeUtc = '2026-08-01T12:00:00.0000000Z'
                evidence     = @()
            }
            Save-MetraDeskFamiliarityLedger -Ledger $high -MetraRoot $TestRoot
            $r = Invoke-MetraDeskFamiliarityAnalyzeNudge -SessionPeak Familiar -SessionFloor Familiar -Direction Up -Sustained -Note 'at ceiling' -MetraRoot $TestRoot
            $r.Score | Should -Be 8
            $r.Outcome | Should -Be 'nudged-up'
        }
    }

    It 'accepts lowercase band names through resolve and analyze-nudge CLI' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            (Resolve-MetraDeskFamiliarityBand -Band 'warming') | Should -Be 'Warming'
            (Resolve-MetraDeskFamiliarityBand -Band 'familiar') | Should -Be 'Familiar'
            (Get-MetraDeskFamiliarityBandIndex -Band 'cold') | Should -Be 0
            (Test-MetraDeskFamiliarityBandName -Band 'WARMING') | Should -Be $true

            $r = Invoke-MetraDeskFamiliarityCommand -Subcommand analyze-nudge -ArgsRest @(
                '-SessionPeak', 'familiar',
                '-SessionFloor', 'warming',
                '-Direction', 'up',
                '-Sustained',
                '-Note', 'lowercase band acceptance'
            ) -MetraRoot $TestRoot
            $r.Outcome | Should -Be 'nudged-up'
            $r.Score | Should -Be 4
        }
    }

    It 'malformed evidence timestamps do not throw on show' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            $bad = [pscustomobject]@{
                version      = 1
                durableBand  = 'Warming'
                score        = 3
                updatedUtc   = 'not-a-date'
                lastNudgeUtc = 'also-bad'
                evidence     = @()
            }
            Save-MetraDeskFamiliarityLedger -Ledger $bad -MetraRoot $TestRoot
            $show = Show-MetraDeskFamiliarity -MetraRoot $TestRoot
            $show.LastNudgeUtcDate | Should -Be $null
            $show.Score | Should -Be 3
        }
    }

    It 'missing value for -Direction throws a clear contract error' {
        InModuleScope Metra -Parameters @{ TestRoot = $script:TestRoot } {
            { Invoke-MetraDeskFamiliarityCommand -Subcommand analyze-nudge -ArgsRest @(
                    '-SessionPeak', 'Warming',
                    '-SessionFloor', 'Warming',
                    '-Direction'
                ) -MetraRoot $TestRoot } | Should -Throw -ExpectedMessage '*Missing value for -Direction*'
        }
    }
}
