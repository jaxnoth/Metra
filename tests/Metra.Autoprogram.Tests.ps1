# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Autoprogram.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    # M2: domain lives in AutoProgram; Metra façade still loads for CLI/adapters.
    Import-Module (Join-Path $metraRoot 'modules\AutoProgram\AutoProgram.psd1') -Force
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Autoprogram transitions (Phase A)' {
    It 'allows @new -> queued and queued -> blocked only' {
        InModuleScope AutoProgram {
            Test-MetraAutoprogramTransition -From '@new' -To 'queued' | Should -BeTrue
            Test-MetraAutoprogramTransition -From 'queued' -To 'blocked' | Should -BeTrue
            Test-MetraAutoprogramTransition -From 'queued' -To 'accepted' | Should -BeFalse
            Test-MetraAutoprogramTransition -From 'blocked' -To 'queued' | Should -BeFalse
        }
    }
}

Describe 'Autoprogram journal append-only' {
    It 'appends journal lines without rewriting prior entries' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraAutoprogramLayout -Root $root
                Add-MetraAutoprogramJournalEntry -Root $root -Entry @{ itemId = 'AP-1'; to = 'queued' }
                Add-MetraAutoprogramJournalEntry -Root $root -Entry @{ itemId = 'AP-1'; to = 'blocked' }
                $path = Get-MetraAutoprogramJournalPath -Root $root
                $lines = @([System.IO.File]::ReadAllLines($path))
                $lines.Count | Should -Be 2
                $first = $lines[0]
                Add-MetraAutoprogramJournalEntry -Root $root -Entry @{ itemId = 'AP-2'; to = 'queued' }
                $linesAfter = @([System.IO.File]::ReadAllLines($path))
                $linesAfter[0] | Should -Be $first
                $linesAfter.Count | Should -Be 3
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Autoprogram enqueue and block' {
    It 'creates queued item and blocks with journal pairing' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                $cand = [PSCustomObject]@{
                    id             = 'CAND-20260831-0001'
                    summary        = 'Test item'
                    source         = [PSCustomObject]@{ type = 'operator' }
                    project        = [PSCustomObject]@{
                        registryName = 'Metra'; root = (Get-AutoProgramHostRoot)
                        routingConfidence = 0.99; routingEvidence = 'test'
                    }
                    classification = @{
                        reversibility = 'code'; crossRoot = $false; productionTouch = $false
                        externalSideEffect = $false; manualTestClass = 'none'
                    }
                    scores         = [PSCustomObject]@{
                        impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5
                        dependencyValue = 2; total = 20; rubricVersion = 'triage-v1'
                    }
                    contract       = [PSCustomObject]@{
                        objective = 'x'; allowedPaths = @('tests'); forbiddenPaths = @()
                        doneWhen = @('pass'); verifyCommands = @('.\metra.ps1 verify')
                    }
                    eligible       = $true
                    ineligibleReasons = @()
                }
                $item = New-MetraAutoprogramQueueItemFromCandidate -Root $root -Candidate $cand
                $item.status | Should -Be 'queued'
                $item.id | Should -Match '^AP-\d{8}-\d{4}$'

                $blocked = Invoke-MetraAutoprogramStateChange -Root $root -ItemId $item.id -From 'queued' -To 'blocked' -Reason 'test'
                $blocked.status | Should -Be 'blocked'

                { Invoke-MetraAutoprogramStateChange -Root $root -ItemId $item.id -From 'queued' -To 'blocked' } |
                    Should -Throw '*expected*queued*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Autoprogram deterministic scoring' {
    It 'returns the same total for the same inputs' {
        InModuleScope AutoProgram {
            $classification = @{
                reversibility = 'code'; crossRoot = $false; productionTouch = $false
                externalSideEffect = $false; manualTestClass = 'none'
            }
            $scoresIn = @{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2 }
            $project = [PSCustomObject]@{ routingConfidence = 0.99 }
            $a = Measure-MetraAutoprogramTriageScore -Classification $classification -Scores $scoresIn -Project $project
            $b = Measure-MetraAutoprogramTriageScore -Classification $classification -Scores $scoresIn -Project $project
            $a.total | Should -Be $b.total
            $a.rubricVersion | Should -Be 'triage-v1'
        }
    }
}

Describe 'Autoprogram eligibility' {
    It 'rejects capture-like items without contract' {
        InModuleScope AutoProgram {
            $classification = [PSCustomObject]@{
                reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false
            }
            $project = [PSCustomObject]@{ routingConfidence = 0.0 }
            $contract = [PSCustomObject]@{ verifyCommands = @(); doneWhen = @() }
            $elig = Test-MetraAutoprogramEligibility -Classification $classification -Project $project -Contract $contract
            $elig.eligible | Should -BeFalse
            $elig.reasons | Should -Contain 'missing-verify-commands'
            $elig.reasons | Should -Contain 'routing-confidence-low'
        }
    }

    It 'rejects non-approved formal plans' {
        InModuleScope AutoProgram {
            $classification = [PSCustomObject]@{
                reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false
            }
            $project = [PSCustomObject]@{ routingConfidence = 0.99 }
            $contract = [PSCustomObject]@{
                verifyCommands = @('.\metra.ps1 verify'); doneWhen = @('ok')
            }
            $elig = Test-MetraAutoprogramEligibility -Classification $classification -Project $project -Contract $contract -RequireApprovedPlan
            $elig.eligible | Should -BeFalse
            $elig.reasons | Should -Contain 'formal-plan-not-approved'
        }
    }
}

Describe 'Autoprogram plan indexer' {
    It 'detects Approved status in plan body' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                $planPath = Join-Path $root 'sample.plan.md'
                $body = @"
---
name: Sample Plan
overview: "Metra sample"
todos:
  - id: slice-1
    content: "Do thing"
    status: pending
---

# Sample

**Status:** Approved (Bing test)

Run ``Invoke-Pester .\tests\Sample.Tests.ps1``
"@
                Write-AutoProgramAtomicUtf8Text -Path $planPath -Text $body
                $parsed = Read-MetraAutoprogramPlanFile -Path $planPath -MetraRoot (Get-AutoProgramHostRoot)
                $parsed.approved | Should -BeTrue
                $parsed.name | Should -Be 'Sample Plan'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Autoprogram triage dry-run' {
    It 'does not enqueue queue items' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                $report = Invoke-MetraAutoprogramTriage -Root $root -MetraRoot (Get-AutoProgramHostRoot)
                $report.dryRun | Should -BeTrue
                @(Get-MetraAutoprogramQueueItems -Root $root).Count | Should -Be 0
                @($report.candidates).Count | Should -BeGreaterThan 0
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Autoprogram enqueue from plan' {
    It 'sets source.type formal-plan with path provenance' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            $metraRoot = Get-AutoProgramHostRoot
            $planRoot = Join-Path $metraRoot ('docs\.ap-test-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
                $planPath = Join-Path $planRoot 'harness.plan.md'
                $body = @"
---
name: Harness Phase A
overview: "Metra autoprogram harness state"
---

# Harness

**Status:** Approved (Bing 2026-08-31)

Accept when Pester passes.
"@
                Write-AutoProgramAtomicUtf8Text -Path $planPath -Text $body
                $item = Invoke-MetraAutoprogramEnqueueFromPlan -Root $root -Path $planPath -MetraRoot $metraRoot
                $item.source.type | Should -Be 'formal-plan'
                [string]$item.source.path | Should -Be $planPath
                $item.status | Should -Be 'queued'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects plans outside allowed formal plan roots' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            $planRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-plan-' + [guid]::NewGuid().ToString('n'))
            try {
                $planPath = Join-Path $planRoot 'harness.plan.md'
                $body = @"
# Harness

**Status:** Approved (Bing 2026-08-31)
"@
                Write-AutoProgramAtomicUtf8Text -Path $planPath -Text $body
                { Invoke-MetraAutoprogramEnqueueFromPlan -Root $root -Path $planPath -MetraRoot (Get-AutoProgramHostRoot) } |
                    Should -Throw '*not under an allowed formal plan root*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects Pending Bing plans' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            $metraRoot = Get-AutoProgramHostRoot
            $planRoot = Join-Path $metraRoot ('docs\.ap-test-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
                $planPath = Join-Path $planRoot 'draft.plan.md'
                $body = @"
# Draft

**Status:** Pending Bing Review
"@
                Write-AutoProgramAtomicUtf8Text -Path $planPath -Text $body
                { Invoke-MetraAutoprogramEnqueueFromPlan -Root $root -Path $planPath -MetraRoot $metraRoot } |
                    Should -Throw '*not Approved*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Autoprogram daily stub' {
    It 'writes intake doc with three sections' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                $result = Invoke-MetraAutoprogramDailyStub -Root $root -MetraRoot (Get-AutoProgramHostRoot)
                Test-Path -LiteralPath $result.path | Should -BeTrue
                $text = [System.IO.File]::ReadAllText($result.path)
                $text | Should -Match '## 1\. Overarching changes made'
                $text | Should -Match '## 2\. Manual testing required'
                $text | Should -Match '## 3\. Next plan\(s\) for review'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Autoprogram path and id guards' {
    It 'rejects traversal and invalid queue ids' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraAutoprogramLayout -Root $root
                Test-MetraAutoprogramItemId -Id 'AP-20260831-0001' -Kind queue | Should -BeTrue
                Test-MetraAutoprogramItemId -Id 'CAND-20260831-0001' -Kind candidate | Should -BeTrue
                Test-MetraAutoprogramItemId -Id '..\evil' -Kind queue | Should -BeFalse
                Test-MetraAutoprogramItemId -Id 'CAND-test' -Kind candidate | Should -BeFalse
                { Get-MetraAutoprogramQueueItemPath -Root $root -Id '..\evil' } | Should -Throw '*Invalid*'
                { Get-MetraAutoprogramCandidate -Root $root -Id 'CAND-test' } | Should -Throw '*Invalid*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'does not treat sibling folder names as under Metra root' {
        InModuleScope AutoProgram {
            $base = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-sib-' + [guid]::NewGuid().ToString('n'))
            $metraRoot = Join-Path $base '_meta'
            $sibling = Join-Path $base '_meta-evil'
            try {
                New-Item -ItemType Directory -Path $metraRoot -Force | Out-Null
                New-Item -ItemType Directory -Path $sibling -Force | Out-Null
                $planPath = Join-Path $sibling 'x.plan.md'
                Write-AutoProgramAtomicUtf8Text -Path $planPath -Text "# X`n"
                $resolved = Resolve-MetraAutoprogramPlanProject -Path $planPath -MetraRoot $metraRoot -Title 'Other'
                $resolved.routingEvidence | Should -Not -Be 'plan-path-under-metra-root'
            }
            finally {
                Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

