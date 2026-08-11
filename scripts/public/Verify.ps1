# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Test-MetraInstallation {
    <#
    .SYNOPSIS
        Tests the Metra installation.
    .DESCRIPTION
        Runs foundation, routing, profile, context, snapshot, self-documentation, updates
        (fail-soft), and Ask capability smoke checks. Returns a Boolean by default.
        The detailed report includes VerifyVersion for suite growth tracking.
        Read-only: no writes, no ShouldProcess.
    .PARAMETER Detailed
        Returns the full PASS/WARN/FAIL report instead of a Boolean.
    .EXAMPLE
        Test-MetraInstallation
    .EXAMPLE
        if (Test-MetraInstallation) { 'ok' }
    .EXAMPLE
        Test-MetraInstallation -Detailed
    .OUTPUTS
        System.Boolean by default, or a PSCustomObject verification report when -Detailed is used.
    #>
    [CmdletBinding()]
    [OutputType([bool], [PSCustomObject])]
    param(
        [switch]$Detailed
    )

    $report = Invoke-MetraVerify
    if ($null -eq $report) {
        if ($Detailed) { return $null }
        return $false
    }

    if ($Detailed) {
        return $report
    }

    return [bool](Get-MetraProp -Object $report -Name 'Ok' -Default $false)
}
