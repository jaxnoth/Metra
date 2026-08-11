# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Test-MetraProjectContext {
    <#
    .SYNOPSIS
        Audits project context files and routing drift.
    .DESCRIPTION
        Performs a read-only check of matching projects for expected agent entry files,
        generated-path exclusions, large files, high-cardinality folders, and registry drift.
        -MetadataOnly skips the recursive tree scan and reports route registry metadata
        advisories only (never counted as drift).
        -DriftOnly and -MetadataOnly are mutually exclusive parameter sets.
    .PARAMETER Filter
        Wildcard applied to project folder names (not -Name).
    .PARAMETER Name
        One or more exact project names. Wildcards are not supported (use -Filter for wildcards).
        Accepts pipeline input by value (string) or by property name (Name).
    .PARAMETER Root
        One or more configured root names.
    .PARAMETER DriftOnly
        Limits output to drift signals. Cannot be combined with -MetadataOnly.
    .PARAMETER MetadataOnly
        Run route registry metadata advisories only. Skips recursive tree scan.
        Cannot be combined with -DriftOnly.
    .PARAMETER Quiet
        Suppresses host-formatted audit output.
    .PARAMETER LargeFileBytes
        File-size threshold used to flag potentially expensive context files.
    .PARAMETER HighCardinalityCount
        Item-count threshold used to flag noisy directories.
    .PARAMETER ScanDepth
        Maximum directory depth examined during the audit (1-20).
    .EXAMPLE
        Test-MetraProjectContext -Name Solarwinds,TicketTracker
    .EXAMPLE
        Test-MetraProjectContext -DriftOnly -Quiet
    .EXAMPLE
        Test-MetraProjectContext -MetadataOnly
    .EXAMPLE
        Get-MetraProject -Name Solarwinds,TicketTracker | Test-MetraProjectContext -Quiet
    .OUTPUTS
        PSCustomObject audit report rows followed by a summary PSCustomObject.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Full')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Full')]
        [Parameter(ParameterSetName = 'Drift')]
        [Parameter(ParameterSetName = 'Metadata')]
        [string]$Filter = '*',

        [Parameter(ParameterSetName = 'Full')]
        [Parameter(ParameterSetName = 'Drift')]
        [Parameter(ParameterSetName = 'Metadata')]
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'Full')]
        [Parameter(ParameterSetName = 'Drift')]
        [Parameter(ParameterSetName = 'Metadata')]
        [string[]]$Root,

        [Parameter(ParameterSetName = 'Drift')]
        [switch]$DriftOnly,

        [Parameter(ParameterSetName = 'Metadata')]
        [switch]$MetadataOnly,

        [Parameter(ParameterSetName = 'Full')]
        [Parameter(ParameterSetName = 'Drift')]
        [Parameter(ParameterSetName = 'Metadata')]
        [switch]$Quiet,

        [Parameter(ParameterSetName = 'Full')]
        [Parameter(ParameterSetName = 'Drift')]
        [Parameter(ParameterSetName = 'Metadata')]
        [ValidateRange(1, 2147483647)]
        [int]$LargeFileBytes = 200KB,

        [Parameter(ParameterSetName = 'Full')]
        [Parameter(ParameterSetName = 'Drift')]
        [Parameter(ParameterSetName = 'Metadata')]
        [ValidateRange(1, 100000)]
        [int]$HighCardinalityCount = 200,

        [Parameter(ParameterSetName = 'Full')]
        [Parameter(ParameterSetName = 'Drift')]
        [Parameter(ParameterSetName = 'Metadata')]
        [ValidateRange(1, 20)]
        [int]$ScanDepth = 4
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
        $invoke = @{
            Filter               = $Filter
            Quiet                = [bool]$Quiet
            LargeFileBytes       = $LargeFileBytes
            HighCardinalityCount = $HighCardinalityCount
            ScanDepth            = $ScanDepth
        }
        if ($nameBuf.Count -gt 0) {
            $invoke.Name = @($nameBuf.ToArray())
        }
        if ($Root) {
            $invoke.Root = $Root
        }
        if ($PSCmdlet.ParameterSetName -eq 'Drift') {
            $invoke.DriftOnly = $true
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Metadata') {
            $invoke.MetadataOnly = $true
        }

        Invoke-MetraProjectContextAudit @invoke
    }
}
