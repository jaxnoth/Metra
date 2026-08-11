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

    It 'Satellite -Quiet -OpsBaseUrl writes without prompt' {
        $temp = Join-Path $env:TEMP ("metra-role-url-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $temp 'docs') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:MetraRepoRoot 'metra.config.example.json') -Destination (Join-Path $temp 'metra.config.json')
        try {
            $result = Invoke-MetraMachineRoleSetup -MetraRoot $temp -Role Satellite `
                -OpsBaseUrl 'https://hq.example.ts.net/' -Quiet
            $result.MachineRole | Should -Be 'Satellite'
            $result.OpsBaseUrl | Should -Be 'https://hq.example.ts.net'
            Get-MetraProfileOpsBaseUrlOrNull -MetraRoot $temp | Should -Be 'https://hq.example.ts.net'
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Standalone -Quiet -NoPreferFriendly forces loopback prefs' {
        $temp = Join-Path $env:TEMP ("metra-role-loop-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $temp 'docs') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:MetraRepoRoot 'metra.config.example.json') -Destination (Join-Path $temp 'metra.config.json')
        try {
            $result = Invoke-MetraMachineRoleSetup -MetraRoot $temp -Role Standalone -NoPreferFriendly -Quiet
            $result.MachineRole | Should -Be 'Standalone'
            $prefs = Get-MetraDeskPreferences -MetraRoot $temp
            $prefs.preferFriendlyUrl | Should -BeFalse
            $prefs.bindTailscale | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Hq -Quiet -BindTailscale sets bindTailscale preference' {
        $temp = Join-Path $env:TEMP ("metra-role-ts-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $temp 'docs') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:MetraRepoRoot 'metra.config.example.json') -Destination (Join-Path $temp 'metra.config.json')
        Mock -CommandName Get-MetraOpsTailscaleIPv4 -ModuleName Metra -MockWith { '100.64.0.1' }
        Mock -CommandName Initialize-MetraOpsDeskBinding -ModuleName Metra -MockWith {
            param($MetraRoot, $PreferFriendly, $BindTailscale, $Interactive, $Preview, $Quiet)
            if ($BindTailscale) {
                $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot -BindTailscale $true -MachineRole Hq
            }
            return [PSCustomObject]@{ Changed = $true; Binding = $null }
        }
        try {
            $result = Invoke-MetraMachineRoleSetup -MetraRoot $temp -Role Hq -NoPreferFriendly -BindTailscale -Quiet
            $result.MachineRole | Should -Be 'Hq'
            $prefs = Get-MetraDeskPreferences -MetraRoot $temp
            $prefs.bindTailscale | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Satellite -Advanced still skips local Ops host prompts' {
        $temp = Join-Path $env:TEMP ("metra-role-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $temp 'docs') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:MetraRepoRoot 'metra.config.example.json') -Destination (Join-Path $temp 'metra.config.json')
        try {
            $result = Invoke-MetraMachineRoleSetup -MetraRoot $temp -Role Satellite -Advanced -Quiet
            $result.MachineRole | Should -Be 'Satellite'
            $prefs = Get-MetraDeskPreferences -MetraRoot $temp
            $prefs.bindTailscale | Should -BeFalse
            $prefs.preferFriendlyUrl | Should -BeFalse
            $prefs.browserHost | Should -Be '127.0.0.1'
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
