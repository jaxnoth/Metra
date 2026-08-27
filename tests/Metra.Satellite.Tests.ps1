# Metra satellite onboarding tests (profile merge, foreign roots)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\scripts\Metra.psd1') -Force
}

Describe 'Metra satellite profile merge' {
    It 'Test-MetraProfileRootPathMatchesHost detects Windows paths on Unix-style host check' {
        InModuleScope Metra {
            Mock Test-MetraHostIsWindows { return $false }
            Test-MetraProfileRootPathMatchesHost -Path 'C:\Projects' | Should -Be $false
            Test-MetraProfileRootPathMatchesHost -Path '/Users/dev/Developer' | Should -Be $true
            Test-MetraProfileRootPathMatchesHost -Path '..' | Should -Be $true
        }
    }

    It 'Merge-MetraProfileMachineLocalConfig preserves local roots when import is foreign' {
        InModuleScope Metra {
            $imported = [PSCustomObject]@{
                projectsRoot = 'C:\Projects'
                opsBaseUrl   = 'https://hq.example.ts.net'
                roots        = @(
                    [PSCustomObject]@{ name = 'work'; path = 'C:\Projects'; primary = $true }
                )
            }
            $local = [PSCustomObject]@{
                projectsRoot = '..'
                roots        = @(
                    [PSCustomObject]@{ name = 'work'; path = '..'; primary = $true; optional = $true }
                )
            }
            Mock Test-MetraHostIsWindows { return $false }
            $merge = Merge-MetraProfileMachineLocalConfig -Imported $imported -Local $local -Quiet
            $merge.Merged | Should -Be $true
            $merge.Config.projectsRoot | Should -Be '..'
            $merge.Config.opsBaseUrl | Should -Be 'https://hq.example.ts.net'
            @($merge.Config.roots).Count | Should -Be 1
            $merge.Config.roots[0].path | Should -Be '..'
        }
    }

    It 'Repair-MetraSatelliteLocalRoots applies template when config has foreign roots' {
        $temp = Join-Path $TestDrive 'satellite-repair'
        $null = New-Item -ItemType Directory -Path $temp -Force
        $templateSrc = Join-Path (Get-MetraRoot) 'profiles/satellite-mac'
        Copy-Item -LiteralPath $templateSrc -Destination (Join-Path $temp 'profiles/satellite-mac') -Recurse -Force
        $cfg = @{
            projectsRoot = 'C:\Projects'
            opsBaseUrl   = 'https://hq.example.ts.net'
            roots        = @(
                @{ name = 'work'; path = 'C:\Projects'; primary = $true }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -LiteralPath (Join-Path $temp 'metra.config.json') -Value $cfg -Encoding utf8

        InModuleScope Metra {
            param($TempRoot)
            Mock Test-MetraHostIsWindows { return $false }
            $result = Repair-MetraSatelliteLocalRoots -MetraRoot $TempRoot -Quiet
            $result.Changed | Should -Be $true
            $repaired = Get-Content -LiteralPath (Join-Path $TempRoot 'metra.config.json') -Raw | ConvertFrom-Json
            $repaired.projectsRoot | Should -Be '..'
            $repaired.opsBaseUrl | Should -Be 'https://hq.example.ts.net'
            Test-MetraProfileConfigRootsForeignToHost -Config $repaired | Should -Be $false
        } -ArgumentList $temp
    }
}

Describe 'Show-MetraSatelliteCli' {
    It 'connect -Preview does not require network' {
        InModuleScope Metra {
            $r = Show-MetraSatelliteCli -Subcommand 'connect' -OpsBaseUrl 'https://hq.example.ts.net' -Preview -Quiet
            $r.Preview | Should -Be $true
            $r.OpsBaseUrl | Should -Be 'https://hq.example.ts.net'
        }
    }
}

Describe 'Invoke-MetraSatelliteConnect ShouldProcess' {
    It 'returns Ok=false when operator cancels confirm' {
        InModuleScope Metra {
            Mock Test-MetraProfileOpsBaseUrlForm { return $true }
            Mock Get-MetraRoot { return (Join-Path $TestDrive 'sat-cancel') }
            $result = Invoke-MetraSatelliteConnect -OpsBaseUrl 'https://hq.example.ts.net' -WhatIf
            $result.Ok | Should -Be $false
            $result.Cancelled | Should -Be $true
            $result.Preview | Should -Be $false
        }
    }
}
