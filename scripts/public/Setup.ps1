# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Initialize-Metra {
    <#
    .SYNOPSIS
        Initializes or refreshes a Metra checkout.
    .DESCRIPTION
        Seeds metra.config.json when needed, optionally imports a profile, validates roots,
        refreshes workspace files and routing, exports the context pack, regenerates
        self-documentation (paired with ctx), and ensures the proposal store root exists.
        Task inventory: Get-MetraSetupTasks.

        -Preview reports setup planning without writing files.
        -WhatIf uses native PowerShell ShouldProcess semantics and runs the same planning
        path (no writes). Keep both: Preview for setup planning output; WhatIf for
        PowerShell-native dry runs.

        -Quiet suppresses host-formatted output and skips prompts only - it does not change
        which setup steps apply (optional Ask still requires -AcceptAsk when Quiet).
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
        HQ Ops URL for Satellite (absolute http:// or https://). No prompt when set with -Quiet.
    .PARAMETER SyncToken
        Optional profile sync token for Satellite (writes %LOCALAPPDATA%/Metra/profile-sync.local.json).
        Plain string for v1; SecureString support may follow profile-sync evolution.
    .PARAMETER PreferFriendly
        Prefer http://metra/ when port 80 is free (HQ/Standalone). Cannot combine with
        -NoPreferFriendly.
    .PARAMETER NoPreferFriendly
        Force loopback Ops URL (HQ/Standalone). Cannot combine with -PreferFriendly.
    .PARAMETER BindTailscale
        Bind HQ Ops for Tailscale reach (Hq only).
    .PARAMETER AcceptAsk
        Install recommended Ask engine without prompting (HQ/Standalone only).
    .PARAMETER Advanced
        Ask local Ops networking knobs (HQ/Standalone interactive).
    .PARAMETER Months
        Overrides the workspace activity lookback (1-120).
    .PARAMETER ScanDepth
        Overrides the workspace project scan depth (1-100).
    .EXAMPLE
        Initialize-Metra
    .EXAMPLE
        Initialize-Metra -WhatIf
    .EXAMPLE
        Initialize-Metra -Preview
    .EXAMPLE
        Initialize-Metra -Quiet -Role Satellite -OpsBaseUrl 'https://hq.example.ts.net' -SyncToken '...'
    .EXAMPLE
        Initialize-Metra -Quiet -Role Hq -PreferFriendly -AcceptAsk
    .OUTPUTS
        PSCustomObject containing configuration, import, root, routing, workspace, context,
        self-documentation, proposal readiness, setup task inventory, and summary flags.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [string]$Profile,

        [switch]$Force,

        [switch]$Preview,

        [switch]$Quiet,

        [ValidateRange(1, 120)]
        [Nullable[int]]$Months,

        [ValidateRange(1, 100)]
        [Nullable[int]]$ScanDepth,

        [ValidateSet('Hq', 'Satellite', 'Standalone')]
        [string]$Role,

        [uri]$OpsBaseUrl,

        [string]$SyncToken,

        [switch]$PreferFriendly,

        [switch]$NoPreferFriendly,

        [switch]$BindTailscale,

        [switch]$AcceptAsk,

        [switch]$Advanced
    )

    if ($PreferFriendly -and $NoPreferFriendly) {
        throw '-PreferFriendly and -NoPreferFriendly cannot both be specified.'
    }

    if ($Role -eq 'Satellite' -and $AcceptAsk) {
        throw '-AcceptAsk is supported only with Hq or Standalone.'
    }

    if ($BindTailscale -and $Role -and $Role -ne 'Hq') {
        throw '-BindTailscale applies only to Hq.'
    }

    if ($Role -eq 'Satellite' -and ($PreferFriendly -or $NoPreferFriendly)) {
        throw '-PreferFriendly / -NoPreferFriendly apply only to Hq or Standalone.'
    }

    if ($Role -eq 'Satellite' -and $Advanced) {
        throw '-Advanced applies only to Hq or Standalone.'
    }

    $opsUrlText = $null
    if ($PSBoundParameters.ContainsKey('OpsBaseUrl') -and $null -ne $OpsBaseUrl) {
        if (-not $OpsBaseUrl.IsAbsoluteUri -or $OpsBaseUrl.Scheme -notin @('http', 'https')) {
            throw 'OpsBaseUrl must be an absolute http:// or https:// URL.'
        }
        $opsUrlText = $OpsBaseUrl.AbsoluteUri.TrimEnd('/')
    }

    $target = Get-MetraRoot
    $action = 'Initialize Metra checkout (may write config, workspace, routing, and sync state)'
    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        if (-not $WhatIfPreference) {
            return
        }
        # -WhatIf: native dry-run uses the Preview planning path (no writes).
        $Preview = $true
    }

    $invoke = @{}
    if ($Profile) { $invoke.Profile = $Profile }
    if ($Force) { $invoke.Force = $true }
    if ($Preview) { $invoke.Preview = $true }
    if ($Quiet) { $invoke.Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Months') -and $null -ne $Months) {
        $invoke.Months = [int]$Months
    }
    if ($PSBoundParameters.ContainsKey('ScanDepth') -and $null -ne $ScanDepth) {
        $invoke.ScanDepth = [int]$ScanDepth
    }
    if ($Role) { $invoke.Role = $Role }
    if ($opsUrlText) { $invoke.OpsBaseUrl = $opsUrlText }
    if ($SyncToken) { $invoke.SyncToken = $SyncToken }
    if ($PreferFriendly) { $invoke.PreferFriendly = $true }
    if ($NoPreferFriendly) { $invoke.NoPreferFriendly = $true }
    if ($BindTailscale) { $invoke.BindTailscale = $true }
    if ($AcceptAsk) { $invoke.AcceptAsk = $true }
    if ($Advanced) { $invoke.Advanced = $true }

    Invoke-MetraSetup @invoke
}
