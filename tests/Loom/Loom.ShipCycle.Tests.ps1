# Loom ship-cycle: reviewed tuple, ship authority, adversarial env marker.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
}

Describe 'Loom ship-cycle work branch prefix' {
    It 'accepts bite/ loom/ and autoprogram/ prefixes' {
        InModuleScope Loom {
            Test-LoomWorkBranchName -Branch 'bite/metra/x' | Should -BeTrue
            Test-LoomWorkBranchName -Branch 'loom/metra/2026-01-01/AP-1' | Should -BeTrue
            Test-LoomWorkBranchName -Branch 'autoprogram/x' | Should -BeTrue
            Test-LoomWorkBranchName -Branch 'main' | Should -BeFalse
            Test-LoomExecutionBranchPrefix -Branch 'bite/metra/x' | Should -BeTrue
        }
    }
}

Describe 'Loom ship-cycle state and adversarial lock' {
    It 'persists reviewed tuple fields' {
        InModuleScope Loom {
            $proj = 'ShipCycleTest-' + [guid]::NewGuid().ToString('n').Substring(0, 8)
            $base = ('a' * 40)
            $head = ('b' * 40)
            $state = New-LoomShipStateObject -Project $proj -WorkBranch 'bite/metra/t' -TargetBranch 'main' `
                -BaseSha $base -HeadSha $head -ContentHash 'deadbeefcafe' -BiteId 't'
            Save-LoomShipState -State $state | Out-Null
            $loaded = Get-LoomShipState -Project $proj
            $loaded.baseSha | Should -Be $base
            $loaded.headSha | Should -Be $head
            $loaded.contentHash | Should -Be 'deadbeefcafe'
            $loaded.workBranch | Should -Be 'bite/metra/t'
            $loaded.targetBranch | Should -Be 'main'
            Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses bare METRA_LOOM_SHIP without lock token (adversarial N2)' {
        InModuleScope Loom {
            $proj = 'ShipAdv-' + [guid]::NewGuid().ToString('n').Substring(0, 8)
            $env:METRA_LOOM_SHIP = '1'
            Remove-Item Env:\METRA_LOOM_SHIP_TOKEN -ErrorAction SilentlyContinue
            Remove-Item Env:\METRA_LOOM_SHIP_PROJECT -ErrorAction SilentlyContinue
            try {
                Test-LoomShipHookBypassAllowed -Project $proj | Should -BeFalse
            }
            finally {
                Remove-Item Env:\METRA_LOOM_SHIP -ErrorAction SilentlyContinue
            }
        }
    }

    It 'allows bypass only with matching lock token (pid may differ for git hooks)' {
        InModuleScope Loom {
            $proj = 'ShipLock-' + [guid]::NewGuid().ToString('n').Substring(0, 8)
            $tuple = [PSCustomObject]@{
                targetBranch = 'main'
                workBranch   = 'bite/metra/x'
                baseSha      = ('1' * 40)
                headSha      = ('2' * 40)
                contentHash  = 'abc'
            }
            try {
                $lock = New-LoomShipLock -Project $proj -ReviewedTuple $tuple
                Test-LoomShipHookBypassAllowed -Project $proj | Should -BeTrue
                $env:METRA_LOOM_SHIP_TOKEN = 'wrong'
                Test-LoomShipHookBypassAllowed -Project $proj | Should -BeFalse
            }
            finally {
                Clear-LoomShipLock -Project $proj
                Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'blocks ship when verdict is changes-requested even if prose would say affirm' {
        InModuleScope Loom {
            $proj = 'ShipVerdict-' + [guid]::NewGuid().ToString('n').Substring(0, 8)
            $base = ('c' * 40)
            $head = ('d' * 40)
            $hash = 'hash1234'
            $state = New-LoomShipStateObject -Project $proj -WorkBranch 'bite/metra/v' -TargetBranch 'main' `
                -BaseSha $base -HeadSha $head -ContentHash $hash -BiteId 'v'
            Save-LoomShipState -State $state | Out-Null
            Set-LoomShipReviewEvidence -Name $proj -Verdict 'changes-requested' -ContentHash $hash -ContractShape | Out-Null
            # Ready check needs a real git root; without one, reasons include git failures - still must include review-verdict.
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ship-v-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $tmp -Force | Out-Null
                & git -C $tmp init -b main 2>$null | Out-Null
                & git -C $tmp config user.email 'ship@test.local'
                & git -C $tmp config user.name 'Ship Test'
                Set-Content -LiteralPath (Join-Path $tmp 'README.md') -Value 'x' -Encoding UTF8
                & git -C $tmp add README.md
                & git -C $tmp commit -m 'init' 2>$null | Out-Null
                $ready = Test-LoomShipReady -Name $proj -ProjectRoot $tmp -SkipFullTests
                $ready.ok | Should -BeFalse
                ($ready.reasons -join ',') | Should -Match 'review-verdict'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'orders multi-repo ship cookbook before chef before root' {
        InModuleScope Loom {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ship-m-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path (Join-Path $tmp 'cookbook') -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $tmp 'chef') -Force | Out-Null
                $ordered = @(Resolve-LoomShipRepoRoots -ProjectRoot $tmp -Repos @('root', 'chef', 'cookbook'))
                $ordered[0].Key | Should -Be 'cookbook'
                $ordered[1].Key | Should -Be 'chef'
                $ordered[2].Key | Should -Be 'root'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom ship-cycle temp repo start/pack/ship happy path' {
    It 'starts branch, packs offline, records approve, ships with --no-ff locally' {
        InModuleScope Loom {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ship-happy-' + [guid]::NewGuid().ToString('n'))
            $proj = 'HappyShip'
            try {
                New-Item -ItemType Directory -Path $tmp -Force | Out-Null
                & git -C $tmp init -b main | Out-Null
                & git -C $tmp config user.email 'ship@test.local'
                & git -C $tmp config user.name 'Ship Test'
                Set-Content -LiteralPath (Join-Path $tmp 'a.txt') -Value 'one' -Encoding UTF8
                & git -C $tmp add a.txt
                & git -C $tmp commit -m 'init' | Out-Null

                $start = Start-LoomShipBranch -Name $proj -Bite 'e2e' -ProjectRoot $tmp -Repos @('root') -TargetBranch 'main' -NoPush
                $start.ok | Should -BeTrue
                $start.workBranch | Should -Be 'bite/happyship/e2e'

                Set-Content -LiteralPath (Join-Path $tmp 'a.txt') -Value 'two' -Encoding UTF8
                $commit = Invoke-LoomShipCommit -Name $proj -Message 'change a' -ProjectRoot $tmp -SkipQuickCheck -NoPush
                $commit.ok | Should -BeTrue

                $pack = Invoke-LoomShipPack -Name $proj -ProjectRoot $tmp -SkipInspectEngine
                $pack.ok | Should -BeTrue
                $pack.contentHash | Should -Not -BeNullOrEmpty

                Set-LoomShipReviewEvidence -Name $proj -Verdict 'approve' -ContentHash $pack.contentHash -ContractShape | Out-Null
                $ship = Invoke-LoomShip -Name $proj -ProjectRoot $tmp -Summary 'e2e' -SkipFullTests -NoPush -NoDeleteBranch
                $ship.ok | Should -BeTrue
                $ship.shipped | Should -BeTrue

                $branch = (Invoke-LoomGit -ProjectRoot $tmp -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')).Stdout.Trim()
                $branch | Should -Be 'main'
                $parents = (Invoke-LoomGit -ProjectRoot $tmp -GitArgs @('rev-list', '--parents', '-n', '1', 'HEAD')).Stdout.Trim()
                # merge --no-ff has two parents
                (@($parents -split '\s+').Count) | Should -BeGreaterThan 1
            }
            finally {
                Clear-LoomShipLock -Project $proj -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
