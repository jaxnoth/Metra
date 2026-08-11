# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Get-MetraRouting {
    <#
    .SYNOPSIS
        Gets merged routing entries resolved against projects on disk.
    .DESCRIPTION
        Merges shared, root-specific, and local registries, then reports whether each
        registered project is present and which triggers, capabilities, and advice apply.
        -SharedOnly and -MissingOnly may be combined (shared registry entries whose project
        folder is absent).
    .PARAMETER Name
        One or more exact registry project names. Wildcards are not supported.
        Accepts pipeline input by value (string) or by property name (Name).
        Tab completion includes present and missing entries.
    .PARAMETER SharedOnly
        Reads only the shared projects.json registry. May be combined with -MissingOnly.
    .PARAMETER MissingOnly
        Returns only registry entries whose project folder is absent. May be combined with
        -SharedOnly.
    .EXAMPLE
        Get-MetraRouting -Name TicketTracker
    .EXAMPLE
        Get-MetraRouting -MissingOnly
    .EXAMPLE
        Get-MetraRouting -SharedOnly -MissingOnly
    .EXAMPLE
        Get-MetraProject -Root work | Get-MetraRouting
    .OUTPUTS
        PSCustomObject containing routing source, project state, triggers, capabilities, and advice.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [switch]$SharedOnly,

        [switch]$MissingOnly
    )

    begin {
        $nameBuf = New-Object System.Collections.Generic.List[string]
    }
    process {
        foreach ($n in @($Name)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$n)) {
                [void]$nameBuf.Add([string]$n)
            }
        }
    }
    end {
        $params = @{}
        if ($nameBuf.Count -gt 0) {
            $params.Name = @($nameBuf.ToArray())
        }
        if ($SharedOnly) { $params.SharedOnly = $true }
        if ($MissingOnly) { $params.MissingOnly = $true }
        Get-MetraRoutingTable @params
    }
}
