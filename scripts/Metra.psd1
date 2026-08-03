@{
    RootModule        = 'Metra.psm1'
    ModuleVersion     = '0.1.0'
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
        'Get-MetraChat'
        'Export-MetraContext'
        'Export-MetraProfile'
        'Import-MetraProfile'
        'Test-MetraInstallation'
        'Get-MetraRoot'
        'Get-MetraConfig'
        'Get-MetraProp'
        'Get-MetraRoots'
        'Get-MetraProjects'
        'Get-MetraOrchestrationProject'
        'Get-MetraHomeDestinationName'
        'Get-MetraRoutingAmbiguity'
        'Get-MetraStatus'
        'Update-MetraProjects'
        'Get-RecentMetraProjects'
        'Get-MetraProjectRegistry'
        'Get-MetraRoutingTable'
        'Invoke-MetraProjectContextAudit'
        'Get-MetraProjectGitCounts'
        'Export-MetraCanvasSnapshot'
        'Test-MetraCanvasSnapshotStale'
        'Get-MetraQuickProjectHealthReports'
        'Invoke-MetraVerify'
        'Export-MetraContextPack'
        'Get-MetraProjectChats'
        'Get-MetraCursorTranscriptRoots'
        'Get-MetraProfileFileMap'
        'Invoke-MetraSetup'
        'Invoke-MetraOperatorContractCommand',
        'Invoke-MetraDecisionRegistryCommand',
        'Show-MetraRoutingCli',
        'Show-MetraKnowledgeCoverageCli',
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
        'Get-MetraDeskAskResult',
        'Test-MetraDeskGreeting',
        'Get-MetraAskCapability',
        'Get-MetraAskSettings',
        'Invoke-MetraAskEngine',
        'Start-MetraAskEngine',
        'Stop-MetraAskEngine',
        'Get-MetraDeskPreferences',
        'Set-MetraDeskPreferences'
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
