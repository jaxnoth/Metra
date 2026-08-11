# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Invoke-MetraSetup {
    <#
    .SYNOPSIS
        One-shot onboarding: ensure config, machine role, roots, workspace, routing, ctx.
    .DESCRIPTION
        Seeds metra.config.json from metra.config.example.json when neither metra.config.json nor
        legacy meta.config.json exists (never overwrites). Asks machine role early, then refreshes
        workspace/routing with short human summaries (not full registry dumps).
    #>
    [CmdletBinding()]
    param(
        [string]$Profile,
        [switch]$Force,
        [switch]$Preview,
        [int]$Months,
        [int]$ScanDepth,
        [ValidateSet('Hq', 'Satellite', 'Standalone')]
        [string]$Role,
        [switch]$Advanced,
        [switch]$Quiet
    )

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
    $roots = @()
    $routingRows = @()
    $deskBinding = $null
    $machineRoleSetup = $null
    $askAccept = $null
    $startMenu = $null

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
            Write-Host '  Would set machine role, regenerate workspace, write ctx'
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
        return [PSCustomObject]@{
            Preview         = $true
            WouldSeedConfig = $wouldSeedConfig
            SeededConfig    = $false
            Profile         = $Profile
            Import          = $importResult
            Roots           = $roots
            Routing         = $routingRows
            Workspace       = $null
            ContextPack     = $null
            MachineRole     = $(if ($Role) { ConvertTo-MetraMachineRole -Role $Role } else { $null })
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
            -Advanced:$Advanced `
            -Interactive:(-not $Quiet) `
            -Quiet:$Quiet
        if ($machineRoleSetup -and $machineRoleSetup.DeskBinding) {
            $deskBinding = $machineRoleSetup.DeskBinding
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
    if ($PSBoundParameters.ContainsKey('Months')) { $wsParams.Months = $Months }
    if ($PSBoundParameters.ContainsKey('ScanDepth')) { $wsParams.ScanDepth = $ScanDepth }
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
    if (-not $Quiet -and -not $isSatellite) {
        try {
            $rec = Get-MetraAskEngineRecommendation -MetraRoot $metraRoot
            Write-Host ''
            Write-Host 'Ask engine (local):' -ForegroundColor Cyan
            Write-Host ("  {0}" -f $rec.summary)
            Write-Host '  Accept installs Ollama when needed, pulls the model, and verifies Ask.'
            $answer = Read-Host '  Use recommended Ask settings now? [Y/n]'
            if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^(?i)y') {
                Write-Host '  Accepting recommended Ask settings (may take several minutes)...' -ForegroundColor DarkGray
                $askAccept = Invoke-MetraAskAcceptRecommended -MetraRoot $metraRoot
                if ($askAccept.ok) {
                    Write-Host '  Ask ready.' -ForegroundColor Green
                }
                else {
                    Write-Warning ("Ask accept incomplete: {0}" -f ($(if ($askAccept.capability) { $askAccept.capability.reason } else { 'see steps' })))
                    Write-Host '  Retry later: .\metra.ps1 ask accept'
                }
            }
            else {
                Write-Host '  Skipped. Later: .\metra.ps1 ask recommend  then  .\metra.ps1 ask accept'
            }
        }
        catch {
            Write-Warning "Ask recommend/accept skipped: $($_.Exception.Message)"
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
    }

    return [PSCustomObject]@{
        Preview         = $false
        WouldSeedConfig = $false
        SeededConfig    = $seededConfig
        Profile         = $Profile
        Import          = $importResult
        Roots           = $roots
        Routing         = $routingRows
        Workspace       = $workspaceResult
        ContextPack     = $ctxResult
        StartMenu       = $startMenu
        DeskBinding     = $deskBinding
        MachineRole     = $(if ($machineRoleSetup) { $machineRoleSetup.MachineRole } else { $null })
        AskAccept       = $askAccept
    }
}
