# Metra machine role / first-run setup tests

Describe 'Metra machine role setup' {
    BeforeAll {
        $script:MetraRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        Import-Module (Join-Path $script:MetraRepoRoot 'scripts\Metra.psd1') -Force
    }

    It 'ConvertTo-MetraMachineRole normalizes labels' {
        ConvertTo-MetraMachineRole -Role 'hq' | Should -Be 'Hq'
        ConvertTo-MetraMachineRole -Role 'Satellite' | Should -Be 'Satellite'
        ConvertTo-MetraMachineRole -Role 'STANDALONE' | Should -Be 'Standalone'
        ConvertTo-MetraMachineRole -Role 'nope' | Should -Be $null
    }

    It 'Satellite defaults skip Tailscale and write loopback prefs' {
        $temp = Join-Path $env:TEMP ("metra-role-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $temp 'docs') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:MetraRepoRoot 'metra.config.example.json') -Destination (Join-Path $temp 'metra.config.json')
        try {
            $result = Invoke-MetraMachineRoleSetup -MetraRoot $temp -Role Satellite -Quiet
            $result.MachineRole | Should -Be 'Satellite'
            $result.Advanced | Should -BeFalse
            $prefs = Get-MetraDeskPreferences -MetraRoot $temp
            $prefs.machineRole | Should -Be 'Satellite'
            $prefs.bindTailscale | Should -BeFalse
            $prefs.preferFriendlyUrl | Should -BeFalse
            $prefs.opsPort | Should -Be (Get-MetraOpsFallbackPort)
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Standalone -Role persists machineRole without Tailscale' {
        $temp = Join-Path $env:TEMP ("metra-role-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $temp 'docs') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:MetraRepoRoot 'metra.config.example.json') -Destination (Join-Path $temp 'metra.config.json')
        try {
            $result = Invoke-MetraMachineRoleSetup -MetraRoot $temp -Role Standalone -Quiet
            $result.MachineRole | Should -Be 'Standalone'
            $prefs = Get-MetraDeskPreferences -MetraRoot $temp
            $prefs.machineRole | Should -Be 'Standalone'
            $prefs.bindTailscale | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Set-MetraConfiguredOpsBaseUrl writes and clears opsBaseUrl' {
        $temp = Join-Path $env:TEMP ("metra-opsurl-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:MetraRepoRoot 'metra.config.example.json') -Destination (Join-Path $temp 'metra.config.json')
        try {
            $null = Set-MetraConfiguredOpsBaseUrl -OpsBaseUrl 'https://hq.example.ts.net' -MetraRoot $temp
            Get-MetraProfileOpsBaseUrlOrNull -MetraRoot $temp | Should -Be 'https://hq.example.ts.net'
            $null = Set-MetraConfiguredOpsBaseUrl -OpsBaseUrl '' -MetraRoot $temp
            Get-MetraProfileOpsBaseUrlOrNull -MetraRoot $temp | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-MetraDeskPreferences round-trips machineRole' {
        $temp = Join-Path $env:TEMP ("metra-prefs-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $temp 'docs') -Force | Out-Null
        try {
            $null = Set-MetraDeskPreferences -MetraRoot $temp -MachineRole Hq
            $prefs = Get-MetraDeskPreferences -MetraRoot $temp
            $prefs.machineRole | Should -Be 'Hq'
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
