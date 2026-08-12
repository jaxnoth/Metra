# Open-in-editor for the Ops desk. The browser cannot launch processes, so the desk
# process (already running in the operator session) does it. Paths are constrained to
# configured Metra roots; this never writes files - Host still owns disk writes.

function Test-MetraOpsRequestLooksProxiedThroughServe {
    <#
    .SYNOPSIS
        True when request headers indicate Tailscale Serve (or similar) proxying.
    .DESCRIPTION
        Request origin may appear loopback when proxied through Tailscale Serve.
        Treat Serve-header requests as remote for authorization purposes unless
        identity (session) or this-machine client IP is proven separately.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Request)

    try {
        $headers = $Request.Headers
        foreach ($name in @(
                'Tailscale-User-Login',
                'Tailscale-User-Name',
                'Tailscale-Headers-Info'
            )) {
            $v = [string]$headers[$name]
            if (-not [string]::IsNullOrWhiteSpace($v)) { return $true }
        }

        foreach ($fwdName in @('X-Forwarded-For', 'X-Real-IP')) {
            $raw = [string]$headers[$fwdName]
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $first = ($raw -split ',')[0].Trim()
            if ([string]::IsNullOrWhiteSpace($first)) { continue }
            try {
                $fwdAddr = [System.Net.IPAddress]::Parse($first)
                if (-not [System.Net.IPAddress]::IsLoopback($fwdAddr)) { return $true }
            }
            catch {
                # Non-IP forwarded value still means a proxy sat in front.
                return $true
            }
        }
    }
    catch { }
    return $false
}

function Get-MetraOpsRequestForwardedClientAddress {
    <#
    .SYNOPSIS
        Client IP from X-Forwarded-For / X-Real-IP only (no RemoteEndPoint fallback).
    .DESCRIPTION
        Tailscale Serve connects to loopback, so RemoteEndPoint is useless for peer vs HQ.
        Missing forwarded headers means unknown client - callers must fail closed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Request)

    try {
        $headers = $Request.Headers
        foreach ($fwdName in @('X-Forwarded-For', 'X-Real-IP')) {
            $raw = [string]$headers[$fwdName]
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $first = ($raw -split ',')[0].Trim()
            if ([string]::IsNullOrWhiteSpace($first)) { continue }
            try {
                return [System.Net.IPAddress]::Parse($first)
            }
            catch { }
        }
    }
    catch { }
    return $null
}

function Test-MetraOpsIpAddressIsThisMachine {
    <#
    .SYNOPSIS
        True when Address is loopback or one of this host's IPv4/IPv6 addresses.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Net.IPAddress]$Address)

    if ([System.Net.IPAddress]::IsLoopback($Address)) { return $true }
    try {
        $mine = @([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()))
        foreach ($ip in $mine) {
            if ($ip.Equals($Address)) { return $true }
        }
    }
    catch { }
    return $false
}

function Test-MetraOpsRequestIsSameMachine {
    <#
    .SYNOPSIS
        True when the caller is this machine (session identity, loopback, or own address).
    .DESCRIPTION
        Order: validated Host-issued X-Metra-Local-Session (works through Serve), then
        Serve client IP owned by this host (HQ MagicDNS without hash), then direct
        loopback / own RemoteEndPoint. Bare Serve from a peer node stays false.
        Transport location alone does not define authority - request identity does.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Request)

    try {
        # Identity signal (stronger than IP ownership for MagicDNS on this host).
        $sessionToken = ''
        try { $sessionToken = [string]$Request.Headers['X-Metra-Local-Session'] } catch { }
        if (Test-MetraOpsLocalSessionToken -SessionToken $sessionToken) {
            return $true
        }

        if (Test-MetraOpsRequestLooksProxiedThroughServe -Request $Request) {
            # HQ browser through Serve: forwarded client IP is this machine's Tailscale address.
            # Do not trust RemoteEndPoint - Serve always connects from loopback.
            $client = Get-MetraOpsRequestForwardedClientAddress -Request $Request
            if ($null -ne $client -and (Test-MetraOpsIpAddressIsThisMachine -Address $client)) {
                return $true
            }
            return $false
        }

        $addr = $Request.RemoteEndPoint.Address
        if ([System.Net.IPAddress]::IsLoopback($addr)) { return $true }

        return Test-MetraOpsIpAddressIsThisMachine -Address $addr
    }
    catch {
        return $false
    }
}

function Test-MetraPathWithinRoot {
    <#
    .SYNOPSIS
        True when Path is the root folder itself or a descendant of Root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }

    $full = $null
    $rootFull = $null
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $rootFull = [System.IO.Path]::GetFullPath($Root)
    }
    catch {
        return $false
    }

    $rootFull = $rootFull.TrimEnd('\', '/')
    if (-not $rootFull) { return $false }
    if ([string]::Equals($full, $rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    return $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-MetraEditorCandidatePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('cursor', 'code')][string]$Editor)

    $local = [Environment]::GetFolderPath('LocalApplicationData')
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')

    if ($Editor -eq 'cursor') {
        return @(
            (Join-Path $local 'Programs\cursor\Cursor.exe'),
            (Join-Path $local 'Programs\Cursor\Cursor.exe'),
            (Join-Path $pf 'Cursor\Cursor.exe'),
            (Join-Path $pf86 'Cursor\Cursor.exe')
        )
    }
    return @(
        (Join-Path $local 'Programs\Microsoft VS Code\Code.exe'),
        (Join-Path $pf 'Microsoft VS Code\Code.exe'),
        (Join-Path $pf86 'Microsoft VS Code\Code.exe')
    )
}

function Find-MetraEditorExecutable {
    <#
    .SYNOPSIS
        Locates Cursor or VS Code on this machine (PATH launcher first, then install paths).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('cursor', 'code')][string]$Editor)

    # GUI executable first - the PATH shim is a .cmd and flashes a console window.
    foreach ($candidate in @(Get-MetraEditorCandidatePaths -Editor $Editor)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return [string]$candidate }
    }

    foreach ($cmdName in @("$Editor.exe", "$Editor.cmd", $Editor)) {
        try {
            $cmd = Get-Command -Name $cmdName -CommandType Application -ErrorAction Stop |
                Select-Object -First 1
            if ($cmd -and $cmd.Source) { return [string]$cmd.Source }
        }
        catch { }
    }
    return $null
}

function Test-MetraOpsEditorExecutablePath {
    <#
    .SYNOPSIS
        True when Path is an existing .exe / .cmd / .bat file (not a folder or other path).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        return ($item -is [System.IO.FileInfo] -and $item.Extension -match '^\.(exe|cmd|bat)$')
    }
    catch {
        return $false
    }
}

function Resolve-MetraOpsEditor {
    <#
    .SYNOPSIS
        Resolves the editor Ops should use for Open in editor.
    .DESCRIPTION
        Preference values: auto (Cursor, then VS Code, then Windows default), cursor, code,
        system (Windows default handler), or a full executable path (.exe / .cmd / .bat).
        editorCommand may be a custom executable path intentionally - not limited to
        cursor | code | system. A missing or non-executable custom path falls back to
        Windows default; Open still means "take me there," not "validate my editor configuration."
    #>
    [CmdletBinding()]
    param(
        [string]$Preference = 'auto',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $pref = if ([string]::IsNullOrWhiteSpace($Preference)) { 'auto' } else { $Preference.Trim() }

    if ($pref -notin @('auto', 'cursor', 'code', 'system')) {
        if (Test-MetraOpsEditorExecutablePath -Path $pref) {
            $exe = (Resolve-Path -LiteralPath $pref).Path
            return [PSCustomObject]@{
                Preference = $pref
                Kind       = 'custom'
                Exe        = $exe
                Label      = [System.IO.Path]::GetFileNameWithoutExtension($exe)
                Available  = $true
            }
        }
        return [PSCustomObject]@{
            Preference = $pref
            Kind       = 'system'
            Exe        = $null
            Label      = 'Windows default (configured editor not found)'
            Available  = $true
        }
    }

    if ($pref -eq 'system') {
        return [PSCustomObject]@{
            Preference = 'system'
            Kind       = 'system'
            Exe        = $null
            Label      = 'Windows default'
            Available  = $true
        }
    }

    if ($pref -in @('auto', 'cursor')) {
        $cursor = Find-MetraEditorExecutable -Editor cursor
        if ($cursor) {
            return [PSCustomObject]@{
                Preference = $pref
                Kind       = 'cursor'
                Exe        = $cursor
                Label      = 'Cursor'
                Available  = $true
            }
        }
        if ($pref -eq 'cursor') {
            return [PSCustomObject]@{
                Preference = 'cursor'
                Kind       = 'system'
                Exe        = $null
                Label      = 'Windows default (Cursor not found)'
                Available  = $true
            }
        }
    }

    if ($pref -in @('auto', 'code')) {
        $code = Find-MetraEditorExecutable -Editor code
        if ($code) {
            return [PSCustomObject]@{
                Preference = $pref
                Kind       = 'code'
                Exe        = $code
                Label      = 'VS Code'
                Available  = $true
            }
        }
    }

    return [PSCustomObject]@{
        Preference = $pref
        Kind       = 'system'
        Exe        = $null
        Label      = 'Windows default'
        Available  = $true
    }
}

function Resolve-MetraOpsOpenPath {
    <#
    .SYNOPSIS
        Validates a requested open path against configured roots and the Metra home.
    .DESCRIPTION
        Only existing directories inside a configured root (or the Metra checkout) may be
        opened. Keeps a desk button from becoming an arbitrary process launcher.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [PSCustomObject]@{ Ok = $false; Path = $null; Reason = 'path required' }
    }

    $full = $null
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return [PSCustomObject]@{ Ok = $false; Path = $null; Reason = 'path is not a valid filesystem path' }
    }

    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        return [PSCustomObject]@{ Ok = $false; Path = $full; Reason = 'path is not an existing folder' }
    }
    $full = (Resolve-Path -LiteralPath $full).Path

    $allowed = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($root in @(Get-MetraRoots -IncludeMissing)) {
            try {
                $rootPath = [string](Get-MetraProp -Object $root -Name 'Path' -Default '')
                if ([string]::IsNullOrWhiteSpace($rootPath)) { continue }
                [void]$allowed.Add([System.IO.Path]::GetFullPath($rootPath))
            }
            catch {
                continue
            }
        }
    }
    catch { }
    if (-not [string]::IsNullOrWhiteSpace($MetraRoot)) {
        try {
            [void]$allowed.Add([System.IO.Path]::GetFullPath([string]$MetraRoot))
        }
        catch { }
    }

    foreach ($rootPath in @($allowed)) {
        if (Test-MetraPathWithinRoot -Path $full -Root $rootPath) {
            return [PSCustomObject]@{ Ok = $true; Path = $full; Reason = $null }
        }
    }

    return [PSCustomObject]@{
        Ok     = $false
        Path   = $full
        Reason = 'path is outside every configured Metra root'
    }
}

function Invoke-MetraOpsOpenInEditor {
    <#
    .SYNOPSIS
        Opens a project folder in the operator's editor from the Ops desk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $resolved = Resolve-MetraOpsOpenPath -Path $Path -MetraRoot $MetraRoot
    if (-not $resolved.Ok) {
        throw $resolved.Reason
    }

    $prefs = Get-MetraDeskPreferences -MetraRoot $MetraRoot
    $preference = [string](Get-MetraProp -Object $prefs -Name 'editorCommand' -Default 'auto')
    $editor = Resolve-MetraOpsEditor -Preference $preference -MetraRoot $MetraRoot

    try {
        if ($editor.Exe) {
            $startArgs = @{
                FilePath     = $editor.Exe
                ArgumentList = @($resolved.Path)
                ErrorAction  = 'Stop'
            }
            if ([System.IO.Path]::GetExtension($editor.Exe) -in @('.cmd', '.bat')) {
                $startArgs['WindowStyle'] = 'Hidden'
            }
            Start-Process @startArgs | Out-Null
        }
        else {
            Start-Process -FilePath 'explorer.exe' -ArgumentList @($resolved.Path) -ErrorAction Stop | Out-Null
        }
    }
    catch {
        Write-MetraOpsHostLog "Editor launch failed for '$($resolved.Path)' - $($_.Exception.Message)" 'warn'
        throw
    }

    Write-MetraOpsHostLog "Opened path '$($resolved.Path)' in $($editor.Label)"
    return [PSCustomObject]@{
        ok      = $true
        path    = $resolved.Path
        editor  = [string]$editor.Label
        kind    = [string]$editor.Kind
        message = "Opened $($resolved.Path) in $($editor.Label)."
    }
}
