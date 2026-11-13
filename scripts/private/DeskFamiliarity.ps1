# Desk familiarity numeric dial - RETIRED 2026-11-12.
# Replaced by operator working-notes (OperatorWorkingNotes.ps1).
# Keep this file so old callers get a clear retired error instead of a missing command.

Set-StrictMode -Version Latest

function Invoke-MetraDeskFamiliarityCommand {
    <#
    .SYNOPSIS
        Retired. Desk familiarity Cold/Warming/Familiar dial is no longer supported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $null = $Subcommand
    $null = $ArgsRest
    $null = $MetraRoot
    throw @"
profile familiarity is retired (2026-11-12).

The Cold/Warming/Familiar numeric desk dial is no longer used.
Use operator working-notes instead:
  %LOCALAPPDATA%\Metra\operator-working-notes.local.json
  (pack path: machine-data/operator-working-notes.local.json via export-profile / import-profile)

See docs/examples/operator-working-notes.local.example.json and docs/Customizing-Metra.md.
"@
}
