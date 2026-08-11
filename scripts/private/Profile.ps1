# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Get-MetraProfileFileMap {
    <#
    .SYNOPSIS
        Relative paths that make up an operator profile pack (same layout as profiles/sample).
    #>
    return @(
        'metra.config.json',
        'projects.local.json',
        '.cursor/rules/metra-persona.local.mdc',
        '.cursor/rules/metra-humor.local.mdc',
        '.cursor/rules/metra-teaching-gentle.local.mdc',
        '.cursor/rules/metra-learned.local.mdc',
        'docs/operator-contract.json',
        'docs/decision-registry.json'
    )
}

function Resolve-MetraProfileSourceDir {
    <#
    .SYNOPSIS
        Resolves a profile pack path to an unpacked directory (extracts zip to temp when needed).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $expanded = [System.Environment]::ExpandEnvironmentVariables($Path)
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path (Get-Location).Path $expanded
    }
    $full = [System.IO.Path]::GetFullPath($expanded)

    if (-not (Test-Path -LiteralPath $full)) {
        throw "Profile path not found: $full"
    }

    $item = Get-Item -LiteralPath $full
    if ($item.PSIsContainer) {
        return [PSCustomObject]@{
            Directory = $item.FullName
            TempDir   = $null
            Source    = $item.FullName
            IsZip     = $false
        }
    }

    if ($item.Extension -ne '.zip') {
        throw "Profile path must be a directory or .zip file: $full"
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-profile-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Expand-Archive -LiteralPath $item.FullName -DestinationPath $tempRoot -Force

    $manifest = Get-ChildItem -LiteralPath $tempRoot -Filter 'metra-profile.json' -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $manifest) {
        $manifest = Get-ChildItem -LiteralPath $tempRoot -Filter 'meta-profile.json' -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    $dir = if ($manifest) {
        $manifest.Directory.FullName
    }
    else {
        $children = @(Get-ChildItem -LiteralPath $tempRoot -Directory)
        $childDir = if ($children.Count -eq 1) { $children[0].FullName } else { $null }
        if ($childDir -and (
                (Test-Path (Join-Path $childDir 'metra-profile.json')) -or
                (Test-Path (Join-Path $childDir 'meta-profile.json'))
            )) {
            $childDir
        }
        else {
            $tempRoot
        }
    }

    return [PSCustomObject]@{
        Directory = $dir
        TempDir   = $tempRoot
        Source    = $item.FullName
        IsZip     = $true
    }
}

function Get-MetraProfileLogicalName {
    param([Parameter(Mandatory)][string]$RelativePath)

    $norm = ($RelativePath -replace '\\', '/').Trim('/')
    $leaf = Split-Path -Leaf $norm
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $norm }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    if ([string]::IsNullOrWhiteSpace($base)) { return $leaf }
    return $base
}

function Get-MetraProfileFileSha256Hex {
    param([Parameter(Mandatory)][string]$Path)

    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    return $hash.Hash.ToLowerInvariant()
}

function Get-MetraProfileStatus {
    <#
    .SYNOPSIS
        Deterministic fingerprint of the current HQ profile pack (content-based).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $fileMap = @(Get-MetraProfileFileMap)
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($rel in $fileMap) {
        $relNorm = ($rel -replace '\\', '/')
        $full = Join-Path $MetraRoot ($relNorm -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $info = Get-Item -LiteralPath $full
        $hex = Get-MetraProfileFileSha256Hex -Path $info.FullName
        [void]$entries.Add([PSCustomObject]@{
                logicalName  = (Get-MetraProfileLogicalName -RelativePath $relNorm)
                relativePath = $relNorm
                writeUtc     = $info.LastWriteTimeUtc.ToString('o')
                sizeBytes    = [long]$info.Length
                hash         = "sha256:$hex"
            })
    }

    $stable = @($entries | Sort-Object relativePath)
    $hashInput = ($stable | ForEach-Object { "$($_.relativePath)|$($_.hash)" }) -join "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($hashInput)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    }
    finally {
        $sha.Dispose()
    }

    $maxWrite = $null
    if ($stable.Count -gt 0) {
        $maxWrite = ($stable | Sort-Object writeUtc -Descending | Select-Object -First 1).writeUtc
    }

    return [PSCustomObject]@{
        ok                 = $true
        profilePackVersion = 1
        contentHash        = "sha256:$digest"
        maxWriteUtc        = $maxWrite
        fileCount          = $stable.Count
        files              = $stable
    }
}

function Get-MetraProfileSyncStatePath {
    param([string]$MetraRoot = (Get-MetraRoot))
    return Join-Path $MetraRoot 'docs\profile-sync.local.json'
}

function Get-MetraProfileSyncTokenHashPath {
    param([string]$DataDir)

    if (-not [string]::IsNullOrWhiteSpace($DataDir)) {
        return Join-Path $DataDir 'profile-sync-token.hash'
    }
    return Join-Path $env:LOCALAPPDATA 'Metra\profile-sync-token.hash'
}

function Get-MetraProfileSyncTokenSha256Hex {
    param([Parameter(Mandatory)][string]$Token)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Token.Trim())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha.Dispose()
    }
}

function Initialize-MetraProfileSyncToken {
    <#
    .SYNOPSIS
        Issues a long-lived profile-sync bearer. Host stores only the SHA256 hash.
    #>
    [CmdletBinding()]
    param(
        [switch]$Rotate,
        [string]$DataDir
    )

    $path = Get-MetraProfileSyncTokenHashPath -DataDir $DataDir
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    if (-not $Rotate -and (Test-Path -LiteralPath $path)) {
        $existingHash = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
        if (-not [string]::IsNullOrWhiteSpace($existingHash)) {
            return [PSCustomObject]@{
                Token     = $null
                TokenHash = $existingHash
                Path      = $path
                Created   = $false
                HasToken  = $true
                Message   = 'A sync token already exists. Pass -Rotate (or Rotate in the API) to issue a new one. The previous plaintext is not recoverable.'
            }
        }
    }

    $rawBytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($rawBytes)
    }
    finally {
        $rng.Dispose()
    }
    $token = -join ($rawBytes | ForEach-Object { $_.ToString('x2') })
    $tokenHash = Get-MetraProfileSyncTokenSha256Hex -Token $token
    [System.IO.File]::WriteAllText($path, $tokenHash + "`n")

    return [PSCustomObject]@{
        Token     = $token
        TokenHash = $tokenHash
        Path      = $path
        Created   = $true
        HasToken  = $true
        Message   = 'Copy this token to the satellite docs/profile-sync.local.json as syncToken. It is shown once.'
        Header    = 'X-Metra-Profile-Sync'
    }
}

function Test-MetraProfileSyncToken {
    param(
        [string]$SyncToken,
        [string]$DataDir
    )

    if ([string]::IsNullOrWhiteSpace($SyncToken)) {
        return $false
    }

    $path = Get-MetraProfileSyncTokenHashPath -DataDir $DataDir
    if (-not (Test-Path -LiteralPath $path)) {
        return $false
    }
    $expected = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
    if ([string]::IsNullOrWhiteSpace($expected)) {
        return $false
    }

    $presented = Get-MetraProfileSyncTokenSha256Hex -Token $SyncToken
    $a = [System.Text.Encoding]::UTF8.GetBytes($presented)
    $b = [System.Text.Encoding]::UTF8.GetBytes($expected.ToLowerInvariant())
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

function Test-MetraOpsProfileSyncAuthorized {
    <#
    .SYNOPSIS
        True when same-machine, local-session, or profile-sync bearer authorizes profile status/export.
    #>
    param(
        [Parameter(Mandatory)]$Request
    )

    if (Test-MetraOpsRequestIsSameMachine -Request $Request) {
        return $true
    }

    $sessionToken = ''
    try { $sessionToken = [string]$Request.Headers['X-Metra-Local-Session'] } catch { }
    if (Test-MetraOpsLocalSessionToken -SessionToken $sessionToken) {
        return $true
    }

    $syncToken = ''
    try { $syncToken = [string]$Request.Headers['X-Metra-Profile-Sync'] } catch { }
    if (Test-MetraProfileSyncToken -SyncToken $syncToken) {
        return $true
    }

    return $false
}

function Get-MetraProfileSyncLocalState {
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Get-MetraProfileSyncStatePath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{
            Path = $path
            Data = $null
        }
    }
    try {
        $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        return [PSCustomObject]@{
            Path = $path
            Data = $data
        }
    }
    catch {
        return [PSCustomObject]@{
            Path = $path
            Data = $null
        }
    }
}

function Save-MetraProfileSyncLocalState {
    param(
        [Parameter(Mandatory)]$State,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $path = Get-MetraProfileSyncStatePath -MetraRoot $MetraRoot
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    ($State | ConvertTo-Json -Depth 6) | Set-Content -Path $path -Encoding utf8
    return $path
}

function Set-MetraProfileSyncClientToken {
    <#
    .SYNOPSIS
        Writes or updates syncToken in docs/profile-sync.local.json (satellite client).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SyncToken,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $trimmed = $SyncToken.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    $local = Get-MetraProfileSyncLocalState -MetraRoot $MetraRoot
    $state = [ordered]@{}
    if ($null -ne $local.Data) {
        foreach ($p in @($local.Data.PSObject.Properties)) {
            if ($null -eq $p -or [string]::IsNullOrWhiteSpace([string]$p.Name)) { continue }
            $state[[string]$p.Name] = $p.Value
        }
    }
    $state['syncToken'] = $trimmed
    $state['updatedUtc'] = (Get-Date).ToUniversalTime().ToString('o')
    $path = Save-MetraProfileSyncLocalState -State ([pscustomobject]$state) -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        Path      = $path
        SyncToken = $trimmed
    }
}

function Resolve-MetraProfileOpsBaseUrl {
    param(
        [string]$OpsBaseUrl,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $resolved = Get-MetraProfileOpsBaseUrlOrNull -OpsBaseUrl $OpsBaseUrl -MetraRoot $MetraRoot
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        throw 'Ops base URL not set. Pass -OpsBaseUrl, set METRA_OPS_BASE_URL, metra.config.json opsBaseUrl, or docs/profile-sync.local.json.'
    }
    return $resolved
}

function Get-MetraProfileOpsBaseUrlOrNull {
    <#
    .SYNOPSIS
        Soft OpsBaseUrl resolve for Desk Mode. Returns $null when no HQ URL is configured.
    #>
    param(
        [string]$OpsBaseUrl,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if (-not [string]::IsNullOrWhiteSpace($OpsBaseUrl)) {
        return $OpsBaseUrl.Trim().TrimEnd('/')
    }
    $envUrl = [string]$env:METRA_OPS_BASE_URL
    if (-not [string]::IsNullOrWhiteSpace($envUrl)) {
        return $envUrl.Trim().TrimEnd('/')
    }

    $configPath = Join-Path $MetraRoot 'metra.config.json'
    if (Test-Path -LiteralPath $configPath) {
        try {
            $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $fromCfg = [string](Get-MetraProp -Object $cfg -Name 'opsBaseUrl' -Default '')
            if ([string]::IsNullOrWhiteSpace($fromCfg)) {
                $ops = Get-MetraProp -Object $cfg -Name 'ops' -Default $null
                if ($ops) {
                    $fromCfg = [string](Get-MetraProp -Object $ops -Name 'baseUrl' -Default '')
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($fromCfg)) {
                return $fromCfg.Trim().TrimEnd('/')
            }
        }
        catch { }
    }

    $local = Get-MetraProfileSyncLocalState -MetraRoot $MetraRoot
    if ($local.Data) {
        $fromState = [string](Get-MetraProp -Object $local.Data -Name 'opsBaseUrl' -Default '')
        if ([string]::IsNullOrWhiteSpace($fromState)) {
            $fromState = [string](Get-MetraProp -Object $local.Data -Name 'lastSourceUrl' -Default '')
        }
        if (-not [string]::IsNullOrWhiteSpace($fromState)) {
            return $fromState.Trim().TrimEnd('/')
        }
    }

    return $null
}

function Set-MetraConfiguredOpsBaseUrl {
    <#
    .SYNOPSIS
        Writes opsBaseUrl into metra.config.json (and clears an empty value).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$OpsBaseUrl,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $configPath = Join-Path $MetraRoot 'metra.config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Missing $configPath - run setup to seed config first."
    }
    $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $url = ([string]$OpsBaseUrl).Trim().TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($url)) {
        if ($null -ne (Get-MetraProp -Object $cfg -Name 'opsBaseUrl' -Default $null)) {
            $cfg.PSObject.Properties.Remove('opsBaseUrl')
        }
    }
    else {
        if ($cfg.PSObject.Properties.Name -contains 'opsBaseUrl') {
            $cfg.opsBaseUrl = $url
        }
        else {
            $cfg | Add-Member -NotePropertyName opsBaseUrl -NotePropertyValue $url -Force
        }
    }
    $json = ($cfg | ConvertTo-Json -Depth 20)
    [System.IO.File]::WriteAllText($configPath, $json + "`r`n", (Get-MetraUtf8NoBomEncoding))
    return [PSCustomObject]@{
        Path       = $configPath
        OpsBaseUrl = $(if ([string]::IsNullOrWhiteSpace($url)) { $null } else { $url })
    }
}

function Test-MetraOpsBaseUrlIsLocal {
    <#
    .SYNOPSIS
        True when OpsBaseUrl points at this machine (loopback, friendly metra host, or this Tailscale identity).
    #>
    param(
        [Parameter(Mandatory)][string]$OpsBaseUrl
    )

    $raw = [string]$OpsBaseUrl
    if ([string]::IsNullOrWhiteSpace($raw)) { return $true }

    $uri = $null
    try {
        $candidate = $raw.Trim()
        if ($candidate -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
            $candidate = 'http://' + $candidate
        }
        $uri = [uri]$candidate
    }
    catch {
        return $false
    }

    $hostName = [string]$uri.Host
    if ([string]::IsNullOrWhiteSpace($hostName)) { return $false }
    $hostLower = $hostName.Trim().ToLowerInvariant()

    if ($hostLower -in @('localhost', '127.0.0.1', '::1', 'metra')) {
        return $true
    }

    try {
        $dns = [string](Get-MetraOpsTailscaleDnsName)
        if (-not [string]::IsNullOrWhiteSpace($dns) -and $hostLower -eq $dns.Trim().ToLowerInvariant()) {
            return $true
        }
    }
    catch { }

    try {
        $ip = [string](Get-MetraOpsTailscaleIPv4)
        if (-not [string]::IsNullOrWhiteSpace($ip) -and $hostLower -eq $ip.Trim().ToLowerInvariant()) {
            return $true
        }
    }
    catch { }

    return $false
}

function Get-MetraDeskMode {
    <#
    .SYNOPSIS
        Desk Mode A/B/C: Standalone | HqClient | ForceLocal. Owns ForceLocal decision-making.
    #>
    [CmdletBinding()]
    param(
        [switch]$ForceLocal,
        [string]$OpsBaseUrl,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $force = [bool]$ForceLocal
    if (-not $force) {
        $envForce = [string]$env:METRA_OPS_FORCE_LOCAL
        if ($envForce -match '^(?i)(1|true|yes)$') { $force = $true }
    }
    if ($force) { return 'ForceLocal' }

    $resolved = Get-MetraProfileOpsBaseUrlOrNull -OpsBaseUrl $OpsBaseUrl -MetraRoot $MetraRoot
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        return 'Standalone'
    }
    if (Test-MetraOpsBaseUrlIsLocal -OpsBaseUrl $resolved) {
        return 'Standalone'
    }
    return 'HqClient'
}

function Assert-MetraOpsMayStartLocally {
    <#
    .SYNOPSIS
        Refuse starting a local Ops desk/host when Desk Mode is HQ Client (Mode B).
    #>
    [CmdletBinding()]
    param(
        [switch]$ForceLocal,
        [string]$OpsBaseUrl,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $mode = Get-MetraDeskMode -ForceLocal:$ForceLocal -OpsBaseUrl $OpsBaseUrl -MetraRoot $MetraRoot
    if ($mode -ne 'HqClient') { return }

    $hq = Get-MetraProfileOpsBaseUrlOrNull -OpsBaseUrl $OpsBaseUrl -MetraRoot $MetraRoot
    if ([string]::IsNullOrWhiteSpace($hq)) { $hq = '(unknown)' }

    $msg = @"
Metra detected a remote Ask host.

Configured HQ:
  $hq

Local Ops hosting is disabled on satellite devices.

Use:
  .\metra.ps1 ask sessions

or intentionally override:

  .\metra.ps1 ops -ForceLocal

This creates a second Ask host and may result in journal divergence.
"@
    throw $msg.TrimEnd()
}

function Resolve-MetraProfileSyncToken {
    param(
        [string]$SyncToken,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if (-not [string]::IsNullOrWhiteSpace($SyncToken)) {
        return $SyncToken.Trim()
    }
    $envTok = [string]$env:METRA_PROFILE_SYNC_TOKEN
    if (-not [string]::IsNullOrWhiteSpace($envTok)) {
        return $envTok.Trim()
    }
    $local = Get-MetraProfileSyncLocalState -MetraRoot $MetraRoot
    if ($local.Data) {
        $fromState = [string](Get-MetraProp -Object $local.Data -Name 'syncToken' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($fromState)) {
            return $fromState.Trim()
        }
    }
    return ''
}

function ConvertTo-MetraProfileManifestRelativePaths {
    param([object[]]$Candidates)

    $out = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Candidates)) {
        if ($null -eq $item) { continue }
        if ($item -is [string]) {
            $s = [string]$item
            if (-not [string]::IsNullOrWhiteSpace($s)) {
                [void]$out.Add(($s -replace '\\', '/'))
            }
            continue
        }
        $rel = [string](Get-MetraProp -Object $item -Name 'relativePath' -Default '')
        if ([string]::IsNullOrWhiteSpace($rel)) {
            $rel = [string](Get-MetraProp -Object $item -Name 'RelativePath' -Default '')
        }
        if (-not [string]::IsNullOrWhiteSpace($rel)) {
            [void]$out.Add(($rel -replace '\\', '/'))
        }
    }
    return @($out.ToArray())
}

