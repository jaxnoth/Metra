# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Narrative.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Narrative packs and state machine' {
    It 'lists tracked packs including derelict_station and pbi_gateway_ha_prep' {
        InModuleScope Metra {
            $packs = @(Get-MetraNarrativePacks -MetraRoot (Get-MetraRoot))
            ($packs | Where-Object { $_.PackId -eq 'derelict_station' }).Count | Should -Be 1
            ($packs | Where-Object { $_.PackId -eq 'pbi_gateway_ha_prep' }).Count | Should -Be 1
        }
    }

    It 'plays derelict_station to success with deterministic seed path' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-nar2-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $st = Start-MetraNarrativeSession -PackId 'derelict_station' -Seed 42
                $st.packId | Should -Be 'derelict_station'
                $st.lifecycle | Should -Be 'active'
                $st = Invoke-MetraNarrativeMove -MoveId 'enter_corridor' -SessionId $st.sessionId
                $st = Invoke-MetraNarrativeMove -MoveId 'search_lockers' -SessionId $st.sessionId
                $st = Invoke-MetraNarrativeMove -MoveId 'open_archive' -SessionId $st.sessionId
                $st = Invoke-MetraNarrativeMove -MoveId 'grab_archive_quiet' -SessionId $st.sessionId
                $st = Invoke-MetraNarrativeMove -MoveId 'escape_success' -SessionId $st.sessionId
                $st.terminal | Should -Be 'success'
                $st.state.archive_found | Should -BeTrue
                $events = @(Get-MetraNarrativeEvents -SessionId $st.sessionId)
                ($events | Where-Object { $_.type -eq 'move_accepted' }).Count | Should -Be 5
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects unavailable moves without mutating state' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-nar3-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $st = Start-MetraNarrativeSession -PackId 'derelict_station' -Seed 7
                $before = ($st.state | ConvertTo-Json -Compress)
                { Invoke-MetraNarrativeMove -MoveId 'escape_success' -SessionId $st.sessionId } | Should -Throw '*not available*'
                $afterDoc = Read-MetraNarrativeSessionState -SessionId $st.sessionId
                ($afterDoc.state | ConvertTo-Json -Compress) | Should -Be $before
                $rejected = @(Get-MetraNarrativeEvents -SessionId $st.sessionId | Where-Object { $_.type -eq 'move_rejected' })
                $rejected.Count | Should -Be 1
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'completes pbi_gateway_ha_prep lesson success path' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-nar4-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $st = Start-MetraNarrativeSession -PackId 'pbi_gateway_ha_prep' -Seed 9
                foreach ($m in @('check_nodes', 'validate_spn', 'confirm_backup', 'open_window', 'begin_update')) {
                    $st = Invoke-MetraNarrativeMove -MoveId $m -SessionId $st.sessionId
                }
                $st.terminal | Should -Be 'success'
                $st.mode | Should -Be 'lesson'
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'fails pbi_gateway_ha_prep unsafe shortcuts and blocks begin_update early' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-nar-fail-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $skip = Start-MetraNarrativeSession -PackId 'pbi_gateway_ha_prep' -Seed 11
                $skip = Invoke-MetraNarrativeMove -MoveId 'skip_node_check' -SessionId $skip.sessionId
                $skip.terminal | Should -Be 'fail'
                { Invoke-MetraNarrativeMove -MoveId 'begin_update' -SessionId $skip.sessionId } | Should -Throw

                $force = Start-MetraNarrativeSession -PackId 'pbi_gateway_ha_prep' -Seed 12
                $force = Invoke-MetraNarrativeMove -MoveId 'check_nodes' -SessionId $force.sessionId
                $force = Invoke-MetraNarrativeMove -MoveId 'validate_spn' -SessionId $force.sessionId
                $before = ($force.state | ConvertTo-Json -Compress)
                { Invoke-MetraNarrativeMove -MoveId 'begin_update' -SessionId $force.sessionId } | Should -Throw '*not available*'
                $after = Read-MetraNarrativeSessionState -SessionId $force.sessionId
                ($after.state | ConvertTo-Json -Compress) | Should -Be $before
                $force = Invoke-MetraNarrativeMove -MoveId 'force_update_early' -SessionId $force.sessionId
                $force.terminal | Should -Be 'fail'
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects pack fingerprint mismatch after pack edit' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-nar-fp-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            $packPath = Get-MetraNarrativePackPath -PackId 'derelict_station'
            $original = [System.IO.File]::ReadAllText($packPath, [System.Text.Encoding]::UTF8)
            try {
                $st = Start-MetraNarrativeSession -PackId 'derelict_station' -Seed 13
                $sessionFp = [string]$st.packFingerprint
                $doc = $original | ConvertFrom-Json -Depth 40
                $doc | Add-Member -NotePropertyName bingReviewMarker -NotePropertyValue 'changed' -Force
                [System.IO.File]::WriteAllText($packPath, (($doc | ConvertTo-Json -Depth 40) + "`r`n"), [System.Text.UTF8Encoding]::new($false))
                try {
                    Invoke-MetraNarrativeMove -MoveId 'enter_corridor' -SessionId $st.sessionId
                    throw 'expected fingerprint mismatch'
                }
                catch {
                    $_.Exception.Message | Should -Match 'fingerprint mismatch'
                    $_.Exception.Message | Should -Match ([regex]::Escape($sessionFp))
                    $_.Exception.Message | Should -Match 'current='
                }
            }
            finally {
                [System.IO.File]::WriteAllText($packPath, $original, [System.Text.UTF8Encoding]::new($false))
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'whitelists session ids as n plus 12 hex' {
        InModuleScope Metra {
            Test-MetraNarrativeSessionId -SessionId 'n0123456789ab' | Should -BeTrue
            Test-MetraNarrativeSessionId -SessionId '.' | Should -BeFalse
            Test-MetraNarrativeSessionId -SessionId '' | Should -BeFalse
            Test-MetraNarrativeSessionId -SessionId '..' | Should -BeFalse
            Test-MetraNarrativeSessionId -SessionId 'n0123456789abc' | Should -BeFalse
            { Get-MetraNarrativeSessionDir -SessionId '.' } | Should -Throw '*Invalid session id*'
        }
    }
}

Describe 'Narrative narrator and lifecycle' {
    It 'falls back when Ask is unavailable and never blocks' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-nar5-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $st = Start-MetraNarrativeSession -PackId 'derelict_station' -Seed 3
                Mock Invoke-MetraAskEngine { throw 'ask down' }
                $nar = Invoke-MetraNarrativeNarrate -SessionId $st.sessionId
                $nar.source | Should -Be 'fallback'
                $nar.text | Should -Match 'derelict_station'
                $st2 = Invoke-MetraNarrativeMove -MoveId 'enter_corridor' -SessionId $st.sessionId
                $st2.state.location | Should -Be 'station_corridor'
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'forgets session detail and keeps index summary' {
        InModuleScope Metra {
            $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("metra-nar6-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            $prev = $env:METRA_DATA_ROOT
            $env:METRA_DATA_ROOT = $sandbox
            try {
                $st = Start-MetraNarrativeSession -PackId 'derelict_station' -Seed 1
                $sid = $st.sessionId
                [void](Stop-MetraNarrativeSession -SessionId $sid -Summary 'escaped with archive')
                $forgotten = Invoke-MetraNarrativeForget -SessionId $sid
                $forgotten.lifecycle | Should -Be 'forgotten'
                $forgotten.notableOutcome | Should -Match 'escaped'
                Test-Path -LiteralPath (Get-MetraNarrativeSessionDir -SessionId $sid) | Should -BeFalse
                $listed = @(Get-MetraNarrativeSessions -Lifecycle forgotten)
                ($listed | Where-Object { $_.sessionId -eq $sid }).Count | Should -Be 1
            }
            finally {
                if ($null -eq $prev) { Remove-Item Env:METRA_DATA_ROOT -ErrorAction SilentlyContinue }
                else { $env:METRA_DATA_ROOT = $prev }
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'CLI dispatcher lists packs' {
        $packs = @(Invoke-MetraNarrativeCommand -Subcommand packs)
        ($packs | Where-Object { $_.PackId -eq 'derelict_station' }).Count | Should -BeGreaterThan 0
    }
}
