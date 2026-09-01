# Requires Pester 5+. Isolation gate: must pass WITHOUT Import-Module Metra.psd1.
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Loom"

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    # Prove Metra is not required
    Get-Module Metra -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
}

Describe 'Loom isolation gate' {
    It 'loads without Metra.psm1' {
        Get-Module Loom | Should -Not -BeNullOrEmpty
        Get-Module Metra -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'exposes status catalog and Phase A active transitions' {
        $catalog = @(Get-LoomStatusCatalog)
        $catalog | Should -Contain 'queued'
        $catalog | Should -Contain 'accepted'
        $catalog | Should -Contain 'completed'
        @(Get-LoomActiveTransitions -From '@new') | Should -Contain 'queued'
        @(Get-LoomActiveTransitions -From 'queued') | Should -Contain 'blocked'
        @(Get-LoomActiveTransitions -From 'queued') | Should -Contain 'claimed'
        @(Get-LoomActiveTransitions -From 'queued') | Should -Not -Contain 'accepted'
    }

    It 'writes queue/journal state without Metra storage helpers' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-iso-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $root
                Add-MetraLoomJournalEntry -Root $root -Entry @{ itemId = 'AP-1'; to = 'queued' }
                $path = Get-MetraLoomJournalPath -Root $root
                @([System.IO.File]::ReadAllLines($path)).Count | Should -Be 1
                Test-MetraLoomTransition -From '@new' -To 'queued' | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'enforces ID guards without Metra PathWithinRoot' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-iso-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $root
                { Get-MetraLoomQueueItemPath -Root $root -Id '..\evil' } | Should -Throw '*Invalid*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'inspect/verify adapters fail closed without full request context' {
        InModuleScope Loom {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ap-adapt-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            try {
                (Invoke-LoomInspectAdapter -Request @{ schemaVersion = 1 }).outcome | Should -Be 'adapter-unavailable'
                (Invoke-LoomVerifyAdapter -Request @{ schemaVersion = 1; verifyCommands = @() } -ProjectRoot $tmp -RunDir $tmp).outcome | Should -Be 'invalid-contract'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'uses Metra mutex prefix for Phase A serialization compatibility' {
        $storage = Join-Path $script:RepoRoot 'modules\Loom\Private\Storage\Storage.ps1'
        $text = Get-Content -LiteralPath $storage -Raw
        $text | Should -Match 'Local\\Metra_\$Name'
        $text | Should -Not -Match 'Local\\Loom_'
    }
}
