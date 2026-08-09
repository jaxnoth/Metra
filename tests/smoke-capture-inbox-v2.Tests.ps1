#Requires -Version 7
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Metra.psm1') -Force

Describe 'Capture Inbox v2 smoke' {
    It 'mixed Metra + BibleQuiz propose/affirm/promote gates' {
        InModuleScope Metra {
            $meta = Join-Path ([IO.Path]::GetTempPath()) ('metra-2b-smoke-' + [guid]::NewGuid().ToString('n'))
            $bq = Join-Path ([IO.Path]::GetTempPath()) ('metra-2b-smoke-bq-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $meta 'docs') -Force | Out-Null
            New-Item -ItemType Directory -Path $bq -Force | Out-Null
            $script:SmokeMeta = $meta
            $script:SmokeBq = $bq
            try {
                Mock Get-MetraHomeDestinationName { 'Metra' }
                Mock Get-MetraProjects {
                    @(
                        [PSCustomObject]@{ Name = 'Metra'; Path = $script:SmokeMeta; Root = 'work' }
                        [PSCustomObject]@{ Name = 'BibleQuiz'; Path = $script:SmokeBq; Root = 'personal' }
                    )
                }
                Mock Get-MetraScoredRoutingProjects {
                    param($Query)
                    if ("$Query" -match 'BibleQuiz|quiz|handoff') {
                        @([PSCustomObject]@{ Name = 'BibleQuiz'; Score = 5; Path = $script:SmokeBq; Root = 'personal' })
                    }
                    else { @() }
                }
                Mock Get-MetraProjectRegistry {
                    [PSCustomObject]@{
                        projects = @()
                        routing  = [PSCustomObject]@{ homeDestination = 'Metra' }
                    }
                }

                $sess = 'smoke-2b'
                $null = Add-MetraDeskAskEntry -Prompt 'Park a Metra future development scar for Capture Inbox v2' -Message 'ok' `
                    -Handoff ([PSCustomObject]@{ where = 'Metra' }) -SessionId $sess -Origin loopback -Client cli -Answered $true -MetraRoot $script:SmokeMeta
                $t2 = Add-MetraDeskAskEntry -Prompt 'Add BibleQuiz quiz handoff to project backlog' -Message 'ok' `
                    -Handoff ([PSCustomObject]@{ where = 'BibleQuiz' }) -SessionId $sess -Origin loopback -Client cli -Answered $true -MetraRoot $script:SmokeMeta

                $props = @(Propose-MetraCaptureSplit -TurnId $t2.id -SessionId $sess -MetraRoot $script:SmokeMeta)
                $props.Count | Should -BeGreaterOrEqual 2
                foreach ($p in $props) {
                    $p | Add-Member -NotePropertyName accepted -NotePropertyValue $true -Force
                }
                $created = @(Add-MetraCaptureFromAskSplit -Proposals $props -MetraRoot $script:SmokeMeta)
                $created.Count | Should -BeGreaterOrEqual 2

                $fd = $created | Where-Object { $_.suggestedHome -eq 'FutureDevelopment' } | Select-Object -First 1
                $pb = $created | Where-Object { $_.suggestedHome -eq 'ProjectBacklog' -or $_.suggestedProject -eq 'BibleQuiz' } | Select-Object -First 1
                if (-not $fd) { $fd = $created | Where-Object { $_.id -ne $pb.id } | Select-Object -First 1 }
                $pb | Should -Not -BeNullOrEmpty

                $null = Invoke-MetraCapturePromote -Id $fd.id -Home FutureDevelopment -HasLocalAuthority:$true -MetraRoot $script:SmokeMeta
                { Invoke-MetraCapturePromote -Id $pb.id -Home ProjectBacklog -Project BibleQuiz -HasLocalAuthority:$true -MetraRoot $script:SmokeMeta } |
                    Should -Throw -ExpectedMessage '*Cross-root*'
                $null = Invoke-MetraCapturePromote -Id $pb.id -Home ProjectBacklog -Project BibleQuiz -CrossRootConfirm -HasLocalAuthority:$true -MetraRoot $script:SmokeMeta
                Test-Path -LiteralPath (Join-Path $script:SmokeBq 'TODO.md') | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $meta -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $bq -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
