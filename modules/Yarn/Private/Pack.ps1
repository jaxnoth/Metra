# Pack adapter + reconcile (A2/A3). Approval + handoff retry in Approve.ps1 / reconcile.

function Get-YarnInspectPackDir {
    param(
        # Canonical registry projectKey (not display name).
        [Parameter(Mandatory)][string]$ProjectKey
    )
    $safeName = ($ProjectKey -replace '[\\/:*?"<>|]', '_')
    if ($safeName -match '\.\.' -or [string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'Metra' }
    return Join-Path $env:LOCALAPPDATA "Metra\inspect\$safeName"
}

function Write-YarnOwnedPackPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$ProjectKey,
        [string]$Note = 'yarn-owned pack writer'
    )
    $packDir = Get-YarnInspectPackDir -ProjectKey $ProjectKey
    [void][System.IO.Directory]::CreateDirectory($packDir)
    $packPath = Join-Path $packDir 'pack-plan.md'
    $planText = [System.IO.File]::ReadAllText($PlanPath, (Get-YarnUtf8NoBomEncoding))
    $body = @"
# Yarn pack-plan

- projectKey: $ProjectKey
- planPath: $PlanPath
- generatedAt: $((Get-Date).ToUniversalTime().ToString('o'))
- note: $Note
- packContractVersion: $(Get-YarnPackContractVersion)

---

$planText
"@
    Write-YarnAtomicUtf8Text -Path $packPath -Text $body
    return [PSCustomObject]@{
        ok        = $true
        packPath  = $packPath
        stub      = $false
        yarnOwned = $true
    }
}

function Invoke-YarnInspectPackOnlyPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$ProjectKey,
        [string]$MetraRoot = (Get-YarnHostRoot)
    )

    if ($script:YarnPackOverride) {
        return & $script:YarnPackOverride @{
            PlanPath    = $PlanPath
            ProjectName = $ProjectKey
            ProjectKey  = $ProjectKey
            MetraRoot   = $MetraRoot
        }
    }

    $cmd = Get-Command Invoke-MetraInspectPackOnly -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return Write-YarnOwnedPackPlan -PlanPath $PlanPath -ProjectKey $ProjectKey -Note 'inspect-unavailable stub'
    }

    try {
        $packResult = & $cmd -Mode plan -Name $ProjectKey -Path $PlanPath
        $packPath = [string](Get-YarnProp -Object $packResult -Name 'Path' -Default '')
        if ([string]::IsNullOrWhiteSpace($packPath)) {
            $packPath = [string](Get-YarnProp -Object $packResult -Name 'packPath' -Default '')
        }
        if (-not [string]::IsNullOrWhiteSpace($packPath) -and (Test-Path -LiteralPath $packPath)) {
            return [PSCustomObject]@{
                ok        = $true
                packPath  = $packPath
                stub      = $false
                yarnOwned = $false
            }
        }
        return Write-YarnOwnedPackPlan -PlanPath $PlanPath -ProjectKey $ProjectKey -Note 'inspect returned no pack Path'
    }
    catch {
        return Write-YarnOwnedPackPlan -PlanPath $PlanPath -ProjectKey $ProjectKey -Note ("inspect pack failed: $($_.Exception.Message)")
    }
}

function Invoke-MetraYarnPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [string]$BacklogId,
        [string]$Path,
        [switch]$DryRun
    )

    $item = $null
    $planPath = $Path
    if ($BacklogId) {
        $item = @(Get-MetraYarnBacklog -Root $Root) | Where-Object { [string]$_.id -eq $BacklogId } | Select-Object -First 1
        if (-not $item) { throw "Backlog id not found: $BacklogId" }
        $planPath = [string](Get-YarnProp -Object $item -Name 'formalPlanPath' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($planPath) -or -not (Test-Path -LiteralPath $planPath)) {
        throw "Plan path missing for pack: $planPath"
    }
    $planText = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
    $planHash = Get-YarnPlanContentHash -PlanText $planText
    $packHash = Get-YarnPackInputHash -PlanText $planText
    $projectKey = if ($item) { [string]$item.projectKey } else { 'Metra' }
    if ([string]::IsNullOrWhiteSpace($projectKey)) { $projectKey = 'Metra' }

    if ($DryRun) {
        return [PSCustomObject]@{
            outcome         = 'dry-run'
            planPath        = $planPath
            planContentHash = $planHash
            packInputHash   = $packHash
        }
    }

    $pack = Invoke-YarnInspectPackOnlyPlan -PlanPath $planPath -ProjectKey $projectKey -MetraRoot $MetraRoot
    $ok = [bool]$pack.ok
    $packPath = [string]$pack.packPath

    if ($item) {
        $map = @{}
        foreach ($p in $item.PSObject.Properties) { $map[$p.Name] = $p.Value }
        if ($ok) {
            $map['status'] = 'pending-bing'
            $map['health'] = 'ok'
            $map['blockReason'] = $null
        }
        else {
            $map['health'] = 'blocked'
            $map['blockReason'] = 'pack-failed'
            $map['lastError'] = [PSCustomObject]@{
                operation = 'pack'; message = 'pack failed'; at = (Get-Date).ToUniversalTime().ToString('o'); retryable = $true
            }
        }
        $rank = Measure-YarnRank -Item (New-YarnPsObject -Map $map)
        foreach ($rp in $rank.PSObject.Properties) { $map[$rp.Name] = $rp.Value }
        $updated = New-YarnPsObject -Map $map
        $all = @(Get-MetraYarnBacklog -Root $Root | Where-Object { [string]$_.id -ne [string]$item.id }) + @($updated)
        Save-MetraYarnBacklogItems -Root $Root -Items $all

        Sync-YarnPlanLink -Root $Root -Link (New-YarnPsObject -Map @{
                backlogId              = [string]$item.id
                formalPlanPath         = $planPath
                planStatus             = 'Pending Bing Review'
                sourceHash             = [string](Get-YarnProp -Object $item -Name 'sourceHash' -Default '')
                planContentHash        = $planHash
                packInputHash          = $packHash
                packPlanPath           = $packPath
                packedAt               = (Get-Date).ToUniversalTime().ToString('o')
                packSucceeded          = $ok
                packContractVersion    = Get-YarnPackContractVersion
                handoffContractVersion = Get-YarnHandoffContractVersion
            })
    }

    Add-MetraYarnJournalEntry -Root $Root -Entry @{
        op       = 'pack'
        planPath = $planPath
        ok       = $ok
        packPath = $packPath
    }

    return [PSCustomObject]@{
        outcome         = if ($ok) { 'packed' } else { 'pack-failed' }
        planPath        = $planPath
        packPath        = $packPath
        planContentHash = $planHash
        packInputHash   = $packHash
        freshCheck      = Test-YarnPackFreshness -PlanText $planText -RecordedPlanContentHash $planHash -RecordedPackInputHash $packHash -RecordedPackContractVersion (Get-YarnPackContractVersion) -LastPackSucceeded:$ok
    }
}

function Invoke-MetraYarnReconcile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [switch]$DryRun
    )

    $results = New-Object System.Collections.Generic.List[object]

    # A3: retry Loom handoff for approved items (pending|failed).
    foreach ($link in @(Get-YarnPlanLinks -Root $Root)) {
        $handoff = Get-YarnProp -Object $link -Name 'loomHandoff' -Default $null
        $state = [string](Get-YarnProp -Object $handoff -Name 'state' -Default '')
        if ($state -notin @('pending', 'failed')) { continue }
        $bid = [string](Get-YarnProp -Object $link -Name 'backlogId' -Default '')
        if ([string]::IsNullOrWhiteSpace($bid)) { continue }
        if ($DryRun) {
            [void]$results.Add([PSCustomObject]@{
                    backlogId = $bid
                    action    = 'would-retry-handoff'
                    state     = $state
                })
            continue
        }
        $retry = Invoke-YarnHandoffIngestRetry -Root $Root -BacklogId $bid -MetraRoot $MetraRoot
        [void]$results.Add($retry)
    }

    foreach ($item in @(Get-MetraYarnBacklog -Root $Root)) {
        if ([string]$item.status -in @('parked', 'rejected', 'approved')) { continue }
        $health = [string](Get-YarnProp -Object $item -Name 'health' -Default 'ok')
        if ($health -in @('blocked', 'inconsistent')) { continue }

        $ready = [bool](Get-YarnProp -Object $item -Name 'readyEnough' -Default $false)
        $sourceKind = [string](Get-YarnProp -Object $item -Name 'sourceKind' -Default '')
        $planPath = [string](Get-YarnProp -Object $item -Name 'formalPlanPath' -Default '')
        $missingPlan = [string]::IsNullOrWhiteSpace($planPath) -or -not (Test-Path -LiteralPath $planPath)

        if ($missingPlan) {
            $maySynth = $ready -or ($sourceKind -eq 'capture')
            if (-not $maySynth) { continue }
            if ($DryRun) {
                [void]$results.Add([PSCustomObject]@{ backlogId = $item.id; action = 'would-synthesize'; sourceKind = $sourceKind })
                continue
            }
            $synth = Invoke-MetraYarnSynthesize -Root $Root -MetraRoot $MetraRoot -BacklogId $item.id -Confirm
            $planPath = [string]$synth.planPath
            [void]$results.Add($synth)
            $item = @(Get-MetraYarnBacklog -Root $Root) | Where-Object { [string]$_.id -eq [string]$synth.backlogId } | Select-Object -First 1
            $ready = [bool](Get-YarnProp -Object $item -Name 'readyEnough' -Default $false)
        }

        if (-not $ready) { continue }

        $planText = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
        $link = @(Get-YarnPlanLinks -Root $Root) | Where-Object { [string]$_.backlogId -eq [string]$item.id } | Select-Object -First 1
        $fresh = Test-YarnPackFreshness -PlanText $planText `
            -RecordedPlanContentHash ([string](Get-YarnProp -Object $link -Name 'planContentHash' -Default '')) `
            -RecordedPackInputHash ([string](Get-YarnProp -Object $link -Name 'packInputHash' -Default '')) `
            -RecordedPackContractVersion ([string](Get-YarnProp -Object $link -Name 'packContractVersion' -Default '')) `
            -LastPackSucceeded:([bool](Get-YarnProp -Object $link -Name 'packSucceeded' -Default $false))

        if ($DryRun) {
            if ($fresh.fresh) {
                [void]$results.Add([PSCustomObject]@{ backlogId = $item.id; action = 'pack-fresh'; planPath = $planPath })
            }
            else {
                [void]$results.Add([PSCustomObject]@{ backlogId = $item.id; action = 'would-pack'; planPath = $planPath; reason = $fresh.reason })
            }
            continue
        }

        if (-not $fresh.fresh) {
            $pack = Invoke-MetraYarnPack -Root $Root -MetraRoot $MetraRoot -BacklogId $item.id
            [void]$results.Add($pack)
        }
        else {
            [void]$results.Add([PSCustomObject]@{ backlogId = $item.id; action = 'pack-fresh'; planPath = $planPath })
        }
    }

    $approvedPending = @()
    foreach ($link in @(Get-YarnPlanLinks -Root $Root)) {
        $st = [string](Get-YarnProp -Object (Get-YarnProp -Object $link -Name 'loomHandoff' -Default $null) -Name 'state' -Default '')
        if ($st -in @('pending', 'failed')) {
            $approvedPending += [PSCustomObject]@{
                backlogId = [string]$link.backlogId
                handoff   = $st
                lastError = [string](Get-YarnProp -Object $link.loomHandoff -Name 'lastError' -Default '')
            }
        }
    }

    return [PSCustomObject]@{
        outcome                    = $(if ($DryRun) { 'reconcile-dry-run' } else { 'reconciled' })
        actions                    = @($results.ToArray())
        approvedButNotEnqueued     = @($approvedPending)
    }
}

function Get-MetraYarnPending {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $items = @(Get-MetraYarnBacklog -Root $Root | Where-Object {
            $st = [string](Get-YarnProp -Object $_ -Name 'status' -Default '')
            $ready = [bool](Get-YarnProp -Object $_ -Name 'readyEnough' -Default $false)
            ($st -in @('ready', 'pending-bing', 'stale-pack')) -or $ready
        })
    $links = @(Get-YarnPlanLinks -Root $Root)
    $rows = foreach ($item in $items) {
        $link = $links | Where-Object { [string]$_.backlogId -eq [string]$item.id } | Select-Object -First 1
        $planPath = [string](Get-YarnProp -Object $item -Name 'formalPlanPath' -Default '')
        $freshReason = ''
        if ($planPath -and (Test-Path -LiteralPath $planPath) -and $link) {
            $text = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
            $fresh = Test-YarnPackFreshness -PlanText $text `
                -RecordedPlanContentHash ([string](Get-YarnProp -Object $link -Name 'planContentHash' -Default '')) `
                -RecordedPackInputHash ([string](Get-YarnProp -Object $link -Name 'packInputHash' -Default '')) `
                -RecordedPackContractVersion ([string](Get-YarnProp -Object $link -Name 'packContractVersion' -Default '')) `
                -LastPackSucceeded:([bool](Get-YarnProp -Object $link -Name 'packSucceeded' -Default $false))
            if (-not $fresh.fresh) { $freshReason = $fresh.reason }
        }
        [PSCustomObject]@{
            id              = $item.id
            title           = $item.title
            status          = $item.status
            total           = $item.total
            completionReady = $item.completionReady
            packPlanPath    = [string](Get-YarnProp -Object $link -Name 'packPlanPath' -Default '')
            staleReason     = $freshReason
            formalPlanPath  = $planPath
        }
    }
    return Sort-YarnBacklogItems -Items $rows
}
