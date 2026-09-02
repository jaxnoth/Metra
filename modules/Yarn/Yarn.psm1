# Yarn module loader. No Metra.psm1 import.

Set-StrictMode -Version Latest

$script:YarnModuleRoot = $PSScriptRoot

# Shared Patterns matcher (P3) - host checkout scripts/private; no Metra.psm1 import.
. ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\private\Patterns.ps1')))

. (Join-Path $PSScriptRoot 'Private\Storage.ps1')
. (Join-Path $PSScriptRoot 'Private\Validate.ps1')
. (Join-Path $PSScriptRoot 'Private\Hash.ps1')
. (Join-Path $PSScriptRoot 'Private\Rank.ps1')
. (Join-Path $PSScriptRoot 'Adapters\Metra.Adapters.ps1')
. (Join-Path $PSScriptRoot 'Private\Backlog.ps1')
. (Join-Path $PSScriptRoot 'Private\Scan.ps1')
. (Join-Path $PSScriptRoot 'Private\Synthesize.ps1')
. (Join-Path $PSScriptRoot 'Private\Pack.ps1')
. (Join-Path $PSScriptRoot 'Private\Approve.ps1')
. (Join-Path $PSScriptRoot 'Private\Daily.ps1')
. (Join-Path $PSScriptRoot 'Private\Domain.ps1')

$export = @(
    'Invoke-YarnCommand'
    'Get-YarnHostRoot'
    'Test-YarnCaptureAdapterAvailable'
    'Get-YarnCaptureLedger'
    'Get-MetraYarnRoot'
    'Initialize-MetraYarnLayout'
    'Get-MetraYarnBacklog'
    'Save-MetraYarnBacklogItems'
    'Sync-YarnBacklogItem'
    'Get-YarnPlanLinks'
    'Sync-YarnPlanLink'
    'Add-MetraYarnJournalEntry'
    'Get-YarnSchemaVersion'
    'Get-YarnHandoffContractVersion'
    'Get-YarnPackContractVersion'
    'Get-YarnRubricVersion'
    'Get-YarnSourceHash'
    'Get-YarnPlanContentHash'
    'Get-YarnPackInputHash'
    'Test-YarnPackFreshness'
    'Assert-YarnBacklogDocument'
    'Assert-YarnPlanLinksDocument'
    'Measure-YarnRank'
    'Sort-YarnBacklogItems'
    'Invoke-MetraYarnScan'
    'Invoke-MetraYarnSynthesize'
    'Invoke-MetraYarnPack'
    'Invoke-MetraYarnReconcile'
    'Invoke-MetraYarnPlanApprove'
    'Set-YarnPlanApproved'
    'Invoke-YarnHandoffIngestRetry'
    'Get-MetraYarnPending'
    'Get-MetraYarnDaily'
    'Get-MetraYarnStatus'
    'Write-YarnAtomicUtf8Text'
    'Get-YarnUtf8NoBomEncoding'
    'Test-YarnLoomQueueWriteForbidden'
    'Read-YarnFutureDevIdeas'
)

Export-ModuleMember -Function $export
