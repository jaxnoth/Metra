# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Get-MetraChat {
    <#
    .SYNOPSIS
        Gets matching Cursor chats for registered projects.
    .DESCRIPTION
        Searches bounded Cursor agent transcript metadata and snippets for project names,
        query terms, or a ticket identifier. It does not search Microsoft Teams.
    .PARAMETER Name
        One or more registered project names used to scope and seed the search.
    .PARAMETER Query
        Free-text search terms.
    .PARAMETER Ticket
        Ticket identifier to search for.
    .PARAMETER Days
        Maximum transcript age in days.
    .PARAMETER Limit
        Maximum number of chat results returned.
    .PARAMETER IncludeMetra
        Includes chats associated with the Metra orchestration repository.
    .EXAMPLE
        Get-MetraChat -Name Solarwinds -Query 'disk alert'
    .EXAMPLE
        Get-MetraChat -Name TicketTracker,Solarwinds -Ticket 1035020 -IncludeMetra
    .OUTPUTS
        PSCustomObject containing project, source, chat ID, title, snippets, matched terms, and citation.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [string]$Query,
        [string]$Ticket,
        [int]$Days = 90,
        [int]$Limit = 10,
        [Alias('IncludeMeta')]
        [switch]$IncludeMetra,
        [switch]$Cloud
    )

    Get-MetraProjectChats @PSBoundParameters
}
