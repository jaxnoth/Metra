# Tailscale Serve HTTPS front for Metra Ops (optional when bindTailscale).
# Reachability only - Serve never grants apply / write authority.

function Get-MetraOpsTailscaleServeStatus {
    <#
    .SYNOPSIS
        Best-effort Serve status: inferred HTTPS share URL when Serve appears configured.
    .DESCRIPTION
        Ok means MagicDNS is available and some Serve config section is non-empty
        (Web / TCP / Background / Foreground). That is ServeConfigured, not a verified
        HTTPS probe of the MagicDNS URL or proof that Serve targets -Port.
        ShareUrl is constructed from MagicDNS when ServeConfigured; no network check.
        -Port is echoed for caller correlation only.
    #>
    [CmdletBinding()]
    param([int]$Port = 0)

    $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [PSCustomObject]@{
            Ok              = $false
            ServeConfigured = $false
            ShareUrl        = $null
            DnsName         = $null
            Port            = $Port
            ServeSections   = @()
            Reason          = 'tailscale CLI not found'
            Raw             = $null
        }
    }

    $raw = $null
    try {
        $raw = & tailscale serve status --json 2>$null | Out-String
    }
    catch {
        return [PSCustomObject]@{
            Ok              = $false
            ServeConfigured = $false
            ShareUrl        = $null
            DnsName         = $null
            Port            = $Port
            ServeSections   = @()
            Reason          = "serve status failed: $($_.Exception.Message)"
            Raw             = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [PSCustomObject]@{
            Ok              = $false
            ServeConfigured = $false
            ShareUrl        = $null
            DnsName         = $null
            Port            = $Port
            ServeSections   = @()
            Reason          = 'serve status empty'
            Raw             = $null
        }
    }

    $status = $null
    try {
        $status = $raw | ConvertFrom-Json
    }
    catch {
        $rawForDiag = $raw
        if ($rawForDiag.Length -gt 16384) {
            $rawForDiag = $rawForDiag.Substring(0, 16384) + "`n...[truncated]"
        }
        return [PSCustomObject]@{
            Ok              = $false
            ServeConfigured = $false
            ShareUrl        = $null
            DnsName         = $null
            Port            = $Port
            ServeSections   = @()
            Reason          = "serve status failed: $($_.Exception.Message)"
            Raw             = $rawForDiag
        }
    }

    # Non-empty Serve sections mean "something is configured," not "HTTPS fronts this Ops port."
    $serveSections = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($section in @('Web', 'TCP', 'Background', 'Foreground')) {
            $node = $status.$section
            if ($null -eq $node) { continue }
            $props = @($node.PSObject.Properties)
            if ($props.Count -gt 0) {
                [void]$serveSections.Add($section)
            }
        }
    }
    catch { }

    $serveConfigured = $serveSections.Count -gt 0
    $sectionArr = @($serveSections.ToArray())

    $dns = $null
    try { $dns = Get-MetraOpsTailscaleDnsName } catch { }

    if (-not $serveConfigured) {
        return [PSCustomObject]@{
            Ok              = $false
            ServeConfigured = $false
            ShareUrl        = $null
            DnsName         = $(if ([string]::IsNullOrWhiteSpace($dns)) { $null } else { $dns })
            Port            = $Port
            ServeSections   = @()
            Reason          = 'Serve not configured'
            Raw             = $status
        }
    }

    if ([string]::IsNullOrWhiteSpace($dns)) {
        return [PSCustomObject]@{
            Ok              = $false
            ServeConfigured = $true
            ShareUrl        = $null
            DnsName         = $null
            Port            = $Port
            ServeSections   = $sectionArr
            Reason          = 'MagicDNS name unavailable'
            Raw             = $status
        }
    }

    # Inferred share URL from MagicDNS - not HTTP-probed against -Port.
    $share = "https://$dns/"
    return [PSCustomObject]@{
        Ok              = $true
        ServeConfigured = $true
        ShareUrl        = $share
        DnsName         = $dns
        Port            = $Port
        ServeSections   = $sectionArr
        Reason          = $null
        Raw             = $status
    }
}

function Invoke-MetraOpsTailscaleServeCommand {
    <#
    .SYNOPSIS
        Runs a tailscale serve command with a hard timeout so Ops start cannot hang.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Arguments,
        [int]$TimeoutSec = 12
    )

    $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [PSCustomObject]@{ Ok = $false; ExitCode = -1; Output = 'tailscale CLI not found' }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $cmd.Source
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        try {
            [void]$proc.Start()
        }
        catch {
            return [PSCustomObject]@{ Ok = $false; ExitCode = -1; Output = $_.Exception.Message }
        }

        if (-not $proc.WaitForExit([Math]::Max(1, $TimeoutSec) * 1000)) {
            try { $proc.Kill($true) } catch {
                try { $proc.Kill() } catch { }
            }
            return [PSCustomObject]@{
                Ok       = $false
                ExitCode = -1
                Output   = "tailscale serve timed out after ${TimeoutSec}s"
            }
        }

        $stdout = ''
        $stderr = ''
        try { $stdout = $proc.StandardOutput.ReadToEnd() } catch { }
        try { $stderr = $proc.StandardError.ReadToEnd() } catch { }
        $code = $proc.ExitCode
        $out = (@($stdout, $stderr) | Where-Object { $_ } ) -join "`n"
        return [PSCustomObject]@{
            Ok       = ($code -eq 0)
            ExitCode = $code
            Output   = $out
        }
    }
    finally {
        try { $proc.Dispose() } catch { }
    }
}

function Enable-MetraOpsTailscaleServe {
    <#
    .SYNOPSIS
        Configures Tailscale Serve to proxy HTTPS MagicDNS to loopback Ops.
    .DESCRIPTION
        Serve is not required to run Metra. When bindTailscale is on, Metra tries to
        orchestrate Serve so the share URL is a secure context for phone clipboard APIs.
        Funnel stays out of scope. Commands are hard-timeout so Ops start never hangs.
        Success means ServeConfigured + MagicDNS inference succeeded - not a verified
        HTTPS health check of the Ops listener.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port
    )

    $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [PSCustomObject]@{
            Ok       = $false
            ShareUrl = $null
            Reason   = 'tailscale CLI not found - install Tailscale or use loopback Ops'
        }
    }

    $existing = Get-MetraOpsTailscaleServeStatus -Port $Port
    if ($existing.Ok) {
        return [PSCustomObject]@{
            Ok       = $true
            ShareUrl = [string]$existing.ShareUrl
            Reason   = $null
        }
    }

    $target = "http://127.0.0.1:$Port"
    $attempts = @(
        "serve --bg $Port"
        "serve --bg $target"
        "serve --bg --https=443 $target"
    )
    $err = $null
    foreach ($args in $attempts) {
        $run = Invoke-MetraOpsTailscaleServeCommand -Arguments $args -TimeoutSec 12
        if ($run.Ok) { break }
        $err = if ($run.Output) { [string]$run.Output } else { "exit $($run.ExitCode)" }
        if ($err -match 'timed out') { break }
    }

    Start-Sleep -Milliseconds 400
    $status = Get-MetraOpsTailscaleServeStatus -Port $Port
    if ($status.Ok) {
        return [PSCustomObject]@{
            Ok       = $true
            ShareUrl = [string]$status.ShareUrl
            Reason   = $null
        }
    }

    $reason = if ($err) { $err } elseif ($status.Reason) { [string]$status.Reason } else { 'Serve could not start' }
    $hint = 'Enable HTTPS certificates in the Tailscale admin console, then retry Ops with bindTailscale.'
    return [PSCustomObject]@{
        Ok       = $false
        ShareUrl = $null
        Reason   = "$reason. $hint"
    }
}
