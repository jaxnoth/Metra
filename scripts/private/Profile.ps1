# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Get-MetraProfileFileMap {
    <#
    .SYNOPSIS
        Relative paths that make up an operator profile pack (same layout as profiles/sample).
    #>
    return @(
        'metra.config.json',
        'projects.local.json',
        '.cursor/rules/metra-persona.local.mdc',
        '.cursor/rules/metra-humor.local.mdc',
        '.cursor/rules/metra-teaching-gentle.local.mdc',
        '.cursor/rules/metra-learned.local.mdc',
        'docs/operator-contract.json',
        'docs/decision-registry.json'
    )
}

function Resolve-MetraProfileSourceDir {
    <#
    .SYNOPSIS
        Resolves a profile pack path to an unpacked directory (extracts zip to temp when needed).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $expanded = [System.Environment]::ExpandEnvironmentVariables($Path)
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path (Get-Location).Path $expanded
    }
    $full = [System.IO.Path]::GetFullPath($expanded)

    if (-not (Test-Path -LiteralPath $full)) {
        throw "Profile path not found: $full"
    }

    $item = Get-Item -LiteralPath $full
    if ($item.PSIsContainer) {
        return [PSCustomObject]@{
            Directory = $item.FullName
            TempDir   = $null
            Source    = $item.FullName
            IsZip     = $false
        }
    }

    if ($item.Extension -ne '.zip') {
        throw "Profile path must be a directory or .zip file: $full"
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-profile-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Expand-Archive -LiteralPath $item.FullName -DestinationPath $tempRoot -Force

    $manifest = Get-ChildItem -LiteralPath $tempRoot -Filter 'metra-profile.json' -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $manifest) {
        $manifest = Get-ChildItem -LiteralPath $tempRoot -Filter 'meta-profile.json' -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    $dir = if ($manifest) {
        $manifest.Directory.FullName
    }
    else {
        $children = @(Get-ChildItem -LiteralPath $tempRoot -Directory)
        $childDir = if ($children.Count -eq 1) { $children[0].FullName } else { $null }
        if ($childDir -and (
                (Test-Path (Join-Path $childDir 'metra-profile.json')) -or
                (Test-Path (Join-Path $childDir 'meta-profile.json'))
            )) {
            $childDir
        }
        else {
            $tempRoot
        }
    }

    return [PSCustomObject]@{
        Directory = $dir
        TempDir   = $tempRoot
        Source    = $item.FullName
        IsZip     = $true
    }
}

