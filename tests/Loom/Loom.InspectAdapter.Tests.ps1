# Slice 4 inspect adapter — outcome enum, engine classification.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
}

Describe 'ConvertTo-LoomInspectOutcomeFromEngine' {
    It 'maps quota errors to terminal-engine-failure' {
        InModuleScope Loom {
            ConvertTo-LoomInspectOutcomeFromEngine -LoopResult $null -Message 'usage limit exceeded' |
                Should -Be 'terminal-engine-failure'
        }
    }

    It 'maps transient errors to transient-engine-failure' {
        InModuleScope Loom {
            ConvertTo-LoomInspectOutcomeFromEngine -LoopResult $null -Message 'sidecar unavailable' |
                Should -Be 'transient-engine-failure'
        }
    }

    It 'maps clean counts to passed' {
        InModuleScope Loom {
            $loop = [PSCustomObject]@{ CriticalCount = 0; HighCount = 0; MediumCount = 1; TerminationReason = '' }
            ConvertTo-LoomInspectOutcomeFromEngine -LoopResult $loop -Message '' | Should -Be 'passed'
        }
    }

    It 'maps regression termination to regression-reverted' {
        InModuleScope Loom {
            $loop = [PSCustomObject]@{ CriticalCount = 0; HighCount = 0; MediumCount = 0; TerminationReason = 'regression reverted' }
            ConvertTo-LoomInspectOutcomeFromEngine -LoopResult $loop -Message '' | Should -Be 'regression-reverted'
        }
    }
}

Describe 'Invoke-LoomInspectAdapter' {
    It 'returns adapter-unavailable when inspect loop not loaded' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-ia-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-ir-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $r = Invoke-LoomInspectAdapter -Request ([PSCustomObject]@{ registryName = 'Metra' }) -ProjectRoot $proj -RunDir $run
                $r.outcome | Should -Be 'adapter-unavailable'
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'honors injected inspect script' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-ia-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-ir-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $sb = { param($Request, $ProjectRoot, $RunDir)
                    [PSCustomObject]@{ schemaVersion = 1; outcome = 'passed'; goalMet = $true; message = 'mock' }
                }
                $r = Invoke-LoomInspectAdapter -Request ([PSCustomObject]@{}) -ProjectRoot $proj -RunDir $run -InspectScript $sb
                $r.outcome | Should -Be 'passed'
                $r.goalMet | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
