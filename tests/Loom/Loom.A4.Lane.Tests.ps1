# A4 lane identity, atomic claim, ordering, commit verify, ritual split.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force

    function script:New-A4Root {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('loom-a4-' + [guid]::NewGuid().ToString('n'))
        Initialize-MetraLoomLayout -Root $root
        return $root
    }

    function script:New-A4Item {
        param(
            [Parameter(Mandatory)][string]$Root,
            [string]$Id = 'AP-20260902-0001',
            [string]$ProjectKey = 'Metra',
            [string]$Status = 'queued',
            [double]$Total = 10,
            [double]$EffectiveImpact = 1,
            [string]$CreatedAt = '2026-09-01T10:00:00Z',
            [string]$ProjectRoot = $script:RepoRoot,
            [string]$Branch = 'loom/metra/2026-09-02/AP-test',
            [string]$BlockedFrom = $null,
            [switch]$OmitProjectKey,
            [switch]$LegacyRegistryOnly
        )
        $projName = if ($LegacyRegistryOnly) { $ProjectKey } else { $ProjectKey }
        $item = [PSCustomObject]@{
            schemaVersion  = 1
            id             = $Id
            summary        = 'A4 test'
            source         = [PSCustomObject]@{ type = 'operator' }
            project        = [PSCustomObject]@{
                registryName      = $projName
                root              = $ProjectRoot
                routingConfidence = 0.99
                routingEvidence   = 'test'
            }
            classification = @{
                reversibility = 'code'; crossRoot = $false; productionTouch = $false
                externalSideEffect = $false; manualTestClass = 'none'
            }
            scores         = [PSCustomObject]@{
                total = $Total; effectiveImpact = $EffectiveImpact; rubricVersion = 'triage-v1'
            }
            contract       = [PSCustomObject]@{
                objective = 'a4'; allowedPaths = @('tests'); forbiddenPaths = @()
                doneWhen = @('pass'); verifyCommands = @('.\metra.ps1 verify')
            }
            execution      = [PSCustomObject]@{ branch = $Branch }
            status         = $Status
            evidence       = @()
            createdAt      = $CreatedAt
            updatedAt      = $CreatedAt
        }
        if (-not $OmitProjectKey -and -not $LegacyRegistryOnly) {
            $item | Add-Member -NotePropertyName projectKey -NotePropertyValue $ProjectKey -Force
        }
        if ($BlockedFrom) {
            $item | Add-Member -NotePropertyName blockedFrom -NotePropertyValue $BlockedFrom -Force
        }
        Save-MetraLoomQueueItem -Root $Root -Item $item
        return $item
    }

    function script:New-A4GitProject {
        $proj = Join-Path ([IO.Path]::GetTempPath()) ('loom-a4-git-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $proj -Force | Out-Null
        git -C $proj init 2>$null | Out-Null
        git -C $proj config user.email 'a4@t.local' 2>$null | Out-Null
        git -C $proj config user.name 'a4' 2>$null | Out-Null
        Set-Content -Path (Join-Path $proj 'README.md') -Value 'a4'
        git -C $proj add README.md 2>$null | Out-Null
        git -C $proj commit -m init 2>$null | Out-Null
        git -C $proj branch -M main 2>$null | Out-Null
        return $proj
    }
}

Describe 'A4 projectKey identity' {
    It 'persists top-level projectKey on enqueue-from-candidate' {
        $root = New-A4Root
        try {
            $cand = [PSCustomObject]@{
                id = 'CAND-20260902-0001'; summary = 'pk'
                source = [PSCustomObject]@{ type = 'operator' }
                project = [PSCustomObject]@{ registryName = 'Metra'; root = $script:RepoRoot; routingConfidence = 0.99; routingEvidence = 't' }
                classification = @{ reversibility = 'code'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false; manualTestClass = 'none' }
                scores = [PSCustomObject]@{ impact = 4; confidence = 5; userTestBurden = 1; autoVerifiable = 5; dependencyValue = 2; total = 20; rubricVersion = 'triage-v1' }
                contract = [PSCustomObject]@{ objective = 'x'; allowedPaths = @('.'); forbiddenPaths = @(); doneWhen = @('pass'); verifyCommands = @('x') }
                eligible = $true; ineligibleReasons = @()
            }
            $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $cand
            $item.projectKey | Should -Be 'Metra'
            (Get-MetraLoomQueueItem -Root $root -Id $item.id).projectKey | Should -Be 'Metra'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'normalizes legacy registryName once under claim lock' {
        $root = New-A4Root
        try {
            New-A4Item -Root $root -Id 'AP-20260902-0001' -LegacyRegistryOnly -ProjectKey 'Metra' | Out-Null
            $before = Get-MetraLoomQueueItem -Root $root -Id 'AP-20260902-0001'
            [bool]$before.PSObject.Properties['projectKey'] | Should -BeFalse
            $claim = Invoke-MetraLoomClaimNextEligible -Root $root
            $claim.claimed | Should -BeTrue
            $after = Get-MetraLoomQueueItem -Root $root -Id 'AP-20260902-0001'
            $after.projectKey | Should -Be 'Metra'
            $after.status | Should -Be 'claimed'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses claim when projectKey missing' {
        $root = New-A4Root
        try {
            $item = New-A4Item -Root $root -OmitProjectKey -ProjectKey ''
            $item.project.registryName = ''
            Save-MetraLoomQueueItem -Root $root -Item $item
            $claim = Invoke-MetraLoomClaimNextEligible -Root $root
            $claim.claimed | Should -BeFalse
            (Get-MetraLoomQueueItem -Root $root -Id $item.id).status | Should -Be 'queued'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'treats Windows case variants as one lane' {
        $root = New-A4Root
        try {
            New-A4Item -Root $root -Id 'AP-20260902-0001' -ProjectKey 'Metra' -Status 'implementing' | Out-Null
            New-A4Item -Root $root -Id 'AP-20260902-0002' -ProjectKey 'metra' -Status 'queued' -Total 99 | Out-Null
            $claim = Invoke-MetraLoomClaimNextEligible -Root $root
            $claim.claimed | Should -BeFalse
            (Get-MetraLoomQueueItem -Root $root -Id 'AP-20260902-0002').status | Should -Be 'queued'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps distinct projectKeys independent' {
        $root = New-A4Root
        try {
            New-A4Item -Root $root -Id 'AP-20260902-0001' -ProjectKey 'Metra' -Status 'implementing' | Out-Null
            New-A4Item -Root $root -Id 'AP-20260902-0002' -ProjectKey 'Brightspace' -Status 'queued' -Total 5 | Out-Null
            $claim = Invoke-MetraLoomClaimNextEligible -Root $root
            $claim.claimed | Should -BeTrue
            $claim.queueItemId | Should -Be 'AP-20260902-0002'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'A4 lane-holding statuses' {
    $holding = @(
        @{ Status = 'claimed'; BlockedFrom = $null },
        @{ Status = 'implementing'; BlockedFrom = $null },
        @{ Status = 'reviewing'; BlockedFrom = $null },
        @{ Status = 'completed'; BlockedFrom = $null },
        @{ Status = 'accepted-pending-commit'; BlockedFrom = $null },
        @{ Status = 'blocked'; BlockedFrom = 'implementing' }
    )
    It 'blocks second claim when <Status> holds lane (blockedFrom=<BlockedFrom>)' -TestCases $holding {
        param($Status, $BlockedFrom)
        $root = New-A4Root
        try {
            New-A4Item -Root $root -Id 'AP-20260902-0001' -ProjectKey 'Metra' -Status $Status -BlockedFrom $BlockedFrom | Out-Null
            New-A4Item -Root $root -Id 'AP-20260902-0002' -ProjectKey 'Metra' -Status 'queued' -Total 50 | Out-Null
            $claim = Invoke-MetraLoomClaimNextEligible -Root $root
            $claim.claimed | Should -BeFalse
            (Get-MetraLoomQueueItem -Root $root -Id 'AP-20260902-0002').status | Should -Be 'queued'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not hold lane for intake-level blocked without blockedFrom' {
        $root = New-A4Root
        try {
            New-A4Item -Root $root -Id 'AP-20260902-0001' -ProjectKey 'Metra' -Status 'blocked' | Out-Null
            New-A4Item -Root $root -Id 'AP-20260902-0002' -ProjectKey 'Metra' -Status 'queued' -Total 5 | Out-Null
            $claim = Invoke-MetraLoomClaimNextEligible -Root $root
            $claim.claimed | Should -BeTrue
            $claim.queueItemId | Should -Be 'AP-20260902-0002'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'frees lane after accepted with verified commit' {
        $root = New-A4Root
        try {
            New-A4Item -Root $root -Id 'AP-20260902-0001' -ProjectKey 'Metra' -Status 'accepted' | Out-Null
            New-A4Item -Root $root -Id 'AP-20260902-0002' -ProjectKey 'Metra' -Status 'queued' -Total 5 | Out-Null
            $claim = Invoke-MetraLoomClaimNextEligible -Root $root
            $claim.claimed | Should -BeTrue
            $claim.queueItemId | Should -Be 'AP-20260902-0002'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'A4 atomic claim' {
    It 'allows only one active claim for a project' {
        $root = New-A4Root
        try {
            New-A4Item -Root $root -Id 'AP-20260902-0001' -ProjectKey 'Metra' -Total 10 | Out-Null
            New-A4Item -Root $root -Id 'AP-20260902-0002' -ProjectKey 'Metra' -Total 20 | Out-Null
            $c1 = Invoke-MetraLoomClaimNextEligible -Root $root
            $c2 = Invoke-MetraLoomClaimNextEligible -Root $root
            $c1.claimed | Should -BeTrue
            $c2.claimed | Should -BeFalse
            $active = @(Get-MetraLoomQueueItems -Root $root | Where-Object { $_.status -eq 'claimed' })
            $active.Count | Should -Be 1
            $active[0].id | Should -Be 'AP-20260902-0002'
            (Get-MetraLoomQueueItem -Root $root -Id 'AP-20260902-0001').status | Should -Be 'queued'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'journals queued->claimed inside claim path' {
        $root = New-A4Root
        try {
            New-A4Item -Root $root -Id 'AP-20260902-0001' -ProjectKey 'Metra' | Out-Null
            $claim = Invoke-MetraLoomClaimNextEligible -Root $root -Reason 'unit-claim'
            $claim.claimed | Should -BeTrue
            $entries = @(Get-MetraLoomJournalEntries -Root $root -On (Get-Date))
            $hit = @($entries | Where-Object {
                    [string]$_.itemId -eq 'AP-20260902-0001' -and
                    [string]$_.from -eq 'queued' -and
                    [string]$_.to -eq 'claimed'
                })
            $hit.Count | Should -BeGreaterThan 0
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'A4 ordering among free lanes' {
    It 'sorts total desc, effectiveImpact desc, createdAt asc, id asc and skips busy without mutation' {
        $root = New-A4Root
        try {
            New-A4Item -Root $root -Id 'AP-20260902-0001' -ProjectKey 'Metra' -Status 'implementing' -Total 99 -EffectiveImpact 9 | Out-Null
            New-A4Item -Root $root -Id 'AP-20260902-0002' -ProjectKey 'Brightspace' -Total 10 -EffectiveImpact 2 -CreatedAt '2026-09-02T12:00:00Z' | Out-Null
            New-A4Item -Root $root -Id 'AP-20260902-0003' -ProjectKey 'TicketTracker' -Total 10 -EffectiveImpact 5 -CreatedAt '2026-09-03T08:00:00Z' | Out-Null
            New-A4Item -Root $root -Id 'AP-20260902-0004' -ProjectKey 'Solarwinds' -Total 5 -EffectiveImpact 9 -CreatedAt '2026-09-01T08:00:00Z' | Out-Null
            $claim = Invoke-MetraLoomClaimNextEligible -Root $root
            $claim.claimed | Should -BeTrue
            $claim.queueItemId | Should -Be 'AP-20260902-0003'
            (Get-MetraLoomQueueItem -Root $root -Id 'AP-20260902-0001').status | Should -Be 'implementing'
            (Get-MetraLoomQueueItem -Root $root -Id 'AP-20260902-0002').status | Should -Be 'queued'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'A4 commit verification' {
    It 'records SHA on success and fails closed on root/branch/head mismatches' {
        $root = New-A4Root
        $proj = New-A4GitProject
        try {
            $sha = git -C $proj rev-parse HEAD
            $item = New-A4Item -Root $root -Id 'AP-20260902-0001' -ProjectKey 'Metra' -Status 'completed' -ProjectRoot $proj -Branch 'main'
            $item.execution | Add-Member -NotePropertyName baselineSha -NotePropertyValue $sha -Force
            Save-MetraLoomQueueItem -Root $root -Item $item

            $ok = Invoke-MetraLoomAcceptWithLocalCommitVerify -Root $root -ItemId $item.id -Acceptance ([PSCustomObject]@{
                    itemId = $item.id; acceptedAt = (Get-Date).ToString('o'); operator = 'test'
                })
            $ok.outcome | Should -Be 'accepted'
            $ok.status | Should -Be 'accepted'
            $ok.sha | Should -Be $sha
            $verified = Get-MetraLoomQueueItem -Root $root -Id $item.id
            $verified.commitVerification.state | Should -Be 'verified'
            $verified.commitVerification.sha | Should -Be $sha

            $again = Invoke-MetraLoomAcceptWithLocalCommitVerify -Root $root -ItemId $item.id -VerifyOnly
            $again.outcome | Should -BeIn @('already-accepted', 'already-verified')

            $item2 = New-A4Item -Root $root -Id 'AP-20260902-0002' -ProjectKey 'Brightspace' -Status 'completed' -ProjectRoot $proj -Branch 'wrong-branch'
            $fail = Invoke-MetraLoomAcceptWithLocalCommitVerify -Root $root -ItemId $item2.id -Acceptance ([PSCustomObject]@{
                    itemId = $item2.id; acceptedAt = (Get-Date).ToString('o'); operator = 'test'
                })
            $fail.outcome | Should -Be 'verify-failed'
            $fail.lastError | Should -Be 'branch-mismatch'
            (Get-MetraLoomQueueItem -Root $root -Id $item2.id).status | Should -Be 'accepted-pending-commit'

            $item3 = New-A4Item -Root $root -Id 'AP-20260902-0003' -ProjectKey 'TicketTracker' -Status 'completed' `
                -ProjectRoot (Join-Path $proj 'missing-subdir') -Branch 'main'
            $fail2 = Invoke-MetraLoomAcceptWithLocalCommitVerify -Root $root -ItemId $item3.id -Acceptance ([PSCustomObject]@{
                    itemId = $item3.id; acceptedAt = (Get-Date).ToString('o'); operator = 'test'
                })
            $fail2.outcome | Should -Be 'verify-failed'
            $fail2.lastError | Should -Be 'repository-root-missing'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not create commit/push/merge during verification' {
        $root = New-A4Root
        $proj = New-A4GitProject
        try {
            $before = git -C $proj rev-parse HEAD
            $item = New-A4Item -Root $root -Id 'AP-20260902-0001' -ProjectKey 'Metra' -Status 'completed' -ProjectRoot $proj -Branch 'main'
            Invoke-MetraLoomAcceptWithLocalCommitVerify -Root $root -ItemId $item.id -Acceptance ([PSCustomObject]@{
                    itemId = $item.id; operator = 'test'
                }) | Out-Null
            (git -C $proj rev-parse HEAD) | Should -Be $before
            (git -C $proj status --porcelain) | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'A4 ritual split' {
    It 'triage does not create Capture candidates' {
        $root = New-A4Root
        try {
            $r = Invoke-MetraLoomTriage -Root $root -MetraRoot $script:RepoRoot
            $r.captureTriageRemoved | Should -BeTrue
            $r.captureCount | Should -Be 0
            $caps = @($r.candidates | Where-Object { [string]$_.source.type -eq 'capture' })
            $caps.Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'daily intake points plan review at Yarn' {
        $root = New-A4Root
        try {
            $mockPack = {
                param($Name, $Base, $ProjectRoot)
                [PSCustomObject]@{ outcome = 'ok'; packPath = $null; message = 'noop' }
            }
            $result = Invoke-MetraLoomDailyBuild -Root $root -PackScript $mockPack
            $text = [System.IO.File]::ReadAllText($result.path)
            $text | Should -Match '## 3\. Plan review \(Yarn\)'
            $text | Should -Not -Match '## 3\. Next plan\(s\) for review'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'A4 lane helper single source' {
    It 'exposes one lane-holding status set consumed by busy helper' {
        InModuleScope Loom {
            $set = @(Get-MetraLoomLaneHoldingStatuses)
            $set | Should -Contain 'claimed'
            $set | Should -Contain 'accepted-pending-commit'
            $set | Should -Not -Contain 'accepted'
            $set | Should -Not -Contain 'queued'
            Test-MetraLoomStatusHoldsLane -Status 'blocked' -Item ([PSCustomObject]@{ blockedFrom = 'queued' }) | Should -BeFalse
            Test-MetraLoomStatusHoldsLane -Status 'blocked' -Item ([PSCustomObject]@{ blockedFrom = 'reviewing' }) | Should -BeTrue
        }
    }
}
