# Content-bound review affirm + Loom handoff transaction (fail-closed).
# Desk order: affirm (Yarn) -> Approve Plan (Surveyor) -> scan/reconcile handoff.

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

function Invoke-MetraYarnReviewAffirm {
    <#
    .SYNOPSIS
        Record external review affirm: externalReviewed + externalReviewHash only.
        Does not enqueue Loom. Migrates legacy bingReviewed off the automated path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [Parameter(Mandatory)][string]$Path,
        [switch]$DryRun,
        [switch]$Confirm
    )

    if (-not $DryRun -and -not $Confirm) {
        throw 'yarn review affirm requires -Confirm or -DryRun'
    }

    $planPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $planPath)) {
        throw "Plan not found: $planPath"
    }

    $planText = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
    $fm = Get-YarnPlanFrontmatterScalars -PlanText $planText
    $hashNow = Get-YarnPlanContentHash -PlanText $planText

    if ($fm.externalReviewed -and $fm.externalReviewHash -eq $hashNow) {
        return [PSCustomObject]@{
            outcome            = 'already-affirmed'
            planPath           = $planPath
            externalReviewHash = $hashNow
            changed            = $false
        }
    }

    if ($DryRun) {
        $preview = Set-YarnPlanContentBoundMarks -Path $planPath -ExternalReviewed -DryRun
        return [PSCustomObject]@{
            outcome            = 'dry-run'
            planPath           = $planPath
            externalReviewHash = [string]$preview.contentHash
            wouldSet           = @{ externalReviewed = $true; externalReviewHash = [string]$preview.contentHash }
        }
    }

    $fieldsClear = @{}
    if ($fm.map.Contains('bingReviewed')) {
        $fieldsClear['bingReviewed'] = $false
        [void](Set-YarnPlanFrontmatterFields -Path $planPath -Fields $fieldsClear)
    }

    $write = Set-YarnPlanContentBoundMarks -Path $planPath -ExternalReviewed
    $hash = [string]$write.contentHash
    Add-MetraYarnJournalEntry -Root $Root -Entry @{
        op                 = 'review-affirm'
        planPath           = $planPath
        externalReviewHash = $hash
    }

    return [PSCustomObject]@{
        outcome            = 'affirmed'
        planPath           = $planPath
        externalReviewHash = $hash
        changed            = [bool]$write.changed
    }
}

function Invoke-YarnLoomIngest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$ProjectKey,
        [Parameter(Mandatory)][string]$ApprovalRevision,
        [Parameter(Mandatory)][string]$ApprovalId,
        [Parameter(Mandatory)]$RankSnapshot,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [string]$LoomHandoffId
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
            LoomHandoffId          = $LoomHandoffId
        }
    }

    $cmd = Get-Command Invoke-MetraLoomIngestApprovedPlan -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $hostRoot = if (-not [string]::IsNullOrWhiteSpace($MetraRoot)) { $MetraRoot } else { Get-YarnHostRoot }
        $loomManifest = Join-Path $hostRoot 'modules\Loom\Loom.psd1'
        if (Test-Path -LiteralPath $loomManifest) {
            Import-Module $loomManifest -Force
            $cmd = Get-Command Invoke-MetraLoomIngestApprovedPlan -ErrorAction SilentlyContinue
        }
    }
    if (-not $cmd) {
        throw 'Loom ingest adapter unavailable (Invoke-MetraLoomIngestApprovedPlan not loaded).'
    }

    $loomRootCmd = Get-Command Resolve-MetraLoomRoot -ErrorAction SilentlyContinue
    if (-not $loomRootCmd) {
        throw 'Loom root resolver unavailable (Resolve-MetraLoomRoot not loaded).'
    }
    $loomRoot = [string]((& $loomRootCmd).Path)
    $params = @{
        Root                   = $loomRoot
        PlanPath               = $PlanPath
        ProjectKey             = $ProjectKey
        ApprovalRevision       = $ApprovalRevision
        ApprovalId             = $ApprovalId
        RankSnapshot           = $RankSnapshot
        HandoffContractVersion = (Get-YarnHandoffContractVersion)
        MetraRoot              = $MetraRoot
    }
    # Optional LoomHandoffId when Loom supports it (forward-compatible).
    $meta = $cmd.Parameters
    if ($meta -and $meta.ContainsKey('LoomHandoffId') -and -not [string]::IsNullOrWhiteSpace($LoomHandoffId)) {
        $params['LoomHandoffId'] = $LoomHandoffId
    }
    return & $cmd @params
}

function Set-YarnPlanApproved {
    <#
    .SYNOPSIS
        Fail-closed Loom handoff transaction.
        Validate marks -> backlog upsert -> loomHandoffId -> Loom accept -> then status Approved.
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

    $planPath = [string](Get-YarnProp -Object $PlanLink -Name 'formalPlanPath' -Default '')
    if ([string]::IsNullOrWhiteSpace($planPath)) {
        $planPath = [string](Get-YarnProp -Object $BacklogItem -Name 'formalPlanPath' -Default '')
    }
    $projectKeyForRead = [string](Get-YarnProp -Object $BacklogItem -Name 'projectKey' -Default 'Metra')
    if (-not [string]::IsNullOrWhiteSpace($planPath)) {
        $planPath = Resolve-YarnFormalPlanReadPath -FormalPlanPath $planPath -ProjectKey $projectKeyForRead -MetraRoot $MetraRoot
    }
    if ([string]::IsNullOrWhiteSpace($planPath) -or -not (Test-Path -LiteralPath $planPath)) {
        throw "Formal plan missing for backlog $backlogId"
    }

    $planText = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
    $elig = Test-YarnContentBoundLoomEligibility -PlanText $planText
    if (-not $elig.eligible) {
        throw ("Content-bound Loom gates failed ($($elig.reason)). Affirm external review and Approve Plan for current content first.")
    }

    $planHash = [string]$elig.currentContentHash
    $fm = $elig.frontmatter
    $existingHandoffId = [string]$fm.loomHandoffId
    $existingAccepted = [string]$fm.loomAcceptedAt
    $statusNow = [string]$fm.status

    $projectKey = [string](Get-YarnProp -Object $BacklogItem -Name 'projectKey' -Default 'Metra')
    $planIdentity = ('{0}|{1}' -f $projectKey, [System.IO.Path]::GetFileName($planPath))
    $loomHandoffId = if (-not [string]::IsNullOrWhiteSpace($existingHandoffId)) {
        $existingHandoffId
    }
    else {
        Get-YarnDeterministicLoomHandoffId -PlanIdentity $planIdentity -ContentHash $planHash
    }

    $existingApproval = Get-YarnProp -Object $PlanLink -Name 'approval' -Default $null
    $approvalId = [string](Get-YarnProp -Object $existingApproval -Name 'approvalId' -Default '')
    if ([string]::IsNullOrWhiteSpace($approvalId)) { $approvalId = New-YarnApprovalId }
    $approvalRevision = $planHash
    $rankSnapshot = Get-YarnRankSnapshotFromItem -Item $BacklogItem
    $approvedAt = (Get-Date).ToUniversalTime().ToString('o')

    # Idempotent success: already Approved with matching handoff receipt.
    if ($statusNow -match '(?i)^approved$' -and -not [string]::IsNullOrWhiteSpace($existingAccepted)) {
        $handoff = Get-YarnProp -Object $PlanLink -Name 'loomHandoff' -Default $null
        $state = [string](Get-YarnProp -Object $handoff -Name 'state' -Default '')
        if ($state -eq 'succeeded') {
            return [PSCustomObject]@{
                outcome          = 'handoff-already-succeeded'
                backlogId        = $backlogId
                planPath         = $planPath
                approvalId       = $approvalId
                approvalRevision = $approvalRevision
                loomHandoffId    = $loomHandoffId
                queueItemId      = [string](Get-YarnProp -Object $handoff -Name 'queueItemId' -Default '')
            }
        }
    }

    if ($DryRun) {
        return [PSCustomObject]@{
            outcome          = 'dry-run'
            backlogId        = $backlogId
            planPath         = $planPath
            approvalId       = $approvalId
            approvalRevision = $approvalRevision
            loomHandoffId    = $loomHandoffId
            eligible         = $true
        }
    }

    # Ensure backlog + plan-link reflect pending handoff BEFORE Loom (receipt boundary).
    $approval = [PSCustomObject]@{
        approvedAt       = $approvedAt
        approvedBy       = $ApprovedBy
        approvalId       = $approvalId
        approvalRevision = $approvalRevision
        planContentHash  = $planHash
    }
    $handoffPending = [PSCustomObject]@{
        state         = 'pending'
        lastError     = $null
        queueItemId   = $null
        updatedAt     = $approvedAt
        loomHandoffId = $loomHandoffId
    }

    Sync-YarnPlanLink -Root $Root -Link ([PSCustomObject]@{
            backlogId              = $backlogId
            formalPlanPath         = $planPath
            planStatus             = $(if ($statusNow) { $statusNow } else { 'Pending External Review' })
            sourceHash             = [string](Get-YarnProp -Object $PlanLink -Name 'sourceHash' -Default '')
            planContentHash        = $planHash
            packInputHash          = [string](Get-YarnProp -Object $PlanLink -Name 'packInputHash' -Default '')
            packPlanPath           = [string](Get-YarnProp -Object $PlanLink -Name 'packPlanPath' -Default '')
            packContractVersion    = [string](Get-YarnProp -Object $PlanLink -Name 'packContractVersion' -Default (Get-YarnPackContractVersion))
            handoffContractVersion = Get-YarnHandoffContractVersion
            packSucceeded          = [bool](Get-YarnProp -Object $PlanLink -Name 'packSucceeded' -Default $false)
            approval               = $approval
            loomHandoff            = $handoffPending
        })

    $items = @(Get-MetraYarnBacklog -Root $Root)
    $map = ConvertTo-YarnPropertyMap -Object $BacklogItem
    $map['formalPlanPath'] = $planPath
    if ([string](Get-YarnProp -Object $BacklogItem -Name 'status' -Default '') -ne 'approved') {
        $map['status'] = 'pending-bing'
    }
    $updatedItem = (New-YarnPsObject -Map $map)
    $items = @($items | Where-Object { [string]$_.id -ne $backlogId }) + @($updatedItem)
    Save-MetraYarnBacklogItems -Root $Root -Items $items

    Add-MetraYarnJournalEntry -Root $Root -Entry @{
        op               = 'handoff-pending'
        backlogId        = $backlogId
        planPath         = $planPath
        approvalId       = $approvalId
        approvalRevision = $approvalRevision
        loomHandoffId    = $loomHandoffId
    }

    if ($SkipIngest) {
        return [PSCustomObject]@{
            outcome          = 'approved-pending-ingest'
            backlogId        = $backlogId
            planPath         = $planPath
            approvalId       = $approvalId
            approvalRevision = $approvalRevision
            loomHandoffId    = $loomHandoffId
            loomHandoff      = $handoffPending
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
    $loomHandoffId = [string](Get-YarnProp -Object $handoff -Name 'loomHandoffId' -Default '')
    if ($state -eq 'succeeded') {
        return [PSCustomObject]@{
            outcome          = 'handoff-already-succeeded'
            backlogId        = $BacklogId
            queueItemId      = [string](Get-YarnProp -Object $handoff -Name 'queueItemId' -Default '')
            approvalId       = [string](Get-YarnProp -Object $approval -Name 'approvalId' -Default '')
            approvalRevision = [string](Get-YarnProp -Object $approval -Name 'approvalRevision' -Default '')
            loomHandoffId    = $loomHandoffId
        }
    }

    $planPath = [string](Get-YarnProp -Object $link -Name 'formalPlanPath' -Default '')
    $projectKey = [string](Get-YarnProp -Object $item -Name 'projectKey' -Default 'Metra')
    if (-not [string]::IsNullOrWhiteSpace($planPath)) {
        $planPath = Resolve-YarnFormalPlanReadPath -FormalPlanPath $planPath -ProjectKey $projectKey -MetraRoot $MetraRoot
    }

    # Re-validate content-bound gates on retry (plan may have been edited).
    $planText = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
    $elig = Test-YarnContentBoundLoomEligibility -PlanText $planText
    if (-not $elig.eligible) {
        $nowBlock = (Get-Date).ToUniversalTime().ToString('o')
        $blockErr = ("gates-invalid:" + $elig.reason)
        Sync-YarnPlanLink -Root $Root -Link ([PSCustomObject]@{
                backlogId              = $BacklogId
                formalPlanPath         = $planPath
                planStatus             = [string](Get-YarnProp -Object $link -Name 'planStatus' -Default '')
                sourceHash             = [string](Get-YarnProp -Object $link -Name 'sourceHash' -Default '')
                planContentHash        = [string]$elig.currentContentHash
                packInputHash          = [string](Get-YarnProp -Object $link -Name 'packInputHash' -Default '')
                packPlanPath           = [string](Get-YarnProp -Object $link -Name 'packPlanPath' -Default '')
                packContractVersion    = [string](Get-YarnProp -Object $link -Name 'packContractVersion' -Default '')
                handoffContractVersion = Get-YarnHandoffContractVersion
                packSucceeded          = [bool](Get-YarnProp -Object $link -Name 'packSucceeded' -Default $false)
                approval               = $approval
                loomHandoff            = [PSCustomObject]@{
                    state         = 'failed'
                    lastError     = $blockErr
                    queueItemId   = $null
                    updatedAt     = $nowBlock
                    retryable     = $false
                    loomHandoffId = $loomHandoffId
                }
            })
        return [PSCustomObject]@{
            outcome   = 'handoff-gates-invalid'
            backlogId = $BacklogId
            planPath  = $planPath
            lastError = $blockErr
            reason    = $elig.reason
        }
    }

    $planHash = [string]$elig.currentContentHash
    if ([string]::IsNullOrWhiteSpace($loomHandoffId)) {
        $planIdentity = ('{0}|{1}' -f $projectKey, [System.IO.Path]::GetFileName($planPath))
        $loomHandoffId = Get-YarnDeterministicLoomHandoffId -PlanIdentity $planIdentity -ContentHash $planHash
    }

    $approvalId = [string](Get-YarnProp -Object $approval -Name 'approvalId' -Default '')
    if ([string]::IsNullOrWhiteSpace($approvalId)) { $approvalId = New-YarnApprovalId }
    $approvalRevision = $planHash
    $rankSnapshot = Get-YarnRankSnapshotFromItem -Item $item
    $now = (Get-Date).ToUniversalTime().ToString('o')

    try {
        $indexed = Copy-YarnFormalPlanToProjectPlans -SourcePath $planPath -ProjectKey $projectKey -MetraRoot $MetraRoot
        if (-not [string]::Equals($indexed, [System.IO.Path]::GetFullPath($planPath), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "plan-index shim returned non-Cursor path: $indexed"
        }
    }
    catch {
        $copyErr = ("plan-index-upsert: " + [string]$_.Exception.Message)
        Sync-YarnPlanLink -Root $Root -Link ([PSCustomObject]@{
                backlogId              = $BacklogId
                formalPlanPath         = $planPath
                planStatus             = [string](Get-YarnProp -Object $link -Name 'planStatus' -Default '')
                sourceHash             = [string](Get-YarnProp -Object $link -Name 'sourceHash' -Default '')
                planContentHash        = $planHash
                packInputHash          = [string](Get-YarnProp -Object $link -Name 'packInputHash' -Default '')
                packPlanPath           = [string](Get-YarnProp -Object $link -Name 'packPlanPath' -Default '')
                packContractVersion    = [string](Get-YarnProp -Object $link -Name 'packContractVersion' -Default '')
                handoffContractVersion = Get-YarnHandoffContractVersion
                packSucceeded          = [bool](Get-YarnProp -Object $link -Name 'packSucceeded' -Default $false)
                approval               = $approval
                loomHandoff            = [PSCustomObject]@{
                    state         = 'failed'
                    lastError     = $copyErr
                    queueItemId   = $null
                    updatedAt     = $now
                    retryable     = $true
                    loomHandoffId = $loomHandoffId
                }
            })
        Add-MetraYarnJournalEntry -Root $Root -Entry @{
            op        = 'loom-handoff'
            backlogId = $BacklogId
            state     = 'failed'
            error     = $copyErr
        }
        return [PSCustomObject]@{
            outcome          = 'approved-handoff-failed'
            backlogId        = $BacklogId
            planPath         = $planPath
            approvalId       = $approvalId
            approvalRevision = $approvalRevision
            loomHandoffId    = $loomHandoffId
            lastError        = $copyErr
        }
    }

    try {
        $ingest = Invoke-YarnLoomIngest -PlanPath $planPath -ProjectKey $projectKey `
            -ApprovalRevision $approvalRevision -ApprovalId $approvalId `
            -RankSnapshot $rankSnapshot -MetraRoot $MetraRoot -LoomHandoffId $loomHandoffId
        $queueItemId = [string](Get-YarnProp -Object $ingest -Name 'queueItemId' -Default '')
        $acceptedAt = (Get-Date).ToUniversalTime().ToString('o')

        # ONLY after Loom accept: write status Approved + receipts on the plan.
        [void](Set-YarnPlanFrontmatterFields -Path $planPath -Fields @{
                status         = 'Approved'
                loomHandoffId  = $loomHandoffId
                loomAcceptedAt = $acceptedAt
            })

        $approvalOk = [PSCustomObject]@{
            approvedAt       = $acceptedAt
            approvedBy       = 'operator'
            approvalId       = $approvalId
            approvalRevision = $approvalRevision
            planContentHash  = $planHash
        }

        Sync-YarnPlanLink -Root $Root -Link ([PSCustomObject]@{
                backlogId              = $BacklogId
                formalPlanPath         = $planPath
                planStatus             = 'Approved'
                sourceHash             = [string](Get-YarnProp -Object $link -Name 'sourceHash' -Default '')
                planContentHash        = $planHash
                packInputHash          = [string](Get-YarnProp -Object $link -Name 'packInputHash' -Default '')
                packPlanPath           = [string](Get-YarnProp -Object $link -Name 'packPlanPath' -Default '')
                packContractVersion    = [string](Get-YarnProp -Object $link -Name 'packContractVersion' -Default '')
                handoffContractVersion = Get-YarnHandoffContractVersion
                packSucceeded          = [bool](Get-YarnProp -Object $link -Name 'packSucceeded' -Default $false)
                approval               = $approvalOk
                loomHandoff            = [PSCustomObject]@{
                    state         = 'succeeded'
                    lastError     = $null
                    queueItemId   = $queueItemId
                    updatedAt     = $acceptedAt
                    outcome       = [string](Get-YarnProp -Object $ingest -Name 'outcome' -Default '')
                    loomHandoffId = $loomHandoffId
                }
            })

        $all = @(Get-MetraYarnBacklog -Root $Root)
        $bmap = ConvertTo-YarnPropertyMap -Object $item
        $bmap['status'] = 'approved'
        $bmap['formalPlanPath'] = $planPath
        Save-MetraYarnBacklogItems -Root $Root -Items @(($all | Where-Object { [string]$_.id -ne $BacklogId }) + @((New-YarnPsObject -Map $bmap)))

        Add-MetraYarnJournalEntry -Root $Root -Entry @{
            op            = 'loom-handoff'
            backlogId     = $BacklogId
            state         = 'succeeded'
            queueItemId   = $queueItemId
            planPath      = $planPath
            loomHandoffId = $loomHandoffId
        }

        # Plan Board notify is fail-open AFTER accept (no re-ingest on notify failure).
        Invoke-YarnPlanBoardNotifyFailOpen -Root $Root -MetraRoot $MetraRoot -BacklogId $BacklogId -CursorPlan $planPath -Reason 'loom-handoff'

        return [PSCustomObject]@{
            outcome          = 'approved-enqueued'
            backlogId        = $BacklogId
            planPath         = $planPath
            approvalId       = $approvalId
            approvalRevision = $approvalRevision
            loomHandoffId    = $loomHandoffId
            queueItemId      = $queueItemId
            ingest           = $ingest
        }
    }
    catch {
        $err = [string]$_.Exception.Message
        # Fail-closed: do NOT set status Approved when Loom ingest fails.
        Sync-YarnPlanLink -Root $Root -Link ([PSCustomObject]@{
                backlogId              = $BacklogId
                formalPlanPath         = $planPath
                planStatus             = [string](Get-YarnProp -Object $link -Name 'planStatus' -Default '')
                sourceHash             = [string](Get-YarnProp -Object $link -Name 'sourceHash' -Default '')
                planContentHash        = $planHash
                packInputHash          = [string](Get-YarnProp -Object $link -Name 'packInputHash' -Default '')
                packPlanPath           = [string](Get-YarnProp -Object $link -Name 'packPlanPath' -Default '')
                packContractVersion    = [string](Get-YarnProp -Object $link -Name 'packContractVersion' -Default '')
                handoffContractVersion = Get-YarnHandoffContractVersion
                packSucceeded          = [bool](Get-YarnProp -Object $link -Name 'packSucceeded' -Default $false)
                approval               = $approval
                loomHandoff            = [PSCustomObject]@{
                    state         = 'failed'
                    lastError     = $err
                    queueItemId   = $null
                    updatedAt     = $now
                    retryable     = $true
                    loomHandoffId = $loomHandoffId
                }
            })
        Add-MetraYarnJournalEntry -Root $Root -Entry @{
            op            = 'loom-handoff'
            backlogId     = $BacklogId
            state         = 'failed'
            error         = $err
            loomHandoffId = $loomHandoffId
        }
        return [PSCustomObject]@{
            outcome          = 'approved-handoff-failed'
            backlogId        = $BacklogId
            planPath         = $planPath
            approvalId       = $approvalId
            approvalRevision = $approvalRevision
            loomHandoffId    = $loomHandoffId
            lastError        = $err
        }
    }
}

function Sync-YarnEnrollApprovedCursorPlans {
    <#
    .SYNOPSIS
        Operator Approve Plan is a build order. Enroll eligible Cursor plans into Yarn backlog
        so scan/schedule can hand off to Loom without a prior Capture/synth row.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [switch]$DryRun
    )

    $plansDir = Resolve-YarnCursorPlansDir
    if (-not (Test-Path -LiteralPath $plansDir)) {
        return [PSCustomObject]@{ enrolled = 0; updated = 0; scanned = 0 }
    }

    $files = @(Get-ChildItem -LiteralPath $plansDir -Filter '*.plan.md' -File -ErrorAction SilentlyContinue)
    $enrolled = 0
    $updated = 0
    $existing = @(Get-MetraYarnBacklog -Root $Root)

    foreach ($file in $files) {
        $planPath = [System.IO.Path]::GetFullPath($file.FullName)
        try {
            $text = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
            $fm = Get-YarnPlanFrontmatterScalars -PlanText $text
        }
        catch { continue }

        if (-not $fm.approveForLoom) { continue }

        $currentHash = Get-YarnPlanContentHash -PlanText $text
        if (
            -not [string]::IsNullOrWhiteSpace($fm.approveForLoomHash) -and
            $fm.approveForLoomHash -eq $currentHash -and
            (
                -not $fm.externalReviewed -or
                [string]::IsNullOrWhiteSpace($fm.externalReviewHash) -or
                $fm.externalReviewHash -ne $currentHash
            )
        ) {
            if (-not $DryRun) {
                try {
                    $null = Set-YarnPlanContentBoundMarks -Path $planPath -ExternalReviewed
                    $text = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
                    $fm = Get-YarnPlanFrontmatterScalars -PlanText $text
                }
                catch { }
            }
        }

        $elig = Test-YarnContentBoundLoomEligibility -PlanText $text
        if (-not $elig.eligible) { continue }

        $leaf = [System.IO.Path]::GetFileName($planPath)
        $sourceKey = 'cursor-approve:' + $leaf
        $title = [string]$fm.map['name']
        if ([string]::IsNullOrWhiteSpace($title)) { $title = [System.IO.Path]::GetFileNameWithoutExtension($leaf) }
        $overview = [string]$fm.map['overview']
        if ([string]::IsNullOrWhiteSpace($overview)) { $overview = $title }

        $byPath = $existing | Where-Object {
            $fp = [string](Get-YarnProp -Object $_ -Name 'formalPlanPath' -Default '')
            if ([string]::IsNullOrWhiteSpace($fp)) { return $false }
            try {
                return [string]::Equals(
                    [System.IO.Path]::GetFullPath($fp),
                    $planPath,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
            catch { return $false }
        } | Select-Object -First 1

        $primaryKey = if ($byPath) {
            [string](Get-YarnProp -Object $byPath -Name 'primarySourceKey' -Default $sourceKey)
        }
        else { $sourceKey }
        if ([string]::IsNullOrWhiteSpace($primaryKey)) { $primaryKey = $sourceKey }

        $sources = @($primaryKey)
        if ($primaryKey -ne $sourceKey) { $sources += $sourceKey }

        # Never downgrade terminal / already-handed-off backlog rows on re-scan.
        $priorStatus = if ($byPath) {
            [string](Get-YarnProp -Object $byPath -Name 'status' -Default '')
        }
        else { '' }
        $planAlreadyApproved = (
            [string]$fm.status -match '(?i)^approved$' -and
            -not [string]::IsNullOrWhiteSpace([string]$fm.loomHandoffId)
        )
        $status = 'pending-bing'
        if ($priorStatus -in @('approved', 'parked', 'rejected')) {
            $status = $priorStatus
        }
        elseif ($planAlreadyApproved) {
            $status = 'approved'
        }

        $incoming = [PSCustomObject]@{
            title            = $title
            primarySourceKey = $primaryKey
            sources          = $sources
            projectKey       = 'Metra'
            sourceText       = $overview
            status           = $status
            health           = 'ok'
            formalPlanPath   = $planPath
            total            = 3
            effectiveImpact  = 1
            completionReady  = 1
            rubricVersion    = 'yarn-rank-v1'
            rankReasons      = @('surveyorApprove')
        }

        if ($DryRun) {
            if ($byPath) { $updated++ } else { $enrolled++ }
            continue
        }

        # Notify Plan Board on enroll/heal so Approve→queue is visible without a manual sync.
        $row = Sync-YarnBacklogItem -Root $Root -Incoming $incoming
        $linkMap = @{
            backlogId              = [string]$row.id
            formalPlanPath         = $planPath
            planStatus             = $(if ($status -eq 'approved') { 'Approved' } else { 'Pending Loom' })
            handoffContractVersion = Get-YarnHandoffContractVersion
            planContentHash        = [string]$elig.currentContentHash
            packInputHash          = [string]$elig.currentContentHash
            packContractVersion    = Get-YarnPackContractVersion
            packSucceeded          = $true
        }
        if ($planAlreadyApproved) {
            $existingLink = @(Get-YarnPlanLinks -Root $Root) | Where-Object {
                [string](Get-YarnProp -Object $_ -Name 'backlogId' -Default '') -eq [string]$row.id
            } | Select-Object -First 1
            $ho = Get-YarnProp -Object $existingLink -Name 'loomHandoff' -Default $null
            $hoState = [string](Get-YarnProp -Object $ho -Name 'state' -Default '')
            if ($hoState -ne 'succeeded') {
                $linkMap['loomHandoff'] = [PSCustomObject]@{
                    state         = 'succeeded'
                    lastError     = $null
                    queueItemId   = [string](Get-YarnProp -Object $ho -Name 'queueItemId' -Default '')
                    updatedAt     = (Get-Date).ToUniversalTime().ToString('o')
                    outcome       = 'healed-from-plan'
                    loomHandoffId = [string]$fm.loomHandoffId
                }
            }
        }
        Sync-YarnPlanLink -Root $Root -Link (New-YarnPsObject -Map $linkMap)

        if ($byPath) { $updated++ } else { $enrolled++ }
        $existing = @(Get-MetraYarnBacklog -Root $Root)
    }

    return [PSCustomObject]@{
        enrolled = $enrolled
        updated  = $updated
        scanned  = $files.Count
    }
}

function Find-YarnApproveForLoomCandidates {
    <#
    .SYNOPSIS
        Discover backlog items / plan paths with approveForLoom intent for scan/reconcile.
        Enrolls Surveyor-approved Cursor plans into the backlog first (Approve = build order).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot)
    )

    $null = Sync-YarnEnrollApprovedCursorPlans -Root $Root -MetraRoot $MetraRoot

    $hits = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($item in @(Get-MetraYarnBacklog -Root $Root)) {
        $planPath = [string](Get-YarnProp -Object $item -Name 'formalPlanPath' -Default '')
        $pk = [string](Get-YarnProp -Object $item -Name 'projectKey' -Default 'Metra')
        if ([string]::IsNullOrWhiteSpace($planPath)) { continue }
        try {
            $planPath = Resolve-YarnFormalPlanReadPath -FormalPlanPath $planPath -ProjectKey $pk -MetraRoot $MetraRoot
        }
        catch { continue }
        if (-not (Test-Path -LiteralPath $planPath)) { continue }
        if (-not $seen.Add($planPath)) { continue }

        try {
            $text = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
            $fm = Get-YarnPlanFrontmatterScalars -PlanText $text
        }
        catch { continue }

        if (-not $fm.approveForLoom) { continue }

        # Approve Plan is operator authority for both gates. Backfill externalReviewed
        # when approveForLoom hash already matches current content (pre-override Approves).
        $currentHash = Get-YarnPlanContentHash -PlanText $text
        if (
            -not [string]::IsNullOrWhiteSpace($fm.approveForLoomHash) -and
            $fm.approveForLoomHash -eq $currentHash -and
            (
                -not $fm.externalReviewed -or
                [string]::IsNullOrWhiteSpace($fm.externalReviewHash) -or
                $fm.externalReviewHash -ne $currentHash
            )
        ) {
            try {
                $null = Set-YarnPlanContentBoundMarks -Path $planPath -ExternalReviewed
                $text = [System.IO.File]::ReadAllText($planPath, (Get-YarnUtf8NoBomEncoding))
                $fm = Get-YarnPlanFrontmatterScalars -PlanText $text
            }
            catch { }
        }

        $elig = Test-YarnContentBoundLoomEligibility -PlanText $text
        [void]$hits.Add([PSCustomObject]@{
                backlogId     = [string]$item.id
                planPath      = $planPath
                projectKey    = $pk
                eligible      = [bool]$elig.eligible
                reason        = [string]$elig.reason
                contentHash   = [string]$elig.currentContentHash
                status        = [string]$fm.status
                loomHandoffId = [string]$fm.loomHandoffId
            })
    }

    return @($hits.ToArray())
}

function Invoke-YarnProcessApproveForLoomCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-YarnHostRoot),
        [switch]$DryRun
    )

    $results = New-Object System.Collections.Generic.List[object]
    $validationBlocked = 0
    foreach ($c in @(Find-YarnApproveForLoomCandidates -Root $Root -MetraRoot $MetraRoot)) {
        if (-not $c.eligible) {
            $validationBlocked++
            [void]$results.Add([PSCustomObject]@{
                    backlogId = $c.backlogId
                    planPath  = $c.planPath
                    outcome   = 'not-eligible'
                    reason    = $c.reason
                })
            continue
        }
        if ($c.status -match '(?i)^approved$' -and -not [string]::IsNullOrWhiteSpace($c.loomHandoffId)) {
            # Reconcile Plan Board when already handed off (card may still show Idea).
            Invoke-YarnPlanBoardNotifyFailOpen -Root $Root -MetraRoot $MetraRoot `
                -BacklogId ([string]$c.backlogId) -CursorPlan $c.planPath -Reason 'loom-handoff-reconcile'
            [void]$results.Add([PSCustomObject]@{
                    backlogId = $c.backlogId
                    planPath  = $c.planPath
                    outcome   = 'already-approved'
                })
            continue
        }
        if ($DryRun) {
            [void]$results.Add([PSCustomObject]@{
                    backlogId = $c.backlogId
                    planPath  = $c.planPath
                    outcome   = 'would-handoff'
                })
            continue
        }

        $item = @(Get-MetraYarnBacklog -Root $Root) | Where-Object { [string]$_.id -eq [string]$c.backlogId } | Select-Object -First 1
        $link = @(Get-YarnPlanLinks -Root $Root) | Where-Object { [string]$_.backlogId -eq [string]$c.backlogId } | Select-Object -First 1
        if (-not $link) {
            Sync-YarnPlanLink -Root $Root -Link ([PSCustomObject]@{
                    backlogId              = $c.backlogId
                    formalPlanPath         = $c.planPath
                    planStatus             = 'Pending Loom'
                    handoffContractVersion = Get-YarnHandoffContractVersion
                    planContentHash        = $c.contentHash
                    packInputHash          = $c.contentHash
                    packContractVersion    = Get-YarnPackContractVersion
                    packSucceeded          = $true
                })
            $link = @(Get-YarnPlanLinks -Root $Root) | Where-Object { [string]$_.backlogId -eq [string]$c.backlogId } | Select-Object -First 1
        }
        $handoff = Set-YarnPlanApproved -Root $Root -BacklogItem $item -PlanLink $link -MetraRoot $MetraRoot
        [void]$results.Add($handoff)
    }

    return [PSCustomObject]@{
        actions            = @($results.ToArray())
        validationBlocked  = $validationBlocked
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
