# Metra Desk Mode + Ask HQ CLI (Mode A/B/C)

BeforeAll {
    $module = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Metra.psd1'
    Import-Module $module -Force

    function script:New-MetraDeskModeFixtureRoot {
        param(
            [ValidateSet('Hq', 'Satellite', 'Standalone', 'Unset')]
            [string]$MachineRole = 'Unset'
        )

        $tmp = Join-Path $env:TEMP ('metra-desk-mode-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $tmp 'docs') -Force
        if ($MachineRole -ne 'Unset') {
            $null = Set-MetraDeskPreferences -MachineRole $MachineRole -MetraRoot $tmp
        }
        return $tmp
    }
}

Describe 'Metra Desk Mode' {
    BeforeEach {
        $script:deskEnvOps = $env:METRA_OPS_BASE_URL
        $script:deskEnvForce = $env:METRA_OPS_FORCE_LOCAL
        Remove-Item Env:\METRA_OPS_BASE_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\METRA_OPS_FORCE_LOCAL -ErrorAction SilentlyContinue
        $script:deskFixture = $null
    }

    AfterEach {
        if ($null -ne $script:deskEnvOps) { $env:METRA_OPS_BASE_URL = $script:deskEnvOps }
        else { Remove-Item Env:\METRA_OPS_BASE_URL -ErrorAction SilentlyContinue }
        if ($null -ne $script:deskEnvForce) { $env:METRA_OPS_FORCE_LOCAL = $script:deskEnvForce }
        else { Remove-Item Env:\METRA_OPS_FORCE_LOCAL -ErrorAction SilentlyContinue }
        if ($script:deskFixture -and (Test-Path -LiteralPath $script:deskFixture)) {
            Remove-Item -LiteralPath $script:deskFixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-MetraDeskMode is Standalone when no OpsBaseUrl' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot
        Get-MetraDeskMode -MetraRoot $script:deskFixture | Should -Be 'Standalone'
    }

    It 'Get-MetraDeskMode is HqClient for remote OpsBaseUrl (non-Hq role)' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Satellite
        Get-MetraDeskMode -OpsBaseUrl 'https://remote-hq.example.ts.net' -MetraRoot $script:deskFixture |
            Should -Be 'HqClient'
    }

    It 'Get-MetraDeskMode is Standalone for loopback OpsBaseUrl' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Satellite
        Test-MetraOpsBaseUrlIsLocal -OpsBaseUrl 'http://127.0.0.1:7380' | Should -BeTrue
        Get-MetraDeskMode -OpsBaseUrl 'http://localhost:7380' -MetraRoot $script:deskFixture |
            Should -Be 'Standalone'
    }

    It 'Get-MetraDeskMode -ForceLocal returns ForceLocal even with remote URL' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Satellite
        Get-MetraDeskMode -ForceLocal -OpsBaseUrl 'https://remote-hq.example.ts.net' -MetraRoot $script:deskFixture |
            Should -Be 'ForceLocal'
    }

    It 'Assert-MetraOpsMayStartLocally refuses Mode B with divergence guidance' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Satellite
        $err = $null
        try {
            Assert-MetraOpsMayStartLocally -OpsBaseUrl 'https://metra.example.ts.net' -MetraRoot $script:deskFixture
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
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Satellite
        {
            Assert-MetraOpsMayStartLocally -ForceLocal -OpsBaseUrl 'https://metra.example.ts.net' -MetraRoot $script:deskFixture
        } | Should -Not -Throw
    }

    It 'Assert-MetraOpsMayStartLocally allows Standalone' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot
        { Assert-MetraOpsMayStartLocally -MetraRoot $script:deskFixture } | Should -Not -Throw
    }
}

Describe 'Metra Desk Mode HQ machineRole short-circuit' {
    BeforeEach {
        $script:deskEnvOps = $env:METRA_OPS_BASE_URL
        $script:deskEnvForce = $env:METRA_OPS_FORCE_LOCAL
        Remove-Item Env:\METRA_OPS_BASE_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\METRA_OPS_FORCE_LOCAL -ErrorAction SilentlyContinue
        $script:deskFixture = $null
    }

    AfterEach {
        if ($null -ne $script:deskEnvOps) { $env:METRA_OPS_BASE_URL = $script:deskEnvOps }
        else { Remove-Item Env:\METRA_OPS_BASE_URL -ErrorAction SilentlyContinue }
        if ($null -ne $script:deskEnvForce) { $env:METRA_OPS_FORCE_LOCAL = $script:deskEnvForce }
        else { Remove-Item Env:\METRA_OPS_FORCE_LOCAL -ErrorAction SilentlyContinue }
        if ($script:deskFixture -and (Test-Path -LiteralPath $script:deskFixture)) {
            Remove-Item -LiteralPath $script:deskFixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Hq + remote-looking Ops URL still Standalone (MagicDNS fail-stable)' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Hq
        Get-MetraDeskMode -OpsBaseUrl 'https://self-magic.example.ts.net' -MetraRoot $script:deskFixture |
            Should -Be 'Standalone'
    }

    It 'Hq + blank Ops URL is Standalone' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Hq
        Get-MetraDeskMode -MetraRoot $script:deskFixture | Should -Be 'Standalone'
    }

    It 'non-Hq + local URL stays Standalone' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Satellite
        Get-MetraDeskMode -OpsBaseUrl 'http://127.0.0.1:7380' -MetraRoot $script:deskFixture |
            Should -Be 'Standalone'
    }

    It 'non-Hq + remote URL is HqClient' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Satellite
        Get-MetraDeskMode -OpsBaseUrl 'https://remote-hq.example.ts.net' -MetraRoot $script:deskFixture |
            Should -Be 'HqClient'
    }

    It 'unknown machineRole uses URL-driven classification (remote -> HqClient)' {
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Unset
        Get-MetraDeskMode -OpsBaseUrl 'https://remote-hq.example.ts.net' -MetraRoot $script:deskFixture |
            Should -Be 'HqClient'
    }
}

Describe 'Metra Ops child shell selection' {
    It 'Resolve-MetraOpsChildShellExe prefers pwsh when available' {
        $exe = Resolve-MetraOpsChildShellExe
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwsh -and -not [string]::IsNullOrWhiteSpace($pwsh.Source)) {
            $exe | Should -Be $pwsh.Source
        }
        else {
            $exe | Should -Be 'powershell.exe'
        }
    }
}

Describe 'Metra Ask HQ journal CLI' {
    BeforeEach {
        $script:deskEnvOps = $env:METRA_OPS_BASE_URL
        $script:deskEnvForce = $env:METRA_OPS_FORCE_LOCAL
        Remove-Item Env:\METRA_OPS_BASE_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\METRA_OPS_FORCE_LOCAL -ErrorAction SilentlyContinue
        # Satellite fixture so remote OpsBaseUrl classifies as HqClient (not live HQ Standalone).
        $script:deskFixture = New-MetraDeskModeFixtureRoot -MachineRole Satellite
    }

    AfterEach {
        if ($null -ne $script:deskEnvOps) { $env:METRA_OPS_BASE_URL = $script:deskEnvOps }
        else { Remove-Item Env:\METRA_OPS_BASE_URL -ErrorAction SilentlyContinue }
        if ($null -ne $script:deskEnvForce) { $env:METRA_OPS_FORCE_LOCAL = $script:deskEnvForce }
        else { Remove-Item Env:\METRA_OPS_FORCE_LOCAL -ErrorAction SilentlyContinue }
        if ($script:deskFixture -and (Test-Path -LiteralPath $script:deskFixture)) {
            Remove-Item -LiteralPath $script:deskFixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'remote sessions unwraps .sessions' {
        Mock -CommandName Invoke-RestMethod -ModuleName Metra -MockWith {
            [PSCustomObject]@{
                sessions = @([PSCustomObject]@{ sessionId = 's1'; turnCount = 2 })
                turns    = @()
            }
        }
        $rows = @(Invoke-MetraAskLogCommand -Subcommand sessions -OpsBaseUrl 'https://remote-hq.example.ts.net' -MetraRoot $script:deskFixture)
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
        $got = Invoke-MetraAskLogCommand -Subcommand get -ArgsRest @('abc') -OpsBaseUrl 'https://remote-hq.example.ts.net' -MetraRoot $script:deskFixture
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
        $hits = @(Invoke-MetraAskLogCommand -Subcommand recall -ArgsRest @('deployment') -OpsBaseUrl 'https://remote-hq.example.ts.net' -MetraRoot $script:deskFixture)
        $hits.Count | Should -Be 1
        $hits[0].sessionId | Should -Be 's2'
    }

    It 'unreachable HQ fails closed with guidance (no silent local)' {
        Mock -CommandName Invoke-RestMethod -ModuleName Metra -MockWith {
            throw 'Unable to connect to the remote server'
        }
        $err = $null
        try {
            $null = Invoke-MetraAskLogCommand -Subcommand sessions -OpsBaseUrl 'https://remote-hq.example.ts.net' -MetraRoot $script:deskFixture
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
        $rows = @(Invoke-MetraAskLogCommand -Subcommand sessions -OpsBaseUrl 'https://remote-hq.example.ts.net' -Local -MetraRoot $script:deskFixture)
        $rows.Count | Should -Be 1
        $rows[0].sessionId | Should -Be 'local-only'
        Should -Invoke Invoke-RestMethod -ModuleName Metra -Times 0 -Exactly
    }
}
