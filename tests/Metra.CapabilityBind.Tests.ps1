# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.CapabilityBind.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Capability bind ledger' {
    It 'persists bind and clears on leave' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-cbind-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $askSid = 'asksessionalpha01'
                $null = Set-MetraCapabilityBind -SessionId $askSid -Capability 'narrative' `
                    -RuntimeSessionId 'n0123456789ab' -PackId 'derelict_station'
                $got = Get-MetraCapabilityBind -SessionId $askSid
                $got.capability | Should -Be 'narrative'
                $got.runtimeSessionId | Should -Be 'n0123456789ab'
                $got.packId | Should -Be 'derelict_station'
                $got.boundAt | Should -Not -BeNullOrEmpty
                $got.lastTouchedAt | Should -Not -BeNullOrEmpty
                Clear-MetraCapabilityBind -SessionId $askSid | Should -BeTrue
                Get-MetraCapabilityBind -SessionId $askSid | Should -BeNullOrEmpty
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects invalid session id' {
        InModuleScope Metra {
            { Set-MetraCapabilityBind -SessionId 'bad!' -Capability 'narrative' -RuntimeSessionId 'n0123456789ab' } |
                Should -Throw -Because 'session id must be alphanumeric'
        }
    }
    It 'maps legacy engineSessionId field on read' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-clegacy-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $askSid = 'asksessionalpha07'
                $path = Get-MetraCapabilityBindPath -SessionId $askSid
                $legacy = '{"capability":"narrative","engineSessionId":"n0legacy000001","packId":"derelict_station","boundAt":"2026-09-08T00:00:00Z","lastTouchedAt":"2026-09-08T00:00:00Z"}'
                [System.IO.File]::WriteAllText($path, $legacy, [System.Text.UTF8Encoding]::new($false))
                $got = Get-MetraCapabilityBind -SessionId $askSid
                $got.runtimeSessionId | Should -Be 'n0legacy000001'
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    It 'maps numbered choice to allowed move id' {
        InModuleScope Metra {
            $moves = @(
                [PSCustomObject]@{ id = 'enter_corridor'; label = 'Enter' },
                [PSCustomObject]@{ id = 'abandon_mission'; label = 'Flee' }
            )
            $mapped = Resolve-MetraNarrativeMoveIdFromPrompt -Prompt '2' -AllowedMoves $moves
            $mapped.kind | Should -Be 'move'
            $mapped.moveId | Should -Be 'abandon_mission'
        }
    }

    It 'fallback narrate stays pack-agnostic (no ship_hull)' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-cfall-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $st = Start-MetraNarrativeSession -PackId 'derelict_station' -Seed 3
                $text = New-MetraNarrativeFallbackText -Status $st
                $text | Should -Match 'Your choices:'
                $text | Should -Not -Match 'ship_hull'
                $text | Should -Not -Match 'Lifecycle:'
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Capability inertia and change-car confirm' {
    It 'mid-session check SQL replication requests confirmation and keeps bind' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-cinert-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $askSid = 'asksessionalpha02'
                $start = Invoke-MetraCapabilityDispatchTurn -Prompt 'play derelict station' -SessionId $askSid -FallbackNarrate
                $start.answerType | Should -Be 'narrative'
                $bind = Get-MetraCapabilityBind -SessionId $askSid
                $bind.capability | Should -Be 'narrative'
                $runtimeSid = [string]$bind.runtimeSessionId

                $cross = Invoke-MetraCapabilityDispatchTurn -Prompt 'check SQL replication' -SessionId $askSid -FallbackNarrate
                $cross.answerType | Should -Be 'leave_confirm'
                $cross.leaveConfirm.required | Should -BeTrue
                $cross.message | Should -Match 'Leave narrative'
                $still = Get-MetraCapabilityBind -SessionId $askSid
                $still | Should -Not -BeNullOrEmpty
                $still.runtimeSessionId | Should -Be $runtimeSid
                $still.pendingLeaveConfirm | Should -Not -BeNullOrEmpty

                # Narrative session untouched
                $st = Get-MetraNarrativeSessionStatus -SessionId $runtimeSid
                $st.lifecycle | Should -Be 'active'
                [string]$st.terminal | Should -BeNullOrEmpty
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'explicit end the adventure clears bind' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-cend-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $askSid = 'asksessionalpha03'
                [void](Invoke-MetraCapabilityDispatchTurn -Prompt 'play derelict station' -SessionId $askSid -FallbackNarrate)
                $end = Invoke-MetraCapabilityDispatchTurn -Prompt 'end the adventure' -SessionId $askSid -FallbackNarrate
                $end.answerType | Should -Be 'narrative_left'
                Get-MetraCapabilityBind -SessionId $askSid | Should -BeNullOrEmpty
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'operator affirm leave clears bind without inventing a route inside the car' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-caffirm-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $askSid = 'asksessionalpha04'
                [void](Invoke-MetraCapabilityDispatchTurn -Prompt 'play derelict station' -SessionId $askSid -FallbackNarrate)
                [void](Invoke-MetraCapabilityDispatchTurn -Prompt 'check SQL replication' -SessionId $askSid -FallbackNarrate)
                $affirm = Invoke-MetraCapabilityDispatchTurn -Prompt 'yes leave' -SessionId $askSid -FallbackNarrate
                [bool]$affirm.__capabilityLeaveAffirmed | Should -BeTrue
                Get-MetraCapabilityBind -SessionId $askSid | Should -BeNullOrEmpty
                [string]$affirm.priorPrompt | Should -Match 'SQL'
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'maps allowed move by id and stays bound' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-cmove-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $askSid = 'asksessionalpha05'
                [void](Invoke-MetraCapabilityDispatchTurn -Prompt 'play derelict station' -SessionId $askSid -FallbackNarrate)
                $moved = Invoke-MetraCapabilityDispatchTurn -Prompt 'enter_corridor' -SessionId $askSid -FallbackNarrate
                $moved.message | Should -Match 'Your choices:'
                $moved.message | Should -Match 'search_lockers'
                $bind = Get-MetraCapabilityBind -SessionId $askSid
                $bind | Should -Not -BeNullOrEmpty
                $st = Get-MetraNarrativeSessionStatus -SessionId ([string]$bind.runtimeSessionId)
                @($st.allowedMoves | ForEach-Object { $_.id }) | Should -Contain 'search_lockers'
                $st.lastText | Should -Match 'corridor'
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'terminal session clears bind without extra confirm' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-cterm-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $askSid = 'asksessionalpha06'
                [void](Invoke-MetraCapabilityDispatchTurn -Prompt 'play derelict station' -SessionId $askSid -FallbackNarrate)
                $bind = Get-MetraCapabilityBind -SessionId $askSid
                $sid = [string]$bind.runtimeSessionId
                foreach ($m in @('enter_corridor', 'search_lockers', 'open_archive', 'grab_archive_quiet', 'escape_success')) {
                    [void](Invoke-MetraNarrativeMove -MoveId $m -SessionId $sid)
                }
                $after = Invoke-MetraCapabilityDispatchTurn -Prompt 'status' -SessionId $askSid -FallbackNarrate
                $after.answerType | Should -Be 'narrative_terminal'
                Get-MetraCapabilityBind -SessionId $askSid | Should -BeNullOrEmpty
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

