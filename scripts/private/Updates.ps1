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
        [switch]$WhatIf
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
        Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing -TimeoutSec 600
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
        [switch]$WhatIf
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
        if (Get-Command Install-MetraAskOllamaRuntime -ErrorAction SilentlyContinue) {
            $install = Install-MetraAskOllamaRuntime -MetraRoot $MetraRoot
            if ($install.ok) {
                $ver = Get-MetraOllamaInstalledVersion
                Set-MetraUpdatesCacheApplyStamp -Target ollama -Version $ver
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
            Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile $tempInstaller -UseBasicParsing -TimeoutSec 600
            $sig = Get-AuthenticodeSignature -LiteralPath $tempInstaller
            $signerOk = $sig.Status -eq 'Valid' -and $sig.SignerCertificate -and ($sig.SignerCertificate.Subject -match 'Ollama')
            if ($signerOk) {
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
        [switch]$WhatIf
    )

    if ($Target -eq 'metra') {
        return Update-MetraProduct -MetraRoot $MetraRoot -WhatIf:$WhatIf
    }
    return Update-MetraOllamaProduct -MetraRoot $MetraRoot -WhatIf:$WhatIf
}
