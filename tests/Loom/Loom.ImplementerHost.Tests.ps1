# Metra Loom implementer host - structured failures and launcher contract (no live SDK).
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Metra, Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'scripts\Metra.psd1') -Force
}

Describe 'Invoke-MetraLoomImplementer export' {
    It 'is exported and discoverable after importing Metra' {
        $cmd = Get-Command Invoke-MetraLoomImplementer -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
        $cmd.Source | Should -Match 'Metra'
    }
}

Describe 'Invoke-MetraLoomImplementer host matrix' {
    BeforeEach {
        $script:proj = Join-Path ([IO.Path]::GetTempPath()) ('metra-impl-proj-' + [guid]::NewGuid().ToString('n'))
        $script:run = Join-Path ([IO.Path]::GetTempPath()) ('metra-impl-run-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:proj, $script:run -Force | Out-Null
        $script:req = [PSCustomObject]@{
            schemaVersion = 1
            itemId        = 'AP-HOST-1'
            projectRoot   = $script:proj
            summary       = 'host test'
            planBody      = '# test'
        }
    }
    AfterEach {
        Remove-Item -LiteralPath $script:proj, $script:run -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'persists in-memory request as request.json' {
        $p = @{ Proj = $script:proj; Run = $script:run; Req = $script:req }
        InModuleScope Metra -Parameters $p {
            param($Proj, $Run, $Req)
            Mock Get-MetraAskNodePath { return (Join-Path $env:WINDIR 'System32\cmd.exe') }
            Mock Get-MetraCursorApiKey { return 'test-secret-key-value-xyz' }
            $runDir = $Run
            $launcher = {
                param($NodePath, $ScriptPath, $RequestPath, $ProjectRoot, $ApiKey, $CursorModel, $CursorOptimizeFor)
                Test-Path -LiteralPath $RequestPath | Should -BeTrue
                $RequestPath | Should -Be ([IO.Path]::GetFullPath((Join-Path $runDir 'request.json')))
                return [PSCustomObject]@{
                    ExitCode = 0
                    StdOut   = '{"schemaVersion":1,"status":"completed","message":"ok"}'
                    StdErr   = ''
                    Arguments = "`"$ScriptPath`" --request `"$RequestPath`""
                    WorkingDirectory = $ProjectRoot
                }
            }.GetNewClosure()
            $r = Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run -Launcher $launcher
            $r.status | Should -Be 'completed'
            Test-Path -LiteralPath (Join-Path $Run 'request.json') | Should -BeTrue
        }
    }

    It 'starts child with ProjectRoot as working directory' {
        $p = @{ Proj = $script:proj; Run = $script:run; Req = $script:req }
        InModuleScope Metra -Parameters $p {
            param($Proj, $Run, $Req)
            Mock Get-MetraAskNodePath { return (Join-Path $env:WINDIR 'System32\cmd.exe') }
            Mock Get-MetraCursorApiKey { return 'test-secret-key-value-xyz' }
            $script:seenCwd = $null
            $launcher = {
                param($NodePath, $ScriptPath, $RequestPath, $ProjectRoot, $ApiKey, $CursorModel, $CursorOptimizeFor)
                $script:seenCwd = $ProjectRoot
                return [PSCustomObject]@{
                    ExitCode = 0
                    StdOut   = '{"schemaVersion":1,"status":"ok","message":"ok"}'
                    StdErr   = ''
                    Arguments = 'node --request x'
                    WorkingDirectory = $ProjectRoot
                }
            }
            $null = Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run -Launcher $launcher
            $script:seenCwd | Should -Be ([IO.Path]::GetFullPath($Proj))
        }
    }

    It 'keeps API key out of arguments and returned output' {
        $p = @{ Proj = $script:proj; Run = $script:run; Req = $script:req }
        InModuleScope Metra -Parameters $p {
            param($Proj, $Run, $Req)
            Mock Get-MetraAskNodePath { return (Join-Path $env:WINDIR 'System32\cmd.exe') }
            Mock Get-MetraCursorApiKey { return 'test-secret-key-value-xyz' }
            $launcher = {
                param($NodePath, $ScriptPath, $RequestPath, $ProjectRoot, $ApiKey, $CursorModel, $CursorOptimizeFor)
                return [PSCustomObject]@{
                    ExitCode = 0
                    StdOut   = '{"schemaVersion":1,"status":"completed","message":"done"}'
                    StdErr   = 'diag line'
                    Arguments = "`"$ScriptPath`" --request `"$RequestPath`""
                    WorkingDirectory = $ProjectRoot
                }
            }
            $r = Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run -Launcher $launcher
            ($r | ConvertTo-Json -Depth 5) | Should -Not -Match 'test-secret-key-value-xyz'
            $r.status | Should -Be 'completed'
        }
    }

    It 'accepts valid ok and completed results' {
        $p = @{ Proj = $script:proj; Run = $script:run; Req = $script:req }
        InModuleScope Metra -Parameters $p {
            param($Proj, $Run, $Req)
            Mock Get-MetraAskNodePath { return (Join-Path $env:WINDIR 'System32\cmd.exe') }
            Mock Get-MetraCursorApiKey { return 'test-secret-key-value-xyz' }
            $okLauncher = {
                param($NodePath, $ScriptPath, $RequestPath, $ProjectRoot, $ApiKey, $CursorModel, $CursorOptimizeFor)
                [PSCustomObject]@{ ExitCode = 0; StdOut = '{"schemaVersion":1,"status":"ok","message":"m"}'; StdErr = ''; Arguments = 'a'; WorkingDirectory = $ProjectRoot }
            }
            $doneLauncher = {
                param($NodePath, $ScriptPath, $RequestPath, $ProjectRoot, $ApiKey, $CursorModel, $CursorOptimizeFor)
                [PSCustomObject]@{ ExitCode = 0; StdOut = '{"schemaVersion":1,"status":"completed","message":"m"}'; StdErr = ''; Arguments = 'a'; WorkingDirectory = $ProjectRoot }
            }
            (Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run -Launcher $okLauncher).status | Should -Be 'ok'
            (Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run -Launcher $doneLauncher).status | Should -Be 'completed'
        }
    }

    It 'maps nonzero exit, empty stdout, malformed JSON, unsupported status to structured failure' {
        $p = @{ Proj = $script:proj; Run = $script:run; Req = $script:req }
        InModuleScope Metra -Parameters $p {
            param($Proj, $Run, $Req)
            Mock Get-MetraAskNodePath { return (Join-Path $env:WINDIR 'System32\cmd.exe') }
            Mock Get-MetraCursorApiKey { return 'test-secret-key-value-xyz' }

            $nonzero = {
                param($NodePath, $ScriptPath, $RequestPath, $ProjectRoot, $ApiKey, $CursorModel, $CursorOptimizeFor)
                [PSCustomObject]@{ ExitCode = 7; StdOut = '{"schemaVersion":1,"status":"failed","message":"usage limit reached"}'; StdErr = 'x'; Arguments = 'a'; WorkingDirectory = $ProjectRoot }
            }
            $r1 = Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run -Launcher $nonzero
            $r1.status | Should -Be 'failed'
            $r1.message | Should -Match 'usage limit'

            $empty = {
                param($NodePath, $ScriptPath, $RequestPath, $ProjectRoot, $ApiKey, $CursorModel, $CursorOptimizeFor)
                [PSCustomObject]@{ ExitCode = 1; StdOut = ''; StdErr = 'boom'; Arguments = 'a'; WorkingDirectory = $ProjectRoot }
            }
            $r2 = Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run -Launcher $empty
            $r2.status | Should -Be 'failed'
            $r2.message | Should -Match 'Empty stdout'
            $r2.stderr | Should -Match 'boom'

            $badJson = {
                param($NodePath, $ScriptPath, $RequestPath, $ProjectRoot, $ApiKey, $CursorModel, $CursorOptimizeFor)
                [PSCustomObject]@{ ExitCode = 0; StdOut = 'not-json'; StdErr = ''; Arguments = 'a'; WorkingDirectory = $ProjectRoot }
            }
            $r3 = Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run -Launcher $badJson
            $r3.status | Should -Be 'failed'
            $r3.message | Should -Match 'Malformed JSON'

            $badStatus = {
                param($NodePath, $ScriptPath, $RequestPath, $ProjectRoot, $ApiKey, $CursorModel, $CursorOptimizeFor)
                [PSCustomObject]@{ ExitCode = 0; StdOut = '{"schemaVersion":1,"status":"weird","message":"x"}'; StdErr = ''; Arguments = 'a'; WorkingDirectory = $ProjectRoot }
            }
            $r4 = Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run -Launcher $badStatus
            $r4.status | Should -Be 'failed'
            $r4.message | Should -Match 'Unsupported status'
        }
    }

    It 'returns structured failure for missing ProjectRoot and Node launch exception' {
        $p = @{ Proj = $script:proj; Run = $script:run; Req = $script:req }
        InModuleScope Metra -Parameters $p {
            param($Proj, $Run, $Req)
            Mock Get-MetraAskNodePath { return (Join-Path $env:WINDIR 'System32\cmd.exe') }
            Mock Get-MetraCursorApiKey { return 'test-secret-key-value-xyz' }
            $r = Invoke-MetraLoomImplementer -Request $Req -ProjectRoot (Join-Path $Proj 'missing') -RunDir $Run
            $r.status | Should -Be 'failed'
            $r.message | Should -Match 'does not exist'

            $throwLauncher = {
                param($NodePath, $ScriptPath, $RequestPath, $ProjectRoot, $ApiKey, $CursorModel, $CursorOptimizeFor)
                throw 'cannot start'
            }
            $r2 = Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run -Launcher $throwLauncher
            $r2.status | Should -Be 'failed'
            $r2.message | Should -Match 'Node launch failure'
        }
    }

    It 'returns structured failure when API key missing' {
        $p = @{ Proj = $script:proj; Run = $script:run; Req = $script:req }
        InModuleScope Metra -Parameters $p {
            param($Proj, $Run, $Req)
            Mock Get-MetraAskNodePath { return (Join-Path $env:WINDIR 'System32\cmd.exe') }
            Mock Get-MetraCursorApiKey { return '' }
            $r = Invoke-MetraLoomImplementer -Request $Req -ProjectRoot $Proj -RunDir $Run
            $r.status | Should -Be 'failed'
            $r.message | Should -Match 'CURSOR_API_KEY|authentication'
        }
    }

    It 'adapter boundary: Loom adapter does not throw on host launch failure' {
        $proj = $script:proj
        $run = $script:run
        Get-Module Loom -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
        InModuleScope Loom -Parameters @{ Proj = $proj; Run = $run } {
            param($Proj, $Run)
            function script:Invoke-MetraLoomImplementer {
                param($Request, $ProjectRoot, $RunDir)
                throw 'simulated launch exception'
            }
            $r = Invoke-LoomImplementerAdapter -Request ([PSCustomObject]@{}) -ProjectRoot $Proj -RunDir $Run
            $r.status | Should -Be 'failed'
            $r.message | Should -Match 'simulated launch'
        }
    }
}
