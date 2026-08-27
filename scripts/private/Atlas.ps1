# Metra Atlas passthrough - resolves Atlas checkout and forwards CLI args.

function Get-MetraAtlasProjectPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $candidates = @(
        (Join-Path (Split-Path -Parent $MetraRoot) 'Atlas')
        'C:\Projects\Atlas'
    )
    foreach ($c in $candidates) {
        $cli = Join-Path $c 'Atlas.ps1'
        if (Test-Path -LiteralPath $cli) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    return $null
}

function Invoke-MetraAtlasCommand {
    [CmdletBinding()]
    param(
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $atlasRoot = Get-MetraAtlasProjectPath -MetraRoot $MetraRoot
    if (-not $atlasRoot) {
        throw 'Atlas project not found (expected sibling C:\Projects\Atlas with Atlas.ps1).'
    }
    $cli = Join-Path $atlasRoot 'Atlas.ps1'
    if (-not $ArgsRest -or $ArgsRest.Count -eq 0) {
        & $cli help
        return
    }
    & $cli @ArgsRest
}
