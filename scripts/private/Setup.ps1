# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Invoke-MetraSetup {
    <#
    .SYNOPSIS
        One-shot onboarding: ensure config, optional profile import, roots, workspace, routing, ctx.
    .DESCRIPTION
        Seeds metra.config.json from metra.config.example.json when neither metra.config.json nor
        legacy meta.config.json exists (never overwrites). Regenerates Metra.code-workspace from
        roots. Prints short glosses for roots / routing / ctx.
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
            Write-Host '  Would regenerate Metra.code-workspace, print routing, write ctx'
            try {
                $null = Initialize-MetraOpsDeskBinding -MetraRoot $metraRoot -Preview -Quiet:$Quiet
            }
            catch { }
            if ($Role -or $Advanced) {
                Write-Host ("  Would apply machine role setup Role={0} Advanced={1}" -f $(if ($Role) { $Role } else { '(prompt)' }), [bool]$Advanced)
            }
        }
        if ($configPresent) {
            try {
                $roots = @(Get-MetraRoots -IncludeMissing)
                $routingRows = @(Get-MetraRoutingTable)
                if (-not $Quiet) {
                    Write-Host ''
                    Write-Host 'Roots (would scan; not Cursor folders until workspace runs):' -ForegroundColor Cyan
                    $roots |
                        Select-Object Name, Primary, Exists, Optional, Path |
                        Format-Table -AutoSize | Out-Host
                    Write-Host ("Routing: {0} entr(ies); {1} present (full table on real setup)" -f `
                        $routingRows.Count, @($routingRows | Where-Object Present).Count)
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
            Write-Host ("Seeded metra.config.json from metra.config.example.json") -ForegroundColor Cyan
            Write-Host '  Edit roots / workspace.alwaysInclude for this machine, then re-run .\metra.ps1 setup' -ForegroundColor Yellow
        }
    }

    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Roots (paths Metra scans for projects - not Cursor folders until workspace runs):' -ForegroundColor Cyan
    }
    $roots = @(Get-MetraRoots -IncludeMissing)
    if (-not $Quiet) {
        $roots |
            Select-Object Name, Primary, Exists, Optional, Audit, Path |
            Format-Table -AutoSize | Out-Host
        $missing = @($roots | Where-Object { -not $_.Exists })
        if ($missing.Count -gt 0) {
            Write-Host ("Not present on this machine: {0}" -f (($missing.Name) -join ', ')) -ForegroundColor Yellow
        }
        $primaryMissing = @($roots | Where-Object { $_.Primary -and -not $_.Exists })
        if ($primaryMissing.Count -gt 0) {
            throw ("Primary root(s) missing: {0}. Fix metra.config.json roots.path and re-run setup." -f (($primaryMissing.Name) -join ', '))
        }
    }
    else {
        $primaryMissing = @($roots | Where-Object { $_.Primary -and -not $_.Exists })
        if ($primaryMissing.Count -gt 0) {
            throw ("Primary root(s) missing: {0}. Fix metra.config.json roots.path and re-run setup." -f (($primaryMissing.Name) -join ', '))
        }
    }

    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Workspace (rebuild Cursor/VS Code folder list from roots + recent activity):' -ForegroundColor Cyan
    }
    $wsParams = @{}
    if ($PSBoundParameters.ContainsKey('Months')) { $wsParams.Months = $Months }
    if ($PSBoundParameters.ContainsKey('ScanDepth')) { $wsParams.ScanDepth = $ScanDepth }
    $workspaceResult = Update-MetraWorkspace @wsParams
    if (-not $Quiet -and $workspaceResult) {
        $workspaceResult | Format-List | Out-Host
    }

    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Routing (registry names + triggers vs Present on disk):' -ForegroundColor Cyan
    }
    $routingRows = @(Get-MetraRoutingTable)
    if (-not $Quiet) {
        if ($routingRows.Count -eq 0) {
            Write-Host 'No registry entries matched.' -ForegroundColor Yellow
        }
        else {
            $routingRows |
                Select-Object Name, Source, Root, Present, Optional,
                    @{ n = 'Triggers'; e = { ($_.Triggers -join ', ') } } |
                Format-Table -AutoSize | Out-Host
            foreach ($row in @($routingRows | Where-Object { -not $_.Present })) {
                Write-Host ("{0}: {1}" -f $row.Name, $row.Advice) -ForegroundColor Yellow
            }
            Write-Host ("{0} entr(ies); {1} present" -f $routingRows.Count, @($routingRows | Where-Object Present).Count)
        }
    }

    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Context pack (hand docs/context-pack.md to any agent):' -ForegroundColor Cyan
    }
    $ctxResult = Export-MetraContextPack -Quiet:$Quiet

    $startMenu = $null
    try {
        $startMenu = Install-MetraOpsStartMenuShortcuts -MetraRoot $metraRoot
        if (-not $Quiet) {
            Write-Host ''
            Write-Host 'Start Menu: Metra Ops shortcut refreshed (brand icon).' -ForegroundColor Cyan
        }
    }
    catch {
        if (-not $Quiet) {
            Write-Warning "Start Menu shortcut skipped: $($_.Exception.Message)"
        }
    }

    $deskBinding = $null
    $machineRoleSetup = $null
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
            Write-Warning "Machine role / Ops desk URL setup skipped: $($_.Exception.Message)"
        }
    }

    $askAccept = $null
    if (-not $Quiet -and -not $Preview) {
        try {
            $rec = Get-MetraAskEngineRecommendation -MetraRoot $metraRoot
            Write-Host ''
            Write-Host 'Ask engine (recommended for this PC):' -ForegroundColor Cyan
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

    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Next:' -ForegroundColor Yellow
        Write-Host '  - Open or reload Metra.code-workspace (siblings appear after workspace regenerate)'
        Write-Host '  - Edit metra.config.json roots / alwaysInclude if paths differ, then: .\metra.ps1 setup'
        Write-Host '  - Optional personal/cloud root snippets: docs/Customizing-Metra.md'
        Write-Host '  - If using Cursor: set operator display name in .cursor/rules/metra-persona.local.mdc'
        Write-Host '  - Ask: .\metra.ps1 ask accept   (Ollama recommended) or Advanced Cursor via ask engine set cursor'
        Write-Host '  - Front door: Start Menu Metra Ops (or .\metra.ps1 host)'
        if ($machineRoleSetup -and $machineRoleSetup.MachineRole) {
            Write-Host ("  - Machine role: {0}" -f $machineRoleSetup.MachineRole)
        }
        if ($machineRoleSetup -and $machineRoleSetup.MachineRole -eq 'Satellite') {
            Write-Host '  - Satellite: do not start local Ops as HQ; use profile sync / ask against OpsBaseUrl'
            if ($machineRoleSetup.OpsBaseUrl) {
                Write-Host ("  - OpsBaseUrl: {0}" -f $machineRoleSetup.OpsBaseUrl)
            }
        }
        if ($deskBinding -and $deskBinding.Binding) {
            Write-Host ("  - Ops desk URL: {0}" -f $deskBinding.Binding.BrowserUrl)
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

