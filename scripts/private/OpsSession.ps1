# Metra Ops local session token (Slice 8). Host issues; Ops validates on non-loopback mutate.
# Authority model: reachability is not apply authority. Mutating desk actions require loopback
# or this Host-issued token (X-Metra-Local-Session). Token file lives under %LOCALAPPDATA%\Metra,
# which is user-profile owned; WriteAllText inherits that ACL (user-only for typical installs).

function Get-MetraOpsLocalSessionTokenPath {
    return Join-Path $env:LOCALAPPDATA 'Metra\ops-local-session.token'
}

if ($null -eq (Get-Variable -Name MetraOpsSessionTokenCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:MetraOpsSessionTokenCache = @{
        Token     = $null
        Path      = $null
        Lwt       = [datetime]::MinValue
        CachedUtc = [datetime]::MinValue
        TtlSec    = 30
    }
}

function Clear-MetraOpsLocalSessionTokenCache {
    [CmdletBinding()]
    param()
    $script:MetraOpsSessionTokenCache.Token = $null
    $script:MetraOpsSessionTokenCache.Path = $null
    $script:MetraOpsSessionTokenCache.Lwt = [datetime]::MinValue
    $script:MetraOpsSessionTokenCache.CachedUtc = [datetime]::MinValue
}

function Get-MetraOpsProposalLocalSessionToken {
    param([switch]$AllowMissing)

    $path = Get-MetraOpsLocalSessionTokenPath
    if (-not (Test-Path -LiteralPath $path)) {
        Clear-MetraOpsLocalSessionTokenCache
        if ($AllowMissing) { return '' }
        return ''
    }

    $lwt = [datetime]::MinValue
    try { $lwt = (Get-Item -LiteralPath $path).LastWriteTimeUtc } catch { }

    $cache = $script:MetraOpsSessionTokenCache
    $ageOk = $cache.CachedUtc -ne [datetime]::MinValue -and `
        (([datetime]::UtcNow - $cache.CachedUtc).TotalSeconds -lt [double]$cache.TtlSec)
    if ($ageOk -and $cache.Path -eq $path -and $cache.Lwt -eq $lwt -and
        -not [string]::IsNullOrWhiteSpace([string]$cache.Token)) {
        return [string]$cache.Token
    }

    $token = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
    $script:MetraOpsSessionTokenCache.Token = $token
    $script:MetraOpsSessionTokenCache.Path = $path
    $script:MetraOpsSessionTokenCache.Lwt = $lwt
    $script:MetraOpsSessionTokenCache.CachedUtc = [datetime]::UtcNow
    return $token
}

function Test-MetraOpsLocalSessionTokenFormat {
    <#
    .SYNOPSIS
        True when Value looks like a Host-issued 256-bit hex session token.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value.Trim() -match '^[a-f0-9]{64}$')
}

function Initialize-MetraOpsLocalSessionToken {
    <#
    .SYNOPSIS
        Creates or rotates the Host-issued local session token used for non-loopback propose/request-apply.
    .PARAMETER Rotate
        Always write a new token. Default keeps an existing non-empty token.
    #>
    param(
        [switch]$Rotate,
        [string]$DataDir
    )

    $path = if ([string]::IsNullOrWhiteSpace($DataDir)) {
        Get-MetraOpsLocalSessionTokenPath
    }
    else {
        Join-Path $DataDir 'ops-local-session.token'
    }

    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($dir)
    }

    if (-not $Rotate -and (Test-Path -LiteralPath $path)) {
        $existing = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
        # Reuse only a well-formed 64-hex token; missing/malformed fall through to mint/replace.
        if (Test-MetraOpsLocalSessionTokenFormat -Value $existing) {
            $script:MetraOpsSessionTokenCache.Token = $existing
            $script:MetraOpsSessionTokenCache.Path = $path
            try { $script:MetraOpsSessionTokenCache.Lwt = (Get-Item -LiteralPath $path).LastWriteTimeUtc } catch { }
            $script:MetraOpsSessionTokenCache.CachedUtc = [datetime]::UtcNow
            return [PSCustomObject]@{
                Token   = $existing
                Path    = $path
                Created = $false
            }
        }
    }

    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    $token = -join ($bytes | ForEach-Object { $_.ToString('x2') })
    [System.IO.File]::WriteAllText($path, $token + "`n")
    Clear-MetraOpsLocalSessionTokenCache
    $script:MetraOpsSessionTokenCache.Token = $token
    $script:MetraOpsSessionTokenCache.Path = $path
    try { $script:MetraOpsSessionTokenCache.Lwt = (Get-Item -LiteralPath $path).LastWriteTimeUtc } catch { }
    $script:MetraOpsSessionTokenCache.CachedUtc = [datetime]::UtcNow

    return [PSCustomObject]@{
        Token   = $token
        Path    = $path
        Created = $true
    }
}

function Test-MetraOpsLocalSessionToken {
    <#
    .SYNOPSIS
        True when the presented token matches the Host-issued local session marker.
    .DESCRIPTION
        Fail-closed: missing/empty/malformed tokens are false. Comparison is constant-time
        when CryptographicOperations.FixedTimeEquals is available.
    #>
    param(
        [string]$SessionToken,
        [string]$ExpectedToken
    )

    if ([string]::IsNullOrWhiteSpace($SessionToken)) {
        return $false
    }

    $presented = $SessionToken.Trim()
    if (-not (Test-MetraOpsLocalSessionTokenFormat -Value $presented)) {
        return $false
    }

    $expected = if (-not [string]::IsNullOrWhiteSpace($ExpectedToken)) {
        $ExpectedToken
    }
    else {
        Get-MetraOpsProposalLocalSessionToken -AllowMissing
    }
    $expected = if ($null -eq $expected) { '' } else { $expected.Trim() }

    if ([string]::IsNullOrWhiteSpace($expected)) {
        Clear-MetraOpsLocalSessionTokenCache
        return $false
    }
    if (-not (Test-MetraOpsLocalSessionTokenFormat -Value $expected)) {
        Clear-MetraOpsLocalSessionTokenCache
        return $false
    }

    $a = [System.Text.Encoding]::UTF8.GetBytes($presented)
    $b = [System.Text.Encoding]::UTF8.GetBytes($expected)
    if ($a.Length -ne $b.Length) {
        return $false
    }
    $ok = $false
    try {
        $ok = [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals($a, $b)
    }
    catch {
        $diff = 0
        for ($i = 0; $i -lt $a.Length; $i++) {
            $diff = $diff -bor ($a[$i] -bxor $b[$i])
        }
        $ok = ($diff -eq 0)
    }
    if (-not $ok) {
        Clear-MetraOpsLocalSessionTokenCache
    }
    return $ok
}
