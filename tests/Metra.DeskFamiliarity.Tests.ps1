# Desk familiarity numeric dial - retired 2026-11-12.
# Behavioral coverage moved to Metra.OperatorWorkingNotes.Tests.ps1.

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Desk familiarity ledger (retired)' {
    It 'CLI dispatcher refuses with retired guidance' {
        InModuleScope Metra {
            { Invoke-MetraDeskFamiliarityCommand -Subcommand show } | Should -Throw -ExpectedMessage '*working-notes*'
            { Invoke-MetraDeskFamiliarityCommand -Subcommand analyze-nudge -ArgsRest @('-SessionPeak', 'Familiar', '-SessionFloor', 'Warming', '-Direction', 'Up') } |
                Should -Throw -ExpectedMessage '*retired*'
        }
    }
}
