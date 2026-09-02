# Slice 5 daily gate tests.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
}

Describe 'Loom Slice 5 transitions' {
    It 'allows completed exits only via approve map' {
        InModuleScope Loom {
            Test-MetraLoomTransition -From 'completed' -To 'accepted-pending-commit' | Should -BeTrue
            Test-MetraLoomTransition -From 'accepted-pending-commit' -To 'accepted' | Should -BeTrue
            Test-MetraLoomTransition -From 'completed' -To 'accepted' | Should -BeFalse
            Test-MetraLoomTransition -From 'completed' -To 'blocked' | Should -BeTrue
            Test-MetraLoomTransition -From 'completed' -To 'implementing' | Should -BeTrue
            Test-MetraLoomTransition -From 'completed' -To 'queued' | Should -BeFalse
        }
    }

    It 'blocks completed exit without daily approve active flag' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $root
                $cand = [PSCustomObject]@{
                    id = 'CAND-20260901-0099'; summary = 'Daily test'
                    source = [PSCustomObject]@{ type = 'operator' }
                    project = [PSCustomObject]@{
                        registryName = 'Metra'; root = (Get-LoomHostRoot)
                        routingConfidence = 0.99; routingEvidence = 'test'
                    }
                    classification = @{
                        reversibility = 'code'; crossRoot = $false; productionTouch = $false
                        externalSideEffect = $false; manualTestClass = 'none'
                    }
                    scores = [PSCustomObject]@{
                        impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5
                        dependencyValue = 2; total = 20; rubricVersion = 'triage-v1'
                    }
                    contract = [PSCustomObject]@{
                        objective = 'daily test'; allowedPaths = @('.'); forbiddenPaths = @()
                        doneWhen = @('pass')
                        verifyCommands = @(@{ executable = 'pwsh'; arguments = @('-NoProfile', '-Command', 'exit 0'); workingDirectory = '.'; timeoutSeconds = 30 })
                    }
                    eligible = $true; ineligibleReasons = @()
                }
                $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand
                $item.status = 'completed'
                Save-MetraLoomQueueItem -Root $root -Item $item
                { Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'completed' -To 'accepted-pending-commit' -Reason 'illegal' } |
                    Should -Throw '*only Invoke-MetraLoomDailyApprove*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom daily plan parser' {
    It 'parses valid directives and rejects conflicts' {
        InModuleScope Loom {
            $path = Join-Path ([IO.Path]::GetTempPath()) ('plan-' + [guid]::NewGuid().ToString('n') + '.md')
            try {
                @'
- [x] ACCEPT AP-20260901-0001
- [x] MANUAL-TEST-DONE AP-20260901-0001
'@ | Set-Content -LiteralPath $path -Encoding UTF8
                $d = @(Read-LoomDailyPlanDirectives -Path $path)
                $d.Count | Should -Be 2
                $d[0].verb | Should -Be 'ACCEPT'

                @'
- [x] ACCEPT AP-20260901-0001
- [x] RETRY AP-20260901-0001
'@ | Set-Content -LiteralPath $path -Encoding UTF8
                { Read-LoomDailyPlanDirectives -Path $path } | Should -Throw '*Conflicting*'
            }
            finally {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom project acceptance gate' {
    It 'blocks enqueue when project has completed item' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-' + [guid]::NewGuid().ToString('n'))
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-p-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                $cand1 = [PSCustomObject]@{
                    id = 'CAND-20260901-0001'; summary = 'one'
                    source = [PSCustomObject]@{ type = 'operator' }
                    project = [PSCustomObject]@{ registryName = 'Metra'; root = $proj; routingConfidence = 0.99; routingEvidence = 'test' }
                    classification = @{ reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false; manualTestClass = 'none' }
                    scores = [PSCustomObject]@{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2; total = 20; rubricVersion = 'triage-v1' }
                    contract = [PSCustomObject]@{ objective = 'x'; allowedPaths = @('.'); forbiddenPaths = @(); doneWhen = @('pass'); verifyCommands = @('x') }
                    eligible = $true; ineligibleReasons = @()
                }
                $item1 = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand1
                $item1.status = 'completed'
                Save-MetraLoomQueueItem -Root $root -Item $item1

                $cand2 = [PSCustomObject]@{
                    id = 'CAND-20260901-0002'; summary = 'two'
                    source = [PSCustomObject]@{ type = 'operator' }
                    project = [PSCustomObject]@{ registryName = 'Metra'; root = $proj; routingConfidence = 0.99; routingEvidence = 'test' }
                    classification = @{ reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false; manualTestClass = 'none' }
                    scores = [PSCustomObject]@{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2; total = 20; rubricVersion = 'triage-v1' }
                    contract = [PSCustomObject]@{ objective = 'x'; allowedPaths = @('.'); forbiddenPaths = @(); doneWhen = @('pass'); verifyCommands = @('x') }
                    eligible = $true; ineligibleReasons = @()
                }
                { New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand2 } |
                    Should -Throw '*lane-held*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom daily approve' {
    It 'preview does not mutate state' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-' + [guid]::NewGuid().ToString('n'))
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-p-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                git -C $proj init 2>$null | Out-Null
                git -C $proj config user.email 't@t.local' 2>$null | Out-Null
                git -C $proj config user.name 't' 2>$null | Out-Null
                Set-Content -Path (Join-Path $proj 'README.md') -Value 'x'
                git -C $proj add README.md 2>$null | Out-Null
                git -C $proj commit -m init 2>$null | Out-Null
                git -C $proj branch -M main 2>$null | Out-Null
                $baseline = git -C $proj rev-parse HEAD

                $cand = [PSCustomObject]@{
                    id = 'CAND-20260901-0099'; summary = 'approve preview'
                    source = [PSCustomObject]@{ type = 'operator' }
                    project = [PSCustomObject]@{ registryName = 'Metra'; root = $proj; routingConfidence = 0.99; routingEvidence = 'test' }
                    classification = @{ reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false; manualTestClass = 'none' }
                    scores = [PSCustomObject]@{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2; total = 20; rubricVersion = 'triage-v1' }
                    contract = [PSCustomObject]@{ objective = 'x'; allowedPaths = @('.'); forbiddenPaths = @(); doneWhen = @('pass'); verifyCommands = @('x') }
                    eligible = $true; ineligibleReasons = @()
                }
                $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand
                $item.execution | Add-Member -NotePropertyName baselineSha -NotePropertyValue $baseline -Force
                $item.execution | Add-Member -NotePropertyName completedCommit -NotePropertyValue $baseline -Force
                $item.status = 'completed'
                Save-MetraLoomQueueItem -Root $root -Item $item

                $reviewDate = Get-LoomDailyReviewDate
                Add-MetraLoomJournalEntry -Root $root -Entry @{
                    itemId = $item.id; from = 'reviewing'; to = 'completed'
                    actor = 'harness'; reason = 'test'
                }
                $mockRoot = $root
                $mockReviewDate = $reviewDate
                $mockPack = {
                    param($Name, $Base, $ProjectRoot)
                    $pack = Join-Path $mockRoot "daily/$mockReviewDate-bing/metra/$($item.id)/pack-diff.md"
                    $dir = Split-Path -Parent $pack
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    Set-Content -Path $pack -Value 'mock pack'
                    [PSCustomObject]@{ outcome = 'ok'; packPath = $pack; message = 'mock' }
                }
                Invoke-MetraLoomDailyPackDiff -Root $root -ReviewDate $reviewDate -PackScript $mockPack | Out-Null

                $planPath = Join-Path $root 'daily-plan.md'
                Set-Content -LiteralPath $planPath -Value "- [x] ACCEPT $($item.id)"

                $preview = Invoke-MetraLoomDailyApprove -Root $root -PlanPath $planPath -ReviewDate $reviewDate
                $preview.dryRun | Should -BeTrue
                $preview.applied | Should -BeFalse
                (Get-MetraLoomQueueItem -Root $root -Id $item.id).status | Should -Be 'completed'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'batch fails with zero mutations when manifest missing for second item' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-' + [guid]::NewGuid().ToString('n'))
            $proj1 = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-p1-' + [guid]::NewGuid().ToString('n'))
            $proj2 = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-p2-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj1,$proj2 -Force | Out-Null
                $ids = @()
                $regs = @('Metra', 'Brightspace')
                $projs = @($proj1, $proj2)
                foreach ($i in 0..1) {
                    $cand = [PSCustomObject]@{
                        id = "CAND-20260901-000$($i+1)"; summary = "item $i"
                        source = [PSCustomObject]@{ type = 'operator' }
                        project = [PSCustomObject]@{ registryName = $regs[$i]; root = $projs[$i]; routingConfidence = 0.99; routingEvidence = 'test' }
                        classification = @{ reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false; manualTestClass = 'none' }
                        scores = [PSCustomObject]@{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2; total = 20; rubricVersion = 'triage-v1' }
                        contract = [PSCustomObject]@{ objective = 'x'; allowedPaths = @('.'); forbiddenPaths = @(); doneWhen = @('pass'); verifyCommands = @(@{ executable = 'pwsh'; arguments = @('-Command', 'exit 0'); workingDirectory = '.'; timeoutSeconds = 30 }) }
                        eligible = $true; ineligibleReasons = @()
                    }
                    $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand
                    $item.status = 'completed'
                    Save-MetraLoomQueueItem -Root $root -Item $item
                    $ids += $item.id
                }

                $planPath = Join-Path $root 'daily-plan.md'
                Set-Content -LiteralPath $planPath -Value @"
- [x] ACCEPT $($ids[0])
- [x] ACCEPT $($ids[1])
"@

                $result = Invoke-MetraLoomDailyApprove -Root $root -PlanPath $planPath -Confirm
                $result.applied | Should -BeFalse
                (Get-MetraLoomQueueItem -Root $root -Id $ids[0]).status | Should -Be 'completed'
                (Get-MetraLoomQueueItem -Root $root -Id $ids[1]).status | Should -Be 'completed'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $proj1,$proj2 -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom daily build' {
    It 'writes intake with sections 1-3 when queue empty' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-' + [guid]::NewGuid().ToString('n'))
            try {
                $mockPack = {
                    param($Name, $Base, $ProjectRoot)
                    [PSCustomObject]@{ outcome = 'ok'; packPath = $null; message = 'noop' }
                }
                $result = Invoke-MetraLoomDailyBuild -Root $root -PackScript $mockPack
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

Describe 'Loom daily pack-diff aggregate' {
    It 'writes one pack-diff.md per project with a section per item' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-' + [guid]::NewGuid().ToString('n'))
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-d5-p-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $root
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                git -C $proj init 2>$null | Out-Null
                git -C $proj config user.email 't@t.local' 2>$null | Out-Null
                git -C $proj config user.name 't' 2>$null | Out-Null
                Set-Content -Path (Join-Path $proj 'README.md') -Value 'x'
                git -C $proj add README.md 2>$null | Out-Null
                git -C $proj commit -m init 2>$null | Out-Null
                $sha = git -C $proj rev-parse HEAD

                $ids = @()
                foreach ($n in 1..2) {
                    $cand = [PSCustomObject]@{
                        id = "CAND-20260901-000$n"; summary = "item $n"
                        source = [PSCustomObject]@{ type = 'operator' }
                        project = [PSCustomObject]@{ registryName = 'Metra'; root = $proj; routingConfidence = 0.99; routingEvidence = 'test' }
                        classification = @{ reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false; manualTestClass = 'none' }
                        scores = [PSCustomObject]@{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2; total = 20; rubricVersion = 'triage-v1' }
                        contract = [PSCustomObject]@{ objective = 'x'; allowedPaths = @('.'); forbiddenPaths = @(); doneWhen = @('pass'); verifyCommands = @('x') }
                        eligible = $true; ineligibleReasons = @()
                    }
                    $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand
                    $item.execution | Add-Member -NotePropertyName baselineSha -NotePropertyValue $sha -Force
                    $item.execution | Add-Member -NotePropertyName completedCommit -NotePropertyValue $sha -Force
                    Save-MetraLoomQueueItem -Root $root -Item $item
                    $ids += $item.id
                }
                foreach ($id in $ids) {
                    $item = Get-MetraLoomQueueItem -Root $root -Id $id
                    $item.status = 'completed'
                    Save-MetraLoomQueueItem -Root $root -Item $item
                    Add-MetraLoomJournalEntry -Root $root -Entry @{
                        itemId = $id; from = 'reviewing'; to = 'completed'; actor = 'harness'; reason = 'test'
                    }
                }

                $reviewDate = Get-LoomDailyReviewDate
                $mockRoot = $root
                $mockReviewDate = $reviewDate
                $mockPack = {
                    param($Name, $Base, $ProjectRoot)
                    $pack = Join-Path $mockRoot "daily/$mockReviewDate-bing/metra/mock-pack.md"
                    $dir = Split-Path -Parent $pack
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    Set-Content -Path $pack -Value 'mock pack body'
                    [PSCustomObject]@{ outcome = 'ok'; packPath = $pack; message = 'mock' }
                }
                Invoke-MetraLoomDailyPackDiff -Root $root -ReviewDate $reviewDate -PackScript $mockPack | Out-Null

                $packPath = Join-Path $root "daily/$reviewDate-pack-diff/metra/pack-diff.md"
                Test-Path -LiteralPath $packPath | Should -BeTrue
                $text = [System.IO.File]::ReadAllText($packPath)
                $text | Should -Match '# Project: Metra'
                foreach ($id in $ids) {
                    $text | Should -Match "## $id"
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom project key' {
    It 'normalizes registry names and detects collisions' {
        InModuleScope Loom {
            $map = @{}
            Get-LoomProjectKey -RegistryName 'Foo.Bar' -KeyRegistryMap $map | Should -Be 'foo-bar'
            Get-LoomProjectKey -RegistryName 'Foo.Bar' -KeyRegistryMap $map | Should -Be 'foo-bar'
            { Get-LoomProjectKey -RegistryName 'Foo Bar' -KeyRegistryMap $map } | Should -Throw '*collision*'
        }
    }
}
