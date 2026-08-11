# Metra Ops local session token (Slice 8). Host issues; Ops validates on non-loopback mutate.
# Authority model: reachability is not apply authority. Mutating desk actions require loopback
# or this Host-issued token (X-Metra-Local-Session). Token file lives under %LOCALAPPDATA%\Metra,
# which is user-profile owned; WriteAllText inherits that ACL (user-only for typical installs).

function Get-MetraOpsLocalSessionTokenPath {
    return Join-Path $env:LOCALAPPDATA 'Metra\ops-local-session.token'
}

function Get-MetraOpsProposalLocalSessionToken {
    param([switch]$AllowMissing)

    $path = Get-MetraOpsLocalSessionTokenPath
    if (Test-Path -LiteralPath $path) {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
    }
    if ($AllowMissing) {
        return ''
    }
    return ''
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
        if (-not [string]::IsNullOrWhiteSpace($existing)) {
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
        return $false
    }
    if (-not (Test-MetraOpsLocalSessionTokenFormat -Value $expected)) {
        return $false
    }

    $a = [System.Text.Encoding]::UTF8.GetBytes($presented)
    $b = [System.Text.Encoding]::UTF8.GetBytes($expected)
    if ($a.Length -ne $b.Length) {
        return $false
    }
    try {
        return [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals($a, $b)
    }
    catch {
        $diff = 0
        for ($i = 0; $i -lt $a.Length; $i++) {
            $diff = $diff -bor ($a[$i] -bxor $b[$i])
        }
        return ($diff -eq 0)
    }
}
