# Requires Pester 5+.
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.HostCadence.Tests.ps1"

BeforeAll {
    $script:MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Metra Host Cadence' {
    BeforeEach {
        $script:CadencePath = Join-Path ([IO.Path]::GetTempPath()) ('host-cadence-' + [guid]::NewGuid().ToString('n') + '.json')
    }
    AfterEach {
        Remove-Item -LiteralPath $script:CadencePath -Force -ErrorAction SilentlyContinue
    }

    It 'initializes disabled state by default' {
        $st = Initialize-MetraHostCadenceState -Path $script:CadencePath
        $st.enabled | Should -BeFalse
        Test-Path -LiteralPath $script:CadencePath | Should -BeTrue
        $status = Get-MetraHostCadenceStatus -Path $script:CadencePath
        $status.armedIdle | Should -BeTrue
        $status.owner | Should -Be 'legacy-or-absent'
    }

    It 'requires -Confirm to enable and refuses legacy install when owned' {
        { Enable-MetraHostCadence -Path $script:CadencePath } | Should -Throw
        $st = Enable-MetraHostCadence -Path $script:CadencePath -Confirm
        $st.enabled | Should -BeTrue
        $st.owner | Should -Be 'MetraHost'
        { Assert-MetraHostCadenceAllowsLegacyInstall -Path $script:CadencePath } | Should -Throw
        $null = Disable-MetraHostCadence -Path $script:CadencePath
        { Assert-MetraHostCadenceAllowsLegacyInstall -Path $script:CadencePath } | Should -Not -Throw
    }

    It 'applies Pulse early skew of 60 seconds' {
        $state = Initialize-MetraHostCadenceState -Path $script:CadencePath
        $due = [datetime]::UtcNow.AddSeconds(90)
        $state.nextPulseDueUtc = $due.ToString('o')
        Save-MetraHostCadenceState -State $state -Path $script:CadencePath
        $state = Read-MetraHostCadenceState -Path $script:CadencePath
        Test-MetraHostCadencePulseDue -State $state -UtcNow ([datetime]::UtcNow) | Should -BeFalse
        $state.nextPulseDueUtc = ([datetime]::UtcNow.AddSeconds(30)).ToString('o')
        Test-MetraHostCadencePulseDue -State $state -UtcNow ([datetime]::UtcNow) | Should -BeTrue
    }

    It 'treats Daily as due on or after local wall time when not completed today' {
        $state = Initialize-MetraHostCadenceState -Path $script:CadencePath
        $state.dailyAtLocal = '00:00'
        $state.lastDailyLocalDate = $null
        $state.lastDailyCompletedUtc = $null
        Test-MetraHostCadenceDailyDue -State $state | Should -BeTrue
        $parts = Get-MetraHostCadenceLocalDailyParts -DailyAtLocal '00:00'
        $state.lastDailyLocalDate = $parts.LocalDateKey
        $state.lastDailyCompletedUtc = ([datetime]::UtcNow).ToString('o')
        Test-MetraHostCadenceDailyDue -State $state | Should -BeFalse
    }

    It 'honors injected UtcNow for Daily due evaluation' {
        $state = Initialize-MetraHostCadenceState -Path $script:CadencePath
        $state.dailyAtLocal = '12:00'
        $state.lastDailyLocalDate = $null
        $state.lastDailyCompletedUtc = $null
        $before = [datetime]::SpecifyKind([datetime]::Parse('2026-10-08T11:00:00'), [DateTimeKind]::Local).ToUniversalTime()
        $after = [datetime]::SpecifyKind([datetime]::Parse('2026-10-08T12:30:00'), [DateTimeKind]::Local).ToUniversalTime()
        Test-MetraHostCadenceDailyDue -State $state -UtcNow $before | Should -BeFalse
        Test-MetraHostCadenceDailyDue -State $state -UtcNow $after | Should -BeTrue
        $parts = Get-MetraHostCadenceLocalDailyParts -DailyAtLocal '12:00' -Now $after
        $state.lastDailyLocalDate = $parts.LocalDateKey
        $state.lastDailyCompletedUtc = $after.ToString('o')
        Test-MetraHostCadenceDailyDue -State $state -UtcNow $after | Should -BeFalse
    }

    It 'resolves cadence state path under sandbox MetraRoot' {
        $sandbox = Join-Path ([IO.Path]::GetTempPath()) ('hc-root-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
        try {
            $path = Get-MetraHostCadenceStatePath -MetraRoot $sandbox
            $path | Should -Be (Join-Path $sandbox 'host-cadence.json')
            $st = Get-MetraHostCadenceStatus -MetraRoot $sandbox
            $st.statePath | Should -Be $path
            Test-Path -LiteralPath $path | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps in-flight activeRunKind within lease; clears only when expired' {
        $state = Initialize-MetraHostCadenceState -Path $script:CadencePath
        $state.activeRunKind = 'Pulse'
        $state.lastPulseStartedUtc = ([datetime]::UtcNow.AddMinutes(-5)).ToString('o')
        $state.lastPulseCompletedUtc = $null
        Save-MetraHostCadenceState -State $state -Path $script:CadencePath
        $alive = Repair-MetraHostCadenceInterruptedRun -State (Read-MetraHostCadenceState -Path $script:CadencePath) -Path $script:CadencePath
        $alive.activeRunKind | Should -Be 'Pulse'

        $state = Read-MetraHostCadenceState -Path $script:CadencePath
        $state.lastPulseStartedUtc = ([datetime]::UtcNow.AddHours(-3)).ToString('o')
        Save-MetraHostCadenceState -State $state -Path $script:CadencePath
        $repaired = Repair-MetraHostCadenceInterruptedRun -State (Read-MetraHostCadenceState -Path $script:CadencePath) -Path $script:CadencePath
        $repaired.activeRunKind | Should -BeNullOrEmpty
        [string]$repaired.lastPulseCompletedUtc | Should -BeNullOrEmpty
    }

    It 'coalesces Daily over Pulse and completes with exit codes as health' {
        $null = Enable-MetraHostCadence -Path $script:CadencePath -Confirm -DailyAtLocal '00:00'
        $state = Read-MetraHostCadenceState -Path $script:CadencePath
        $state.nextPulseDueUtc = ([datetime]::UtcNow.AddHours(-1)).ToString('o')
        $state.pendingPulse = $true
        $state.pendingDaily = $true
        Save-MetraHostCadenceState -State $state -Path $script:CadencePath

        Mock -CommandName Invoke-MetraHostCadenceScheduleMode -MockWith {
            param($Mode, $MetraRoot)
            return [pscustomobject]@{ exitCode = 0; outcome = 'completed'; mode = $Mode }
        } -ModuleName Metra

        $tick = Invoke-MetraHostCadenceTick -MetraRoot $script:MetraRoot -Path $script:CadencePath -Execute
        $tick.executed | Should -BeTrue
        $tick.mode | Should -Be 'Daily'
        $tick.exitCode | Should -Be 0
        # Follow-up Pulse after Daily when Pulse was also pending
        $tick.followMode | Should -Be 'Pulse'
        $tick.followExitCode | Should -Be 0
        $after = Read-MetraHostCadenceState -Path $script:CadencePath
        $after.activeRunKind | Should -BeNullOrEmpty
        $after.pendingDaily | Should -BeFalse
        $after.pendingPulse | Should -BeFalse
    }

    It 'does not execute when disabled' {
        $null = Initialize-MetraHostCadenceState -Path $script:CadencePath
        $tick = Invoke-MetraHostCadenceTick -MetraRoot $script:MetraRoot -Path $script:CadencePath -Execute
        $tick.executed | Should -BeFalse
        $tick.reason | Should -Be 'disabled'
    }

    It 'records failed Daily as completed for the local date (no same-day retry)' {
        $null = Enable-MetraHostCadence -Path $script:CadencePath -Confirm -DailyAtLocal '00:00'
        $state = Read-MetraHostCadenceState -Path $script:CadencePath
        $state.nextPulseDueUtc = ([datetime]::UtcNow.AddDays(1)).ToString('o')
        Save-MetraHostCadenceState -State $state -Path $script:CadencePath

        Mock -CommandName Invoke-MetraHostCadenceScheduleMode -MockWith {
            return [pscustomobject]@{ exitCode = 1; outcome = 'failed'; mode = 'Daily' }
        } -ModuleName Metra

        $tick = Invoke-MetraHostCadenceTick -MetraRoot $script:MetraRoot -Path $script:CadencePath -Execute
        $tick.mode | Should -Be 'Daily'
        $tick.exitCode | Should -Be 1
        $after = Read-MetraHostCadenceState -Path $script:CadencePath
        Test-MetraHostCadenceDailyDue -State $after | Should -BeFalse
    }
}
