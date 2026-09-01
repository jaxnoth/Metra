# Slice 3 branch runner tests.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Metra, AutoProgram -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\AutoProgram\AutoProgram.psd1') -Force

    function script:Initialize-AutoProgramTestGitRepo {
        param([Parameter(Mandatory)][string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Push-Location $Path
        try {
            git init 2>$null | Out-Null
            git config user.email 'autoprogram@test.local' 2>$null | Out-Null
            git config user.name 'AutoProgram Test' 2>$null | Out-Null
            Set-Content -Path (Join-Path $Path 'README.md') -Value '# autoprogram test repo'
            git add README.md 2>$null | Out-Null
            git commit -m 'init' 2>$null | Out-Null
        }
        finally {
            Pop-Location
        }
    }

    function script:New-AutoProgramTestQueueItem {
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
        return New-MetraAutoprogramQueueItemFromCandidate -Root $Root -Candidate $cand
    }
}

Describe 'AutoProgram Slice 3 transitions' {
    It 'allows queued -> claimed -> implementing -> reviewing' {
        Test-MetraAutoprogramTransition -From 'queued' -To 'claimed' | Should -BeTrue
        Test-MetraAutoprogramTransition -From 'claimed' -To 'implementing' | Should -BeTrue
        Test-MetraAutoprogramTransition -From 'implementing' -To 'reviewing' | Should -BeTrue
        Test-MetraAutoprogramTransition -From 'implementing' -To 'claimed' | Should -BeTrue
        Test-MetraAutoprogramTransition -From 'queued' -To 'reviewing' | Should -BeFalse
    }
}

Describe 'AutoProgram run dry-run' {
    It 'writes request.json without git or status change' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
        $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-proj-' + [guid]::NewGuid().ToString('n'))
        try {
            Initialize-AutoProgramTestGitRepo -Path $proj
            Initialize-MetraAutoprogramLayout -Root $root
            $item = New-AutoProgramTestQueueItem -Root $root -ProjectRoot $proj
            $result = Invoke-MetraAutoprogramRun -Root $root -ItemId $item.id -DryRun
            $result.dryRun | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $result.runDir 'request.json') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $result.runDir 'implementation.json') | Should -BeTrue
            (Get-MetraAutoprogramQueueItem -Root $root -Id $item.id).status | Should -Be 'queued'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'AutoProgram run live (git + implementer override)' {
    It 'blocks on dirty git baseline' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
        $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-proj-' + [guid]::NewGuid().ToString('n'))
        try {
            Initialize-AutoProgramTestGitRepo -Path $proj
            Set-Content -Path (Join-Path $proj 'dirty.txt') -Value 'x'
            Initialize-MetraAutoprogramLayout -Root $root
            $item = New-AutoProgramTestQueueItem -Root $root -ProjectRoot $proj
            { Invoke-MetraAutoprogramRun -Root $root -ItemId $item.id -Confirm } |
                Should -Throw '*not clean*'
            (Get-MetraAutoprogramQueueItem -Root $root -Id $item.id).status | Should -Be 'blocked'
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
            Initialize-AutoProgramTestGitRepo -Path $proj
            New-Item -ItemType Directory -Path (Join-Path $proj 'tests') -Force | Out-Null
            Initialize-MetraAutoprogramLayout -Root $root
            $item = New-AutoProgramTestQueueItem -Root $root -ProjectRoot $proj
            $branchName = [string]$item.execution.branch
            $impl = {
                param($Request, $ProjectRoot, $RunDir)
                $target = Join-Path $ProjectRoot 'tests\runner-ok.txt'
                Set-Content -Path $target -Value 'ok'
                git -C $ProjectRoot add tests/runner-ok.txt 2>$null | Out-Null
                return [PSCustomObject]@{ schemaVersion = 1; status = 'ok'; message = 'test ok'; exitCode = 0 }
            }
            $result = Invoke-MetraAutoprogramRun -Root $root -ItemId $item.id -Confirm -ImplementerScript $impl
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
            Initialize-AutoProgramTestGitRepo -Path $proj
            Initialize-MetraAutoprogramLayout -Root $root
            $item = New-AutoProgramTestQueueItem -Root $root -ProjectRoot $proj
            $impl = {
                param($Request, $ProjectRoot, $RunDir)
                Set-Content -Path (Join-Path $ProjectRoot 'evil-outside.txt') -Value 'nope'
                git -C $ProjectRoot add evil-outside.txt 2>$null | Out-Null
                return [PSCustomObject]@{ schemaVersion = 1; status = 'ok'; message = 'test ok'; exitCode = 0 }
            }
            { Invoke-MetraAutoprogramRun -Root $root -ItemId $item.id -Confirm -ImplementerScript $impl } |
                Should -Throw '*violate contract*'
            (Get-MetraAutoprogramQueueItem -Root $root -Id $item.id).status | Should -Be 'blocked'
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
            Initialize-AutoProgramTestGitRepo -Path $proj
            Initialize-MetraAutoprogramLayout -Root $root
            $item = New-AutoProgramTestQueueItem -Root $root -ProjectRoot $proj
            $impl = {
                return [PSCustomObject]@{
                    schemaVersion = 1; status = 'failed'
                    message = 'Your team has reached its usage limit'
                    exitCode = 1
                }
            }
            { Invoke-MetraAutoprogramRun -Root $root -ItemId $item.id -Confirm -ImplementerScript $impl } |
                Should -Throw '*licensing_error*'
            (Get-MetraAutoprogramQueueItem -Root $root -Id $item.id).status | Should -Be 'blocked'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'AutoProgram implementer failure classifier' {
    It 'classifies licensing vs transient errors' {
        InModuleScope AutoProgram {
            (Get-AutoProgramImplementerFailureClass -Message 'usage limit reached').failureClass | Should -Be 'licensing_error'
            (Get-AutoProgramImplementerFailureClass -Message 'connection reset by peer').failureClass | Should -Be 'transient'
        }
    }
}

Describe 'AutoProgram changed-path scope' {
    It 'rejects paths that escape project root' {
        InModuleScope AutoProgram {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-scope-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $proj -Force | Out-Null
            try {
                $scope = Test-AutoProgramChangedPathsAllowed -ChangedPaths @('..\outside.txt') `
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
        InModuleScope AutoProgram {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-scope-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $proj -Force | Out-Null
            try {
                $scope = Test-AutoProgramChangedPathsAllowed -ChangedPaths @('docs-archive/x.txt') `
                    -ProjectRoot $proj -AllowedPaths @('docs-archive') -ForbiddenPaths @('docs')
                $scope.allowed | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'preserves dotfile names when normalizing' {
        InModuleScope AutoProgram {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-dot-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $proj -Force | Out-Null
            try {
                $norm = Get-AutoProgramNormalizedRepoRelativePath -RelativePath './.env' -ProjectRoot $proj
                $norm | Should -Be '.env'
            }
            finally {
                Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'AutoProgram git cleanup after failed run' {
    It 'does not delete the item branch when checkout back to original fails' {
        InModuleScope AutoProgram {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-gitcl-' + [guid]::NewGuid().ToString('n'))
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
                git checkout -b 'ap/test-item' 2>$null | Out-Null
                $itemBranch = (git rev-parse --abbrev-ref HEAD).Trim()
                $itemBranch | Should -Be 'ap/test-item'

                Restore-AutoProgramGitAfterFailedRun -ProjectRoot $proj -BaselineSha $baseline `
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
}
