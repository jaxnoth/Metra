# Metra pre-commit: require Bing affirm for the assessed report (live drift warns only).
# Install: .\metra.ps1 inspect hooks install  (sets git config metra.root)
# Full hook skip: METRA_SKIP_INSPECT_HOOK=1. Bing-gate-only skip is handled in-process
# (METRA_SKIP_BING_GATE=1) so work-branch safety and protected-branch refuse still run.

$ErrorActionPreference = 'Stop'

if ($env:METRA_SKIP_INSPECT_HOOK -eq '1') {
    exit 0
}

function Resolve-MetraPreCommitScript {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $candidates = New-Object System.Collections.Generic.List[string]

    function Add-Candidate([string]$Path) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        if ($seen.Add($Path)) { [void]$candidates.Add($Path) }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$env:METRA_ROOT)) {
        Add-Candidate (Join-Path ([string]$env:METRA_ROOT).Trim() 'metra.ps1')
    }
    $cfgRaw = @(& git -C $RepoRoot config --get-all metra.root 2>$null) | Select-Object -First 1
    $cfgRoot = if ($null -eq $cfgRaw) { '' } else { [string]$cfgRaw.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($cfgRoot)) {
        Add-Candidate (Join-Path $cfgRoot 'metra.ps1')
    }
    Add-Candidate (Join-Path $RepoRoot 'metra.ps1')

    $dir = $RepoRoot
    while (-not [string]::IsNullOrWhiteSpace($dir)) {
        Add-Candidate (Join-Path $dir 'metra.ps1')
        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

$repoRoot = [string](@(& git rev-parse --show-toplevel 2>$null) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    Write-Error 'pre-commit: not inside a git repository.'
    exit 1
}

$metra = Resolve-MetraPreCommitScript -RepoRoot $repoRoot
if (-not $metra) {
    Write-Error 'pre-commit: metra.ps1 not found. Set METRA_ROOT, run inspect hooks install (metra.root), or place metra.ps1 on a parent path.'
    exit 1
}

Push-Location $repoRoot
try {
    # Prefer metra.project for nested bite repos (CDM chef/); same order as pre-push.
    . (Join-Path $PSScriptRoot 'HookProjectName.ps1')
    $isMetraRoot = Test-Path -LiteralPath (Join-Path $repoRoot 'metra.ps1')
    $cfgProject = Get-MetraHookConfiguredProject -RepoRoot $repoRoot
    $projName = Resolve-MetraHookProjectName -RepoRoot $repoRoot -ConfiguredProject $cfgProject `
        -FolderLeaf (Split-Path -Leaf $repoRoot) -IsMetraRoot:$isMetraRoot
    & $metra inspect pre-commit -Name $projName -RepoRoot $repoRoot
    if (-not $?) {
        exit 1
    }
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Pop-Location
}
