# Loom ship-cycle: reviewed tuple, ship authority, adversarial env marker.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
    $metraPsd1 = Join-Path $script:RepoRoot 'scripts\Metra.psd1'
    if (Test-Path -LiteralPath $metraPsd1) {
        Import-Module $metraPsd1 -Force -ErrorAction SilentlyContinue
    }
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
                $lock = New-LoomShipLock -Project $proj -ReviewedTuple $tuple -AuthorizedTargetBranches @('main', 'master')
                Test-LoomShipHookBypassAllowed -Project $proj | Should -BeTrue
                Test-LoomShipHookBypassAllowed -Project $proj -TargetBranch 'master' | Should -BeTrue
                Test-LoomShipHookBypassAllowed -Project $proj -TargetBranch 'develop' | Should -BeFalse
                $env:METRA_LOOM_SHIP_TOKEN = 'wrong'
                Test-LoomShipHookBypassAllowed -Project $proj | Should -BeFalse
            }
            finally {
                Clear-LoomShipLock -Project $proj
                Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'ship lock authorizes merge SHA for protected push and refuses unrelated SHA (Bing L1 B1)' {
        InModuleScope Loom {
            $proj = 'ShipMergeLock-' + [guid]::NewGuid().ToString('n').Substring(0, 8)
            $workHead = ('a' * 40)
            $mergeSha = ('b' * 40)
            $unrelated = ('c' * 40)
            $tuple = [PSCustomObject]@{
                targetBranch = 'main'
                workBranch   = 'bite/metra/x'
                baseSha      = ('1' * 40)
                headSha      = $workHead
                contentHash  = 'abc'
            }
            try {
                $null = New-LoomShipLock -Project $proj -ReviewedTuple $tuple `
                    -AuthorizedTargetBranches @('main') -AuthorizedHeadShas @($workHead)
                Test-LoomShipHookBypassAllowed -Project $proj -TargetBranch 'main' -HeadSha $workHead | Should -BeTrue
                Test-LoomShipHookBypassAllowed -Project $proj -TargetBranch 'main' -HeadSha $mergeSha | Should -BeFalse
                $updated = Update-LoomShipLockAuthorizedHeads -Project $proj -AuthorizedHeadShas @($mergeSha) `
                    -PrimaryHeadSha $mergeSha
                @($updated.authorizedHeadShas) | Should -Contain $mergeSha
                @($updated.authorizedHeadShas) | Should -Not -Contain $workHead
                Test-LoomShipHookBypassAllowed -Project $proj -TargetBranch 'main' -HeadSha $mergeSha | Should -BeTrue
                Test-LoomShipHookBypassAllowed -Project $proj -TargetBranch 'refs/heads/main' -HeadSha $mergeSha | Should -BeTrue
                Test-LoomShipHookBypassAllowed -Project $proj -TargetBranch 'main' -HeadSha $workHead | Should -BeFalse
                Test-LoomShipHookBypassAllowed -Project $proj -TargetBranch 'main' -HeadSha $unrelated | Should -BeFalse
            }
            finally {
                Clear-LoomShipLock -Project $proj
                Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Resolve-LoomShipProjectRoot containment-checks Name under portfolio parent (Bing L1 N1)' {
        InModuleScope Loom {
            { Resolve-LoomShipProjectRoot -Name '..' } | Should -Throw '*escapes portfolio parent*'
            { Resolve-LoomShipProjectRoot -Name '..\Windows' } | Should -Throw '*escapes portfolio parent*'
            $hostRoot = Get-LoomHostRoot
            $ok = Resolve-LoomShipProjectRoot -ProjectRoot $hostRoot -Name 'ignored'
            $ok | Should -Be ([System.IO.Path]::GetFullPath($hostRoot))
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
                & git -C (Join-Path $tmp 'cookbook') init -b master | Out-Null
                & git -C (Join-Path $tmp 'chef') init -b master | Out-Null
                & git -C $tmp init -b main | Out-Null
                $ordered = @(Resolve-LoomShipRepoRoots -ProjectRoot $tmp -Repos @('root', 'chef', 'cookbook'))
                $ordered[0].Key | Should -Be 'cookbook'
                $ordered[1].Key | Should -Be 'chef'
                $ordered[2].Key | Should -Be 'root'
                $ordered[0].RelativePath | Should -Be 'cookbook'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'requires root and rejects duplicate git top-levels' {
        InModuleScope Loom {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ship-n3-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $tmp -Force | Out-Null
                & git -C $tmp init -b main | Out-Null
                { Resolve-LoomShipRepoRoots -ProjectRoot $tmp -Repos @('chef') } | Should -Throw
                { Resolve-LoomShipRepoRoots -ProjectRoot $tmp -Repos @('root', 'root') } | Should -Throw
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'resolves biteRepoTargets per key; protectedBranches does not select nested targets' {
        InModuleScope Loom {
            $policy = [PSCustomObject]@{
                protectedBranches = @('main', 'master')
                biteRepoTargets   = @{ root = 'main'; chef = 'master' }
            }
            Resolve-LoomShipRepoTarget -Key 'root' -Policy $policy | Should -Be 'main'
            Resolve-LoomShipRepoTarget -Key 'chef' -Policy $policy | Should -Be 'master'
            $noMap = [PSCustomObject]@{ protectedBranches = @('main', 'master'); biteRepoTargets = @{} }
            { Resolve-LoomShipRepoTarget -Key 'chef' -Policy $noMap } | Should -Throw
        }
    }

    It 'persists schema v2 primaryRepoKey and repoStates' {
        InModuleScope Loom {
            $proj = 'ShipV2-' + [guid]::NewGuid().ToString('n').Substring(0, 8)
            $rs = New-LoomShipRepoStateObject -Key 'root' -RelativePath '.' -TargetBranch 'main' `
                -TargetTipSha ('a' * 40) -BaseSha ('b' * 40) -HeadSha ('c' * 40) -RangeHash 'dead' -PushStatus 'pending'
            $state = New-LoomShipStateObject -Project $proj -WorkBranch 'bite/x/y' -TargetBranch 'main' `
                -BaseSha ('b' * 40) -HeadSha ('c' * 40) -ContentHash 'comp' -BiteId 'y' `
                -PrimaryRepoKey 'root' -RepoStates @($rs) -ShipPhase 'active'
            Save-LoomShipState -State $state | Out-Null
            $loaded = Get-LoomShipState -Project $proj
            $loaded.schemaVersion | Should -Be 2
            $loaded.primaryRepoKey | Should -Be 'root'
            @($loaded.repoStates).Count | Should -Be 1
            $loaded.repoStates[0].targetTipSha | Should -Be ('a' * 40)
            Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Loom ship-cycle temp repo start/pack/ship happy path' {
    BeforeAll {
        $script:ShipCycleShareRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-shipcycle-share-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:ShipCycleShareRoot -Force | Out-Null
    }
    AfterAll {
        Remove-Item -LiteralPath $script:ShipCycleShareRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'starts branch, packs offline, records approve, ships with --no-ff locally' {
        InModuleScope Loom {
            Mock -ModuleName Metra Get-MetraShareRoot { $script:ShipCycleShareRoot }
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

                Mock Get-LoomShipProjectPolicy {
                    [PSCustomObject]@{
                        protectedBranches = @('main')
                        ownerAffirmPaths  = @()
                        biteRepos         = @('root')
                        biteRepoTargets   = @{ root = 'main' }
                        resolved          = $true
                    }
                }

                $start = Start-LoomShipBranch -Name $proj -Bite 'e2e' -ProjectRoot $tmp -Repos @('root') -TargetBranch 'main' -NoPush
                $start.ok | Should -BeTrue
                $start.workBranch | Should -Be 'bite/happyship/e2e'
                $start.primaryRepoKey | Should -Be 'root'

                Set-Content -LiteralPath (Join-Path $tmp 'a.txt') -Value 'two' -Encoding UTF8
                $commit = Invoke-LoomShipCommit -Name $proj -Message 'change a' -ProjectRoot $tmp -SkipQuickCheck -NoPush
                $commit.ok | Should -BeTrue

                $pack = Invoke-LoomShipPack -Name $proj -ProjectRoot $tmp -SkipInspectEngine
                $pack.ok | Should -BeTrue
                $pack.contentHash | Should -Not -BeNullOrEmpty
                Test-Path -LiteralPath $pack.multiRepoPackPath | Should -BeTrue
                (Get-Content -LiteralPath $pack.multiRepoPackPath -Raw) | Should -Match '## Repository: root'
                # B1: Bing contract pack (pack-diff) must carry composite ship evidence + same contentHash.
                $bingPack = Join-Path $env:LOCALAPPDATA ("Metra\inspect\{0}\pack-diff.md" -f $proj)
                if (Get-Command Publish-MetraInspectBingPackFromText -ErrorAction SilentlyContinue) {
                    Test-Path -LiteralPath $bingPack | Should -BeTrue
                    $bingBody = Get-Content -LiteralPath $bingPack -Raw
                    $bingBody | Should -Match '## Ship evidence \(authoritative\)'
                    $bingBody | Should -Match '## Repository: root'
                    ($bingBody -like ('*contentHash: {0}*' -f $pack.contentHash)) | Should -BeTrue
                    $handoff = Join-Path $env:LOCALAPPDATA ("Metra\inspect\{0}\handoff.md" -f $proj)
                    if (Test-Path -LiteralPath $handoff) {
                        ((Get-Content -LiteralPath $handoff -Raw) -like ('*{0}*' -f $pack.contentHash)) | Should -BeTrue
                    }
                }

                Set-LoomShipReviewEvidence -Name $proj -Verdict 'approve' -ContentHash $pack.contentHash -ContractShape | Out-Null
                $ship = Invoke-LoomShip -Name $proj -ProjectRoot $tmp -Summary 'e2e' -SkipFullTests -NoPush -NoDeleteBranch
                $ship.ok | Should -BeTrue
                $ship.shipped | Should -BeFalse
                $ship.shipPhase | Should -Be 'mergedLocal'
                $ship.lockKept | Should -BeTrue
                Test-Path -LiteralPath (Get-LoomShipStatePath -Project $proj) | Should -BeTrue
                Test-Path -LiteralPath (Get-LoomShipLockPath -Project $proj) | Should -BeTrue

                $branch = (Invoke-LoomGit -ProjectRoot $tmp -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')).Stdout.Trim()
                $branch | Should -Be 'main'
                $parents = (Invoke-LoomGit -ProjectRoot $tmp -GitArgs @('rev-list', '--parents', '-n', '1', 'HEAD')).Stdout.Trim()
                # merge --no-ff has two parents
                (@($parents -split '\s+').Count) | Should -BeGreaterThan 1
            }
            finally {
                Clear-LoomShipLock -Project $proj -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA ("Metra\inspect\{0}" -f $proj)) -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'packs and ships two repos with composite review sections (chef + root)' {
        InModuleScope Loom {
            Mock -ModuleName Metra Get-MetraShareRoot { $script:ShipCycleShareRoot }
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ship-2r-' + [guid]::NewGuid().ToString('n'))
            $proj = 'TwoRepoShip'
            $chef = Join-Path $tmp 'chef'
            try {
                New-Item -ItemType Directory -Path $tmp -Force | Out-Null
                New-Item -ItemType Directory -Path $chef -Force | Out-Null
                & git -C $tmp init -b main | Out-Null
                & git -C $chef init -b master | Out-Null
                & git -C $tmp config user.email 'ship@test.local'
                & git -C $tmp config user.name 'Ship Test'
                & git -C $chef config user.email 'ship@test.local'
                & git -C $chef config user.name 'Ship Test'
                # Nested git worktrees must be ignored by the parent (CDM-shaped layout).
                Set-Content -LiteralPath (Join-Path $tmp '.gitignore') -Value "chef/`n" -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $tmp 'f.txt') -Value 'one' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $chef 'f.txt') -Value 'one' -Encoding UTF8
                & git -C $tmp add .gitignore f.txt
                & git -C $tmp commit -m 'init' | Out-Null
                & git -C $chef add f.txt
                & git -C $chef commit -m 'init' | Out-Null

                Mock Get-LoomShipProjectPolicy {
                    [PSCustomObject]@{
                        protectedBranches = @('main', 'master')
                        ownerAffirmPaths  = @()
                        biteRepos         = @('root', 'chef')
                        biteRepoTargets   = @{ root = 'main'; chef = 'master' }
                        resolved          = $true
                    }
                }

                $start = Start-LoomShipBranch -Name $proj -Bite 'multi' -ProjectRoot $tmp -Repos @('root', 'chef') -NoPush
                $start.ok | Should -BeTrue
                @($start.repos) | Should -Contain 'chef'
                @($start.repos) | Should -Contain 'root'
                $start.workBranch | Should -Be 'bite/tworepoship/multi/root'
                $chefWb = @($start.repoStates | Where-Object { $_.key -eq 'chef' })[0].workBranch
                $rootWb = @($start.repoStates | Where-Object { $_.key -eq 'root' })[0].workBranch
                $chefWb | Should -Be 'bite/tworepoship/multi/chef'
                $rootWb | Should -Be 'bite/tworepoship/multi/root'
                $chefWb | Should -Not -Be $rootWb

                Set-Content -LiteralPath (Join-Path $tmp 'f.txt') -Value 'root-two' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $chef 'f.txt') -Value 'chef-two' -Encoding UTF8
                $null = Invoke-LoomShipCommit -Name $proj -Message 'change both' -ProjectRoot $tmp -SkipQuickCheck -NoPush

                $pack = Invoke-LoomShipPack -Name $proj -ProjectRoot $tmp -SkipInspectEngine
                $pack.ok | Should -BeTrue
                @($pack.repoStates).Count | Should -Be 2
                $body = Get-Content -LiteralPath $pack.multiRepoPackPath -Raw
                $body | Should -Match '## Repository: chef'
                $body | Should -Match '## Repository: root'
                $body | Should -Match 'chef-two'
                $body | Should -Match 'root-two'
                # Ship order in evidence: chef before root (N1).
                ($body.IndexOf('## Repository: chef')) | Should -BeLessThan ($body.IndexOf('## Repository: root'))
                $bingPack = Join-Path $env:LOCALAPPDATA ("Metra\inspect\{0}\pack-diff.md" -f $proj)
                if (Get-Command Publish-MetraInspectBingPackFromText -ErrorAction SilentlyContinue) {
                    $bingBody = Get-Content -LiteralPath $bingPack -Raw
                    $bingBody | Should -Match '## Ship evidence \(authoritative\)'
                    $bingBody | Should -Match '## Repository: chef'
                    $bingBody | Should -Match 'chef-two'
                    ($bingBody -like ('*contentHash: {0}*' -f $pack.contentHash)) | Should -BeTrue
                }

                Set-LoomShipReviewEvidence -Name $proj -Verdict 'approve' -ContentHash $pack.contentHash -ContractShape | Out-Null
                $ship = Invoke-LoomShip -Name $proj -ProjectRoot $tmp -Summary 'multi' -SkipFullTests -NoPush -NoDeleteBranch
                $ship.ok | Should -BeTrue
                $ship.shipped | Should -BeFalse
                $ship.shipPhase | Should -Be 'mergedLocal'
                $ship.lockKept | Should -BeTrue

                (Invoke-LoomGit -ProjectRoot $tmp -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')).Stdout.Trim() | Should -Be 'main'
                (Invoke-LoomGit -ProjectRoot $chef -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')).Stdout.Trim() | Should -Be 'master'
            }
            finally {
                Clear-LoomShipLock -Project $proj -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA ("Metra\inspect\{0}" -f $proj)) -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'pushes distinct remote refs when two worktrees share one bare remote' {
        InModuleScope Loom {
            Mock -ModuleName Metra Get-MetraShareRoot { $script:ShipCycleShareRoot }
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ship-share-' + [guid]::NewGuid().ToString('n'))
            $bare = Join-Path $tmp 'bare.git'
            $root = Join-Path $tmp 'root'
            $chef = Join-Path $root 'chef'
            $proj = 'SharedRemoteShip'
            try {
                New-Item -ItemType Directory -Path $tmp -Force | Out-Null
                & git init --bare $bare | Out-Null
                & git clone $bare $root | Out-Null
                & git -C $root checkout -b main 2>$null | Out-Null
                & git -C $root config user.email 'ship@test.local'
                & git -C $root config user.name 'Ship Test'
                Set-Content -LiteralPath (Join-Path $root '.gitignore') -Value "chef/`n" -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $root 'r.txt') -Value 'root-a' -Encoding UTF8
                & git -C $root add .gitignore r.txt
                & git -C $root commit -m 'root-init' | Out-Null
                & git -C $root push -u origin main | Out-Null

                New-Item -ItemType Directory -Path $chef -Force | Out-Null
                & git -C $chef init -b master | Out-Null
                & git -C $chef config user.email 'ship@test.local'
                & git -C $chef config user.name 'Ship Test'
                & git -C $chef remote add origin $bare
                Set-Content -LiteralPath (Join-Path $chef 'c.txt') -Value 'chef-a' -Encoding UTF8
                & git -C $chef add c.txt
                & git -C $chef commit -m 'chef-init' | Out-Null
                & git -C $chef push -u origin master | Out-Null

                Mock Get-LoomShipProjectPolicy {
                    [PSCustomObject]@{
                        protectedBranches = @('main', 'master')
                        ownerAffirmPaths  = @()
                        biteRepos         = @('root', 'chef')
                        biteRepoTargets   = @{ root = 'main'; chef = 'master' }
                        resolved          = $true
                    }
                }

                $start = Start-LoomShipBranch -Name $proj -Bite 'e4b' -ProjectRoot $root -Repos @('root', 'chef')
                $start.ok | Should -BeTrue
                $remoteRefs = @(& git -C $bare show-ref --heads)
                ($remoteRefs -join "`n") | Should -Match 'refs/heads/bite/sharedremoteship/e4b/root'
                ($remoteRefs -join "`n") | Should -Match 'refs/heads/bite/sharedremoteship/e4b/chef'
                ($remoteRefs -join "`n") | Should -Not -Match 'refs/heads/bite/sharedremoteship/e4b$'
            }
            finally {
                Clear-LoomShipLock -Project $proj -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'requires -Resume when shipPhase is partialShip' {
        InModuleScope Loom {
            $proj = 'PartialShip-' + [guid]::NewGuid().ToString('n').Substring(0, 8)
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ship-ps-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $tmp -Force | Out-Null
                & git -C $tmp init -b main | Out-Null
                & git -C $tmp config user.email 'ship@test.local'
                & git -C $tmp config user.name 'Ship Test'
                Set-Content -LiteralPath (Join-Path $tmp 'a.txt') -Value 'x' -Encoding UTF8
                & git -C $tmp add a.txt
                & git -C $tmp commit -m 'init' | Out-Null
                $head = (Invoke-LoomGit -ProjectRoot $tmp -GitArgs @('rev-parse', 'HEAD')).Stdout.Trim()
                $rs = New-LoomShipRepoStateObject -Key 'root' -RelativePath '.' -TargetBranch 'main' `
                    -TargetTipSha $head -BaseSha $head -HeadSha $head -RangeHash 'x' -MergeCommitSha $head -PushStatus 'pushed'
                $state = New-LoomShipStateObject -Project $proj -WorkBranch 'bite/x/p' -TargetBranch 'main' `
                    -BaseSha $head -HeadSha $head -ContentHash 'h' -BiteId 'p' -RepoStates @($rs) -ShipPhase 'partialShip'
                $state.reviewVerdict = 'approve'
                $state.reviewProvenance = [PSCustomObject]@{
                    source = 'test'; reviewDepth = 'L1'; evidenceInspected = @('pack')
                }
                Save-LoomShipState -State $state | Out-Null
                $blocked = Invoke-LoomShip -Name $proj -ProjectRoot $tmp -SkipFullTests -NoPush
                $blocked.ok | Should -BeFalse
                $blocked.shipPhase | Should -Be 'partialShip'
                ($blocked.reasons -join ',') | Should -Match 'partial-ship-resume-required'
            }
            finally {
                Clear-LoomShipLock -Project $proj -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Get-LoomShipStateRoot -Project $proj) -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
