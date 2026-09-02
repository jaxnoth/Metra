@{
    RootModule        = 'Yarn.psm1'
    ModuleVersion     = '0.2.1'
    GUID              = 'b9d1f3e5-8c02-4e4f-a017-3d2b6c9e5f81'
    Author            = 'Metra'
    CompanyName       = 'IWU'
    Copyright         = '(c) Metra'
    Description       = 'Yarn: L1.5 intake — ranked backlog, synthesize, pack freshness (A0-A2).'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
        'Get-MetraYarnPending'
        'Get-MetraYarnDaily'
        'Get-MetraYarnStatus'
        'Write-YarnAtomicUtf8Text'
        'Get-YarnUtf8NoBomEncoding'
        'Test-YarnLoomQueueWriteForbidden'
        'Read-YarnFutureDevIdeas'
    )
    AliasesToExport   = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('Metra', 'Yarn', 'intake')
        }
    }
}
