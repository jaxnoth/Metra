# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Capture.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Capture ledger read/write' {
    It 'missing ledger returns empty' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-cap-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                @(Get-MetraCaptureLedger -MetraRoot $root) | Should -HaveCount 0
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'sorts by at descending regardless of file order' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-cap-" + [guid]::NewGuid().ToString('n'))
            $docs = Join-Path $root 'docs'
            New-Item -ItemType Directory -Path $docs -Force | Out-Null
            try {
                $payload = [ordered]@{
                    schemaVersion = 1
                    items         = @(
                        [PSCustomObject]@{ id = 'old'; at = '2026-01-01T00:00:00.0000000Z'; status = 'candidate'; summary = 'old' }
                        [PSCustomObject]@{ id = 'new'; at = '2026-08-11T12:00:00.0000000Z'; status = 'candidate'; summary = 'new' }
                    )
                }
                $path = Join-Path $docs 'ops-capture.local.json'
                [System.IO.File]::WriteAllText($path, (($payload | ConvertTo-Json -Depth 6) + "`r`n"))
                $items = @(Get-MetraCaptureLedger -MetraRoot $root -Limit 10 -Status all)
                $items[0].id | Should -Be 'new'
                $items[1].id | Should -Be 'old'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'atomic save leaves a readable ledger' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-cap-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                Save-MetraCaptureLedger -MetraRoot $root -Items @(
                    [PSCustomObject]@{ id = 'a'; at = (Get-Date).ToString('o'); status = 'candidate'; summary = 'x' }
                )
                $path = Get-MetraCaptureLedgerPath -MetraRoot $root
                Test-Path -LiteralPath $path | Should -BeTrue
                Test-Path -LiteralPath "$path.tmp" | Should -BeFalse
                @(Get-MetraCaptureLedger -MetraRoot $root).Count | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'corrupt ledger returns empty' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-cap-" + [guid]::NewGuid().ToString('n'))
            $docs = Join-Path $root 'docs'
            New-Item -ItemType Directory -Path $docs -Force | Out-Null
            try {
                Set-Content -LiteralPath (Join-Path $docs 'ops-capture.local.json') -Value '{ not json' -NoNewline
                @(Get-MetraCaptureLedger -MetraRoot $root) | Should -HaveCount 0
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Capture immutability and promote gates' {
    It 'rejects derivedFrom mutation and dismisses candidates' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-cap-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                $derived = New-MetraCaptureDerivedFrom -Type manual
                $cap = Add-MetraCaptureItem -Summary 'park this' -Source manual -DerivedFrom $derived -MetraRoot $root
                { Update-MetraCaptureItem -Id $cap.id -DerivedFrom ([PSCustomObject]@{ type = 'askTurn' }) -MetraRoot $root } |
                    Should -Throw '*immutable*'
                $dismissed = Dismiss-MetraCaptureItem -Id $cap.id -MetraRoot $root
                $dismissed.status | Should -Be 'dismissed'
                { Invoke-MetraCapturePromote -Id $cap.id -Home FutureDevelopment -MetraRoot $root } |
                    Should -Throw '*dismissed*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'refuses TicketTracker and ProjectAgents promote' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-cap-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                $derived = New-MetraCaptureDerivedFrom -Type manual
                $tt = Add-MetraCaptureItem -Summary 'ticket note' -Source manual -DerivedFrom $derived `
                    -SuggestedHome TicketTracker -SuggestedProject TicketTracker -MetraRoot $root
                { Invoke-MetraCapturePromote -Id $tt.id -Home TicketTracker -MetraRoot $root } |
                    Should -Throw '*suggest-only*'
                $ag = Add-MetraCaptureItem -Summary 'agents note' -Source manual -DerivedFrom $derived `
                    -SuggestedHome ProjectAgents -SuggestedProject Trivia -MetraRoot $root
                { Invoke-MetraCapturePromote -Id $ag.id -Home ProjectAgents -MetraRoot $root } |
                    Should -Throw '*suggest-only*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'ProjectBacklog promote without local authority fails' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-cap-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                Mock Test-MetraCaptureRegisteredProject {
                    [PSCustomObject]@{ Name = 'Trivia'; Path = (Join-Path $root 'Trivia'); Root = 'work' }
                }
                $derived = New-MetraCaptureDerivedFrom -Type manual
                $cap = Add-MetraCaptureItem -Summary 'todo' -Source manual -DerivedFrom $derived `
                    -SuggestedHome ProjectBacklog -SuggestedProject Trivia -MetraRoot $root
                { Invoke-MetraCapturePromote -Id $cap.id -Home ProjectBacklog -Project Trivia `
                        -HasLocalAuthority $false -MetraRoot $root } |
                    Should -Throw '*local Metra session*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Capture suggestion and path safety' {
    It 'passes MetraRoot into suggestion from Add-MetraCaptureItem' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-cap-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                $script:capSuggestRoots = @()
                Mock Resolve-MetraCaptureSuggestedHome {
                    param($Text, $Where, $HomeId, $MetraRoot)
                    $script:capSuggestRoots += [string]$MetraRoot
                    [PSCustomObject]@{
                        suggestedHome       = 'FutureDevelopment'
                        suggestedProject    = 'Metra'
                        confidence          = 'thin'
                        reason              = 'mock'
                        rootLabel           = 'Metra'
                        requiresCrossRoot   = $false
                        requiresHostSession = $false
                    }
                }
                $derived = New-MetraCaptureDerivedFrom -Type manual
                $null = Add-MetraCaptureItem -Summary 'x' -Source manual -DerivedFrom $derived -MetraRoot $root
                $script:capSuggestRoots | Should -Contain $root
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Variable -Name capSuggestRoots -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }

    It 'matches registered project names case-insensitively' {
        InModuleScope Metra {
            Mock Get-MetraProjects {
                @([PSCustomObject]@{ Name = 'Trivia'; Path = 'C:\Projects\Trivia'; Root = 'work' })
            }
            Mock Get-MetraProjectRegistry { [PSCustomObject]@{ projects = @() } }
            Mock Get-MetraHomeDestinationName { 'Metra' }
            $hit = Test-MetraCaptureRegisteredProject -Name 'trivia' -MetraRoot 'C:\Projects\_meta'
            $hit.Name | Should -Be 'Trivia'
        }
    }

    It 'cross-root flags reject _meta2 prefix false positive' {
        InModuleScope Metra {
            Mock Get-MetraHomeDestinationName { 'Metra' }
            Mock Get-MetraProjects {
                @([PSCustomObject]@{ Name = 'Metra'; Path = 'C:\Projects\_meta'; Root = 'work' })
            }
            $flags = Get-MetraCaptureCrossRootFlags `
                -ProjectInfo ([PSCustomObject]@{ Name = 'Other'; Path = 'C:\Projects\_meta2\Other'; Root = 'personal' }) `
                -MetraRoot 'C:\Projects\_meta'
            $flags.requiresCrossRoot | Should -BeTrue
        }
    }

    It 'flattens multiline summaries in TODO stub and drops Bing plan wording' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-cap-" + [guid]::NewGuid().ToString('n'))
            $proj = Join-Path $root 'Proj'
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            New-Item -ItemType Directory -Path $proj -Force | Out-Null
            try {
                $todo = Add-MetraProjectBacklogCaptureStub -ProjectPath $proj `
                    -Summary "line one`r`nline two" -Lineage 'manual' -CaptureId 'abc'
                $text = Get-Content -LiteralPath $todo -Raw
                $text | Should -Match 'line one line two'
                $text | Should -Not -Match '(?m)^- \[ \] .*`r`nline two'

                $null = Add-MetraFutureDevelopmentCaptureStub -Summary "a`nb" -CaptureId 'c1' -MetraRoot $root
                $fd = Get-Content -LiteralPath (Join-Path $root 'docs\Future-Development.local.md') -Raw
                $fd | Should -Match 'operator review required'
                $fd | Should -Not -Match 'Bing plan'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
