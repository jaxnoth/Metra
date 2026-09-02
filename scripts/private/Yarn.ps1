# Yarn shim — domain lives in modules/Yarn. Loaded by Metra.psm1.

$yarnManifest = Join-Path $script:MetraModuleRoot 'modules\Yarn\Yarn.psd1'
if (-not (Test-Path -LiteralPath $yarnManifest)) {
    throw "Yarn module missing: $yarnManifest"
}
Import-Module $yarnManifest -Force

function Invoke-MetraYarnCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot,
        [string]$Root
    )

    $params = @{
        Subcommand = $Subcommand
        ArgsRest   = $ArgsRest
    }
    if (-not [string]::IsNullOrWhiteSpace($MetraRoot)) { $params['MetraRoot'] = $MetraRoot }
    if (-not [string]::IsNullOrWhiteSpace($Root)) { $params['Root'] = $Root }
    return Invoke-YarnCommand @params
}
