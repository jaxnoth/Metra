# Desk bridge - jumpbox <-> satellite (Mac) message drop over SSH/SCP.
# Machine-local store under %LOCALAPPDATA%\Metra\desk-bridge (not in git).

function Get-MetraDeskBridgeRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($IsWindows -or $env:OS -match 'Windows') {
        return (Join-Path $env:LOCALAPPDATA 'Metra\desk-bridge')
    }
    $home = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($home)) { $home = $env:HOME }
    return (Join-Path $home 'Library/Application Support/Metra/desk-bridge')
}

function Get-MetraDeskBridgeConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    Join-Path (Get-MetraDeskBridgeRoot) 'bridge.local.json'
}

function Initialize-MetraDeskBridgeLayout {
    [CmdletBinding()]
    param(
        [string]$Root = (Get-MetraDeskBridgeRoot)
    )

    foreach ($name in @('outbox', 'inbox', 'archive', 'agent-inbox')) {
        $dir = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    $cfgPath = Join-Path $Root 'bridge.local.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) {
        $default = [ordered]@{
            defaultPeer = 'mac'
            peers       = [ordered]@{
                mac = [ordered]@{
                    label           = 'peer Mac'
                    sshHost         = 'user@peer-host'
                    sshIdentityFile = '%USERPROFILE%\.ssh\id_ed25519'
                    # Optional LAN/IP fallback when MagicDNS fails; override in bridge.local.json.
                    sshHostFallback = 'user@peer-host-or-ip'
                    remoteRoot      = '/path/to/peer/desk-bridge'
                    metraRoot       = '/path/to/peer/Metra'
                }
            }
        }
        $json = ($default | ConvertTo-Json -Depth 6)
        [System.IO.File]::WriteAllText($cfgPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    }
    $readme = Join-Path $Root 'README.txt'
    if (-not (Test-Path -LiteralPath $readme)) {
        $text = @(
            'Metra desk bridge (machine-local).'
            'Use: .\metra.ps1 desk send|inbox|push|pull|sync|status|open'
            'audience=operator -> human instructions; audience=agent -> Cursor on the peer.'
            'Edit bridge.local.json for SSH host / remoteRoot.'
        ) -join "`n"
        [System.IO.File]::WriteAllText($readme, $text + "`n", [System.Text.UTF8Encoding]::new($false))
    }
    return $Root
}

function Get-MetraDeskBridgeConfig {
    [CmdletBinding()]
    param()

    $root = Initialize-MetraDeskBridgeLayout
    $cfgPath = Join-Path $root 'bridge.local.json'
    $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    [PSCustomObject]@{
        Root   = $root
        Config = $cfg
        Path   = $cfgPath
    }
}

function Resolve-MetraDeskBridgePeer {
    [CmdletBinding()]
    param(
        [string]$Peer
    )

    $pack = Get-MetraDeskBridgeConfig
    $cfg = $pack.Config
    $name = if ([string]::IsNullOrWhiteSpace($Peer)) { [string]$cfg.defaultPeer } else { $Peer.Trim() }
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'No desk peer. Set defaultPeer in bridge.local.json or pass -To / peer name.'
    }
    $peers = $cfg.peers
    if (-not $peers -or -not ($peers.PSObject.Properties.Name -contains $name)) {
        throw ("Unknown desk peer '{0}'. Known: {1}" -f $name, (($peers.PSObject.Properties.Name) -join ', '))
    }
    $p = $peers.$name
    $idFile = [Environment]::ExpandEnvironmentVariables([string](Get-MetraProp -Object $p -Name 'sshIdentityFile' -Default ''))
    # ExpandEnvironmentVariables does not expand $HOME; finish common Unix placeholders.
    if ($idFile -match '%USERPROFILE%' -or $idFile -match '\$\{?HOME\}?') {
        $home = [Environment]::GetFolderPath('UserProfile')
        if ([string]::IsNullOrWhiteSpace($home)) { $home = [string]$env:HOME }
        if (-not [string]::IsNullOrWhiteSpace($home)) {
            $idFile = $idFile.Replace('%USERPROFILE%', $home)
            $idFile = $idFile -replace '\$\{HOME\}', $home
            $idFile = $idFile -replace '\$HOME', $home
        }
    }
    if ($idFile.StartsWith('~/') -or $idFile.StartsWith('~\') -or $idFile -eq '~') {
        $home = [Environment]::GetFolderPath('UserProfile')
        if ([string]::IsNullOrWhiteSpace($home)) { $home = [string]$env:HOME }
        if (-not [string]::IsNullOrWhiteSpace($home)) {
            if ($idFile -eq '~') {
                $idFile = $home
            }
            else {
                $idFile = Join-Path $home $idFile.Substring(2)
            }
        }
    }
    [PSCustomObject]@{
        Name            = $name
        Label           = [string](Get-MetraProp -Object $p -Name 'label' -Default $name)
        SshHost         = [string](Get-MetraProp -Object $p -Name 'sshHost' -Default '')
        SshHostFallback = [string](Get-MetraProp -Object $p -Name 'sshHostFallback' -Default '')
        SshIdentityFile = $idFile
        RemoteRoot      = [string](Get-MetraProp -Object $p -Name 'remoteRoot' -Default '')
        MetraRoot       = [string](Get-MetraProp -Object $p -Name 'metraRoot' -Default '')
        LocalRoot       = $pack.Root
        ConfigPath      = $pack.Path
    }
}

function New-MetraDeskBridgeMessageId {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmss') + 'Z-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
}

function New-MetraDeskBridgeMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$To,

        [Parameter(Mandatory)]
        [ValidateSet('operator', 'agent')]
        [string]$Audience,

        [Parameter(Mandatory)]
        [string]$Body,

        [string]$Subject = '',
        [string]$From = 'jumpbox'
    )

    $root = Initialize-MetraDeskBridgeLayout
    $id = New-MetraDeskBridgeMessageId
    $safeAudience = $Audience.ToLowerInvariant()
    $fileName = '{0}_{1}_to-{2}.md' -f $id, $safeAudience, ($To -replace '[^\w\-]+', '-')
    $path = Join-Path (Join-Path $root 'outbox') $fileName
    if ([string]::IsNullOrWhiteSpace($Subject)) {
        $Subject = if ($Audience -eq 'agent') { 'Agent handoff' } else { 'Operator note' }
    }
    $created = (Get-Date).ToUniversalTime().ToString('o')
    $md = @(
        '---'
        "id: $id"
        "from: $From"
        "to: $To"
        "audience: $Audience"
        "subject: $Subject"
        "createdAt: $created"
        '---'
        ''
        $Body.TrimEnd()
        ''
    ) -join "`n"
    [System.IO.File]::WriteAllText($path, $md, [System.Text.UTF8Encoding]::new($false))

    # Sticky CURRENT for the peer audience (overwritten each send of that type).
    $currentName = if ($Audience -eq 'agent') { 'CURRENT-agent.md' } else { 'CURRENT-operator.md' }
    $currentPath = Join-Path $root $currentName
    [System.IO.File]::WriteAllText($currentPath, $md, [System.Text.UTF8Encoding]::new($false))

    [PSCustomObject]@{
        Ok       = $true
        Id       = $id
        Path     = $path
        Current  = $currentPath
        Audience = $Audience
        To       = $To
        Subject  = $Subject
    }
}

function Escape-MetraDeskBridgeRemoteSingleQuoted {
    <#
    .SYNOPSIS
        Escape a value for embedding inside a remote POSIX single-quoted shell string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value) { return '' }
    return ($Value -replace "'", "'\''")
}

function Get-MetraDeskBridgeLocalHostName {
    <#
    .SYNOPSIS
        Lowercase sender id for desk bridge messages (Windows, macOS, Linux).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    foreach ($candidate in @(
            [string]$env:COMPUTERNAME
            [string]$env:HOSTNAME
            [Environment]::MachineName
        )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return $candidate.Trim().ToLowerInvariant()
        }
    }
    return 'local'
}

function Get-MetraDeskBridgeSshArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Peer
    )

    $khDir = Join-Path (Get-MetraDeskBridgeRoot) 'ssh'
    if (-not (Test-Path -LiteralPath $khDir)) {
        New-Item -ItemType Directory -Path $khDir -Force | Out-Null
    }
    $knownHosts = Join-Path $khDir 'known_hosts'
    $args = @(
        '-o', 'BatchMode=yes'
        '-o', 'ConnectTimeout=20'
        '-o', 'StrictHostKeyChecking=accept-new'
        '-o', ("UserKnownHostsFile={0}" -f $knownHosts)
    )
    if ($Peer.SshIdentityFile -and (Test-Path -LiteralPath $Peer.SshIdentityFile)) {
        $args += @('-i', $Peer.SshIdentityFile)
    }
    return , $args
}

function Format-MetraDeskBridgeScpRemoteSpec {
    <#
    .SYNOPSIS
        Build host:path for scp, quoting remote paths that contain whitespace.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$SshHost,
        [Parameter(Mandatory)][string]$RemotePath
    )

    if ($RemotePath -match '\s') {
        $escaped = $RemotePath -replace '"', '\"'
        return ('{0}:"{1}"' -f $SshHost, $escaped)
    }
    return ('{0}:{1}' -f $SshHost, $RemotePath)
}

function Invoke-MetraDeskBridgeSsh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Peer,
        [Parameter(Mandatory)]
        [string]$RemoteCommand
    )

    $sshArgs = Get-MetraDeskBridgeSshArgs -Peer $Peer
    $hosts = @($Peer.SshHost)
    if ($Peer.SshHostFallback -and $Peer.SshHostFallback -ne $Peer.SshHost) {
        $hosts += $Peer.SshHostFallback
    }
    $lastErr = $null
    foreach ($h in $hosts) {
        if ([string]::IsNullOrWhiteSpace($h)) { continue }
        $all = $sshArgs + @($h, $RemoteCommand)
        $stdoutPath = [System.IO.Path]::GetTempFileName()
        $stderrPath = [System.IO.Path]::GetTempFileName()
        try {
            $proc = Start-Process -FilePath 'ssh' -ArgumentList $all -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
            $stdout = if (Test-Path -LiteralPath $stdoutPath) {
                [System.IO.File]::ReadAllText($stdoutPath).TrimEnd()
            } else { '' }
            $stderr = if (Test-Path -LiteralPath $stderrPath) {
                [System.IO.File]::ReadAllText($stderrPath).TrimEnd()
            } else { '' }
            if ($proc.ExitCode -eq 0) {
                return [PSCustomObject]@{
                    Ok       = $true
                    Host     = $h
                    Output   = $stdout
                    Stderr   = $stderr
                    ExitCode = 0
                }
            }
            $lastErr = if (-not [string]::IsNullOrWhiteSpace($stderr)) { $stderr } else { $stdout }
        }
        catch {
            $lastErr = [string]$_.Exception.Message
        }
        finally {
            Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }
    throw ("SSH to peer '{0}' failed. Last error: {1}" -f $Peer.Name, $lastErr)
}

function Invoke-MetraDeskBridgeScp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Peer,
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination,
        [switch]$ToRemote
    )

    $sshArgs = Get-MetraDeskBridgeSshArgs -Peer $Peer
    $hosts = @($Peer.SshHost)
    if ($Peer.SshHostFallback -and $Peer.SshHostFallback -ne $Peer.SshHost) {
        $hosts += $Peer.SshHostFallback
    }
    $lastErr = $null
    foreach ($h in $hosts) {
        if ([string]::IsNullOrWhiteSpace($h)) { continue }
        if ($ToRemote) {
            $dest = Format-MetraDeskBridgeScpRemoteSpec -SshHost $h -RemotePath $Destination
            $src = $Source
        }
        else {
            $src = Format-MetraDeskBridgeScpRemoteSpec -SshHost $h -RemotePath $Source
            $dest = $Destination
        }
        $all = $sshArgs + @($src, $dest)
        $stdoutPath = [System.IO.Path]::GetTempFileName()
        $stderrPath = [System.IO.Path]::GetTempFileName()
        try {
            $proc = Start-Process -FilePath 'scp' -ArgumentList $all -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
            $stdout = if (Test-Path -LiteralPath $stdoutPath) {
                [System.IO.File]::ReadAllText($stdoutPath).TrimEnd()
            } else { '' }
            $stderr = if (Test-Path -LiteralPath $stderrPath) {
                [System.IO.File]::ReadAllText($stderrPath).TrimEnd()
            } else { '' }
            if ($proc.ExitCode -eq 0) {
                $combined = if (-not [string]::IsNullOrWhiteSpace($stdout)) { $stdout } else { $stderr }
                return [PSCustomObject]@{ Ok = $true; Host = $h; Output = $combined; ExitCode = 0 }
            }
            $lastErr = if (-not [string]::IsNullOrWhiteSpace($stderr)) { $stderr } else { $stdout }
        }
        catch {
            $lastErr = [string]$_.Exception.Message
        }
        finally {
            Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }
    throw ("SCP with peer '{0}' failed. Last error: {1}" -f $Peer.Name, $lastErr)
}

function Sync-MetraDeskBridgePush {
    [CmdletBinding()]
    param(
        [string]$PeerName
    )

    $peer = Resolve-MetraDeskBridgePeer -Peer $PeerName
    $local = $peer.LocalRoot
    $remote = $peer.RemoteRoot.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($remote)) {
        throw 'Peer remoteRoot is empty.'
    }
    $remoteEsc = Escape-MetraDeskBridgeRemoteSingleQuoted -Value $remote

    $null = Invoke-MetraDeskBridgeSsh -Peer $peer -RemoteCommand ("mkdir -p '{0}/outbox' '{0}/inbox' '{0}/archive' '{0}/agent-inbox'" -f $remoteEsc)

    $pushed = New-Object System.Collections.Generic.List[string]
    $outbox = Join-Path $local 'outbox'
    foreach ($f in @(Get-ChildItem -LiteralPath $outbox -File -Filter '*.md' -ErrorAction SilentlyContinue)) {
        $remotePath = '{0}/inbox/{1}' -f $remote, $f.Name
        $null = Invoke-MetraDeskBridgeScp -Peer $peer -Source $f.FullName -Destination $remotePath -ToRemote
        if ($f.Name -match '_agent_') {
            $agentPath = '{0}/agent-inbox/{1}' -f $remote, $f.Name
            $null = Invoke-MetraDeskBridgeScp -Peer $peer -Source $f.FullName -Destination $agentPath -ToRemote
        }
        $archive = Join-Path (Join-Path $local 'archive') $f.Name
        Move-Item -LiteralPath $f.FullName -Destination $archive -Force
        [void]$pushed.Add($f.Name)
    }

    foreach ($sticky in @('CURRENT-operator.md', 'CURRENT-agent.md')) {
        $p = Join-Path $local $sticky
        if (Test-Path -LiteralPath $p) {
            $null = Invoke-MetraDeskBridgeScp -Peer $peer -Source $p -Destination ('{0}/{1}' -f $remote, $sticky) -ToRemote
            [void]$pushed.Add($sticky)
        }
    }

    # Mirror agent CURRENT into Metra clone for Cursor Remote SSH chats.
    $agentCurrent = Join-Path $local 'CURRENT-agent.md'
    if ((Test-Path -LiteralPath $agentCurrent) -and $peer.MetraRoot) {
        $metraRoot = $peer.MetraRoot.TrimEnd('/')
        $metraEsc = Escape-MetraDeskBridgeRemoteSingleQuoted -Value $metraRoot
        $remoteAgentNote = '{0}/local/DESK-HANDOFF-agent.md' -f $metraRoot
        $null = Invoke-MetraDeskBridgeSsh -Peer $peer -RemoteCommand ("mkdir -p '{0}/local'" -f $metraEsc)
        $null = Invoke-MetraDeskBridgeScp -Peer $peer -Source $agentCurrent -Destination $remoteAgentNote -ToRemote
        [void]$pushed.Add('DESK-HANDOFF-agent.md')
    }

    [PSCustomObject]@{
        Ok     = $true
        Peer   = $peer.Name
        Host   = $peer.SshHost
        Pushed = @($pushed)
        Count  = $pushed.Count
    }
}

function Sync-MetraDeskBridgePull {
    [CmdletBinding()]
    param(
        [string]$PeerName
    )

    $peer = Resolve-MetraDeskBridgePeer -Peer $PeerName
    $local = $peer.LocalRoot
    $remote = $peer.RemoteRoot.TrimEnd('/')
    $remoteEsc = Escape-MetraDeskBridgeRemoteSingleQuoted -Value $remote
    $inbox = Join-Path $local 'inbox'
    $agentInbox = Join-Path $local 'agent-inbox'

    $null = Invoke-MetraDeskBridgeSsh -Peer $peer -RemoteCommand ("mkdir -p '{0}/outbox' '{0}/inbox'" -f $remoteEsc)

    # List remote outbox files.
    $list = Invoke-MetraDeskBridgeSsh -Peer $peer -RemoteCommand ("ls -1 '{0}/outbox'/*.md 2>/dev/null || true" -f $remoteEsc)
    $pulled = New-Object System.Collections.Generic.List[string]
    # Stdout only; keep lines that look like markdown paths (ignore SSH banners/MOTD on stderr).
    $lines = @(
        $list.Output -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and ($_ -match '\.md$') -and ($_ -notmatch '(?i)No such|Permission denied|Warning:') }
    )
    foreach ($remoteFile in $lines) {
        $name = Split-Path -Leaf $remoteFile
        $dest = Join-Path $inbox $name
        $null = Invoke-MetraDeskBridgeScp -Peer $peer -Source $remoteFile -Destination $dest
        if ($name -match '_agent_') {
            Copy-Item -LiteralPath $dest -Destination (Join-Path $agentInbox $name) -Force
        }
        # Archive on remote so we do not re-pull.
        $remoteFileEsc = Escape-MetraDeskBridgeRemoteSingleQuoted -Value $remoteFile
        $null = Invoke-MetraDeskBridgeSsh -Peer $peer -RemoteCommand ("mkdir -p '{0}/archive'; mv -f '{1}' '{0}/archive/'" -f $remoteEsc, $remoteFileEsc)
        [void]$pulled.Add($name)
    }

    foreach ($sticky in @('CURRENT-operator.md', 'CURRENT-agent.md')) {
        $remoteSticky = '{0}/{1}' -f $remote, $sticky
        $remoteStickyEsc = Escape-MetraDeskBridgeRemoteSingleQuoted -Value $remoteSticky
        $probe = Invoke-MetraDeskBridgeSsh -Peer $peer -RemoteCommand ("test -f '{0}' && echo yes || echo no" -f $remoteStickyEsc)
        if (($probe.Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq 'yes' }).Count -gt 0) {
            # Keep peer sticky as PEER-* so we do not clobber our own CURRENT.
            $peerDest = Join-Path $local ('PEER-' + $sticky)
            $null = Invoke-MetraDeskBridgeScp -Peer $peer -Source $remoteSticky -Destination $peerDest
            [void]$pulled.Add(('PEER-' + $sticky))
        }
    }

    [PSCustomObject]@{
        Ok     = $true
        Peer   = $peer.Name
        Pulled = @($pulled)
        Count  = $pulled.Count
        Inbox  = $inbox
    }
}

function Get-MetraDeskBridgeInbox {
    [CmdletBinding()]
    param(
        [ValidateSet('all', 'operator', 'agent')]
        [string]$Audience = 'all'
    )

    $root = Initialize-MetraDeskBridgeLayout
    $dirs = @((Join-Path $root 'inbox'))
    if ($Audience -eq 'agent' -or $Audience -eq 'all') {
        $dirs += (Join-Path $root 'agent-inbox')
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($d in $dirs) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Filter '*.md' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
            if (-not $seen.Add($f.Name)) { continue }
            $aud = if ($f.Name -match '_agent_') { 'agent' } elseif ($f.Name -match '_operator_') { 'operator' } else { 'unknown' }
            if ($Audience -ne 'all' -and $aud -ne $Audience) { continue }
            $preview = ''
            try {
                $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
                if ($raw -match '(?ms)^---\r?\n.*?\r?\n---\r?\n(.*)$') {
                    $preview = ($Matches[1].Trim() -split "`n" | Select-Object -First 2) -join ' '
                }
            }
            catch { }
            [void]$items.Add([PSCustomObject]@{
                    Name     = $f.Name
                    Audience = $aud
                    Path     = $f.FullName
                    Written  = $f.LastWriteTime
                    Preview  = $preview
                })
        }
    }
    return @($items)
}
