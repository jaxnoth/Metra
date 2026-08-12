@{
    RootModule        = 'Metra.psm1'
    ModuleVersion     = '0.1.11'
    GUID              = 'afe44c63-0346-4acf-b723-164fb28c585d'
    Author            = 'Metra contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) Metra contributors. MIT License.'
    Description       = 'PowerShell commands for Metra multi-project portfolio operations.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Initialize-Metra'
        'Get-MetraProject'
        'Get-MetraProjectRoot'
        'Get-MetraRouting'
        'Get-MetraProjectStatus'
        'Update-MetraProject'
        'Invoke-MetraProjectCommand'
        'Copy-MetraProjectFile'
        'New-MetraProject'
        'Update-MetraWorkspace'
        'Test-MetraProjectContext'
        'Export-MetraSnapshot'
        'Update-MetraSelfDocumentation'
        'Get-MetraChat'
        'Export-MetraContext'
        'Export-MetraProfile'
        'Import-MetraProfile'
        'Sync-MetraProfile'
        'Get-MetraProfileSyncClientStatus'
        'Test-MetraInstallation'
        'Get-MetraRoot'
        'Get-MetraConfig'
        'Get-MetraProp'
        'Get-MetraRoots',
        'Get-MetraSettingsPortfolio',
        'Save-MetraSettingsPortfolio',
        'Get-MetraProductUpdates',
        'Invoke-MetraProductUpdate',
        'Start-MetraProductUpdateApplyJob',
        'Complete-MetraProductUpdateApplyJob',
        'Get-MetraOpsUpdatesApiPayload',
        'Get-MetraProjects',
        'Get-MetraOrchestrationProject',
        'Get-MetraHomeDestinationName',
        'Get-MetraRoutingAmbiguity',
        'Clear-MetraRoutingCache',
        'Get-MetraStatus',
        'Update-MetraProjects',
        'Get-RecentMetraProjects',
        'Get-MetraProjectRegistry',
        'Get-MetraRoutingTable',
        'Invoke-MetraProjectContextAudit',
        'Get-MetraProjectGitCounts',
        'Export-MetraCanvasSnapshot'
        'Test-MetraCanvasSnapshotStale'
        'Get-MetraQuickProjectHealthReports'
        'Invoke-MetraVerify'
        'Export-MetraContextPack'
        'Get-MetraProjectChats'
        'Get-MetraCursorTranscriptRoots'
        'Get-MetraProfileFileMap'
        'Get-MetraProfileStatus'
        'Initialize-MetraProfileSyncToken'
        'Test-MetraProfileSyncToken'
        'Invoke-MetraSetup'
        'Invoke-MetraOperatorContractCommand',
        'Invoke-MetraDecisionRegistryCommand',
        'Show-MetraRoutingCli',
        'Show-MetraKnowledgeCoverageCli',
        'Show-MetraInspectCli',
        'Show-MetraUnblockCli',
        'Start-MetraOpsServer',
        'Stop-MetraOpsServer',
        'Test-MetraOpsDeskResponding',
        'Start-MetraOpsHost',
        'Stop-MetraOpsHost',
        'Get-MetraOpsHostState',
        'Test-MetraOpsHostRunning',
        'Set-MetraOpsHostStartup',
        'Install-MetraOpsStartMenuShortcuts',
        'Start-MetraOpsDeskIfDown',
        'Test-MetraOpsDeskAlive',
        'Resolve-MetraOpsDeskBinding',
        'Initialize-MetraOpsDeskBinding',
        'Get-MetraOpsDeskUrl',
        'Test-MetraTcpPortFree',
        'Get-MetraDeskPayload',
        'Get-MetraDeskHandoff',
        'Get-MetraDeskPlaceRecommendation',
        'Get-MetraDeskAskResult',
        'Test-MetraDeskGreeting',
        'Test-MetraAskShowWhere',
        'Add-MetraPlaceMemoryItem',
        'Save-MetraPlaceUpload',
        'Get-MetraPlaceUploadMeta',
        'Remove-MetraPlaceExpiredUploads',
        'Enable-MetraOpsTailscaleServe',
        'Get-MetraOpsTailscaleServeStatus',
        'Get-MetraOpsTailscaleBinding',
        'Get-MetraAskCapability',
        'Get-MetraAskSettings',
        'Get-MetraAskEngineRecommendation',
        'Get-MetraAskEngineMenu',
        'Invoke-MetraAskAcceptRecommended',
        'Invoke-MetraAskEngineCommand',
        'Set-MetraAskEngine',
        'Set-MetraCursorApiKey',
        'Test-MetraCursorInstall',
        'Invoke-MetraAskEngine',
        'Start-MetraAskEngine',
        'Stop-MetraAskEngine',
        'Get-MetraDeskPreferences',
        'Set-MetraDeskPreferences',
        'Get-MetraOpsFallbackPort',
        'Get-MetraSetupLogPath',
        'Get-MetraInstallerLogPath',
        'Get-MetraInstallStatus',
        'Start-MetraSetupTranscript',
        'Stop-MetraSetupTranscript',
        'Copy-MetraInnoInstallerLog',
        'ConvertTo-MetraMachineRole',
        'Invoke-MetraMachineRoleSetup',
        'Set-MetraConfiguredOpsBaseUrl',
        'Invoke-MetraCaptureCommand',
        'Invoke-MetraAskLogCommand',
        'Invoke-MetraAskJournalRemote',
        'Get-MetraDeskMode',
        'Get-MetraProfileOpsBaseUrlOrNull',
        'Test-MetraOpsBaseUrlIsLocal',
        'Assert-MetraOpsMayStartLocally',
        'Get-MetraCaptureLedger',
        'Add-MetraCaptureFromAskTurn',
        'Invoke-MetraCapturePromote',
        'Get-MetraDeskAskLog',
        'Get-MetraDeskAskSessionSummaries',
        'Get-MetraDeskAskSessionTurns',
        'Search-MetraDeskAskJournal',
        'Get-MetraAskContinuityContext',
        'Add-MetraDeskAskEntry',
        'Invoke-MetraTicketWatchScan',
        'Invoke-MetraTicketWatchStoreRecommend',
        'New-MetraTicketWatchRecommendBody',
        'New-MetraTicketWatchRecommendBasis'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @(
        'Get-MetaRoot'
        'Get-MetaConfig'
        'Get-MetaProp'
        'Get-MetaRoots'
        'Get-MetaProjects'
        'Get-MetaStatus'
        'Update-MetaProjects'
        'New-MetaProject'
        'Get-RecentMetaProjects'
        'Update-MetaWorkspace'
        'Get-MetaProjectRegistry'
        'Get-MetaRoutingTable'
        'Invoke-MetaProjectContextAudit'
        'Get-MetaProjectGitCounts'
        'Export-MetaCanvasSnapshot'
        'Test-MetaCanvasSnapshotStale'
        'Get-MetaQuickProjectHealthReports'
        'Invoke-MetaVerify'
        'Export-MetaContextPack'
        'Get-MetaProjectChats'
        'Get-MetaCursorTranscriptRoots'
        'Get-MetaProfileFileMap'
        'Export-MetaProfile'
        'Import-MetaProfile'
        'Invoke-MetaSetup'
    )

    PrivateData = @{
        PSData = @{
            ProjectUri = 'https://github.com/jaxnoth/Metra'
            LicenseUri = 'https://github.com/jaxnoth/Metra/blob/main/LICENSE'
            Tags       = @('Metra', 'Portfolio', 'Projects', 'Workspace')
        }
    }
}
