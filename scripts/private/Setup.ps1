# Setup.ps1 - one-shot onboarding orchestrator (task inventory + known-good checkout)

function Get-MetraSetupTasks {
    <#
    .SYNOPSIS
        Declares the setup task inventory so Invoke-MetraSetup stays an orchestrator.
    .DESCRIPTION
        New capabilities that need a known-good checkout should add a row here and a step
        in Invoke-MetraSetup (or a Verify mode later). Do not grow setup as an ad-hoc dump.
    #>
    [CmdletBinding()]
    param()

    return @(
        [PSCustomObject]@{ Name = 'Config'; Kind = 'ensure'; Summary = 'Seed metra.config.json when missing' }
        [PSCustomObject]@{ Name = 'ProfileImport'; Kind = 'optional'; Summary = 'Import operator profile when -Profile is set' }
        [PSCustomObject]@{ Name = 'MachineRole'; Kind = 'write'; Summary = 'HQ / Satellite / Standalone role' }
        [PSCustomObject]@{ Name = 'ProfileSync'; Kind = 'satellite'; Summary = 'Pull overlays from HQ on Satellite' }
        [PSCustomObject]@{ Name = 'Workspace'; Kind = 'write'; Summary = 'Regenerate Metra.code-workspace' }
        [PSCustomObject]@{ Name = 'Routing'; Kind = 'read'; Summary = 'Resolve present/missing routing table' }
        [PSCustomObject]@{ Name = 'ContextPack'; Kind = 'write'; Summary = 'Export docs/context-pack.md' }
        [PSCustomObject]@{ Name = 'SelfDocumentation'; Kind = 'write'; Summary = 'Refresh Overview / canvas / selfdoc JSON from live routing' }
        [PSCustomObject]@{ Name = 'ProposalStore'; Kind = 'ensure'; Summary = 'Ensure local proposal store root exists' }
        [PSCustomObject]@{ Name = 'StartMenu'; Kind = 'write'; Summary = 'Install Metra Ops Start Menu shortcut' }
        [PSCustomObject]@{ Name = 'Ask'; Kind = 'optional'; Summary = 'Accept recommended Ask engine (HQ/Standalone)' }
    )
}

function Test-MetraProposalSetupReady {
    <#
    .SYNOPSIS
        Ensures the proposal store root exists (lightweight readiness for setup).
    #>
    [CmdletBinding()]
    param()

    try {
        $root = Get-MetraProposalStoreRoot
        $ready = Test-Path -LiteralPath $root
        return [PSCustomObject]@{
            Ready     = [bool]$ready
            StoreRoot = $root
            Detail    = $(if ($ready) { 'Proposal store ready' } else { 'Proposal store missing after create' })
        }
    }
    catch {
        return [PSCustomObject]@{
            Ready     = $false
            StoreRoot = $null
            Detail    = [string]$_.Exception.Message
        }
    }
}

function Invoke-MetraSetup {
    <#
    .SYNOPSIS
        One-shot onboarding: ensure config, machine role, roots, workspace, routing, ctx, selfdoc.
    .DESCRIPTION
        Seeds metra.config.json from metra.config.example.json when neither metra.config.json nor
        legacy meta.config.json exists (never overwrites). Asks machine role early, then refreshes
        workspace/routing with short human summaries (not full registry dumps). Context pack and
        self-documentation regenerate as a pair. Task inventory: Get-MetraSetupTasks.
        -Quiet changes host output and prompting only. Public Initialize-Metra owns -WhatIf / -Confirm
        (maps WhatIf to -Preview); this helper keeps defensive argument validation.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Profile,
        [switch]$Force,
        [switch]$Preview,
        [ValidateRange(1, 120)]
        [Nullable[int]]$Months,
        [ValidateRange(1, 100)]
        [Nullable[int]]$ScanDepth,
        [ValidateSet('Hq', 'Satellite', 'Standalone')]
        [string]$Role,
        [string]$OpsBaseUrl,
        [string]$SyncToken,
        [switch]$Advanced,
        [switch]$PreferFriendly,
        [switch]$NoPreferFriendly,
        [switch]$BindTailscale,
        [switch]$AcceptAsk,
        [switch]$Quiet
    )

    if ($PreferFriendly -and $NoPreferFriendly) {
        throw '-PreferFriendly and -NoPreferFriendly cannot both be specified.'
    }
    if ($Role -eq 'Satellite' -and $AcceptAsk) {
        throw '-AcceptAsk is supported only with Hq or Standalone.'
    }
    if ($BindTailscale -and $Role -and $Role -ne 'Hq') {
        throw '-BindTailscale applies only to Hq.'
    }
    if ($Role -eq 'Satellite' -and ($PreferFriendly -or $NoPreferFriendly)) {
        throw '-PreferFriendly / -NoPreferFriendly apply only to Hq or Standalone.'
    }
    if ($Role -eq 'Satellite' -and $Advanced) {
        throw '-Advanced applies only to Hq or Standalone.'
    }
    if (-not [string]::IsNullOrWhiteSpace($OpsBaseUrl) -and $OpsBaseUrl -notmatch '^https?://') {
        throw 'OpsBaseUrl must start with http:// or https://.'
    }

    $metraRoot = Get-MetraRoot
    $preferredConfig = Join-Path $metraRoot 'metra.config.json'
    $legacyConfig = Join-Path $metraRoot 'meta.config.json'
    $exampleConfig = Join-Path $metraRoot 'metra.config.example.json'
    $configPresent = (Test-Path -LiteralPath $preferredConfig) -or (Test-Path -LiteralPath $legacyConfig)
    $wouldSeedConfig = -not $configPresent
    $seededConfig = $false
    $importResult = $null
    $workspaceResult = $null
    $ctxResult = $null
    $selfDocResult = $null
    $proposalReady = $null
    $roots = @()
    $routingRows = @()
    $deskBinding = $null
    $machineRoleSetup = $null
    $askAccept = $null
    $startMenu = $null
    $logSession = $null
    $setupTasks = @(Get-MetraSetupTasks)
    if (-not $Preview) {
        $logSession = Start-MetraSetupTranscript -MetraRoot $metraRoot -Source 'setup'
        if (-not $Quiet) {
            Write-Host ("Setup log: {0}" -f (Get-MetraSetupLogPath -MetraRoot $metraRoot)) -ForegroundColor DarkGray
        }
    }

    try {
    if (-not $Quiet) {
        $blockedScripts = @(
            Get-MetraCheckoutScriptFiles -Path $metraRoot |
                Where-Object { Test-MetraBlockedFile -Path $_.FullName }
        )
        if ($blockedScripts.Count -gt 0) {
            Write-Host ''
            Write-Host ("Mark-of-the-web: {0} script file(s) still blocked (ZIP / download)." -f $blockedScripts.Count) -ForegroundColor Yellow
            Write-Host '  Hint: .\metra.ps1 unblock   (or double-click Metra-Setup.cmd on a fresh ZIP extract)' -ForegroundColor Yellow
        }
    }

    if ($Profile) {
        if (-not $Quiet) {
            Write-Host ''
            Write-Host 'Profile:' -ForegroundColor Cyan
        }
        $importResult = Import-MetraProfile -Path $Profile -Preview:$Preview -Force:$Force -Quiet:$Quiet
        if (-not $Preview) {
            $configPresent = (Test-Path -LiteralPath $preferredConfig) -or (Test-Path -LiteralPath $legacyConfig)
            $wouldSeedConfig = -not $configPresent
        }
    }

    if ($Preview) {
        if (-not $Quiet) {
            Write-Host ''
            Write-Host 'Setup preview (no writes):' -ForegroundColor Cyan
            if ($wouldSeedConfig) {
                Write-Host '  Would seed metra.config.json from metra.config.example.json'
            }
            else {
                Write-Host '  Config already present (will not overwrite with example)'
            }
            if ($Profile) {
                Write-Host '  Profile import previewed above (no files written)'
            }
            Write-Host '  Would set machine role, regenerate workspace, write ctx + selfdoc'
            Write-Host '  Would ensure proposal store root'
            if ($Role -or $Advanced) {
                Write-Host ("  Would apply machine role setup Role={0} Advanced={1}" -f $(if ($Role) { $Role } else { '(prompt)' }), [bool]$Advanced)
            }
        }
        if ($configPresent) {
            try {
                $roots = @(Get-MetraRoots -IncludeMissing)
                $routingRows = @(Get-MetraRoutingTable)
                if (-not $Quiet) {
                    $present = @($routingRows | Where-Object Present).Count
                    Write-Host ("  Roots OK; routing would show {0} present of {1}." -f $present, $routingRows.Count)
                }
            }
            catch {
                if (-not $Quiet) {
                    Write-Host ("  Could not read roots/routing yet: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
                }
            }
        }
        $previewRole = $(if ($Role) { ConvertTo-MetraMachineRole -Role $Role } else { $null })
        return [PSCustomObject]@{
            Success            = $true
            Preview            = $true
            WouldSeedConfig    = $wouldSeedConfig
            SeededConfig       = $false
            ConfigCreated      = $false
            Profile            = $Profile
            ProfileImported    = ($null -ne $importResult)
            Import             = $importResult
            Roots              = $roots
            Routing            = $routingRows
            RoutingUpdated     = $false
            Workspace          = $null
            WorkspaceUpdated   = $false
            ContextPack        = $null
            ContextExported    = $false
            SelfDocumentation  = $null
            Proposal           = $null
            Tasks              = $setupTasks
            MachineRole        = $previewRole
            Role               = $previewRole
            OpsBaseUrl         = $(if ($OpsBaseUrl) { $OpsBaseUrl.TrimEnd('/') } else { $null })
        }
    }

    # Ensure config (never overwrite existing)
    if (-not $configPresent) {
        if (-not (Test-Path -LiteralPath $exampleConfig)) {
            throw "Missing $exampleConfig - cannot seed metra.config.json."
        }
        Copy-Item -LiteralPath $exampleConfig -Destination $preferredConfig -Force
        $seededConfig = $true
        $configPresent = $true
        if (-not $Quiet) {
            Write-Host ''
            Write-Host 'Created metra.config.json from the example.' -ForegroundColor Cyan
        }
    }

    # Machine role first - before noisy portfolio refresh.
    try {
        $machineRoleSetup = Invoke-MetraMachineRoleSetup -MetraRoot $metraRoot `
            -Role $Role `
            -OpsBaseUrl $OpsBaseUrl `
            -SyncToken $SyncToken `
            -Advanced:$Advanced `
            -PreferFriendly:$PreferFriendly `
            -NoPreferFriendly:$NoPreferFriendly `
            -BindTailscale:$BindTailscale `
            -Interactive:(-not $Quiet) `
            -Quiet:$Quiet
        if ($machineRoleSetup -and $machineRoleSetup.DeskBinding) {
            $deskBinding = $machineRoleSetup.DeskBinding
        }
        if ($machineRoleSetup -and -not $Preview) {
            $roleName = [string](Get-MetraProp -Object $machineRoleSetup -Name 'MachineRole' -Default '')
            if ($roleName -eq 'Satellite') {
                $tokenOnDisk = Resolve-MetraProfileSyncToken -MetraRoot $metraRoot
                $freshToken = -not [string]::IsNullOrWhiteSpace($SyncToken)
                if ($freshToken -or -not [string]::IsNullOrWhiteSpace($tokenOnDisk)) {
                    try {
                        $syncParams = @{ Quiet = [bool]$Quiet }
                        if (-not [string]::IsNullOrWhiteSpace($OpsBaseUrl)) {
                            $syncParams.OpsBaseUrl = $OpsBaseUrl
                        }
                        if ($freshToken) {
                            $syncParams.SyncToken = $SyncToken
                            $syncParams.Force = $true
                        }
                        $null = Sync-MetraProfile @syncParams
                        if (-not $Quiet) {
                            Write-Host 'Profile sync: pulled from main Metra machine.' -ForegroundColor Cyan
                        }
                    }
                    catch {
                        if (-not $Quiet) {
                            Write-Warning ("Profile sync deferred: {0}. Retry: .\metra.ps1 profile sync" -f $_.Exception.Message)
                        }
                    }
                }
            }
        }
    }
    catch {
        if (-not $Quiet) {
            Write-Warning "Machine role setup skipped: $($_.Exception.Message)"
        }
    }

    $roots = @(Get-MetraRoots -IncludeMissing)
    $primaryMissing = @($roots | Where-Object { $_.Primary -and -not $_.Exists })
    if ($primaryMissing.Count -gt 0) {
        throw ("Primary root(s) missing: {0}. Fix metra.config.json roots.path and re-run setup." -f (($primaryMissing.Name) -join ', '))
    }
    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Portfolio folders:' -ForegroundColor Cyan
        foreach ($r in $roots) {
            $mark = if ($r.Exists) { 'ok' } else { 'missing' }
            $prim = if ($r.Primary) { 'primary' } else { 'optional' }
            Write-Host ("  {0,-10} {1,-8} {2}  {3}" -f $r.Name, $prim, $mark, $r.Path)
        }
    }

    $wsParams = @{ Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Months') -and $null -ne $Months) { $wsParams.Months = [int]$Months }
    if ($PSBoundParameters.ContainsKey('ScanDepth') -and $null -ne $ScanDepth) { $wsParams.ScanDepth = [int]$ScanDepth }
    $workspaceResult = Update-MetraWorkspace @wsParams
    if (-not $Quiet -and $workspaceResult) {
        $wsFile = @($workspaceResult.Files) | Select-Object -First 1
        Write-Host ''
        Write-Host ("Workspace: {0} project(s) -> {1}" -f $workspaceResult.ProjectCount, $(if ($wsFile) { $wsFile } else { '(see Files)' })) -ForegroundColor Cyan
    }

    $routingRows = @(Get-MetraRoutingTable)
    if (-not $Quiet) {
        $presentRows = @($routingRows | Where-Object Present)
        $missingCount = $routingRows.Count - $presentRows.Count
        Write-Host ("Routing: {0} on disk, {1} registered elsewhere (details: .\metra.ps1 routing)." -f $presentRows.Count, $missingCount) -ForegroundColor Cyan
    }

    $ctxResult = Export-MetraContextPack -Quiet
    if (-not $Quiet -and $ctxResult) {
        $ctxPath = Get-MetraProp -Object $ctxResult -Name 'Path' -Default ''
        if (-not $ctxPath) { $ctxPath = Get-MetraProp -Object $ctxResult -Name 'OutPath' -Default 'docs/context-pack.md' }
        Write-Host ("Context pack: {0}" -f $ctxPath) -ForegroundColor Cyan
    }

    # Pair with context pack: both are derived explain artifacts.
    try {
        $selfDocResult = Update-MetraSelfDocumentation
        if (-not $Quiet -and $selfDocResult) {
            Write-Host ("Self-doc: {0} route(s); behavior failCount={1}" -f $selfDocResult.RouteCount, $selfDocResult.BehaviorFailCount) -ForegroundColor Cyan
        }
    }
    catch {
        if (-not $Quiet) {
            Write-Warning ("Self-documentation skipped: {0}. Retry: .\metra.ps1 selfdoc" -f $_.Exception.Message)
        }
    }

    $proposalReady = Test-MetraProposalSetupReady
    if (-not $Quiet) {
        if ($proposalReady.Ready) {
            Write-Host ("Proposal store: ready ({0})" -f $proposalReady.StoreRoot) -ForegroundColor Cyan
        }
        else {
            Write-Warning ("Proposal store: {0}" -f $proposalReady.Detail)
        }
    }

    try {
        $startMenu = Install-MetraOpsStartMenuShortcuts -MetraRoot $metraRoot
        if (-not $Quiet) {
            Write-Host 'Start Menu: Metra Ops shortcut ready.' -ForegroundColor Cyan
        }
    }
    catch {
        if (-not $Quiet) {
            Write-Warning "Start Menu shortcut skipped: $($_.Exception.Message)"
        }
    }

    $roleName = $(if ($machineRoleSetup) { [string]$machineRoleSetup.MachineRole } else { '' })
    $isSatellite = ($roleName -eq 'Satellite')

    # Local Ask engine install is for HQ / Standalone hosts - satellites use HQ Ask.
    # -AcceptAsk (installer) runs without prompts; interactive setup still asks unless Quiet.
    if (-not $isSatellite -and ($AcceptAsk -or (-not $Quiet))) {
        $shouldAcceptAsk = [bool]$AcceptAsk
        if (-not $Quiet -and -not $AcceptAsk) {
            try {
                $rec = Get-MetraAskEngineRecommendation -MetraRoot $metraRoot
                Write-Host ''
                Write-Host 'Ask engine (local):' -ForegroundColor Cyan
                Write-Host ("  {0}" -f $rec.summary)
                Write-Host '  Accept installs Ollama when needed, pulls the model, and verifies Ask.'
                $answer = Read-Host '  Use recommended Ask settings now? [Y/n]'
                $shouldAcceptAsk = [string]::IsNullOrWhiteSpace($answer) -or ($answer -match '^(?i)y')
                if (-not $shouldAcceptAsk) {
                    Write-Host '  Skipped. Later: .\metra.ps1 ask recommend  then  .\metra.ps1 ask accept'
                }
            }
            catch {
                Write-Warning "Ask recommend/accept skipped: $($_.Exception.Message)"
                $shouldAcceptAsk = $false
            }
        }
        if ($shouldAcceptAsk) {
            try {
                if (-not $Quiet) {
                    Write-Host '  Accepting recommended Ask settings (may take several minutes)...' -ForegroundColor DarkGray
                }
                else {
                    Write-Host 'Ask accept: installing recommended engine (may take several minutes)...' -ForegroundColor Cyan
                }
                $askAccept = Invoke-MetraAskAcceptRecommended -MetraRoot $metraRoot
                if ($askAccept.ok) {
                    if (-not $Quiet) { Write-Host '  Ask ready.' -ForegroundColor Green }
                    else { Write-Host 'Ask accept: ready.' -ForegroundColor Green }
                }
                else {
                    $reason = $(if ($askAccept.capability) { $askAccept.capability.reason } else { 'see steps' })
                    Write-Warning ("Ask accept incomplete: {0}" -f $reason)
                    Write-Host '  Retry later: .\metra.ps1 ask accept'
                }
            }
            catch {
                Write-Warning "Ask accept failed: $($_.Exception.Message)"
            }
        }
    }
    elseif (-not $Quiet -and $isSatellite) {
        Write-Host ''
        Write-Host 'Ask: use HQ (no local Ollama install on Satellite).' -ForegroundColor Cyan
        Write-Host '  After OpsBaseUrl is set: .\metra.ps1 profile sync   then   .\metra.ps1 ask sessions'
    }

    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Next:' -ForegroundColor Yellow
        Write-Host '  - Open Metra.code-workspace in Cursor'
        if ($isSatellite) {
            Write-Host '  - Do not run .\metra.ps1 ops / host on this PC (use HQ)'
            if ($machineRoleSetup -and $machineRoleSetup.OpsBaseUrl) {
                Write-Host ("  - OpsBaseUrl: {0}" -f $machineRoleSetup.OpsBaseUrl)
            }
            Write-Host '  - Pull overlays: .\metra.ps1 profile sync'
        }
        else {
            Write-Host '  - Front door: Start Menu Metra Ops (or .\metra.ps1 host)'
            if ($roleName -eq 'Hq') {
                Write-Host '  - Share Ops URL with satellites (Tailscale Serve / MagicDNS)'
            }
            Write-Host '  - Optional Ask later: .\metra.ps1 ask accept'
        }
        if ($roleName) {
            Write-Host ("  - Machine role: {0}" -f $roleName)
        }
        Write-Host ("  - Setup log: {0}" -f (Get-MetraSetupLogPath -MetraRoot $metraRoot))
    }

    $resolvedRole = $(if ($machineRoleSetup) { $machineRoleSetup.MachineRole } else { $null })
    $resolvedOpsUrl = $null
    if ($machineRoleSetup) {
        $resolvedOpsUrl = Get-MetraProp -Object $machineRoleSetup -Name 'OpsBaseUrl' -Default $null
    }
    if (-not $resolvedOpsUrl -and $OpsBaseUrl) {
        $resolvedOpsUrl = $OpsBaseUrl.TrimEnd('/')
    }

    return [PSCustomObject]@{
        Success            = $true
        Preview            = $false
        WouldSeedConfig    = $false
        SeededConfig       = $seededConfig
        ConfigCreated      = $seededConfig
        Profile            = $Profile
        ProfileImported    = ($null -ne $importResult)
        Import             = $importResult
        Roots              = $roots
        Routing            = $routingRows
        RoutingUpdated     = ($routingRows.Count -gt 0)
        Workspace          = $workspaceResult
        WorkspaceUpdated   = ($null -ne $workspaceResult)
        ContextPack        = $ctxResult
        ContextExported    = ($null -ne $ctxResult)
        SelfDocumentation  = $selfDocResult
        Proposal           = $proposalReady
        Tasks              = $setupTasks
        StartMenu          = $startMenu
        DeskBinding        = $deskBinding
        MachineRole        = $resolvedRole
        Role               = $resolvedRole
        OpsBaseUrl         = $resolvedOpsUrl
        AskAccept          = $askAccept
        SetupLogPath       = (Get-MetraSetupLogPath -MetraRoot $metraRoot)
    }
    }
    finally {
        if ($null -ne $logSession) {
            Stop-MetraSetupTranscript -Session $logSession -MetraRoot $metraRoot
        }
    }
}
