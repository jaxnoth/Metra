# Mark-of-the-web / ZIP-install helpers. Private except Show-MetraUnblockCli (CLI export).
# Also owns durable setup / installer troubleshooting logs under docs/*.local.log.
# Setup/installer logs use UTF-8 via Add-Content/Set-Content -Encoding utf8 (BOM behavior
# follows the host PowerShell version; prefer PowerShell 7+ for no-BOM UTF-8).

function Get-MetraSetupLogPath {
    <#
    .SYNOPSIS
        Path to the durable first-run / setup transcript (gitignored).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return (Join-Path $MetraRoot 'docs\setup.local.log')
}

function Get-MetraInstallerLogPath {
    <#
    .SYNOPSIS
        Path to the last copied Inno Setup log (gitignored).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return (Join-Path $MetraRoot 'docs\installer.local.log')
}

function Get-MetraInstallStatus {
    <#
    .SYNOPSIS
        Lightweight installer / setup log health summary for troubleshooting.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $setupLog = Get-MetraSetupLogPath -MetraRoot $MetraRoot
    $installerLog = Get-MetraInstallerLogPath -MetraRoot $MetraRoot

    return [PSCustomObject]@{
        SetupLogExists     = [bool](Test-Path -LiteralPath $setupLog -PathType Leaf)
        InstallerLogExists = [bool](Test-Path -LiteralPath $installerLog -PathType Leaf)
        SetupLogPath       = $setupLog
        InstallerLogPath   = $installerLog
    }
}

function Initialize-MetraSetupLogFolder {
    param([string]$MetraRoot = (Get-MetraRoot))

    $docs = Join-Path $MetraRoot 'docs'
    if (-not (Test-Path -LiteralPath $docs)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($docs)
    }
    return $docs
}

function Write-MetraSetupLogLine {
    <#
    .SYNOPSIS
        Appends one timestamped line to docs/setup.local.log (safe without a transcript).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    try {
        $null = Initialize-MetraSetupLogFolder -MetraRoot $MetraRoot
        $path = Get-MetraSetupLogPath -MetraRoot $MetraRoot
        $clean = ($Message -replace '\r?\n', ' ' -replace '\t', ' ' -replace '\s+', ' ').Trim()
        $line = '[{0:yyyy-MM-dd HH:mm:ssK}] {1}' -f (Get-Date), $clean
        Add-Content -LiteralPath $path -Value $line -Encoding utf8
    }
    catch {
        # Logging must never fail setup.
    }
}

function Copy-MetraInnoInstallerLog {
    <#
    .SYNOPSIS
        Best-effort: copy the newest Inno "Setup Log *.txt" from %TEMP% into docs/installer.local.log.
    .DESCRIPTION
        Inno SetupLogging=yes writes under TEMP. Operators need a stable path under the product tree.
        Only copies a log whose header mentions Metra - never falls back to an unrelated installer log.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$MaxAgeHours = 12
    )

    $dest = Get-MetraInstallerLogPath -MetraRoot $MetraRoot
    try {
        $null = Initialize-MetraSetupLogFolder -MetraRoot $MetraRoot
        $temp = [System.IO.Path]::GetTempPath()
        $cutoff = (Get-Date).AddHours(-1 * [Math]::Abs($MaxAgeHours))
        $candidates = @(
            Get-ChildItem -LiteralPath $temp -Filter 'Setup Log *.txt' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $cutoff } |
                Sort-Object @{ Expression = { $_.LastWriteTime }; Descending = $true }
        )
        $picked = $null
        foreach ($c in $candidates) {
            $head = ''
            try {
                $head = Get-Content -LiteralPath $c.FullName -TotalCount 40 -ErrorAction Stop | Out-String
            }
            catch { continue }
            if ($head -match '(?i)\bMetra\b') {
                $picked = $c
                break
            }
        }
        if (-not $picked) {
            return [PSCustomObject]@{
                Copied = $false
                Source = $null
                Path   = $dest
                Reason = 'No Metra installer log detected'
            }
        }
        Copy-Item -LiteralPath $picked.FullName -Destination $dest -Force
        if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
            throw 'Installer log copy verification failed.'
        }
        Write-MetraSetupLogLine -MetraRoot $MetraRoot -Message ("Copied Inno installer log from {0}" -f $picked.FullName)
        return [PSCustomObject]@{
            Copied = $true
            Source = $picked.FullName
            Path   = $dest
        }
    }
    catch {
        return [PSCustomObject]@{
            Copied = $false
            Source = $null
            Path   = $dest
            Error  = $_.Exception.Message
        }
    }
}

function Start-MetraSetupTranscript {
    <#
    .SYNOPSIS
        Starts an append transcript to docs/setup.local.log when one is not already active.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$Source = 'setup'
    )

    $null = Initialize-MetraSetupLogFolder -MetraRoot $MetraRoot
    $path = Get-MetraSetupLogPath -MetraRoot $MetraRoot

    $version = ''
    try {
        $psd1 = Join-Path $MetraRoot 'scripts\Metra.psd1'
        if (Test-Path -LiteralPath $psd1) {
            $importParams = @{ ErrorAction = 'Stop' }
            if ((Get-Command Import-PowerShellDataFile).Parameters.ContainsKey('LiteralPath')) {
                $importParams.LiteralPath = $psd1
            }
            else {
                $importParams.Path = $psd1
            }
            $manifest = Import-PowerShellDataFile @importParams
            $version = [string]$manifest.ModuleVersion
        }
    }
    catch { }

    # Header before transcript - transcript locks the file on some hosts.
    Write-MetraSetupLogLine -MetraRoot $MetraRoot -Message ("==== Metra {0} start source={1} host={2} user={3} ps={4} ====" -f `
            $(if ($version) { $version } else { '?' }),
        $Source,
        $env:COMPUTERNAME,
        $env:USERNAME,
        $PSVersionTable.PSVersion)

    $started = $false
    try {
        Start-Transcript -Path $path -Append -ErrorAction Stop | Out-Null
        $started = $true
    }
    catch {
        $started = $false
    }

    return [PSCustomObject]@{
        Path    = $path
        Started = $started
        Source  = $Source
    }
}

function Stop-MetraSetupTranscript {
    <#
    .SYNOPSIS
        Stops a transcript started by Start-MetraSetupTranscript (ignores if not ours / already stopped).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Session,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($Session -and [bool]$Session.Started) {
        try { Stop-Transcript -ErrorAction Stop | Out-Null } catch { }
    }
    Write-MetraSetupLogLine -MetraRoot $MetraRoot -Message ("==== Metra setup end source={0} ====" -f $(if ($Session.Source) { $Session.Source } else { 'setup' }))
}

function Test-MetraBlockedFile {
    <#
    .SYNOPSIS
        Returns $true when a file still carries a Zone.Identifier alternate data stream (mark-of-the-web).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $streamPath = $Path + ':Zone.Identifier'
    return [bool](Test-Path -LiteralPath $streamPath)
}

function Get-MetraCheckoutScriptFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $root = (Resolve-Path -LiteralPath $Path).Path
    $extensions = @('.ps1', '.psm1', '.psd1', '.cmd')
    return @(
        Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() }
    )
}

function Unblock-MetraCheckout {
    <#
    .SYNOPSIS
        Clears mark-of-the-web from Metra checkout script files. Supports -Preview.
    .OUTPUTS
        PSCustomObject with BlockedDetected, FilesUnblocked, AlreadyClean, Failed, FailedFiles.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Preview
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-MetraRoot
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Checkout path not found: $Path"
    }

    $files = @(Get-MetraCheckoutScriptFiles -Path $Path)
    $blockedDetected = 0
    $filesUnblocked = 0
    $alreadyClean = 0
    $failed = 0
    $failedFiles = New-Object System.Collections.Generic.List[string]

    foreach ($file in $files) {
        $isBlocked = Test-MetraBlockedFile -Path $file.FullName
        if (-not $isBlocked) {
            $alreadyClean++
            continue
        }

        $blockedDetected++
        if ($Preview) {
            continue
        }

        try {
            Unblock-File -LiteralPath $file.FullName -ErrorAction Stop
            if (Test-MetraBlockedFile -Path $file.FullName) {
                $failed++
                if ($failedFiles.Count -lt 10) {
                    [void]$failedFiles.Add([string]$file.FullName)
                }
            }
            else {
                $filesUnblocked++
            }
        }
        catch {
            $failed++
            if ($failedFiles.Count -lt 10) {
                [void]$failedFiles.Add([string]$file.FullName)
            }
        }
    }

    return [PSCustomObject]@{
        Path            = (Resolve-Path -LiteralPath $Path).Path
        Preview         = [bool]$Preview
        ScannedCount    = $files.Count
        BlockedDetected = $blockedDetected
        FilesUnblocked  = $filesUnblocked
        AlreadyClean    = $alreadyClean
        Failed          = $failed
        FailedFiles     = @($failedFiles.ToArray())
    }
}

function Write-MetraUnblockResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Result,
        [switch]$Quiet
    )

    if ($Quiet -and $Result.Failed -eq 0 -and $Result.BlockedDetected -eq 0) {
        return
    }

    Write-Host ''
    if ($Result.Preview) {
        Write-Host 'Unblock preview (no writes):' -ForegroundColor Cyan
    }
    else {
        Write-Host 'Unblock:' -ForegroundColor Cyan
    }

    if ($Quiet -or ($Result.Failed -eq 0 -and $Result.BlockedDetected -eq 0 -and -not $Result.Preview)) {
        Write-Host ("  Scripts OK ({0} checked)." -f $Result.ScannedCount) -ForegroundColor DarkGray
        return
    }

    Write-Host ("  Path:             {0}" -f $Result.Path)
    Write-Host ("  Scanned:          {0}" -f $Result.ScannedCount)
    Write-Host ("  BlockedDetected:  {0}" -f $Result.BlockedDetected)
    Write-Host ("  FilesUnblocked:   {0}" -f $Result.FilesUnblocked)
    Write-Host ("  AlreadyClean:     {0}" -f $Result.AlreadyClean)
    Write-Host ("  Failed:           {0}" -f $Result.Failed)
    if ($Result.Failed -gt 0) {
        Write-Host '  Some files could not be unblocked. Retry as the file owner, or unblock the ZIP before extracting.' -ForegroundColor Yellow
        foreach ($f in @($Result.FailedFiles | Select-Object -First 5)) {
            Write-Host ("    - {0}" -f $f) -ForegroundColor DarkYellow
        }
    }
    elseif ($Result.Preview -and $Result.BlockedDetected -gt 0) {
        Write-Host '  Hint: .\metra.ps1 unblock' -ForegroundColor Yellow
    }
}

function Show-MetraUnblockCli {
    <#
    .SYNOPSIS
        Thin CLI export: unblock Metra checkout scripts and print supportability counts.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Preview,
        [switch]$Quiet
    )

    $params = @{ Preview = [bool]$Preview }
    if ($Path) { $params.Path = $Path }
    $result = Unblock-MetraCheckout @params
    Write-MetraUnblockResult -Result $result -Quiet:$Quiet
    return $result
}
