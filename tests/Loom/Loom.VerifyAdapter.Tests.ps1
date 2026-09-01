# Slice 4 verify adapter — structured commands, root containment, fail-fast.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
}

Describe 'Loom verify adapter contract' {
    It 'returns invalid-contract when verifyCommands missing' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-va-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-vr-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $r = Invoke-LoomVerifyAdapter -Request ([PSCustomObject]@{ contract = [PSCustomObject]@{ verifyCommands = @() } }) -ProjectRoot $proj -RunDir $run
                $r.outcome | Should -Be 'invalid-contract'
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'runs structured command and captures stdout/stderr paths' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-va-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-vr-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $req = [PSCustomObject]@{
                    verifyCommands = @(@{
                            executable        = 'pwsh'
                            arguments         = @('-NoProfile', '-Command', 'Write-Output ok')
                            workingDirectory  = '.'
                            timeoutSeconds    = 30
                        })
                }
                $r = Invoke-LoomVerifyAdapter -Request $req -ProjectRoot $proj -RunDir $run
                $r.outcome | Should -Be 'passed'
                Test-Path -LiteralPath (Join-Path $run 'verify-1-stdout.log') | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'fails fast on non-zero exit' {
        InModuleScope Loom {
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-va-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-vr-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $req = [PSCustomObject]@{
                    verifyCommands = @(@{
                            executable        = 'pwsh'
                            arguments         = @('-NoProfile', '-Command', 'exit 7')
                            workingDirectory  = '.'
                            timeoutSeconds    = 30
                        })
                }
                $r = Invoke-LoomVerifyAdapter -Request $req -ProjectRoot $proj -RunDir $run
                $r.outcome | Should -Be 'command-failed'
                $r.exitCode | Should -Be 7
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
