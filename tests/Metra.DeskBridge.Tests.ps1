# Metra desk bridge tests (hostname fallback, CLI entry)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\scripts\Metra.psd1') -Force
}

Describe 'Metra desk bridge hostname' {
    It 'Get-MetraDeskBridgeLocalHostName falls back HOSTNAME then MachineName' {
        InModuleScope Metra {
            Mock Get-ChildItem { return @() } -ParameterFilter { $LiteralPath -like '*desk-bridge*' }
            $savedComputer = $env:COMPUTERNAME
            $savedHost = $env:HOSTNAME
            try {
                $env:COMPUTERNAME = ''
                $env:HOSTNAME = 'MacBook-Pro.local'
                Get-MetraDeskBridgeLocalHostName | Should -Be 'macbook-pro.local'
                $env:HOSTNAME = ''
                $name = Get-MetraDeskBridgeLocalHostName
                $name | Should -Not -Be 'local'
                $name | Should -Be ([Environment]::MachineName.ToLowerInvariant())
            }
            finally {
                $env:COMPUTERNAME = $savedComputer
                $env:HOSTNAME = $savedHost
            }
        }
    }
}

Describe 'Invoke-MetraDeskBridgeCommand help' {
    It 'returns usage without throwing' {
        InModuleScope Metra {
            $r = Invoke-MetraDeskBridgeCommand -Subcommand help
            $r.Usage | Should -Match 'desk send'
        }
    }
}
