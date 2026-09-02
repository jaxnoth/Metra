# Loom module loader. No Metra.psm1 import.

Set-StrictMode -Version Latest

$script:LoomModuleRoot = $PSScriptRoot
$script:LoomHostRootOverride = $null

. (Join-Path $PSScriptRoot 'Private\Storage\Storage.ps1')
. (Join-Path $PSScriptRoot 'Private\Contracts\Contracts.ps1')
. (Join-Path $PSScriptRoot 'Adapters\Metra.Adapters.ps1')
. (Join-Path $PSScriptRoot 'Private\Migrate.ps1')
. (Join-Path $PSScriptRoot 'Private\Daily.ps1')
. (Join-Path $PSScriptRoot 'Private\Review.ps1')
. (Join-Path $PSScriptRoot 'Private\Runner.ps1')
. (Join-Path $PSScriptRoot 'Private\Domain.ps1')

$export = @(
    'Invoke-LoomCommand'
    'Get-LoomStatusCatalog'
    'Get-LoomActiveTransitions'
    'Get-LoomRoutingContext'
    'Test-LoomRoutingAdapterAvailable'
    'Test-LoomCaptureAdapterAvailable'
    'Test-LoomContract'
    'Invoke-LoomInspectAdapter'
    'Invoke-LoomVerifyAdapter'
    'Get-LoomHostRoot'
    'Get-MetraLoomSchemaVersion'
    'Get-MetraLoomRoot'
    'Resolve-MetraLoomRoot'
    'Get-MetraLoomMinimumRoutingConfidence'
    'Get-MetraLoomPhaseATransitions'
    'Test-MetraLoomTransition'
    'Initialize-MetraLoomLayout'
    'Get-MetraLoomState'
    'Save-MetraLoomState'
    'Get-MetraLoomJournalPath'
    'Add-MetraLoomJournalEntry'
    'Get-MetraLoomJournalEntries'
    'Test-MetraLoomItemId'
    'Resolve-MetraLoomItemPath'
    'Get-MetraLoomQueueItemPath'
    'Get-MetraLoomQueueItems'
    'Get-MetraLoomQueueItem'
    'Save-MetraLoomQueueItem'
    'Test-MetraLoomQueueItemSchema'
    'New-MetraLoomQueueId'
    'New-MetraLoomCandidateId'
    'Invoke-MetraLoomStateChange'
    'Get-MetraLoomPlanRoots'
    'Get-MetraLoomFormalPlans'
    'Read-MetraLoomPlanFile'
    'Resolve-MetraLoomPlanProject'
    'Measure-MetraLoomTriageScore'
    'Test-MetraLoomEligibility'
    'Save-MetraLoomCandidate'
    'Get-MetraLoomCandidate'
    'Add-MetraLoomQueueItem'
    'New-MetraLoomQueueItemFromCandidate'
    'Invoke-MetraLoomTriage'
    'Invoke-MetraLoomEnqueueFromPlan'
        'Invoke-MetraLoomDailyStub'
        'Invoke-MetraLoomDailyBuild'
        'Invoke-MetraLoomDailyPackDiff'
        'Invoke-MetraLoomDailyApprove'
        'Read-LoomDailyPlanDirectives'
        'Test-LoomProjectAcceptanceGate'
        'Get-LoomSlice5Transitions'
        'Get-LoomProjectKey'
        'Invoke-MetraLoomRun'
    'Invoke-MetraLoomReview'
    'Invoke-MetraLoomMigrate'
    'Get-LoomActiveTransitionMap'
    'Write-LoomAtomicUtf8Text'
    'Get-LoomUtf8NoBomEncoding'
    'Test-LoomPathWithinRoot'
    'Test-LoomExecutionBranchPrefix'
)

Export-ModuleMember -Function $export
