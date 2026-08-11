# Metra Desk Mode + Ask HQ CLI (Mode A/B/C)

Describe 'Metra Desk Mode' {
    BeforeAll {
        $module = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Metra.psd1'
        Import-Module $module -Force
    }

    It 'Get-MetraDeskMode is Standalone when no OpsBaseUrl' {
        $saved = $env:METRA_OPS_BASE_URL
        $envForce = $env:METRA_OPS_FORCE_LOCAL
        try {
            Remove-Item Env:\METRA_OPS_BASE_URL -ErrorAction SilentlyContinue
            Remove-Item Env:\METRA_OPS_FORCE_LOCAL -ErrorAction SilentlyContinue
            # Explicit empty OpsBaseUrl still falls through; pass a blank via soft resolve by using a temp root with no state.
            $tmp = Join-Path $env:TEMP ('metra-desk-mode-' + [guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path (Join-Path $tmp 'docs') -Force
            Get-MetraDeskMode -MetraRoot $tmp | Should -Be 'Standalone'
        }
        finally {
            if ($null -ne $saved) { $env:METRA_OPS_BASE_URL = $saved } else { Remove-Item Env:\METRA_OPS_BASE_URL -ErrorAction SilentlyContinue }
            if ($null -ne $envForce) { $env:METRA_OPS_FORCE_LOCAL = $envForce } else { Remove-Item Env:\METRA_OPS_FORCE_LOCAL -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'Get-MetraDeskMode is HqClient for remote OpsBaseUrl' {
        Get-MetraDeskMode -OpsBaseUrl 'https://remote-hq.example.ts.net' | Should -Be 'HqClient'
    }

    It 'Get-MetraDeskMode is Standalone for loopback OpsBaseUrl' {
        Test-MetraOpsBaseUrlIsLocal -OpsBaseUrl 'http://127.0.0.1:7380' | Should -BeTrue
        Get-MetraDeskMode -OpsBaseUrl 'http://localhost:7380' | Should -Be 'Standalone'
    }

    It 'Get-MetraDeskMode -ForceLocal returns ForceLocal even with remote URL' {
        Get-MetraDeskMode -ForceLocal -OpsBaseUrl 'https://remote-hq.example.ts.net' | Should -Be 'ForceLocal'
    }

    It 'Assert-MetraOpsMayStartLocally refuses Mode B with divergence guidance' {
        $err = $null
        try {
            Assert-MetraOpsMayStartLocally -OpsBaseUrl 'https://metra.example.ts.net'
        }
        catch {
            $err = [string]$_.Exception.Message
        }
        $err | Should -Not -BeNullOrEmpty
        $err | Should -Match 'remote Ask host'
        $err | Should -Match 'https://metra.example.ts.net'
        $err | Should -Match 'journal divergence'
        $err | Should -Match '-ForceLocal'
    }

    It 'Assert-MetraOpsMayStartLocally allows ForceLocal' {
        { Assert-MetraOpsMayStartLocally -ForceLocal -OpsBaseUrl 'https://metra.example.ts.net' } | Should -Not -Throw
    }

    It 'Assert-MetraOpsMayStartLocally allows Standalone' {
        $tmp = Join-Path $env:TEMP ('metra-desk-allow-' + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path (Join-Path $tmp 'docs') -Force
            { Assert-MetraOpsMayStartLocally -MetraRoot $tmp } | Should -Not -Throw
        }
        finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Metra Ask HQ journal CLI' {
    BeforeAll {
        $module = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Metra.psd1'
        Import-Module $module -Force
    }

    It 'remote sessions unwraps .sessions' {
        Mock -CommandName Invoke-RestMethod -ModuleName Metra -MockWith {
            [PSCustomObject]@{
                sessions = @([PSCustomObject]@{ sessionId = 's1'; turnCount = 2 })
                turns    = @()
            }
        }
        $rows = @(Invoke-MetraAskLogCommand -Subcommand sessions -OpsBaseUrl 'https://remote-hq.example.ts.net')
        $rows.Count | Should -Be 1
        $rows[0].sessionId | Should -Be 's1'
    }

    It 'remote get preserves continuity' {
        Mock -CommandName Invoke-RestMethod -ModuleName Metra -MockWith {
            [PSCustomObject]@{
                sessionId  = 'abc'
                turnCount  = 1
                continuity = [PSCustomObject]@{ summary = 'prior work' }
                turns      = @([PSCustomObject]@{ id = 't1' })
            }
        }
        $got = Invoke-MetraAskLogCommand -Subcommand get -ArgsRest @('abc') -OpsBaseUrl 'https://remote-hq.example.ts.net'
        $got.sessionId | Should -Be 'abc'
        $got.continuity.summary | Should -Be 'prior work'
        @($got.turns).Count | Should -Be 1
    }

    It 'remote recall unwraps .hits' {
        Mock -CommandName Invoke-RestMethod -ModuleName Metra -MockWith {
            [PSCustomObject]@{
                query = 'deployment'
                hits  = @([PSCustomObject]@{ sessionId = 's2'; prompt = 'deployment window' })
            }
        }
        $hits = @(Invoke-MetraAskLogCommand -Subcommand recall -ArgsRest @('deployment') -OpsBaseUrl 'https://remote-hq.example.ts.net')
        $hits.Count | Should -Be 1
        $hits[0].sessionId | Should -Be 's2'
    }

    It 'unreachable HQ fails closed with guidance (no silent local)' {
        Mock -CommandName Invoke-RestMethod -ModuleName Metra -MockWith {
            throw 'Unable to connect to the remote server'
        }
        $err = $null
        try {
            $null = Invoke-MetraAskLogCommand -Subcommand sessions -OpsBaseUrl 'https://remote-hq.example.ts.net'
        }
        catch {
            $err = [string]$_.Exception.Message
        }
        $err | Should -Match 'HQ Ask host unreachable'
        $err | Should -Match 'Tailscale'
        $err | Should -Match '-Local'
        $err | Should -Not -Match '(?i)silently'
    }

    It '-Local ignores remote OpsBaseUrl and reads local journal helpers' {
        Mock -CommandName Get-MetraDeskAskSessionSummaries -ModuleName Metra -MockWith {
            @([PSCustomObject]@{ sessionId = 'local-only'; turnCount = 1 })
        }
        Mock -CommandName Invoke-RestMethod -ModuleName Metra -MockWith {
            throw 'should not call remote when -Local'
        }
        $rows = @(Invoke-MetraAskLogCommand -Subcommand sessions -OpsBaseUrl 'https://remote-hq.example.ts.net' -Local)
        $rows.Count | Should -Be 1
        $rows[0].sessionId | Should -Be 'local-only'
        Should -Invoke Invoke-RestMethod -ModuleName Metra -Times 0 -Exactly
    }
}
