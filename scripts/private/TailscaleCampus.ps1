# IWU campus DNSFilter MITMs Tailscale admin hostnames (login.tailscale.com).
# Pin public Tailscale coordination anycast (192.200.0.0/24) in the Windows hosts file
# so HTTPS reaches Let's Encrypt-backed endpoints instead of DNSFilter Root CA.

$script:MetraTailscaleCampusHostMarkerStart = '# MetraTailscaleCampusStart'
$script:MetraTailscaleCampusHostMarkerEnd = '# MetraTailscaleCampusEnd'
$script:MetraTailscaleCampusDefaultHosts = @(
    'login.tailscale.com'
    'controlplane.tailscale.com'
)
$script:MetraTailscaleCampusPreferredCidr = '192.200.0.0/24'
$script:MetraTailscaleCampusDnsServers = @('1.1.1.1', '8.8.8.8', '9.9.9.9')

function Test-MetraFqdnHostName {
    <#
    .SYNOPSIS
        True when Name is a safe dotted DNS hostname (not a single-label friendly host).
    #>
    [CmdletBinding()]
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $n = $Name.Trim().TrimEnd('.').ToLowerInvariant()
    if ($n.Length -gt 253) { return $false }
    if ($n -notmatch '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$') {
        return $false
    }
    foreach ($label in ($n -split '\.')) {
        if ($label.Length -lt 1 -or $label.Length -gt 63) { return $false }
    }
    return $true
}

function Test-MetraIPv4InCidr {
    <#
    .SYNOPSIS
        True when Address is an IPv4 inside Cidr (e.g. 192.200.0.0/24).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Address,
        [Parameter(Mandatory)][string]$Cidr
    )

    if (-not (Test-MetraIPv4Address -Address $Address)) { return $false }
    $parts = $Cidr.Split('/')
    if ($parts.Count -ne 2) { return $false }
    $networkText = $parts[0].Trim()
    $prefixText = $parts[1].Trim()
    if (-not (Test-MetraIPv4Address -Address $networkText)) { return $false }
    $prefix = 0
    if (-not [int]::TryParse($prefixText, [ref]$prefix)) { return $false }
    if ($prefix -lt 0 -or $prefix -gt 32) { return $false }

    $addrBytes = [System.Net.IPAddress]::Parse($Address.Trim()).GetAddressBytes()
    $netBytes = [System.Net.IPAddress]::Parse($networkText).GetAddressBytes()
    if ([BitConverter]::IsLittleEndian) {
        [Array]::Reverse($addrBytes)
        [Array]::Reverse($netBytes)
    }
    $addrVal = [BitConverter]::ToUInt32($addrBytes, 0)
    $netVal = [BitConverter]::ToUInt32($netBytes, 0)
    if ($prefix -eq 0) { return $true }
    $shifted = ([int64][uint32]::MaxValue -shl (32 - $prefix)) -band 0xFFFFFFFFL
    $mask = [uint32]$shifted
    return (($addrVal -band $mask) -eq ($netVal -band $mask))
}

function Resolve-MetraTailscaleCampusAddresses {
    <#
    .SYNOPSIS
        Resolves Tailscale campus hostnames via public DNS and prefers 192.200.0.0/24.
    .DESCRIPTION
        Campus DNSFilter rewrites login.tailscale.com to a MITM VIP (wrong cert + HSTS).
        Public resolvers return Tailscale coordination anycast in 192.200.0.0/24.
    #>
    [CmdletBinding()]
    param(
        [string[]]$HostName = $script:MetraTailscaleCampusDefaultHosts,
        [string[]]$DnsServer = $script:MetraTailscaleCampusDnsServers,
        [string]$PreferredCidr = $script:MetraTailscaleCampusPreferredCidr
    )

    $names = @(
        foreach ($h in @($HostName)) {
            $n = ([string]$h).Trim().TrimEnd('.').ToLowerInvariant()
            if (-not (Test-MetraFqdnHostName -Name $n)) {
                throw "Invalid Tailscale campus hostname: $h"
            }
            $n
        }
    ) | Select-Object -Unique

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($name in $names) {
        $raw = New-Object System.Collections.Generic.List[string]
        $errors = New-Object System.Collections.Generic.List[string]
        foreach ($server in @($DnsServer)) {
            try {
                $answers = @(Resolve-DnsName -Name $name -Type A -Server $server -DnsOnly -ErrorAction Stop |
                    Where-Object { $_.Type -eq 'A' -or $_.QueryType -eq 'A' })
                foreach ($a in $answers) {
                    $ip = [string]$a.IPAddress
                    if ((Test-MetraIPv4Address -Address $ip) -and -not $raw.Contains($ip)) {
                        [void]$raw.Add($ip)
                    }
                }
                if ($raw.Count -gt 0) { break }
            }
            catch {
                [void]$errors.Add("$server`: $($_.Exception.Message)")
            }
        }

        $preferred = New-Object System.Collections.Generic.List[string]
        foreach ($ip in $raw) {
            if (Test-MetraIPv4InCidr -Address $ip -Cidr $PreferredCidr) {
                [void]$preferred.Add($ip)
            }
        }
        $selected = if ($preferred.Count -gt 0) { $preferred.ToArray() } else { $raw.ToArray() }

        [void]$rows.Add([PSCustomObject]@{
                HostName       = $name
                AllAddresses   = $raw.ToArray()
                PreferredCidr  = $PreferredCidr
                Selected       = @($selected)
                ResolveErrors  = $errors.ToArray()
                Ok             = ($selected.Count -gt 0)
            })
    }

    return $rows.ToArray()
}

function Get-MetraTailscaleCampusHostsPlan {
    <#
    .SYNOPSIS
        Builds a hosts-file plan that pins Tailscale campus hostnames to public anycast IPs.
    #>
    [CmdletBinding()]
    param(
        [string[]]$HostName = $script:MetraTailscaleCampusDefaultHosts,
        [string[]]$DnsServer = $script:MetraTailscaleCampusDnsServers,
        [string]$PreferredCidr = $script:MetraTailscaleCampusPreferredCidr,
        [string]$HostsPath = (Get-MetraOpsHostsFilePath)
    )

    $resolved = @(Resolve-MetraTailscaleCampusAddresses -HostName $HostName -DnsServer $DnsServer -PreferredCidr $PreferredCidr)
    $targetNames = @($resolved | ForEach-Object { $_.HostName })
    $desiredLines = New-Object System.Collections.Generic.List[string]
    foreach ($row in $resolved) {
        if (-not $row.Ok) { continue }
        foreach ($ip in @($row.Selected)) {
            [void]$desiredLines.Add("$ip $($row.HostName)")
        }
    }

    $existing = @()
    if (Test-Path -LiteralPath $HostsPath) {
        $existing = @(Get-Content -LiteralPath $HostsPath -ErrorAction Stop)
    }

    $managedStart = -1
    $managedEnd = -1
    for ($i = 0; $i -lt $existing.Count; $i++) {
        $t = $existing[$i].Trim()
        if ($t -eq $script:MetraTailscaleCampusHostMarkerStart) { $managedStart = $i }
        if ($t -eq $script:MetraTailscaleCampusHostMarkerEnd) { $managedEnd = $i }
    }

    $removeIndexes = New-Object System.Collections.Generic.List[int]
    $staleLines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $existing.Count; $i++) {
        $line = $existing[$i]
        $trim = $line.Trim()
        if ($trim.StartsWith('#') -or [string]::IsNullOrWhiteSpace($trim)) { continue }
        if ($trim -notmatch '^\s*(\S+)\s+(\S+)') { continue }
        $ip = $Matches[1]
        $hostFromLine = $Matches[2].Trim().TrimEnd('.').ToLowerInvariant()
        if ($targetNames -notcontains $hostFromLine) { continue }

        $inManaged = ($managedStart -ge 0 -and $managedEnd -ge $managedStart -and $i -ge $managedStart -and $i -le $managedEnd)
        $keep = $false
        if ($inManaged) {
            $keep = $desiredLines.Contains("$ip $hostFromLine")
        }
        else {
            # Outside Metra block: drop non-preferred mappings for these names (DNSFilter VIP, search-suffix traps).
            $keep = (
                (Test-MetraIPv4InCidr -Address $ip -Cidr $PreferredCidr) -and
                $desiredLines.Contains("$ip $hostFromLine")
            )
        }
        if (-not $keep) {
            [void]$removeIndexes.Add($i)
            [void]$staleLines.Add($trim)
        }
    }

    $alreadyPresent = $true
    foreach ($line in $desiredLines) {
        $found = $false
        for ($i = 0; $i -lt $existing.Count; $i++) {
            if ($removeIndexes.Contains($i)) { continue }
            if ($existing[$i].Trim() -eq $line) { $found = $true; break }
        }
        if (-not $found) { $alreadyPresent = $false; break }
    }

    $needsWrite = (-not $alreadyPresent) -or ($removeIndexes.Count -gt 0) -or ($managedStart -lt 0)
    $bad = @($resolved | Where-Object { -not $_.Ok })
    $ok = ($desiredLines.Count -gt 0 -and $bad.Count -eq 0)
    $err = $null
    if ($desiredLines.Count -eq 0) {
        $err = 'No Tailscale campus addresses resolved from public DNS.'
    }
    elseif ($bad.Count -gt 0) {
        $err = "Unresolved: $($bad.HostName -join ', ')"
    }

    return [PSCustomObject]@{
        HostsPath      = $HostsPath
        Resolved       = $resolved
        DesiredLines   = @($desiredLines)
        StaleLines     = @($staleLines)
        RemoveIndexes  = @($removeIndexes)
        NeedsWrite     = [bool]$needsWrite
        MarkerStart    = $script:MetraTailscaleCampusHostMarkerStart
        MarkerEnd      = $script:MetraTailscaleCampusHostMarkerEnd
        PreferredCidr  = $PreferredCidr
        Ok             = $ok
        Error          = $err
    }
}

function Repair-MetraTailscaleCampusHosts {
    <#
    .SYNOPSIS
        Pins Tailscale admin hostnames in the Windows hosts file for IWU DNSFilter bypass.
    .DESCRIPTION
        login.tailscale.com is MITMed on campus (DNSFilter Root CA + HSTS). This writes a
        managed hosts block for login/controlplane using public DNS 192.200.0.0/24 anycast.
        Requires elevation to modify the hosts file. Use -Preview to print the plan only.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string[]]$HostName = $script:MetraTailscaleCampusDefaultHosts,
        [switch]$Preview,
        [switch]$Force,
        [switch]$Quiet
    )

    if (-not (Test-MetraHostIsWindows)) {
        return [PSCustomObject]@{
            Ok           = $false
            Preview      = [bool]$Preview
            Changed      = $false
            NeedsWrite   = $false
            HostsPath    = $null
            DesiredLines = @()
            StaleLines   = @()
            Resolved     = @()
            Error        = 'Tailscale campus hosts is Windows-only (hosts file pin).'
        }
    }

    $plan = Get-MetraTailscaleCampusHostsPlan -HostName $HostName
    if (-not $plan.Ok) {
        return [PSCustomObject]@{
            Ok           = $false
            Preview      = [bool]$Preview
            Changed      = $false
            NeedsWrite   = $false
            HostsPath    = $plan.HostsPath
            DesiredLines = @($plan.DesiredLines)
            StaleLines   = @($plan.StaleLines)
            Resolved     = @($plan.Resolved)
            Error        = $plan.Error
        }
    }

    if (-not $plan.NeedsWrite) {
        if (-not $Quiet) {
            Write-Host 'Tailscale campus hosts already pinned.' -ForegroundColor Green
            foreach ($line in $plan.DesiredLines) { Write-Host "  $line" -ForegroundColor DarkGray }
        }
        return [PSCustomObject]@{
            Ok           = $true
            Preview      = [bool]$Preview
            Changed      = $false
            NeedsWrite   = $false
            HostsPath    = $plan.HostsPath
            DesiredLines = @($plan.DesiredLines)
            StaleLines   = @($plan.StaleLines)
            Resolved     = @($plan.Resolved)
            Error        = $null
        }
    }

    if ($Preview -or $WhatIfPreference) {
        if (-not $Quiet) {
            Write-Host 'Tailscale campus hosts plan (Preview):' -ForegroundColor Cyan
            Write-Host "  Hosts: $($plan.HostsPath)" -ForegroundColor DarkGray
            if ($plan.StaleLines.Count -gt 0) {
                Write-Host '  Remove stale:' -ForegroundColor Yellow
                foreach ($s in $plan.StaleLines) { Write-Host "    - $s" -ForegroundColor DarkGray }
            }
            Write-Host '  Write managed block:' -ForegroundColor Yellow
            foreach ($line in $plan.DesiredLines) { Write-Host "    + $line" -ForegroundColor DarkGray }
            Write-Host '  Apply: .\metra.ps1 tailscale campus-hosts -Force' -ForegroundColor DarkGray
            Write-Host '  (Elevation required - use Windows PowerShell as Administrator, not VS Code terminal.)' -ForegroundColor DarkGray
        }
        return [PSCustomObject]@{
            Ok           = $true
            Preview      = $true
            Changed      = $false
            NeedsWrite   = $true
            HostsPath    = $plan.HostsPath
            DesiredLines = @($plan.DesiredLines)
            StaleLines   = @($plan.StaleLines)
            Resolved     = @($plan.Resolved)
            Error        = $null
        }
    }

    if (-not $Force -and -not $PSCmdlet.ShouldProcess($plan.HostsPath, 'Pin Tailscale campus hosts')) {
        if (-not $Quiet) {
            Write-Host 'Cancelled. Re-run with -Force in elevated PowerShell (Start menu -> Windows PowerShell -> Run as administrator).' -ForegroundColor Yellow
        }
        return [PSCustomObject]@{
            Ok           = $false
            Preview      = $false
            Changed      = $false
            NeedsWrite   = $true
            HostsPath    = $plan.HostsPath
            DesiredLines = @($plan.DesiredLines)
            StaleLines   = @($plan.StaleLines)
            Resolved     = @($plan.Resolved)
            Error        = 'Cancelled.'
        }
    }

    $existing = @()
    if (Test-Path -LiteralPath $plan.HostsPath) {
        $existing = @(Get-Content -LiteralPath $plan.HostsPath -ErrorAction Stop)
    }

    $removeSet = @{}
    foreach ($idx in @($plan.RemoveIndexes)) { $removeSet[$idx] = $true }

    $managedStart = -1
    $managedEnd = -1
    for ($i = 0; $i -lt $existing.Count; $i++) {
        $t = $existing[$i].Trim()
        if ($t -eq $plan.MarkerStart) { $managedStart = $i }
        if ($t -eq $plan.MarkerEnd) { $managedEnd = $i }
    }

    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $existing.Count; $i++) {
        if ($removeSet.ContainsKey($i)) { continue }
        if ($managedStart -ge 0 -and $managedEnd -ge $managedStart -and $i -ge $managedStart -and $i -le $managedEnd) {
            continue
        }
        # Drop dangling markers from a partial prior write before appending a fresh block.
        if ($managedStart -ge 0 -and $managedEnd -lt $managedStart -and $i -eq $managedStart) {
            continue
        }
        if ($managedEnd -ge 0 -and $managedStart -lt 0 -and $i -eq $managedEnd) {
            continue
        }
        [void]$out.Add($existing[$i])
    }

    while ($out.Count -gt 0 -and [string]::IsNullOrWhiteSpace($out[$out.Count - 1])) {
        $out.RemoveAt($out.Count - 1)
    }
    if ($out.Count -gt 0) { [void]$out.Add('') }
    [void]$out.Add($plan.MarkerStart)
    [void]$out.Add('# IWU DNSFilter bypass - Tailscale coordination anycast (Metra).')
    foreach ($line in $plan.DesiredLines) { [void]$out.Add($line) }
    [void]$out.Add($plan.MarkerEnd)

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllLines($plan.HostsPath, $out.ToArray(), $utf8NoBom)
    }
    catch {
        $msg = $_.Exception.Message
        if (-not $Quiet) {
            Write-Host "Could not write hosts file: $msg" -ForegroundColor Red
            Write-Host 'Run elevated PowerShell once (not VS Code terminal):' -ForegroundColor Yellow
            Write-Host '  cd C:\Projects\_meta' -ForegroundColor DarkGray
            Write-Host '  .\metra.ps1 tailscale campus-hosts -Force' -ForegroundColor DarkGray
        }
        return [PSCustomObject]@{
            Ok           = $false
            Preview      = $false
            Changed      = $false
            NeedsWrite   = $true
            HostsPath    = $plan.HostsPath
            DesiredLines = @($plan.DesiredLines)
            StaleLines   = @($plan.StaleLines)
            Resolved     = @($plan.Resolved)
            Error        = $msg
        }
    }

    if (-not $Quiet) {
        Write-Host 'Tailscale campus hosts updated.' -ForegroundColor Green
        foreach ($line in $plan.DesiredLines) { Write-Host "  $line" -ForegroundColor DarkGray }
        Write-Host 'Next: open the Serve enable link, then: tailscale serve --bg http://127.0.0.1:80' -ForegroundColor DarkGray
    }

    return [PSCustomObject]@{
        Ok           = $true
        Preview      = $false
        Changed      = $true
        NeedsWrite   = $false
        HostsPath    = $plan.HostsPath
        DesiredLines = @($plan.DesiredLines)
        StaleLines   = @($plan.StaleLines)
        Resolved     = @($plan.Resolved)
        Error        = $null
    }
}

function Show-MetraTailscaleCli {
    <#
    .SYNOPSIS
        Thin CLI export for Tailscale campus helpers.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('campus-hosts', 'help')]
        [string]$Subcommand = 'help',

        [switch]$Preview,
        [switch]$Force,
        [switch]$Quiet
    )

    switch ($Subcommand) {
        'campus-hosts' {
            return Repair-MetraTailscaleCampusHosts -Preview:$Preview -Force:$Force -Quiet:$Quiet -WhatIf:$WhatIfPreference
        }
        default {
            Write-Host @'
Metra Tailscale helpers (IWU campus):

  .\metra.ps1 tailscale campus-hosts [-Preview] [-Force]
      Pin login.tailscale.com / controlplane.tailscale.com to public Tailscale
      anycast (192.200.0.0/24) so campus DNSFilter cannot MITM admin HTTPS.

When Serve enable fails with ERR_CERT_AUTHORITY_INVALID / HSTS on login.tailscale.com,
run campus-hosts (elevated), refresh the Serve enable page, then:
  tailscale serve --bg http://127.0.0.1:80
'@
            return [PSCustomObject]@{ Ok = $true; Subcommand = 'help' }
        }
    }
}
