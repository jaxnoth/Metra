# Slice 3 implementer adapter - Metra host import contract (no Pester Mock; Pester 6 InModuleScope conflict).
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:LoomManifest = Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1'
}

BeforeEach {
    Get-Module Metra, Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:LoomManifest -Force
}

Describe 'Invoke-LoomImplementerAdapter host import' {
    It 'imports Metra host exactly once when command initially missing then resolves' {
        InModuleScope Loom {
            $script:importHits = 0
            function Import-LoomMetraHostModule {
                param([string]$MetraRoot = (Get-LoomHostRoot))
                $script:importHits++
                function script:Invoke-MetraLoomImplementer {
                    param($Request, $ProjectRoot, $RunDir)
                    return [PSCustomObject]@{
                        schemaVersion = 1
                        status        = 'completed'
                        message       = 'mock host'
                        exitCode      = 0
                    }
                }
                return $true
            }

            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-impl-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $r = Invoke-LoomImplementerAdapter -Request ([PSCustomObject]@{ itemId = 'AP-1' }) -ProjectRoot $proj -RunDir $run
                $r.status | Should -Be 'completed'
                $script:importHits | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'returns adapter-unavailable when import helper returns false' {
        InModuleScope Loom {
            $script:importHits = 0
            function Import-LoomMetraHostModule {
                param([string]$MetraRoot = (Get-LoomHostRoot))
                $script:importHits++
                return $false
            }
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-impl-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $r = Invoke-LoomImplementerAdapter -Request ([PSCustomObject]@{}) -ProjectRoot $proj -RunDir $run
                $r.status | Should -Be 'adapter-unavailable'
                $r.message | Should -Match 'import failed'
                $script:importHits | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'returns adapter-unavailable when import throws' {
        InModuleScope Loom {
            $script:importHits = 0
            function Import-LoomMetraHostModule {
                param([string]$MetraRoot = (Get-LoomHostRoot))
                $script:importHits++
                throw 'import boom'
            }
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-impl-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $r = Invoke-LoomImplementerAdapter -Request ([PSCustomObject]@{}) -ProjectRoot $proj -RunDir $run
                $r.status | Should -Be 'adapter-unavailable'
                $r.message | Should -Match 'import failed'
                $script:importHits | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'returns adapter-unavailable when host still missing after successful import' {
        InModuleScope Loom {
            $script:importHits = 0
            function Import-LoomMetraHostModule {
                param([string]$MetraRoot = (Get-LoomHostRoot))
                $script:importHits++
                return $true
            }
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-impl-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $r = Invoke-LoomImplementerAdapter -Request ([PSCustomObject]@{}) -ProjectRoot $proj -RunDir $run
                $r.status | Should -Be 'adapter-unavailable'
                $r.message | Should -Match 'not loaded'
                $script:importHits | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'does not import when host already present' {
        InModuleScope Loom {
            $script:importHits = 0
            function Import-LoomMetraHostModule {
                param([string]$MetraRoot = (Get-LoomHostRoot))
                $script:importHits++
                throw 'should not import'
            }
            function script:Invoke-MetraLoomImplementer {
                param($Request, $ProjectRoot, $RunDir)
                return [PSCustomObject]@{
                    schemaVersion = 1
                    status        = 'ok'
                    message       = 'preloaded'
                    exitCode      = 0
                }
            }
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-impl-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $r = Invoke-LoomImplementerAdapter -Request ([PSCustomObject]@{}) -ProjectRoot $proj -RunDir $run
                $r.status | Should -Be 'ok'
                $script:importHits | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'normalizes host throw into structured failure' {
        InModuleScope Loom {
            function script:Invoke-MetraLoomImplementer {
                param($Request, $ProjectRoot, $RunDir)
                throw 'host exploded'
            }
            $proj = Join-Path ([IO.Path]::GetTempPath()) ('ap-impl-' + [guid]::NewGuid().ToString('n'))
            $run = Join-Path ([IO.Path]::GetTempPath()) ('ap-run-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $proj, $run -Force | Out-Null
                $r = Invoke-LoomImplementerAdapter -Request ([PSCustomObject]@{}) -ProjectRoot $proj -RunDir $run
                $r.status | Should -Be 'failed'
                $r.message | Should -Match 'host exploded'
            }
            finally {
                Remove-Item -LiteralPath $proj, $run -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'honors ImplementerScript override without import' {
        InModuleScope Loom {
            $script:importHits = 0
            function Import-LoomMetraHostModule {
                param([string]$MetraRoot = (Get-LoomHostRoot))
                $script:importHits++
                throw 'should not import'
            }
            $sb = {
                param($Request, $ProjectRoot, $RunDir)
                [PSCustomObject]@{ schemaVersion = 1; status = 'ok'; message = 'script'; exitCode = 0 }
            }
            $r = Invoke-LoomImplementerAdapter -Request ([PSCustomObject]@{}) -ProjectRoot 'C:\' -RunDir 'C:\' -ImplementerScript $sb
            $r.status | Should -Be 'ok'
            $script:importHits | Should -Be 0
        }
    }
}
