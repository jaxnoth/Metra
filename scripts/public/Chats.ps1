# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Get-MetraChat {
    <#
    .SYNOPSIS
        Gets matching Cursor chats for registered projects.
    .DESCRIPTION
        Searches bounded Cursor agent transcript metadata and snippets for project names,
        query terms, or a ticket identifier. It does not search Microsoft Teams.
        -Query and -Ticket are mutually exclusive parameter sets. Specify at least one of
        -Name, -Query, -Ticket, or -IncludeMetra.
    .PARAMETER Name
        One or more exact project names used to scope and seed the search.
        Accepts pipeline input by property name (Name). Wildcards are not supported.
    .PARAMETER Query
        Free-text search terms. Cannot be combined with -Ticket.
    .PARAMETER Ticket
        Ticket identifier to search for. Cannot be combined with -Query.
    .PARAMETER Days
        Maximum transcript age in days (1-3650).
    .PARAMETER Limit
        Maximum number of chat results returned (1-100).
    .PARAMETER IncludeMetra
        Includes chats associated with the Metra orchestration repository.
    .PARAMETER Cloud
        Also search Cursor Cloud Agent chats when a CURSOR_API_KEY is available.
    .EXAMPLE
        Get-MetraChat -Name Solarwinds -Query 'disk alert'
    .EXAMPLE
        Get-MetraChat -Name TicketTracker,Solarwinds -Ticket 1035020 -IncludeMetra
    .EXAMPLE
        Get-MetraProject -Name Solarwinds | Get-MetraChat -Query alert -Limit 5
    .OUTPUTS
        PSCustomObject containing project, source, chat ID, title, snippets, matched terms, and citation.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Search')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Search')]
        [Parameter(ParameterSetName = 'Ticket')]
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'Search')]
        [string]$Query,

        [Parameter(ParameterSetName = 'Ticket')]
        [ValidateNotNullOrEmpty()]
        [string]$Ticket,

        [ValidateRange(1, 3650)]
        [int]$Days = 90,

        [ValidateRange(1, 100)]
        [int]$Limit = 10,

        [Alias('IncludeMeta')]
        [switch]$IncludeMetra,

        [switch]$Cloud
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
        $hasName = $nameBuf.Count -gt 0
        $hasQuery = -not [string]::IsNullOrWhiteSpace($Query)
        $hasTicket = -not [string]::IsNullOrWhiteSpace($Ticket)
        if (-not $hasName -and -not $hasQuery -and -not $hasTicket -and -not $IncludeMetra) {
            throw 'Specify -Name, -Query, -Ticket, or -IncludeMetra.'
        }

        $invoke = @{
            Days  = $Days
            Limit = $Limit
        }
        if ($hasName) {
            $invoke.Name = @($nameBuf.ToArray())
        }
        if ($PSCmdlet.ParameterSetName -eq 'Ticket') {
            $invoke.Ticket = $Ticket
        }
        elseif ($hasQuery) {
            $invoke.Query = $Query
        }
        if ($IncludeMetra) {
            $invoke.IncludeMetra = $true
        }
        if ($Cloud) {
            $invoke.Cloud = $true
        }

        Get-MetraProjectChats @invoke
    }
}
