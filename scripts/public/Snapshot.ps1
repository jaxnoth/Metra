# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Export-MetraSnapshot {
    <#
    .SYNOPSIS
        Exports the Metra Ops canvas snapshot.
    .DESCRIPTION
        Writes the bounded portfolio snapshot consumed by the Metra Ops canvas and installs
        or refreshes the canvas integration. Quick skips deep audit and Git inspection.
        Self-documentation refresh is opt-in via -RefreshSelfDocumentation (setup already
        pairs context pack + selfdoc). Supports -WhatIf / -Confirm (ConfirmImpact Low).
    .PARAMETER ScanDepth
        Maximum project scan depth used for full health collection (1-100).
    .PARAMETER Quick
        Produces a faster snapshot without deep audit or Git status collection.
    .PARAMETER RefreshSelfDocumentation
        Also run Update-MetraSelfDocumentation after the snapshot write.
    .EXAMPLE
        Export-MetraSnapshot
    .EXAMPLE
        Export-MetraSnapshot -Quick
    .EXAMPLE
        Export-MetraSnapshot -WhatIf
    .EXAMPLE
        Export-MetraSnapshot -RefreshSelfDocumentation
    .OUTPUTS
        PSCustomObject describing snapshot and canvas output paths.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([PSCustomObject])]
    param(
        [ValidateRange(1, 100)]
        [Nullable[int]]$ScanDepth,

        [switch]$Quick,

        [switch]$RefreshSelfDocumentation
    )

    $metraRoot = Get-MetraRoot
    $outPath = Join-Path $metraRoot 'docs\canvas-snapshot.json'
    $action = if ($Quick) {
        'Export quick Metra Ops canvas snapshot (writes snapshot + canvas embed)'
    }
    else {
        'Export Metra Ops canvas snapshot (writes snapshot + canvas embed)'
    }

    if (-not $PSCmdlet.ShouldProcess($outPath, $action)) {
        return
    }

    $invoke = @{}
    if ($PSBoundParameters.ContainsKey('ScanDepth') -and $null -ne $ScanDepth) {
        $invoke.ScanDepth = [int]$ScanDepth
    }
    if ($Quick) { $invoke.Quick = $true }
    if ($RefreshSelfDocumentation) { $invoke.RefreshSelfDocumentation = $true }

    Export-MetraCanvasSnapshot @invoke
}
