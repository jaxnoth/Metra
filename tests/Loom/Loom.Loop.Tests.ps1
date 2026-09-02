# Slice 6 unattended loop tests.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Metra, Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force

    function script:New-LoomLoopTestItem {
        param(
            [Parameter(Mandatory)][string]$Root,
            [string]$Id = 'AP-20260902-0001',
            [int]$Score = 10,
            [string]$CreatedAt = '2026-09-01T10:00:00Z',
            [hashtable]$Classification = $null,
            [string]$Registry = 'Metra',
            [string]$ProjectRoot = $script:RepoRoot
        )
        if (-not $Classification) {
            $Classification = @{
                reversibility      = 'code'
                crossRoot          = $false
                productionTouch    = $false
                externalSideEffect = $false
                manualTestClass    = 'none'
            }
        }
        $item = [PSCustomObject]@{
            schemaVersion  = 1
            id             = $Id
            summary        = 'Loop test item'
            source         = [PSCustomObject]@{ type = 'operator' }
            project        = [PSCustomObject]@{
                registryName      = $Registry
                root              = $ProjectRoot
                routingConfidence = 0.99
                routingEvidence   = 'test'
            }
            classification = $Classification
            scores         = [PSCustomObject]@{
                total = $Score; rubricVersion = 'triage-v1'
            }
            contract       = [PSCustomObject]@{
                objective      = 'loop test'
                allowedPaths   = @('tests')
                forbiddenPaths = @()
                doneWhen       = @('pass')
                verifyCommands = @('.\metra.ps1 verify')
            }
            execution      = [PSCustomObject]@{
                branch = 'loom/metra/2026-09-02/AP-test'
            }
            status         = 'queued'
            evidence       = @()
            createdAt      = $CreatedAt
            updatedAt      = $CreatedAt
        }
        Save-MetraLoomQueueItem -Root $Root -Item $item
        return $item
    }

    function script:New-LoomLoopTestRoot {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('loom-loop-' + [guid]::NewGuid().ToString('n'))
        Initialize-MetraLoomLayout -Root $root
        return $root
    }
}

Describe 'Loom unattended policy' {
    It 'rejects missing classification (fail closed)' {
        $root = New-LoomLoopTestRoot
        try {
            $item = New-LoomLoopTestItem -Root $root -Classification @{}
            $item.classification = $null
            Save-MetraLoomQueueItem -Root $root -Item $item
            $policy = Test-LoomUnattendedPolicy -Root $root -Item $item
            $policy.eligible | Should -BeFalse
            $policy.reasons | Should -Contain 'missing-classification'
        }
        finally {
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'accepts code-only eligible item' {
        $root = New-LoomLoopTestRoot
        try {
            $item = New-LoomLoopTestItem -Root $root
            $policy = Test-LoomUnattendedPolicy -Root $root -Item $item
            $policy.eligible | Should -BeTrue
        }
        finally {
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'rejects config reversibility' {
        $root = New-LoomLoopTestRoot
        try {
            $cls = @{
                reversibility = 'config'; crossRoot = $false; productionTouch = $false; externalSideEffect = $false
            }
            $item = New-LoomLoopTestItem -Root $root -Classification $cls
            $policy = Test-LoomUnattendedPolicy -Root $root -Item $item
            $policy.eligible | Should -BeFalse
            $policy.reasons | Should -Contain 'reversibility-not-code'
        }
        finally {
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Loom dequeue selection' {
    It 'sorts score desc then createdAt asc then id asc' {
        $root = New-LoomLoopTestRoot
        try {
            New-LoomLoopTestItem -Root $root -Id 'AP-20260902-0003' -Score 10 -CreatedAt '2026-09-02T12:00:00Z' | Out-Null
            New-LoomLoopTestItem -Root $root -Id 'AP-20260902-0001' -Score 10 -CreatedAt '2026-09-01T10:00:00Z' | Out-Null
            New-LoomLoopTestItem -Root $root -Id 'AP-20260902-0002' -Score 20 -CreatedAt '2026-09-03T08:00:00Z' | Out-Null
            $picked = @(Get-LoomEligibleQueuedItems -Root $root)
            $picked.Count | Should -Be 3
            $picked[0].id | Should -Be 'AP-20260902-0002'
            $picked[1].id | Should -Be 'AP-20260902-0001'
            $picked[2].id | Should -Be 'AP-20260902-0003'
        }
        finally {
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'returns empty when no queued eligible items' {
        $root = New-LoomLoopTestRoot
        try {
            @(Get-LoomEligibleQueuedItems -Root $root).Count | Should -Be 0
        }
        finally {
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Loom loop pause enforcement' {
    It 'emits pause reason and does not dequeue when loopPaused' {
        $root = New-LoomLoopTestRoot
        try {
            New-LoomLoopTestItem -Root $root | Out-Null
            Set-LoomLoopPauseState -Root $root -Paused $true -Reason 'inspect-license' | Out-Null
            $before = @(Get-MetraLoomJournalEntries -Root $root -On (Get-Date))
            $r = Invoke-MetraLoomLoop -Root $root -UntilDailyGate -DryRun
            $r.outcome | Should -Be 'paused'
            $r.pauseReason | Should -Be 'inspect-license'
            $r.pauseAge | Should -Not -BeNullOrEmpty
            @(Get-MetraLoomJournalEntries -Root $root -On (Get-Date)).Count | Should -Be $before.Count
        }
        finally {
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'respects pause on second invocation after Tier1 set' {
        $root = New-LoomLoopTestRoot
        try {
            New-LoomLoopTestItem -Root $root | Out-Null
            Set-LoomLoopPauseState -Root $root -Paused $true -Reason 'inspect-key_missing' | Out-Null
            $first = Invoke-MetraLoomLoop -Root $root -UntilDailyGate -DryRun
            $second = Invoke-MetraLoomLoop -Root $root -UntilDailyGate -DryRun
            $first.outcome | Should -Be 'paused'
            $second.outcome | Should -Be 'paused'
            $second.PSObject.Properties.Name | Should -Not -Contain 'selectedItemId'
        }
        finally {
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Loom loop dry-run' {
    It 'previews selection without queue mutations beyond existing items' {
        $root = New-LoomLoopTestRoot
        try {
            $item = New-LoomLoopTestItem -Root $root
            $before = Get-MetraLoomQueueItem -Root $root -Id $item.id
            $r = Invoke-MetraLoomLoop -Root $root -UntilDailyGate -DryRun
            $r.outcome | Should -Be 'dry-run'
            $r.selectedItemId | Should -Be $item.id
            $after = Get-MetraLoomQueueItem -Root $root -Id $item.id
            [string]$after.status | Should -Be 'queued'
        }
        finally {
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Loom loop live (mocked run)' {
    It 'journals harness-loop and completes via RunOverride' {
        function Global:Get-MetraAskCapability {
            return [PSCustomObject]@{
                available = $true; engineHealthy = $true; reason = 'ok'; message = ''
            }
        }
        $root = New-LoomLoopTestRoot
        try {
            $item = New-LoomLoopTestItem -Root $root
            $override = {
                param($p)
                $it = Get-MetraLoomQueueItem -Root $p.Root -Id $p.ItemId
                $it.status = 'completed'
                Save-MetraLoomQueueItem -Root $p.Root -Item $it
                Add-MetraLoomJournalEntry -Root $p.Root -Entry @{
                    itemId = $p.ItemId; from = 'loop'; to = 'completed'; actor = 'harness-loop'; reason = 'mock'
                }
                return [PSCustomObject]@{ ok = $true; mocked = $true }
            }
            Get-Module Loom | Remove-Module -Force
            Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
            $r = Invoke-MetraLoomLoop -Root $root -UntilDailyGate -Confirm -RunOverride $override
            $r.outcome | Should -Be 'completed'
            $entries = @(Get-MetraLoomJournalEntries -Root $root -On (Get-Date) | Where-Object { [string]$_.itemId -eq $item.id })
            @($entries | Where-Object { [string]$_.actor -eq 'harness-loop' }).Count | Should -BeGreaterThan 0
        }
        finally {
            Remove-Item Function:\Get-MetraAskCapability -ErrorAction SilentlyContinue
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Loom loop CLI dispatch' {
    It 'Invoke-LoomCommand loop -UntilDailyGate -DryRun works' {
        $root = New-LoomLoopTestRoot
        try {
            $env:METRA_LOOM_ROOT = $root
            New-LoomLoopTestItem -Root $root | Out-Null
            $r = Invoke-LoomCommand -Subcommand 'loop' -ArgsRest @('-UntilDailyGate', '-DryRun') -Root $root
            $r.outcome | Should -Be 'dry-run'
        }
        finally {
            Remove-Item Env:METRA_LOOM_ROOT -ErrorAction SilentlyContinue
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Loom loop engine Tier1 pause' {
    It 'sets enriched pause state on engine-stop confirm path' {
        $root = New-LoomLoopTestRoot
        try {
            New-LoomLoopTestItem -Root $root | Out-Null
            function Global:Get-MetraAskCapability {
                return [PSCustomObject]@{
                    available = $false; engineHealthy = $false; reason = 'key_missing'; message = 'no key'
                }
            }
            Get-Module Loom | Remove-Module -Force
            Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
            $r = Invoke-MetraLoomLoop -Root $root -UntilDailyGate -Confirm
            $r.outcome | Should -Be 'engine-stop'
            $pause = Get-LoomLoopPauseState -Root $root
            $pause.loopPaused | Should -BeTrue
            $pause.pauseReason | Should -Match 'inspect-key_missing'
            $pause.pausedAtUtc | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Item Function:\Get-MetraAskCapability -ErrorAction SilentlyContinue
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Loom daily intake loop paused section' {
    It 'includes loop paused block when state paused' {
        $root = New-LoomLoopTestRoot
        try {
            Set-LoomLoopPauseState -Root $root -Paused $true -Reason 'inspect-license' | Out-Null
            $section = Format-LoomLoopPausedIntakeSection -Root $root
            $section | Should -Match '## Loop paused'
            $section | Should -Match 'inspect-license'
        }
        finally {
            if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
