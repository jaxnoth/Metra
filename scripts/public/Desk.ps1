function Invoke-MetraDeskBridgeCommand {
    <#
    .SYNOPSIS
        Jumpbox <-> satellite desk bridge (SSH drop for operator notes and agent handoffs).
    .DESCRIPTION
        Stores messages under %LOCALAPPDATA%\Metra\desk-bridge and syncs via SCP/SSH.
        audience=operator is for you; audience=agent is for Cursor on the peer machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subcommand,

        [string[]]$ArgsRest = @()
    )

    $sub = $Subcommand.Trim().ToLowerInvariant()
    $peer = $null
    $audience = 'operator'
    $subject = ''
    $bodyParts = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $ArgsRest.Count) {
        $a = [string]$ArgsRest[$i]
        if ($a -match '^(?i)-To$' -and ($i + 1) -lt $ArgsRest.Count) {
            $peer = [string]$ArgsRest[$i + 1]; $i += 2; continue
        }
        if ($a -match '^(?i)-To=(.+)$') {
            $peer = $Matches[1]; $i += 1; continue
        }
        if ($a -match '^(?i)-Peer$' -and ($i + 1) -lt $ArgsRest.Count) {
            $peer = [string]$ArgsRest[$i + 1]; $i += 2; continue
        }
        if ($a -match '^(?i)-Peer=(.+)$') {
            $peer = $Matches[1]; $i += 1; continue
        }
        if ($a -match '^(?i)-Audience$' -and ($i + 1) -lt $ArgsRest.Count) {
            $audience = [string]$ArgsRest[$i + 1]; $i += 2; continue
        }
        if ($a -match '^(?i)-Audience=(.+)$') {
            $audience = $Matches[1]; $i += 1; continue
        }
        if ($a -match '^(?i)-Subject$' -and ($i + 1) -lt $ArgsRest.Count) {
            $subject = [string]$ArgsRest[$i + 1]; $i += 2; continue
        }
        if ($a -match '^(?i)-Subject=(.+)$') {
            $subject = $Matches[1]; $i += 1; continue
        }
        if ($a -match '^(?i)-Body$' -and ($i + 1) -lt $ArgsRest.Count) {
            [void]$bodyParts.Add([string]$ArgsRest[$i + 1]); $i += 2; continue
        }
        if ($a -match '^(?i)-Agent$') {
            $audience = 'agent'; $i += 1; continue
        }
        if ($a -match '^(?i)-Operator$') {
            $audience = 'operator'; $i += 1; continue
        }
        if ($a -match '^-') {
            throw ("Unknown desk flag: {0}" -f $a)
        }
        [void]$bodyParts.Add($a)
        $i += 1
    }
    if ($audience -notmatch '^(?i)(operator|agent)$') {
        throw "Audience must be operator or agent."
    }
    $audience = $audience.ToLowerInvariant()

    switch ($sub) {
        'status' {
            $pack = Get-MetraDeskBridgeConfig
            $p = Resolve-MetraDeskBridgePeer -Peer $peer
            $outCount = @(Get-ChildItem -LiteralPath (Join-Path $pack.Root 'outbox') -File -Filter '*.md' -ErrorAction SilentlyContinue).Count
            $inCount = @(Get-ChildItem -LiteralPath (Join-Path $pack.Root 'inbox') -File -Filter '*.md' -ErrorAction SilentlyContinue).Count
            return [PSCustomObject]@{
                Root            = $pack.Root
                ConfigPath      = $pack.Path
                DefaultPeer     = [string]$pack.Config.defaultPeer
                Peer            = $p.Name
                PeerLabel       = $p.Label
                SshHost         = $p.SshHost
                SshHostFallback = $p.SshHostFallback
                RemoteRoot      = $p.RemoteRoot
                OutboxCount     = $outCount
                InboxCount      = $inCount
            }
        }
        'send' {
            $body = ($bodyParts -join ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($body)) {
                throw "desk send requires a body. Example: .\metra.ps1 desk send -Agent 'Create clients/ios Xcode project'"
            }
            $to = if ($peer) { $peer } else { (Get-MetraDeskBridgeConfig).Config.defaultPeer }
            $from = Get-MetraDeskBridgeLocalHostName
            $msg = New-MetraDeskBridgeMessage -To $to -Audience $audience -Body $body -Subject $subject -From $from
            $push = Sync-MetraDeskBridgePush -PeerName $to
            return [PSCustomObject]@{
                Ok       = $true
                Action   = 'send+push'
                Message  = $msg
                Push     = $push
            }
        }
        'push' {
            return Sync-MetraDeskBridgePush -PeerName $peer
        }
        'pull' {
            return Sync-MetraDeskBridgePull -PeerName $peer
        }
        'sync' {
            $pushed = Sync-MetraDeskBridgePush -PeerName $peer
            $pulled = Sync-MetraDeskBridgePull -PeerName $peer
            return [PSCustomObject]@{
                Ok     = $true
                Action = 'sync'
                Push   = $pushed
                Pull   = $pulled
            }
        }
        'inbox' {
            return Get-MetraDeskBridgeInbox -Audience $audience
        }
        'open' {
            $root = Initialize-MetraDeskBridgeLayout
            $candidates = @(
                (Join-Path $root 'PEER-CURRENT-operator.md')
                (Join-Path $root 'PEER-CURRENT-agent.md')
                (Join-Path $root 'CURRENT-operator.md')
                (Join-Path $root 'CURRENT-agent.md')
            )
            if ($audience -eq 'agent') {
                $candidates = @(
                    (Join-Path $root 'PEER-CURRENT-agent.md')
                    (Join-Path $root 'CURRENT-agent.md')
                ) + $candidates
            }
            $path = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $path) {
                $latest = Get-MetraDeskBridgeInbox -Audience $audience | Select-Object -First 1
                if ($latest) { $path = $latest.Path }
            }
            if (-not $path) {
                throw 'No desk messages to open. Send or pull first.'
            }
            if ($IsWindows -or $env:OS -match 'Windows') {
                Start-Process notepad.exe -ArgumentList ("`"{0}`"" -f $path) | Out-Null
            }
            elseif (Get-Command open -ErrorAction SilentlyContinue) {
                & open $path
            }
            elseif (Get-Command xdg-open -ErrorAction SilentlyContinue) {
                & xdg-open $path
            }
            elseif (-not [string]::IsNullOrWhiteSpace($env:EDITOR)) {
                & $env:EDITOR $path
            }
            else {
                throw "No opener found for desk message. Set `$env:EDITOR or install open/xdg-open."
            }
            return [PSCustomObject]@{ Ok = $true; Path = $path }
        }
        'help' {
            return [PSCustomObject]@{
                Usage = @(
                    '.\metra.ps1 desk status'
                    ".\metra.ps1 desk send 'Please install Homebrew on the Mac'"
                    ".\metra.ps1 desk send -Agent 'Scaffold MetraOps SwiftUI Ask shell under clients/ios'"
                    '.\metra.ps1 desk push | pull | sync'
                    '.\metra.ps1 desk inbox'
                    '.\metra.ps1 desk inbox -Audience agent'
                    '.\metra.ps1 desk open'
                ) -join "`n"
            }
        }
        default {
            throw "desk supports status|send|push|pull|sync|inbox|open|help. Example: .\metra.ps1 desk send -Agent '...'"
        }
    }
}
