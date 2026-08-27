# Metra Tailscale campus hosts (IWU DNSFilter bypass)

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
            Test-MetraIPv4InCidr -Address '45.54.28.11' -Cidr '192.200.0.0/24' | Should -BeFalse
            Test-MetraIPv4InCidr -Address '10.7.2.91' -Cidr '192.200.0.0/24' | Should -BeFalse
        }
    }

    It 'Get-MetraTailscaleCampusHostsPlan pins preferred anycast and drops DNSFilter VIP' {
        InModuleScope Metra {
            $tmp = Join-Path $env:TEMP ('metra-ts-hosts-' + [guid]::NewGuid().ToString('N'))
            $hostsFile = Join-Path $tmp 'hosts'
            try {
                $null = New-Item -ItemType Directory -Path $tmp -Force
                @(
                    '# sample'
                    '45.54.28.11 login.tailscale.com'
                    '192.200.0.108 controlplane.tailscale.com'
                ) | Set-Content -LiteralPath $hostsFile -Encoding ascii

                $plan = Get-MetraTailscaleCampusHostsPlan -HostsPath $hostsFile
                $plan.Ok | Should -BeTrue
                $plan.NeedsWrite | Should -BeTrue
                $plan.DesiredLines.Count | Should -BeGreaterThan 0
                @($plan.DesiredLines | Where-Object { $_ -match 'login\.tailscale\.com$' }).Count | Should -BeGreaterThan 0
                @($plan.DesiredLines | Where-Object { $_ -match '^45\.54\.' }).Count | Should -Be 0
                $plan.StaleLines | Should -Contain '45.54.28.11 login.tailscale.com'
            }
            finally {
                if (Test-Path -LiteralPath $tmp) {
                    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    It 'Repair-MetraTailscaleCampusHosts -Preview does not write' {
        InModuleScope Metra {
            $result = Repair-MetraTailscaleCampusHosts -Preview -Quiet
            $result.Ok | Should -BeTrue
            $result.Preview | Should -BeTrue
            $result.Changed | Should -BeFalse
        }
    }

    It 'Show-MetraTailscaleCli campus-hosts -Preview returns a plan object' {
        $result = Show-MetraTailscaleCli -Subcommand campus-hosts -Preview -Quiet
        $result.Ok | Should -BeTrue
        $result.Preview | Should -BeTrue
    }
}
