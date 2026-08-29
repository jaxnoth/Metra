# Tailscale client identity (WhoIs + allowlist) and host-minted device capability tokens.
# Reach/identity only - never local authority. See SECURITY.md and docs/tailscale-identity-auth.plan.md.

$script:MetraWhoIsCache = @{}
$script:MetraWhoIsCacheTtlSeconds = 120

function Get-MetraClientAuthConfigPath {
    param([string]$MetraRoot = (Get-MetraRoot))
    return Join-Path $MetraRoot 'docs\client-auth.local.json'
}

function Get-MetraClientDevicesPath {
    param([string]$DataDir)

    if (-not [string]::IsNullOrWhiteSpace($DataDir)) {
        return Join-Path $DataDir 'client-devices.json'
    }
    return Join-Path $env:LOCALAPPDATA 'Metra\client-devices.json'
}

function Get-MetraClientPairPendingPath {
    param([string]$DataDir)

    if (-not [string]::IsNullOrWhiteSpace($DataDir)) {
        return Join-Path $DataDir 'client-pair-pending.json'
    }
    return Join-Path $env:LOCALAPPDATA 'Metra\client-pair-pending.json'
}

function Clear-MetraTailscaleWhoIsCache {
    <#
    .SYNOPSIS
        Clears the in-process WhoIs IP cache (tests / operator refresh).
    #>
    [CmdletBinding()]
    param()

    $script:MetraWhoIsCache = @{}
}

function Get-MetraOpsRequestClientIp {
    <#
    .SYNOPSIS
        Best-effort client IP for identity: Serve forwarded headers only on loopback, else RemoteEndPoint.
    .DESCRIPTION
        Tailscale Serve connects to loopback and injects X-Forwarded-For. Direct Tailscale / non-loopback
        binds must ignore client-supplied forwarded headers (spoofable).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Request)

    $remoteLoopback = $false
    try {
        $remoteLoopback = [System.Net.IPAddress]::IsLoopback($Request.RemoteEndPoint.Address)
    }
    catch { }

    if ($remoteLoopback) {
        $fwd = Get-MetraOpsRequestForwardedClientAddress -Request $Request
        if ($null -ne $fwd) {
            return $fwd.ToString()
        }
    }

    try {
        return [string]$Request.RemoteEndPoint.Address
    }
    catch {
        return $null
    }
}

function ConvertTo-MetraPeerIdentityRecord {
    param(
        [string]$Login = '',
        [string]$Node = '',
        [object]$Tags = $null,
        [string]$Source = '',
        [string]$Ip = ''
    )

    $tagList = @()
    foreach ($t in @($Tags)) {
        $s = [string]$t
        if (-not [string]::IsNullOrWhiteSpace($s)) {
            $tagList += $s.Trim()
        }
    }

    return [PSCustomObject]@{
        Login  = $(if ($Login) { $Login.Trim() } else { '' })
        Node   = $(if ($Node) { $Node.Trim().TrimEnd('.') } else { '' })
        Tags   = @($tagList)
        Source = $Source
        Ip     = $(if ($Ip) { $Ip.Trim() } else { '' })
    }
}

function Get-MetraTailscaleWhoIs {
    <#
    .SYNOPSIS
        Resolves Tailscale peer identity for an IP via whois (cached 120s by IP).
    .PARAMETER WhoIsCommand
        Optional scriptblock for tests: receives IP string, returns JSON text or object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Address,
        [scriptblock]$WhoIsCommand,
        [switch]$SkipCache
    )

    $ipKey = $Address.Trim()
    if ([string]::IsNullOrWhiteSpace($ipKey)) {
        return $null
    }

    if (-not $SkipCache) {
        $cached = $script:MetraWhoIsCache[$ipKey]
        if ($null -ne $cached) {
            $age = ([datetime]::UtcNow - [datetime]$cached.CachedUtc).TotalSeconds
            if ($age -ge 0 -and $age -lt $script:MetraWhoIsCacheTtlSeconds) {
                return $cached.Identity
            }
        }
    }

    $raw = $null
    try {
        if ($WhoIsCommand) {
            $raw = & $WhoIsCommand $ipKey
        }
        else {
            $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
            if (-not $cmd) { return $null }
            $raw = & tailscale whois --json $ipKey 2>$null | Out-String
        }
    }
    catch {
        return $null
    }

    if ($null -eq $raw) { return $null }
    $obj = $null
    if ($raw -is [string]) {
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        try { $obj = $raw | ConvertFrom-Json } catch { return $null }
    }
    else {
        $obj = $raw
    }
    if ($null -eq $obj) { return $null }

    $login = [string](Get-MetraProp -Object (Get-MetraProp -Object $obj -Name 'UserProfile' -Default $null) -Name 'LoginName' -Default '')
    if ([string]::IsNullOrWhiteSpace($login)) {
        $login = [string](Get-MetraProp -Object $obj -Name 'LoginName' -Default '')
    }
    $nodeObj = Get-MetraProp -Object $obj -Name 'Node' -Default $null
    $node = [string](Get-MetraProp -Object $nodeObj -Name 'Name' -Default '')
    if ([string]::IsNullOrWhiteSpace($node)) {
        $node = [string](Get-MetraProp -Object $nodeObj -Name 'HostName' -Default '')
    }
    $tags = @(Get-MetraProp -Object $nodeObj -Name 'Tags' -Default @())
    if ($tags.Count -eq 0) {
        $tags = @(Get-MetraProp -Object $obj -Name 'Tags' -Default @())
    }

    $identity = ConvertTo-MetraPeerIdentityRecord -Login $login -Node $node -Tags $tags -Source 'whois' -Ip $ipKey
    if ([string]::IsNullOrWhiteSpace($identity.Login) -and [string]::IsNullOrWhiteSpace($identity.Node) -and @($identity.Tags).Count -eq 0) {
        return $null
    }

    $script:MetraWhoIsCache[$ipKey] = [PSCustomObject]@{
        CachedUtc = [datetime]::UtcNow
        Identity  = $identity
    }
    return $identity
}

function Get-MetraOpsRequestPeerIdentity {
    <#
    .SYNOPSIS
        Peer identity for a request: Serve-injected headers when proxied, else WhoIs on client IP.
    .DESCRIPTION
        Trust Tailscale-* identity headers only when RemoteEndPoint is loopback (Serve connects
        locally). Direct Tailscale binds use WhoIs on the peer IP and ignore client-supplied
        Tailscale-* headers (spoofable). Test-MetraOpsRequestLooksProxiedThroughServe alone is
        not enough - that helper returns true if Tailscale-User-Login is present.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [scriptblock]$WhoIsCommand
    )

    $ip = Get-MetraOpsRequestClientIp -Request $Request
    $remoteLoopback = $false
    try {
        $remoteLoopback = [System.Net.IPAddress]::IsLoopback($Request.RemoteEndPoint.Address)
    }
    catch { }

    $loginHdr = ''
    try { $loginHdr = [string]$Request.Headers['Tailscale-User-Login'] } catch { }
    $hasServeIdentityHeader = -not [string]::IsNullOrWhiteSpace($loginHdr)
    $fwdAddr = Get-MetraOpsRequestForwardedClientAddress -Request $Request
    $hasNonLoopbackForwarded = ($null -ne $fwdAddr -and -not [System.Net.IPAddress]::IsLoopback($fwdAddr))

    # Serve -> loopback listener: trust injected identity headers only with a real forwarded peer IP.
    if ($remoteLoopback -and $hasNonLoopbackForwarded -and $hasServeIdentityHeader) {
        $login = $loginHdr
        $node = ''
        try {
            $info = [string]$Request.Headers['Tailscale-Headers-Info']
            if ($info -match '(?i)node[=:]([^\s;,]+)') {
                $node = $Matches[1]
            }
        }
        catch { }
        # Do not map Tailscale-User-Name (display name) onto Node - leave Node empty and rely on Login.

        if (-not [string]::IsNullOrWhiteSpace($login) -or -not [string]::IsNullOrWhiteSpace($node)) {
            return ConvertTo-MetraPeerIdentityRecord -Login $login -Node $node -Tags @() -Source 'serve-headers' -Ip $(if ($ip) { $ip } else { '' })
        }
        # Loopback Serve without usable login: fall through to WhoIs on forwarded IP when present.
    }

    if ([string]::IsNullOrWhiteSpace($ip)) {
        return $null
    }

    $whoParams = @{ Address = $ip }
    if ($WhoIsCommand) { $whoParams.WhoIsCommand = $WhoIsCommand }
    return Get-MetraTailscaleWhoIs @whoParams
}

function Get-MetraTailscaleSelfLogin {
    <#
    .SYNOPSIS
        This host's Tailscale login name from status --json (for first-pair auto-accept).
    #>
    [CmdletBinding()]
    param([scriptblock]$StatusCommand)

    try {
        $raw = $null
        if ($StatusCommand) {
            $raw = & $StatusCommand
        }
        else {
            $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
            if (-not $cmd) { return '' }
            $raw = & tailscale status --json 2>$null | Out-String
        }
        if ($null -eq $raw) { return '' }
        $obj = if ($raw -is [string]) {
            if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
            $raw | ConvertFrom-Json
        }
        else { $raw }

        $login = [string](Get-MetraProp -Object (Get-MetraProp -Object $obj -Name 'UserProfile' -Default $null) -Name 'LoginName' -Default '')
        if ([string]::IsNullOrWhiteSpace($login)) {
            $self = Get-MetraProp -Object $obj -Name 'Self' -Default $null
            $userId = Get-MetraProp -Object $self -Name 'UserID' -Default $null
            $users = Get-MetraProp -Object $obj -Name 'User' -Default $null
            if ($null -ne $users -and $null -ne $userId) {
                $uid = [string]$userId
                try {
                    $u = $users.$uid
                    $login = [string](Get-MetraProp -Object $u -Name 'LoginName' -Default '')
                }
                catch { }
            }
        }
        return $(if ($login) { $login.Trim() } else { '' })
    }
    catch {
        return ''
    }
}

function Get-MetraClientAuthConfig {
    <#
    .SYNOPSIS
        Loads docs/client-auth.local.json allowlist (empty when missing).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Get-MetraClientAuthConfigPath -MetraRoot $MetraRoot
    $empty = [PSCustomObject]@{
        Path       = $path
        Exists     = $false
        Allowlist  = @()
        Configured = $false
    }
    if (-not (Test-Path -LiteralPath $path)) {
        return $empty
    }
    try {
        $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $entries = @()
        $rawList = Get-MetraProp -Object $data -Name 'allowlist' -Default @()
        foreach ($item in @($rawList)) {
            if ($null -eq $item) { continue }
            if ($item -is [string]) {
                $s = [string]$item
                if (-not [string]::IsNullOrWhiteSpace($s)) {
                    $entries += [PSCustomObject]@{ login = $s.Trim(); node = ''; tag = '' }
                }
                continue
            }
            $entries += [PSCustomObject]@{
                login = [string](Get-MetraProp -Object $item -Name 'login' -Default '').Trim()
                node  = [string](Get-MetraProp -Object $item -Name 'node' -Default '').Trim().TrimEnd('.')
                tag   = [string](Get-MetraProp -Object $item -Name 'tag' -Default '').Trim()
            }
        }
        $configured = $false
        foreach ($e in $entries) {
            if ($e.login -or $e.node -or $e.tag) { $configured = $true; break }
        }
        return [PSCustomObject]@{
            Path       = $path
            Exists     = $true
            Allowlist  = @($entries)
            Configured = $configured
            ParseError = $false
        }
    }
    catch {
        # Fail closed: corrupt allowlist must not reopen transitional Ask/sync.
        return [PSCustomObject]@{
            Path       = $path
            Exists     = $true
            Allowlist  = @()
            Configured = $true
            ParseError = $true
        }
    }
}

function Test-MetraClientAuthAllowlistConfigured {
    param([string]$MetraRoot = (Get-MetraRoot))
    return [bool](Get-MetraClientAuthConfig -MetraRoot $MetraRoot).Configured
}

function Test-MetraClientIdentityAllowed {
    <#
    .SYNOPSIS
        True when identity matches an allowlist entry (login, node, or tag).
    .DESCRIPTION
        Empty/missing allowlist returns $false for an explicit deny check; callers that
        treat empty allowlist as transitional must check Configured first.
    #>
    [CmdletBinding()]
    param(
        $Identity,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($null -eq $Identity) { return $false }
    $cfg = Get-MetraClientAuthConfig -MetraRoot $MetraRoot
    if (-not $cfg.Configured) { return $false }

    $login = [string](Get-MetraProp -Object $Identity -Name 'Login' -Default '').Trim()
    $node = [string](Get-MetraProp -Object $Identity -Name 'Node' -Default '').Trim().TrimEnd('.')
    $tags = @($(Get-MetraProp -Object $Identity -Name 'Tags' -Default @()) | ForEach-Object { [string]$_ })

    foreach ($entry in @($cfg.Allowlist)) {
        $eLogin = [string]$entry.login
        $eNode = [string]$entry.node
        $eTag = [string]$entry.tag
        $criteria = 0
        $matched = 0
        if ($eLogin) {
            $criteria++
            if ($login -and $eLogin.Equals($login, [StringComparison]::OrdinalIgnoreCase)) {
                $matched++
            }
        }
        if ($eNode) {
            $criteria++
            if ($node -and $eNode.Equals($node, [StringComparison]::OrdinalIgnoreCase)) {
                $matched++
            }
        }
        if ($eTag) {
            $criteria++
            $tagHit = $false
            foreach ($t in $tags) {
                if ($t -and $eTag.Equals($t.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
                    $tagHit = $true
                    break
                }
            }
            if ($tagHit) { $matched++ }
        }
        # Multi-field rows are conjunctive (AND). Single-field rows stay simple matches.
        if ($criteria -gt 0 -and $matched -eq $criteria) {
            return $true
        }
    }
    return $false
}

function Test-MetraClientIdentityPairAutoAccept {
    <#
    .SYNOPSIS
        True when identity may auto-pair: allowlisted or matches this host Tailscale login.
    #>
    [CmdletBinding()]
    param(
        $Identity,
        [string]$MetraRoot = (Get-MetraRoot),
        [scriptblock]$StatusCommand
    )

    if ($null -eq $Identity) { return $false }
    if (Test-MetraClientIdentityAllowed -Identity $Identity -MetraRoot $MetraRoot) {
        return $true
    }
    $selfLogin = Get-MetraTailscaleSelfLogin -StatusCommand $StatusCommand
    $login = [string](Get-MetraProp -Object $Identity -Name 'Login' -Default '').Trim()
    if ($selfLogin -and $login -and $selfLogin.Equals($login, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $false
}

function Get-MetraClientDevicesLedger {
    param([string]$DataDir)

    $path = Get-MetraClientDevicesPath -DataDir $DataDir
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{
            Path    = $path
            Devices = @()
        }
    }
    try {
        $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $devices = @(Get-MetraProp -Object $data -Name 'devices' -Default @())
        return [PSCustomObject]@{
            Path    = $path
            Devices = @($devices)
        }
    }
    catch {
        return [PSCustomObject]@{
            Path    = $path
            Devices = @()
        }
    }
}

function Save-MetraClientDevicesLedger {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Devices,
        [string]$DataDir
    )

    $path = Get-MetraClientDevicesPath -DataDir $DataDir
    $payload = [ordered]@{
        schemaVersion = 1
        devices       = @($Devices)
    }
    $json = ($payload | ConvertTo-Json -Depth 8)
    Write-MetraProfileAtomicText -Path $path -Text ($json + "`n")
    return $path
}

function Test-MetraTokenHashEquals {
    param(
        [Parameter(Mandatory)][string]$PresentedHex,
        [Parameter(Mandatory)][string]$ExpectedHex
    )

    $a = [System.Text.Encoding]::UTF8.GetBytes($PresentedHex.Trim().ToLowerInvariant())
    $b = [System.Text.Encoding]::UTF8.GetBytes($ExpectedHex.Trim().ToLowerInvariant())
    if ($a.Length -ne $b.Length) { return $false }
    try {
        return [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals($a, $b)
    }
    catch {
        $diff = 0
        for ($i = 0; $i -lt $a.Length; $i++) {
            $diff = $diff -bor ($a[$i] -bxor $b[$i])
        }
        return ($diff -eq 0)
    }
}

function New-MetraClientDeviceToken {
    <#
    .SYNOPSIS
        Mints a device capability token; stores hash + identity snapshot. Plaintext returned once.
    #>
    [CmdletBinding()]
    param(
        $Identity,
        [string]$Label = '',
        [string]$DataDir
    )

    $rawBytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($rawBytes)
    }
    finally {
        $rng.Dispose()
    }
    $token = -join ($rawBytes | ForEach-Object { $_.ToString('x2') })
    $tokenHash = Get-MetraProfileSyncTokenSha256Hex -Token $token
    $deviceId = [guid]::NewGuid().ToString('N')
    $now = [datetime]::UtcNow.ToString('o')
    $login = [string](Get-MetraProp -Object $Identity -Name 'Login' -Default '')
    $node = [string](Get-MetraProp -Object $Identity -Name 'Node' -Default '')
    $tags = @(Get-MetraProp -Object $Identity -Name 'Tags' -Default @())
    $ip = [string](Get-MetraProp -Object $Identity -Name 'Ip' -Default '')
    if ([string]::IsNullOrWhiteSpace($Label)) {
        $Label = if ($node) { $node } elseif ($login) { $login } else { "device-$($deviceId.Substring(0, 8))" }
    }

    $device = [PSCustomObject]@{
        deviceId      = $deviceId
        label         = $Label
        login         = $login
        node          = $node
        tags          = @($tags)
        tokenHash     = $tokenHash
        issuedUtc     = $now
        revokedUtc    = $null
        lastSeenUtc   = $now
        lastIp        = $ip
        lastIdentity  = [PSCustomObject]@{
            login = $login
            node  = $node
            tags  = @($tags)
        }
    }

    $ledger = Get-MetraClientDevicesLedger -DataDir $DataDir
    $devices = @($ledger.Devices) + @($device)
    $null = Save-MetraClientDevicesLedger -Devices $devices -DataDir $DataDir

    return [PSCustomObject]@{
        Ok        = $true
        DeviceId  = $deviceId
        Label     = $Label
        Token     = $token
        TokenHash = $tokenHash
        Header    = 'X-Metra-Profile-Sync'
        Device    = $device
        Message   = 'Store this token as syncToken in docs/profile-sync.local.json. It is shown once.'
    }
}

function Test-MetraClientDeviceToken {
    <#
    .SYNOPSIS
        Validates a device capability token. On success updates lastSeen metadata.
    #>
    [CmdletBinding()]
    param(
        [string]$Token,
        [string]$DataDir,
        [string]$ClientIp = '',
        $Identity = $null,
        [switch]$NoTouch
    )

    if ([string]::IsNullOrWhiteSpace($Token)) { return $false }

    $presented = Get-MetraProfileSyncTokenSha256Hex -Token $Token
    $ledger = Get-MetraClientDevicesLedger -DataDir $DataDir
    $matched = $null
    $matchedIndex = -1
    for ($i = 0; $i -lt @($ledger.Devices).Count; $i++) {
        $d = $ledger.Devices[$i]
        $revoked = Get-MetraProp -Object $d -Name 'revokedUtc' -Default $null
        if ($null -ne $revoked -and -not [string]::IsNullOrWhiteSpace([string]$revoked)) {
            continue
        }
        $hash = [string](Get-MetraProp -Object $d -Name 'tokenHash' -Default '')
        if ([string]::IsNullOrWhiteSpace($hash)) { continue }
        if (Test-MetraTokenHashEquals -PresentedHex $presented -ExpectedHex $hash) {
            $matched = $d
            $matchedIndex = $i
            break
        }
    }
    if ($null -eq $matched) { return $false }

    if (-not $NoTouch -and $matchedIndex -ge 0) {
        $login = [string](Get-MetraProp -Object $Identity -Name 'Login' -Default (Get-MetraProp -Object $matched -Name 'login' -Default ''))
        $node = [string](Get-MetraProp -Object $Identity -Name 'Node' -Default (Get-MetraProp -Object $matched -Name 'node' -Default ''))
        $tags = @(Get-MetraProp -Object $Identity -Name 'Tags' -Default (Get-MetraProp -Object $matched -Name 'tags' -Default @()))
        $ip = if ($ClientIp) { $ClientIp } else { [string](Get-MetraProp -Object $Identity -Name 'Ip' -Default (Get-MetraProp -Object $matched -Name 'lastIp' -Default '')) }
        $updated = [PSCustomObject]@{
            deviceId     = [string](Get-MetraProp -Object $matched -Name 'deviceId' -Default '')
            label        = [string](Get-MetraProp -Object $matched -Name 'label' -Default '')
            login        = [string](Get-MetraProp -Object $matched -Name 'login' -Default '')
            node         = [string](Get-MetraProp -Object $matched -Name 'node' -Default '')
            tags         = @(Get-MetraProp -Object $matched -Name 'tags' -Default @())
            tokenHash    = [string](Get-MetraProp -Object $matched -Name 'tokenHash' -Default '')
            issuedUtc    = [string](Get-MetraProp -Object $matched -Name 'issuedUtc' -Default '')
            revokedUtc   = $null
            lastSeenUtc  = [datetime]::UtcNow.ToString('o')
            lastIp       = $ip
            lastIdentity = [PSCustomObject]@{
                login = $login
                node  = $node
                tags  = @($tags)
            }
        }
        $devices = @($ledger.Devices)
        $devices[$matchedIndex] = $updated
        $null = Save-MetraClientDevicesLedger -Devices $devices -DataDir $DataDir
    }
    return $true
}

function Revoke-MetraClientDeviceToken {
    <#
    .SYNOPSIS
        Revokes one device by id. Does not remove the row (audit / last-seen retained).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DeviceId,
        [string]$DataDir
    )

    $id = $DeviceId.Trim()
    $ledger = Get-MetraClientDevicesLedger -DataDir $DataDir
    $found = $false
    $devices = @()
    foreach ($d in @($ledger.Devices)) {
        $did = [string](Get-MetraProp -Object $d -Name 'deviceId' -Default '')
        if ($did -eq $id) {
            $found = $true
            $devices += [PSCustomObject]@{
                deviceId     = $did
                label        = [string](Get-MetraProp -Object $d -Name 'label' -Default '')
                login        = [string](Get-MetraProp -Object $d -Name 'login' -Default '')
                node         = [string](Get-MetraProp -Object $d -Name 'node' -Default '')
                tags         = @(Get-MetraProp -Object $d -Name 'tags' -Default @())
                tokenHash    = [string](Get-MetraProp -Object $d -Name 'tokenHash' -Default '')
                issuedUtc    = [string](Get-MetraProp -Object $d -Name 'issuedUtc' -Default '')
                revokedUtc   = [datetime]::UtcNow.ToString('o')
                lastSeenUtc  = Get-MetraProp -Object $d -Name 'lastSeenUtc' -Default $null
                lastIp       = Get-MetraProp -Object $d -Name 'lastIp' -Default $null
                lastIdentity = Get-MetraProp -Object $d -Name 'lastIdentity' -Default $null
            }
        }
        else {
            $devices += $d
        }
    }
    if (-not $found) {
        return [PSCustomObject]@{ Ok = $false; DeviceId = $id; Message = 'Device not found.' }
    }
    $null = Save-MetraClientDevicesLedger -Devices $devices -DataDir $DataDir
    return [PSCustomObject]@{ Ok = $true; DeviceId = $id; Message = 'Device revoked.' }
}

function Get-MetraClientDeviceList {
    param(
        [string]$DataDir,
        [switch]$IncludeRevoked
    )

    $ledger = Get-MetraClientDevicesLedger -DataDir $DataDir
    $out = @()
    foreach ($d in @($ledger.Devices)) {
        $revoked = [string](Get-MetraProp -Object $d -Name 'revokedUtc' -Default '')
        if (-not $IncludeRevoked -and -not [string]::IsNullOrWhiteSpace($revoked)) {
            continue
        }
        $out += [PSCustomObject]@{
            deviceId     = [string](Get-MetraProp -Object $d -Name 'deviceId' -Default '')
            label        = [string](Get-MetraProp -Object $d -Name 'label' -Default '')
            login        = [string](Get-MetraProp -Object $d -Name 'login' -Default '')
            node         = [string](Get-MetraProp -Object $d -Name 'node' -Default '')
            tags         = @(Get-MetraProp -Object $d -Name 'tags' -Default @())
            issuedUtc    = [string](Get-MetraProp -Object $d -Name 'issuedUtc' -Default '')
            revokedUtc   = $(if ($revoked) { $revoked } else { $null })
            lastSeenUtc  = Get-MetraProp -Object $d -Name 'lastSeenUtc' -Default $null
            lastIp       = Get-MetraProp -Object $d -Name 'lastIp' -Default $null
            lastIdentity = Get-MetraProp -Object $d -Name 'lastIdentity' -Default $null
            active       = [string]::IsNullOrWhiteSpace($revoked)
        }
    }
    return @($out)
}

function Get-MetraClientPairPending {
    param([string]$DataDir)

    $path = Get-MetraClientPairPendingPath -DataDir $DataDir
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{ Path = $path; Requests = @() }
    }
    try {
        $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        return [PSCustomObject]@{
            Path     = $path
            Requests = @(Get-MetraProp -Object $data -Name 'requests' -Default @())
        }
    }
    catch {
        return [PSCustomObject]@{ Path = $path; Requests = @() }
    }
}

function Save-MetraClientPairPending {
    param(
        [AllowEmptyCollection()]
        [object[]]$Requests = @(),
        [string]$DataDir
    )

    $path = Get-MetraClientPairPendingPath -DataDir $DataDir
    $payload = [ordered]@{
        schemaVersion = 1
        requests      = @($Requests)
    }
    Write-MetraProfileAtomicText -Path $path -Text ((($payload | ConvertTo-Json -Depth 8)) + "`n")
    return $path
}

function Add-MetraClientAuthAllowlistEntry {
    <#
    .SYNOPSIS
        Ensures a login/node allowlist row exists in client-auth.local.json (approve path).
    .DESCRIPTION
        Writes a single-criterion row when only one of login/node is set. When both are set,
        stores one conjunctive row (login AND node must match).
    #>
    [CmdletBinding()]
    param(
        [string]$Login = '',
        [string]$Node = '',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $path = Get-MetraClientAuthConfigPath -MetraRoot $MetraRoot
    $cfg = Get-MetraClientAuthConfig -MetraRoot $MetraRoot
    $entries = @($cfg.Allowlist)
    $login = $Login.Trim()
    $node = $Node.Trim().TrimEnd('.')
    if (-not $login -and -not $node) {
        return [PSCustomObject]@{ Ok = $false; Path = $path; Added = $false; Message = 'login or node required' }
    }
    foreach ($e in $entries) {
        $sameLogin = (-not $login -and -not $e.login) -or (
            $login -and $e.login -and $e.login.Equals($login, [StringComparison]::OrdinalIgnoreCase))
        $sameNode = (-not $node -and -not $e.node) -or (
            $node -and $e.node -and $e.node.Equals($node, [StringComparison]::OrdinalIgnoreCase))
        if ($sameLogin -and $sameNode -and [string]::IsNullOrWhiteSpace([string]$e.tag)) {
            return [PSCustomObject]@{ Ok = $true; Path = $path; Added = $false }
        }
    }
    $entries += [PSCustomObject]@{
        login = $login
        node  = $node
        tag   = ''
    }
    $payload = [ordered]@{
        schemaVersion = 1
        allowlist     = @($entries)
    }
    Write-MetraProfileAtomicText -Path $path -Text ((($payload | ConvertTo-Json -Depth 6)) + "`n")
    return [PSCustomObject]@{ Ok = $true; Path = $path; Added = $true }
}

function Invoke-MetraClientPairRequest {
    <#
    .SYNOPSIS
        First Tailscale-proven pair: auto-mint device token or queue pending approve.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [string]$Label = '',
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$DataDir,
        [scriptblock]$WhoIsCommand,
        [scriptblock]$StatusCommand
    )

    $idParams = @{ Request = $Request }
    if ($WhoIsCommand) { $idParams.WhoIsCommand = $WhoIsCommand }
    $identity = Get-MetraOpsRequestPeerIdentity @idParams
    if ($null -eq $identity -or (
            [string]::IsNullOrWhiteSpace([string]$identity.Login) -and
            [string]::IsNullOrWhiteSpace([string]$identity.Node))) {
        return [PSCustomObject]@{
            Ok         = $false
            Pending    = $false
            ReasonCode = 'peerIdentityRequired'
            Message    = 'Could not resolve Tailscale peer identity for this request.'
        }
    }

    $auto = Test-MetraClientIdentityPairAutoAccept -Identity $identity -MetraRoot $MetraRoot -StatusCommand $StatusCommand
    if ($auto) {
        # Persist Self-login (or allowlisted) identity so later allowlist files do not strand the device.
        $persistLogin = [string]$identity.Login
        $persistNode = ''
        if ([string]::IsNullOrWhiteSpace($persistLogin)) {
            $persistNode = [string]$identity.Node
        }
        $null = Add-MetraClientAuthAllowlistEntry -Login $persistLogin -Node $persistNode -MetraRoot $MetraRoot
        $minted = New-MetraClientDeviceToken -Identity $identity -Label $Label -DataDir $DataDir
        return [PSCustomObject]@{
            Ok        = $true
            Pending   = $false
            Accepted  = $true
            DeviceId  = $minted.DeviceId
            Label     = $minted.Label
            Token     = $minted.Token
            Header    = $minted.Header
            Identity  = $identity
            Message   = $minted.Message
        }
    }

    $pending = Get-MetraClientPairPending -DataDir $DataDir
    $loginKey = [string]$identity.Login
    $nodeKey = [string]$identity.Node
    foreach ($existing in @($pending.Requests)) {
        $exLogin = [string](Get-MetraProp -Object $existing -Name 'login' -Default '')
        $exNode = [string](Get-MetraProp -Object $existing -Name 'node' -Default '')
        if (-not $loginKey -and -not $nodeKey) { continue }
        $sameLogin = $loginKey.Equals($exLogin, [StringComparison]::OrdinalIgnoreCase)
        $sameNode = $nodeKey.Equals($exNode, [StringComparison]::OrdinalIgnoreCase)
        # Same peer identity tuple only - distinct devices for one login stay separate.
        if ($sameLogin -and $sameNode) {
            return [PSCustomObject]@{
                Ok         = $true
                Pending    = $true
                Accepted   = $false
                RequestId  = [string](Get-MetraProp -Object $existing -Name 'requestId' -Default '')
                Identity   = $identity
                Message    = 'Pairing already pending operator approve on Ops desk (local authority).'
                ReasonCode = 'pairPendingApprove'
            }
        }
    }
    $requestId = [guid]::NewGuid().ToString('N')
    $row = [PSCustomObject]@{
        requestId   = $requestId
        createdUtc  = [datetime]::UtcNow.ToString('o')
        label       = $Label
        login       = $loginKey
        node        = $nodeKey
        tags        = @($identity.Tags)
        ip          = [string]$identity.Ip
        status      = 'pending'
    }
    $null = Save-MetraClientPairPending -Requests (@($pending.Requests) + @($row)) -DataDir $DataDir
    return [PSCustomObject]@{
        Ok         = $true
        Pending    = $true
        Accepted   = $false
        RequestId  = $requestId
        Identity   = $identity
        Message    = 'Pairing pending operator approve on Ops desk (local authority).'
        ReasonCode = 'pairPendingApprove'
    }
}

function Approve-MetraClientPairRequest {
    <#
    .SYNOPSIS
        Approves a pending pair: adds allowlist entry and mints device token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$DataDir
    )

    $id = $RequestId.Trim()
    $pending = Get-MetraClientPairPending -DataDir $DataDir
    $row = $null
    $rest = @()
    foreach ($r in @($pending.Requests)) {
        $rid = [string](Get-MetraProp -Object $r -Name 'requestId' -Default '')
        if ($rid -eq $id) {
            $row = $r
        }
        else {
            $rest += $r
        }
    }
    if ($null -eq $row) {
        return [PSCustomObject]@{ Ok = $false; Message = 'Pending pair request not found.'; ReasonCode = 'pairNotFound' }
    }

    $login = [string](Get-MetraProp -Object $row -Name 'login' -Default '')
    $node = [string](Get-MetraProp -Object $row -Name 'node' -Default '')
    # Single-criterion allowlist (login preferred) so Serve peers that only forward login still match.
    $persistLogin = $login
    $persistNode = ''
    if ([string]::IsNullOrWhiteSpace($persistLogin)) {
        $persistNode = $node
    }
    $null = Add-MetraClientAuthAllowlistEntry -Login $persistLogin -Node $persistNode -MetraRoot $MetraRoot
    $identity = ConvertTo-MetraPeerIdentityRecord `
        -Login $login `
        -Node $node `
        -Tags (Get-MetraProp -Object $row -Name 'tags' -Default @()) `
        -Source 'pair-approve' `
        -Ip ([string](Get-MetraProp -Object $row -Name 'ip' -Default ''))
    $label = [string](Get-MetraProp -Object $row -Name 'label' -Default '')
    $minted = New-MetraClientDeviceToken -Identity $identity -Label $label -DataDir $DataDir
    $null = Save-MetraClientPairPending -Requests $rest -DataDir $DataDir

    return [PSCustomObject]@{
        Ok       = $true
        DeviceId = $minted.DeviceId
        Label    = $minted.Label
        Token    = $minted.Token
        Header   = $minted.Header
        Identity = $identity
        Message  = $minted.Message
    }
}

function Test-MetraOpsProfileSyncRemoteCapability {
    <#
    .SYNOPSIS
        Remote sync capability: legacy break-glass token alone, or device token (+ WhoIs when allowlist configured).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$DataDir,
        [scriptblock]$WhoIsCommand
    )

    $syncToken = ''
    try { $syncToken = [string]$Request.Headers['X-Metra-Profile-Sync'] } catch { }
    if ([string]::IsNullOrWhiteSpace($syncToken)) {
        return $false
    }

    # Break-glass: legacy HQ sync hash authorizes without WhoIs.
    if (Test-MetraProfileSyncToken -SyncToken $syncToken -DataDir $DataDir) {
        return $true
    }

    $idParams = @{ Request = $Request }
    if ($WhoIsCommand) { $idParams.WhoIsCommand = $WhoIsCommand }
    $identity = Get-MetraOpsRequestPeerIdentity @idParams
    $clientIp = Get-MetraOpsRequestClientIp -Request $Request
    # Validate without touching lastSeen until identity is allowed.
    if (-not (Test-MetraClientDeviceToken -Token $syncToken -DataDir $DataDir -NoTouch)) {
        return $false
    }

    if ((Test-MetraClientAuthAllowlistConfigured -MetraRoot $MetraRoot) -and
        -not (Test-MetraClientIdentityAllowed -Identity $identity -MetraRoot $MetraRoot)) {
        return $false
    }

    $null = Test-MetraClientDeviceToken -Token $syncToken -DataDir $DataDir `
        -ClientIp $(if ($clientIp) { $clientIp } else { '' }) -Identity $identity
    return $true
}

function Test-MetraOpsRemoteAskIdentityAllowed {
    <#
    .SYNOPSIS
        Remote Ask gate: when allowlist configured, require allowlisted WhoIs/Serve identity.
    .DESCRIPTION
        Callers with local authority should skip this. Empty allowlist = transitional open.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [string]$MetraRoot = (Get-MetraRoot),
        [scriptblock]$WhoIsCommand
    )

    if (-not (Test-MetraClientAuthAllowlistConfigured -MetraRoot $MetraRoot)) {
        return $true
    }
    $idParams = @{ Request = $Request }
    if ($WhoIsCommand) { $idParams.WhoIsCommand = $WhoIsCommand }
    $identity = Get-MetraOpsRequestPeerIdentity @idParams
    return [bool](Test-MetraClientIdentityAllowed -Identity $identity -MetraRoot $MetraRoot)
}

function Invoke-MetraProfileClientPair {
    <#
    .SYNOPSIS
        Satellite-side: POST /api/profile/pair and store returned device token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OpsBaseUrl,
        [string]$Label = '',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $base = $OpsBaseUrl.Trim().TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($Label)) {
        $Label = [System.Environment]::MachineName
    }
    $body = @{ label = $Label } | ConvertTo-Json -Compress
    $uri = "$base/api/profile/pair"
    try {
        $resp = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 30 -ErrorAction Stop
    }
    catch {
        throw "Profile pair failed at $uri : $($_.Exception.Message)"
    }

    $pending = [bool](Get-MetraProp -Object $resp -Name 'pending' -Default $false)
    if ($pending) {
        return [PSCustomObject]@{
            Ok        = $false
            Pending   = $true
            RequestId = [string](Get-MetraProp -Object $resp -Name 'requestId' -Default '')
            Message   = [string](Get-MetraProp -Object $resp -Name 'message' -Default 'Pairing pending Ops approve.')
            OpsBaseUrl = $base
        }
    }

    $token = [string](Get-MetraProp -Object $resp -Name 'token' -Default '')
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw 'Profile pair response did not include a device token.'
    }
    $null = Set-MetraProfileSyncClientToken -SyncToken $token -MetraRoot $MetraRoot
    $state = Get-MetraProfileSyncLocalState -MetraRoot $MetraRoot
    $data = if ($state.Data) { $state.Data } else { [PSCustomObject]@{} }
    $hash = @{ }
    foreach ($p in @($data.PSObject.Properties)) {
        $hash[$p.Name] = $p.Value
    }
    $hash['opsBaseUrl'] = $base
    $hash['syncToken'] = $token
    $hash['deviceId'] = [string](Get-MetraProp -Object $resp -Name 'deviceId' -Default '')
    $hash['pairedUtc'] = [datetime]::UtcNow.ToString('o')
    $null = Save-MetraProfileSyncLocalState -State $hash -MetraRoot $MetraRoot

    return [PSCustomObject]@{
        Ok         = $true
        Pending    = $false
        DeviceId   = [string](Get-MetraProp -Object $resp -Name 'deviceId' -Default '')
        OpsBaseUrl = $base
        Message    = 'Paired; device token stored in docs/profile-sync.local.json.'
    }
}
