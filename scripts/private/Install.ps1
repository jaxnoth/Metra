# Mark-of-the-web / ZIP-install helpers. Private except Show-MetraUnblockCli (CLI export).

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
        PSCustomObject with BlockedDetected, FilesUnblocked, AlreadyClean, Failed.
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
            }
            else {
                $filesUnblocked++
            }
        }
        catch {
            $failed++
        }
    }

    return [PSCustomObject]@{
        Path             = (Resolve-Path -LiteralPath $Path).Path
        Preview          = [bool]$Preview
        ScannedCount     = $files.Count
        BlockedDetected  = $blockedDetected
        FilesUnblocked   = $filesUnblocked
        AlreadyClean     = $alreadyClean
        Failed           = $failed
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
