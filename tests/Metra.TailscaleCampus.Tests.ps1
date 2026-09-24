# Metra Tailscale campus hosts (optional DNS-filter pin)

Describe 'Metra Tailscale campus hosts' {
    BeforeAll {
        $module = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Metra.psd1'
        Import-Module $module -Force
    }

    It 'Test-MetraFqdnHostName accepts Tailscale FQDNs and rejects junk' {
        InModuleScope Metra {
            Test-MetraFqdnHostName -Name 'login.tailscale.com' | Should -BeTrue
            Test-MetraFqdnHostName -Name 'controlplane.tailscale.com' | Should -BeTrue
            Test-MetraFqdnHostName -Name 'metra' | Should -BeFalse
            Test-MetraFqdnHostName -Name '-bad.example.com' | Should -BeFalse
            Test-MetraFqdnHostName -Name '' | Should -BeFalse
        }
    }

    It 'Test-MetraIPv4InCidr matches Tailscale coordination anycast' {
        InModuleScope Metra {
            Test-MetraIPv4InCidr -Address '192.200.0.108' -Cidr '192.200.0.0/24' | Should -BeTrue
            Test-MetraIPv4InCidr -Address '192.200.0.1' -Cidr '192.200.0.0/24' | Should -BeTrue
            Test-MetraIPv4InCidr -Address '203.0.113.10' -Cidr '192.200.0.0/24' | Should -BeFalse
            Test-MetraIPv4InCidr -Address '10.7.2.91' -Cidr '192.200.0.0/24' | Should -BeFalse
        }
    }

    It 'Get-MetraTailscaleCampusHostsPlan pins preferred anycast and drops MITM VIP' {
        InModuleScope Metra {
            $tmp = Join-Path $env:TEMP ('metra-ts-hosts-' + [guid]::NewGuid().ToString('N'))
            $hostsFile = Join-Path $tmp 'hosts'
            try {
                $null = New-Item -ItemType Directory -Path $tmp -Force
                @(
                    '# sample'
                    '203.0.113.10 login.tailscale.com'
                    '192.200.0.108 controlplane.tailscale.com'
                ) | Set-Content -LiteralPath $hostsFile -Encoding ascii

                $plan = Get-MetraTailscaleCampusHostsPlan -HostsPath $hostsFile -HostName @(
                    'login.tailscale.com'
                    'controlplane.tailscale.com'
                )
                $plan.Ok | Should -BeTrue
                $plan.NeedsWrite | Should -BeTrue
                $plan.DesiredLines.Count | Should -BeGreaterThan 0
                @($plan.DesiredLines | Where-Object { $_ -match 'login\.tailscale\.com$' }).Count | Should -BeGreaterThan 0
                @($plan.DesiredLines | Where-Object { $_ -match '^45\.54\.' }).Count | Should -Be 0
                $plan.StaleLines | Should -Contain '203.0.113.10 login.tailscale.com'
            }
            finally {
                if (Test-Path -LiteralPath $tmp) {
                    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    It 'Repair without enabled local config refuses apply' {
        InModuleScope Metra {
            $missing = Join-Path $env:TEMP ('metra-campus-missing-' + [guid]::NewGuid().ToString('N') + '.json')
            $result = Repair-MetraTailscaleCampusHosts -Preview -Quiet -ConfigPath $missing
            $result.Ok | Should -BeFalse
            $result.Error | Should -Match 'local campus config|enabled'
        }
    }

    It 'Repair -Preview with explicit HostName does not write' {
        InModuleScope Metra {
            $result = Repair-MetraTailscaleCampusHosts -Preview -Quiet -HostName @(
                'login.tailscale.com'
                'controlplane.tailscale.com'
            )
            $result.Ok | Should -BeTrue
            $result.Preview | Should -BeTrue
            $result.Changed | Should -BeFalse
        }
    }

    It 'CLI campus-hosts refuses when seeded AppData config is disabled for the call' {
        # Show-MetraTailscaleCli has no -ConfigPath; exercise Repair gate used by CLI.
        InModuleScope Metra {
            $tmp = Join-Path $env:TEMP ('metra-campus-disabled-' + [guid]::NewGuid().ToString('N') + '.json')
            @{ schemaVersion = 1; enabled = $false; hostNames = @('login.tailscale.com') } |
                ConvertTo-Json | Set-Content -LiteralPath $tmp -Encoding utf8
            try {
                $result = Repair-MetraTailscaleCampusHosts -Preview -Quiet -ConfigPath $tmp
                $result.Ok | Should -BeFalse
            }
            finally {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
