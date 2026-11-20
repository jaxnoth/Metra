# Shared hook project-name resolution (pre-push / pre-commit).
# Prefer git config metra.project, then Metra checkout aliases, then folder leaf.
# Null-safe: never call .Trim() on a null config value.

function Resolve-MetraHookProjectName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [AllowNull()][string]$ConfiguredProject,
        [string]$FolderLeaf,
        [bool]$IsMetraRoot = $false
    )

    $leaf = if (-not [string]::IsNullOrWhiteSpace($FolderLeaf)) {
        $FolderLeaf.Trim()
    }
    else {
        Split-Path -Leaf ([string]$RepoRoot)
    }

    $cfg = ''
    if ($null -ne $ConfiguredProject -and -not [string]::IsNullOrWhiteSpace([string]$ConfiguredProject)) {
        $cfg = ([string]$ConfiguredProject).Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($cfg)) {
        return $cfg
    }
    if ($leaf -match '^(?i)(_meta|_metra|metra)$' -or $IsMetraRoot) {
        return 'Metra'
    }
    return $leaf
}

function Get-MetraHookConfiguredProject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)

    $raw = @(& git -C $RepoRoot config --get metra.project 2>$null) | Select-Object -First 1
    if ($null -eq $raw) { return $null }
    return [string]$raw
}
