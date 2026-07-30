# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Test-MetraInstallation {
    <#
    .SYNOPSIS
        Tests the Metra installation.
    .DESCRIPTION
        Runs routing fixtures, profile previews, bounded context generation, chat search, and
        drift checks. Returns a Boolean by default.
    .PARAMETER Detailed
        Returns the full PASS/WARN/FAIL report instead of a Boolean.
    .EXAMPLE
        Test-MetraInstallation
    .EXAMPLE
        Test-MetraInstallation -Detailed
    .OUTPUTS
        Boolean, or a PSCustomObject verification report when Detailed is used.
    #>
    [CmdletBinding()]
    param(
        [switch]$Detailed
    )

    $report = Invoke-MetraVerify
    if ($Detailed) { return $report }
    return [bool]$report.Ok
}

