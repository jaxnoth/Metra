# Metra Ops local session token (Slice 8). Host issues; Ops validates on non-loopback mutate.

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
        $null = New-Item -ItemType Directory -Path $dir -Force
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
    #>
    param(
        [string]$SessionToken,
        [string]$ExpectedToken
    )

    if ([string]::IsNullOrWhiteSpace($SessionToken)) {
        return $false
    }

    $expected = if (-not [string]::IsNullOrWhiteSpace($ExpectedToken)) {
        $ExpectedToken.Trim()
    }
    else {
        Get-MetraOpsProposalLocalSessionToken -AllowMissing
    }

    if ([string]::IsNullOrWhiteSpace($expected)) {
        return $false
    }

    $a = [System.Text.Encoding]::UTF8.GetBytes($SessionToken.Trim())
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
