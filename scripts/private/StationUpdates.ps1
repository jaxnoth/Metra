# Metra Station release discovery / install / update (TicketTracker, Codex, ...).
# Loaded with other private scripts. Wired into Get-MetraProductUpdates / apply jobs.

function Get-MetraStationUpdatesPrefsPath {
    Join-Path $env:LOCALAPPDATA 'Metra\updates-prefs.local.json'
}

function Get-MetraStationLockPath {
    param([Parameter(Mandatory)][string]$StationId)
    $dir = Join-Path $env:LOCALAPPDATA 'Metra\locks'
    if (-not (Test-Path -LiteralPath $dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    Join-Path $dir ("station-{0}-update.lock" -f $StationId)
}

function Read-MetraStationUpdatesPrefs {
    [CmdletBinding()]
    param([string]$Path = (Get-MetraStationUpdatesPrefsPath))

    $prefs = [PSCustomObject]@{
        autoUpdateStations = $false
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $prefs }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $prefs.autoUpdateStations = [bool](Get-MetraProp -Object $raw -Name 'autoUpdateStations' -Default $false)
    }
    catch { }
    return $prefs
}

function Write-MetraStationUpdatesPrefs {
    [CmdletBinding()]
    param(
        [bool]$AutoUpdateStations,
        [string]$Path = (Get-MetraStationUpdatesPrefsPath)
    )

    $payload = [PSCustomObject]@{
        autoUpdateStations = [bool]$AutoUpdateStations
        updatedAt          = [datetime]::UtcNow.ToString('o')
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $json = ($payload | ConvertTo-Json -Depth 4) + "`r`n"
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
    return $payload
}

function Get-MetraWorkRootPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    try {
        $roots = @(Get-MetraRoots -IncludeMissing | Where-Object { $_.Primary })
        if ($roots.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$roots[0].Path)) {
            return [string]$roots[0].Path
        }
    }
    catch { }
    # Fallback: parent of Metra checkout (typical .. from _meta / Metra).
    return (Resolve-Path -LiteralPath (Join-Path $MetraRoot '..')).Path
}

function Get-MetraGitHubApiHeaders {
    [CmdletBinding()]
    param()

    $token = [string]$env:GH_TOKEN
    if ([string]::IsNullOrWhiteSpace($token)) { $token = [string]$env:GITHUB_TOKEN }
    if ([string]::IsNullOrWhiteSpace($token)) {
        try {
            $gh = Get-Command gh -ErrorAction SilentlyContinue
            if ($gh) {
                $token = (& $gh.Source auth token 2>$null | Out-String).Trim()
                if ($LASTEXITCODE -ne 0) { $token = $null }
            }
        }
        catch { $token = $null }
    }

    $headers = @{
        'User-Agent' = 'Metra-Ops-StationUpdate'
        Accept       = 'application/vnd.github+json'
    }
    if (-not [string]::IsNullOrWhiteSpace($token)) {
        $headers['Authorization'] = "Bearer $token"
    }
    return $headers
}

function Get-MetraStationsManifestPath {
    param([string]$MetraRoot = (Get-MetraRoot))

    $preferred = Join-Path $MetraRoot 'config\stations.json'
    $example = Join-Path $MetraRoot 'config\stations.example.json'
    if (Test-Path -LiteralPath $preferred) { return $preferred }
    if (Test-Path -LiteralPath $example) { return $example }
    return $null
}

function Test-MetraStationManifestEntry {
    param($Entry)

    $issues = [System.Collections.Generic.List[string]]::new()
    $id = [string](Get-MetraProp -Object $Entry -Name 'id' -Default '')
    if ($id -notmatch '^[a-z0-9][a-z0-9-]*$') {
        $issues.Add('id must match ^[a-z0-9][a-z0-9-]*$')
    }
    $registryName = [string](Get-MetraProp -Object $Entry -Name 'registryName' -Default '')
    if ([string]::IsNullOrWhiteSpace($registryName) -or $registryName -eq '.' -or $registryName -eq '..' -or
        $registryName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
        $issues.Add('registryName must be a single non-dot directory segment (A-Z, 0-9, _, ., -)')
    }
    $repo = [string](Get-MetraProp -Object $Entry -Name 'githubRepo' -Default '')
    if ($repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        $issues.Add('githubRepo must be owner/name')
    }
    $pattern = [string](Get-MetraProp -Object $Entry -Name 'assetNamePattern' -Default '')
    if ([string]::IsNullOrWhiteSpace($pattern) -or $pattern -match '[\\/]') {
        $issues.Add('assetNamePattern required without path separators')
    }
    return [PSCustomObject]@{
        ok     = ($issues.Count -eq 0)
        issues = @($issues)
        id     = $id
    }
}

function Get-MetraStationsManifest {
    <#
    .SYNOPSIS
        Load and validate stations.json (or stations.example.json). Soft-fail bad entries.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Get-MetraStationsManifestPath -MetraRoot $MetraRoot
    if (-not $path) {
        return [PSCustomObject]@{
            path     = $null
            stations = @()
            errors   = @('stations manifest not found')
        }
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return [PSCustomObject]@{
            path     = $path
            stations = @()
            errors   = @("failed to parse stations manifest: $($_.Exception.Message)")
        }
    }

    $schema = Get-MetraProp -Object $raw -Name 'schemaVersion' -Default 0
    if ([int]$schema -ne 1) {
        return [PSCustomObject]@{
            path     = $path
            stations = @()
            errors   = @("unsupported stations schemaVersion '$schema' (expected 1)")
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $stations = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in @((Get-MetraProp -Object $raw -Name 'stations' -Default @()))) {
        $check = Test-MetraStationManifestEntry -Entry $entry
        if (-not $check.ok) {
            $errors.Add(("station '{0}': {1}" -f $check.id, ($check.issues -join '; ')))
            continue
        }
        if (-not $seen.Add($check.id)) {
            $errors.Add("duplicate station id '$($check.id)'")
            continue
        }
        $enabled = [bool](Get-MetraProp -Object $entry -Name 'enabled' -Default $true)
        if (-not $enabled) { continue }
        $stations.Add([PSCustomObject]@{
                id               = [string]$entry.id
                label            = [string](Get-MetraProp -Object $entry -Name 'label' -Default $entry.id)
                registryName     = [string]$entry.registryName
                githubRepo       = [string]$entry.githubRepo
                assetNamePattern = [string]$entry.assetNamePattern
                enabled          = $true
            })
    }

    return [PSCustomObject]@{
        path     = $path
        stations = @($stations)
        errors   = @($errors)
    }
}

function Get-MetraStationInstallPath {
    param(
        [Parameter(Mandatory)]$Station,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $workRoot = Get-MetraWorkRootPath -MetraRoot $MetraRoot
    Join-Path $workRoot ([string]$Station.registryName)
}

function Get-MetraStationInstalledVersion {
    param([Parameter(Mandatory)][string]$InstallPath)

    $versionFile = Join-Path $InstallPath 'station.version'
    if (Test-Path -LiteralPath $versionFile) {
        $v = (Get-Content -LiteralPath $versionFile -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($v)) { return ($v -replace '^[vV]', '').Trim() }
    }
    $pkg = Join-Path $InstallPath 'station.package.json'
    if (Test-Path -LiteralPath $pkg) {
        try {
            $d = Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json
            $v = [string](Get-MetraProp -Object $d -Name 'version' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($v)) { return ($v -replace '^[vV]', '').Trim() }
        }
        catch { }
    }
    return $null
}

function Test-MetraStationDevCheckout {
    param([Parameter(Mandatory)][string]$InstallPath)
    Test-Path -LiteralPath (Join-Path $InstallPath '.git')
}

function Get-MetraStationGitHubRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$AssetNamePattern,
        [int]$TimeoutSec = 30
    )

    $uri = "https://api.github.com/repos/$Repo/releases/latest"
    $headers = Get-MetraGitHubApiHeaders
    try {
        $rel = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSec
    }
    catch {
        $resp = $_.Exception.Response
        $code = $null
        if ($resp -and $resp.StatusCode) { $code = [int]$resp.StatusCode }
        $status = 'check_failed'
        if ($code -eq 401 -or $code -eq 403) { $status = 'authentication_required' }
        elseif ($code -eq 404) { $status = 'repository_unavailable' }
        elseif ($code -eq 429) { $status = 'rate_limited' }
        return [PSCustomObject]@{
            ok        = $false
            status    = $status
            message   = $_.Exception.Message
            httpStatus = $code
        }
    }

    $tag = [string]$rel.tag_name
    $version = ($tag -replace '^[vV]', '').Trim()
    $assets = @($rel.assets)
    $zipMatches = @(
        $assets | Where-Object {
            $name = [string]$_.name
            $name -like $AssetNamePattern -and $name -notlike '*.sha256'
        }
    )
    if ($zipMatches.Count -eq 0) {
        return [PSCustomObject]@{
            ok      = $false
            status  = 'no_zip_asset'
            message = "Release $tag has no zip matching $AssetNamePattern"
            tag     = $tag
            version = $version
            htmlUrl = [string]$rel.html_url
        }
    }
    if ($zipMatches.Count -gt 1) {
        return [PSCustomObject]@{
            ok      = $false
            status  = 'asset_ambiguous'
            message = "Release $tag has multiple zips matching $AssetNamePattern"
            tag     = $tag
            version = $version
            htmlUrl = [string]$rel.html_url
        }
    }

    $zip = $zipMatches[0]
    $zipName = [string]$zip.name
    # Identity: zip basename must embed the release tag version (TicketTracker-1.2.3.zip).
    $expectedZipSuffix = "-$version.zip"
    if (-not $zipName.EndsWith($expectedZipSuffix, [StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{
            ok      = $false
            status  = 'invalid_release'
            message = "Release $tag asset '$zipName' does not end with $expectedZipSuffix (tag/package version agreement)"
            tag     = $tag
            version = $version
            htmlUrl = [string]$rel.html_url
            assetName = $zipName
        }
    }
    $shaName = "$zipName.sha256"
    $shaAsset = @($assets | Where-Object { [string]$_.name -eq $shaName } | Select-Object -First 1)
    if (-not $shaAsset) {
        return [PSCustomObject]@{
            ok      = $false
            status  = 'missing_sha256_asset'
            message = "Release $tag has zip $zipName but no matching $shaName sidecar"
            tag     = $tag
            version = $version
            htmlUrl = [string]$rel.html_url
            assetName = $zipName
        }
    }

    return [PSCustomObject]@{
        ok              = $true
        status          = 'ok'
        tag             = $tag
        version         = $version
        name            = [string]$rel.name
        assetName       = $zipName
        assetSize       = $(if ($null -ne $zip.size) { [long]$zip.size } else { $null })
        downloadUrl     = [string]$zip.browser_download_url
        downloadApiUrl  = [string]$zip.url
        sha256Url       = [string]$shaAsset.browser_download_url
        sha256ApiUrl    = [string]$shaAsset.url
        sha256AssetName = $shaName
        htmlUrl         = [string]$rel.html_url
    }
}

function New-MetraStationStatusRow {
    param(
        [Parameter(Mandatory)]$Station,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $installPath = Get-MetraStationInstallPath -Station $Station -MetraRoot $MetraRoot
    $installed = Test-Path -LiteralPath $installPath
    $row = [PSCustomObject]@{
        id                = [string]$Station.id
        label             = [string]$Station.label
        registryName      = [string]$Station.registryName
        githubRepo        = [string]$Station.githubRepo
        installPath       = $installPath
        installed         = $false
        installedVersion  = $null
        releaseAvailable  = $false
        availableVersion  = $null
        updateAvailable   = $false
        canInstall        = $false
        canUpdate         = $false
        status            = 'unknown'
        reason            = $null
        message           = $null
        downloadUrl       = $null
        downloadApiUrl    = $null
        sha256Url         = $null
        sha256ApiUrl      = $null
        releaseUrl        = $null
        assetName         = $null
        assetSize         = $null
        channel           = 'station'
    }

    if ($installed -and (Test-MetraStationDevCheckout -InstallPath $installPath)) {
        $row.installed = $true
        $row.installedVersion = Get-MetraStationInstalledVersion -InstallPath $installPath
        $row.status = 'dev_checkout'
        $row.reason = 'dev_checkout'
        $row.message = "$($Station.label) is a Git checkout - installer will not overwrite it."
        $row.channel = 'dev'
        # Still discover release for display, but never canInstall/canUpdate.
        try {
            $rel = Get-MetraStationGitHubRelease -Repo $Station.githubRepo -AssetNamePattern $Station.assetNamePattern
            if ($rel.ok) {
                $row.releaseAvailable = $true
                $row.availableVersion = $rel.version
                $row.releaseUrl = $rel.htmlUrl
                $row.assetName = $rel.assetName
                $row.downloadUrl = $rel.downloadUrl
                $row.downloadApiUrl = $rel.downloadApiUrl
                $row.sha256Url = $rel.sha256Url
                $row.sha256ApiUrl = $rel.sha256ApiUrl
                $row.assetSize = $rel.assetSize
            }
        }
        catch { }
        return $row
    }

    try {
        $rel = Get-MetraStationGitHubRelease -Repo $Station.githubRepo -AssetNamePattern $Station.assetNamePattern
    }
    catch {
        $row.status = 'check_failed'
        $row.reason = 'check_failed'
        $row.message = $_.Exception.Message
        if ($installed) {
            $row.installed = $true
            $row.installedVersion = Get-MetraStationInstalledVersion -InstallPath $installPath
        }
        return $row
    }

    if (-not $rel.ok) {
        $row.status = [string]$rel.status
        $row.reason = [string]$rel.status
        $row.message = [string]$rel.message
        if ($rel.version) { $row.availableVersion = $rel.version }
        if ($rel.htmlUrl) { $row.releaseUrl = $rel.htmlUrl }
        if ($installed) {
            $row.installed = $true
            $row.installedVersion = Get-MetraStationInstalledVersion -InstallPath $installPath
        }
        return $row
    }

    $row.releaseAvailable = $true
    $row.availableVersion = $rel.version
    $row.releaseUrl = $rel.htmlUrl
    $row.downloadUrl = $rel.downloadUrl
    $row.downloadApiUrl = $rel.downloadApiUrl
    $row.sha256Url = $rel.sha256Url
    $row.sha256ApiUrl = $rel.sha256ApiUrl
    $row.assetName = $rel.assetName
    $row.assetSize = $rel.assetSize

    if (-not $installed) {
        $row.installed = $false
        $row.canInstall = $true
        $row.status = 'available_to_install'
        $row.reason = 'not_installed'
        $row.message = "$($Station.label) $($rel.version) is available to install."
        return $row
    }

    $row.installed = $true
    $installedVersion = Get-MetraStationInstalledVersion -InstallPath $installPath
    $row.installedVersion = $installedVersion
    if ([string]::IsNullOrWhiteSpace($installedVersion)) {
        $row.status = 'installed_unknown_version'
        $row.reason = 'installed_unknown_version'
        $row.canUpdate = $true
        $row.updateAvailable = $true
        $row.message = "$($Station.label) is installed without station.version; $($rel.version) is available."
        return $row
    }

    $cmp = Compare-MetraVersionString -Left $installedVersion -Right $rel.version
    if ($cmp -lt 0) {
        $row.updateAvailable = $true
        $row.canUpdate = $true
        $row.status = 'update_available'
        $row.reason = 'update_available'
        $row.message = "$($Station.label) $($rel.version) is available (you have $installedVersion)."
    }
    else {
        $row.status = 'up_to_date'
        $row.reason = 'up_to_date'
        $row.message = "$($Station.label) is up to date ($installedVersion)."
    }
    return $row
}

function Get-MetraStationUpdateStatuses {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $manifest = Get-MetraStationsManifest -MetraRoot $MetraRoot
    $rows = foreach ($s in @($manifest.stations)) {
        New-MetraStationStatusRow -Station $s -MetraRoot $MetraRoot
    }
    return [PSCustomObject]@{
        stations = @($rows)
        errors   = @($manifest.errors)
        path     = $manifest.path
    }
}

function Test-MetraStationPreservePathSafe {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$BasePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }
    if ($RelativePath.Contains('*') -or $RelativePath.Contains('?')) { return $false }
    $norm = ($RelativePath -replace '/', '\').Trim().Trim('\', '/')
    if ([string]::IsNullOrWhiteSpace($norm) -or $norm -eq '.' -or $norm -eq '..') { return $false }
    if ($norm.StartsWith('\') -or $norm -match '^[A-Za-z]:') { return $false }
    if ($norm -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
    if ($norm -match '(^|[\\/])\.git([\\/]|$)') { return $false }
    foreach ($segment in ($norm -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.' -or $segment -eq '..') {
            return $false
        }
    }
    $full = [System.IO.Path]::GetFullPath((Join-Path $BasePath $norm))
    $baseTrim = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $basePrefix = $baseTrim + [IO.Path]::DirectorySeparatorChar
    $fullTrim = $full.TrimEnd('\', '/')
    if ([string]::Equals($fullTrim, $baseTrim, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if (-not $full.StartsWith($basePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    return $true
}

function Expand-MetraStationZipSafe {
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    [void][System.IO.Directory]::CreateDirectory($Destination)

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $destFull = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        foreach ($entry in $zip.Entries) {
            $name = [string]$entry.FullName
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            # Normalize zip separators before join.
            $safeRel = ($name -replace '/', [IO.Path]::DirectorySeparatorChar)
            $target = [System.IO.Path]::GetFullPath((Join-Path $Destination $safeRel))
            if (-not $target.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Zip entry escapes destination: $name"
            }
        }
    }
    finally {
        $zip.Dispose()
    }

    Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force

    # Flatten single outer wrapper folder if present.
    $children = @(Get-ChildItem -LiteralPath $Destination -Force)
    if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
        $inner = $children[0].FullName
        $hasDescriptor = Test-Path -LiteralPath (Join-Path $inner 'station.package.json')
        $outerHas = Test-Path -LiteralPath (Join-Path $Destination 'station.package.json')
        if ($hasDescriptor -and -not $outerHas) {
            Get-ChildItem -LiteralPath $inner -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination (Join-Path $Destination $_.Name) -Force
            }
            Remove-Item -LiteralPath $inner -Recurse -Force
        }
    }
}

function Save-MetraStationReleaseAsset {
    <#
    .SYNOPSIS
        Download a GitHub release asset without leaking Authorization to S3 redirects.
    .NOTES
        Requests the API asset URL with auth + Accept: application/octet-stream and no auto-redirect,
        then downloads the Location URL with no Authorization header.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiUrl,
        [Parameter(Mandatory)][string]$OutFile,
        [int]$TimeoutSec = 600
    )

    if ([string]::IsNullOrWhiteSpace($ApiUrl) -or $ApiUrl -notmatch '^https://api\.github\.com/') {
        throw 'Station asset download requires a GitHub API asset URL.'
    }

    $headers = Get-MetraGitHubApiHeaders
    $auth = [string]$headers['Authorization']
    $req = [System.Net.HttpWebRequest]::Create($ApiUrl)
    $req.Method = 'GET'
    $req.AllowAutoRedirect = $false
    $req.UserAgent = [string]$headers['User-Agent']
    $req.Accept = 'application/octet-stream'
    $req.Timeout = [Math]::Max(1000, $TimeoutSec * 1000)
    if (-not [string]::IsNullOrWhiteSpace($auth)) {
        $req.Headers['Authorization'] = $auth
    }

    $location = $null
    $resp = $null
    try {
        $resp = [System.Net.HttpWebResponse]$req.GetResponse()
        $code = [int]$resp.StatusCode
        if ($code -ge 300 -and $code -lt 400) {
            $location = [string]$resp.Headers['Location']
        }
        elseif ($code -ge 200 -and $code -lt 300) {
            $stream = $resp.GetResponseStream()
            $fs = [System.IO.File]::Create($OutFile)
            try { $stream.CopyTo($fs) }
            finally {
                $fs.Dispose()
                if ($stream) { $stream.Dispose() }
            }
            return
        }
        else {
            throw "GitHub asset download failed HTTP $code for $ApiUrl"
        }
    }
    catch [System.Net.WebException] {
        $exResp = $_.Exception.Response
        if ($exResp) {
            $code = [int]$exResp.StatusCode
            if ($code -ge 300 -and $code -lt 400) {
                $location = [string]$exResp.Headers['Location']
            }
            else {
                throw
            }
        }
        else {
            throw
        }
    }
    finally {
        if ($resp) { $resp.Dispose() }
    }

    if ([string]::IsNullOrWhiteSpace($location)) {
        throw "GitHub asset redirect missing Location for $ApiUrl"
    }
    # Second hop: storage CDN - never send Authorization.
    Invoke-WebRequest -Uri $location -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec
}

function Copy-MetraStationPreservePaths {
    param(
        [Parameter(Mandatory)][string]$FromPath,
        [Parameter(Mandatory)][string]$ToPath,
        [Parameter(Mandatory)][string[]]$PreservePaths
    )

    foreach ($rel in @($PreservePaths)) {
        if (-not (Test-MetraStationPreservePathSafe -RelativePath $rel -BasePath $FromPath)) {
            throw "Unsafe preserve path refused: $rel"
        }
        if (-not (Test-MetraStationPreservePathSafe -RelativePath $rel -BasePath $ToPath)) {
            throw "Unsafe preserve path refused for destination: $rel"
        }
        $src = Join-Path $FromPath ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dest = Join-Path $ToPath ($rel -replace '/', '\')
        $destParent = Split-Path -Parent $dest
        if ($destParent -and -not (Test-Path -LiteralPath $destParent)) {
            [void][System.IO.Directory]::CreateDirectory($destParent)
        }
        if ((Get-Item -LiteralPath $src).PSIsContainer) {
            if (Test-Path -LiteralPath $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force
            }
            Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
        }
        else {
            Copy-Item -LiteralPath $src -Destination $dest -Force
        }
    }
}

function Enter-MetraStationUpdateLock {
    param([Parameter(Mandatory)][string]$StationId)

    $path = Get-MetraStationLockPath -StationId $StationId
    if (Test-Path -LiteralPath $path) {
        $ageHours = 2
        try {
            $info = Get-Item -LiteralPath $path
            if ((([datetime]::UtcNow) - $info.LastWriteTimeUtc).TotalHours -lt $ageHours) {
                return [PSCustomObject]@{ ok = $false; status = 'apply_in_progress'; path = $path }
            }
        }
        catch {
            return [PSCustomObject]@{ ok = $false; status = 'apply_in_progress'; path = $path }
        }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    $text = "{0}`r`n{1}`r`n" -f [datetime]::UtcNow.ToString('o'), $PID
    try {
        $fs = [System.IO.File]::Open(
            $path,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        try {
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
            $fs.Write($bytes, 0, $bytes.Length)
        }
        finally {
            $fs.Dispose()
        }
    }
    catch [System.IO.IOException] {
        return [PSCustomObject]@{ ok = $false; status = 'apply_in_progress'; path = $path }
    }
    return [PSCustomObject]@{ ok = $true; path = $path }
}

function Exit-MetraStationUpdateLock {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-MetraStationProductUpdate {
    <#
    .SYNOPSIS
        Install or update a station tree under the work root (transactional swap).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StationId,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$WhatIf,
        [string]$ApplyJobId
    )

    $manifest = Get-MetraStationsManifest -MetraRoot $MetraRoot
    $station = @($manifest.stations) | Where-Object { $_.id -eq $StationId } | Select-Object -First 1
    if (-not $station) {
        return [PSCustomObject]@{
            ok      = $false
            target  = $StationId
            status  = 'unknown_station'
            message = "Station '$StationId' is not in the stations manifest."
        }
    }

    $statusBundle = Get-MetraStationUpdateStatuses -MetraRoot $MetraRoot
    $row = @($statusBundle.stations) | Where-Object { $_.id -eq $StationId } | Select-Object -First 1
    if (-not $row) {
        return [PSCustomObject]@{
            ok      = $false
            target  = $StationId
            status  = 'check_failed'
            message = 'Could not resolve station status.'
        }
    }

    if ($row.status -eq 'dev_checkout') {
        return [PSCustomObject]@{
            ok      = $false
            target  = $StationId
            status  = 'dev_checkout'
            message = $row.message
        }
    }

    $isInstall = -not [bool]$row.installed
    $isUpdate = [bool]$row.canUpdate
    if (-not $isInstall -and -not $isUpdate) {
        return [PSCustomObject]@{
            ok      = $true
            target  = $StationId
            status  = 'already_current'
            message = $row.message
            updates = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$row.downloadApiUrl)) {
        return [PSCustomObject]@{
            ok      = $false
            target  = $StationId
            status  = 'no_download_url'
            message = 'No station zip API download URL.'
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$row.sha256ApiUrl)) {
        return [PSCustomObject]@{
            ok      = $false
            target  = $StationId
            status  = 'invalid_release'
            message = 'Release is missing the required .sha256 sidecar asset.'
        }
    }

    if ($WhatIf) {
        $action = if ($isInstall) { 'install' } else { 'update' }
        return [PSCustomObject]@{
            ok      = $true
            target  = $StationId
            status  = 'whatif'
            message = "Would $action $($station.label) to $($row.availableVersion)."
        }
    }

    $lock = Enter-MetraStationUpdateLock -StationId $StationId
    if (-not $lock.ok) {
        return [PSCustomObject]@{
            ok      = $false
            target  = $StationId
            status  = 'apply_in_progress'
            message = 'Another apply holds the station lock.'
        }
    }

    $installPath = [string]$row.installPath
    $stagingPath = "$installPath.__staging"
    $previousPath = "$installPath.__previous"
    $tempZip = Join-Path $env:TEMP ("MetraStation-{0}-{1}.zip" -f $StationId, ([guid]::NewGuid().ToString('n').Substring(0, 8)))
    $tempSha = "$tempZip.sha256"
    $activated = $false
    $swapped = $false

    try {
        # Re-check .git after lock.
        if ((Test-Path -LiteralPath $installPath) -and (Test-MetraStationDevCheckout -InstallPath $installPath)) {
            return [PSCustomObject]@{
                ok      = $false
                target  = $StationId
                status  = 'dev_checkout'
                message = 'Git checkout appeared after lock; refusing overwrite.'
            }
        }

        if ($ApplyJobId) {
            Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase downloading -Message "Downloading $($station.label)..."
        }

        Save-MetraStationReleaseAsset -ApiUrl $row.downloadApiUrl -OutFile $tempZip -TimeoutSec 600
        Save-MetraStationReleaseAsset -ApiUrl $row.sha256ApiUrl -OutFile $tempSha -TimeoutSec 120

        $expectedLine = (Get-Content -LiteralPath $tempSha -Raw).Trim()
        $expectedHash = ($expectedLine -split '\s+')[0].Trim().ToLowerInvariant()
        if ($expectedHash -notmatch '^[a-f0-9]{64}$') {
            throw 'SHA-256 sidecar did not contain a 64-char hex digest.'
        }
        $actualHash = (Get-FileHash -LiteralPath $tempZip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "SHA-256 mismatch (expected $expectedHash, got $actualHash)."
        }

        if ($ApplyJobId) {
            Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase installing -Message "Extracting $($station.label)..."
        }

        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        }
        Expand-MetraStationZipSafe -ZipPath $tempZip -Destination $stagingPath

        $pkgPath = Join-Path $stagingPath 'station.package.json'
        if (-not (Test-Path -LiteralPath $pkgPath)) {
            throw 'invalid_release: staged tree missing station.package.json'
        }
        $pkg = Get-Content -LiteralPath $pkgPath -Raw | ConvertFrom-Json
        $pkgId = [string](Get-MetraProp -Object $pkg -Name 'id' -Default '')
        $pkgVersion = ([string](Get-MetraProp -Object $pkg -Name 'version' -Default '') -replace '^[vV]', '').Trim()
        if ($pkgId -ne $StationId) {
            throw "invalid_release: package id '$pkgId' does not match station '$StationId'"
        }
        if ($pkgVersion -ne [string]$row.availableVersion) {
            throw "invalid_release: package version '$pkgVersion' does not match release '$($row.availableVersion)'"
        }
        $assetName = [string](Get-MetraProp -Object $row -Name 'assetName' -Default '')
        if ($assetName -and -not $assetName.EndsWith("-$pkgVersion.zip", [StringComparison]::OrdinalIgnoreCase)) {
            throw "invalid_release: asset '$assetName' does not embed package version $pkgVersion"
        }
        if (Test-Path -LiteralPath (Join-Path $stagingPath '.git')) {
            throw 'invalid_release: archive contains .git'
        }

        $preserve = @()
        foreach ($p in @(Get-MetraProp -Object $pkg -Name 'preservePaths' -Default @())) {
            $preserve += [string]$p
        }

        if (-not $isInstall -and (Test-Path -LiteralPath $installPath) -and $preserve.Count -gt 0) {
            Copy-MetraStationPreservePaths -FromPath $installPath -ToPath $stagingPath -PreservePaths $preserve
        }

        if ($ApplyJobId) {
            Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase installing -Message "Activating $($station.label)..."
        }

        if (Test-Path -LiteralPath $previousPath) {
            Remove-Item -LiteralPath $previousPath -Recurse -Force
        }

        if (Test-Path -LiteralPath $installPath) {
            Rename-Item -LiteralPath $installPath -NewName ([IO.Path]::GetFileName($previousPath))
            $swapped = $true
        }
        Rename-Item -LiteralPath $stagingPath -NewName ([IO.Path]::GetFileName($installPath))
        $activated = $true

        $versionPath = Join-Path $installPath 'station.version'
        [System.IO.File]::WriteAllText($versionPath, ($pkgVersion + "`r`n"), [System.Text.UTF8Encoding]::new($false))

        $receipt = [PSCustomObject]@{
            id          = $StationId
            version     = $pkgVersion
            installedAt = [datetime]::UtcNow.ToString('o')
            assetName   = $row.assetName
            sha256      = $actualHash
            sourceRepo  = $station.githubRepo
            mode        = $(if ($isInstall) { 'install' } else { 'update' })
        }
        $receiptPath = Join-Path $installPath 'station.install.json'
        $receiptJson = ($receipt | ConvertTo-Json -Depth 6) + "`r`n"
        [System.IO.File]::WriteAllText($receiptPath, $receiptJson, [System.Text.UTF8Encoding]::new($false))

        if ($ApplyJobId) {
            Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase verifying -Message 'Refreshing Metra workspace...'
        }
        if (Get-Command Update-MetraWorkspace -ErrorAction SilentlyContinue) {
            try { $null = Update-MetraWorkspace -Quiet } catch { }
        }

        if (Test-Path -LiteralPath $previousPath) {
            Remove-Item -LiteralPath $previousPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        $fresh = Get-MetraProductUpdates -MetraRoot $MetraRoot -Force
        return [PSCustomObject]@{
            ok              = $true
            target          = $StationId
            status          = $(if ($isInstall) { 'installed' } else { 'updated' })
            restartRequired = $false
            message         = $(if ($isInstall) { "$($station.label) $pkgVersion installed." } else { "$($station.label) $pkgVersion updated." })
            versionAfter    = $pkgVersion
            updates         = $fresh
        }
    }
    catch {
        $msg = $_.Exception.Message
        if ($activated) {
            # Attempt rollback from __previous.
            try {
                if (Test-Path -LiteralPath $installPath) {
                    Remove-Item -LiteralPath $installPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path -LiteralPath $previousPath) {
                    Rename-Item -LiteralPath $previousPath -NewName ([IO.Path]::GetFileName($installPath))
                }
            }
            catch {
                $msg = "Activation failed and rollback failed: $msg / $($_.Exception.Message). Manual recovery: check $installPath / $previousPath / $stagingPath"
            }
        }
        elseif ($swapped -and -not $activated) {
            try {
                if ((Test-Path -LiteralPath $previousPath) -and -not (Test-Path -LiteralPath $installPath)) {
                    Rename-Item -LiteralPath $previousPath -NewName ([IO.Path]::GetFileName($installPath))
                }
            }
            catch {
                $msg = "Activation failed and rollback from __previous failed: $msg / $($_.Exception.Message). Manual recovery: check $installPath / $previousPath / $stagingPath"
            }
        }
        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        $status = 'apply_failed'
        if ($msg -match 'invalid_release') { $status = 'invalid_release' }
        elseif ($msg -match 'SHA-256') { $status = 'checksum_failed' }
        return [PSCustomObject]@{
            ok      = $false
            target  = $StationId
            status  = $status
            message = $msg
        }
    }
    finally {
        Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempSha -Force -ErrorAction SilentlyContinue
        Exit-MetraStationUpdateLock -Path $lock.path
    }
}
