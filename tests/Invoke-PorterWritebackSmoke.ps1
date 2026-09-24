# Porter Agent Store write-back smoke (B+A + projectKey). Fully isolated temp MetraRoot.

[CmdletBinding()]
param(
    [string]$MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failed = 0
function Assert-Smoke {
    param([bool]$Ok, [string]$Name, [string]$Detail = '')
    if ($Ok) { Write-Host "PASS: $Name" }
    else {
        Write-Host "FAIL: $Name $Detail" -ForegroundColor Red
        $script:failed++
    }
}

$porter = Join-Path $MetraRoot 'scripts\Invoke-MetraPorter.ps1'
$example = Join-Path $MetraRoot 'porter\cursor-project.local.example.json'
Assert-Smoke (Test-Path -LiteralPath $porter) 'Porter script present'
Assert-Smoke (Test-Path -LiteralPath $example) 'cursor-project.local.example.json present'
$ex = Get-Content -LiteralPath $example -Raw | ConvertFrom-Json
Assert-Smoke ($ex.projectKey -eq 'Metra') 'example projectKey is Metra'
Assert-Smoke (-not [string]::IsNullOrWhiteSpace([string]$ex.projectId)) 'example has projectId placeholder'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("porter-wb-" + [guid]::NewGuid().ToString('n'))
$isoRoot = Join-Path $tempRoot 'metra'
$cfgPath = Join-Path $tempRoot 'cursor-project.local.json'
$storesRoot = Join-Path $tempRoot 'agent-stores'
$projectId = 'test-metra-project-id'
$storePlans = Join-Path $storesRoot "$projectId\files\docs\plans"
$cursorPlans = Join-Path $tempRoot 'cursor-plans'
$localData = Join-Path $tempRoot 'localapp'
$ledgerPath = Join-Path $localData 'Metra\porter\writeback-ledger.json'

New-Item -ItemType Directory -Force -Path @(
    (Join-Path $isoRoot 'porter\plans'),
    (Join-Path $isoRoot 'plans'),
    $storePlans,
    $cursorPlans,
    (Join-Path $localData 'Metra\porter')
) | Out-Null

Copy-Item -LiteralPath (Join-Path $MetraRoot 'porter\scope.json') -Destination (Join-Path $isoRoot 'porter\scope.json') -Force
Set-Content -LiteralPath (Join-Path $isoRoot 'porter\plans\README.md') -Value "# plans`n" -Encoding utf8
Set-Content -LiteralPath (Join-Path $isoRoot 'plans\index.yaml') -Value "schemaVersion: 1`nentries: []`n" -Encoding utf8
Set-Content -LiteralPath (Join-Path $storesRoot "$projectId\files\docs\metra-charter.md") -Value "# Metra`n" -Encoding utf8

# Missing config
& $porter -MetraRoot $isoRoot -CursorPlansDir $cursorPlans -CursorProjectConfigPath (Join-Path $tempRoot 'missing.json') -AgentStoresRoot $storesRoot -WritebackLedgerPath $ledgerPath 2>&1 | Out-Null
$man = Get-Content (Join-Path $isoRoot 'porter\manifest.json') -Raw | ConvertFrom-Json
Assert-Smoke ([int]$man.counts.writebackSkippedNoProjectId -ge 1 -or [string]$man.agentStoreWriteback.skipReason -eq 'missing-config') 'missing config soft-skips write-back'

# Wrong projectKey
@{ schemaVersion = 1; projectId = $projectId; projectKey = 'TicketTracker' } | ConvertTo-Json |
    Set-Content -LiteralPath $cfgPath -Encoding utf8
& $porter -MetraRoot $isoRoot -CursorPlansDir $cursorPlans -CursorProjectConfigPath $cfgPath -AgentStoresRoot $storesRoot -WritebackLedgerPath $ledgerPath 2>&1 | Out-Null
$man = Get-Content (Join-Path $isoRoot 'porter\manifest.json') -Raw | ConvertFrom-Json
Assert-Smoke ([int]$man.counts.writebackSkippedProjectKeyMismatch -ge 1 -or [string]$man.agentStoreWriteback.skipReason -eq 'projectKey-mismatch') 'wrong projectKey soft-skips'

@{ schemaVersion = 1; projectId = $projectId; projectKey = 'Metra' } | ConvertTo-Json |
    Set-Content -LiteralPath $cfgPath -Encoding utf8

$draftDest = Join-Path $storePlans 'porter-writeback-smoke-draft.plan.md'
Set-Content -LiteralPath $draftDest -Value "---`nname: smoke draft`nstatus: draft`n---`n`ndraft body`n" -Encoding utf8
$draftBefore = Get-Content -LiteralPath $draftDest -Raw
& $porter -MetraRoot $isoRoot -CursorPlansDir $cursorPlans -CursorProjectConfigPath $cfgPath -AgentStoresRoot $storesRoot -WritebackLedgerPath $ledgerPath 2>&1 | Out-Null
$draftAfter = Get-Content -LiteralPath $draftDest -Raw
Assert-Smoke ($draftBefore -eq $draftAfter) 'draft Agent Store body not clobbered without Approved desk leaf'

$suffix = [guid]::NewGuid().ToString('n').Substring(0, 8)
$leafName = "porter_writeback_smoke_$suffix.plan.md"
$leafPath = Join-Path $cursorPlans $leafName
$wbPath = Join-Path $storePlans 'porter-writeback-smoke.plan.md'
$v1Tag = [guid]::NewGuid().ToString('n').Substring(0, 8)
Set-Content -LiteralPath $leafPath -Value @"
---
name: Porter writeback smoke
status: Approved
approveForLoom: true
---

# Porter writeback smoke

Body v1 $v1Tag
"@ -Encoding utf8

& $porter -MetraRoot $isoRoot -CursorPlansDir $cursorPlans -CursorProjectConfigPath $cfgPath -AgentStoresRoot $storesRoot -WritebackLedgerPath $ledgerPath 2>&1 | Out-Null
Assert-Smoke (Test-Path -LiteralPath $wbPath) 'Approved leaf write-back created Agent Store file'
$man = Get-Content (Join-Path $isoRoot 'porter\manifest.json') -Raw | ConvertFrom-Json
Assert-Smoke ([int]$man.counts.writebackWritten -ge 1) 'manifest counts writebackWritten'

& $porter -MetraRoot $isoRoot -CursorPlansDir $cursorPlans -CursorProjectConfigPath $cfgPath -AgentStoresRoot $storesRoot -WritebackLedgerPath $ledgerPath 2>&1 | Out-Null
$man2 = Get-Content (Join-Path $isoRoot 'porter\manifest.json') -Raw | ConvertFrom-Json
Assert-Smoke ([int]$man2.counts.writebackSkippedUnchanged -ge 1) 'second refresh skips when source+dest+ledger match'

# Destination drift: Project mutates Agent Store after Approve; Porter restores byte-identical v1
$v1Body = Get-Content -LiteralPath $wbPath -Raw
Set-Content -LiteralPath $wbPath -Value "DRIFT-MUTATION $($v1Tag)`n" -Encoding utf8
Assert-Smoke ((Get-Content -LiteralPath $wbPath -Raw) -ne $v1Body) 'Agent Store destination mutated for drift case'
& $porter -MetraRoot $isoRoot -CursorPlansDir $cursorPlans -CursorProjectConfigPath $cfgPath -AgentStoresRoot $storesRoot -WritebackLedgerPath $ledgerPath 2>&1 | Out-Null
$restored = Get-Content -LiteralPath $wbPath -Raw
Assert-Smoke ($restored -eq $v1Body) 'destination drift restored byte-for-byte to approved v1'
$manDrift = Get-Content (Join-Path $isoRoot 'porter\manifest.json') -Raw | ConvertFrom-Json
Assert-Smoke ([int]$manDrift.counts.writebackWritten -ge 1) 'drift restore increments writebackWritten'
Assert-Smoke ([int]$manDrift.counts.writebackWrittenDriftCorrected -ge 1) 'drift restore increments writebackWrittenDriftCorrected'

# Source change: Approved leaf v2 overwrites destination and ledger
$v2Tag = [guid]::NewGuid().ToString('n').Substring(0, 8)
Set-Content -LiteralPath $leafPath -Value @"
---
name: Porter writeback smoke
status: Approved
approveForLoom: true
---

# Porter writeback smoke

Body v2 $v2Tag
"@ -Encoding utf8
& $porter -MetraRoot $isoRoot -CursorPlansDir $cursorPlans -CursorProjectConfigPath $cfgPath -AgentStoresRoot $storesRoot -WritebackLedgerPath $ledgerPath 2>&1 | Out-Null
$v2Body = Get-Content -LiteralPath $wbPath -Raw
Assert-Smoke ($v2Body -match [regex]::Escape("Body v2 $v2Tag")) 'source v2 write-back updates Agent Store body'
Assert-Smoke ($v2Body -notmatch [regex]::Escape("Body v1 $v1Tag")) 'source v2 replaces prior v1 body'
$manV2 = Get-Content (Join-Path $isoRoot 'porter\manifest.json') -Raw | ConvertFrom-Json
Assert-Smoke ([int]$manV2.counts.writebackWritten -ge 1) 'source v2 increments writebackWritten'
$ledger = Get-Content -LiteralPath $ledgerPath -Raw | ConvertFrom-Json
$stemKey = 'porter-writeback-smoke'
$ledgerHash = [string]$ledger.stems.$stemKey.contentHash
Assert-Smoke (-not [string]::IsNullOrWhiteSpace($ledgerHash)) 'ledger records stem after v2 write'
# Hash of dest should match ledger (recompute via second skip)
& $porter -MetraRoot $isoRoot -CursorPlansDir $cursorPlans -CursorProjectConfigPath $cfgPath -AgentStoresRoot $storesRoot -WritebackLedgerPath $ledgerPath 2>&1 | Out-Null
$manV2Skip = Get-Content (Join-Path $isoRoot 'porter\manifest.json') -Raw | ConvertFrom-Json
Assert-Smoke ([int]$manV2Skip.counts.writebackSkippedUnchanged -ge 1) 'after v2, matching dest+ledger skips'

# Live checkout porter/plans must be untouched
$livePlans = @(Get-ChildItem (Join-Path $MetraRoot 'porter\plans\*.plan.md') -ErrorAction SilentlyContinue)
Assert-Smoke ($livePlans.Count -ge 1) 'live porter/plans snapshots still present'

Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($failed -gt 0) {
    Write-Host "Porter write-back smoke FAILED ($failed)" -ForegroundColor Red
    exit 1
}
Write-Host 'Porter write-back smoke OK.' -ForegroundColor Green
exit 0
