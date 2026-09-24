# Porter continuity smoke (Stage 1 path; no Stage 2 purge)
# Validates leaf mirror visibility, handoff CLI, and prep skip/advance plumbing.

[CmdletBinding()]
param(
    [string]$MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failed = 0
function Assert-Smoke {
    param([bool]$Ok, [string]$Name, [string]$Detail = '')
    if ($Ok) {
        Write-Host "PASS: $Name"
    }
    else {
        Write-Host "FAIL: $Name $Detail" -ForegroundColor Red
        $script:failed++
    }
}

$cli = Join-Path $MetraRoot 'scripts\Invoke-MetraPorterCli.ps1'
$porter = Join-Path $MetraRoot 'scripts\Invoke-MetraPorter.ps1'
$charter = Join-Path $MetraRoot 'docs\Cursor-Project-Metra-Charter.md'
$playbook = Join-Path $MetraRoot 'docs\playbooks\project-lane.md'
$openPlans = Join-Path $MetraRoot 'porter\OPEN-PLANS.md'
$gitignore = Join-Path $MetraRoot '.gitignore'

Assert-Smoke (Test-Path -LiteralPath $cli) 'Porter CLI present'
Assert-Smoke (Test-Path -LiteralPath $porter) 'Porter refresh script present'
Assert-Smoke (Test-Path -LiteralPath $charter) 'Charter present'
Assert-Smoke (Test-Path -LiteralPath $playbook) 'project-lane playbook present'

$gi = Get-Content -LiteralPath $gitignore -Raw
Assert-Smoke ($gi -match 'porter/manifest\.json') 'manifest stays gitignored'
Assert-Smoke ($gi -notmatch '(?m)^porter/OPEN-PLANS\.md') 'OPEN-PLANS not ignored'
Assert-Smoke ($gi -notmatch '(?m)^porter/plans/\*\*') 'plans/** not bulk-ignored'

& $porter -MetraRoot $MetraRoot | Out-Null
Assert-Smoke (Test-Path -LiteralPath $openPlans) 'OPEN-PLANS after refresh'

$stem = 'smoke-porter-continuity'
& $cli -Action handoff -HandoffVerb set -Stem $stem -MetraRoot $MetraRoot -Notes 'smoke' | Out-Null
$show = & $cli -Action handoff -HandoffVerb show -MetraRoot $MetraRoot | Out-String
Assert-Smoke ($show -match 'awaiting-prepare-bing') 'handoff set -> awaiting-prepare-bing'
Assert-Smoke ($show -match $stem) 'handoff show lists stem'

$handoffJson = Join-Path $MetraRoot 'porter\handoff.json'
Assert-Smoke (Test-Path -LiteralPath $handoffJson) 'handoff.json written (gitignored machine state)'

# Prep with awaiting row would call Inspect; for smoke we clear first then confirm skip path,
# then re-set and advance via handoff ready (Pulse path uses Inspect; operator Bing stays human).
& $cli -Action handoff -HandoffVerb clear -Stem $stem -MetraRoot $MetraRoot | Out-Null
$prepSkip = & $cli -Action prep -MetraRoot $MetraRoot
Assert-Smoke ([bool]$prepSkip.skipped) 'prep skips when no awaiting rows'

& $cli -Action handoff -HandoffVerb set -Stem $stem -MetraRoot $MetraRoot | Out-Null
& $cli -Action handoff -HandoffVerb ready -Stem $stem -MetraRoot $MetraRoot | Out-Null
$showReady = & $cli -Action handoff -HandoffVerb show -MetraRoot $MetraRoot | Out-String
Assert-Smoke ($showReady -match 'ready-for-bing') 'handoff ready advances status (Inspect path separate)'

& $cli -Action handoff -HandoffVerb clear -Stem $stem -MetraRoot $MetraRoot | Out-Null

$sched = Get-Content -LiteralPath (Join-Path $MetraRoot 'modules\Yarn\Private\Schedule.ps1') -Raw
Assert-Smoke ($sched -match 'Stage=InspectPrep') 'Pulse Schedule has InspectPrep stage'
Assert-Smoke ($sched -match "Action prep") 'Pulse calls porter prep'

Assert-Smoke (-not ($sched -match 'gate affirm')) 'Pulse never Bing-affirms'

Write-Host ''
if ($failed -gt 0) {
    Write-Host "Porter continuity smoke FAILED ($failed)" -ForegroundColor Red
    exit 1
}
Write-Host 'Porter continuity smoke OK (no Stage 2 purge; Bing affirm remains human).' -ForegroundColor Green
exit 0
