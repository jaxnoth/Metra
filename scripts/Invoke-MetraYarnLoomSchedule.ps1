# Scheduled entrypoint for MetraYarnLoomDaily / MetraYarnLoomPulse.
# Modes:
#   Daily (default): yarn scan -> yarn daily -Reconcile -> loom loop -UntilDailyGate -Confirm
#   Pulse: yarn scan -> loom loop -UntilDailyGate -Confirm (skips reconcile)
# Exit codes match Invoke-MetraYarnLoomSchedule (0-4).

[CmdletBinding()]
param(
    [ValidateSet('Daily', 'Pulse')]
    [string]$Mode = 'Daily'
)

$ErrorActionPreference = 'Stop'
$metraRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$yarnManifest = Join-Path $metraRoot 'modules\Yarn\Yarn.psd1'
Import-Module $yarnManifest -Force
$result = Invoke-MetraYarnLoomSchedule -MetraRoot $metraRoot -Mode $Mode
$code = 1
if ($null -ne $result -and $null -ne $result.exitCode) {
    $code = [int]$result.exitCode
}
exit $code
