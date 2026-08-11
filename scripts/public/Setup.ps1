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
        Suppresses host-formatted setup output and skips prompts (installer path).
    .PARAMETER Role
        Machine role: Hq, Satellite, or Standalone.
    .PARAMETER OpsBaseUrl
        HQ Ops URL for Satellite (no prompt when set with -Quiet).
    .PARAMETER PreferFriendly
        Prefer http://metra/ when port 80 is free (HQ/Standalone).
    .PARAMETER NoPreferFriendly
        Force loopback Ops URL (HQ/Standalone).
    .PARAMETER BindTailscale
        Bind HQ Ops for Tailscale reach.
    .PARAMETER AcceptAsk
        Install recommended Ask engine without prompting (HQ/Standalone).
    .PARAMETER Advanced
        Ask local Ops networking knobs (HQ/Standalone interactive).
    .PARAMETER Months
        Overrides the workspace activity lookback.
    .PARAMETER ScanDepth
        Overrides the workspace project scan depth.
    .EXAMPLE
        Initialize-Metra
    .EXAMPLE
        Initialize-Metra -Quiet -Role Satellite -OpsBaseUrl 'https://hq.example.ts.net'
    .EXAMPLE
        Initialize-Metra -Quiet -Role Hq -PreferFriendly -AcceptAsk
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
        [int]$ScanDepth,
        [ValidateSet('Hq', 'Satellite', 'Standalone')]
        [string]$Role,
        [string]$OpsBaseUrl,
        [switch]$PreferFriendly,
        [switch]$NoPreferFriendly,
        [switch]$BindTailscale,
        [switch]$AcceptAsk,
        [switch]$Advanced
    )

    Invoke-MetraSetup @PSBoundParameters
}
