# Loom storage migration tests (temp roots only — never touches live LOCALAPPDATA).

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Loom, Metra -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
}

Describe 'Loom migrate dry-run' {
    It 'dry-run performs no filesystem mutations when legacy source absent' {
        InModuleScope Loom {
            $dst = Join-Path ([IO.Path]::GetTempPath()) ('loom-mig-dst-' + [guid]::NewGuid().ToString('n'))
            try {
                $env:METRA_LOOM_ROOT = $dst
                try {
                    $r = Invoke-MetraLoomMigrate
                    $r.mode | Should -Be 'dry-run'
                    Test-Path -LiteralPath $dst | Should -BeFalse
                }
                finally {
                    Remove-Item Env:METRA_LOOM_ROOT -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom migrate apply' {
    It 'copy-first preserves source and preserves execution.branch verbatim' {
        InModuleScope Loom {
            $src = Join-Path ([IO.Path]::GetTempPath()) ('loom-mig-src-' + [guid]::NewGuid().ToString('n'))
            $dst = Join-Path ([IO.Path]::GetTempPath()) ('loom-mig-dst-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $src
                $branch = 'autoprogram/metra/2026-08-31/AP-20260831-0001'
                $item = [PSCustomObject]@{
                    schemaVersion = 1
                    id            = 'AP-20260831-0001'
                    summary       = 'migrate test'
                    status        = 'queued'
                    execution     = [PSCustomObject]@{ branch = $branch }
                    createdAt     = (Get-Date).ToString('o')
                    updatedAt     = (Get-Date).ToString('o')
                }
                Save-MetraLoomQueueItem -Root $src -Item $item

                $env:METRA_LOOM_ROOT = $dst
                try {
                    # Override legacy source by copying layout into known legacy path is heavy;
                    # test Copy-LoomStorageTree directly for branch preservation.
                    [void][System.IO.Directory]::CreateDirectory($dst)
                    $copy = Copy-LoomStorageTree -SourceRoot $src -DestRoot $dst
                    $copy.Copied | Should -BeGreaterThan 0

                    $migrated = Get-Content -LiteralPath (Join-Path $dst 'queue\AP-20260831-0001.json') -Raw | ConvertFrom-Json
                    [string]$migrated.execution.branch | Should -BeExactly $branch
                    Test-Path -LiteralPath (Join-Path $src 'queue\AP-20260831-0001.json') | Should -BeTrue
                }
                finally {
                    Remove-Item Env:METRA_LOOM_ROOT -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects -Force without -Apply' {
        InModuleScope Loom {
            { Invoke-MetraLoomMigrate -Force } | Should -Throw '*-Force requires -Apply*'
        }
    }

    It 'does not copy any files when a conflict is detected without -Force' {
        InModuleScope Loom {
            $src = Join-Path ([IO.Path]::GetTempPath()) ('loom-mig-src-' + [guid]::NewGuid().ToString('n'))
            $dst = Join-Path ([IO.Path]::GetTempPath()) ('loom-mig-dst-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $src
                $item = [PSCustomObject]@{
                    schemaVersion = 1
                    id            = 'AP-20260831-0002'
                    summary       = 'source item'
                    status        = 'queued'
                    createdAt     = (Get-Date).ToString('o')
                    updatedAt     = (Get-Date).ToString('o')
                }
                Save-MetraLoomQueueItem -Root $src -Item $item
                Add-MetraLoomJournalEntry -Root $src -Entry @{ itemId = $item.id; from = '@new'; to = 'queued' }

                [void][System.IO.Directory]::CreateDirectory((Join-Path $dst 'queue'))
                $conflictPath = Join-Path $dst 'queue\AP-20260831-0002.json'
                @{ id = 'AP-20260831-0002'; summary = 'different' } | ConvertTo-Json | Set-Content -LiteralPath $conflictPath

                $copy = Copy-LoomStorageTree -SourceRoot $src -DestRoot $dst
                $copy.Copied | Should -Be 0
                @($copy.Conflicts).Count | Should -BeGreaterThan 0
                Test-Path -LiteralPath (Join-Path $dst 'journal') | Should -BeFalse
                Test-Path -LiteralPath (Join-Path $dst 'state.json') | Should -BeFalse
            }
            finally {
                Remove-Item -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Loom legacy read-only commands' {
    It 'status does not initialize missing layout on legacy storage' {
        $savedLocal = $env:LOCALAPPDATA
        $tempLocal = Join-Path ([IO.Path]::GetTempPath()) ('loom-local-' + [guid]::NewGuid().ToString('n'))
        try {
            $env:LOCALAPPDATA = $tempLocal
            Remove-Item Env:METRA_LOOM_ROOT -ErrorAction SilentlyContinue

            InModuleScope Loom {
                $legacy = Get-LoomLegacyStorageRoot
                $queueDir = Join-Path $legacy 'queue'
                [void][System.IO.Directory]::CreateDirectory($queueDir)
                $item = [PSCustomObject]@{
                    schemaVersion = 1
                    id            = 'AP-20260831-0099'
                    summary       = 'legacy only'
                    status        = 'queued'
                    createdAt     = (Get-Date).ToString('o')
                    updatedAt     = (Get-Date).ToString('o')
                }
                Save-MetraLoomQueueItem -Root $legacy -Item $item

                $resolved = Resolve-MetraLoomRoot
                $resolved.IsReadOnly | Should -BeTrue
                $resolved.IsLegacy | Should -BeTrue

                $status = Invoke-LoomCommand -Subcommand status -MetraRoot (Get-LoomHostRoot)
                $status.totalItems | Should -Be 1
                Test-Path -LiteralPath (Join-Path $legacy 'state.json') | Should -BeFalse
                Test-Path -LiteralPath (Join-Path $legacy 'journal') | Should -BeFalse
            }
        }
        finally {
            if ($savedLocal) { $env:LOCALAPPDATA = $savedLocal }
            else { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $tempLocal -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Loom branch prefix validation' {
    It 'accepts loom/ and autoprogram/ prefixes only' {
        InModuleScope Loom {
            Test-LoomExecutionBranchPrefix -Branch 'loom/metra/2026-08-31/AP-1' | Should -BeTrue
            Test-LoomExecutionBranchPrefix -Branch 'autoprogram/metra/2026-08-31/AP-1' | Should -BeTrue
            Test-LoomExecutionBranchPrefix -Branch 'feature/foo' | Should -BeFalse
        }
    }
}

Describe 'Loom enqueue branch prefix' {
    It 'new enqueue uses loom/ branch template' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('loom-enq-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraLoomLayout -Root $root
                $candidate = [PSCustomObject]@{
                    id             = 'CAND-20260831-0001'
                    eligible       = $true
                    summary        = 'test'
                    ineligibleReasons = @()
                    source         = @{ type = 'formal-plan' }
                    project        = @{ registryName = 'Metra'; root = (Get-LoomHostRoot); routingConfidence = 0.9 }
                    classification = @{ reversibility = 'code' }
                    scores         = @{ total = 5 }
                    contract       = @{}
                }
                $item = New-MetraLoomQueueItemFromCandidate -Root $root -Candidate $candidate
                [string]$item.execution.branch | Should -Match '^loom/'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
