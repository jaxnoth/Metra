# Metra Tailscale client identity + device capability tokens

Describe 'Metra ClientAuth WhoIs and allowlist' {
    BeforeAll {
        $module = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Metra.psd1'
        Import-Module $module -Force
    }

    BeforeEach {
        InModuleScope Metra { Clear-MetraTailscaleWhoIsCache }
    }

    It 'Get-MetraTailscaleWhoIs parses whois JSON and caches by IP' {
        InModuleScope Metra {
            $script:MetraWhoIsTestCalls = 0
            $who = {
                param($ip)
                $script:MetraWhoIsTestCalls++
                return (@{
                        UserProfile = @{ LoginName = 'op@example.com' }
                        Node        = @{ Name = 'laptop.tailnet.ts.net'; Tags = @('tag:metra-client') }
                    } | ConvertTo-Json -Depth 5)
            }
            $a = Get-MetraTailscaleWhoIs -Address '100.64.1.2' -WhoIsCommand $who
            $a.Login | Should -Be 'op@example.com'
            $a.Node | Should -Be 'laptop.tailnet.ts.net'
            $a.Tags | Should -Contain 'tag:metra-client'
            $b = Get-MetraTailscaleWhoIs -Address '100.64.1.2' -WhoIsCommand $who
            $b.Login | Should -Be 'op@example.com'
            $script:MetraWhoIsTestCalls | Should -Be 1
        }
    }

    It 'allowlist hit and miss' {
        $root = Join-Path $env:TEMP ("metra-client-auth-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force
        try {
            $cfgPath = Join-Path $root 'client-auth.local.json'
            @{
                schemaVersion = 1
                allowlist     = @(
                    @{ login = 'op@example.com'; node = ''; tag = '' }
                    @{ login = ''; node = ''; tag = 'tag:metra-client' }
                )
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8

            InModuleScope Metra -Parameters @{ Root = $root } {
                $ok = ConvertTo-MetraPeerIdentityRecord -Login 'op@example.com' -Node 'x' -Tags @()
                Test-MetraClientIdentityAllowed -Identity $ok -MetraRoot $Root | Should -BeTrue

                $tagOk = ConvertTo-MetraPeerIdentityRecord -Login 'other@x' -Node 'y' -Tags @('tag:metra-client')
                Test-MetraClientIdentityAllowed -Identity $tagOk -MetraRoot $Root | Should -BeTrue

                $deny = ConvertTo-MetraPeerIdentityRecord -Login 'nope@example.com' -Node 'other' -Tags @()
                Test-MetraClientIdentityAllowed -Identity $deny -MetraRoot $Root | Should -BeFalse

                Test-MetraClientAuthAllowlistConfigured -MetraRoot $Root | Should -BeTrue
            }
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'empty allowlist is not configured (transitional)' {
        $root = Join-Path $env:TEMP ("metra-client-auth-empty-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force
        try {
            InModuleScope Metra -Parameters @{ Root = $root } {
                Test-MetraClientAuthAllowlistConfigured -MetraRoot $Root | Should -BeFalse
                $req = [pscustomobject]@{
                    Headers        = @{}
                    RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Parse('127.0.0.1') }
                }
                Test-MetraOpsRemoteAskIdentityAllowed -Request $req -MetraRoot $Root | Should -BeTrue
            }
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Serve path uses Tailscale-User-Login; non-Serve ignores spoofed header' {
        InModuleScope Metra {
            $who = {
                param($ip)
                return (@{
                        UserProfile = @{ LoginName = 'from-whois@example.com' }
                        Node        = @{ Name = 'peer' }
                    } | ConvertTo-Json -Depth 4)
            }
            $serveReq = [pscustomobject]@{
                Headers = @{
                    'Tailscale-User-Login' = 'serve@example.com'
                    'X-Forwarded-For'      = '100.64.9.9'
                }
                RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Loopback }
            }
            $idServe = Get-MetraOpsRequestPeerIdentity -Request $serveReq -WhoIsCommand $who
            $idServe.Login | Should -Be 'serve@example.com'
            $idServe.Source | Should -Be 'serve-headers'
            $idServe.Node | Should -BeNullOrEmpty

            # Display name must never become Node when Headers-Info has no node id.
            $serveNameOnly = [pscustomobject]@{
                Headers = @{
                    'Tailscale-User-Login' = 'serve@example.com'
                    'Tailscale-User-Name'  = 'Jane Doe'
                    'X-Forwarded-For'      = '100.64.9.9'
                }
                RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Loopback }
            }
            $idName = Get-MetraOpsRequestPeerIdentity -Request $serveNameOnly -WhoIsCommand $who
            $idName.Login | Should -Be 'serve@example.com'
            $idName.Node | Should -BeNullOrEmpty
            $idName.Source | Should -Be 'serve-headers'

            $directReq = [pscustomobject]@{
                Headers = @{
                    'Tailscale-User-Login' = 'spoofed@evil.example'
                    'X-Forwarded-For'      = '100.64.1.1'
                }
                RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Parse('100.64.1.5') }
            }
            # Direct bind must WhoIs RemoteEndPoint, not spoofed X-Forwarded-For.
            $idDirect = Get-MetraOpsRequestPeerIdentity -Request $directReq -WhoIsCommand $who
            $idDirect.Login | Should -Be 'from-whois@example.com'
            $idDirect.Source | Should -Be 'whois'
            $idDirect.Ip | Should -Be '100.64.1.5'
        }
    }

    It 'Get-MetraOpsRequestClientIp ignores X-Forwarded-For on non-loopback' {
        InModuleScope Metra {
            $direct = [pscustomobject]@{
                Headers = @{ 'X-Forwarded-For' = '100.64.9.9' }
                RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Parse('100.64.1.5') }
            }
            Get-MetraOpsRequestClientIp -Request $direct | Should -Be '100.64.1.5'

            $serve = [pscustomobject]@{
                Headers = @{ 'X-Forwarded-For' = '100.64.9.9' }
                RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Loopback }
            }
            Get-MetraOpsRequestClientIp -Request $serve | Should -Be '100.64.9.9'
        }
    }
}

Describe 'Metra ClientAuth device ledger' {
    BeforeAll {
        $module = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Metra.psd1'
        Import-Module $module -Force
    }

    It 'mint validate revoke and lastSeen update' {
        $dataDir = Join-Path $env:TEMP ("metra-client-devices-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $dataDir -Force
        try {
            InModuleScope Metra -Parameters @{ DataDir = $dataDir } {
                $identity = ConvertTo-MetraPeerIdentityRecord -Login 'op@example.com' -Node 'macbook' -Tags @() -Ip '100.64.2.2'
                $minted = New-MetraClientDeviceToken -Identity $identity -Label 'MacBook' -DataDir $DataDir
                $minted.Ok | Should -BeTrue
                $minted.Token | Should -Not -BeNullOrEmpty

                Test-MetraClientDeviceToken -Token $minted.Token -DataDir $DataDir -ClientIp '100.64.2.3' -Identity $identity | Should -BeTrue
                $list = @(Get-MetraClientDeviceList -DataDir $DataDir)
                $list.Count | Should -Be 1
                $list[0].label | Should -Be 'MacBook'
                $list[0].lastIp | Should -Be '100.64.2.3'
                $list[0].lastSeenUtc | Should -Not -BeNullOrEmpty

                $rev = Revoke-MetraClientDeviceToken -DeviceId $minted.DeviceId -DataDir $DataDir
                $rev.Ok | Should -BeTrue
                Test-MetraClientDeviceToken -Token $minted.Token -DataDir $DataDir -NoTouch | Should -BeFalse

                $legacy = Initialize-MetraProfileSyncToken -Rotate -DataDir $DataDir
                Test-MetraProfileSyncToken -SyncToken $legacy.Token -DataDir $DataDir | Should -BeTrue
            }
        }
        finally {
            Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'pair auto-accept for Self login mints device; unknown goes pending' {
        $dataDir = Join-Path $env:TEMP ("metra-client-pair-" + [guid]::NewGuid().ToString('N'))
        $root = Join-Path $env:TEMP ("metra-client-pair-root-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $dataDir -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force
        try {
            InModuleScope Metra -Parameters @{ DataDir = $dataDir; Root = $root } {
                $statusCmd = {
                    return (@{ UserProfile = @{ LoginName = 'op@example.com' } } | ConvertTo-Json)
                }
                $whoSelf = {
                    param($ip)
                    return (@{
                            UserProfile = @{ LoginName = 'op@example.com' }
                            Node        = @{ Name = 'sat-1' }
                        } | ConvertTo-Json -Depth 4)
                }
                $req = [pscustomobject]@{
                    Headers        = @{}
                    RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Parse('100.64.8.8') }
                }
                $accepted = Invoke-MetraClientPairRequest -Request $req -Label 'sat' -MetraRoot $Root -DataDir $DataDir `
                    -WhoIsCommand $whoSelf -StatusCommand $statusCmd
                $accepted.Accepted | Should -BeTrue
                $accepted.Token | Should -Not -BeNullOrEmpty

                Clear-MetraTailscaleWhoIsCache
                $whoOther = {
                    param($ip)
                    return (@{
                            UserProfile = @{ LoginName = 'stranger@example.com' }
                            Node        = @{ Name = 'unknown-node' }
                        } | ConvertTo-Json -Depth 4)
                }
                $req2 = [pscustomobject]@{
                    Headers        = @{}
                    RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Parse('100.64.8.9') }
                }
                $pending = Invoke-MetraClientPairRequest -Request $req2 -Label 'other' -MetraRoot $Root -DataDir $DataDir `
                    -WhoIsCommand $whoOther -StatusCommand $statusCmd
                $pending.Pending | Should -BeTrue
                $pending.RequestId | Should -Not -BeNullOrEmpty

                $approved = Approve-MetraClientPairRequest -RequestId $pending.RequestId -MetraRoot $Root -DataDir $DataDir
                $approved.Ok | Should -BeTrue
                $approved.Token | Should -Not -BeNullOrEmpty
                Test-MetraClientAuthAllowlistConfigured -MetraRoot $Root | Should -BeTrue
            }
        }
        finally {
            Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'remote sync capability: legacy break-glass alone; device needs allowlist WhoIs when configured' {
        $dataDir = Join-Path $env:TEMP ("metra-client-remote-cap-" + [guid]::NewGuid().ToString('N'))
        $root = Join-Path $env:TEMP ("metra-client-remote-root-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $dataDir -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force
        try {
            InModuleScope Metra -Parameters @{ DataDir = $dataDir; Root = $root } {
                $legacy = Initialize-MetraProfileSyncToken -Rotate -DataDir $DataDir
                $reqLegacy = [pscustomobject]@{
                    Headers        = @{ 'X-Metra-Profile-Sync' = $legacy.Token }
                    RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Parse('100.64.3.3') }
                }
                Test-MetraOpsProfileSyncRemoteCapability -Request $reqLegacy -MetraRoot $Root -DataDir $DataDir | Should -BeTrue

                $identity = ConvertTo-MetraPeerIdentityRecord -Login 'op@example.com' -Node 'sat' -Ip '100.64.3.4'
                $minted = New-MetraClientDeviceToken -Identity $identity -Label 'sat' -DataDir $DataDir
                @{
                    schemaVersion = 1
                    allowlist     = @(@{ login = 'op@example.com'; node = ''; tag = '' })
                } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Root 'client-auth.local.json') -Encoding utf8

                $whoOk = {
                    param($ip)
                    return (@{ UserProfile = @{ LoginName = 'op@example.com' }; Node = @{ Name = 'sat' } } | ConvertTo-Json -Depth 4)
                }
                $reqDev = [pscustomobject]@{
                    Headers        = @{ 'X-Metra-Profile-Sync' = $minted.Token }
                    RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Parse('100.64.3.4') }
                }
                Test-MetraOpsProfileSyncRemoteCapability -Request $reqDev -MetraRoot $Root -DataDir $DataDir -WhoIsCommand $whoOk |
                    Should -BeTrue

                $whoBad = {
                    param($ip)
                    return (@{ UserProfile = @{ LoginName = 'nope@example.com' }; Node = @{ Name = 'other' } } | ConvertTo-Json -Depth 4)
                }
                Clear-MetraTailscaleWhoIsCache
                Test-MetraOpsProfileSyncRemoteCapability -Request $reqDev -MetraRoot $Root -DataDir $DataDir -WhoIsCommand $whoBad |
                    Should -BeFalse

                $null = Revoke-MetraClientDeviceToken -DeviceId $minted.DeviceId -DataDir $DataDir
                Clear-MetraTailscaleWhoIsCache
                Test-MetraOpsProfileSyncRemoteCapability -Request $reqDev -MetraRoot $Root -DataDir $DataDir -WhoIsCommand $whoOk |
                    Should -BeFalse
            }
        }
        finally {
            Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'remote Ask denies when allowlist configured and WhoIs misses' {
        $root = Join-Path $env:TEMP ("metra-client-ask-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force
        try {
            @{
                schemaVersion = 1
                allowlist     = @(@{ login = 'op@example.com'; node = ''; tag = '' })
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'client-auth.local.json') -Encoding utf8

            InModuleScope Metra -Parameters @{ Root = $root } {
                $whoBad = {
                    param($ip)
                    return (@{ UserProfile = @{ LoginName = 'nope@example.com' }; Node = @{ Name = 'x' } } | ConvertTo-Json -Depth 4)
                }
                $req = [pscustomobject]@{
                    Headers        = @{}
                    RemoteEndPoint = [pscustomobject]@{ Address = [IPAddress]::Parse('100.64.7.7') }
                }
                Test-MetraOpsRemoteAskIdentityAllowed -Request $req -MetraRoot $Root -WhoIsCommand $whoBad | Should -BeFalse

                $whoOk = {
                    param($ip)
                    return (@{ UserProfile = @{ LoginName = 'op@example.com' }; Node = @{ Name = 'x' } } | ConvertTo-Json -Depth 4)
                }
                Clear-MetraTailscaleWhoIsCache
                Test-MetraOpsRemoteAskIdentityAllowed -Request $req -MetraRoot $Root -WhoIsCommand $whoOk | Should -BeTrue
            }
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
