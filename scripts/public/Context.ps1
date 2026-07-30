# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Export-MetraContext {
    <#
    .SYNOPSIS
        Exports a bounded Metra context pack for an agent.
    .DESCRIPTION
        Builds a compact map from configured roots, present routing entries, and selected
        project guidance. Writes docs/context-pack.md by default; Path '-' returns content
        without writing a file.
    .PARAMETER Query
        Terms used to rank and limit relevant projects.
    .PARAMETER Format
        Output format: markdown or json.
    .PARAMETER Path
        Output file path. Use '-' for stdout-only content.
    .PARAMETER Limit
        Maximum number of project entries included.
    .PARAMETER Quiet
        Suppresses host status messages.
    .EXAMPLE
        Export-MetraContext -Query 'ticket disk'
    .EXAMPLE
        Export-MetraContext -Format json -Path $env:TEMP\metra-context.json
    .EXAMPLE
        Export-MetraContext -Path '-' -Quiet
    .OUTPUTS
        Context content when Path is '-', followed by a summary object describing the export.
    #>
    [CmdletBinding()]
    param(
        [string]$Query,
        [ValidateSet('markdown', 'json')]
        [string]$Format = 'markdown',
        [string]$Path,
        [int]$Limit = 25,
        [switch]$Quiet
    )

    Export-MetraContextPack @PSBoundParameters
}

