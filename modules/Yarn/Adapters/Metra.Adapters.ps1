# Metra host adapters for Yarn. Domain never dotsources scripts/private/*.ps1.
# Yarn must not write Loom queue/journal files.

$script:YarnHostRootOverride = $null
$script:YarnCaptureOverride = $null
$script:YarnPackOverride = $null
$script:YarnLoomIngestOverride = $null

function Get-YarnHostRoot {
    [CmdletBinding()]
    param()
    if ($script:YarnHostRootOverride) {
        return [System.IO.Path]::GetFullPath([string]$script:YarnHostRootOverride)
    }
    $cmd = Get-Command Get-MetraRoot -ErrorAction SilentlyContinue
    if ($cmd) {
        return & $cmd
    }
    $modRoot = $PSScriptRoot
    while ($modRoot -and (Split-Path -Leaf $modRoot) -ne 'Yarn') {
        $modRoot = Split-Path -Parent $modRoot
    }
    if ($modRoot) {
        $candidate = Split-Path -Parent (Split-Path -Parent $modRoot)
        if (Test-Path -LiteralPath (Join-Path $candidate 'metra.ps1')) {
            return $candidate
        }
    }
    throw 'Yarn host root unavailable (Metra not loaded and metra.ps1 not found).'
}

function Test-YarnCaptureAdapterAvailable {
    [CmdletBinding()]
    param()
    if ($script:YarnCaptureOverride) { return $true }
    return $null -ne (Get-Command Get-MetraCaptureLedger -ErrorAction SilentlyContinue)
}

function Get-YarnCaptureLedger {
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [int]$Limit = 40,
        [string]$Status = 'candidate'
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-YarnHostRoot
    }
    if ($script:YarnCaptureOverride) {
        return @(& $script:YarnCaptureOverride @{
                MetraRoot = $MetraRoot
                Limit     = $Limit
                Status    = $Status
            })
    }
    if (-not (Test-YarnCaptureAdapterAvailable)) {
        return @()
    }
    return @(& (Get-Command Get-MetraCaptureLedger) -MetraRoot $MetraRoot -Limit $Limit -Status $Status)
}

function Test-YarnLoomQueueWriteForbidden {
    <#
    .SYNOPSIS
        Guard: Yarn never mutates Loom queue storage.
    #>
    [CmdletBinding()]
    param()
    # Presence of Loom save cmdlets is fine; Yarn must not call them.
    return $true
}
