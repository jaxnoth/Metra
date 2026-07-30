# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Get-MetraRouting {
    <#
    .SYNOPSIS
        Gets merged routing entries resolved against projects on disk.
    .DESCRIPTION
        Merges shared, root-specific, and local registries, then reports whether each
        registered project is present and which triggers, capabilities, and advice apply.
    .PARAMETER Name
        One or more exact registry project names. Tab completion includes present and missing entries.
    .PARAMETER SharedOnly
        Reads only the shared projects.json registry.
    .PARAMETER MissingOnly
        Returns only registry entries whose project folder is absent.
    .EXAMPLE
        Get-MetraRouting -Name TicketTracker
    .EXAMPLE
        Get-MetraRouting -MissingOnly
    .OUTPUTS
        PSCustomObject containing routing source, project state, triggers, capabilities, and advice.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [switch]$SharedOnly,
        [switch]$MissingOnly
    )

    Get-MetraRoutingTable @PSBoundParameters
}

