# AutoProgram / Loom module loader. No Metra.psm1 import.

Set-StrictMode -Version Latest

$script:AutoProgramModuleRoot = $PSScriptRoot
$script:AutoProgramHostRootOverride = $null

. (Join-Path $PSScriptRoot 'Private\Storage\Storage.ps1')
. (Join-Path $PSScriptRoot 'Private\Contracts\Contracts.ps1')
. (Join-Path $PSScriptRoot 'Adapters\Metra.Adapters.ps1')
. (Join-Path $PSScriptRoot 'Private\Runner.ps1')
. (Join-Path $PSScriptRoot 'Private\Domain.ps1')

# Compatibility alias for Metra façade / existing exports
Set-Alias -Name Invoke-MetraAutoprogramCommand -Value Invoke-AutoProgramCommand

$export = @(
    'Invoke-AutoProgramCommand'
    'Get-AutoProgramStatusCatalog'
    'Get-AutoProgramActiveTransitions'
    'Get-AutoProgramRoutingContext'
    'Test-AutoProgramRoutingAdapterAvailable'
    'Test-AutoProgramCaptureAdapterAvailable'
    'Test-AutoProgramContract'
    'Invoke-AutoProgramInspectAdapter'
    'Invoke-AutoProgramVerifyAdapter'
    'Get-AutoProgramHostRoot'
    'Get-MetraAutoprogramSchemaVersion'
    'Get-MetraAutoprogramRoot'
    'Get-MetraAutoprogramMinimumRoutingConfidence'
    'Get-MetraAutoprogramPhaseATransitions'
    'Test-MetraAutoprogramTransition'
    'Initialize-MetraAutoprogramLayout'
    'Get-MetraAutoprogramState'
    'Save-MetraAutoprogramState'
    'Get-MetraAutoprogramJournalPath'
    'Add-MetraAutoprogramJournalEntry'
    'Get-MetraAutoprogramJournalEntries'
    'Test-MetraAutoprogramItemId'
    'Resolve-MetraAutoprogramItemPath'
    'Get-MetraAutoprogramQueueItemPath'
    'Get-MetraAutoprogramQueueItems'
    'Get-MetraAutoprogramQueueItem'
    'Save-MetraAutoprogramQueueItem'
    'Test-MetraAutoprogramQueueItemSchema'
    'New-MetraAutoprogramQueueId'
    'New-MetraAutoprogramCandidateId'
    'Invoke-MetraAutoprogramStateChange'
    'Get-MetraAutoprogramPlanRoots'
    'Get-MetraAutoprogramFormalPlans'
    'Read-MetraAutoprogramPlanFile'
    'Resolve-MetraAutoprogramPlanProject'
    'Measure-MetraAutoprogramTriageScore'
    'Test-MetraAutoprogramEligibility'
    'Save-MetraAutoprogramCandidate'
    'Get-MetraAutoprogramCandidate'
    'Add-MetraAutoprogramQueueItem'
    'New-MetraAutoprogramQueueItemFromCandidate'
    'Invoke-MetraAutoprogramTriage'
    'Invoke-MetraAutoprogramEnqueueFromPlan'
    'Invoke-MetraAutoprogramDailyStub'
    'Invoke-MetraAutoprogramRun'
    'Get-AutoProgramActiveTransitionMap'
    'Write-AutoProgramAtomicUtf8Text'
    'Get-AutoProgramUtf8NoBomEncoding'
    'Test-AutoProgramPathWithinRoot'
)

Export-ModuleMember -Function $export -Alias Invoke-MetraAutoprogramCommand
