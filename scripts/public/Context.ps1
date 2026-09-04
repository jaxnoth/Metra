# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Export-MetraContext {
    <#
    .SYNOPSIS
        Exports a bounded Metra context pack for an agent.
    .DESCRIPTION
        Builds a compact map from configured roots, present routing entries, and selected
        project guidance. Writes machine-local desk/context-pack.md by default; -AsString or Path '-'
        returns content without writing a file. Query is optional (default pack when omitted).
    .PARAMETER Query
        Terms used to rank and limit relevant projects.
    .PARAMETER Format
        Output format: markdown or json.
    .PARAMETER Path
        Output file path. Use '-' for stdout-only content (same as -AsString).
        Parent directory must already exist when writing a file.
    .PARAMETER Limit
        Maximum number of project entries included (1-100).
    .PARAMETER Quiet
        Suppresses host status messages.
    .PARAMETER AsString
        Stdout-only content (no file write). Equivalent to -Path '-'.
    .EXAMPLE
        Export-MetraContext -Query 'ticket disk'
    .EXAMPLE
        Export-MetraContext -Format json -Path $env:TEMP\metra-context.json
    .EXAMPLE
        Export-MetraContext -AsString -Quiet
    .EXAMPLE
        Export-MetraContext -Path '-' -Quiet
    .OUTPUTS
        System.String context content when using -AsString or Path '-', followed by a
        summary PSCustomObject describing the export. File exports return the summary only.
    #>
    [CmdletBinding()]
    [OutputType([string], [pscustomobject])]
    param(
        [string]$Query,

        [ValidateSet('markdown', 'json')]
        [string]$Format = 'markdown',

        [string]$Path,

        [ValidateRange(1, 100)]
        [int]$Limit = 25,

        [switch]$Quiet,

        [Alias('PassThru')]
        [switch]$AsString
    )

    $resolvedPath = $Path
    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        $resolvedPath = $null
    }

    if ($AsString) {
        if ($null -ne $resolvedPath -and $resolvedPath -ne '-') {
            throw "AsString cannot be combined with a file -Path. Use -AsString alone, or -Path '-'."
        }
        $resolvedPath = '-'
    }

    if ($null -ne $resolvedPath -and $resolvedPath -ne '-') {
        $parent = Split-Path -Parent -Path $resolvedPath
        if ($parent) {
            $parentFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($parent)
            if (-not (Test-Path -LiteralPath $parentFull)) {
                throw "Directory does not exist: $parentFull"
            }
        }

        $pathFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($resolvedPath)
        if ((Test-Path -LiteralPath $pathFull) -and (Test-Path -LiteralPath $pathFull -PathType Container)) {
            throw "Path is a directory, not a file: $pathFull"
        }
    }

    $invoke = @{
        Format = $Format
        Limit  = $Limit
    }
    if ($Quiet) { $invoke.Quiet = $true }
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $invoke.Query = $Query
    }
    if ($null -ne $resolvedPath) {
        $invoke.Path = $resolvedPath
    }

    Export-MetraContextPack @invoke
}
