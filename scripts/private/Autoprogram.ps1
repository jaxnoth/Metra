# DEPRECATED shim (M2) — AutoProgram lives in modules/AutoProgram.
# Loaded by Metra.psm1 for façade compatibility. Do not add domain logic here.

$apManifest = Join-Path $script:MetraModuleRoot 'modules\AutoProgram\AutoProgram.psd1'
if (-not (Test-Path -LiteralPath $apManifest)) {
    throw "AutoProgram module missing: $apManifest"
}
Import-Module $apManifest -Force

function Invoke-MetraAutoprogramCommand {
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
    return Invoke-AutoProgramCommand @params
}
