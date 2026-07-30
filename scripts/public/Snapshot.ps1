# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Export-MetraSnapshot {
    <#
    .SYNOPSIS
        Exports the Metra Ops canvas snapshot.
    .DESCRIPTION
        Writes the bounded portfolio snapshot consumed by the Metra Ops canvas and installs
        or refreshes the canvas integration. Quick skips deep audit and Git inspection.
    .PARAMETER ScanDepth
        Maximum project scan depth used for full health collection.
    .PARAMETER Quick
        Produces a faster snapshot without deep audit or Git status collection.
    .EXAMPLE
        Export-MetraSnapshot
    .EXAMPLE
        Export-MetraSnapshot -Quick
    .OUTPUTS
        PSCustomObject describing snapshot and canvas output paths.
    #>
    [CmdletBinding()]
    param(
        [int]$ScanDepth,
        [switch]$Quick
    )

    Export-MetraCanvasSnapshot @PSBoundParameters
}

