# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Loom.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'modules\Loom\Loom.psd1') -Force
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Loom transitions (Phase A + Slice 3 + Slice 5)' {
    It 'allows Phase A and Slice 3 run transitions' {
        InModuleScope Loom {
            Test-MetraLoomTransition -From '@new' -To 'queued' | Should -BeTrue
            Test-MetraLoomTransition -From 'queued' -To 'blocked' | Should -BeTrue
            Test-MetraLoomTransition -From 'queued' -To 'claimed' | Should -BeTrue
            Test-MetraLoomTransition -From 'queued' -To 'accepted' | Should -BeFalse
            Test-MetraLoomTransition -From 'blocked' -To 'queued' | Should -BeFalse
            Test-MetraLoomTransition -From 'completed' -To 'accepted-pending-commit' | Should -BeTrue
            Test-MetraLoomTransition -From 'accepted-pending-commit' -To 'accepted' | Should -BeTrue
            Test-MetraLoomTransition -From 'completed' -To 'accepted' | Should -BeFalse
        }
    }
}

Describe 'Loom journal append-only' {
    It 'appends journal lines without rewriting prior entries' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $root
                Add-MetraLoomJournalEntry -Root $root -Entry @{ itemId = 'AP-1'; to = 'queued' }
                Add-MetraLoomJournalEntry -Root $root -Entry @{ itemId = 'AP-1'; to = 'blocked' }
                $path = Get-MetraLoomJournalPath -Root $root
                $lines = @([System.IO.File]::ReadAllLines($path))
                $lines.Count | Should -Be 2
                $first = $lines[0]
                Add-MetraLoomJournalEntry -Root $root -Entry @{ itemId = 'AP-2'; to = 'queued' }
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

Describe 'Loom enqueue and block' {
    It 'creates queued item and blocks with journal pairing' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                $cand = [PSCustomObject]@{
                    id             = 'CAND-20260831-0001'
                    summary        = 'Test item'
                    source         = [PSCustomObject]@{ type = 'operator' }
                    project        = [PSCustomObject]@{
                        registryName = 'Metra'; root = (Get-LoomHostRoot)
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
                $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand
                $item.status | Should -Be 'queued'
                $item.id | Should -Match '^AP-\d{8}-\d{4}$'

                $blocked = Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'queued' -To 'blocked' -Reason 'test'
                $blocked.status | Should -Be 'blocked'

                { Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'queued' -To 'blocked' } |
                    Should -Throw '*expected*queued*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'records prior status in journal when -From is omitted' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $root
                $cand = [PSCustomObject]@{
                    id             = 'CAND-20260831-0002'
                    summary        = 'Journal from test'
                    source         = [PSCustomObject]@{ type = 'operator' }
                    project        = [PSCustomObject]@{
                        registryName = 'Metra'; root = (Get-LoomHostRoot)
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
                $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand
                Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -To 'blocked' -Reason 'omit-from' | Out-Null
                $path = Get-MetraLoomJournalPath -Root $root
                $last = (Get-Content -LiteralPath $path -Tail 1 | ConvertFrom-Json)
                [string]$last.from | Should -Be 'queued'
                [string]$last.to | Should -Be 'blocked'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom deterministic scoring' {
    It 'returns the same total for the same inputs' {
        InModuleScope Loom {
            $classification = @{
                reversibility = 'code'; crossRoot = $false; productionTouch = $false
                externalSideEffect = $false; manualTestClass = 'none'
            }
            $scoresIn = @{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2 }
            $project = [PSCustomObject]@{ routingConfidence = 0.99 }
            $a = Measure-MetraLoomTriageScore -Classification $classification -Scores $scoresIn -Project $project
            $b = Measure-MetraLoomTriageScore -Classification $classification -Scores $scoresIn -Project $project
            $a.total | Should -Be $b.total
            $a.rubricVersion | Should -Be 'triage-v1'
        }
    }
}

Describe 'Loom eligibility' {
    It 'rejects capture-like items without contract' {
        InModuleScope Loom {
            $classification = [PSCustomObject]@{
                reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false
            }
            $project = [PSCustomObject]@{ routingConfidence = 0.0 }
            $contract = [PSCustomObject]@{ verifyCommands = @(); doneWhen = @() }
            $elig = Test-MetraLoomEligibility -Classification $classification -Project $project -Contract $contract
            $elig.eligible | Should -BeFalse
            $elig.reasons | Should -Contain 'missing-verify-commands'
            $elig.reasons | Should -Contain 'routing-confidence-low'
        }
    }

    It 'rejects non-approved formal plans' {
        InModuleScope Loom {
            $classification = [PSCustomObject]@{
                reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false
            }
            $project = [PSCustomObject]@{ routingConfidence = 0.99 }
            $contract = [PSCustomObject]@{
                verifyCommands = @('.\metra.ps1 verify'); doneWhen = @('ok')
            }
            $elig = Test-MetraLoomEligibility -Classification $classification -Project $project -Contract $contract -RequireApprovedPlan
            $elig.eligible | Should -BeFalse
            $elig.reasons | Should -Contain 'formal-plan-not-approved'
        }
    }
}

Describe 'Loom plan indexer' {
    It 'detects Approved status in plan body' {
        InModuleScope Loom {
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
                Write-LoomAtomicUtf8Text -Path $planPath -Text $body
                $parsed = Read-MetraLoomPlanFile -Path $planPath -MetraRoot (Get-LoomHostRoot)
                $parsed.approved | Should -BeTrue
                $parsed.name | Should -Be 'Sample Plan'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom triage dry-run' {
    It 'does not enqueue queue items' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                $report = Invoke-MetraLoomTriage -Root $root -MetraRoot (Get-LoomHostRoot)
                $report.dryRun | Should -BeTrue
                @(Get-MetraLoomQueueItems -Root $root).Count | Should -Be 0
                @($report.candidates).Count | Should -BeGreaterThan 0
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom enqueue from plan' {
    It 'sets source.type formal-plan with path provenance' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            $metraRoot = Get-LoomHostRoot
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
                Write-LoomAtomicUtf8Text -Path $planPath -Text $body
                $item = Invoke-MetraLoomEnqueueFromPlan -Root $root -Path $planPath -MetraRoot $metraRoot
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
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            $planRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-plan-' + [guid]::NewGuid().ToString('n'))
            try {
                $planPath = Join-Path $planRoot 'harness.plan.md'
                $body = @"
# Harness

**Status:** Approved (Bing 2026-08-31)
"@
                Write-LoomAtomicUtf8Text -Path $planPath -Text $body
                { Invoke-MetraLoomEnqueueFromPlan -Root $root -Path $planPath -MetraRoot (Get-LoomHostRoot) } |
                    Should -Throw '*not under an allowed formal plan root*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects Pending Bing plans' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            $metraRoot = Get-LoomHostRoot
            $planRoot = Join-Path $metraRoot ('docs\.ap-test-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
                $planPath = Join-Path $planRoot 'draft.plan.md'
                $body = @"
# Draft

**Status:** Pending Bing Review
"@
                Write-LoomAtomicUtf8Text -Path $planPath -Text $body
                { Invoke-MetraLoomEnqueueFromPlan -Root $root -Path $planPath -MetraRoot $metraRoot } |
                    Should -Throw '*not Approved*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom daily stub' {
    It 'writes intake doc with three sections' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                $mockPack = {
                    param($Name, $Base, $ProjectRoot)
                    [PSCustomObject]@{ outcome = 'ok'; packPath = $null; message = 'noop' }
                }
                $result = Invoke-MetraLoomDailyStub -Root $root -MetraRoot (Get-LoomHostRoot)
                Test-Path -LiteralPath $result.path | Should -BeTrue
                $text = [System.IO.File]::ReadAllText($result.path)
                $text | Should -Match '## 1\. Overarching changes made'
                $text | Should -Match '## 2\. Manual testing required'
                $text | Should -Match '## 3\. Plan review \(Yarn\)'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom path and id guards' {
    It 'rejects traversal and invalid queue ids' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $root
                Test-MetraLoomItemId -Id 'AP-20260831-0001' -Kind queue | Should -BeTrue
                Test-MetraLoomItemId -Id 'CAND-20260831-0001' -Kind candidate | Should -BeTrue
                Test-MetraLoomItemId -Id '..\evil' -Kind queue | Should -BeFalse
                Test-MetraLoomItemId -Id 'CAND-test' -Kind candidate | Should -BeFalse
                { Get-MetraLoomQueueItemPath -Root $root -Id '..\evil' } | Should -Throw '*Invalid*'
                { Get-MetraLoomCandidate -Root $root -Id 'CAND-test' } | Should -Throw '*Invalid*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'does not treat sibling folder names as under Metra root' {
        InModuleScope Loom {
            $base = Join-Path ([IO.Path]::GetTempPath()) ('metra-ap-sib-' + [guid]::NewGuid().ToString('n'))
            $metraRoot = Join-Path $base '_meta'
            $sibling = Join-Path $base '_meta-evil'
            try {
                New-Item -ItemType Directory -Path $metraRoot -Force | Out-Null
                New-Item -ItemType Directory -Path $sibling -Force | Out-Null
                $planPath = Join-Path $sibling 'x.plan.md'
                Write-LoomAtomicUtf8Text -Path $planPath -Text "# X`n"
                $resolved = Resolve-MetraLoomPlanProject -Path $planPath -MetraRoot $metraRoot -Title 'Other'
                $resolved.routingEvidence | Should -Not -Be 'plan-path-under-metra-root'
            }
            finally {
                Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Metra CLI loom entry' {
    It 'loom status invokes without error' {
        $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        Push-Location $metraRoot
        try {
            { & (Join-Path $metraRoot 'metra.ps1') loom status | Out-Null } | Should -Not -Throw
        }
        finally {
            Pop-Location
        }
    }

    It 'autoprogram status warns once and succeeds' {
        $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        Push-Location $metraRoot
        try {
            $warn = $null
            & (Join-Path $metraRoot 'metra.ps1') autoprogram status -WarningVariable warn 2>&1 | Out-Null
            @($warn | Where-Object { $_ -match 'deprecated' }).Count | Should -Be 1
        }
        finally {
            Pop-Location
        }
    }

    It 'forwards script -Confirm to loom loop ArgsRest' {
        function Global:Get-MetraAskCapability {
            return [PSCustomObject]@{
                available = $true; engineHealthy = $true; reason = 'ok'; message = ''
            }
        }
        InModuleScope Loom {
            $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-loom-cli-' + [guid]::NewGuid().ToString('n'))
            Initialize-MetraLoomLayout -Root $root
            $env:METRA_LOOM_ROOT = $root
            Push-Location $metraRoot
            try {
                { & (Join-Path $metraRoot 'metra.ps1') loom loop -UntilDailyGate -Confirm } | Should -Not -Throw '*requires -Confirm*'
            }
            finally {
                Remove-Item Env:METRA_LOOM_ROOT -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Pop-Location
            }
        }
        Remove-Item Function:\Get-MetraAskCapability -ErrorAction SilentlyContinue
    }
}


Describe "Loom Yarn ingest handoff (A3)" {
    It "validates handoffContractVersion and rankSnapshot" {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-loom-yarn-" + [guid]::NewGuid().ToString("n"))
            try {
                Initialize-MetraLoomLayout -Root $root
                $snap = [PSCustomObject]@{ total = 1; effectiveImpact = 1; completionReady = 1; rubricVersion = "yarn-rank-v1"; rankReasons = @("x") }
                { Invoke-MetraLoomIngestApprovedPlan -Root $root -PlanPath "C:\nope.md" -ProjectKey "Metra" -ApprovalRevision "r1" -ApprovalId "a1" -RankSnapshot $snap -HandoffContractVersion 99 } |
                    Should -Throw "*handoffContractVersion*"
                { Invoke-MetraLoomIngestApprovedPlan -Root $root -PlanPath "C:\nope.md" -ProjectKey "Metra" -ApprovalRevision "r1" -ApprovalId "a1" -RankSnapshot ([PSCustomObject]@{ total = 1 }) -HandoffContractVersion 1 } |
                    Should -Throw "*rankSnapshot missing*"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It "enqueues once for same planIdentity+approvalRevision" {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-loom-yarn-" + [guid]::NewGuid().ToString("n"))
            $metraRoot = Get-LoomHostRoot
            $planRoot = Join-Path $metraRoot ("docs\.yarn-ingest-" + [guid]::NewGuid().ToString("n"))
            try {
                New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
                $planPath = Join-Path $planRoot "approved.plan.md"
                $body = @"
---
name: Yarn Ingest
overview: "Metra yarn ingest fixture"
status: Approved
bingReviewed: true
---

# Yarn Ingest
"@
                Write-LoomAtomicUtf8Text -Path $planPath -Text $body
                $snap = [PSCustomObject]@{ total = 2.5; effectiveImpact = 1.2; completionReady = 0.8; rubricVersion = "yarn-rank-v1"; rankReasons = @("objectivePresent") }
                $a = Invoke-MetraLoomIngestApprovedPlan -Root $root -PlanPath $planPath -ProjectKey "Metra" -ApprovalRevision "rev-a" -ApprovalId "ya-1" -RankSnapshot $snap -HandoffContractVersion 1 -MetraRoot $metraRoot
                $a.outcome | Should -Be "enqueued"
                $b = Invoke-MetraLoomIngestApprovedPlan -Root $root -PlanPath $planPath -ProjectKey "Metra" -ApprovalRevision "rev-a" -ApprovalId "ya-1" -RankSnapshot $snap -HandoffContractVersion 1 -MetraRoot $metraRoot
                $b.outcome | Should -Be "idempotent"
                $b.queueItemId | Should -Be $a.queueItemId
                $a.item.yarnHandoff.approvalRevision | Should -Be "rev-a"
                $a.item.yarnHandoff.rankSnapshot.rubricVersion | Should -Be "yarn-rank-v1"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It "rejects Pending Bing plans" {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-loom-yarn-" + [guid]::NewGuid().ToString("n"))
            $metraRoot = Get-LoomHostRoot
            $planRoot = Join-Path $metraRoot ("docs\.yarn-ingest-" + [guid]::NewGuid().ToString("n"))
            try {
                New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
                $planPath = Join-Path $planRoot "pending.plan.md"
                Write-LoomAtomicUtf8Text -Path $planPath -Text @"
---
name: Pending
status: Pending Bing Review
bingReviewed: false
---
"@
                $snap = [PSCustomObject]@{ total = 1; effectiveImpact = 1; completionReady = 1; rubricVersion = "yarn-rank-v1"; rankReasons = @("x") }
                { Invoke-MetraLoomIngestApprovedPlan -Root $root -PlanPath $planPath -ProjectKey "Metra" -ApprovalRevision "r" -ApprovalId "a" -RankSnapshot $snap -HandoffContractVersion 1 -MetraRoot $metraRoot } |
                    Should -Throw "*not Approved*"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom Pattern package (P2)' {
    It 'parses patterns front matter and attaches excerpts to request package' {
        InModuleScope Loom {
            $runDir = Join-Path ([IO.Path]::GetTempPath()) ('metra-loom-pat-' + [guid]::NewGuid().ToString('n'))
            $planDir = Join-Path ([IO.Path]::GetTempPath()) ('metra-loom-plan-' + [guid]::NewGuid().ToString('n'))
            try {
                [void][System.IO.Directory]::CreateDirectory($planDir)
                $planPath = Join-Path $planDir 'with-patterns.plan.md'
                $body = @"
---
name: Pattern Cite Plan
overview: "Cite loom-review"
status: Approved
bingReviewed: true
patterns:
  - loom-review
  - does-not-exist-xyz
todos:
  - id: t1
    content: "Do"
    status: pending
---

# Pattern Cite Plan
"@
                Write-LoomAtomicUtf8Text -Path $planPath -Text $body
                $parsed = Read-MetraLoomPlanFile -Path $planPath -MetraRoot (Get-LoomHostRoot)
                $parsed.patterns | Should -Contain 'loom-review'
                $parsed.patterns | Should -Contain 'does-not-exist-xyz'

                $item = [PSCustomObject]@{
                    id        = 'AP-PAT-1'
                    summary   = 'pattern package'
                    source    = [PSCustomObject]@{ path = $planPath; type = 'formal-plan' }
                    project   = [PSCustomObject]@{ root = (Get-LoomHostRoot); registryName = 'Metra' }
                    execution = [PSCustomObject]@{ branch = 'loom/ap-pat-1' }
                    contract  = [PSCustomObject]@{
                        allowedPaths   = @('docs/patterns/')
                        forbiddenPaths = @()
                        doneWhen       = @('pester')
                        verifyCommands = @('.\metra.ps1 verify')
                    }
                }
                $pkg = New-LoomRunRequestPackage -Item $item -RunDir $runDir -MetraRoot (Get-LoomHostRoot)
                @($pkg.patterns).Count | Should -Be 1
                $pkg.patterns[0].patternId | Should -Be 'loom-review'
                $pkg.patterns[0].contentHash | Should -Match '^[a-f0-9]{64}$'
                ($pkg.patternWarnings -join ' ') | Should -Match 'does-not-exist-xyz'
            }
            finally {
                Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom Slice 8 Pattern promote' {
    It 'blocks promote when item is not accepted' {
        InModuleScope Loom {
            $loomRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-loom-s8-' + [guid]::NewGuid().ToString('n'))
            $hostRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-host-s8-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $loomRoot
                $patDir = Join-Path $hostRoot 'docs\patterns\guild'
                [void][System.IO.Directory]::CreateDirectory($patDir)
                $body = @"
---
patternSchemaVersion: 1
defaultContext: false
patternId: guild-knowledge-promotion
owner: loom
cabinet: guild
status: active
implemented: true
---
# Guild Knowledge Promotion Pattern
"@
                $patPath = Join-Path $patDir 'knowledge-promotion.md'
                [System.IO.File]::WriteAllText($patPath, $body, [System.Text.UTF8Encoding]::new($false))
                'guild-knowledge-promotion: guild/knowledge-promotion.md' | Set-Content -LiteralPath (Join-Path $hostRoot 'docs\patterns\index.yaml') -Encoding utf8

                $item = [PSCustomObject]@{
                    id            = 'AP-20260902-0001'
                    schemaVersion = 1
                    summary       = 's8 block'
                    createdAt     = '2026-09-02T00:00:00Z'
                    updatedAt     = '2026-09-02T00:00:00Z'
                    status        = 'completed'
                    project       = [PSCustomObject]@{ root = $hostRoot; registryName = 'Metra' }
                    execution     = [PSCustomObject]@{
                        baselineCommit  = 'aaa'
                        completedCommit = 'bbb'
                        branch          = 'loom/metra/x'
                    }
                }
                Save-MetraLoomQueueItem -Root $loomRoot -Item $item

                $script:LoomPatternDiffOverride = {
                    param($ProjectRoot, $BaselineCommit, $CompletedCommit, $PathFilter)
                    @('docs/patterns/guild/knowledge-promotion.md')
                }
                $script:LoomPatternBlobOverride = {
                    param($ProjectRoot, $Commit, $RepoRelativePath)
                    return [System.IO.File]::ReadAllText($patPath, [System.Text.UTF8Encoding]::new($false))
                }

                $prev = Invoke-MetraLoomPatternPromote -Root $loomRoot -MetraRoot $hostRoot -Path $patPath -ItemId 'AP-20260902-0001' -Preview
                $prev.eligible | Should -BeFalse
                $prev.reasons -join ' ' | Should -Match 'item-not-accepted'
            }
            finally {
                $script:LoomPatternDiffOverride = $null
                $script:LoomPatternBlobOverride = $null
                $script:LoomAtlasPutOverride = $null
                Remove-Item -LiteralPath $loomRoot -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hostRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'promotes on Confirm when accepted evidence matches and records ledger' {
        InModuleScope Loom {
            $loomRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-loom-s8b-' + [guid]::NewGuid().ToString('n'))
            $hostRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-host-s8b-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $loomRoot
                $patDir = Join-Path $hostRoot 'docs\patterns\guild'
                [void][System.IO.Directory]::CreateDirectory($patDir)
                $body = @"
---
patternSchemaVersion: 1
defaultContext: false
patternId: guild-knowledge-promotion
owner: loom
cabinet: guild
status: active
implemented: true
---
# Guild Knowledge Promotion Pattern
"@
                $patPath = Join-Path $patDir 'knowledge-promotion.md'
                [System.IO.File]::WriteAllText($patPath, $body, [System.Text.UTF8Encoding]::new($false))
                'guild-knowledge-promotion: guild/knowledge-promotion.md' | Set-Content -LiteralPath (Join-Path $hostRoot 'docs\patterns\index.yaml') -Encoding utf8

                $item = [PSCustomObject]@{
                    id            = 'AP-20260902-0002'
                    schemaVersion = 1
                    summary       = 's8 promote'
                    createdAt     = '2026-09-02T00:00:00Z'
                    updatedAt     = '2026-09-02T00:00:00Z'
                    status        = 'accepted'
                    project       = [PSCustomObject]@{ root = $hostRoot; registryName = 'Metra' }
                    execution     = [PSCustomObject]@{
                        baselineCommit  = 'aaa'
                        completedCommit = 'bbb'
                        branch          = 'loom/metra/x'
                    }
                }
                Save-MetraLoomQueueItem -Root $loomRoot -Item $item

                $script:LoomPatternDiffOverride = {
                    param($ProjectRoot, $BaselineCommit, $CompletedCommit, $PathFilter)
                    @('docs/patterns/guild/knowledge-promotion.md')
                }
                $script:LoomPatternBlobOverride = {
                    param($ProjectRoot, $Commit, $RepoRelativePath)
                    return [System.IO.File]::ReadAllText($patPath, [System.Text.UTF8Encoding]::new($false))
                }
                $script:LoomAtlasPutOverride = {
                    param($StableId, $Project, $Kind, $Title, $BodyPath, $Publish, $MetraRoot)
                    [PSCustomObject]@{ ok = $true; stableId = $StableId; stub = $true; published = [bool]$Publish }
                }

                $prev = Invoke-MetraLoomPatternPromote -Root $loomRoot -MetraRoot $hostRoot -Path $patPath -ItemId 'AP-20260902-0002' -Preview
                $prev.eligible | Should -BeTrue
                $prev.stableId | Should -Be 'pattern:guild-knowledge-promotion'

                $done = Invoke-MetraLoomPatternPromote -Root $loomRoot -MetraRoot $hostRoot -Path $patPath -ItemId 'AP-20260902-0002' -Confirm
                $done.outcome | Should -Be 'promoted'
                $ledger = Get-LoomPatternPromotions -Root $loomRoot
                @($ledger.promotions).Count | Should -Be 1
                $ledger.promotions[0].patternId | Should -Be 'guild-knowledge-promotion'

                $again = Invoke-MetraLoomPatternPromote -Root $loomRoot -MetraRoot $hostRoot -Path $patPath -ItemId 'AP-20260902-0002' -Preview
                $again.eligible | Should -BeFalse
                $again.reasons -join ' ' | Should -Match 'already-promoted'
            }
            finally {
                $script:LoomPatternDiffOverride = $null
                $script:LoomPatternBlobOverride = $null
                $script:LoomAtlasPutOverride = $null
                Remove-Item -LiteralPath $loomRoot -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hostRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'scores eligible candidates from accepted pattern diffs' {
        InModuleScope Loom {
            $loomRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-loom-s8c-' + [guid]::NewGuid().ToString('n'))
            $hostRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-host-s8c-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $loomRoot
                $patDir = Join-Path $hostRoot 'docs\patterns\guild'
                [void][System.IO.Directory]::CreateDirectory($patDir)
                $body = @"
---
patternSchemaVersion: 1
defaultContext: false
patternId: guild-knowledge-promotion
owner: loom
cabinet: guild
status: active
implemented: true
---
# Guild Knowledge Promotion Pattern
"@
                $patPath = Join-Path $patDir 'knowledge-promotion.md'
                [System.IO.File]::WriteAllText($patPath, $body, [System.Text.UTF8Encoding]::new($false))
                'guild-knowledge-promotion: guild/knowledge-promotion.md' | Set-Content -LiteralPath (Join-Path $hostRoot 'docs\patterns\index.yaml') -Encoding utf8

                Save-MetraLoomQueueItem -Root $loomRoot -Item ([PSCustomObject]@{
                        id            = 'AP-20260902-0003'
                        schemaVersion = 1
                        summary       = 's8 score'
                        createdAt     = '2026-09-02T00:00:00Z'
                        updatedAt     = '2026-09-02T00:00:00Z'
                        status        = 'accepted'
                        project       = [PSCustomObject]@{ root = $hostRoot; registryName = 'Metra' }
                        execution     = [PSCustomObject]@{ baselineCommit = 'a'; completedCommit = 'b'; branch = 'loom/x' }
                    })

                $script:LoomPatternDiffOverride = {
                    param($ProjectRoot, $BaselineCommit, $CompletedCommit, $PathFilter)
                    @('docs/patterns/guild/knowledge-promotion.md')
                }
                $script:LoomPatternBlobOverride = {
                    param($ProjectRoot, $Commit, $RepoRelativePath)
                    return [System.IO.File]::ReadAllText($patPath, [System.Text.UTF8Encoding]::new($false))
                }

                $score = Invoke-MetraLoomPatternScore -Root $loomRoot -MetraRoot $hostRoot
                $score.outcome | Should -Be 'scored'
                @($score.candidates | Where-Object { $_.eligible }).Count | Should -BeGreaterOrEqual 1
            }
            finally {
                $script:LoomPatternDiffOverride = $null
                $script:LoomPatternBlobOverride = $null
                Remove-Item -LiteralPath $loomRoot -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hostRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'fails closed on path escape and absolute paths outside docs/patterns' {
        InModuleScope Loom {
            $hostRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-host-s8d-' + [guid]::NewGuid().ToString('n'))
            try {
                $patDir = Join-Path $hostRoot 'docs\patterns\guild'
                [void][System.IO.Directory]::CreateDirectory($patDir)
                $body = @"
---
patternSchemaVersion: 1
defaultContext: false
patternId: guild-knowledge-promotion
owner: loom
cabinet: guild
status: active
implemented: true
---
# ok
"@
                [System.IO.File]::WriteAllText((Join-Path $patDir 'knowledge-promotion.md'), $body, [System.Text.UTF8Encoding]::new($false))
                { Resolve-LoomPatternFileUnderMetra -Path 'C:\Temp\evil.md' -MetraRoot $hostRoot } | Should -Throw '*escapes docs/patterns*'
                { Resolve-LoomPatternFileUnderMetra -Path '..\..\..\Windows\System32\drivers\etc\hosts' -MetraRoot $hostRoot } | Should -Throw '*escapes docs/patterns*'
                $ok = Resolve-LoomPatternFileUnderMetra -Path (Join-Path $patDir 'knowledge-promotion.md') -MetraRoot $hostRoot
                $ok.repoRelative | Should -Be 'docs/patterns/guild/knowledge-promotion.md'
            }
            finally {
                Remove-Item -LiteralPath $hostRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
