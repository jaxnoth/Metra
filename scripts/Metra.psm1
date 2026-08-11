# Metra.psm1 - module loader and explicit command boundary

Set-StrictMode -Version Latest

$script:MetraModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$privatePath = Join-Path $PSScriptRoot 'private'
$publicPath = Join-Path $PSScriptRoot 'public'

foreach ($file in @(Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File | Sort-Object Name)) {
    . $file.FullName
}
foreach ($file in @(Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File | Sort-Object Name)) {
    . $file.FullName
}

Register-MetraArgumentCompleters

$script:MetraPublicFunctions = @(
    'Initialize-Metra',
    'Get-MetraProject',
    'Get-MetraProjectRoot',
    'Get-MetraRouting',
    'Get-MetraProjectStatus',
    'Update-MetraProject',
    'Invoke-MetraProjectCommand',
    'Copy-MetraProjectFile',
    'New-MetraProject',
    'Update-MetraWorkspace',
    'Test-MetraProjectContext',
    'Export-MetraSnapshot',
    'Update-MetraSelfDocumentation',
    'Get-MetraChat',
    'Export-MetraContext',
    'Export-MetraProfile',
    'Import-MetraProfile',
    'Sync-MetraProfile',
    'Test-MetraInstallation'
)

# One-release compatibility functions. These remain callable but are not the
# documented API. New scripts should use the public functions above.
$script:MetraCompatibilityFunctions = @(
    'Get-MetraRoot',
    'Get-MetraConfig',
    'Get-MetraProp',
    'Get-MetraRoots',
    'Get-MetraSettingsPortfolio',
    'Save-MetraSettingsPortfolio',
    'Get-MetraProductUpdates',
    'Invoke-MetraProductUpdate',
    'Get-MetraProjects',
    'Get-MetraStatus',
    'Update-MetraProjects',
    'Get-RecentMetraProjects',
    'Get-MetraProjectRegistry',
    'Get-MetraRoutingTable',
    'Invoke-MetraProjectContextAudit',
    'Get-MetraProjectGitCounts',
    'Export-MetraCanvasSnapshot',
    'Test-MetraCanvasSnapshotStale',
    'Get-MetraQuickProjectHealthReports',
    'Invoke-MetraVerify',
    'Export-MetraContextPack',
    'Get-MetraProjectChats',
    'Get-MetraCursorTranscriptRoots',
    'Get-MetraProfileFileMap',
    'Get-MetraProfileStatus',
    'Initialize-MetraProfileSyncToken',
    'Test-MetraProfileSyncToken',
    'Invoke-MetraSetup',
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
    'Get-MetraDeskPlaceRecommendation',
    'Get-MetraDeskAskResult',
    'New-MetraAskEvidenceItem',
    'New-MetraAskEvidencePack',
    'Get-MetraAskEvidenceQuality',
    'Resolve-MetraAskAnswerSemantics',
    'Test-MetraDeskGreeting',
    'Test-MetraAskPersonalObservationIntent',
    'Test-MetraAskParkOrSaveIntent',
    'Repair-MetraAskWritePromise',
    'Get-MetraUtf8NoBomEncoding',
    'Test-MetraAskShowWhere',
    'Add-MetraPlaceMemoryItem',
    'Save-MetraPlaceUpload',
    'Get-MetraPlaceUploadMeta',
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
    'Get-MetraOrchestrationProject',
    'Get-MetraHomeDestinationName',
    'Get-MetraRoutingAmbiguity',
    'Clear-MetraRoutingCache',
    'Get-MetraDeskPreferences',
    'Set-MetraDeskPreferences',
    'Get-MetraOpsFallbackPort',
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
    'Resolve-MetraCaptureSuggestedTarget',
    'Propose-MetraCaptureSplit',
    'Add-MetraCaptureFromAskSplit',
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

# Silent one-release compatibility aliases for the former Meta naming.
$script:MetraCompatAliasMap = [ordered]@{
    'Get-MetaRoot'                       = 'Get-MetraRoot'
    'Get-MetaConfig'                     = 'Get-MetraConfig'
    'Get-MetaProp'                       = 'Get-MetraProp'
    'Get-MetaRoots'                      = 'Get-MetraRoots'
    'Get-MetaProjects'                   = 'Get-MetraProjects'
    'Get-MetaStatus'                     = 'Get-MetraStatus'
    'Update-MetaProjects'                = 'Update-MetraProjects'
    'New-MetaProject'                    = 'New-MetraProject'
    'Get-RecentMetaProjects'             = 'Get-RecentMetraProjects'
    'Update-MetaWorkspace'               = 'Update-MetraWorkspace'
    'Get-MetaProjectRegistry'            = 'Get-MetraProjectRegistry'
    'Get-MetaRoutingTable'               = 'Get-MetraRoutingTable'
    'Invoke-MetaProjectContextAudit'     = 'Invoke-MetraProjectContextAudit'
    'Get-MetaProjectGitCounts'           = 'Get-MetraProjectGitCounts'
    'Export-MetaCanvasSnapshot'          = 'Export-MetraCanvasSnapshot'
    'Test-MetaCanvasSnapshotStale'       = 'Test-MetraCanvasSnapshotStale'
    'Get-MetaQuickProjectHealthReports'  = 'Get-MetraQuickProjectHealthReports'
    'Invoke-MetaVerify'                  = 'Invoke-MetraVerify'
    'Export-MetaContextPack'             = 'Export-MetraContextPack'
    'Get-MetaProjectChats'               = 'Get-MetraProjectChats'
    'Get-MetaCursorTranscriptRoots'      = 'Get-MetraCursorTranscriptRoots'
    'Get-MetaProfileFileMap'             = 'Get-MetraProfileFileMap'
    'Export-MetaProfile'                 = 'Export-MetraProfile'
    'Import-MetaProfile'                 = 'Import-MetraProfile'
    'Invoke-MetaSetup'                   = 'Invoke-MetraSetup'
}
foreach ($pair in $script:MetraCompatAliasMap.GetEnumerator()) {
    Set-Alias -Name $pair.Key -Value $pair.Value -Scope Script -Force
}

Export-ModuleMember `
    -Function @($script:MetraPublicFunctions + $script:MetraCompatibilityFunctions) `
    -Alias @($script:MetraCompatAliasMap.Keys)
