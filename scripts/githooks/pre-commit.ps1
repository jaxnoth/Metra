# Metra pre-commit: enforce live == assess == gate (see inspect pre-commit).
# Install: .\metra.ps1 inspect hooks install  (sets git config metra.root)
# Emergency skip: METRA_SKIP_BING_GATE=1 git commit ...

$ErrorActionPreference = 'Stop'

if ($env:METRA_SKIP_BING_GATE -eq '1' -or $env:METRA_SKIP_INSPECT_HOOK -eq '1') {
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
    & $metra inspect pre-commit
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
