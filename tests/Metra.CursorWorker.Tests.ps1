# Requires Pester 5+.
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.CursorWorker.Tests.ps1"

BeforeAll {
    $script:MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Metra Cursor Worker' {
    BeforeEach {
        $script:Tmp = Join-Path ([IO.Path]::GetTempPath()) ('cw-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Force -Path $script:Tmp | Out-Null
        $script:ConfigPath = Join-Path $script:Tmp 'cursor-worker.local.json'
        $script:RuntimePath = Join-Path $script:Tmp 'cursor-worker-runtime.json'
        $script:RepairPath = Join-Path $script:Tmp 'cursor-worker-repair.json'
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports Disabled when enabled is false' {
        @{
            schemaVersion = 1
            enabled       = $false
            name          = 'metra-host'
            workerDirs    = @($script:MetraRoot)
            idleReleaseTimeoutSeconds = 0
        } | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding utf8
        $st = Get-MetraCursorWorkerStatus -MetraRoot $script:MetraRoot -ConfigPath $script:ConfigPath `
            -RuntimePath $script:RuntimePath -RepairPath $script:RepairPath -SkipDebug
        $st.state | Should -Be 'Disabled'
        $st.enabled | Should -BeFalse
        $st.running | Should -BeFalse
    }

    It 'fail-closes foreign identity without treating it as Running' {
        @{
            schemaVersion = 1
            enabled       = $true
            name          = 'metra-host'
            workerDirs    = @($script:MetraRoot)
            idleReleaseTimeoutSeconds = 0
        } | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding utf8
        $cfg = Read-MetraCursorWorkerConfig -Path $script:ConfigPath -MetraRoot $script:MetraRoot
        $other = [IO.Path]::GetFullPath('C:\Other\Repo').TrimEnd('\', '/').ToLowerInvariant()
        $observed = @(
            [pscustomobject]@{
                ProcessId = 424242
                Name      = 'someone-else'
                Workspace = $other
            }
        )
        $id = Resolve-MetraCursorWorkerIdentity -Config $cfg -MetraRoot $script:MetraRoot `
            -RuntimePath $script:RuntimePath -Observed $observed
        $id.kind | Should -Be 'foreign'
        $id.identityOk | Should -BeFalse

        $st = Get-MetraCursorWorkerStatus -MetraRoot $script:MetraRoot -ConfigPath $script:ConfigPath `
            -RuntimePath $script:RuntimePath -RepairPath $script:RepairPath -SkipDebug -Observed $observed
        $st.state | Should -Be 'Error'
        $st.running | Should -BeFalse
        $st.identityOk | Should -BeFalse
        $st.lastError | Should -Match 'Foreign|ambiguous'
    }

    It 'classifies matching name and workspace as ours' {
        @{
            schemaVersion = 1
            enabled       = $true
            name          = 'metra-host'
            workerDirs    = @($script:MetraRoot)
            idleReleaseTimeoutSeconds = 0
        } | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding utf8
        $cfg = Read-MetraCursorWorkerConfig -Path $script:ConfigPath -MetraRoot $script:MetraRoot
        $ws = [IO.Path]::GetFullPath($script:MetraRoot).TrimEnd('\', '/').ToLowerInvariant()
        $observed = @(
            [pscustomobject]@{
                ProcessId = 111
                Name      = 'metra-host'
                Workspace = $ws
            }
        )
        $id = Resolve-MetraCursorWorkerIdentity -Config $cfg -MetraRoot $script:MetraRoot `
            -RuntimePath $script:RuntimePath -Observed $observed
        $id.kind | Should -Be 'ours'
        $id.identityOk | Should -BeTrue
    }

    It 'detects ABI error text for RepairRequired classification' {
        Test-MetraCursorWorkerAbiErrorText -Text 'NODE_MODULE_VERSION 127' | Should -BeTrue
        Test-MetraCursorWorkerAbiErrorText -Text 'was compiled against a different Node.js version' | Should -BeTrue
        Test-MetraCursorWorkerAbiErrorText -Text 'ordinary start failure' | Should -BeFalse
    }

    It 'refuses repair retry after failed attempt for same CLI version' {
        $cliVersion = $null
        $cli = Join-Path $env:LOCALAPPDATA 'cursor-agent\cursor-agent.ps1'
        if (Test-Path -LiteralPath $cli) {
            $verDir = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'cursor-agent\versions') -Directory |
                Where-Object { $_.Name -match '^\d{4}\.' } |
                Sort-Object Name -Descending |
                Select-Object -First 1
            if ($verDir) { $cliVersion = $verDir.Name }
        }
        if (-not $cliVersion) {
            Set-ItResult -Skipped -Because 'cursor-agent version directory not present'
            return
        }
        $ledger = [pscustomobject]@{
            schemaVersion        = 1
            lastRepairAttemptUtc = [datetime]::UtcNow.ToString('o')
            lastRepairVersion    = $cliVersion
            lastRepairOutcome    = 'failed'
        }
        Save-MetraCursorWorkerRepairLedger -Ledger $ledger -Path $script:RepairPath -MetraRoot $script:MetraRoot
        $result = Invoke-MetraCursorWorkerRepairSqlite -MetraRoot $script:MetraRoot -RepairPath $script:RepairPath
        $result.ok | Should -BeFalse
        $result.outcome | Should -Be 'skipped'
        $result.error | Should -Match 'refused'
    }

    It 'repair downloader failure records failed outcome without looping ensure' {
        $ledgerPath = $script:RepairPath
        $result = Invoke-MetraCursorWorkerRepairSqlite -MetraRoot $script:MetraRoot -RepairPath $ledgerPath -Force `
            -Downloader {
                param($Url, $Archive)
                throw "simulated download failure for $Url"
            }
        $result.ok | Should -BeFalse
        $result.outcome | Should -Be 'failed'
        $read = Read-MetraCursorWorkerRepairLedger -Path $ledgerPath -MetraRoot $script:MetraRoot
        $read.lastRepairOutcome | Should -Be 'failed'
        # Ensure must not call repair - status/ensure stay operator-gated; only assert ledger persistence here.
    }

    It 'bridge status returns JSON (default config is Disabled)' {
        $bridge = Join-Path $script:MetraRoot 'scripts\bootstrap\Invoke-MetraCursorWorkerBridge.ps1'
        # Default / missing machine-local config is enabled=false - do not rewrite operator config here.
        $json = & pwsh -NoProfile -File $bridge -Action status -MetraRoot $script:MetraRoot -SkipDebug 2>$null
        $line = @($json) | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1
        $obj = $line | ConvertFrom-Json
        $obj.ok | Should -BeTrue
        $obj.state | Should -BeIn @('Disabled', 'MissingCli', 'Unauthenticated', 'RepairRequired', 'Running', 'Error')
    }
}
