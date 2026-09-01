# Loom storage helpers (self-contained; no Metra imports).

function Get-LoomUtf8NoBomEncoding {
    return [System.Text.UTF8Encoding]::new($false)
}

function Write-LoomAtomicUtf8Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $enc = Get-LoomUtf8NoBomEncoding
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, $enc)
    if (Test-Path -LiteralPath $Path) {
        $bak = "$Path.bak"
        [System.IO.File]::Replace($tmp, $Path, $bak)
        Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
    }
    else {
        [System.IO.File]::Move($tmp, $Path)
    }
}

function Invoke-LoomWithNamedMutex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Script,
        [int]$TimeoutMs = 15000
    )
    $mutexName = "Local\Metra_$Name"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $acquired = $false
    try {
        $acquired = $mutex.WaitOne($TimeoutMs)
        if (-not $acquired) {
            throw "Timed out waiting for mutex $Name (${TimeoutMs}ms)."
        }
        return (& $Script)
    }
    finally {
        if ($acquired) { [void]$mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Get-LoomProp {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            $val = $Object[$Name]
            if ($null -eq $val) { return $Default }
            return $val
        }
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $val = $Object[$key]
                if ($null -eq $val) { return $Default }
                return $val
            }
        }
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        foreach ($p in $Object.PSObject.Properties) {
            if ([string]::Equals($p.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($null -eq $p.Value) { return $Default }
                return $p.Value
            }
        }
        return $Default
    }
    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function Test-LoomPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Root
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $rootFull = [System.IO.Path]::GetFullPath($Root)
    }
    catch { return $false }
    $rootFull = $rootFull.TrimEnd('\', '/')
    if ([string]::Equals($full, $rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}
