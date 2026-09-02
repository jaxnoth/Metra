# A3: human approval + Loom handoff (Yarn never writes Loom queue files).

function New-YarnApprovalId {
    return ('ya-' + [guid]::NewGuid().ToString('n'))
}

function Get-YarnRankSnapshotFromItem {
    param([Parameter(Mandatory)]$Item)
    return [PSCustomObject]@{
        total            = [double](Get-YarnProp -Object $Item -Name 'total' -Default 0)
        effectiveImpact  = [double](Get-YarnProp -Object $Item -Name 'effectiveImpact' -Default 0)
        completionReady  = [double](Get-YarnProp -Object $Item -Name 'completionReady' -Default 0)
        rubricVersion    = [string](Get-YarnProp -Object $Item -Name 'rubricVersion' -Default (Get-YarnRubricVersion))
        rankReasons      = @(Get-YarnProp -Object $Item -Name 'rankReasons' -Default @())
    }
}

function Set-YarnFormalPlanApprovedFrontmatter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [switch]$DryRun
    )

    $text = [System.IO.File]::ReadAllText($PlanPath, (Get-YarnUtf8NoBomEncoding))
    if ($text -notmatch '(?ms)^---\r?\n.*?\r?\n---') {
        throw "Formal plan missing YAML frontmatter: $PlanPath"
    }
    $updated = [regex]::Replace($text, '(?m)^status:\s*.*$', 'status: Approved', 1)
    if ($updated -match '(?m)^bingReviewed:\s*') {
        $updated = [regex]::Replace($updated, '(?m)^bingReviewed:\s*.*$', 'bingReviewed: true', 1)
    }
    else {
        $updated = [regex]::Replace($updated, '(?ms)^(---\r?\n)', "`$1bingReviewed: true`n", 1)
    }
    if ($DryRun) {
        return [PSCustomObject]@{ changed = ($updated -ne $text); text = $updated }
    }
    Write-YarnAtomicUtf8Text -Path $PlanPath -Text $updated
    return [PSCustomObject]@{ changed = ($updated -ne $text); path = $PlanPath }
}

function Invoke-YarnLoomIngest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$ProjectKey,
        [Parameter(Mandatory)][string]$ApprovalRevision,
        [Parameter(Mandatory)][string]$ApprovalId,
        [Parameter(Mandatory)]$RankSnapshot,
        [string]$MetraRoot = (Get-YarnHostRoot)
    )

    if ($script:YarnLoomIngestOverride) {
        return & $script:YarnLoomIngestOverride @{
            PlanPath               = $PlanPath
            ProjectKey             = $ProjectKey
            ApprovalRevision       = $ApprovalRevision
            ApprovalId             = $ApprovalId
            RankSnapshot           = $RankSnapshot
            HandoffContractVersion = Get-YarnHandoffContractVersion
            MetraRoot              = $MetraRoot
        }
    }

    $cmd = Get-Command Invoke-MetraLoomIngestApprovedPlan -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw 'Loom ingest adapter unavailable (Invoke-MetraLoomIngestApprovedPlan not loaded).'
    }

    $loomRootCmd = Get-Command Resolve-MetraLoomRoot -ErrorAction SilentlyContinue
    if (-not $loomRootCmd) {
        throw 'Loom root resolver unavailable (Resolve-MetraLoomRoot not loaded).'
    }
    $loomRoot = [string]((& $loomRootCmd).Path)
    return & $cmd -Root $loomRoot -PlanPath $PlanPath -ProjectKey $ProjectKey `
        -ApprovalRevision $ApprovalRevision -ApprovalId $ApprovalId `
        -RankSnapshot $RankSnapshot -HandoffContractVersion (Get-YarnHandoffContractVersion) `
        -MetraRoot $MetraRoot
}

function Set-YarnPlanApproved {
    <#
    .SYNOPSIS
        Coordinated Approved write + Loom ingest request (A3).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$BacklogItem,
        [Parameter(Mandatory)]$PlanLink,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [string]$ApprovedBy = 'operator',
        [switch]$DryRun,
        [switch]$SkipIngest
    )

    $backlogId = [string](Get-YarnProp -Object $BacklogItem -Name 'id' -Default '')
    $health = [string](Get-YarnProp -Object $BacklogItem -Name 'health' -Default 'ok')
    if ($health -in @('blocked', 'inconsistent')) {
        throw "Cannot approve backlog $backlogId while health=$health"
    }

    $status = [string](Get-YarnProp -Object $BacklogItem -Name 'status' -Default '')
    $alreadyApproved = ($status -eq 'approved')
    if (-not $alreadyApproved -and $status -ne 'pending-bing') {
        throw "Cannot approve backlog $backlogId with status '$status' (require pending-bing)."
    }

    $planPath = [string](Get-YarnProp -Object $PlanLink -Name 'formalPlanPath' -Default '')
    if ([string]::IsNullOrWhiteSpace($planPath)) {
        $planPath = [string](Get-YarnProp -Object $BacklogItem -Name 'formalPlanPath' -Default '')
    }
    if ([string]::IsNullOrWhiteSpace($planPath) -or -not (Test-Path -LiteralPath $planPath)) {
        throw "Formal plan missing for backlog $backlogId"
    }

    $planText = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
    $fresh = Test-YarnPackFreshness -PlanText $planText `
        -RecordedPlanContentHash ([string](Get-YarnProp -Object $PlanLink -Name 'planContentHash' -Default '')) `
        -RecordedPackInputHash ([string](Get-YarnProp -Object $PlanLink -Name 'packInputHash' -Default '')) `
        -RecordedPackContractVersion ([string](Get-YarnProp -Object $PlanLink -Name 'packContractVersion' -Default '')) `
        -LastPackSucceeded:([bool](Get-YarnProp -Object $PlanLink -Name 'packSucceeded' -Default $false))
    if (-not $fresh.fresh) {
        throw ("Pack not fresh for approve ($($fresh.reason)). Run yarn pack / reconcile first.")
    }

    $planHash = Get-YarnPlanContentHash -PlanText $planText
    $linkHash = [string](Get-YarnProp -Object $PlanLink -Name 'planContentHash' -Default '')
    if ($linkHash -ne $planHash) {
        throw 'Formal plan vs plan-link planContentHash mismatch (health=inconsistent path).'
    }

    $existingApproval = Get-YarnProp -Object $PlanLink -Name 'approval' -Default $null
    $approvalId = [string](Get-YarnProp -Object $existingApproval -Name 'approvalId' -Default '')
    $approvalRevision = [string](Get-YarnProp -Object $existingApproval -Name 'approvalRevision' -Default '')
    if ([string]::IsNullOrWhiteSpace($approvalId)) { $approvalId = New-YarnApprovalId }
    if ([string]::IsNullOrWhiteSpace($approvalRevision)) { $approvalRevision = $planHash }

    $projectKey = [string](Get-YarnProp -Object $BacklogItem -Name 'projectKey' -Default 'Metra')
    $rankSnapshot = Get-YarnRankSnapshotFromItem -Item $BacklogItem
    $approvedAt = (Get-Date).ToUniversalTime().ToString('o')

    if ($DryRun) {
        return [PSCustomObject]@{
            outcome          = 'dry-run'
            backlogId        = $backlogId
            planPath         = $planPath
            approvalId       = $approvalId
            approvalRevision = $approvalRevision
        }
    }

    [void](Set-YarnFormalPlanApprovedFrontmatter -PlanPath $planPath)

    $approval = [PSCustomObject]@{
        approvedAt         = $approvedAt
        approvedBy         = $ApprovedBy
        approvalId         = $approvalId
        approvalRevision   = $approvalRevision
        planContentHash    = $planHash
    }

    $handoff = [PSCustomObject]@{
        state      = 'pending'
        lastError  = $null
        queueItemId = $null
        updatedAt  = $approvedAt
    }

    Sync-YarnPlanLink -Root $Root -Link ([PSCustomObject]@{
            backlogId              = $backlogId
            formalPlanPath         = $planPath
            planStatus             = 'Approved'
            sourceHash             = [string](Get-YarnProp -Object $PlanLink -Name 'sourceHash' -Default '')
            planContentHash        = $planHash
            packInputHash          = [string](Get-YarnProp -Object $PlanLink -Name 'packInputHash' -Default '')
            packPlanPath           = [string](Get-YarnProp -Object $PlanLink -Name 'packPlanPath' -Default '')
            packContractVersion    = [string](Get-YarnProp -Object $PlanLink -Name 'packContractVersion' -Default (Get-YarnPackContractVersion))
            handoffContractVersion = Get-YarnHandoffContractVersion
            packSucceeded          = [bool](Get-YarnProp -Object $PlanLink -Name 'packSucceeded' -Default $false)
            approval               = $approval
            loomHandoff            = $handoff
        })

    $items = @(Get-MetraYarnBacklog -Root $Root)
    $map = ConvertTo-YarnPropertyMap -Object $BacklogItem
    $map['status'] = 'approved'
    $map['formalPlanPath'] = $planPath
    $updatedItem = (New-YarnPsObject -Map $map)
    $items = @($items | Where-Object { [string]$_.id -ne $backlogId }) + @($updatedItem)
    Save-MetraYarnBacklogItems -Root $Root -Items $items

    Add-MetraYarnJournalEntry -Root $Root -Entry @{
        op               = 'approve'
        backlogId        = $backlogId
        planPath         = $planPath
        approvalId       = $approvalId
        approvalRevision = $approvalRevision
    }

    if ($SkipIngest) {
        return [PSCustomObject]@{
            outcome          = 'approved-pending-ingest'
            backlogId        = $backlogId
            planPath         = $planPath
            approvalId       = $approvalId
            approvalRevision = $approvalRevision
            loomHandoff      = $handoff
        }
    }

    return Invoke-YarnHandoffIngestRetry -Root $Root -BacklogId $backlogId -MetraRoot $MetraRoot
}

function Invoke-YarnHandoffIngestRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BacklogId,
        [string]$MetraRoot = (Get-YarnHostRoot)
    )

    $item = @(Get-MetraYarnBacklog -Root $Root) | Where-Object { [string]$_.id -eq $BacklogId } | Select-Object -First 1
    if (-not $item) { throw "Backlog item not found: $BacklogId" }
    $link = @(Get-YarnPlanLinks -Root $Root) | Where-Object { [string]$_.backlogId -eq $BacklogId } | Select-Object -First 1
    if (-not $link) { throw "Plan-link missing for backlog $BacklogId" }

    $approval = Get-YarnProp -Object $link -Name 'approval' -Default $null
    $handoff = Get-YarnProp -Object $link -Name 'loomHandoff' -Default $null
    $state = [string](Get-YarnProp -Object $handoff -Name 'state' -Default '')
    if ($state -eq 'succeeded') {
        return [PSCustomObject]@{
            outcome          = 'handoff-already-succeeded'
            backlogId        = $BacklogId
            queueItemId      = [string](Get-YarnProp -Object $handoff -Name 'queueItemId' -Default '')
            approvalId       = [string](Get-YarnProp -Object $approval -Name 'approvalId' -Default '')
            approvalRevision = [string](Get-YarnProp -Object $approval -Name 'approvalRevision' -Default '')
        }
    }

    $planPath = [string](Get-YarnProp -Object $link -Name 'formalPlanPath' -Default '')
    $projectKey = [string](Get-YarnProp -Object $item -Name 'projectKey' -Default 'Metra')
    $approvalId = [string](Get-YarnProp -Object $approval -Name 'approvalId' -Default '')
    $approvalRevision = [string](Get-YarnProp -Object $approval -Name 'approvalRevision' -Default '')
    $rankSnapshot = Get-YarnRankSnapshotFromItem -Item $item
    $now = (Get-Date).ToUniversalTime().ToString('o')

    try {
        $ingest = Invoke-YarnLoomIngest -PlanPath $planPath -ProjectKey $projectKey `
            -ApprovalRevision $approvalRevision -ApprovalId $approvalId `
            -RankSnapshot $rankSnapshot -MetraRoot $MetraRoot
        $queueItemId = [string](Get-YarnProp -Object $ingest -Name 'queueItemId' -Default '')
        Sync-YarnPlanLink -Root $Root -Link ([PSCustomObject]@{
                backlogId              = $BacklogId
                formalPlanPath         = $planPath
                planStatus             = 'Approved'
                sourceHash             = [string](Get-YarnProp -Object $link -Name 'sourceHash' -Default '')
                planContentHash        = [string](Get-YarnProp -Object $link -Name 'planContentHash' -Default '')
                packInputHash          = [string](Get-YarnProp -Object $link -Name 'packInputHash' -Default '')
                packPlanPath           = [string](Get-YarnProp -Object $link -Name 'packPlanPath' -Default '')
                packContractVersion    = [string](Get-YarnProp -Object $link -Name 'packContractVersion' -Default '')
                handoffContractVersion = Get-YarnHandoffContractVersion
                packSucceeded          = [bool](Get-YarnProp -Object $link -Name 'packSucceeded' -Default $false)
                approval               = $approval
                loomHandoff            = [PSCustomObject]@{
                    state       = 'succeeded'
                    lastError   = $null
                    queueItemId = $queueItemId
                    updatedAt   = $now
                    outcome     = [string](Get-YarnProp -Object $ingest -Name 'outcome' -Default '')
                }
            })
        Add-MetraYarnJournalEntry -Root $Root -Entry @{
            op          = 'loom-handoff'
            backlogId   = $BacklogId
            state       = 'succeeded'
            queueItemId = $queueItemId
        }
        return [PSCustomObject]@{
            outcome          = 'approved-enqueued'
            backlogId        = $BacklogId
            planPath         = $planPath
            approvalId       = $approvalId
            approvalRevision = $approvalRevision
            queueItemId      = $queueItemId
            ingest           = $ingest
        }
    }
    catch {
        $err = [string]$_.Exception.Message
        Sync-YarnPlanLink -Root $Root -Link ([PSCustomObject]@{
                backlogId              = $BacklogId
                formalPlanPath         = $planPath
                planStatus             = 'Approved'
                sourceHash             = [string](Get-YarnProp -Object $link -Name 'sourceHash' -Default '')
                planContentHash        = [string](Get-YarnProp -Object $link -Name 'planContentHash' -Default '')
                packInputHash          = [string](Get-YarnProp -Object $link -Name 'packInputHash' -Default '')
                packPlanPath           = [string](Get-YarnProp -Object $link -Name 'packPlanPath' -Default '')
                packContractVersion    = [string](Get-YarnProp -Object $link -Name 'packContractVersion' -Default '')
                handoffContractVersion = Get-YarnHandoffContractVersion
                packSucceeded          = [bool](Get-YarnProp -Object $link -Name 'packSucceeded' -Default $false)
                approval               = $approval
                loomHandoff            = [PSCustomObject]@{
                    state       = 'failed'
                    lastError   = $err
                    queueItemId = $null
                    updatedAt   = $now
                    retryable   = $true
                }
            })
        Add-MetraYarnJournalEntry -Root $Root -Entry @{
            op        = 'loom-handoff'
            backlogId = $BacklogId
            state     = 'failed'
            error     = $err
        }
        return [PSCustomObject]@{
            outcome          = 'approved-handoff-failed'
            backlogId        = $BacklogId
            planPath         = $planPath
            approvalId       = $approvalId
            approvalRevision = $approvalRevision
            lastError        = $err
        }
    }
}

function Invoke-MetraYarnPlanApprove {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [string]$BacklogId,
        [string]$Path,
        [switch]$DryRun,
        [switch]$Confirm,
        [string]$ApprovedBy = 'operator'
    )

    if (-not $DryRun -and -not $Confirm) {
        throw 'yarn plan approve requires -Confirm or -DryRun'
    }

    $item = $null
    if ($BacklogId) {
        $item = @(Get-MetraYarnBacklog -Root $Root) | Where-Object { [string]$_.id -eq $BacklogId } | Select-Object -First 1
    }
    elseif ($Path) {
        $full = [System.IO.Path]::GetFullPath($Path)
        $item = @(Get-MetraYarnBacklog -Root $Root) | Where-Object {
            $p = [string](Get-YarnProp -Object $_ -Name 'formalPlanPath' -Default '')
            $p -and ([System.IO.Path]::GetFullPath($p) -eq $full)
        } | Select-Object -First 1
        if (-not $item) {
            $linkHit = @(Get-YarnPlanLinks -Root $Root) | Where-Object {
                $p = [string](Get-YarnProp -Object $_ -Name 'formalPlanPath' -Default '')
                $p -and ([System.IO.Path]::GetFullPath($p) -eq $full)
            } | Select-Object -First 1
            if ($linkHit) {
                $bid = [string]$linkHit.backlogId
                $item = @(Get-MetraYarnBacklog -Root $Root) | Where-Object { [string]$_.id -eq $bid } | Select-Object -First 1
            }
        }
    }
    else {
        throw 'yarn plan approve requires -BacklogId <id> or -Path <formal.plan.md>'
    }
    if (-not $item) { throw 'Backlog item not found for approve' }

    $link = @(Get-YarnPlanLinks -Root $Root) | Where-Object { [string]$_.backlogId -eq [string]$item.id } | Select-Object -First 1
    if (-not $link) { throw "Plan-link missing for backlog $($item.id)" }

    return Set-YarnPlanApproved -Root $Root -BacklogItem $item -PlanLink $link -MetraRoot $MetraRoot `
        -ApprovedBy $ApprovedBy -DryRun:$DryRun
}
