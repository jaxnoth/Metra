# Slice 4 — review orchestrator (sole owner of reviewing exits).

function Get-LoomReviewDefaultLimits {
    [CmdletBinding()]
    param()
    return [PSCustomObject]@{
        maxReviewCycles              = 5
        maxInspectRecoveryAttempts   = 3
        recoveryDelaySeconds         = @(2, 5, 10)
        operationTimeoutMinutes      = 30
    }
}

function Get-LoomContractDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Contract)
    if (-not $Contract) { return 'empty' }
    $json = ($Contract | ConvertTo-Json -Depth 12 -Compress)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function ConvertTo-LoomStructuredVerifyCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Command)
    if ($Command -is [string]) {
        return [PSCustomObject]@{
            executable       = 'pwsh'
            arguments        = @('-NoProfile', '-Command', [string]$Command)
            workingDirectory = '.'
            timeoutSeconds   = 900
        }
    }
    if ($Command -is [System.Collections.IDictionary]) {
        return [PSCustomObject]@{
            executable       = [string](Get-LoomProp -Object $Command -Name 'executable' -Default 'pwsh')
            arguments        = @($(Get-LoomProp -Object $Command -Name 'arguments' -Default @()))
            workingDirectory = [string](Get-LoomProp -Object $Command -Name 'workingDirectory' -Default '.')
            timeoutSeconds   = [int](Get-LoomProp -Object $Command -Name 'timeoutSeconds' -Default 900)
        }
    }
    if ($null -ne $Command) {
        return [PSCustomObject]@{
            executable       = [string](Get-LoomProp -Object $Command -Name 'executable' -Default 'pwsh')
            arguments        = @($(Get-LoomProp -Object $Command -Name 'arguments' -Default @()))
            workingDirectory = [string](Get-LoomProp -Object $Command -Name 'workingDirectory' -Default '.')
            timeoutSeconds   = [int](Get-LoomProp -Object $Command -Name 'timeoutSeconds' -Default 900)
        }
    }
    return $null
}

function Resolve-LoomVerifyWorkingDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$WorkingDirectory = '.'
    )
    $wd = [string]$WorkingDirectory
    if ([string]::IsNullOrWhiteSpace($wd)) { $wd = '.' }
    if ($wd -match '\.\.' -or $wd -match '^[\\/]{2}') {
        throw "Verify workingDirectory escapes project root: $wd"
    }
    $full = if ([System.IO.Path]::IsPathRooted($wd)) {
        [System.IO.Path]::GetFullPath($wd)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $wd))
    }
    if (-not (Test-LoomPathWithinRoot -Path $full -Root $ProjectRoot)) {
        throw "Verify workingDirectory must stay under project root: $full"
    }
    return $full
}

function New-LoomReviewIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item,
        [Parameter(Mandatory)][string]$RunDir,
        [string]$ReviewRunId
    )
    if ([string]::IsNullOrWhiteSpace($ReviewRunId)) {
        $ReviewRunId = [guid]::NewGuid().ToString('n')
    }
    $runNum = [string](Get-LoomProp -Object $Item.execution -Name 'runNumber' -Default '')
    $implRunId = if ($runNum) { "$($Item.id)-run-$runNum" } else { [guid]::NewGuid().ToString('n') }
    $projectRoot = [string](Get-LoomProp -Object $Item.project -Name 'root' -Default '')
    $head = if ($projectRoot -and (Test-Path -LiteralPath $projectRoot)) {
        Get-LoomGitHeadCommit -ProjectRoot $projectRoot
    }
    else { '' }

    $identity = [PSCustomObject]@{
        schemaVersion       = 1
        queueItemId         = [string]$Item.id
        implementationRunId = $implRunId
        reviewRunId         = $ReviewRunId
        sourceCommit        = [string](Get-LoomProp -Object $Item.execution -Name 'baselineSha' -Default $head)
        itemBranch          = [string](Get-LoomProp -Object $Item.execution -Name 'branch' -Default '')
        contractDigest      = Get-LoomContractDigest -Contract $Item.contract
        runDir              = $RunDir
        registryName        = [string](Get-LoomProp -Object $Item.project -Name 'registryName' -Default '')
    }
    Test-LoomContract -Schema 'review-identity' -Object $identity | Out-Null
    return $identity
}

function Get-LoomImplementationRunId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Item)
    $runNum = [string](Get-LoomProp -Object $Item.execution -Name 'runNumber' -Default '')
    if ([string]::IsNullOrWhiteSpace($runNum)) { return $null }
    return "$($Item.id)-run-$runNum"
}

function Test-LoomReviewIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item,
        [Parameter(Mandatory)][object]$Identity,
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$LoomRoot,
        [object]$ExistingReviewState
    )
    if ([string]$Item.status -ne 'reviewing') {
        return [PSCustomObject]@{ ok = $false; reason = 'not-reviewing' }
    }
    if ([string]$Identity.queueItemId -ne [string]$Item.id) {
        return [PSCustomObject]@{ ok = $false; reason = 'item-mismatch' }
    }
    $currentImplRunId = Get-LoomImplementationRunId -Item $Item
    $identityImplRunId = [string](Get-LoomProp -Object $Identity -Name 'implementationRunId' -Default '')
    if ($currentImplRunId -and $identityImplRunId -and $identityImplRunId -ne $currentImplRunId) {
        return [PSCustomObject]@{ ok = $false; reason = 'implementation-run-mismatch' }
    }
    $itemProject = [string](Get-LoomProp -Object $Item.project -Name 'registryName' -Default '')
    $identityProject = [string](Get-LoomProp -Object $Identity -Name 'registryName' -Default '')
    if ($itemProject -and $identityProject -and $identityProject -ne $itemProject) {
        return [PSCustomObject]@{ ok = $false; reason = 'project-mismatch' }
    }
    $itemRunDir = [string](Get-LoomProp -Object $Item.execution -Name 'runDir' -Default '')
    if ($itemRunDir -and $itemRunDir -ne $RunDir) {
        return [PSCustomObject]@{ ok = $false; reason = 'run-dir-mismatch' }
    }
    if ((Get-LoomContractDigest -Contract $Item.contract) -ne [string]$Identity.contractDigest) {
        return [PSCustomObject]@{ ok = $false; reason = 'contract-changed' }
    }
    $branch = Get-LoomGitCurrentBranch -ProjectRoot $ProjectRoot
    if ($branch -ne [string]$Identity.itemBranch) {
        return [PSCustomObject]@{ ok = $false; reason = 'wrong-branch' }
    }
    $head = Get-LoomGitHeadCommit -ProjectRoot $ProjectRoot
    $expected = [string]$Identity.sourceCommit
    if ($expected -and $head -ne $expected) {
        $altCommits = @(
            [string](Get-LoomProp -Object $Item.execution -Name 'postImplementationCommit' -Default '')
            [string](Get-LoomProp -Object $Item.execution -Name 'completedCommit' -Default '')
            [string](Get-LoomProp -Object $ExistingReviewState -Name 'completedCommit' -Default '')
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($altCommits -notcontains $head) {
            return [PSCustomObject]@{ ok = $false; reason = 'stale-commit' }
        }
    }
    if ($LoomRoot -and -not (Test-LoomPathWithinRoot -Path $RunDir -Root $LoomRoot)) {
        return [PSCustomObject]@{ ok = $false; reason = 'run-dir-escape' }
    }
    return [PSCustomObject]@{ ok = $true; reason = $null }
}

function Get-LoomReviewStatePath {
    param([Parameter(Mandatory)][string]$RunDir)
    return Join-Path $RunDir 'review.json'
}

function Get-LoomReviewState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RunDir)
    $path = Get-LoomReviewStatePath -RunDir $RunDir
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch { return $null }
}

function Save-LoomReviewState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][object]$State
    )
    $path = Get-LoomReviewStatePath -RunDir $RunDir
    $json = ($State | ConvertTo-Json -Depth 12) + "`n"
    Write-LoomAtomicUtf8Text -Path $path -Text $json
    return $path
}

function Initialize-LoomReviewCounters {
  [CmdletBinding()]
  param([object]$Existing)
  $base = @{
    reviewCycleCount              = 0
    inspectRecoveryAttemptCount   = 0
    implementationAttemptCount    = 0
    verificationAttemptCount      = 0
  }
  if ($Existing) {
    foreach ($k in @($base.Keys)) {
      $v = Get-LoomProp -Object $Existing -Name $k -Default $null
      if ($null -ne $v) { $base[$k] = [int]$v }
    }
  }
  return [PSCustomObject]$base
}

function Test-LoomReviewCompletionEvidence {
    [CmdletBinding()]
    param([object]$ReviewState)
    if (-not $ReviewState) { return $false }
    $inspect = [string](Get-LoomProp -Object $ReviewState -Name 'inspectOutcome' -Default '')
    $verify = [string](Get-LoomProp -Object $ReviewState -Name 'verifyOutcome' -Default '')
    return ($inspect -eq 'passed' -and $verify -eq 'passed')
}

function Test-LoomCanTransitionToCompleted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$From,
        [object]$ReviewState
    )
    if ($From -ne 'reviewing') { return $false }
    return (Test-LoomReviewCompletionEvidence -ReviewState $ReviewState)
}

function Invoke-LoomInspectEngineRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Probe,
        [int[]]$DelaySeconds = @(2, 5, 10)
    )
    foreach ($delay in $DelaySeconds) {
        Start-Sleep -Seconds $delay
        $r = & $Probe
        if ($r) { return $true }
    }
    return $false
}

function Invoke-LoomReviewCommitTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ItemBranch,
        [Parameter(Mandatory)][string[]]$IntendedPaths,
        [Parameter(Mandatory)][string]$ItemId,
        [string]$CommitMessage
    )
    $expectedBranch = [string]$ItemBranch.Trim()
    $branch = (Get-LoomGitCurrentBranch -ProjectRoot $ProjectRoot).Trim()
    if ($branch -ne $expectedBranch) {
        return [PSCustomObject]@{ ok = $false; reason = "wrong-branch:current=$branch;expected=$expectedBranch"; commit = $null }
    }
    if ([string]::IsNullOrWhiteSpace($branch)) {
        return [PSCustomObject]@{ ok = $false; reason = 'detached-head'; commit = $null }
    }
    $untracked = @(Get-LoomGitUntrackedPaths -ProjectRoot $ProjectRoot)
    foreach ($u in $untracked) {
        $norm = Get-LoomNormalizedRepoRelativePath -ProjectRoot $ProjectRoot -RelativePath $u
        $allowed = $false
        foreach ($p in $IntendedPaths) {
            if ($norm -eq $p -or $norm -like ($p.TrimEnd('/') + '/*')) { $allowed = $true; break }
        }
        if (-not $allowed -and $norm -notmatch '^runs/' -and $norm -notmatch 'review\.json') {
            return [PSCustomObject]@{ ok = $false; reason = "unexpected-untracked:$norm"; commit = $null }
        }
    }
    $changed = @(Get-LoomGitChangedPaths -ProjectRoot $ProjectRoot)
    if ($changed.Count -eq 0) {
        return [PSCustomObject]@{ ok = $false; reason = 'empty-diff'; commit = $null }
    }
    foreach ($p in $changed) {
        if ($p -match 'review\.json' -or $p -match '^runs/') { continue }
        $norm = Get-LoomNormalizedRepoRelativePath -ProjectRoot $ProjectRoot -RelativePath $p
        $allowed = $false
        foreach ($ip in $IntendedPaths) {
            if ($norm -eq $ip -or $norm -like ($ip.TrimEnd('/') + '/*')) { $allowed = $true; break }
        }
        if (-not $allowed) {
            return [PSCustomObject]@{ ok = $false; reason = "unexpected-modified:$norm"; commit = $null }
        }
        $add = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('add', '--', $p)
        if ($add.ExitCode -ne 0) {
            return [PSCustomObject]@{ ok = $false; reason = "git-add-failed:$norm"; commit = $null; detail = (Get-LoomGitErrorDetail $add) }
        }
    }
    $msg = if ($CommitMessage) { $CommitMessage } else { "loom: $ItemId review complete" }
    $commit = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('commit', '-m', $msg)
    if ($commit.ExitCode -ne 0) {
        return [PSCustomObject]@{ ok = $false; reason = 'commit-failed'; commit = $null; detail = (Get-LoomGitErrorDetail $commit) }
    }
    $sha = Get-LoomGitHeadCommit -ProjectRoot $ProjectRoot
    return [PSCustomObject]@{ ok = $true; reason = $null; commit = $sha }
}

function Invoke-MetraLoomReview {
    <#
    .SYNOPSIS
        Slice 4 review orchestrator - sole owner of transitions out of reviewing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId,
        [string]$MetraRoot = (Get-LoomHostRoot),
        [switch]$Confirm,
        [switch]$DryRun,
        [scriptblock]$InspectScript,
        [scriptblock]$VerifyScript,
        [scriptblock]$ImplementerScript,
        [int]$MaxReviewCycles,
        [int]$MaxInspectRecoveryAttempts
    )

    $limits = Get-LoomReviewDefaultLimits
    if (-not $PSBoundParameters.ContainsKey('MaxReviewCycles')) { $MaxReviewCycles = $limits.maxReviewCycles }
    if (-not $PSBoundParameters.ContainsKey('MaxInspectRecoveryAttempts')) { $MaxInspectRecoveryAttempts = $limits.maxInspectRecoveryAttempts }

    $item = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
    if (-not $item) { throw "Queue item not found: $ItemId" }
    if ([string]$item.status -ne 'reviewing') {
        throw "Queue item $ItemId status is '$($item.status)'; expected 'reviewing'."
    }

    $runDir = [string](Get-LoomProp -Object $item.execution -Name 'runDir' -Default '')
    if ([string]::IsNullOrWhiteSpace($runDir)) {
        throw "Queue item $ItemId missing execution.runDir"
    }
    $projectRoot = [System.IO.Path]::GetFullPath([string]$item.project.root)
    $policy = [string](Get-LoomProp -Object $item -Name 'completionCommitPolicy' -Default 'required')
    if ([string]::IsNullOrWhiteSpace($policy)) { $policy = 'required' }

    $existingState = Get-LoomReviewState -RunDir $runDir
    $identity = if ($existingState -and $existingState.identity) {
        $existingState.identity
    }
    else {
        New-LoomReviewIdentity -Item $item -RunDir $runDir
    }

    $idCheck = Test-LoomReviewIdentity -Item $item -Identity $identity -RunDir $runDir -ProjectRoot $projectRoot -LoomRoot $Root -ExistingReviewState $existingState
    if (-not $idCheck.ok) {
        Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'blocked' -Reason "stale-review:$($idCheck.reason)" -Actor 'harness' | Out-Null
        throw "Review identity validation failed: $($idCheck.reason)"
    }

    $counters = Initialize-LoomReviewCounters -Existing $(if ($existingState) { $existingState.counters } else { $null })
    $reviewState = [ordered]@{
        schemaVersion   = 1
        identity        = $identity
        counters        = $counters
        inspectOutcome  = [string](Get-LoomProp -Object $existingState -Name 'inspectOutcome' -Default '')
        verifyOutcome   = [string](Get-LoomProp -Object $existingState -Name 'verifyOutcome' -Default '')
        completedCommit = [string](Get-LoomProp -Object $existingState -Name 'completedCommit' -Default '')
        recoveryLog     = @($(Get-LoomProp -Object $existingState -Name 'recoveryLog' -Default @()))
    }

    if ($DryRun -or -not $Confirm) {
        $dry = [PSCustomObject]@{
            schemaVersion = 1
            outcome       = 'dry-run'
            dryRun        = $true
            message       = 'Review assess only — use -Confirm for live inspect, verify, commit, and transitions.'
            reviewRunId   = [string]$identity.reviewRunId
        }
        return $dry
    }

  # Idempotent resume: already completed commit + evidence
    if ((Test-LoomReviewCompletionEvidence -ReviewState $reviewState) -and [string]$reviewState.completedCommit) {
        $completed = Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'completed' -Reason 'review-resume-complete' -Actor 'harness' -Mutator {
            param($i)
            if (-not $i.execution) { $i | Add-Member -NotePropertyName execution -NotePropertyValue ([PSCustomObject]@{}) -Force }
            $i.execution | Add-Member -NotePropertyName completedCommit -NotePropertyValue ([string]$reviewState.completedCommit) -Force
            return $i
        }
        return [PSCustomObject]@{
            schemaVersion   = 1
            outcome         = 'completed'
            dryRun          = $false
            message         = 'Resumed to completed with existing evidence.'
            reviewRunId     = [string]$identity.reviewRunId
            completedCommit = [string]$reviewState.completedCommit
            status          = [string]$completed.status
        }
    }

    $pkg = $null
    $reqPath = Join-Path $runDir 'request.json'
    if (Test-Path -LiteralPath $reqPath) {
        $pkg = Get-Content -LiteralPath $reqPath -Raw | ConvertFrom-Json
    }
    else {
        $pkg = New-LoomRunRequestPackage -Item $item -RunDir $runDir -MetraRoot $MetraRoot
    }

    # --- Inspect phase ---
    if ([string]$reviewState.inspectOutcome -ne 'passed') {
        $inspectResult = $null
        if ($InspectScript) {
            $inspectResult = & $InspectScript $pkg $projectRoot $runDir
        }
        else {
            $inspectResult = Invoke-LoomInspectAdapter -Request $pkg -ProjectRoot $projectRoot -RunDir $runDir
        }
        $inspectOutcome = [string](Get-LoomProp -Object $inspectResult -Name 'outcome' -Default 'invalid-result')
        $reviewState.inspectOutcome = $inspectOutcome
        Save-LoomReviewState -RunDir $runDir -State ([PSCustomObject]$reviewState) | Out-Null

        switch ($inspectOutcome) {
            'passed' { }
            'regression-reverted' {
                $after = [string](Get-LoomProp -Object $inspectResult -Name 'afterCommit' -Default '')
                $head = Get-LoomGitHeadCommit -ProjectRoot $projectRoot
                if ($after -and $head -ne $after) {
                    Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'blocked' -Reason 'regression-revert-failed' -Actor 'harness' | Out-Null
                    throw 'Regression revert validation failed.'
                }
                $counters.reviewCycleCount++
                Save-LoomReviewState -RunDir $runDir -State ([PSCustomObject]$reviewState) | Out-Null
                Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'implementing' -Reason 'inspect-regression-reverted' -Actor 'harness' | Out-Null
                throw 'Inspect regression reverted — item returned to implementing.'
            }
            'code-findings' {
                if ($counters.reviewCycleCount -ge $MaxReviewCycles) {
                    Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'blocked' -Reason 'MaxReviewCycles exceeded' -Actor 'harness' | Out-Null
                    throw 'Review cycles exhausted.'
                }
                $counters.reviewCycleCount++
                Save-LoomReviewState -RunDir $runDir -State ([PSCustomObject]$reviewState) | Out-Null
                Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'implementing' -Reason 'inspect-code-findings' -Actor 'harness' | Out-Null
                if ($ImplementerScript) {
                    Invoke-LoomImplementerAdapter -Request $pkg -ProjectRoot $projectRoot -RunDir $runDir -ImplementerScript $ImplementerScript | Out-Null
                }
                throw 'Inspect code findings — item returned to implementing.'
            }
            'transient-engine-failure' {
                if ($counters.inspectRecoveryAttemptCount -ge $MaxInspectRecoveryAttempts) {
                    Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'blocked' -Reason 'inspect-recovery-exhausted' -Actor 'harness' | Out-Null
                    throw 'Inspect engine recovery exhausted.'
                }
                $counters.inspectRecoveryAttemptCount++
                $reviewState.recoveryLog += @([PSCustomObject]@{ at = (Get-Date).ToString('o'); type = 'inspect-engine-recovery' })
                Save-LoomReviewState -RunDir $runDir -State ([PSCustomObject]$reviewState) | Out-Null
                $recovered = Invoke-LoomInspectEngineRecovery -Probe { $true } -DelaySeconds $limits.recoveryDelaySeconds
                if (-not $recovered) {
                    Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'blocked' -Reason 'inspect-recovery-failed' -Actor 'harness' | Out-Null
                    throw 'Inspect engine recovery failed.'
                }
                throw 'Transient inspect failure — retry review after recovery.'
            }
            default {
                Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'blocked' -Reason "inspect-$inspectOutcome" -Actor 'harness' | Out-Null
                throw "Inspect blocked: $inspectOutcome"
            }
        }
    }

    # --- Verify phase ---
    if ([string]$reviewState.verifyOutcome -ne 'passed') {
        $counters.verificationAttemptCount++
        $reviewState.counters = $counters
        Save-LoomReviewState -RunDir $runDir -State ([PSCustomObject]$reviewState) | Out-Null

        $verifyResult = $null
        if ($VerifyScript) {
            $verifyResult = & $VerifyScript $pkg $projectRoot $runDir
        }
        else {
            $verifyResult = Invoke-LoomVerifyAdapter -Request $pkg -ProjectRoot $projectRoot -RunDir $runDir
        }
        $verifyOutcome = [string](Get-LoomProp -Object $verifyResult -Name 'outcome' -Default 'invalid-result')
        $reviewState.verifyOutcome = $verifyOutcome
        Save-LoomReviewState -RunDir $runDir -State ([PSCustomObject]$reviewState) | Out-Null

        if ($verifyOutcome -ne 'passed') {
            Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'blocked' -Reason "verify-$verifyOutcome" -Actor 'harness' | Out-Null
            throw "Verify blocked: $verifyOutcome"
        }
    }

    if (-not (Test-LoomReviewCompletionEvidence -ReviewState $reviewState)) {
        Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'blocked' -Reason 'missing-review-evidence' -Actor 'harness' | Out-Null
        throw 'Cannot complete without inspect and verify evidence.'
    }

    # --- Commit transaction (before completed) ---
    $completedCommit = [string]$reviewState.completedCommit
    if ($policy -eq 'required' -and [string]::IsNullOrWhiteSpace($completedCommit)) {
        $allowed = @($(Get-LoomProp -Object $item.contract -Name 'allowedPaths' -Default @()))
        $itemFresh = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
        $branchName = [string](Get-LoomProp -Object $itemFresh.execution -Name 'branch' -Default [string]$identity.itemBranch)
        $commitTx = Invoke-LoomReviewCommitTransaction -ProjectRoot $projectRoot `
            -ItemBranch $branchName -IntendedPaths $allowed -ItemId $ItemId
        if (-not $commitTx.ok) {
            Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'blocked' -Reason "commit-$($commitTx.reason)" -Actor 'harness' | Out-Null
            throw "Commit failed: $($commitTx.reason)"
        }
        $completedCommit = [string]$commitTx.commit
        $reviewState.completedCommit = $completedCommit
        Save-LoomReviewState -RunDir $runDir -State ([PSCustomObject]$reviewState) | Out-Null
        Add-MetraLoomJournalEntry -Root $Root -Entry @{
            timestamp = (Get-Date).ToString('o')
            itemId    = $ItemId
            from      = 'reviewing'
            to        = 'reviewing'
            actor     = 'harness'
            reason    = "completion-commit-created:$completedCommit"
        }
    }
    elseif ($policy -eq 'disabled') {
        $completedCommit = $null
    }

    if (-not (Test-LoomCanTransitionToCompleted -From 'reviewing' -ReviewState $reviewState)) {
        throw 'Transition guard rejected reviewing -> completed.'
    }

    $registry = [string](Get-LoomProp -Object $item.project -Name 'registryName' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($registry)) {
        $gate = Test-LoomProjectAcceptanceGate -Root $Root -RegistryName $registry -ExcludeItemId $ItemId
        if ($gate.blocked) {
            throw $gate.message
        }
    }

    $final = Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'reviewing' -To 'completed' -Reason 'review-complete' -Actor 'harness' -Mutator {
        param($i)
        if (-not $i.execution) { $i | Add-Member -NotePropertyName execution -NotePropertyValue ([PSCustomObject]@{}) -Force }
        $i.execution | Add-Member -NotePropertyName completedCommit -NotePropertyValue $completedCommit -Force
        $i.evidence = @($i.evidence) + @([PSCustomObject]@{
            type   = 'review'
            runDir = $runDir
            at     = (Get-Date).ToString('o')
        })
        return $i
    }

    $result = [PSCustomObject]@{
        schemaVersion   = 1
        outcome         = 'completed'
        dryRun          = $false
        message         = 'Review complete.'
        reviewRunId     = [string]$identity.reviewRunId
        completedCommit   = $completedCommit
        inspectOutcome  = [string]$reviewState.inspectOutcome
        verifyOutcome   = [string]$reviewState.verifyOutcome
        status          = [string]$final.status
    }
    Test-LoomContract -Schema 'review-result' -Object $result | Out-Null
    return $result
}
