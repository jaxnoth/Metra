# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Test-MetraProjectContext {
    <#
    .SYNOPSIS
        Audits project context files and routing drift.
    .DESCRIPTION
        Performs a read-only check of matching projects for expected agent entry files,
        generated-path exclusions, large files, high-cardinality folders, and registry drift.
    .PARAMETER Filter
        Wildcard applied to project folder names.
    .PARAMETER Name
        One or more exact project names.
    .PARAMETER Root
        One or more configured root names.
    .PARAMETER DriftOnly
        Limits output to drift signals.
    .PARAMETER Quiet
        Suppresses host-formatted audit output.
    .PARAMETER LargeFileBytes
        File-size threshold used to flag potentially expensive context files.
    .PARAMETER HighCardinalityCount
        Item-count threshold used to flag noisy directories.
    .PARAMETER ScanDepth
        Maximum directory depth examined during the audit.
    .EXAMPLE
        Test-MetraProjectContext -Name Solarwinds,TicketTracker
    .EXAMPLE
        Test-MetraProjectContext -DriftOnly -Quiet
    .OUTPUTS
        Audit report objects followed by a summary object.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$DriftOnly,
        [switch]$Quiet,
        [int]$LargeFileBytes = 200KB,
        [int]$HighCardinalityCount = 200,
        [int]$ScanDepth = 4
    )

    Invoke-MetraProjectContextAudit @PSBoundParameters
}

