# Ops desk URL binding: prefer http://metra/ on port 80 when free; else 127.0.0.1:7380.

$script:MetraOpsFallbackPort = 7380
$script:MetraOpsFriendlyHost = 'metra'
$script:MetraOpsFriendlyPort = 80

function Get-MetraOpsFallbackPort {
    return [int]$script:MetraOpsFallbackPort
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

    $path = Get-MetraOpsHostsFilePath
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $pattern = "^\s*$([regex]::Escape($Address))\s+$([regex]::Escape($HostName))(\s|$)"
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

    $norm = $Prefix.TrimEnd('/').ToLowerInvariant() + '/'
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
            # http://+:80/ covers any host on 80
            if ($reserved -eq ('http://+:' + ([uri]$norm).Port + '/')) { return $true }
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

    $prefixes = @("http://127.0.0.1:$Port/")
    $browserUrl = if ($Port -eq 80) { 'http://127.0.0.1/' } else { "http://127.0.0.1:$Port/" }
    return [PSCustomObject]@{
        Port           = $Port
        BrowserHost    = '127.0.0.1'
        BrowserUrl     = $browserUrl
        ListenerPrefixes = $prefixes
        Friendly       = $false
        Reason         = 'loopback-fallback'
    }
}

function Get-MetraOpsFriendlyBinding {
    param(
        [string]$HostName = $script:MetraOpsFriendlyHost,
        [int]$Port = $script:MetraOpsFriendlyPort
    )

    $prefixes = @(
        "http://127.0.0.1:$Port/"
        "http://${HostName}:$Port/"
    )
    $browserUrl = if ($Port -eq 80) { "http://${HostName}/" } else { "http://${HostName}:$Port/" }
    return [PSCustomObject]@{
        Port             = $Port
        BrowserHost      = $HostName
        BrowserUrl       = $browserUrl
        ListenerPrefixes = $prefixes
        Friendly         = $true
        Reason           = 'friendly-hostname'
    }
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
    #>
    [CmdletBinding()]
    param(
        [string]$HostName = 'metra',
        [int]$Port = 80
    )

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

function Initialize-MetraOpsDeskBinding {
    <#
    .SYNOPSIS
        Setup / operator choice for Ops desk URL: http://metra/ when port 80 is free, else 7380.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Interactive,
        [switch]$PreferFriendly,
        [switch]$Preview,
        [switch]$Quiet
    )

    $fallback = Get-MetraOpsFallbackPort
    $port80Free = Test-MetraTcpPortFree -Port $script:MetraOpsFriendlyPort
    $prefs = Get-MetraDeskPreferences -MetraRoot $MetraRoot
    $alreadyChosen = ($null -ne $prefs.opsPort -and [int]$prefs.opsPort -gt 0)

    $wantFriendly = [bool]$PreferFriendly
    if ($Interactive -and -not $PreferFriendly -and -not $alreadyChosen) {
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
    elseif ($alreadyChosen) {
        $binding = Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot
        if (-not $Quiet -and -not $Preview) {
            Write-Host ("Ops desk URL already set: {0}" -f $binding.BrowserUrl) -ForegroundColor DarkGray
        }
        return [PSCustomObject]@{
            Preview   = [bool]$Preview
            Changed   = $false
            Binding   = $binding
            Port80Free = $port80Free
            Error     = $null
        }
    }
    else {
        # Non-interactive first setup: prefer friendly when 80 is free.
        $wantFriendly = $port80Free
    }

    if ($Preview) {
        $would = if ($wantFriendly -and $port80Free) {
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

    if ($wantFriendly -and $port80Free) {
        $enabled = Enable-MetraOpsFriendlyBinding -AllowElevation:$Interactive
        if ($enabled.Ok) {
            $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot `
                -OpsPort $enabled.Binding.Port `
                -BrowserHost $enabled.Binding.BrowserHost `
                -PreferFriendlyUrl $true
            if (-not $Quiet) {
                Write-Host ("Ops desk URL: {0}" -f $enabled.Binding.BrowserUrl) -ForegroundColor Green
            }
            return [PSCustomObject]@{
                Preview    = $false
                Changed    = $true
                Binding    = $enabled.Binding
                Port80Free = $port80Free
                Error      = $null
            }
        }
        if (-not $Quiet) {
            Write-Warning "Friendly URL unavailable - $($enabled.Error)"
            Write-Host ("Falling back to http://127.0.0.1:{0}/" -f $fallback) -ForegroundColor Yellow
        }
    }

    $loop = Get-MetraOpsLoopbackBinding -Port $fallback
    $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot `
        -OpsPort $loop.Port `
        -BrowserHost '127.0.0.1' `
        -PreferFriendlyUrl $false
    if (-not $Quiet) {
        Write-Host ("Ops desk URL: {0}" -f $loop.BrowserUrl) -ForegroundColor Green
    }
    return [PSCustomObject]@{
        Preview    = $false
        Changed    = $true
        Binding    = $loop
        Port80Free = $port80Free
        Error      = $(if ($wantFriendly) { 'friendly-failed-fallback' } else { $null })
    }
}
