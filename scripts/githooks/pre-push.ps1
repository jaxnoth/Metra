# Metra pre-push: security-audit must be clean before push to a public remote.
# Install: .\metra.ps1 inspect hooks install  (sets git config metra.root + core.hooksPath)
# Emergency skip: METRA_SKIP_SECURITY_PUSH=1 git push ...
# Policy: SECURITY.md (Public push gate); docs/Decisions.md (2026-10-20)

$ErrorActionPreference = 'Stop'

# METRA_SKIP_INSPECT_HOOK skips all hook work. METRA_SKIP_SECURITY_PUSH only skips
# security-audit; protected-branch ship-lock still runs.
if ($env:METRA_SKIP_INSPECT_HOOK -eq '1') {
    Write-Host 'pre-push: skipped (METRA_SKIP_INSPECT_HOOK=1)'
    exit 0
}
$skipSecurityAuditOnly = ($env:METRA_SKIP_SECURITY_PUSH -eq '1')

function Resolve-MetraPrePushScript {
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

function Test-MetraPublicGitRemoteUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    $u = $Url.Trim()
    # github.com / gist.github.com (https or ssh) - public product surface unless clearly private host.
    if ($u -match '(?i)github\.com[/:]') { return $true }
    if ($u -match '(?i)gitlab\.com[/:]') { return $true }
    return $false
}

$repoRoot = [string](@(& git rev-parse --show-toplevel 2>$null) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    Write-Error 'pre-push: not inside a git repository.'
    exit 1
}

$remoteName = if ($args.Count -ge 1) { [string]$args[0] } else { '' }
$remoteUrl = if ($args.Count -ge 2) { [string]$args[1] } else { '' }
if ([string]::IsNullOrWhiteSpace($remoteUrl) -and -not [string]::IsNullOrWhiteSpace($remoteName)) {
    $remoteUrl = [string](@(& git -C $repoRoot remote get-url $remoteName 2>$null) | Select-Object -First 1)
}
# git push <url> may pass the URL as $1 only; treat name as URL when url arg is blank.
$effectiveRemote = if (-not [string]::IsNullOrWhiteSpace($remoteUrl)) { $remoteUrl } else { $remoteName }

# Read stdin ref tuples (<local-ref> <local-sha> <remote-ref> <remote-sha>) before skip/exit.
$pushLines = @($input)
$remoteBranches = New-Object System.Collections.Generic.List[string]
foreach ($line in $pushLines) {
    $parts = @(([string]$line).Trim() -split '\s+')
    if ($parts.Count -lt 3) { continue }
    $remoteRef = [string]$parts[2]
    if ($remoteRef -match '^refs/heads/(.+)$') {
        [void]$remoteBranches.Add($Matches[1])
    }
    elseif ($remoteRef -and $remoteRef -ne '(delete)') {
        [void]$remoteBranches.Add(($remoteRef -replace '^refs/heads/', ''))
    }
}

$metra = Resolve-MetraPrePushScript -RepoRoot $repoRoot
if (-not $metra) {
    Write-Error 'pre-push: metra.ps1 not found. Set METRA_ROOT or run inspect hooks install.'
    exit 1
}

$isPublicRemote = Test-MetraPublicGitRemoteUrl -Url $effectiveRemote
$isMetraRoot = Test-Path -LiteralPath (Join-Path $repoRoot 'metra.ps1')
# Protected-branch ship-lock runs for every remote. Public security-audit stays public/Metra-only.
$runSecurityAudit = $isPublicRemote -or $isMetraRoot

Write-Host ("pre-push: protected-branch check remote={0}" -f $(if ($remoteUrl) { $remoteUrl } else { $remoteName }))
Push-Location $repoRoot
try {
    # Prior git probes in this hook (e.g. config --get-all metra.root) may leave
    # $LASTEXITCODE=1. In-process & of metra.ps1 does not always reset it on success.
    $LASTEXITCODE = 0
    $projLeaf = Split-Path -Leaf $repoRoot
    # Prefer registry name when folder leaf is a Metra checkout alias (_meta / Metra / _metra).
    # Never adopt METRA_LOOM_SHIP_PROJECT for sibling repos - that would check the wrong lock/policy.
    $projName = $projLeaf
    if ($projLeaf -match '^(?i)(_meta|_metra|metra)$' -or $isMetraRoot) {
        $projName = 'Metra'
    }
    $prePushArgs = @('inspect', 'pre-push', '-Name', $projName)
    foreach ($rb in @($remoteBranches | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$rb)) {
            $prePushArgs += @('-RemoteBranch', [string]$rb)
        }
    }
    & $metra @prePushArgs
    if (-not $? -or $LASTEXITCODE -ne 0) {
        Write-Error 'pre-push blocked: protected-branch / ship-lock guard failed.'
        exit 1
    }
    if (-not $runSecurityAudit -or $skipSecurityAuditOnly) {
        if ($skipSecurityAuditOnly) {
            Write-Host 'pre-push: security-audit skipped (METRA_SKIP_SECURITY_PUSH=1); ship-lock already checked.'
        }
        exit 0
    }
    Write-Host ("pre-push: security-audit (public/Metra push gate) remote={0}" -f $(if ($remoteUrl) { $remoteUrl } else { $remoteName }))
    # -Force maps to FailOnFindings in metra.ps1 security-audit
    & $metra security-audit -Force -Path $repoRoot
    if (-not $? -or $LASTEXITCODE -ne 0) {
        Write-Error 'pre-push blocked: security-audit FAIL. Scrub InternalTopology / RestrictedDataMap (SECURITY.md). Skip only with METRA_SKIP_SECURITY_PUSH=1.'
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
