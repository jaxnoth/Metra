# Metra + Ollama product update check/apply (Settings + Ops Host cache).

function Get-MetraUpdatesCachePath {
    Join-Path $env:LOCALAPPDATA 'Metra\updates-status.local.json'
}

function Write-MetraUpdatesCacheAtomic {
    <#
    .SYNOPSIS
        Atomically write the updates status cache (temp + Move-Item).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Payload
    )

    $json = ($Payload | ConvertTo-Json -Depth 8) + "`r`n"
    if (Get-Command Write-MetraProfileAtomicText -ErrorAction SilentlyContinue) {
        Write-MetraProfileAtomicText -Path $Path -Text $json
        return
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-MetraWingetExePath {
    <#
    .SYNOPSIS
        Resolve winget.exe path from Get-Command (prefer .Source, then .Path).
    #>
    [CmdletBinding()]
    param()

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    $path = [string]$cmd.Source
    if ([string]::IsNullOrWhiteSpace($path)) { $path = [string]$cmd.Path }
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return $path
}

function Read-MetraUpdatesCacheApplyStamp {
    [CmdletBinding()]
    param([string]$CachePath = (Get-MetraUpdatesCachePath))

    $stamp = [PSCustomObject]@{
        lastUpdatedAt     = $null
        lastMetraVersion  = $null
        lastOllamaVersion = $null
    }
    if (-not (Test-Path -LiteralPath $CachePath)) { return $stamp }
    try {
        $cached = Get-Content -LiteralPath $CachePath -Raw | ConvertFrom-Json
        $stamp.lastUpdatedAt = Get-MetraProp -Object $cached -Name 'lastUpdatedAt' -Default $null
        $stamp.lastMetraVersion = Get-MetraProp -Object $cached -Name 'lastMetraVersion' -Default $null
        $stamp.lastOllamaVersion = Get-MetraProp -Object $cached -Name 'lastOllamaVersion' -Default $null
    }
    catch { }
    return $stamp
}

function Set-MetraUpdatesCacheApplyStamp {
    <#
    .SYNOPSIS
        Persist last successful apply timestamps/versions into the updates cache.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('metra', 'ollama')][string]$Target,
        [string]$Version,
        [string]$CachePath = (Get-MetraUpdatesCachePath)
    )

    $payload = $null
    if (Test-Path -LiteralPath $CachePath) {
        try {
            $payload = Get-Content -LiteralPath $CachePath -Raw | ConvertFrom-Json
        }
        catch { }
    }
    if (-not $payload) {
        $payload = [PSCustomObject]@{
            checkedAt = [datetime]::UtcNow.ToString('o')
        }
    }

    $at = [datetime]::UtcNow.ToString('o')
    if ($payload.PSObject.Properties['lastUpdatedAt']) { $payload.lastUpdatedAt = $at }
    else { $payload | Add-Member -NotePropertyName lastUpdatedAt -NotePropertyValue $at -Force }

    if ($Target -eq 'metra') {
        if ($payload.PSObject.Properties['lastMetraVersion']) { $payload.lastMetraVersion = $Version }
        else { $payload | Add-Member -NotePropertyName lastMetraVersion -NotePropertyValue $Version -Force }
    }
    else {
        if ($payload.PSObject.Properties['lastOllamaVersion']) { $payload.lastOllamaVersion = $Version }
        else { $payload | Add-Member -NotePropertyName lastOllamaVersion -NotePropertyValue $Version -Force }
    }

    try {
        Write-MetraUpdatesCacheAtomic -Path $CachePath -Payload $payload
    }
    catch { }
}

function Get-MetraInstalledModuleVersion {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $mod = Get-Module -Name Metra -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($mod -and $mod.Version) { return [string]$mod.Version }

    $psd1 = Join-Path $MetraRoot 'scripts\Metra.psd1'
    if (Test-Path -LiteralPath $psd1) {
        $match = [regex]::Match((Get-Content -LiteralPath $psd1 -Raw), "ModuleVersion\s*=\s*'([^']+)'")
        if ($match.Success) { return $match.Groups[1].Value }
    }
    return '0.0.0'
}

function Compare-MetraVersionString {
    param([string]$Left, [string]$Right)
    $a = (($Left -replace '^[vV]', '').Trim())
    $b = (($Right -replace '^[vV]', '').Trim())
    if ([string]::IsNullOrWhiteSpace($a)) { $a = '0.0.0' }
    if ([string]::IsNullOrWhiteSpace($b)) { $b = '0.0.0' }
    try {
        return ([version]$a).CompareTo([version]$b)
    }
    catch {
        return [string]::Compare($a, $b, [StringComparison]::OrdinalIgnoreCase)
    }
}

function Test-MetraDevCheckout {
    param([string]$MetraRoot = (Get-MetraRoot))
    Test-Path -LiteralPath (Join-Path $MetraRoot '.git')
}

function Get-MetraGitHubLatestRelease {
    [CmdletBinding()]
    param(
        [string]$Repo = 'jaxnoth/Metra',
        [int]$TimeoutSec = 20
    )

    $uri = "https://api.github.com/repos/$Repo/releases/latest"
    $headers = @{
        'User-Agent' = 'Metra-Ops-UpdateCheck'
        Accept       = 'application/vnd.github+json'
    }
    $rel = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSec
    $tag = [string]$rel.tag_name
    $version = ($tag -replace '^[vV]', '').Trim()
    $setupAsset = @($rel.assets) | Where-Object { $_.name -eq 'MetraSetup.exe' } | Select-Object -First 1
    if (-not $setupAsset) {
        $setupAsset = @($rel.assets) | Where-Object { $_.name -like 'MetraSetup-*.exe' } | Select-Object -First 1
    }
    $hasInstaller = $null -ne $setupAsset
    $downloadUrl = if ($hasInstaller) { [string]$setupAsset.browser_download_url } else { $null }
    $assetSize = $null
    if ($hasInstaller -and $null -ne $setupAsset.size) {
        try { $assetSize = [long]$setupAsset.size } catch { $assetSize = $null }
    }
    return [PSCustomObject]@{
        tag               = $tag
        version           = $version
        name              = [string]$rel.name
        hasInstallerAsset = $hasInstaller
        assetName         = $(if ($hasInstaller) { [string]$setupAsset.name } else { $null })
        assetSize         = $assetSize
        downloadUrl       = $downloadUrl
        htmlUrl           = [string]$rel.html_url
    }
}

function Get-MetraOllamaInstalledVersion {
    $exe = $null
    if (Get-Command Get-MetraAskOllamaExePath -ErrorAction SilentlyContinue) {
        $exe = Get-MetraAskOllamaExePath
    }
    if (-not $exe) { return $null }
    try {
        $out = & $exe --version 2>&1 | Out-String
        $m = [regex]::Match($out, '(\d+\.\d+\.\d+(?:-[\w\.]+)?)')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    catch { }
    return $null
}

function Get-MetraOllamaAvailableVersion {
    $wingetPath = Get-MetraWingetExePath
    if (-not $wingetPath) { return $null }
    try {
        $out = & $wingetPath show -e --id Ollama.Ollama 2>&1 | Out-String
        $m = [regex]::Match($out, '(?m)^Version:\s*(\S+)')
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    }
    catch { }
    return $null
}

function Get-MetraProductUpdates {
    <#
    .SYNOPSIS
        Returns Metra + Ollama update status for Settings / Host cache.
    .PARAMETER Force
        Bypass the 24h local cache and re-check remote versions.
    .NOTES
        Setup does not invoke this - update checks stay operator-initiated (Settings / Host).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Force,
        [int]$CacheHours = 24
    )

    $cachePath = Get-MetraUpdatesCachePath
    $applyStamp = Read-MetraUpdatesCacheApplyStamp -CachePath $cachePath
    if (-not $Force -and (Test-Path -LiteralPath $cachePath)) {
        try {
            $cached = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
            $checked = [datetime]::Parse([string]$cached.checkedAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if (([datetime]::UtcNow - $checked).TotalHours -lt $CacheHours) {
                return $cached
            }
        }
        catch { }
    }

    $installed = Get-MetraInstalledModuleVersion -MetraRoot $MetraRoot
    $devCheckout = Test-MetraDevCheckout -MetraRoot $MetraRoot
    $metra = [PSCustomObject]@{
        id                = 'metra'
        label             = 'Metra'
        installed         = $installed
        available         = $null
        updateAvailable   = $false
        canUpdate         = $false
        status            = 'unknown'
        message           = $null
        downloadUrl       = $null
        releaseUrl        = $null
        hasInstallerAsset = $null
        assetName         = $null
        assetSize         = $null
        channel           = $(if ($devCheckout) { 'dev' } else { 'installer' })
    }

    if ($devCheckout) {
        $metra.status = 'dev_checkout'
        $metra.message = 'Developer checkout - use git pull (or rebuild the installer) instead of in-app Update.'
    }
    else {
        try {
            $rel = Get-MetraGitHubLatestRelease
            $metra.available = $rel.version
            $metra.downloadUrl = $rel.downloadUrl
            $metra.releaseUrl = $rel.htmlUrl
            $metra.hasInstallerAsset = [bool]$rel.hasInstallerAsset
            $metra.assetName = $rel.assetName
            $metra.assetSize = $rel.assetSize
            $cmp = Compare-MetraVersionString -Left $installed -Right $rel.version
            if ($cmp -lt 0) {
                $metra.updateAvailable = $true
                if ($rel.hasInstallerAsset) {
                    $metra.canUpdate = $true
                    $metra.status = 'update_available'
                    $metra.message = "Metra $($rel.version) is available (you have $installed)."
                }
                else {
                    $metra.canUpdate = $false
                    $metra.status = 'no_installer_asset'
                    $metra.message = "Metra $($rel.version) is available but release $($rel.tag) has no MetraSetup.exe asset."
                }
            }
            else {
                $metra.status = 'up_to_date'
                $metra.message = "Metra is up to date ($installed)."
            }
        }
        catch {
            $metra.status = 'check_failed'
            $metra.message = "Could not check Metra releases: $($_.Exception.Message)"
        }
    }

    $ollamaInstalled = Get-MetraOllamaInstalledVersion
    $ollama = [PSCustomObject]@{
        id              = 'ollama'
        label           = 'Ollama'
        installed       = $ollamaInstalled
        available       = $null
        updateAvailable = $false
        canUpdate       = $false
        status          = 'unknown'
        message         = $null
    }

    if (-not $ollamaInstalled) {
        $ollama.status = 'not_installed'
        $ollama.message = 'Ollama is not installed. Use Ask recommended settings to install.'
        $ollama.canUpdate = $false
    }
    else {
        $avail = Get-MetraOllamaAvailableVersion
        $ollama.available = $avail
        if (-not $avail) {
            $ollama.status = 'check_failed'
            $ollama.message = "Installed $ollamaInstalled - could not query winget for a newer package."
        }
        else {
            $cmp = Compare-MetraVersionString -Left $ollamaInstalled -Right $avail
            if ($cmp -lt 0) {
                $ollama.updateAvailable = $true
                $ollama.canUpdate = $true
                $ollama.status = 'update_available'
                $ollama.message = "Ollama $avail is available (you have $ollamaInstalled)."
            }
            else {
                $ollama.status = 'up_to_date'
                $ollama.message = "Ollama is up to date ($ollamaInstalled)."
            }
        }
    }

    $payload = [PSCustomObject]@{
        checkedAt         = [datetime]::UtcNow.ToString('o')
        lastUpdatedAt     = $applyStamp.lastUpdatedAt
        lastMetraVersion  = $applyStamp.lastMetraVersion
        lastOllamaVersion = $applyStamp.lastOllamaVersion
        metra             = $metra
        ollama            = $ollama
        anyUpdate         = [bool]($metra.updateAvailable -or $ollama.updateAvailable)
    }

    try {
        Write-MetraUpdatesCacheAtomic -Path $cachePath -Payload $payload
    }
    catch { }

    return $payload
}

function Update-MetraProduct {
    <#
    .SYNOPSIS
        Downloads MetraSetup.exe from the latest GitHub release and runs it silently.
    .DESCRIPTION
        Operator-confirm path only (Settings Update button). Does not auto-apply.
        Dev checkouts refuse this path. After a successful silent upgrade, restart Ops.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$WhatIf,
        [string]$ApplyJobId
    )

    if (Test-MetraDevCheckout -MetraRoot $MetraRoot) {
        return [PSCustomObject]@{
            ok              = $false
            target          = 'metra'
            status          = 'dev_checkout'
            restartRequired = $false
            message         = 'Developer checkout - use git pull instead of the installer Update button.'
        }
    }

    $status = Get-MetraProductUpdates -MetraRoot $MetraRoot -Force
    if (-not $status.metra.updateAvailable) {
        return [PSCustomObject]@{
            ok              = $true
            target          = 'metra'
            status          = 'already_current'
            restartRequired = $false
            message         = $status.metra.message
            updates         = $status
        }
    }

    $url = [string]$status.metra.downloadUrl
    $hasAsset = $true
    if ($null -ne (Get-MetraProp -Object $status.metra -Name 'hasInstallerAsset' -Default $null)) {
        $hasAsset = [bool]$status.metra.hasInstallerAsset
    }
    if (-not $hasAsset -or [string]::IsNullOrWhiteSpace($url)) {
        return [PSCustomObject]@{
            ok              = $false
            target          = 'metra'
            status          = 'no_download_url'
            restartRequired = $false
            message         = 'Latest release has no MetraSetup.exe asset.'
            updates         = $status
        }
    }

    if ($WhatIf) {
        return [PSCustomObject]@{
            ok              = $true
            target          = 'metra'
            status          = 'whatif'
            restartRequired = $false
            message         = "Would download and run $url silently."
        }
    }

    $temp = Join-Path $env:TEMP ("MetraSetup-update-{0}.exe" -f ([guid]::NewGuid().ToString('n').Substring(0, 8)))
    try {
        if ($ApplyJobId) {
            Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase downloading -Message 'Downloading Metra installer...'
        }
        Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing -TimeoutSec 600
        if ($ApplyJobId) {
            Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase installing `
                -Message 'Installing Metra (Ops may restart or interrupt during this step)...'
        }
        $args = @('/VERYSILENT', '/NORESTART', '/SUPPRESSMSGBOXES', '/CLOSEAPPLICATIONS')
        $p = Start-Process -FilePath $temp -ArgumentList $args -Wait -PassThru
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        if ($p.ExitCode -ne 0) {
            return [PSCustomObject]@{
                ok              = $false
                target          = 'metra'
                status          = 'setup_failed'
                restartRequired = $false
                exitCode        = $p.ExitCode
                message         = "MetraSetup.exe exited $($p.ExitCode)."
            }
        }
    }
    catch {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{
            ok              = $false
            target          = 'metra'
            status          = 'download_failed'
            restartRequired = $false
            message         = $_.Exception.Message
        }
    }

    if ($ApplyJobId) {
        Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase verifying -Message 'Verifying Metra version...'
    }
    $appliedVersion = [string]$status.metra.available
    Set-MetraUpdatesCacheApplyStamp -Target metra -Version $appliedVersion
    $fresh = Get-MetraProductUpdates -MetraRoot $MetraRoot -Force
    return [PSCustomObject]@{
        ok              = $true
        target          = 'metra'
        status          = 'updated'
        restartRequired = $true
        message         = 'Metra installer finished. Restart Metra Ops to load the new build.'
        updates         = $fresh
    }
}

function Update-MetraOllamaProduct {
    <#
    .SYNOPSIS
        Silently upgrades Ollama (winget preferred, signed setup fallback).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$WhatIf,
        [string]$ApplyJobId
    )

    $status = Get-MetraProductUpdates -MetraRoot $MetraRoot -Force
    if ($status.ollama.status -eq 'not_installed') {
        if ($WhatIf) {
            return [PSCustomObject]@{
                ok              = $true
                target          = 'ollama'
                status          = 'whatif_install'
                restartRequired = $false
                message         = 'Would run silent install.'
            }
        }
        if ($ApplyJobId) {
            Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase installing -Message 'Installing Ollama...'
        }
        if (Get-Command Install-MetraAskOllamaRuntime -ErrorAction SilentlyContinue) {
            $install = Install-MetraAskOllamaRuntime -MetraRoot $MetraRoot
            if ($install.ok) {
                $ver = Get-MetraOllamaInstalledVersion
                Set-MetraUpdatesCacheApplyStamp -Target ollama -Version $ver
            }
            if ($ApplyJobId) {
                Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase verifying -Message 'Verifying Ollama version...'
            }
            $fresh = Get-MetraProductUpdates -MetraRoot $MetraRoot -Force
            return [PSCustomObject]@{
                ok              = [bool]$install.ok
                target          = 'ollama'
                status          = $(if ($install.ok) { 'installed' } else { [string]$install.status })
                restartRequired = $false
                message         = $(if ($install.ok) { 'Ollama installed.' } else { [string]$install.message })
                step            = $install
                updates         = $fresh
            }
        }
        return [PSCustomObject]@{
            ok              = $false
            target          = 'ollama'
            status          = 'not_installed'
            restartRequired = $false
            message         = 'Ollama is not installed.'
        }
    }

    if (-not $status.ollama.updateAvailable) {
        return [PSCustomObject]@{
            ok              = $true
            target          = 'ollama'
            status          = 'already_current'
            restartRequired = $false
            message         = $status.ollama.message
            updates         = $status
        }
    }

    if ($WhatIf) {
        return [PSCustomObject]@{
            ok              = $true
            target          = 'ollama'
            status          = 'whatif'
            restartRequired = $false
            message         = "Would silently upgrade Ollama to $($status.ollama.available)."
        }
    }

    if (Get-Command Set-MetraAskOllamaHiddenStartMarker -ErrorAction SilentlyContinue) {
        $null = Set-MetraAskOllamaHiddenStartMarker
    }

    $wingetPath = Get-MetraWingetExePath
    $upgraded = $false
    $detail = $null
    if ($wingetPath) {
        if ($ApplyJobId) {
            Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase installing -Message 'Upgrading Ollama via winget...'
        }
        $args = @(
            'upgrade', '-e', '--id', 'Ollama.Ollama',
            '--silent',
            '--accept-package-agreements', '--accept-source-agreements',
            '--override', '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES'
        )
        $p = Start-Process -FilePath $wingetPath -ArgumentList $args -Wait -PassThru -NoNewWindow
        # 0 = upgraded; -1978335189 often means no newer package / already current
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq -1978335189) {
            $upgraded = $true
            $detail = "winget exit $($p.ExitCode)"
        }
        else {
            $detail = "winget upgrade failed (exit $($p.ExitCode)); trying silent setup"
        }
    }

    if (-not $upgraded -and (Get-Command Install-MetraAskOllamaRuntime -ErrorAction SilentlyContinue)) {
        # Force the silent setup path by pretending health is down: download setup again.
        # Install-MetraAskOllamaRuntime short-circuits when already healthy - so run setup directly.
        $tempInstaller = Join-Path $env:TEMP 'MetraOllamaSetup-upgrade.exe'
        try {
            if ($ApplyJobId) {
                Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase downloading -Message 'Downloading Ollama installer...'
            }
            Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile $tempInstaller -UseBasicParsing -TimeoutSec 600
            $sig = Get-AuthenticodeSignature -LiteralPath $tempInstaller
            $signerOk = $sig.Status -eq 'Valid' -and $sig.SignerCertificate -and ($sig.SignerCertificate.Subject -match 'Ollama')
            if ($signerOk) {
                if ($ApplyJobId) {
                    Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase installing -Message 'Installing Ollama...'
                }
                $sp = Start-Process -FilePath $tempInstaller -ArgumentList @('/VERYSILENT', '/NORESTART', '/SUPPRESSMSGBOXES') -Wait -PassThru
                if ($sp.ExitCode -eq 0) {
                    $upgraded = $true
                    $detail = 'silent OllamaSetup.exe'
                }
                else {
                    $detail = "OllamaSetup.exe exited $($sp.ExitCode)"
                }
            }
            else {
                $detail = 'OllamaSetup.exe signature not verified'
            }
        }
        catch {
            $detail = $_.Exception.Message
        }
        finally {
            Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $upgraded) {
        $freshFail = Get-MetraProductUpdates -MetraRoot $MetraRoot -Force
        return [PSCustomObject]@{
            ok              = $false
            target          = 'ollama'
            status          = 'upgrade_failed'
            restartRequired = $false
            message         = $detail
            updates         = $freshFail
        }
    }

    # Bring API back if the upgrade bounced the service.
    $exe = Get-MetraAskOllamaExePath
    if ($exe) {
        Start-Process -FilePath $exe -ArgumentList @('serve') -WindowStyle Hidden -ErrorAction SilentlyContinue
    }

    if ($ApplyJobId) {
        Set-MetraUpdateApplyPhase -JobId $ApplyJobId -Phase verifying -Message 'Verifying Ollama version...'
    }
    $appliedVersion = [string]$status.ollama.available
    if (-not $appliedVersion) { $appliedVersion = Get-MetraOllamaInstalledVersion }
    Set-MetraUpdatesCacheApplyStamp -Target ollama -Version $appliedVersion
    $fresh = Get-MetraProductUpdates -MetraRoot $MetraRoot -Force
    return [PSCustomObject]@{
        ok              = $true
        target          = 'ollama'
        status          = 'updated'
        restartRequired = $false
        message         = "Ollama updated ($detail)."
        updates         = $fresh
    }
}

function Invoke-MetraProductUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('metra', 'ollama')][string]$Target,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$WhatIf,
        [string]$ApplyJobId
    )

    if ($Target -eq 'metra') {
        return Update-MetraProduct -MetraRoot $MetraRoot -WhatIf:$WhatIf -ApplyJobId $ApplyJobId
    }
    return Update-MetraOllamaProduct -MetraRoot $MetraRoot -WhatIf:$WhatIf -ApplyJobId $ApplyJobId
}

# --- Async apply job (Ops Settings; single-flight; status poll) ---

if ($null -eq (Get-Variable -Name MetraUpdateApplyHandles -Scope Script -ErrorAction SilentlyContinue)) {
    $script:MetraUpdateApplyHandles = @{}
}
if ($null -eq (Get-Variable -Name MetraUpdateApplyJobRunner -Scope Script -ErrorAction SilentlyContinue)) {
    $script:MetraUpdateApplyJobRunner = $null
}

function Get-MetraUpdateApplyStatusPath {
    Join-Path $env:LOCALAPPDATA 'Metra\updates-apply.local.json'
}

function New-MetraUpdateApplyJobId {
    $stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $suffix = [guid]::NewGuid().ToString('n').Substring(0, 4)
    return "$stamp-$suffix"
}

function ConvertTo-MetraUpdateApplyIsoTimestamp {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToUniversalTime().ToString('o')
    }
    try {
        return [datetime]::Parse([string]$Value, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime().ToString('o')
    }
    catch {
        return [string]$Value
    }
}

function Read-MetraUpdateApplyJob {
    [CmdletBinding()]
    param([string]$Path = (Get-MetraUpdateApplyStatusPath))

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $job = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if (-not $job) { return $null }
        # ConvertFrom-Json may coerce ISO timestamps to DateTime; normalize back to round-trip strings.
        if ($job.PSObject.Properties['startedAt']) {
            $job.startedAt = ConvertTo-MetraUpdateApplyIsoTimestamp -Value $job.startedAt
        }
        if ($job.PSObject.Properties['finishedAt']) {
            $job.finishedAt = ConvertTo-MetraUpdateApplyIsoTimestamp -Value $job.finishedAt
        }
        return $job
    }
    catch {
        return $null
    }
}

function Write-MetraUpdateApplyStatus {
    <#
    .SYNOPSIS
        Atomically write apply-job status. Refuses replace when on-disk jobId differs.
    .NOTES
        Initial create (no file / empty jobId) is allowed. Progress write failures return $false
        and must not abort apply - only the first job-creation write is treated as fatal by callers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Job,
        [string]$Path = (Get-MetraUpdateApplyStatusPath)
    )

    $jobId = [string](Get-MetraProp -Object $Job -Name 'jobId' -Default '')
    if ([string]::IsNullOrWhiteSpace($jobId)) {
        return $false
    }

    $existing = Read-MetraUpdateApplyJob -Path $Path
    if ($existing) {
        $existingId = [string](Get-MetraProp -Object $existing -Name 'jobId' -Default '')
        $existingState = [string](Get-MetraProp -Object $existing -Name 'state' -Default '')
        # Refuse only when a different job is still running (stale progress must not overwrite).
        # Terminal statuses may be replaced by a new jobId.
        if ($existingId -and $existingId -ne $jobId -and $existingState -eq 'running') {
            return $false
        }
    }

    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            [void][System.IO.Directory]::CreateDirectory($dir)
        }
        $json = ($Job | ConvertTo-Json -Depth 8) + "`r`n"
        $tmp = "$Path.$PID.$jobId.tmp"
        [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $Path -Force
        return $true
    }
    catch {
        try { Remove-Item -LiteralPath "$Path.$PID.$jobId.tmp" -Force -ErrorAction SilentlyContinue } catch { }
        return $false
    }
}

function Set-MetraUpdateApplyPhase {
    <#
    .SYNOPSIS
        Best-effort phase/message update for a running apply job (percent always null in v1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$JobId,
        [Parameter(Mandatory)][ValidateSet('starting', 'downloading', 'installing', 'verifying', 'done')][string]$Phase,
        [string]$Message,
        [ValidateSet('running', 'succeeded', 'failed', 'interrupted')]$State = 'running'
    )

    $current = Read-MetraUpdateApplyJob
    if (-not $current) { return }
    if ([string](Get-MetraProp -Object $current -Name 'jobId' -Default '') -ne $JobId) { return }

    $job = [PSCustomObject]@{
        jobId      = $JobId
        target     = Get-MetraProp -Object $current -Name 'target' -Default $null
        state      = $State
        phase      = $Phase
        message    = $(if ($PSBoundParameters.ContainsKey('Message')) { $Message } else { Get-MetraProp -Object $current -Name 'message' -Default $null })
        percent    = $null
        startedAt  = Get-MetraProp -Object $current -Name 'startedAt' -Default $null
        finishedAt = Get-MetraProp -Object $current -Name 'finishedAt' -Default $null
        result     = Get-MetraProp -Object $current -Name 'result' -Default $null
    }
    $null = Write-MetraUpdateApplyStatus -Job $job
}

function Clear-MetraUpdateApplyKnownTemps {
    <#
    .SYNOPSIS
        Best-effort delete of Metra-owned installer temp names only (no broad TEMP scan).
    #>
    [CmdletBinding()]
    param()

    $tempRoot = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempRoot)) { return }

    $exact = @(
        (Join-Path $tempRoot 'MetraOllamaSetup-upgrade.exe')
    )
    foreach ($path in $exact) {
        try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch { }
    }

    try {
        Get-ChildItem -LiteralPath $tempRoot -Filter 'MetraSetup-update-*.exe' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue } catch { }
            }
    }
    catch { }
}

function Sync-MetraUpdateApplyHandles {
    <#
    .SYNOPSIS
        EndInvoke + Dispose completed child runspaces; clear matching handle entries.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:MetraUpdateApplyHandles) { return }
    foreach ($jobId in @($script:MetraUpdateApplyHandles.Keys)) {
        $h = $script:MetraUpdateApplyHandles[$jobId]
        if (-not $h) {
            $script:MetraUpdateApplyHandles.Remove($jobId)
            continue
        }
        $ar = $h.AsyncResult
        if ($ar -and -not $ar.IsCompleted) { continue }
        $ps = $h.PowerShell
        if ($ps -and $ar) {
            try { $null = $ps.EndInvoke($ar) } catch { }
        }
        if ($ps) {
            try { $ps.Dispose() } catch { }
        }
        $script:MetraUpdateApplyHandles.Remove($jobId)
    }
}

function Test-MetraUpdateApplyRunning {
    [CmdletBinding()]
    param()

    Sync-MetraUpdateApplyHandles
    $job = Read-MetraUpdateApplyJob
    if ($job -and [string](Get-MetraProp -Object $job -Name 'state' -Default '') -eq 'running') {
        return $true
    }
    if ($script:MetraUpdateApplyHandles -and $script:MetraUpdateApplyHandles.Count -gt 0) {
        return $true
    }
    return $false
}

function Sync-MetraUpdateApplyInterrupted {
    <#
    .SYNOPSIS
        Mark stale running jobs as interrupted when no in-process handle matches; clean known temps.
    #>
    [CmdletBinding()]
    param()

    Sync-MetraUpdateApplyHandles
    $job = Read-MetraUpdateApplyJob
    if (-not $job) { return $null }
    if ([string](Get-MetraProp -Object $job -Name 'state' -Default '') -ne 'running') {
        return $job
    }

    $jobId = [string](Get-MetraProp -Object $job -Name 'jobId' -Default '')
    $hasHandle = $jobId -and $script:MetraUpdateApplyHandles -and $script:MetraUpdateApplyHandles.ContainsKey($jobId)
    if ($hasHandle) { return $job }

    $finishedAt = [datetime]::UtcNow.ToString('o')
    $interrupted = [PSCustomObject]@{
        jobId      = $jobId
        target     = Get-MetraProp -Object $job -Name 'target' -Default $null
        state      = 'interrupted'
        phase      = Get-MetraProp -Object $job -Name 'phase' -Default 'installing'
        message    = 'Ops restarted during update. Verify installed version and retry if necessary.'
        percent    = $null
        startedAt  = Get-MetraProp -Object $job -Name 'startedAt' -Default $null
        finishedAt = $finishedAt
        result     = $null
    }
    $null = Write-MetraUpdateApplyStatus -Job $interrupted
    Clear-MetraUpdateApplyKnownTemps
    return $interrupted
}

function New-MetraUpdateApplyResultFromInvoke {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InvokeResult,
        [Parameter(Mandatory)][string]$Target,
        [string]$VersionBefore
    )

    $ok = [bool](Get-MetraProp -Object $InvokeResult -Name 'ok' -Default $false)
    $versionAfter = $null
    $updates = Get-MetraProp -Object $InvokeResult -Name 'updates' -Default $null
    if ($updates) {
        $slice = Get-MetraProp -Object $updates -Name $Target -Default $null
        if ($slice) {
            $versionAfter = Get-MetraProp -Object $slice -Name 'installed' -Default $null
        }
    }
    if (-not $versionAfter) {
        $versionAfter = Get-MetraProp -Object $InvokeResult -Name 'versionAfter' -Default $null
    }

    $changed = $false
    $status = [string](Get-MetraProp -Object $InvokeResult -Name 'status' -Default '')
    if ($ok -and $status -in @('updated', 'installed')) { $changed = $true }
    elseif ($ok -and $VersionBefore -and $versionAfter -and $VersionBefore -ne $versionAfter) { $changed = $true }

    return [PSCustomObject]@{
        target          = $Target
        changed         = $changed
        versionBefore   = $VersionBefore
        versionAfter    = $versionAfter
        restartRequired = [bool](Get-MetraProp -Object $InvokeResult -Name 'restartRequired' -Default $false)
        message         = Get-MetraProp -Object $InvokeResult -Name 'message' -Default $null
        status          = $status
        ok              = $ok
    }
}

function Complete-MetraProductUpdateApplyJob {
    <#
    .SYNOPSIS
        Child-runspace entry: run product update and write terminal applyJob status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('metra', 'ollama')][string]$Target,
        [string]$MetraRoot = (Get-MetraRoot),
        [Parameter(Mandatory)][string]$JobId
    )

    $versionBefore = $null
    try {
        if ($Target -eq 'metra') {
            $versionBefore = Get-MetraInstalledModuleVersion -MetraRoot $MetraRoot
        }
        else {
            $versionBefore = Get-MetraOllamaInstalledVersion
        }

        Set-MetraUpdateApplyPhase -JobId $JobId -Phase starting -Message $(
            if ($Target -eq 'metra') {
                'Starting Metra update (Ops may restart or interrupt during install)...'
            }
            else {
                'Starting Ollama update...'
            }
        )

        $invoke = Invoke-MetraProductUpdate -Target $Target -MetraRoot $MetraRoot -ApplyJobId $JobId
        $rich = New-MetraUpdateApplyResultFromInvoke -InvokeResult $invoke -Target $Target -VersionBefore $versionBefore
        $finishedAt = [datetime]::UtcNow.ToString('o')
        $terminalState = $(if ($rich.ok) { 'succeeded' } else { 'failed' })
        $job = [PSCustomObject]@{
            jobId      = $JobId
            target     = $Target
            state      = $terminalState
            phase      = 'done'
            message    = $rich.message
            percent    = $null
            startedAt  = $(
                $cur = Read-MetraUpdateApplyJob
                if ($cur) { Get-MetraProp -Object $cur -Name 'startedAt' -Default $finishedAt } else { $finishedAt }
            )
            finishedAt = $finishedAt
            result     = $rich
        }
        $null = Write-MetraUpdateApplyStatus -Job $job
        return $job
    }
    catch {
        $finishedAt = [datetime]::UtcNow.ToString('o')
        $msg = $_.Exception.Message
        $job = [PSCustomObject]@{
            jobId      = $JobId
            target     = $Target
            state      = 'failed'
            phase      = 'done'
            message    = $msg
            percent    = $null
            startedAt  = $(
                $cur = Read-MetraUpdateApplyJob
                if ($cur) { Get-MetraProp -Object $cur -Name 'startedAt' -Default $finishedAt } else { $finishedAt }
            )
            finishedAt = $finishedAt
            result     = [PSCustomObject]@{
                target          = $Target
                changed         = $false
                versionBefore   = $versionBefore
                versionAfter    = $null
                restartRequired = $false
                message         = $msg
                status          = 'exception'
                ok              = $false
            }
        }
        $null = Write-MetraUpdateApplyStatus -Job $job
        return $job
    }
    finally {
        Clear-MetraUpdateApplyKnownTemps
    }
}

function Start-MetraProductUpdateApplyJob {
    <#
    .SYNOPSIS
        Accept or refuse an async product update apply (single-flight).
    .OUTPUTS
        PSCustomObject with StatusCode (202/409/422), Accepted, Error, Message, Job.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('metra', 'ollama')][string]$Target,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $null = Sync-MetraUpdateApplyInterrupted

    if (Test-MetraUpdateApplyRunning) {
        $running = Read-MetraUpdateApplyJob
        return [PSCustomObject]@{
            StatusCode = 409
            Accepted   = $false
            Error      = 'updateAlreadyRunning'
            Message    = 'A product update is already running.'
            Job        = $running
        }
    }

    # Preflight from cache/fresh check - do not create a job when not applicable.
    $status = Get-MetraProductUpdates -MetraRoot $MetraRoot
    $slice = Get-MetraProp -Object $status -Name $Target -Default $null
    $canUpdate = $false
    if ($slice) { $canUpdate = [bool](Get-MetraProp -Object $slice -Name 'canUpdate' -Default $false) }
    if (-not $canUpdate) {
        $msg = if ($slice) { [string](Get-MetraProp -Object $slice -Name 'message' -Default 'Update is not applicable.') } else { 'Update is not applicable.' }
        return [PSCustomObject]@{
            StatusCode = 422
            Accepted   = $false
            Error      = 'updateNotApplicable'
            Message    = $msg
            Job        = $null
        }
    }

    $jobId = New-MetraUpdateApplyJobId
    $startedAt = [datetime]::UtcNow.ToString('o')
    $startMessage = if ($Target -eq 'metra') {
        'Starting Metra update. Metra may restart or interrupt Ops during install.'
    }
    else {
        'Starting Ollama update...'
    }
    $job = [PSCustomObject]@{
        jobId      = $jobId
        target     = $Target
        state      = 'running'
        phase      = 'starting'
        message    = $startMessage
        percent    = $null
        startedAt  = $startedAt
        finishedAt = $null
        result     = $null
    }

    if (-not (Write-MetraUpdateApplyStatus -Job $job)) {
        return [PSCustomObject]@{
            StatusCode = 500
            Accepted   = $false
            Error      = 'applyStatusWriteFailed'
            Message    = 'Could not write apply job status.'
            Job        = $null
        }
    }

    # Test seam: when set, invoke instead of spawning a child runspace (no live download).
    if ($script:MetraUpdateApplyJobRunner) {
        try {
            & $script:MetraUpdateApplyJobRunner -Target $Target -MetraRoot $MetraRoot -JobId $jobId
            # Keep single-flight honest for conflict tests unless the runner cleared the handle.
            if (-not $script:MetraUpdateApplyHandles.ContainsKey($jobId)) {
                $script:MetraUpdateApplyHandles[$jobId] = @{
                    PowerShell  = $null
                    AsyncResult = [PSCustomObject]@{ IsCompleted = $false }
                }
            }
        }
        catch {
            $failJob = [PSCustomObject]@{
                jobId      = $jobId
                target     = $Target
                state      = 'failed'
                phase      = 'done'
                message    = "Could not start apply job: $($_.Exception.Message)"
                percent    = $null
                startedAt  = $startedAt
                finishedAt = [datetime]::UtcNow.ToString('o')
                result     = $null
            }
            $null = Write-MetraUpdateApplyStatus -Job $failJob
            return [PSCustomObject]@{
                StatusCode = 500
                Accepted   = $false
                Error      = 'applyStartFailed'
                Message    = $failJob.message
                Job        = $failJob
            }
        }
        return [PSCustomObject]@{
            StatusCode = 202
            Accepted   = $true
            Error      = $null
            Message    = $startMessage
            Job        = $job
        }
    }

    $modulePath = Join-Path $MetraRoot 'scripts\Metra.psd1'
    if (-not (Test-Path -LiteralPath $modulePath)) {
        $modulePath = Join-Path $MetraRoot 'scripts\Metra.psm1'
    }

    $ps = $null
    try {
        $ps = [powershell]::Create()
        $null = $ps.AddScript({
                param($ModulePath, $TargetName, $Root, $ApplyJobId)
                Import-Module $ModulePath -Force
                Complete-MetraProductUpdateApplyJob -Target $TargetName -MetraRoot $Root -JobId $ApplyJobId
            }).AddArgument($modulePath).AddArgument($Target).AddArgument($MetraRoot).AddArgument($jobId)

        $async = $ps.BeginInvoke()
        $script:MetraUpdateApplyHandles[$jobId] = @{
            PowerShell  = $ps
            AsyncResult = $async
        }
    }
    catch {
        if ($ps) { try { $ps.Dispose() } catch { } }
        $failJob = [PSCustomObject]@{
            jobId      = $jobId
            target     = $Target
            state      = 'failed'
            phase      = 'done'
            message    = "Could not start apply job: $($_.Exception.Message)"
            percent    = $null
            startedAt  = $startedAt
            finishedAt = [datetime]::UtcNow.ToString('o')
            result     = $null
        }
        $null = Write-MetraUpdateApplyStatus -Job $failJob
        return [PSCustomObject]@{
            StatusCode = 500
            Accepted   = $false
            Error      = 'applyStartFailed'
            Message    = $failJob.message
            Job        = $failJob
        }
    }

    return [PSCustomObject]@{
        StatusCode = 202
        Accepted   = $true
        Error      = $null
        Message    = $startMessage
        Job        = $job
    }
}

function Get-MetraOpsUpdatesApiPayload {
    <#
    .SYNOPSIS
        Ops GET /api/updates payload: cheap cached versions while apply is running + applyJob.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Force
    )

    $applyJob = Sync-MetraUpdateApplyInterrupted
    if (-not $applyJob) { $applyJob = Read-MetraUpdateApplyJob }

    $running = $applyJob -and [string](Get-MetraProp -Object $applyJob -Name 'state' -Default '') -eq 'running'

    if ($running) {
        $cachePath = Get-MetraUpdatesCachePath
        $payload = $null
        if (Test-Path -LiteralPath $cachePath) {
            try {
                $payload = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
            }
            catch { }
        }
        if (-not $payload) {
            $payload = [PSCustomObject]@{
                checkedAt         = $null
                lastUpdatedAt     = $null
                lastMetraVersion  = $null
                lastOllamaVersion = $null
                metra             = $null
                ollama            = $null
                anyUpdate         = $false
            }
        }
        if ($payload.PSObject.Properties['applyJob']) {
            $payload.applyJob = $applyJob
        }
        else {
            $payload | Add-Member -NotePropertyName applyJob -NotePropertyValue $applyJob -Force
        }
        return $payload
    }

    $fresh = Get-MetraProductUpdates -MetraRoot $MetraRoot -Force:$Force
    if ($fresh.PSObject.Properties['applyJob']) {
        $fresh.applyJob = $applyJob
    }
    else {
        $fresh | Add-Member -NotePropertyName applyJob -NotePropertyValue $applyJob -Force
    }
    return $fresh
}
