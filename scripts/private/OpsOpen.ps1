# Open-in-editor for the Ops desk. The browser cannot launch processes, so the desk
# process (already running in the operator session) does it. Paths are constrained to
# configured Metra roots; this never writes files - Host still owns disk writes.

function Test-MetraOpsRequestIsSameMachine {
    <#
    .SYNOPSIS
        True when the caller is this machine (loopback or one of its own addresses).
    .DESCRIPTION
        Launching an editor is operator-desktop reach, so a MagicDNS URL used on the operator
        machine still counts as local. A different device does not.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Request)

    try {
        $addr = $Request.RemoteEndPoint.Address
        if ([System.Net.IPAddress]::IsLoopback($addr)) { return $true }
        $mine = @([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()))
        foreach ($ip in $mine) {
            if ($ip.Equals($addr)) { return $true }
        }
        return $false
    }
    catch {
        return $false
    }
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

function Resolve-MetraOpsEditor {
    <#
    .SYNOPSIS
        Resolves the editor Ops should use for Open in editor.
    .DESCRIPTION
        Preference values: auto (Cursor, then VS Code, then Windows default), cursor, code,
        system (Windows default handler), or a full executable path.
    #>
    [CmdletBinding()]
    param(
        [string]$Preference = 'auto',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $pref = if ([string]::IsNullOrWhiteSpace($Preference)) { 'auto' } else { $Preference.Trim() }

    if ($pref -notin @('auto', 'cursor', 'code', 'system')) {
        if (Test-Path -LiteralPath $pref) {
            return [PSCustomObject]@{
                Preference = $pref
                Kind       = 'custom'
                Exe        = (Resolve-Path -LiteralPath $pref).Path
                Label      = [System.IO.Path]::GetFileNameWithoutExtension($pref)
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

    $allowed = @()
    try {
        $allowed += @(Get-MetraRoots -IncludeMissing | ForEach-Object { [string]$_.Path })
    }
    catch { }
    if ($MetraRoot) { $allowed += [string]$MetraRoot }

    foreach ($rootPath in @($allowed | Where-Object { $_ })) {
        $rootFull = $null
        try { $rootFull = [System.IO.Path]::GetFullPath($rootPath) } catch { continue }
        $rootFull = $rootFull.TrimEnd('\', '/')
        if (-not $rootFull) { continue }
        if ($full -eq $rootFull) {
            return [PSCustomObject]@{ Ok = $true; Path = $full; Reason = $null }
        }
        if ($full.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
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

    return [PSCustomObject]@{
        ok      = $true
        path    = $resolved.Path
        editor  = [string]$editor.Label
        kind    = [string]$editor.Kind
        message = "Opened $($resolved.Path) in $($editor.Label)."
    }
}
