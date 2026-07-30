# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Initialize-Metra {
    <#
    .SYNOPSIS
        Initializes or refreshes a Metra checkout.
    .DESCRIPTION
        Seeds metra.config.json when needed, optionally imports a profile, validates roots,
        refreshes workspace files and routing, and exports the context pack.
    .PARAMETER Profile
        Optional profile folder or .zip to import before setup.
    .PARAMETER Force
        Allows the profile import to overwrite existing local files.
    .PARAMETER Preview
        Reports setup and import actions without writing files.
    .PARAMETER Quiet
        Suppresses host-formatted setup output.
    .PARAMETER Months
        Overrides the workspace activity lookback.
    .PARAMETER ScanDepth
        Overrides the workspace project scan depth.
    .EXAMPLE
        Initialize-Metra
    .EXAMPLE
        Initialize-Metra -Profile .\profiles\sample -Preview
    .OUTPUTS
        PSCustomObject containing configuration, import, root, routing, workspace, and context results.
    #>
    [CmdletBinding()]
    param(
        [string]$Profile,
        [switch]$Force,
        [switch]$Preview,
        [switch]$Quiet,
        [int]$Months,
        [int]$ScanDepth
    )

    Invoke-MetraSetup @PSBoundParameters
}

