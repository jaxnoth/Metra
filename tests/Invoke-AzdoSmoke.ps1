# Live AzDO smoke (requires METRA_AZDO_PAT in User/Process env or docs/azdo.local.json)
$ErrorActionPreference = 'Stop'
$metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $metraRoot

$pat = [Environment]::GetEnvironmentVariable('METRA_AZDO_PAT', 'User')
if (-not [string]::IsNullOrWhiteSpace($pat)) {
    $env:METRA_AZDO_PAT = $pat.Trim()
}

$status = .\metra.ps1 azdo status
$status | Format-List

if (-not $status.ready) {
    Write-Warning 'AzDO not ready in this shell (no PAT). Skipping live API smoke; Pester already passed.'
    exit 0
}

Write-Host '=== azdo repos (count) ==='
$repos = @(.\metra.ps1 azdo repos)
Write-Host "repos: $($repos.Count)"

Write-Host '=== azdo gaps ==='
$gaps = .\metra.ps1 azdo gaps
Write-Host "MatchedPresent: $($gaps.MatchedPresentCount) InAzdoNotInRegistry: $($gaps.InAzdoNotInRegistryCount)"

Write-Host '=== azdo get Colleague AGENTS.md ==='
$file = .\metra.ps1 azdo get -Project PowerShell -Repo Colleague -ItemPath AGENTS.md
Write-Host "path: $($file.path) chars: $($file.content.Length) truncated: $($file.truncated)"

Write-Host '=== azdo search WAGC ==='
$search = .\metra.ps1 azdo search 'WAGC' -Project PowerShell -Repo Colleague
Write-Host "searchUsed: $($search.searchUsed) hits: $($search.hitCount)"

Write-Host '=== azdo ideas (degraded ok) ==='
$ideas = .\metra.ps1 azdo ideas -Topic 'Smoke test ideas draft'
Write-Host "degraded: $($ideas.degraded) gather repos: $(@($ideas.gather).Count)"

Write-Host 'AzDO live smoke complete.'
