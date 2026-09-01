# Slice 4 review orchestrator tests.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
}

Describe 'Loom review dry-run' {
    It 'does not invoke adapters without -Confirm' {
        InModuleScope Loom {
            function Initialize-LoomReviewTestGitRepo {
                param([Parameter(Mandatory)][string]$Path)
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
                Push-Location $Path
                try {
                    git init 2>$null | Out-Null
                    git config user.email 'loom-review@test.local' 2>$null | Out-Null
                    git config user.name 'Loom Review Test' 2>$null | Out-Null
                    New-Item -ItemType Directory -Path (Join-Path $Path 'tests') -Force | Out-Null
                    Set-Content -Path (Join-Path $Path 'tests\ok.txt') -Value 'ok'
                    git add tests/ok.txt 2>$null | Out-Null
                    git commit -m 'init' 2>$null | Out-Null
                }
                finally { Pop-Location }
            }

            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-rev-' + [guid]::NewGuid().ToString('n'))
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-rev-p-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-LoomReviewTestGitRepo -Path $proj
                Initialize-MetraLoomLayout -Root $root
                $cand = [PSCustomObject]@{
                    id = 'CAND-20260901-0099'; summary = 'Review test'
                    source = [PSCustomObject]@{ type = 'operator' }
                    project = [PSCustomObject]@{ registryName = 'Metra'; root = $proj; routingConfidence = 0.99; routingEvidence = 'test' }
                    classification = @{ reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false; manualTestClass = 'none' }
                    scores = [PSCustomObject]@{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2; total = 20; rubricVersion = 'triage-v1' }
                    contract = [PSCustomObject]@{
                        objective = 'review test'; allowedPaths = @('tests'); forbiddenPaths = @()
                        doneWhen = @('pass')
                        verifyCommands = @(@{ executable = 'pwsh'; arguments = @('-NoProfile', '-Command', 'exit 0'); workingDirectory = '.'; timeoutSeconds = 30 })
                    }
                    eligible = $true; ineligibleReasons = @()
                }
                $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand
                $branch = [string]$item.execution.branch
                git -C $proj checkout -b $branch 2>$null | Out-Null
                $runDir = Join-Path $root "runs\$($item.id)\run-001"
                New-Item -ItemType Directory -Path $runDir -Force | Out-Null
                Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'queued' -To 'claimed' -Reason 'test' | Out-Null
                Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'claimed' -To 'implementing' -Reason 'test' | Out-Null
                Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'implementing' -To 'reviewing' -Reason 'test' -Mutator {
                    param($i)
                    if (-not $i.execution) { $i | Add-Member -NotePropertyName execution -NotePropertyValue ([PSCustomObject]@{}) -Force }
                    $i.execution | Add-Member -NotePropertyName runDir -NotePropertyValue $runDir -Force
                    $i.execution | Add-Member -NotePropertyName runNumber -NotePropertyValue 1 -Force
                    $i.execution | Add-Member -NotePropertyName baselineSha -NotePropertyValue (Get-LoomGitHeadCommit -ProjectRoot $proj) -Force
                    return $i
                } | Out-Null
                New-LoomRunRequestPackage -Item (Get-MetraLoomQueueItem -Root $root -Id $item.id) -RunDir $runDir | Out-Null

                $r = Invoke-MetraLoomReview -Root $root -ItemId $item.id -DryRun
                $r.dryRun | Should -BeTrue
                (Get-MetraLoomQueueItem -Root $root -Id $item.id).status | Should -Be 'reviewing'
            }
            finally {
                Remove-Item -LiteralPath $root, $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom review completion path' {
    It 'transitions reviewing to completed with mocked adapters and commit' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-rev-' + [guid]::NewGuid().ToString('n'))
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-rev-p-' + [guid]::NewGuid().ToString('n'))
            $branch = $null
            try {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                Push-Location $proj
                git init 2>$null | Out-Null
                git config user.email 't@test.local' 2>$null | Out-Null
                git config user.name 'T' 2>$null | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $proj 'tests') -Force | Out-Null
                Set-Content -Path (Join-Path $proj 'tests\ok.txt') -Value 'ok'
                git add tests/ok.txt 2>$null | Out-Null
                git commit -m 'init' 2>$null | Out-Null
                Pop-Location

                Initialize-MetraLoomLayout -Root $root
                $cand = [PSCustomObject]@{
                    id = 'CAND-20260901-0100'; summary = 'Review complete test'
                    source = [PSCustomObject]@{ type = 'operator' }
                    project = [PSCustomObject]@{ registryName = 'Metra'; root = $proj; routingConfidence = 0.99; routingEvidence = 'test' }
                    classification = @{ reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false; manualTestClass = 'none' }
                    scores = [PSCustomObject]@{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2; total = 20; rubricVersion = 'triage-v1' }
                    contract = [PSCustomObject]@{
                        objective = 'review test'; allowedPaths = @('tests'); forbiddenPaths = @()
                        doneWhen = @('pass')
                        verifyCommands = @(@{ executable = 'pwsh'; arguments = @('-NoProfile', '-Command', 'exit 0'); workingDirectory = '.'; timeoutSeconds = 30 })
                    }
                    eligible = $true; ineligibleReasons = @()
                }
                $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand
                $branch = [string]$item.execution.branch
                git -C $proj checkout -b $branch 2>$null | Out-Null
                if ((Get-LoomGitCurrentBranch -ProjectRoot $proj) -ne $branch) {
                    git -C $proj checkout -B $branch 2>$null | Out-Null
                }
                (Get-LoomGitCurrentBranch -ProjectRoot $proj) | Should -Be $branch
                Set-Content -Path (Join-Path $proj 'tests\change.txt') -Value 'x'
                git -C $proj add tests/change.txt 2>$null | Out-Null
                $runDir = Join-Path $root "runs\$($item.id)\run-001"
                New-Item -ItemType Directory -Path $runDir -Force | Out-Null
                Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'queued' -To 'claimed' -Reason 'test' | Out-Null
                Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'claimed' -To 'implementing' -Reason 'test' | Out-Null
                Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'implementing' -To 'reviewing' -Reason 'test' -Mutator {
                    param($i)
                    if (-not $i.execution) { $i | Add-Member -NotePropertyName execution -NotePropertyValue ([PSCustomObject]@{}) -Force }
                    $i.execution | Add-Member -NotePropertyName runDir -NotePropertyValue $runDir -Force
                    $i.execution | Add-Member -NotePropertyName runNumber -NotePropertyValue 1 -Force
                    $i.execution | Add-Member -NotePropertyName baselineSha -NotePropertyValue (Get-LoomGitHeadCommit -ProjectRoot $proj) -Force
                    return $i
                } | Out-Null
                New-LoomRunRequestPackage -Item (Get-MetraLoomQueueItem -Root $root -Id $item.id) -RunDir $runDir | Out-Null

                $inspect = { param($Request, $ProjectRoot, $RunDir)
                    [PSCustomObject]@{ schemaVersion = 1; outcome = 'passed'; goalMet = $true; message = 'mock pass' }
                }
                $verify = { param($Request, $ProjectRoot, $RunDir)
                    [PSCustomObject]@{ schemaVersion = 1; outcome = 'passed'; passed = $true; message = 'mock pass' }
                }

                $r = Invoke-MetraLoomReview -Root $root -ItemId $item.id -Confirm -InspectScript $inspect -VerifyScript $verify
                $r.outcome | Should -Be 'completed'
                (Get-MetraLoomQueueItem -Root $root -Id $item.id).status | Should -Be 'completed'
                (Get-MetraLoomQueueItem -Root $root -Id $item.id).execution.completedCommit | Should -Not -BeNullOrEmpty
            }
            finally {
                if ($branch -and (Test-Path $proj)) {
                    git -C $proj checkout master 2>$null | Out-Null
                    git -C $proj branch -D $branch 2>$null | Out-Null
                }
                Remove-Item -LiteralPath $root, $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'blocks direct completed without evidence' {
        InModuleScope Loom {
            Test-LoomCanTransitionToCompleted -From 'reviewing' -ReviewState $null | Should -BeFalse
        }
    }
}

Describe 'Loom review identity' {
    It 'rejects resume when implementationRunId mismatches current run' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-id-' + [guid]::NewGuid().ToString('n'))
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-id-p-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                Push-Location $proj
                git init 2>$null | Out-Null
                git config user.email 't@test.local' 2>$null | Out-Null
                git config user.name 'T' 2>$null | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $proj 'tests') -Force | Out-Null
                Set-Content -Path (Join-Path $proj 'tests\ok.txt') -Value 'ok'
                git add tests/ok.txt 2>$null | Out-Null
                git commit -m 'init' 2>$null | Out-Null
                Pop-Location

                Initialize-MetraLoomLayout -Root $root
                $cand = [PSCustomObject]@{
                    id = 'CAND-20260901-0200'; summary = 'Identity mismatch test'
                    source = [PSCustomObject]@{ type = 'operator' }
                    project = [PSCustomObject]@{ registryName = 'Metra'; root = $proj; routingConfidence = 0.99; routingEvidence = 'test' }
                    classification = @{ reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false; manualTestClass = 'none' }
                    scores = [PSCustomObject]@{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2; total = 20; rubricVersion = 'triage-v1' }
                    contract = [PSCustomObject]@{
                        objective = 'id test'; allowedPaths = @('tests'); forbiddenPaths = @()
                        doneWhen = @('pass')
                        verifyCommands = @(@{ executable = 'pwsh'; arguments = @('-NoProfile', '-Command', 'exit 0'); workingDirectory = '.'; timeoutSeconds = 30 })
                    }
                    eligible = $true; ineligibleReasons = @()
                }
                $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand
                $branch = [string]$item.execution.branch
                git -C $proj checkout -b $branch 2>$null | Out-Null
                $runDir = Join-Path $root "runs\$($item.id)\run-002"
                New-Item -ItemType Directory -Path $runDir -Force | Out-Null
                Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'queued' -To 'claimed' -Reason 'test' | Out-Null
                Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'claimed' -To 'implementing' -Reason 'test' | Out-Null
                Invoke-MetraLoomStateChange -Root $root -ItemId $item.id -From 'implementing' -To 'reviewing' -Reason 'test' -Mutator {
                    param($i)
                    if (-not $i.execution) { $i | Add-Member -NotePropertyName execution -NotePropertyValue ([PSCustomObject]@{}) -Force }
                    $i.execution | Add-Member -NotePropertyName runDir -NotePropertyValue $runDir -Force
                    $i.execution | Add-Member -NotePropertyName runNumber -NotePropertyValue 2 -Force
                    $i.execution | Add-Member -NotePropertyName baselineSha -NotePropertyValue (Get-LoomGitHeadCommit -ProjectRoot $proj) -Force
                    return $i
                } | Out-Null

                $staleIdentity = [PSCustomObject]@{
                    schemaVersion       = 1
                    queueItemId         = $item.id
                    implementationRunId = "$($item.id)-run-001"
                    reviewRunId         = [guid]::NewGuid().ToString('n')
                    sourceCommit        = (Get-LoomGitHeadCommit -ProjectRoot $proj)
                    itemBranch          = $branch
                    contractDigest      = (Get-LoomContractDigest -Contract $item.contract)
                    runDir              = $runDir
                    registryName        = 'Metra'
                }
                $state = [PSCustomObject]@{
                    schemaVersion  = 1
                    identity       = $staleIdentity
                    counters       = [PSCustomObject]@{ reviewCycleCount = 0; inspectRecoveryAttemptCount = 0; implementationAttemptCount = 0; verificationAttemptCount = 0 }
                    inspectOutcome = ''
                    verifyOutcome  = ''
                }
                Save-LoomReviewState -RunDir $runDir -State $state | Out-Null

                $itemNow = Get-MetraLoomQueueItem -Root $root -Id $item.id
                $check = Test-LoomReviewIdentity -Item $itemNow -Identity $staleIdentity -RunDir $runDir -ProjectRoot $proj -LoomRoot $root -ExistingReviewState $state
                $check.ok | Should -BeFalse
                $check.reason | Should -Be 'implementation-run-mismatch'
            }
            finally {
                Remove-Item -LiteralPath $root, $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom verify adapter contract normalization' {
    It 'applies defaults to hashtable verify command entries' {
        InModuleScope Loom {
            $cmd = ConvertTo-LoomStructuredVerifyCommand -Command @{ executable = 'pwsh' }
            $cmd.executable | Should -Be 'pwsh'
            $cmd.workingDirectory | Should -Be '.'
            $cmd.timeoutSeconds | Should -Be 900
            @($cmd.arguments).Count | Should -Be 0
        }
    }
}
Describe 'Loom verify adapter' {
    It 'rejects path escape in workingDirectory' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-v-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                { Resolve-LoomVerifyWorkingDirectory -ProjectRoot $proj -WorkingDirectory '..\escape' } |
                    Should -Throw '*project root*'
            }
            finally {
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
