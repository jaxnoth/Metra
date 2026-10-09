# Pester: Ask routed telemetry rotation (5 MB, one .1 backup).
$ErrorActionPreference = 'Stop'
$module = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Metra.psd1'
Import-Module $module -Force

Describe 'Ask routed telemetry rotation' {
    It 'rotates at MaxBytes and keeps one .1 backup' {
        InModuleScope Metra {
            $dir = Join-Path $TestDrive 'ask-telem'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $path = Join-Path $dir 'events.jsonl'
            $big = ('x' * 2000)
            Set-Content -LiteralPath $path -Value $big -Encoding utf8 -NoNewline
            Sync-MetraAskRoutedTelemetryRotation -Path $path -MaxBytes 1000
            (Test-Path -LiteralPath $path) | Should -BeFalse
            (Test-Path -LiteralPath "$path.1") | Should -BeTrue
            # Second rotation replaces .1
            Set-Content -LiteralPath $path -Value ('y' * 2000) -Encoding utf8 -NoNewline
            Sync-MetraAskRoutedTelemetryRotation -Path $path -MaxBytes 1000
            (Get-Content -LiteralPath "$path.1" -Raw).Substring(0, 1) | Should -Be 'y'
        }
    }
}
