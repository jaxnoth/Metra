# A4 lane identity, atomic claim, accept + local commit verification.

function Get-MetraLoomLaneHoldingStatuses {
    <#
    .SYNOPSIS
        Statuses that occupy the one-active-per-projectKey lane (single source of truth).
    #>
    return @(
        'claimed',
        'implementing',
        'reviewing',
        'completed',
        'accepted-pending-commit'
    )
}

function Test-MetraLoomStatusHoldsLane {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Status,
        $Item = $null
    )

    $st = [string]$Status
    if ((Get-MetraLoomLaneHoldingStatuses) -contains $st) {
        return $true
    }
    if ($st -eq 'blocked') {
        $from = [string](Get-LoomProp -Object $Item -Name 'blockedFrom' -Default '')
        if ([string]::IsNullOrWhiteSpace($from)) {
            $laneHeld = Get-LoomProp -Object $Item -Name 'laneHeld' -Default $null
            if ($null -ne $laneHeld) { return [bool]$laneHeld }
            return $false
        }
        return ((Get-MetraLoomLaneHoldingStatuses) -contains $from) -or ($from -eq 'accepted-pending-commit')
    }
    return $false
}

function Get-MetraLoomQueueItemProjectKey {
    <#
    .SYNOPSIS
        Resolve canonical projectKey; optionally persist during locked mutation/migration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        [switch]$PersistNormalized,
        [string]$Root
    )

    $persisted = [string](Get-LoomProp -Object $Item -Name 'projectKey' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($persisted)) {
        return $persisted.Trim()
    }

    $yarnKey = [string](Get-LoomProp -Object (Get-LoomProp -Object $Item -Name 'yarnHandoff' -Default $null) -Name 'projectKey' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($yarnKey)) {
        $key = $yarnKey.Trim()
        if ($PersistNormalized -and $Root) {
            $Item | Add-Member -NotePropertyName projectKey -NotePropertyValue $key -Force
            Save-MetraLoomQueueItem -Root $Root -Item $Item
        }
        return $key
    }

    $registry = [string](Get-LoomProp -Object (Get-LoomProp -Object $Item -Name 'project' -Default $null) -Name 'registryName' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($registry)) {
        $key = $registry.Trim()
        if ($PersistNormalized -and $Root) {
            $Item | Add-Member -NotePropertyName projectKey -NotePropertyValue $key -Force
            Save-MetraLoomQueueItem -Root $Root -Item $Item
        }
        return $key
    }

    return $null
}

function Get-MetraLoomBusyProjectKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ExcludeItemId
    )

    $busy = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @(Get-MetraLoomQueueItems -Root $Root)) {
        if ($ExcludeItemId -and [string]$item.id -eq $ExcludeItemId) { continue }
        if (-not (Test-MetraLoomStatusHoldsLane -Status ([string]$item.status) -Item $item)) { continue }
        $key = Get-MetraLoomQueueItemProjectKey -Item $item
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        [void]$busy.Add($key.Trim())
    }
    return @($busy)
}

function Test-MetraLoomProjectLaneBusy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ProjectKey,
        [string]$ExcludeItemId
    )

    if ([string]::IsNullOrWhiteSpace($ProjectKey)) {
        return [PSCustomObject]@{ busy = $true; reason = 'missing-projectKey'; blockingItemId = $null }
    }
    foreach ($item in @(Get-MetraLoomQueueItems -Root $Root)) {
        if ($ExcludeItemId -and [string]$item.id -eq $ExcludeItemId) { continue }
        if (-not (Test-MetraLoomStatusHoldsLane -Status ([string]$item.status) -Item $item)) { continue }
        $key = Get-MetraLoomQueueItemProjectKey -Item $item
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ([string]::Equals($key.Trim(), $ProjectKey.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
            return [PSCustomObject]@{
                busy            = $true
                reason          = 'lane-held'
                blockingItemId  = [string]$item.id
                blockingStatus  = [string]$item.status
            }
        }
    }
    return [PSCustomObject]@{ busy = $false; reason = $null; blockingItemId = $null }
}

function Sort-MetraLoomEligibleQueuedItems {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Candidates = @()
    )

    if (@($Candidates).Count -eq 0) { return @() }

    return @(
        $Candidates |
            Sort-Object -Property `
                @{ Expression = { [double](Get-LoomProp -Object $_.scores -Name 'total' -Default 0) }; Descending = $true }, `
                @{ Expression = {
                        $ei = Get-LoomProp -Object $_.scores -Name 'effectiveImpact' -Default $null
                        if ($null -eq $ei) {
                            $snap = Get-LoomProp -Object (Get-LoomProp -Object $_ -Name 'yarnHandoff' -Default $null) -Name 'rankSnapshot' -Default $null
                            $ei = Get-LoomProp -Object $snap -Name 'effectiveImpact' -Default 0
                        }
                        [double]$ei
                    }; Descending = $true }, `
                @{ Expression = {
                        try { [datetime]::Parse([string]$_.createdAt) } catch { [datetime]::MinValue }
                    }; Descending = $false }, `
                @{ Expression = { [string]$_.id }; Descending = $false }
    )
}

function Get-MetraLoomEligibleQueuedForClaim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string[]]$BusyProjectKeys = @()
    )

    $busy = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($k in @($BusyProjectKeys)) {
        if (-not [string]::IsNullOrWhiteSpace($k)) { [void]$busy.Add($k.Trim()) }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-MetraLoomQueueItems -Root $Root)) {
        if ([string]$item.status -ne 'queued') { continue }
        $key = Get-MetraLoomQueueItemProjectKey -Item $item
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ($busy.Contains($key.Trim())) { continue }
        $policy = Test-LoomUnattendedPolicy -Root $Root -Item $item
        if (-not $policy.eligible) { continue }
        [void]$candidates.Add($item)
    }
    return @(Sort-MetraLoomEligibleQueuedItems -Candidates @($candidates.ToArray()))
}

function Invoke-MetraLoomClaimNextEligible {
    <#
    .SYNOPSIS
        Atomic claim: lock entire queue namespace, reload, busy lanes, select, queued->claimed, persist+journal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Actor = 'harness',
        [string]$Reason = 'atomic-claim'
    )

    return Invoke-LoomWithNamedMutex -Name 'loom_queue' -Script {
        $busy = @(Get-MetraLoomBusyProjectKeys -Root $Root)
        $eligible = @(Get-MetraLoomEligibleQueuedForClaim -Root $Root -BusyProjectKeys $busy)
        if ($eligible.Count -eq 0) {
            return [PSCustomObject]@{
                claimed     = $false
                queueItemId = $null
                item        = $null
                reason      = 'no-eligible'
            }
        }

        $pick = $eligible[0]
        $id = [string]$pick.id
        $projectKey = Get-MetraLoomQueueItemProjectKey -Item $pick -PersistNormalized -Root $Root
        $lane = Test-MetraLoomProjectLaneBusy -Root $Root -ProjectKey $projectKey -ExcludeItemId $id
        if ($lane.busy) {
            return [PSCustomObject]@{
                claimed     = $false
                queueItemId = $null
                item        = $null
                reason      = 'lane-became-busy'
            }
        }

        $item = Get-MetraLoomQueueItem -Root $Root -Id $id
        if (-not $item -or [string]$item.status -ne 'queued') {
            return [PSCustomObject]@{
                claimed     = $false
                queueItemId = $null
                item        = $null
                reason      = 'stale-eligibility'
            }
        }

        if (-not (Test-MetraLoomTransition -From 'queued' -To 'claimed')) {
            throw "Illegal Loom transition: 'queued' -> 'claimed'"
        }

        $item | Add-Member -NotePropertyName projectKey -NotePropertyValue $projectKey -Force
        $item.status = 'claimed'
        $item.updatedAt = (Get-Date).ToString('o')
        Test-MetraLoomQueueItemSchema -Item $item | Out-Null
        Save-MetraLoomQueueItem -Root $Root -Item $item
        Add-MetraLoomJournalEntry -Root $Root -Entry @{
            timestamp = (Get-Date).ToString('o')
            itemId    = $id
            from      = 'queued'
            to        = 'claimed'
            actor     = $Actor
            reason    = $Reason
        }

        return [PSCustomObject]@{
            claimed     = $true
            queueItemId = $id
            item        = $item
            projectKey  = $projectKey
            reason      = 'ok'
        }
    }
}

function Invoke-MetraLoomClaimItem {
    <#
    .SYNOPSIS
        Atomic claim of a specific queued item (run path), under queue-namespace lock.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId,
        [string]$Actor = 'operator',
        [string]$Reason = 'run-claim',
        [scriptblock]$Mutator
    )

    return Invoke-LoomWithNamedMutex -Name 'loom_queue' -Script {
        $item = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
        if (-not $item) { throw "Queue item not found: $ItemId" }
        if ([string]$item.status -ne 'queued') {
            throw "Queue item $ItemId status is '$($item.status)'; expected 'queued' for claim."
        }
        $projectKey = Get-MetraLoomQueueItemProjectKey -Item $item -PersistNormalized -Root $Root
        if ([string]::IsNullOrWhiteSpace($projectKey)) {
            throw "Queue item $ItemId missing projectKey; cannot claim."
        }
        $lane = Test-MetraLoomProjectLaneBusy -Root $Root -ProjectKey $projectKey -ExcludeItemId $ItemId
        if ($lane.busy) {
            throw ("Project lane busy for '{0}' (blocking {1})." -f $projectKey, $lane.blockingItemId)
        }
        if (-not (Test-MetraLoomTransition -From 'queued' -To 'claimed')) {
            throw "Illegal Loom transition: 'queued' -> 'claimed'"
        }
        if ($Mutator) { $item = & $Mutator $item }
        $item | Add-Member -NotePropertyName projectKey -NotePropertyValue $projectKey.Trim() -Force
        $item.status = 'claimed'
        $item.updatedAt = (Get-Date).ToString('o')
        Test-MetraLoomQueueItemSchema -Item $item | Out-Null
        Save-MetraLoomQueueItem -Root $Root -Item $item
        Add-MetraLoomJournalEntry -Root $Root -Entry @{
            timestamp = (Get-Date).ToString('o')
            itemId    = $ItemId
            from      = 'queued'
            to        = 'claimed'
            actor     = $Actor
            reason    = $Reason
        }
        return $item
    }
}

function Test-MetraLoomLocalCommitVerification {
    <#
    .SYNOPSIS
        Observe-only local commit verification (no commit/push/merge).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$ExpectedProjectRoot
    )

    $expectedRoot = [System.IO.Path]::GetFullPath($ExpectedProjectRoot)
    $projectRoot = [string](Get-LoomProp -Object (Get-LoomProp -Object $Item -Name 'project' -Default $null) -Name 'root' -Default '')
    if ([string]::IsNullOrWhiteSpace($projectRoot)) {
        return [PSCustomObject]@{
            ok = $false; state = 'failed'; sha = $null; lastError = 'missing-project-root'
            repositoryRoot = $null; branch = $null
        }
    }
    $projectRoot = [System.IO.Path]::GetFullPath($projectRoot)
    if (-not [string]::Equals($projectRoot, $expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{
            ok = $false; state = 'failed'; sha = $null
            lastError = 'repository-root-mismatch'
            repositoryRoot = $projectRoot; branch = $null
        }
    }
    if (-not (Test-Path -LiteralPath $projectRoot)) {
        return [PSCustomObject]@{
            ok = $false; state = 'failed'; sha = $null
            lastError = 'repository-root-missing'
            repositoryRoot = $projectRoot; branch = $null
        }
    }

    $expectedBranch = [string](Get-LoomProp -Object (Get-LoomProp -Object $Item -Name 'execution' -Default $null) -Name 'branch' -Default '')
    if ([string]::IsNullOrWhiteSpace($expectedBranch)) {
        return [PSCustomObject]@{
            ok = $false; state = 'failed'; sha = $null
            lastError = 'missing-execution-branch'
            repositoryRoot = $projectRoot; branch = $null
        }
    }

    try {
        $currentBranch = Get-LoomGitCurrentBranch -ProjectRoot $projectRoot
    }
    catch {
        return [PSCustomObject]@{
            ok = $false; state = 'failed'; sha = $null
            lastError = ('branch-resolve-failed:' + $_.Exception.Message)
            repositoryRoot = $projectRoot; branch = $null
        }
    }
    if (-not [string]::Equals($currentBranch, $expectedBranch, [StringComparison]::OrdinalIgnoreCase)) {
        return [PSCustomObject]@{
            ok = $false; state = 'failed'; sha = $null
            lastError = 'branch-mismatch'
            repositoryRoot = $projectRoot; branch = $currentBranch
        }
    }

    try {
        $sha = Get-LoomGitHeadCommit -ProjectRoot $projectRoot
    }
    catch {
        return [PSCustomObject]@{
            ok = $false; state = 'failed'; sha = $null
            lastError = ('head-unavailable:' + $_.Exception.Message)
            repositoryRoot = $projectRoot; branch = $currentBranch
        }
    }
    if ([string]::IsNullOrWhiteSpace($sha)) {
        return [PSCustomObject]@{
            ok = $false; state = 'failed'; sha = $null
            lastError = 'head-empty'
            repositoryRoot = $projectRoot; branch = $currentBranch
        }
    }

    return [PSCustomObject]@{
        ok             = $true
        state          = 'verified'
        sha            = $sha
        lastError      = $null
        repositoryRoot = $projectRoot
        branch         = $currentBranch
    }
}

function Invoke-MetraLoomAcceptWithLocalCommitVerify {
    <#
    .SYNOPSIS
        completed -> accepted-pending-commit (human accept) then local verify -> accepted (or stay pending/failed).
        Observe-only Git; never creates/amends/pushes/merges.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId,
        $Acceptance = $null,
        [string]$Actor = 'operator',
        [switch]$VerifyOnly
    )

    $script:LoomDailyApproveActive = $true
    try {
        $item = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
        if (-not $item) { throw "Queue item not found: $ItemId" }

        if (-not $VerifyOnly) {
            if ([string]$item.status -ne 'completed') {
                throw "ACCEPT requires status completed (was $($item.status))"
            }
            if ($null -eq $Acceptance) {
                throw 'ACCEPT requires Acceptance evidence object.'
            }
            $item = Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'completed' -To 'accepted-pending-commit' `
                -Reason 'daily-accept' -Actor $Actor -Mutator {
                    param($i)
                    $i | Add-Member -NotePropertyName acceptance -NotePropertyValue $Acceptance -Force
                    $i | Add-Member -NotePropertyName commitVerification -NotePropertyValue ([PSCustomObject]@{
                            state          = 'pending'
                            repositoryRoot = $null
                            branch         = $null
                            sha            = $null
                            verifiedAt     = $null
                            lastError      = $null
                        }) -Force
                    return $i
                }
        }
        else {
            if ([string]$item.status -eq 'accepted') {
                return [PSCustomObject]@{
                    outcome = 'already-accepted'
                    itemId  = $ItemId
                    status  = 'accepted'
                    item    = $item
                }
            }
            if ([string]$item.status -ne 'accepted-pending-commit') {
                throw "VerifyOnly requires accepted-pending-commit (was $($item.status))"
            }
            $cv = Get-LoomProp -Object $item -Name 'commitVerification' -Default $null
            if ([string](Get-LoomProp -Object $cv -Name 'state' -Default '') -eq 'verified' -and
                -not [string]::IsNullOrWhiteSpace([string](Get-LoomProp -Object $cv -Name 'sha' -Default ''))) {
                return [PSCustomObject]@{
                    outcome = 'already-verified'
                    itemId  = $ItemId
                    status  = [string]$item.status
                    item    = $item
                    sha     = [string]$cv.sha
                }
            }
        }

        $item = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
        if ([string]$item.status -eq 'accepted') {
            return [PSCustomObject]@{ outcome = 'already-accepted'; itemId = $ItemId; status = 'accepted'; item = $item }
        }

        $existingCv = Get-LoomProp -Object $item -Name 'commitVerification' -Default $null
        if ([string](Get-LoomProp -Object $existingCv -Name 'state' -Default '') -eq 'verified' -and
            -not [string]::IsNullOrWhiteSpace([string](Get-LoomProp -Object $existingCv -Name 'sha' -Default ''))) {
            # Idempotent: already verified evidence present while still pending-commit -> finish to accepted
            $final = Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'accepted-pending-commit' -To 'accepted' `
                -Reason 'commit-verified-idempotent' -Actor $Actor
            Invoke-LoomPlanBoardAcceptedNotify -Item $final
            return [PSCustomObject]@{ outcome = 'accepted'; itemId = $ItemId; status = $final.status; item = $final; sha = $existingCv.sha }
        }

        $projectRoot = [string](Get-LoomProp -Object $item.project -Name 'root' -Default '')
        $verify = Test-MetraLoomLocalCommitVerification -Item $item -ExpectedProjectRoot $projectRoot
        $now = (Get-Date).ToUniversalTime().ToString('o')

        if (-not $verify.ok) {
            $item = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
            $item | Add-Member -NotePropertyName commitVerification -NotePropertyValue ([PSCustomObject]@{
                    state          = 'failed'
                    repositoryRoot = $verify.repositoryRoot
                    branch         = $verify.branch
                    sha            = $null
                    verifiedAt     = $now
                    lastError      = $verify.lastError
                }) -Force
            $item.updatedAt = (Get-Date).ToString('o')
            Save-MetraLoomQueueItem -Root $Root -Item $item
            Add-MetraLoomJournalEntry -Root $Root -Entry @{
                timestamp = (Get-Date).ToString('o')
                itemId    = $ItemId
                from      = 'accepted-pending-commit'
                to        = 'accepted-pending-commit'
                actor     = $Actor
                reason    = ('commit-verify-failed:' + $verify.lastError)
            }
            return [PSCustomObject]@{
                outcome   = 'verify-failed'
                itemId    = $ItemId
                status    = 'accepted-pending-commit'
                item      = $item
                lastError = $verify.lastError
            }
        }

        $final = Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'accepted-pending-commit' -To 'accepted' `
            -Reason 'commit-verified' -Actor $Actor -Mutator {
                param($i)
                $i | Add-Member -NotePropertyName commitVerification -NotePropertyValue ([PSCustomObject]@{
                        state          = 'verified'
                        repositoryRoot = $verify.repositoryRoot
                        branch         = $verify.branch
                        sha            = $verify.sha
                        verifiedAt     = $now
                        lastError      = $null
                    }) -Force
                return $i
            }

        Invoke-LoomPlanBoardAcceptedNotify -Item $final

        return [PSCustomObject]@{
            outcome = 'accepted'
            itemId  = $ItemId
            status  = $final.status
            item    = $final
            sha     = $verify.sha
        }
    }
    finally {
        $script:LoomDailyApproveActive = $false
    }
}
