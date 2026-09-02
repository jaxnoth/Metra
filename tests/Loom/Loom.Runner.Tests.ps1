# Slice 3 branch runner tests.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Metra, Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force

    function script:Initialize-LoomTestGitRepo {
        param([Parameter(Mandatory)][string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Push-Location $Path
        try {
            git init 2>$null | Out-Null
            git config user.email 'autoprogram@test.local' 2>$null | Out-Null
            git config user.name 'Loom Test' 2>$null | Out-Null
            Set-Content -Path (Join-Path $Path 'README.md') -Value '# autoprogram test repo'
            git add README.md 2>$null | Out-Null
            git commit -m 'init' 2>$null | Out-Null
        }
        finally {
            Pop-Location
        }
    }

    function script:New-LoomTestQueueItem {
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][string]$ProjectRoot
        )
        $cand = [PSCustomObject]@{
            id             = 'CAND-20260831-0099'
            summary        = 'Runner test item'
            source         = [PSCustomObject]@{ type = 'operator' }
            project        = [PSCustomObject]@{
                registryName = 'Metra'; root = $ProjectRoot
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
                objective = 'runner test'; allowedPaths = @('tests'); forbiddenPaths = @('docs/Decisions.md')
                doneWhen = @('pass'); verifyCommands = @('.\metra.ps1 verify')
            }
            eligible       = $true
            ineligibleReasons = @()
        }
        return New-MetraLoomQueueItemFromCandidate -Root $Root -Candidate $cand
    }
}

Describe 'Loom Slice 3 transitions' {
    It 'allows queued -> claimed -> implementing -> reviewing' {
        Test-MetraLoomTransition -From 'queued' -To 'claimed' | Should -BeTrue
        Test-MetraLoomTransition -From 'claimed' -To 'implementing' | Should -BeTrue
        Test-MetraLoomTransition -From 'implementing' -To 'reviewing' | Should -BeTrue
        Test-MetraLoomTransition -From 'implementing' -To 'claimed' | Should -BeTrue
        Test-MetraLoomTransition -From 'queued' -To 'reviewing' | Should -BeFalse
    }
    It 'allows Slice 4 reviewing exits' {
        Test-MetraLoomTransition -From 'reviewing' -To 'completed' | Should -BeTrue
        Test-MetraLoomTransition -From 'reviewing' -To 'implementing' | Should -BeTrue
        Test-MetraLoomTransition -From 'reviewing' -To 'blocked' | Should -BeTrue
        Test-MetraLoomTransition -From 'reviewing' -To 'failed' | Should -BeFalse
    }
    It 'allows Slice 5 completed exits in map (approve runtime guard)' {
        Test-MetraLoomTransition -From 'completed' -To 'accepted' | Should -BeTrue
        Test-MetraLoomTransition -From 'completed' -To 'blocked' | Should -BeTrue
        Test-MetraLoomTransition -From 'completed' -To 'implementing' | Should -BeTrue
        Test-MetraLoomTransition -From 'completed' -To 'queued' | Should -BeFalse
    }
}

Describe 'Loom run dry-run' {
    It 'writes request.json without git or status change' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
        $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-proj-' + [guid]::NewGuid().ToString('n'))
        try {
            Initialize-LoomTestGitRepo -Path $proj
            Initialize-MetraLoomLayout -Root $root
            $item = New-LoomTestQueueItem -Root $root -ProjectRoot $proj
            $result = Invoke-MetraLoomRun -Root $root -ItemId $item.id -DryRun
            $result.dryRun | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $result.runDir 'request.json') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $result.runDir 'implementation.json') | Should -BeTrue
            (Get-MetraLoomQueueItem -Root $root -Id $item.id).status | Should -Be 'queued'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Loom run live (git + implementer override)' {
    It 'blocks on dirty git baseline' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
        $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-proj-' + [guid]::NewGuid().ToString('n'))
        try {
            Initialize-LoomTestGitRepo -Path $proj
            Set-Content -Path (Join-Path $proj 'dirty.txt') -Value 'x'
            Initialize-MetraLoomLayout -Root $root
            $item = New-LoomTestQueueItem -Root $root -ProjectRoot $proj
            { Invoke-MetraLoomRun -Root $root -ItemId $item.id -Confirm -ChainReview:$false } |
                Should -Throw '*not clean*'
            (Get-MetraLoomQueueItem -Root $root -Id $item.id).status | Should -Be 'blocked'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'advances to reviewing when implementer succeeds and paths are in scope' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
        $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-proj-' + [guid]::NewGuid().ToString('n'))
        $branchName = $null
        try {
            Initialize-LoomTestGitRepo -Path $proj
            New-Item -ItemType Directory -Path (Join-Path $proj 'tests') -Force | Out-Null
            Initialize-MetraLoomLayout -Root $root
            $item = New-LoomTestQueueItem -Root $root -ProjectRoot $proj
            $branchName = [string]$item.execution.branch
            $impl = {
                param($Request, $ProjectRoot, $RunDir)
                $target = Join-Path $ProjectRoot 'tests\runner-ok.txt'
                Set-Content -Path $target -Value 'ok'
                git -C $ProjectRoot add tests/runner-ok.txt 2>$null | Out-Null
                return [PSCustomObject]@{ schemaVersion = 1; status = 'ok'; message = 'test ok'; exitCode = 0 }
            }
            $result = Invoke-MetraLoomRun -Root $root -ItemId $item.id -Confirm -ChainReview:$false -ImplementerScript $impl
            $result.status | Should -Be 'reviewing'
            Test-Path -LiteralPath (Join-Path $result.runDir 'implementation.json') | Should -BeTrue
        }
        finally {
            if ($branchName -and (Test-Path -LiteralPath $proj)) {
                git -C $proj checkout master 2>$null | Out-Null
                git -C $proj branch -D $branchName 2>$null | Out-Null
            }
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks on out-of-scope path changes' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
        $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-proj-' + [guid]::NewGuid().ToString('n'))
        try {
            Initialize-LoomTestGitRepo -Path $proj
            Initialize-MetraLoomLayout -Root $root
            $item = New-LoomTestQueueItem -Root $root -ProjectRoot $proj
            $impl = {
                param($Request, $ProjectRoot, $RunDir)
                Set-Content -Path (Join-Path $ProjectRoot 'evil-outside.txt') -Value 'nope'
                git -C $ProjectRoot add evil-outside.txt 2>$null | Out-Null
                return [PSCustomObject]@{ schemaVersion = 1; status = 'ok'; message = 'test ok'; exitCode = 0 }
            }
            { Invoke-MetraLoomRun -Root $root -ItemId $item.id -Confirm -ChainReview:$false -ImplementerScript $impl } |
                Should -Throw '*violate contract*'
            (Get-MetraLoomQueueItem -Root $root -Id $item.id).status | Should -Be 'blocked'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks on licensing-class implementer failure' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
        $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-proj-' + [guid]::NewGuid().ToString('n'))
        try {
            Initialize-LoomTestGitRepo -Path $proj
            Initialize-MetraLoomLayout -Root $root
            $item = New-LoomTestQueueItem -Root $root -ProjectRoot $proj
            $impl = {
                return [PSCustomObject]@{
                    schemaVersion = 1; status = 'failed'
                    message = 'Your team has reached its usage limit'
                    exitCode = 1
                }
            }
            { Invoke-MetraLoomRun -Root $root -ItemId $item.id -Confirm -ChainReview:$false -ImplementerScript $impl } |
                Should -Throw '*licensing_error*'
            (Get-MetraLoomQueueItem -Root $root -Id $item.id).status | Should -Be 'blocked'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Loom implementer failure classifier' {
    It 'classifies licensing vs transient errors' {
        InModuleScope Loom {
            (Get-LoomImplementerFailureClass -Message 'usage limit reached').failureClass | Should -Be 'licensing_error'
            (Get-LoomImplementerFailureClass -Message 'connection reset by peer').failureClass | Should -Be 'transient'
        }
    }
}

Describe 'Loom changed-path scope' {
    It 'rejects paths that escape project root' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-scope-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $proj -Force | Out-Null
            try {
                $scope = Test-LoomChangedPathsAllowed -ChangedPaths @('..\outside.txt') `
                    -ProjectRoot $proj -AllowedPaths @('tests') -ForbiddenPaths @()
                $scope.allowed | Should -BeFalse
                ($scope.violations -join ',') | Should -Match 'escape:'
            }
            finally {
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'does not treat docs-archive as forbidden docs' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-scope-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $proj -Force | Out-Null
            try {
                $scope = Test-LoomChangedPathsAllowed -ChangedPaths @('docs-archive/x.txt') `
                    -ProjectRoot $proj -AllowedPaths @('docs-archive') -ForbiddenPaths @('docs')
                $scope.allowed | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'preserves dotfile names when normalizing' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-dot-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $proj -Force | Out-Null
            try {
                $norm = Get-LoomNormalizedRepoRelativePath -RelativePath './.env' -ProjectRoot $proj
                $norm | Should -Be '.env'
            }
            finally {
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'matches wildcard forbidden patterns on nested paths' {
        InModuleScope Loom {
            Test-LoomForbiddenPathMatch -NormalizedPath 'secrets/prod.env' -ForbiddenPattern '*.env' | Should -BeTrue
            Test-LoomForbiddenPathMatch -NormalizedPath 'config/api.key' -ForbiddenPattern '*.key' | Should -BeTrue
            Test-LoomForbiddenPathMatch -NormalizedPath 'docs/readme.md' -ForbiddenPattern 'docs' | Should -BeTrue
            Test-LoomForbiddenPathMatch -NormalizedPath 'mydocs/x' -ForbiddenPattern 'docs' | Should -BeFalse
        }
    }
}

Describe 'Loom git cleanup after failed run' {
    It 'does not delete the item branch when checkout back to original fails' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-gitcl-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                Push-Location $proj
                git init 2>$null | Out-Null
                git config user.email 'autoprogram@test.local' 2>$null | Out-Null
                git config user.name 'Loom Test' 2>$null | Out-Null
                Set-Content -Path (Join-Path $proj 'README.md') -Value 'init'
                git add README.md 2>$null | Out-Null
                git commit -m 'init' 2>$null | Out-Null
                $baseline = (git rev-parse HEAD).Trim()
                git checkout -b 'ap/test-item' 2>$null | Out-Null
                $itemBranch = (git rev-parse --abbrev-ref HEAD).Trim()
                $itemBranch | Should -Be 'ap/test-item'

                Restore-LoomGitAfterFailedRun -ProjectRoot $proj -BaselineSha $baseline `
                    -OriginalBranch 'missing-original-branch' -ItemBranch $itemBranch

                (git rev-parse --abbrev-ref HEAD).Trim() | Should -Be $itemBranch
                (git branch --list $itemBranch) | Should -Match $itemBranch
            }
            finally {
                Pop-Location
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'removes only run-created untracked files (delta cleanup)' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-gitclean-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj -Force | Out-Null
                Push-Location $proj
                git init 2>$null | Out-Null
                git config user.email 'autoprogram@test.local' 2>$null | Out-Null
                git config user.name 'AutoProgram Test' 2>$null | Out-Null
                Set-Content -Path (Join-Path $proj 'README.md') -Value 'init'
                git add README.md 2>$null | Out-Null
                git commit -m 'init' 2>$null | Out-Null
                $baseline = (git rev-parse HEAD).Trim()
                $originalBranch = (git rev-parse --abbrev-ref HEAD).Trim()
                git checkout -b 'ap/test-item' 2>$null | Out-Null
                $itemBranch = (git rev-parse --abbrev-ref HEAD).Trim()
                Set-Content -Path (Join-Path $proj 'operator-kept.txt') -Value 'pre-existing'
                $before = @(Get-LoomGitUntrackedPaths -ProjectRoot $proj)
                Set-Content -Path (Join-Path $proj 'implementer-scratch.txt') -Value 'left behind'
                Test-LoomGitWorkingTreeClean -ProjectRoot $proj | Should -BeFalse

                $runDir = Join-Path $proj 'run-evidence'
                Restore-LoomGitAfterFailedRun -ProjectRoot $proj -BaselineSha $baseline `
                    -OriginalBranch $originalBranch -ItemBranch $itemBranch `
                    -BeforeUntracked @($before) -RunDir $runDir

                Test-Path -LiteralPath (Join-Path $proj 'implementer-scratch.txt') | Should -BeFalse
                Test-Path -LiteralPath (Join-Path $proj 'operator-kept.txt') | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $runDir 'untracked-cleanup.json') | Should -BeTrue
            }
            finally {
                Pop-Location
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
