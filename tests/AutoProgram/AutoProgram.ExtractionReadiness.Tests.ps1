# Requires Pester 5+. Isolation gate: must pass WITHOUT Import-Module Metra.psd1.
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\AutoProgram"

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    # Prove Metra is not required
    Get-Module Metra -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\AutoProgram\AutoProgram.psd1') -Force
}

Describe 'AutoProgram isolation gate' {
    It 'loads without Metra.psm1' {
        Get-Module AutoProgram | Should -Not -BeNullOrEmpty
        Get-Module Metra -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'exposes status catalog and Phase A active transitions' {
        $catalog = @(Get-AutoProgramStatusCatalog)
        $catalog | Should -Contain 'queued'
        $catalog | Should -Contain 'accepted'
        $catalog | Should -Contain 'completed'
        @(Get-AutoProgramActiveTransitions -From '@new') | Should -Contain 'queued'
        @(Get-AutoProgramActiveTransitions -From 'queued') | Should -Contain 'blocked'
        @(Get-AutoProgramActiveTransitions -From 'queued') | Should -Contain 'claimed'
        @(Get-AutoProgramActiveTransitions -From 'queued') | Should -Not -Contain 'accepted'
    }

    It 'writes queue/journal state without Metra storage helpers' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-iso-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraAutoprogramLayout -Root $root
                Add-MetraAutoprogramJournalEntry -Root $root -Entry @{ itemId = 'AP-1'; to = 'queued' }
                $path = Get-MetraAutoprogramJournalPath -Root $root
                @([System.IO.File]::ReadAllLines($path)).Count | Should -Be 1
                Test-MetraAutoprogramTransition -From '@new' -To 'queued' | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'enforces ID guards without Metra PathWithinRoot' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-iso-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraAutoprogramLayout -Root $root
                { Get-MetraAutoprogramQueueItemPath -Root $root -Id '..\evil' } | Should -Throw '*Invalid*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'inspect/verify adapters return not-implemented stubs' {
        (Invoke-AutoProgramInspectAdapter -Request @{ schemaVersion = 1 }).status | Should -Be 'not-implemented'
        (Invoke-AutoProgramVerifyAdapter -Request @{ schemaVersion = 1 }).status | Should -Be 'not-implemented'
    }

    It 'uses Metra mutex prefix for Phase A serialization compatibility' {
        $storage = Join-Path $script:RepoRoot 'modules\AutoProgram\Private\Storage\Storage.ps1'
        $text = Get-Content -LiteralPath $storage -Raw
        $text | Should -Match 'Local\\Metra_\$Name'
        $text | Should -Not -Match 'Local\\AutoProgram_'
    }
}
