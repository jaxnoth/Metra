# Tailscale Serve HTTPS front for Metra Ops (optional when bindTailscale).

function Get-MetraOpsTailscaleServeStatus {
    <#
    .SYNOPSIS
        Best-effort Serve status: HTTPS share URL when Serve fronts a local port.
    #>
    [CmdletBinding()]
    param([int]$Port = 0)

    $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [PSCustomObject]@{
            Ok       = $false
            ShareUrl = $null
            Reason   = 'tailscale CLI not found'
            Raw      = $null
        }
    }

    try {
        $raw = & tailscale serve status --json 2>$null | Out-String
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [PSCustomObject]@{
                Ok       = $false
                ShareUrl = $null
                Reason   = 'serve status empty'
                Raw      = $null
            }
        }
        $status = $raw | ConvertFrom-Json
    }
    catch {
        return [PSCustomObject]@{
            Ok       = $false
            ShareUrl = $null
            Reason   = "serve status failed: $($_.Exception.Message)"
            Raw      = $null
        }
    }

    $dns = $null
    try { $dns = Get-MetraOpsTailscaleDnsName } catch { }
    if ([string]::IsNullOrWhiteSpace($dns)) {
        return [PSCustomObject]@{
            Ok       = $false
            ShareUrl = $null
            Reason   = 'MagicDNS name unavailable'
            Raw      = $status
        }
    }

    # Serve status JSON is empty object when nothing is configured.
    $httpsOn = $false
    try {
        if ($null -ne $status.Web) {
            $webProps = @($status.Web.PSObject.Properties)
            if ($webProps.Count -gt 0) { $httpsOn = $true }
        }
        if (-not $httpsOn -and $null -ne $status.TCP) {
            $tcpProps = @($status.TCP.PSObject.Properties)
            if ($tcpProps.Count -gt 0) { $httpsOn = $true }
        }
        if (-not $httpsOn -and $null -ne $status.Background) {
            $bgProps = @($status.Background.PSObject.Properties)
            if ($bgProps.Count -gt 0) { $httpsOn = $true }
        }
        if (-not $httpsOn -and $null -ne $status.Foreground) {
            $fgProps = @($status.Foreground.PSObject.Properties)
            if ($fgProps.Count -gt 0) { $httpsOn = $true }
        }
    }
    catch { }

    if (-not $httpsOn) {
        return [PSCustomObject]@{
            Ok       = $false
            ShareUrl = $null
            Reason   = 'Serve not configured'
            Raw      = $status
        }
    }

    $share = "https://$dns/"
    return [PSCustomObject]@{
        Ok       = $true
        ShareUrl = $share
        DnsName  = $dns
        Port     = $Port
        Reason   = $null
        Raw      = $status
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
        [void]$proc.Start()
    }
    catch {
        return [PSCustomObject]@{ Ok = $false; ExitCode = -1; Output = $_.Exception.Message }
    }

    if (-not $proc.WaitForExit([Math]::Max(1, $TimeoutSec) * 1000)) {
        try { $proc.Kill($true) } catch {
            try { $proc.Kill() } catch { }
        }
        try { $proc.Dispose() } catch { }
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
    try { $proc.Dispose() } catch { }
    $out = (@($stdout, $stderr) | Where-Object { $_ } ) -join "`n"
    return [PSCustomObject]@{
        Ok       = ($code -eq 0)
        ExitCode = $code
        Output   = $out
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
