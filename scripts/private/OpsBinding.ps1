# Ops desk URL binding: prefer http://metra/ on port 80 when free; else 127.0.0.1:7380.
# BrowserUrl / ShareUrl may be reachable by peers (Tailscale / friendly).
# OperatorUrl must remain loopback because local-session authority and tray Apply are local-only.
# When Tailscale binding is enabled, BrowserUrl prefers Tailscale reachability even if friendly
# host reservations exist (friendly prefixes may still be added as listeners).

$script:MetraOpsFallbackPort = 7380
$script:MetraOpsFriendlyHost = 'metra'
$script:MetraOpsFriendlyPort = 80

function Get-MetraOpsFallbackPort {
    return [int]$script:MetraOpsFallbackPort
}

function Test-MetraIPv4Address {
    <#
    .SYNOPSIS
        True when Address is a parseable IPv4 address (not merely dotted-digit shape).
    #>
    [CmdletBinding()]
    param([string]$Address)

    if ([string]::IsNullOrWhiteSpace($Address)) { return $false }

    $parsed = [System.Net.IPAddress]::None
    if (-not [System.Net.IPAddress]::TryParse($Address.Trim(), [ref]$parsed)) {
        return $false
    }

    return $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
}

function Test-MetraFriendlyHostName {
    <#
    .SYNOPSIS
        True when Name is a safe single-label hostname for hosts / URL ACL use.
    #>
    [CmdletBinding()]
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $n = $Name.Trim()
    # Single label, max 63, no leading/trailing hyphen (rejects -metra / metra-).
    return (
        $n.Length -le 63 -and
        $n -match '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$'
    )
}

function Assert-MetraOpsBindPort {
    param(
        [Parameter(Mandatory)][int]$Port,
        [string]$Label = 'port'
    )

    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "Invalid ${Label}: $Port"
    }
}

function Get-MetraOpsTailscaleIPv4 {
    <#
    .SYNOPSIS
        Best-effort Tailscale IPv4 for the local machine (CLI or interface alias).
    #>
    [CmdletBinding()]
    param()

    $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            $raw = & tailscale ip -4 2>$null | Select-Object -First 1
            $ip = ([string]$raw).Trim()
            if (Test-MetraIPv4Address -Address $ip) {
                return $ip
            }
        }
        catch { }
    }

    try {
        $hit = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.InterfaceAlias -match 'Tailscale' -and
                $_.IPAddress -notlike '169.254*' -and
                $_.IPAddress -ne '127.0.0.1'
            } |
            Select-Object -First 1)
        if ($hit.Count -gt 0 -and (Test-MetraIPv4Address -Address $hit[0].IPAddress)) {
            return [string]$hit[0].IPAddress
        }
    }
    catch { }

    return $null
}

function Get-MetraOpsTailscaleDnsName {
    <#
    .SYNOPSIS
        Best-effort MagicDNS name for this machine (trailing dot stripped).
    #>
    [CmdletBinding()]
    param()

    $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }

    try {
        $raw = & tailscale status --json 2>$null | Out-String
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        try {
            $status = $raw | ConvertFrom-Json
        }
        catch {
            return $null
        }
        $dns = [string](Get-MetraProp -Object $status.Self -Name 'DNSName' -Default '')
        $dns = $dns.Trim().TrimEnd('.')
        if ($dns -match '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$' -and $dns -match '\.') {
            return $dns.ToLowerInvariant()
        }
    }
    catch { }

    return $null
}

function Get-MetraOpsTailscaleBinding {
    <#
    .SYNOPSIS
        Bind loopback (+ Tailscale reach) for view/ask. Prefer HTTPS ShareUrl when Serve fronts Ops.
    .DESCRIPTION
        Not anonymous apply authority. When ServeHttpsUrl is set, HttpListener stays on loopback
        (Serve terminates HTTPS). Otherwise listen on loopback + Tailscale IPv4 + MagicDNS http.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Address,
        [int]$Port = $(Get-MetraOpsFallbackPort),
        [string]$DnsName = '',
        [string]$ServeHttpsUrl = '',
        [string]$ServeError = ''
    )

    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "Invalid Tailscale Ops port: $Port"
    }

    $addr = ([string]$Address).Trim()
    if (-not (Test-MetraIPv4Address -Address $addr)) {
        throw "Invalid Tailscale IPv4 address: $Address"
    }

    $dns = ([string]$DnsName).Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($dns)) {
        try { $dns = [string](Get-MetraOpsTailscaleDnsName) } catch { $dns = '' }
    }
    if (-not [string]::IsNullOrWhiteSpace($dns)) {
        $dns = $dns.ToLowerInvariant()
    }

    $serveUrl = ([string]$ServeHttpsUrl).Trim()
    $useServe = $serveUrl -match '^https://'
    $shareHost = if (-not [string]::IsNullOrWhiteSpace($dns)) { $dns } else { $addr }

    $prefixes = [System.Collections.Generic.List[string]]::new()
    $null = $prefixes.Add("http://127.0.0.1:$Port/")

    # OperatorUrl stays loopback - never Tailscale / Serve (local-session + tray Apply).
    $operatorUrl = if ($Port -eq 80) { 'http://127.0.0.1/' } else { "http://127.0.0.1:$Port/" }

    if ($useServe) {
        $browserUrl = if ($serveUrl.EndsWith('/')) { $serveUrl } else { "$serveUrl/" }
        return [PSCustomObject]@{
            Port             = $Port
            BrowserHost      = $shareHost
            BrowserUrl       = $browserUrl
            ShareUrl         = $browserUrl
            OperatorUrl      = $operatorUrl
            TailscaleIp      = $addr
            DnsName          = $(if ([string]::IsNullOrWhiteSpace($dns)) { $null } else { $dns })
            ListenerPrefixes = @($prefixes)
            Friendly         = (-not [string]::IsNullOrWhiteSpace($dns))
            Tailscale        = $true
            Serve            = $true
            ServeError       = $null
            Reason           = 'tailscale-serve-https'
        }
    }

    $browserUrl = if ($Port -eq 80) { "http://${shareHost}/" } else { "http://${shareHost}:$Port/" }
    $null = $prefixes.Add("http://${addr}:$Port/")
    if (-not [string]::IsNullOrWhiteSpace($dns) -and $dns -ne $addr) {
        $dnsPrefix = "http://${dns}:$Port/"
        if (-not $prefixes.Contains($dnsPrefix)) {
            $null = $prefixes.Add($dnsPrefix)
        }
    }

    return [PSCustomObject]@{
        Port             = $Port
        BrowserHost      = $shareHost
        BrowserUrl       = $browserUrl
        ShareUrl         = $browserUrl
        OperatorUrl      = $operatorUrl
        TailscaleIp      = $addr
        DnsName          = $(if ([string]::IsNullOrWhiteSpace($dns)) { $null } else { $dns })
        ListenerPrefixes = @($prefixes)
        Friendly         = (-not [string]::IsNullOrWhiteSpace($dns))
        Tailscale        = $true
        Serve            = $false
        ServeError       = $(if ([string]::IsNullOrWhiteSpace($ServeError)) { $null } else { $ServeError })
        Reason           = 'tailscale-bind'
    }
}

function Enable-MetraOpsTailscaleBinding {
    <#
    .SYNOPSIS
        Ensures URL ACL for Tailscale prefixes (may need elevation) and returns binding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Address,
        [int]$Port = $(Get-MetraOpsFallbackPort),
        [string]$DnsName = ''
    )

    $binding = Get-MetraOpsTailscaleBinding -Address $Address -Port $Port -DnsName $DnsName
    foreach ($prefix in @($binding.ListenerPrefixes)) {
        if ($prefix -notmatch '^http://') { continue }
        if (Test-MetraHttpUrlAcl -Prefix $prefix) { continue }
        $acl = Add-MetraHttpUrlAcl -Prefix $prefix
        if (-not $acl.Ok) {
            return [PSCustomObject]@{
                Ok      = $false
                Binding = $binding
                Error   = "Could not reserve $prefix ($($acl.Error)). Run elevated once for URL ACL."
            }
        }
    }
    return [PSCustomObject]@{
        Ok      = $true
        Binding = $binding
        Error   = $null
    }
}

function Get-MetraOpsHostsFilePath {
    return Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
}

function Test-MetraTcpPortFree {
    <#
    .SYNOPSIS
        True when nothing is listening on the TCP port (best-effort).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Port)

    if ($Port -lt 1 -or $Port -gt 65535) { return $false }
    try {
        $hits = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
        return ($hits.Count -eq 0)
    }
    catch {
        return $true
    }
}

function Test-MetraHostsEntry {
    <#
    .SYNOPSIS
        True when hosts maps the name to the given address (comment lines ignored).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [string]$Address = '127.0.0.1'
    )

    if (-not (Test-MetraFriendlyHostName -Name $HostName)) { return $false }

    $path = Get-MetraOpsHostsFilePath
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $pattern = "^\s*$([regex]::Escape($Address))\s+$([regex]::Escape($HostName.Trim()))(\s|$)"
    foreach ($line in Get-Content -LiteralPath $path -ErrorAction SilentlyContinue) {
        if ($line -match '^\s*#') { continue }
        if ($line -match $pattern) { return $true }
    }
    return $false
}

function Add-MetraHostsEntry {
    <#
    .SYNOPSIS
        Ensures hosts has Address HostName. May require elevation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [string]$Address = '127.0.0.1'
    )

    if (-not (Test-MetraFriendlyHostName -Name $HostName)) {
        return [PSCustomObject]@{ Ok = $false; Changed = $false; Error = "Invalid hostname: $HostName" }
    }
    $HostName = $HostName.Trim()

    if (Test-MetraHostsEntry -HostName $HostName -Address $Address) {
        return [PSCustomObject]@{ Ok = $true; Changed = $false; Error = $null }
    }

    $path = Get-MetraOpsHostsFilePath
    $line = "$Address $HostName"
    try {
        Add-Content -LiteralPath $path -Value $line -Encoding ascii -ErrorAction Stop
        if (Test-MetraHostsEntry -HostName $HostName -Address $Address) {
            return [PSCustomObject]@{ Ok = $true; Changed = $true; Error = $null }
        }
        return [PSCustomObject]@{ Ok = $false; Changed = $false; Error = 'Hosts write did not stick.' }
    }
    catch {
        return [PSCustomObject]@{ Ok = $false; Changed = $false; Error = $_.Exception.Message }
    }
}

function Test-MetraHttpUrlAcl {
    <#
    .SYNOPSIS
        True when netsh lists a reserved URL that covers the prefix.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Prefix)

    $url = ([string]$Prefix).Trim()
    if (-not $url.EndsWith('/')) { $url += '/' }

    $uri = $null
    if (-not [System.Uri]::TryCreate($url, [System.UriKind]::Absolute, [ref]$uri)) {
        return $false
    }

    $norm = $uri.AbsoluteUri.TrimEnd('/').ToLowerInvariant() + '/'
    $wildcard = "http://+:$($uri.Port)/"

    try {
        $raw = netsh http show urlacl | Out-String
    }
    catch {
        return $false
    }

    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -match 'Reserved URL\s+:\s+(\S+)') {
            $reserved = $Matches[1].Trim().ToLowerInvariant()
            if (-not $reserved.EndsWith('/')) { $reserved += '/' }

            if ($reserved -eq $norm) { return $true }
            if ($reserved -eq $wildcard) { return $true }
        }
    }

    return $false
}

function Add-MetraHttpUrlAcl {
    <#
    .SYNOPSIS
        Reserves an HTTP.sys URL for the current user. May require elevation.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Prefix)

    $url = $Prefix
    if (-not $url.EndsWith('/')) { $url += '/' }
    if (Test-MetraHttpUrlAcl -Prefix $url) {
        return [PSCustomObject]@{ Ok = $true; Changed = $false; Error = $null }
    }

    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    try {
        $output = & netsh.exe http add urlacl url=$url user=$user 2>&1 | Out-String
        if (Test-MetraHttpUrlAcl -Prefix $url) {
            return [PSCustomObject]@{ Ok = $true; Changed = $true; Error = $null }
        }
        return [PSCustomObject]@{ Ok = $false; Changed = $false; Error = ($output.Trim()) }
    }
    catch {
        return [PSCustomObject]@{ Ok = $false; Changed = $false; Error = $_.Exception.Message }
    }
}

function Get-MetraOpsLoopbackBinding {
    param([int]$Port = $(Get-MetraOpsFallbackPort))

    Assert-MetraOpsBindPort -Port $Port -Label 'loopback Ops port'
    $prefixes = @("http://127.0.0.1:$Port/")
    $browserUrl = if ($Port -eq 80) { 'http://127.0.0.1/' } else { "http://127.0.0.1:$Port/" }
    return [PSCustomObject]@{
        Port             = $Port
        BrowserHost      = '127.0.0.1'
        BrowserUrl       = $browserUrl
        ShareUrl         = $browserUrl
        OperatorUrl      = $browserUrl
        ListenerPrefixes = $prefixes
        Friendly         = $false
        Reason           = 'loopback-fallback'
    }
}

function Get-MetraOpsFriendlyBinding {
    param(
        [string]$HostName = $script:MetraOpsFriendlyHost,
        [int]$Port = $script:MetraOpsFriendlyPort
    )

    if (-not (Test-MetraFriendlyHostName -Name $HostName)) {
        throw "Invalid hostname: $HostName"
    }
    Assert-MetraOpsBindPort -Port $Port -Label 'friendly Ops port'
    $HostName = $HostName.Trim()

    $prefixes = @(
        "http://127.0.0.1:$Port/"
        "http://${HostName}:$Port/"
    )
    $browserUrl = if ($Port -eq 80) { "http://${HostName}/" } else { "http://${HostName}:$Port/" }
    $operatorUrl = if ($Port -eq 80) { 'http://127.0.0.1/' } else { "http://127.0.0.1:$Port/" }
    return [PSCustomObject]@{
        Port             = $Port
        BrowserHost      = $HostName
        BrowserUrl       = $browserUrl
        ShareUrl         = $browserUrl
        OperatorUrl      = $operatorUrl
        ListenerPrefixes = $prefixes
        Friendly         = $true
        Reason           = 'friendly-hostname'
    }
}

function Get-MetraOpsOperatorOpenUrl {
    <#
    .SYNOPSIS
        Loopback URL Host/Ops open for local Settings, Save role, and issue-sync-token.
    .DESCRIPTION
        Share/Tailscale BrowserUrl stays for peers. Local Host open must use OperatorUrl so
        /api/local-session works (Serve strips loopback authority).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Binding
    )

    $explicit = ''
    try { $explicit = [string](Get-MetraProp -Object $Binding -Name 'OperatorUrl' -Default '') } catch { }
    if (-not [string]::IsNullOrWhiteSpace($explicit)) {
        return $explicit.Trim()
    }

    $port = 0
    try { $port = [int](Get-MetraProp -Object $Binding -Name 'Port' -Default 0) } catch { }
    if ($port -le 0) { $port = Get-MetraOpsFallbackPort }
    if ($port -eq 80) { return 'http://127.0.0.1/' }
    return "http://127.0.0.1:$port/"
}

function Get-MetraOpsDeskUrl {
    <#
    .SYNOPSIS
        Browser URL for the current Ops desk binding.
    #>
    [CmdletBinding()]
    param(
        [object]$Binding = $null,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if (-not $Binding) {
        $Binding = Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot
    }
    return [string]$Binding.BrowserUrl
}

function Install-MetraOpsFriendlyUrlReservation {
    <#
    .SYNOPSIS
        One-shot elevated hosts + URL ACL for http://metra/ (port 80).
    .DESCRIPTION
        Prompts UAC. Safe to re-run. Does not start the desk.
        HostName and Port are validated before the elevated helper is generated.
    #>
    [CmdletBinding()]
    param(
        [string]$HostName = 'metra',
        [int]$Port = 80
    )

    if (-not (Test-MetraFriendlyHostName -Name $HostName)) {
        throw "Invalid hostname: $HostName"
    }
    Assert-MetraOpsBindPort -Port $Port -Label 'port'
    $HostName = $HostName.Trim()

    $helper = Join-Path $env:TEMP ("metra-friendly-url-" + [guid]::NewGuid().ToString('n') + '.ps1')
    $okFile = Join-Path $env:TEMP ("metra-friendly-url-ok-" + [guid]::NewGuid().ToString('n') + '.txt')
    $script = @"
`$ErrorActionPreference = 'Stop'
`$hostsPath = Join-Path `$env:SystemRoot 'System32\drivers\etc\hosts'
`$entry = '127.0.0.1 $HostName'
`$pattern = '^\s*127\.0\.0\.1\s+$HostName(\s|`$)'
if (-not (Select-String -LiteralPath `$hostsPath -Pattern `$pattern -Quiet)) {
    Add-Content -LiteralPath `$hostsPath -Value `$entry -Encoding ascii
}
`$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach (`$url in @('http://127.0.0.1:$Port/','http://${HostName}:$Port/')) {
    `$listed = (netsh http show urlacl) | Out-String
    if (`$listed -notmatch [regex]::Escape(`$url)) {
        netsh http add urlacl url=`$url user=`$user | Out-Null
    }
}
Set-Content -LiteralPath '$okFile' -Value 'ok' -Encoding ascii
"@
    Set-Content -LiteralPath $helper -Value $script -Encoding UTF8
    try {
        $p = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $helper) `
            -Verb RunAs -PassThru -Wait -WindowStyle Hidden
        if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $okFile)) {
            return [PSCustomObject]@{ Ok = $false; Error = 'Elevation cancelled or reservation failed.' }
        }
        return [PSCustomObject]@{ Ok = $true; Error = $null }
    }
    catch {
        return [PSCustomObject]@{ Ok = $false; Error = $_.Exception.Message }
    }
    finally {
        Remove-Item -LiteralPath $helper, $okFile -Force -ErrorAction SilentlyContinue
    }
}

function Enable-MetraOpsFriendlyBinding {
    <#
    .SYNOPSIS
        Tries hosts + URL ACL for http://metra/ (port 80). Falls back object on failure.
    #>
    [CmdletBinding()]
    param(
        [string]$HostName = $script:MetraOpsFriendlyHost,
        [int]$Port = $script:MetraOpsFriendlyPort,
        [switch]$AllowElevation
    )

    if (-not (Test-MetraFriendlyHostName -Name $HostName)) {
        return [PSCustomObject]@{
            Ok      = $false
            Binding = (Get-MetraOpsLoopbackBinding -Port (Get-MetraOpsFallbackPort))
            Error   = "Invalid hostname: $HostName"
        }
    }
    if ($Port -lt 1 -or $Port -gt 65535) {
        return [PSCustomObject]@{
            Ok      = $false
            Binding = (Get-MetraOpsLoopbackBinding -Port (Get-MetraOpsFallbackPort))
            Error   = "Invalid port: $Port"
        }
    }
    $HostName = $HostName.Trim()

    if (-not (Test-MetraTcpPortFree -Port $Port)) {
        return [PSCustomObject]@{
            Ok      = $false
            Binding = (Get-MetraOpsLoopbackBinding -Port (Get-MetraOpsFallbackPort))
            Error   = "Port $Port is already in use."
        }
    }

    $hosts = Add-MetraHostsEntry -HostName $HostName -Address '127.0.0.1'
    if (-not $hosts.Ok) {
        if ($AllowElevation) {
            $elev = Install-MetraOpsFriendlyUrlReservation -HostName $HostName -Port $Port
            if ($elev.Ok) {
                $hosts = [PSCustomObject]@{ Ok = $true; Changed = $true; Error = $null }
            }
            else {
                return [PSCustomObject]@{
                    Ok      = $false
                    Binding = (Get-MetraOpsLoopbackBinding -Port (Get-MetraOpsFallbackPort))
                    Error   = "Could not update hosts/URL ACL ($($elev.Error)). Use port $(Get-MetraOpsFallbackPort)."
                }
            }
        }
        else {
            return [PSCustomObject]@{
                Ok      = $false
                Binding = (Get-MetraOpsLoopbackBinding -Port (Get-MetraOpsFallbackPort))
                Error   = "Could not update hosts file ($($hosts.Error)). Run elevated once, or use port $(Get-MetraOpsFallbackPort)."
            }
        }
    }

    $prefixes = @(
        "http://127.0.0.1:$Port/"
        "http://${HostName}:$Port/"
    )
    foreach ($prefix in $prefixes) {
        $acl = Add-MetraHttpUrlAcl -Prefix $prefix
        if (-not $acl.Ok) {
            if ($AllowElevation) {
                $elev = Install-MetraOpsFriendlyUrlReservation -HostName $HostName -Port $Port
                if (-not $elev.Ok -or -not (Test-MetraHttpUrlAcl -Prefix $prefix)) {
                    return [PSCustomObject]@{
                        Ok      = $false
                        Binding = (Get-MetraOpsLoopbackBinding -Port (Get-MetraOpsFallbackPort))
                        Error   = "Could not reserve $prefix ($($acl.Error)). Use port $(Get-MetraOpsFallbackPort)."
                    }
                }
            }
            else {
                return [PSCustomObject]@{
                    Ok      = $false
                    Binding = (Get-MetraOpsLoopbackBinding -Port (Get-MetraOpsFallbackPort))
                    Error   = "Could not reserve $prefix ($($acl.Error)). Run elevated once, or use port $(Get-MetraOpsFallbackPort)."
                }
            }
        }
    }

    return [PSCustomObject]@{
        Ok      = $true
        Binding = (Get-MetraOpsFriendlyBinding -HostName $HostName -Port $Port)
        Error   = $null
    }
}

function Resolve-MetraOpsDeskBinding {
    <#
    .SYNOPSIS
        Resolves Ops desk port and browser URL from prefs (or safe 7380 fallback).
    .DESCRIPTION
        Does not mutate the system. Use Initialize-MetraOpsDeskBinding to choose and persist.
        Explicit CLI -Port overrides by callers before using this result.
        When bindTailscale is set and a Tailscale IP is available, BrowserUrl prefers Tailscale
        reachability even if friendly host reservations exist. Friendly http://metra/ listening
        is restored separately via Get-MetraOpsDeskBindingForPort when those ACLs are present.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $prefs = Get-MetraDeskPreferences -MetraRoot $MetraRoot
    $opsPort = 0
    if ($null -ne $prefs.opsPort -and "$($prefs.opsPort)" -match '^\d+$') {
        $opsPort = [int]$prefs.opsPort
    }
    $browserHost = [string](Get-MetraProp -Object $prefs -Name 'browserHost' -Default '')
    $prefer = $true
    if ($null -ne $prefs.preferFriendlyUrl) {
        $prefer = [bool]$prefs.preferFriendlyUrl
    }
    $bindTailscale = $false
    if ($null -ne $prefs.bindTailscale) {
        $bindTailscale = [bool]$prefs.bindTailscale
    }

    $port = if ($opsPort -gt 0) { $opsPort } else { Get-MetraOpsFallbackPort }

    if ($bindTailscale) {
        $tsIp = Get-MetraOpsTailscaleIPv4
        if (-not [string]::IsNullOrWhiteSpace($tsIp)) {
            $serveHttps = ''
            $serveErr = ''
            if (Get-Command Get-MetraOpsTailscaleServeStatus -ErrorAction SilentlyContinue) {
                $st = Get-MetraOpsTailscaleServeStatus -Port $port
                if ($st.Ok) {
                    $serveHttps = [string]$st.ShareUrl
                }
                else {
                    $serveErr = [string]$st.Reason
                }
            }
            else {
                $serveErr = 'tailscale-serve-status-unavailable'
            }
            return Get-MetraOpsTailscaleBinding -Address $tsIp -Port $port -ServeHttpsUrl $serveHttps -ServeError $serveErr
        }
    }

    if ($opsPort -gt 0) {
        if ($opsPort -eq $script:MetraOpsFriendlyPort -and (
                $browserHost -eq $script:MetraOpsFriendlyHost -or
                ($prefer -and [string]::IsNullOrWhiteSpace($browserHost))
            )) {
            return Get-MetraOpsFriendlyBinding
        }
        if ($browserHost -eq $script:MetraOpsFriendlyHost -and $opsPort -eq $script:MetraOpsFriendlyPort) {
            return Get-MetraOpsFriendlyBinding
        }
        return Get-MetraOpsLoopbackBinding -Port $opsPort
    }

    return Get-MetraOpsLoopbackBinding -Port (Get-MetraOpsFallbackPort)
}

function Add-MetraOpsFriendlyPrefixIfUsable {
    <#
    .SYNOPSIS
        When http://metra/ is already reserved, keep it on ListenerPrefixes under Tailscale reach.
    .DESCRIPTION
        BrowserUrl / ShareUrl still prefer Tailscale. Friendly listen is additive so supervised
        and init paths stay consistent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Binding,
        [Parameter(Mandatory)][int]$Port
    )

    $friendlyUsable = (
        $Port -eq $script:MetraOpsFriendlyPort -and
        (Test-MetraHostsEntry -HostName $script:MetraOpsFriendlyHost) -and
        (Test-MetraHttpUrlAcl -Prefix "http://$($script:MetraOpsFriendlyHost):$Port/")
    )

    if ($friendlyUsable) {
        $friendlyPrefix = "http://$($script:MetraOpsFriendlyHost):$Port/"
        if (@($Binding.ListenerPrefixes) -notcontains $friendlyPrefix) {
            $Binding.ListenerPrefixes = @(@($Binding.ListenerPrefixes) + $friendlyPrefix)
        }
    }

    return $Binding
}

function Get-MetraOpsDeskBindingForPort {
    <#
    .SYNOPSIS
        Binding for an explicit port that still honors reach prefs (Tailscale, friendly host).
    .DESCRIPTION
        Callers that already know the port (supervised child, -Port on the CLI) must not fall back to
        loopback-only prefixes, or a reserved non-loopback prefix answers 503 with no listener behind it.
        Tailscale reach wins for BrowserUrl / ShareUrl; when friendly host ACLs are already reserved,
        that prefix is still added to ListenerPrefixes so http://metra/ keeps answering.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "Invalid port: $Port"
    }

    $prefs = Get-MetraDeskPreferences -MetraRoot $MetraRoot
    $bindTailscale = $false
    if ($null -ne $prefs.bindTailscale) {
        $bindTailscale = [bool]$prefs.bindTailscale
    }

    $binding = $null
    if ($bindTailscale) {
        $tsIp = Get-MetraOpsTailscaleIPv4
        if (-not [string]::IsNullOrWhiteSpace($tsIp)) {
            $serveHttps = ''
            $serveErr = ''
            if (Get-Command Get-MetraOpsTailscaleServeStatus -ErrorAction SilentlyContinue) {
                $st = Get-MetraOpsTailscaleServeStatus -Port $Port
                if ($st.Ok) {
                    $serveHttps = [string]$st.ShareUrl
                }
                else {
                    $serveErr = [string]$st.Reason
                }
            }
            else {
                $serveErr = 'tailscale-serve-status-unavailable'
            }
            $binding = Get-MetraOpsTailscaleBinding -Address $tsIp -Port $Port -ServeHttpsUrl $serveHttps -ServeError $serveErr
        }
    }

    $friendlyUsable = (
        $Port -eq $script:MetraOpsFriendlyPort -and
        (Test-MetraHostsEntry -HostName $script:MetraOpsFriendlyHost) -and
        (Test-MetraHttpUrlAcl -Prefix "http://$($script:MetraOpsFriendlyHost):$Port/")
    )

    if (-not $binding) {
        if ($friendlyUsable) {
            return Get-MetraOpsFriendlyBinding -Port $Port
        }
        return Get-MetraOpsLoopbackBinding -Port $Port
    }

    # Tailscale reach wins for the browser URL, but keep http://metra/ listening when reserved.
    return Add-MetraOpsFriendlyPrefixIfUsable -Binding $binding -Port $Port
}

function ConvertTo-MetraMachineRole {
    <#
    .SYNOPSIS
        Normalizes HQ / Satellite / Standalone machine role labels.
    #>
    [CmdletBinding()]
    param([string]$Role)

    if ([string]::IsNullOrWhiteSpace($Role)) { return $null }
    switch -Regex ($Role.Trim()) {
        '^(?i)hq$' { return 'Hq' }
        '^(?i)satellite$' { return 'Satellite' }
        '^(?i)standalone$' { return 'Standalone' }
        default { return $null }
    }
}

function Invoke-MetraMachineRoleSetup {
    <#
    .SYNOPSIS
        First-run machine role (Hq / Satellite / Standalone) with Defaults or Advanced networking.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$Role,
        [string]$OpsBaseUrl,
        [string]$SyncToken,
        [switch]$Advanced,
        [switch]$PreferFriendly,
        [switch]$NoPreferFriendly,
        [switch]$BindTailscale,
        [switch]$Interactive,
        [switch]$Preview,
        [switch]$Quiet
    )

    $prefs = Get-MetraDeskPreferences -MetraRoot $MetraRoot
    $resolved = ConvertTo-MetraMachineRole -Role $Role
    if (-not $resolved -and $prefs.machineRole) {
        $resolved = ConvertTo-MetraMachineRole -Role ([string]$prefs.machineRole)
    }

    $useAdvanced = [bool]$Advanced
    if ($Interactive -and -not $resolved) {
        if (-not $Quiet) {
            Write-Host ''
            Write-Host 'What kind of machine is this?' -ForegroundColor Cyan
            Write-Host '  [1] HQ         - This PC hosts Ops (main desk / jumpbox)'
            Write-Host '  [2] Satellite  - Use another machine Ops URL (laptop)'
            Write-Host '  [3] Standalone - Local only; no remote Ops'
        }
        $pick = ''
        try { $pick = Read-Host 'Choice [1/2/3]' } catch { $pick = '3' }
        switch -Regex ($pick.Trim()) {
            '^1$' { $resolved = 'Hq' }
            '^2$' { $resolved = 'Satellite' }
            '^3$' { $resolved = 'Standalone' }
            '^(?i)hq$' { $resolved = 'Hq' }
            '^(?i)sat' { $resolved = 'Satellite' }
            default { $resolved = 'Standalone' }
        }
        if (-not $Quiet) {
            Write-Host ("  Selected: {0}" -f $resolved) -ForegroundColor Green
        }
        # Advanced networking knobs are for machines that host Ops locally.
        if ($resolved -in @('Hq', 'Standalone') -and -not $Advanced) {
            $advPick = ''
            try {
                $advPick = Read-Host 'Use Defaults for this role, or Advanced local Ops prompts? [D]efaults / [A]dvanced'
            }
            catch { $advPick = 'D' }
            if ($advPick -match '^[aA]') { $useAdvanced = $true }
        }
        else {
            $useAdvanced = $false
        }
    }

    if (-not $resolved) {
        $resolved = 'Standalone'
    }

    if (-not $Preview) {
        $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot -MachineRole $resolved
    }

    $opsUrlWritten = $null
    $syncTokenWritten = $null
    if ($resolved -eq 'Satellite' -and -not $Preview) {
        $existing = Get-MetraProfileOpsBaseUrlOrNull -MetraRoot $MetraRoot
        $url = $existing
        if (-not [string]::IsNullOrWhiteSpace($OpsBaseUrl)) {
            $url = $OpsBaseUrl.Trim().TrimEnd('/')
        }
        elseif ($Interactive -and (
                [string]::IsNullOrWhiteSpace($url) -or $useAdvanced -or [bool]$Advanced
            )) {
            if (-not $Quiet) {
                Write-Host ''
                Write-Host 'HQ Ops URL (required for Satellite):' -ForegroundColor Cyan
                Write-Host '  Paste the jumpbox Ops URL from Tailscale Serve / MagicDNS.'
                Write-Host '  Example: https://metra.example.ts.net'
                if (-not [string]::IsNullOrWhiteSpace($existing)) {
                    Write-Host ("  Current: {0}" -f $existing) -ForegroundColor DarkGray
                }
            }
            $entered = ''
            try {
                $prompt = if ([string]::IsNullOrWhiteSpace($existing)) { 'HQ OpsBaseUrl' } else { 'HQ OpsBaseUrl (Enter keeps current)' }
                $entered = Read-Host $prompt
            }
            catch { $entered = '' }
            if (-not [string]::IsNullOrWhiteSpace($entered)) {
                $url = $entered
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($url)) {
            $opsUrlWritten = Set-MetraConfiguredOpsBaseUrl -OpsBaseUrl $url -MetraRoot $MetraRoot
        }
        elseif ($Interactive -and -not $Quiet) {
            Write-Host '  No OpsBaseUrl yet. Set later in Ops Settings or metra.config.json opsBaseUrl.' -ForegroundColor Yellow
        }

        $tokenToStore = $SyncToken
        if ([string]::IsNullOrWhiteSpace($tokenToStore) -and $Interactive -and -not $Quiet) {
            Write-Host ''
            Write-Host 'Profile sync token (optional):' -ForegroundColor Cyan
            Write-Host '  From HQ Metra Ops Settings -> Issue sync token. Leave blank to skip.'
            try { $tokenToStore = Read-Host 'Profile sync token' } catch { $tokenToStore = '' }
        }
        if (-not [string]::IsNullOrWhiteSpace($tokenToStore)) {
            if (-not (Get-Command Set-MetraProfileSyncClientToken -ErrorAction SilentlyContinue)) {
                throw 'Cannot save profile sync token because Set-MetraProfileSyncClientToken is not available.'
            }
            $syncTokenWritten = Set-MetraProfileSyncClientToken -SyncToken $tokenToStore -MetraRoot $MetraRoot
            if (-not $Quiet) {
                Write-Host ("  Profile sync token saved: {0}" -f $syncTokenWritten.Path) -ForegroundColor DarkGray
            }
        }
    }
    elseif ($resolved -ne 'Satellite' -and -not $Preview) {
        # HQ / Standalone: clear a leftover remote OpsBaseUrl so Desk Mode stays local.
        $existing = Get-MetraProfileOpsBaseUrlOrNull -MetraRoot $MetraRoot
        if ($existing -and (Get-Command Test-MetraOpsBaseUrlIsLocal -ErrorAction SilentlyContinue)) {
            $isLocalOpsBase = Test-MetraOpsBaseUrlIsLocal -OpsBaseUrl $existing
            if (-not $isLocalOpsBase -and $Interactive) {
                if (-not $Quiet) {
                    Write-Host ("  Clearing remote OpsBaseUrl ({0}) for {1} role." -f $existing, $resolved) -ForegroundColor DarkGray
                }
                $null = Set-MetraConfiguredOpsBaseUrl -OpsBaseUrl '' -MetraRoot $MetraRoot
            }
        }
    }

    $deskBinding = $null
    $port80Free = Test-MetraTcpPortFree -Port 80
    if ($resolved -eq 'Satellite') {
        # Satellite never hosts Ops - ignore Advanced host/Tailscale quizzes.
        $loop = Get-MetraOpsLoopbackBinding -Port (Get-MetraOpsFallbackPort)
        if (-not $Preview) {
            $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot `
                -MachineRole Satellite `
                -OpsPort $loop.Port `
                -BrowserHost '127.0.0.1' `
                -PreferFriendlyUrl $false `
                -BindTailscale $false
        }
        $deskBinding = [PSCustomObject]@{
            Preview     = [bool]$Preview
            Changed     = -not $Preview
            Binding     = $loop
            Port80Free  = $port80Free
            MachineRole = 'Satellite'
            Error       = $null
        }
        if (-not $Quiet) {
            Write-Host ''
            Write-Host 'Satellite: use HQ Ops via OpsBaseUrl. Do not start local Ops on this PC.' -ForegroundColor Cyan
        }
    }
    elseif ($useAdvanced) {
        $deskBinding = Initialize-MetraOpsDeskBinding -MetraRoot $MetraRoot -Interactive:$Interactive -Preview:$Preview -Quiet:$Quiet
        if (-not $Preview) {
            $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot -MachineRole $resolved
        }
    }
    else {
        # HQ / Standalone defaults, or installer-supplied PreferFriendly / NoPreferFriendly / BindTailscale.
        $wantFriendly = $false
        if ([bool]$PreferFriendly) {
            $wantFriendly = $true
        }
        elseif ([bool]$NoPreferFriendly) {
            $wantFriendly = $false
        }
        else {
            $wantFriendly = $port80Free
        }
        if ($wantFriendly -and $port80Free) {
            $deskBinding = Initialize-MetraOpsDeskBinding -MetraRoot $MetraRoot -PreferFriendly -Interactive:$false -Preview:$Preview -Quiet:$Quiet
        }
        elseif ($wantFriendly -and -not $port80Free) {
            if (-not $Quiet) {
                Write-Host '  Port 80 is busy; using http://127.0.0.1 fallback.' -ForegroundColor Yellow
            }
            $deskBinding = Initialize-MetraOpsDeskBinding -MetraRoot $MetraRoot `
                -NoPreferFriendly `
                -Interactive:$false `
                -Preview:$Preview `
                -Quiet:$Quiet
        }
        else {
            $deskBinding = Initialize-MetraOpsDeskBinding -MetraRoot $MetraRoot `
                -NoPreferFriendly `
                -Interactive:$false `
                -Preview:$Preview `
                -Quiet:$Quiet
        }
        if (-not $Preview) {
            $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot -MachineRole $resolved
        }
        $applyTailscale = $false
        if ($resolved -eq 'Hq' -and -not $Preview) {
            if ([bool]$BindTailscale) {
                $applyTailscale = $true
            }
            elseif ($Interactive -and -not $Quiet) {
                $tsIp = Get-MetraOpsTailscaleIPv4
                if (-not [string]::IsNullOrWhiteSpace($tsIp)) {
                    $prefsAfter = Get-MetraDeskPreferences -MetraRoot $MetraRoot
                    if (-not [bool]$prefsAfter.bindTailscale) {
                        Write-Host ''
                        Write-Host 'Tailscale Ops reach (optional for HQ):' -ForegroundColor Cyan
                        Write-Host "  Detected Tailscale IP $tsIp. Let phone/coworkers open this desk over Tailscale?" -ForegroundColor Yellow
                        Write-Host '  [y] Yes - share this HQ desk on Tailscale' -ForegroundColor DarkGray
                        Write-Host '  [N] No  - this PC only (recommended unless you need phone reach)' -ForegroundColor DarkGray
                        $tsAnswer = 'N'
                        try { $tsAnswer = Read-Host 'Choice [y/N]' } catch { $tsAnswer = 'N' }
                        if ($tsAnswer -match '^[yY]') { $applyTailscale = $true }
                    }
                }
            }
        }
        if ($applyTailscale) {
            $deskBinding = Initialize-MetraOpsDeskBinding -MetraRoot $MetraRoot -BindTailscale -Quiet:$Quiet
            if (-not $Preview) {
                $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot -MachineRole Hq
            }
        }
    }

    return [PSCustomObject]@{
        MachineRole      = $resolved
        Advanced         = $useAdvanced
        PreferFriendly   = [bool]$PreferFriendly
        NoPreferFriendly = [bool]$NoPreferFriendly
        BindTailscale    = [bool]$BindTailscale
        OpsBaseUrl       = $(if ($opsUrlWritten) { $opsUrlWritten.OpsBaseUrl } else { Get-MetraProfileOpsBaseUrlOrNull -MetraRoot $MetraRoot })
        SyncTokenPath    = $(if ($syncTokenWritten) { $syncTokenWritten.Path } else { $null })
        DeskBinding      = $deskBinding
    }
}

function Initialize-MetraOpsDeskBinding {
    <#
    .SYNOPSIS
        Setup / operator choice for Ops desk URL: http://metra/ when port 80 is free, else 7380.
        Optional -BindTailscale for non-loopback reach (view/ask). Propose/request-apply still need local session.
    .DESCRIPTION
        When -BindTailscale is chosen (or already preferred), Tailscale reach takes precedence for
        BrowserUrl over the friendly-host path even if port 80 is free. Friendly-only setup runs
        only when Tailscale bind is off.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Interactive,
        [switch]$PreferFriendly,
        [switch]$NoPreferFriendly,
        [switch]$BindTailscale,
        [switch]$Preview,
        [switch]$Quiet
    )

    $fallback = Get-MetraOpsFallbackPort
    $port80Free = Test-MetraTcpPortFree -Port $script:MetraOpsFriendlyPort
    $prefs = Get-MetraDeskPreferences -MetraRoot $MetraRoot
    $alreadyChosen = ($null -ne $prefs.opsPort -and [int]$prefs.opsPort -gt 0)

    $wantFriendly = [bool]$PreferFriendly
    if ([bool]$NoPreferFriendly) {
        $wantFriendly = $false
    }
    elseif ($Interactive -and -not $PreferFriendly -and -not $alreadyChosen) {
        if ($port80Free) {
            if (-not $Quiet) {
                Write-Host ''
                Write-Host 'Ops desk URL:' -ForegroundColor Cyan
                Write-Host "  Port 80 is free. Use http://$($script:MetraOpsFriendlyHost)/ (no port in the URL)?" -ForegroundColor Yellow
                Write-Host "  [Y] Yes - hosts entry + URL reservation (may need elevation once)" -ForegroundColor DarkGray
                Write-Host "  [N] No  - keep http://127.0.0.1:$fallback/" -ForegroundColor DarkGray
            }
            $answer = 'Y'
            try { $answer = Read-Host 'Choice [Y/n]' } catch { $answer = 'Y' }
            $wantFriendly = ($answer -notmatch '^[nN]')
        }
        else {
            if (-not $Quiet) {
                Write-Host ''
                Write-Host "Ops desk URL: port 80 is in use - using http://127.0.0.1:$fallback/" -ForegroundColor Yellow
            }
            $wantFriendly = $false
        }
    }
    elseif ($PreferFriendly) {
        $wantFriendly = $true
    }
    elseif ($alreadyChosen -and -not $BindTailscale -and -not [bool]$prefs.bindTailscale) {
        $binding = Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot
        if (-not $Quiet -and -not $Preview) {
            Write-Host ("Ops desk URL already set: {0}" -f $binding.BrowserUrl) -ForegroundColor DarkGray
        }
        return [PSCustomObject]@{
            Preview    = [bool]$Preview
            Changed    = $false
            Binding    = $binding
            Port80Free = $port80Free
            Error      = $null
        }
    }
    elseif ($alreadyChosen) {
        # URL already chosen - only Tailscale preference may change.
        $wantFriendly = $false
    }
    else {
        # Non-interactive first setup: prefer friendly when 80 is free.
        $wantFriendly = $port80Free
    }

    $wantTailscale = [bool]$BindTailscale
    if ($null -ne $prefs.bindTailscale -and [bool]$prefs.bindTailscale) {
        $wantTailscale = $true
    }
    $tsIp = Get-MetraOpsTailscaleIPv4
    if ($Interactive -and -not $BindTailscale -and -not [bool]$prefs.bindTailscale -and -not [string]::IsNullOrWhiteSpace($tsIp)) {
        if (-not $Quiet) {
            Write-Host ''
            Write-Host 'Tailscale Ops reach (optional):' -ForegroundColor Cyan
            Write-Host "  Detected Tailscale IP $tsIp. Bind Ops for phone/coworker view/ask?" -ForegroundColor Yellow
            Write-Host '  Peers may view and ask. Propose / request-apply still need your local session + tray Apply once.' -ForegroundColor DarkGray
            Write-Host '  [y] Yes - non-loopback bind (SECURITY: reach is not apply authority)' -ForegroundColor DarkGray
            Write-Host '  [N] No  - loopback / friendly only' -ForegroundColor DarkGray
        }
        $tsAnswer = 'N'
        try { $tsAnswer = Read-Host 'Choice [y/N]' } catch { $tsAnswer = 'N' }
        $wantTailscale = ($tsAnswer -match '^[yY]')
    }

    if ($Preview) {
        $would = if ($wantTailscale -and -not [string]::IsNullOrWhiteSpace($tsIp)) {
            Get-MetraOpsTailscaleBinding -Address $tsIp -Port $(if ($wantFriendly -and $port80Free) { $script:MetraOpsFriendlyPort } else { $fallback })
        }
        elseif ($wantFriendly -and $port80Free) {
            Get-MetraOpsFriendlyBinding
        }
        else {
            Get-MetraOpsLoopbackBinding -Port $fallback
        }
        if (-not $Quiet) {
            Write-Host ("Would use Ops desk URL: {0}" -f $would.BrowserUrl) -ForegroundColor Cyan
        }
        return [PSCustomObject]@{
            Preview    = $true
            Changed    = $false
            Binding    = $would
            Port80Free = $port80Free
            Error      = $null
        }
    }

    $baseBinding = $null
    if ($wantFriendly -and $port80Free -and -not $wantTailscale) {
        $enabled = Enable-MetraOpsFriendlyBinding -AllowElevation:$Interactive
        if ($enabled.Ok) {
            $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot `
                -OpsPort $enabled.Binding.Port `
                -BrowserHost $enabled.Binding.BrowserHost `
                -PreferFriendlyUrl $true `
                -BindTailscale $false
            $baseBinding = $enabled.Binding
            if (-not $Quiet) {
                Write-Host ("Ops desk URL: {0}" -f $enabled.Binding.BrowserUrl) -ForegroundColor Green
            }
        }
        else {
            if (-not $Quiet) {
                Write-Warning "Friendly URL unavailable - $($enabled.Error)"
                Write-Host ("Falling back to http://127.0.0.1:{0}/" -f $fallback) -ForegroundColor Yellow
            }
        }
    }

    if (-not $baseBinding) {
        $loopPort = $fallback
        if ($alreadyChosen -and $null -ne $prefs.opsPort -and [int]$prefs.opsPort -gt 0) {
            $loopPort = [int]$prefs.opsPort
        }
        $loop = Get-MetraOpsLoopbackBinding -Port $loopPort
        $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot `
            -OpsPort $loop.Port `
            -BrowserHost '127.0.0.1' `
            -PreferFriendlyUrl $false `
            -BindTailscale:$wantTailscale
        $baseBinding = $loop
        if (-not $Quiet -and -not $wantTailscale) {
            Write-Host ("Ops desk URL: {0}" -f $loop.BrowserUrl) -ForegroundColor Green
        }
    }

    if ($wantTailscale) {
        if ([string]::IsNullOrWhiteSpace($tsIp)) {
            if (-not $Quiet) {
                Write-Warning 'bindTailscale requested but no Tailscale IPv4 found. Keeping loopback bind.'
            }
            $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot -BindTailscale $true
            return [PSCustomObject]@{
                Preview    = $false
                Changed    = $true
                Binding    = $baseBinding
                Port80Free = $port80Free
                Error      = 'tailscale-ip-missing'
            }
        }

        $ts = Enable-MetraOpsTailscaleBinding -Address $tsIp -Port ([int]$baseBinding.Port)
        if (-not $ts.Ok) {
            if (-not $Quiet) {
                Write-Warning "Tailscale bind incomplete - $($ts.Error)"
            }
            $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot -BindTailscale $true
            return [PSCustomObject]@{
                Preview    = $false
                Changed    = $true
                Binding    = $baseBinding
                Port80Free = $port80Free
                Error      = $ts.Error
            }
        }

        $tsBinding = Add-MetraOpsFriendlyPrefixIfUsable -Binding $ts.Binding -Port ([int]$ts.Binding.Port)
        $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot `
            -OpsPort $tsBinding.Port `
            -BrowserHost $tsBinding.BrowserHost `
            -PreferFriendlyUrl $false `
            -BindTailscale $true
        if (-not $Quiet) {
            Write-Host ("Ops desk URL (Tailscale reach): {0}" -f $tsBinding.BrowserUrl) -ForegroundColor Green
            Write-Host ("Operator desk (Settings / local session): {0}" -f $tsBinding.OperatorUrl) -ForegroundColor DarkGray
            Write-Host 'Share for view/ask only. Propose and request-apply need your local session token; tray Apply once still gates disk writes.' -ForegroundColor DarkYellow
        }
        return [PSCustomObject]@{
            Preview    = $false
            Changed    = $true
            Binding    = $tsBinding
            Port80Free = $port80Free
            Error      = $null
        }
    }

    return [PSCustomObject]@{
        Preview    = $false
        Changed    = $true
        Binding    = $baseBinding
        Port80Free = $port80Free
        Error      = $(if ($wantFriendly -and -not $baseBinding.Friendly) { 'friendly-failed-fallback' } else { $null })
    }
}
