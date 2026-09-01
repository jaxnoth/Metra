# Loom shim — domain lives in modules/Loom. Loaded by Metra.psm1.

$loomManifest = Join-Path $script:MetraModuleRoot 'modules\Loom\Loom.psd1'
if (-not (Test-Path -LiteralPath $loomManifest)) {
    throw "Loom module missing: $loomManifest"
}
Import-Module $loomManifest -Force

function Invoke-MetraLoomCommand {
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
    return Invoke-LoomCommand @params
}
