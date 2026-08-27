# Inspect fix-step dispatch: decide / package / record-fix (schema v2).
# Dot-sourced by Metra.psm1 (loads before Inspect.ps1 by name sort).

function Resolve-MetraInspectReviewSlotRoot {
    <#
    .SYNOPSIS
        Sanitize SlotKey and return a confined directory under the inspect state root.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$SlotKey)

    $raw = [string]$SlotKey
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $safe = 'default'
    }
    else {
        if ([System.IO.Path]::IsPathRooted($raw) -or $raw -match '[\\/]') {
            throw ("Inspect SlotKey must not contain path separators or be rooted: {0}" -f $raw)
        }
        if ($raw -eq '.' -or $raw -eq '..') {
            throw ("Inspect SlotKey must not be '.' or '..': {0}" -f $raw)
        }
        # Word chars and hyphen only - dots removed so '..' cannot survive sanitization.
        $safe = ($raw -replace '[^\w-]', '_').Trim('_')
        while ($safe -match '__') { $safe = $safe -replace '__', '_' }
        if ([string]::IsNullOrWhiteSpace($safe) -or $safe -eq '.' -or $safe -eq '..') {
            $safe = 'default'
        }
    }

    $stateRoot = [System.IO.Path]::GetFullPath((Get-MetraInspectStateRoot))
    $slotRoot = [System.IO.Path]::GetFullPath((Join-Path $stateRoot $safe))
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $rootPrefix = $stateRoot.TrimEnd([char]'\', [char]'/') + $sep
    if (-not (
            [string]::Equals($slotRoot, $stateRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $slotRoot.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
        )) {
        throw 'Inspect slot path escaped the state root.'
    }

    return [PSCustomObject]@{
        SafeKey   = $safe
        SlotRoot  = $slotRoot
        StateRoot = $stateRoot
    }
}

function Get-MetraInspectReviewFixQueuePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SlotKey)

    $slot = Resolve-MetraInspectReviewSlotRoot -SlotKey $SlotKey
    return Join-Path $slot.SlotRoot 'fix-queue.json'
}

function Get-MetraInspectReviewFixPackageDir {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SlotKey)

    $slot = Resolve-MetraInspectReviewSlotRoot -SlotKey $SlotKey
    return Join-Path $slot.SlotRoot 'packages'
}

function Initialize-MetraInspectReviewLoopStateV2Fields {
    <#
    .SYNOPSIS
        StrictMode-safe schema v2 ensure/migrate for review-loop session state.
    .OUTPUTS
        $true when schemaVersion was below 2 (migrated); otherwise $false.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)

    $ver = [int](Get-MetraProp -Object $State -Name 'schemaVersion' -Default 1)
    $migrated = $false
    if ($ver -lt 2) {
        $State | Add-Member -NotePropertyName schemaVersion -NotePropertyValue 2 -Force
        $migrated = $true
    }
    else {
        $State | Add-Member -NotePropertyName schemaVersion -NotePropertyValue $ver -Force
    }

    if ($null -eq (Get-MetraProp -Object $State -Name 'dispatchFixCount' -Default $null)) {
        $State | Add-Member -NotePropertyName dispatchFixCount -NotePropertyValue 0 -Force
    }
    if ($null -eq (Get-MetraProp -Object $State -Name 'inlineFixCount' -Default $null)) {
        $State | Add-Member -NotePropertyName inlineFixCount -NotePropertyValue 0 -Force
    }
    if ($null -eq (Get-MetraProp -Object $State -Name 'fixDispatchInFlight' -Default $null)) {
        $State | Add-Member -NotePropertyName fixDispatchInFlight -NotePropertyValue $false -Force
    }
    if ($null -eq (Get-MetraProp -Object $State -Name 'lastFixPackageId' -Default $null)) {
        $State | Add-Member -NotePropertyName lastFixPackageId -NotePropertyValue $null -Force
    }
    if ($null -eq (Get-MetraProp -Object $State -Name 'lastRecordedFixRound' -Default $null)) {
        $State | Add-Member -NotePropertyName lastRecordedFixRound -NotePropertyValue 0 -Force
    }
    return $migrated
}

function New-MetraInspectReviewLoopStateObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][int]$MaxLoops,
        [bool]$RunUntilGoal = $false
    )

    $state = [PSCustomObject]@{
        schemaVersion         = 2
        project               = $Project
        root                  = $Root
        inspectMode           = 'diff'
        maxLoops              = $MaxLoops
        startedAtUtc          = [datetime]::UtcNow.ToString('o')
        updatedAtUtc          = [datetime]::UtcNow.ToString('o')
        active                = $true
        phase                 = $null
        runUntilGoal          = [bool]$RunUntilGoal
        pendingBaseline       = $null
        lastVerifyCounts      = $null
        completedCycles       = 0
        rounds                = @()
        LoopsUsed             = 0
        FinalGrade            = $null
        CriticalCount         = 0
        HighCount             = 0
        MediumCount           = 0
        LowCount              = 0
        TerminationReason     = $null
        dispatchFixCount      = 0
        inlineFixCount        = 0
        fixDispatchInFlight   = $false
        lastFixPackageId      = $null
        lastRecordedFixRound  = 0
    }
    return $state
}

function Get-MetraInspectReviewFindingId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$RoundNum,
        [Parameter(Mandatory)][int]$Index1Based
    )
    return ('R{0}-F{1:D3}' -f $RoundNum, $Index1Based)
}

function Test-MetraInspectReviewDispatchEligibleBySeverity {
    [CmdletBinding()]
    param([string]$Severity)
    $s = [string]$Severity
    return ($s -eq 'Critical' -or $s -eq 'High')
}

function Test-MetraInspectReviewDispatchRecommended {
    <#
    .SYNOPSIS
        Package-level materiality: Critical/High, multi-file, or missing file path.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$SelectedFindings)

    $list = @($SelectedFindings)
    if ($list.Count -eq 0) { return $false }

    $severities = @($list | ForEach-Object { [string](Get-MetraProp -Object $_ -Name 'severity' -Default '') })
    if ($severities -contains 'Critical' -or $severities -contains 'High') { return $true }

    $files = @($list | ForEach-Object { [string](Get-MetraProp -Object $_ -Name 'file' -Default '') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($files.Count -gt 1) { return $true }

    $missingFile = @($list | Where-Object { [string]::IsNullOrWhiteSpace([string](Get-MetraProp -Object $_ -Name 'file' -Default '')) }).Count -gt 0
    return [bool]$missingFile
}

function Get-MetraInspectReviewDispatchReason {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$SelectedFindings)

    $list = @($SelectedFindings)
    $reasons = [System.Collections.Generic.List[string]]::new()
    $severities = @($list | ForEach-Object { [string](Get-MetraProp -Object $_ -Name 'severity' -Default '') })
    if ($severities -contains 'Critical' -or $severities -contains 'High') {
        [void]$reasons.Add('contains-critical-or-high')
    }
    $files = @($list | ForEach-Object { [string](Get-MetraProp -Object $_ -Name 'file' -Default '') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($files.Count -gt 1) {
        [void]$reasons.Add('touches-multiple-files')
    }
    $missingFile = @($list | Where-Object { [string]::IsNullOrWhiteSpace([string](Get-MetraProp -Object $_ -Name 'file' -Default '')) }).Count -gt 0
    if ($missingFile) {
        [void]$reasons.Add('missing-file-path')
    }
    if ($reasons.Count -eq 0) { return 'inline-trivial' }
    return ($reasons -join ',')
}

function Read-MetraInspectReviewFixQueue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SlotKey)

    $path = Get-MetraInspectReviewFixQueuePath -SlotKey $SlotKey
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Fix queue not found ($path). Run inspect loop assess first."
    }
    try {
        return Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Could not read fix queue ($path): $($_.Exception.Message)"
    }
}

function Get-MetraInspectReviewFixPackagePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SlotKey,
        [Parameter(Mandatory)][string]$PackageId
    )

    $pkgDir = Get-MetraInspectReviewFixPackageDir -SlotKey $SlotKey
    return Join-Path $pkgDir ("{0}.json" -f $PackageId.Trim())
}

function Read-MetraInspectReviewFixPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SlotKey,
        [Parameter(Mandatory)][string]$PackageId
    )

    $path = Get-MetraInspectReviewFixPackagePath -SlotKey $SlotKey -PackageId $PackageId
    if (-not (Test-Path -LiteralPath $path)) {
        throw ("inspect loop record-fix: fix package not found ({0})." -f $path)
    }
    try {
        return Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw ("Could not read fix package ({0}): {1}" -f $path, $_.Exception.Message)
    }
}

function Assert-MetraInspectReviewFixQueueHashMatchesPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SlotKey,
        [Parameter(Mandatory)]$Package
    )

    $expected = [string](Get-MetraProp -Object $Package -Name 'sourceQueueHash' -Default '').Trim()
    if ([string]::IsNullOrWhiteSpace($expected)) {
        return
    }
    $queue = Read-MetraInspectReviewFixQueue -SlotKey $SlotKey
    $actual = Get-MetraInspectReviewFixQueueContentHash -Queue $queue
    if ($actual -ne $expected) {
        throw ("inspect loop record-fix: fix queue changed since package was created (sourceQueueHash mismatch). Re-run inspect loop package before record-fix.")
    }
}

function Save-MetraInspectReviewFixQueue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SlotKey,
        [Parameter(Mandatory)]$Queue
    )

    $path = Get-MetraInspectReviewFixQueuePath -SlotKey $SlotKey
    if (-not $PSCmdlet.ShouldProcess($path, 'Persist inspect fix queue')) {
        return [PSCustomObject]@{ Path = $path; Skipped = $true }
    }
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Write-MetraAtomicUtf8Text -Path $path -Text ($Queue | ConvertTo-Json -Depth 10)
    return [PSCustomObject]@{ Path = $path; Skipped = $false }
}

function Get-MetraInspectReviewFixQueueContentHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Queue)

    $payload = [ordered]@{
        round    = [int](Get-MetraProp -Object $Queue -Name 'round' -Default 0)
        findings = @(@(Get-MetraProp -Object $Queue -Name 'findings' -Default @()) | ForEach-Object {
                [ordered]@{
                    id       = [string](Get-MetraProp -Object $_ -Name 'id' -Default '')
                    severity = [string](Get-MetraProp -Object $_ -Name 'severity' -Default '')
                    file     = [string](Get-MetraProp -Object $_ -Name 'file' -Default '')
                    finding  = [string](Get-MetraProp -Object $_ -Name 'finding' -Default '')
                    status   = [string](Get-MetraProp -Object $_ -Name 'status' -Default 'Pending')
                }
            })
    }
    $json = $payload | ConvertTo-Json -Compress -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertFrom-MetraInspectReviewIdList {
    [CmdletBinding()]
    param([string[]]$Raw)

    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($token in @($Raw)) {
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        foreach ($part in ($token -split '[,;\s]+')) {
            $t = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($t)) {
                [void]$ids.Add($t)
            }
        }
    }
    return @($ids | Select-Object -Unique)
}

function Resolve-MetraInspectReviewLoopSlotContext {
    [CmdletBinding()]
    param([string]$Name)

    $ctx = Resolve-MetraInspectProjectContext -Name $Name -Mode diff
    if (-not $ctx.Ok) { throw $ctx.Error }
    $slotKey = [string]$ctx.Project
    if ([string]::IsNullOrWhiteSpace($slotKey)) { $slotKey = 'default' }
    $state = Get-MetraInspectReviewLoopState -SlotKey $slotKey
    if ($null -eq $state) {
        throw 'No active inspect review loop session. Run inspect loop -Reset first.'
    }
    Assert-MetraInspectReviewLoopRootMatch -PersistedRoot ([string]$state.root) -CurrentRoot ([string]$ctx.Root)
    $null = Initialize-MetraInspectReviewLoopStateV2Fields -State $state
    if ($state.active -eq $false) {
        throw 'Inspect review loop session is complete. Use inspect loop -Reset to start a new session.'
    }
    return [PSCustomObject]@{
        Ctx     = $ctx
        SlotKey = $slotKey
        State   = $state
    }
}

function Invoke-MetraInspectReviewLoopDecide {
    <#
    .SYNOPSIS
        Persist Affirm / Defer / Reject on the current-round fix queue.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name,
        [string[]]$Affirm,
        [string[]]$Defer,
        [string[]]$Reject
    )

    $affirmIds = @(ConvertFrom-MetraInspectReviewIdList -Raw $Affirm)
    $deferIds = @(ConvertFrom-MetraInspectReviewIdList -Raw $Defer)
    $rejectIds = @(ConvertFrom-MetraInspectReviewIdList -Raw $Reject)
    if ($affirmIds.Count -eq 0 -and $deferIds.Count -eq 0 -and $rejectIds.Count -eq 0) {
        throw 'inspect loop decide requires at least one of -Affirm, -Defer, or -Reject.'
    }

    $all = @($affirmIds + $deferIds + $rejectIds)
    $dupes = @($all | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($dupes.Count -gt 0) {
        throw ("inspect loop decide: overlapping finding IDs across lists: {0}" -f ($dupes -join ', '))
    }

    $slot = Resolve-MetraInspectReviewLoopSlotContext -Name $Name
    $state = $slot.State
    $slotKey = $slot.SlotKey
    $currentRound = [int](Get-MetraProp -Object $state -Name 'LoopsUsed' -Default 0)
    if ($currentRound -lt 1) {
        throw 'inspect loop decide: no current round. Run an assess pass first.'
    }

    $queue = Read-MetraInspectReviewFixQueue -SlotKey $slotKey
    $queueRound = [int](Get-MetraProp -Object $queue -Name 'round' -Default 0)
    if ($queueRound -ne $currentRound) {
        throw ("inspect loop decide: fix-queue round {0} does not match session round {1}. Re-run inspect loop assess." -f $queueRound, $currentRound)
    }

    $byId = @{}
    foreach ($f in @($queue.findings)) {
        $id = [string](Get-MetraProp -Object $f -Name 'id' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $byId[$id] = $f
        }
    }

    foreach ($id in $all) {
        if (-not $byId.ContainsKey($id)) {
            throw ("inspect loop decide: unknown finding id '{0}' for round {1}." -f $id, $currentRound)
        }
        if ($id -notmatch ('^R{0}-F\d{{3}}$' -f $currentRound)) {
            throw ("inspect loop decide: finding id '{0}' is not for current round R{1}." -f $id, $currentRound)
        }
    }

    if (-not $PSCmdlet.ShouldProcess("round $currentRound", 'Apply inspect loop decide statuses')) {
        return [PSCustomObject]@{ WhatIf = $true; Round = $currentRound }
    }

    foreach ($id in $affirmIds) {
        $byId[$id] | Add-Member -NotePropertyName status -NotePropertyValue 'Affirmed' -Force
    }
    foreach ($id in $deferIds) {
        $byId[$id] | Add-Member -NotePropertyName status -NotePropertyValue 'Deferred' -Force
    }
    foreach ($id in $rejectIds) {
        $byId[$id] | Add-Member -NotePropertyName status -NotePropertyValue 'Rejected' -Force
    }

    $queue | Add-Member -NotePropertyName decidedAtUtc -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
    $null = Save-MetraInspectReviewFixQueue -SlotKey $slotKey -Queue $queue -Confirm:$false

    # Mirror decisions onto the current round in session state (mandatory audit).
    # Aggregate across multiple decide calls in the same round.
    $rounds = @($state.rounds)
    if ($rounds.Count -gt 0) {
        $last = $rounds[$rounds.Count - 1]
        $prev = Get-MetraProp -Object $last -Name 'decisions' -Default $null
        $mergedAffirm = [System.Collections.Generic.List[string]]::new()
        $mergedDefer = [System.Collections.Generic.List[string]]::new()
        $mergedReject = [System.Collections.Generic.List[string]]::new()
        foreach ($id in @((Get-MetraProp -Object $prev -Name 'affirmed' -Default @()))) {
            if (-not [string]::IsNullOrWhiteSpace([string]$id)) { [void]$mergedAffirm.Add([string]$id) }
        }
        foreach ($id in @((Get-MetraProp -Object $prev -Name 'deferred' -Default @()))) {
            if (-not [string]::IsNullOrWhiteSpace([string]$id)) { [void]$mergedDefer.Add([string]$id) }
        }
        foreach ($id in @((Get-MetraProp -Object $prev -Name 'rejected' -Default @()))) {
            if (-not [string]::IsNullOrWhiteSpace([string]$id)) { [void]$mergedReject.Add([string]$id) }
        }
        foreach ($id in $affirmIds) {
            [void]$mergedDefer.Remove($id); [void]$mergedReject.Remove($id)
            if (-not $mergedAffirm.Contains($id)) { [void]$mergedAffirm.Add($id) }
        }
        foreach ($id in $deferIds) {
            [void]$mergedAffirm.Remove($id); [void]$mergedReject.Remove($id)
            if (-not $mergedDefer.Contains($id)) { [void]$mergedDefer.Add($id) }
        }
        foreach ($id in $rejectIds) {
            [void]$mergedAffirm.Remove($id); [void]$mergedDefer.Remove($id)
            if (-not $mergedReject.Contains($id)) { [void]$mergedReject.Add($id) }
        }
        $last | Add-Member -NotePropertyName decisions -NotePropertyValue ([PSCustomObject]@{
                affirmed = @($mergedAffirm)
                deferred = @($mergedDefer)
                rejected = @($mergedReject)
                atUtc    = [datetime]::UtcNow.ToString('o')
            }) -Force
        $state.rounds = $rounds
    }
    $state.updatedAtUtc = [datetime]::UtcNow.ToString('o')
    $null = Save-MetraInspectReviewLoopState -SlotKey $slotKey -State $state -Confirm:$false

    Write-Host ("decide: Affirmed={0} Deferred={1} Rejected={2} (round {3})" -f $affirmIds.Count, $deferIds.Count, $rejectIds.Count, $currentRound)
    return [PSCustomObject]@{
        Round    = $currentRound
        Affirmed = $affirmIds
        Deferred = $deferIds
        Rejected = $rejectIds
        QueuePath = (Get-MetraInspectReviewFixQueuePath -SlotKey $slotKey)
    }
}

function Test-MetraInspectPathWithinProjectRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativeOrAbsolute
    )

    $rel = [string]$RelativeOrAbsolute
    if ([string]::IsNullOrWhiteSpace($rel)) { return $false }
    if ($rel.Contains('..')) { return $false }
    if (Get-Command Test-MetraPathWithinRoot -ErrorAction SilentlyContinue) {
        try {
            $fullRoot = [System.IO.Path]::GetFullPath($Root)
            $candidate = if ([System.IO.Path]::IsPathRooted($rel)) {
                [System.IO.Path]::GetFullPath($rel)
            }
            else {
                [System.IO.Path]::GetFullPath((Join-Path $fullRoot ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
            }
            return [bool](Test-MetraPathWithinRoot -Path $candidate -Root $fullRoot)
        }
        catch {
            return $false
        }
    }
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $rootPrefix = $fullRoot + $sep
    $candidate = if ([System.IO.Path]::IsPathRooted($rel)) {
        [System.IO.Path]::GetFullPath($rel)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $fullRoot ($rel -replace '/', $sep)))
    }
    if ([string]::Equals($candidate, $fullRoot, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-MetraInspectReviewLoopPackage {
    <#
    .SYNOPSIS
        Build a bounded fix package from Affirmed finding IDs for inline or Task dispatch.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name,
        [Parameter(Mandatory)][string[]]$FindingId,
        [switch]$PassThru
    )

    $ids = @(ConvertFrom-MetraInspectReviewIdList -Raw $FindingId)
    if ($ids.Count -eq 0) {
        throw 'inspect loop package requires -FindingId.'
    }

    $slot = Resolve-MetraInspectReviewLoopSlotContext -Name $Name
    $state = $slot.State
    $slotKey = $slot.SlotKey
    $ctx = $slot.Ctx
    $currentRound = [int](Get-MetraProp -Object $state -Name 'LoopsUsed' -Default 0)
    if ($currentRound -lt 1) {
        throw 'inspect loop package: no current round.'
    }

    if ([bool](Get-MetraProp -Object $state -Name 'fixDispatchInFlight' -Default $false)) {
        throw 'inspect loop package: a fix Task is already in flight (fixDispatchInFlight). Call record-fix (or inspect loop -Reset) before packaging another dispatch.'
    }

    $queue = Read-MetraInspectReviewFixQueue -SlotKey $slotKey
    $queueRound = [int](Get-MetraProp -Object $queue -Name 'round' -Default 0)
    if ($queueRound -ne $currentRound) {
        throw ("inspect loop package: fix-queue round {0} does not match session round {1}." -f $queueRound, $currentRound)
    }

    $byId = @{}
    foreach ($f in @($queue.findings)) {
        $id = [string](Get-MetraProp -Object $f -Name 'id' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($id)) { $byId[$id] = $f }
    }

    $selected = @()
    foreach ($id in $ids) {
        if (-not $byId.ContainsKey($id)) {
            throw ("inspect loop package: unknown finding id '{0}'." -f $id)
        }
        if ($id -notmatch ('^R{0}-F\d{{3}}$' -f $currentRound)) {
            throw ("inspect loop package: finding id '{0}' is not for current round R{1}." -f $id, $currentRound)
        }
        $status = [string](Get-MetraProp -Object $byId[$id] -Name 'status' -Default 'Pending')
        if ($status -ne 'Affirmed') {
            throw ("inspect loop package: finding '{0}' status is {1}; only Affirmed IDs may be packaged." -f $id, $status)
        }
        $selected += $byId[$id]
    }

    $dispatchRecommended = Test-MetraInspectReviewDispatchRecommended -SelectedFindings $selected
    $reason = Get-MetraInspectReviewDispatchReason -SelectedFindings $selected

    $targetFiles = [System.Collections.Generic.List[string]]::new()
    $rejectedPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $selected) {
        $file = [string](Get-MetraProp -Object $f -Name 'file' -Default '').Trim()
        if ([string]::IsNullOrWhiteSpace($file)) { continue }
        $norm = ($file -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar).Trim()
        if (-not (Test-MetraInspectPathWithinProjectRoot -Root ([string]$ctx.Root) -RelativeOrAbsolute $norm)) {
            [void]$rejectedPaths.Add($file)
            continue
        }
        $exists = $false
        foreach ($existing in $targetFiles) {
            if ([string]::Equals($existing, $norm, [StringComparison]::OrdinalIgnoreCase)) {
                $exists = $true
                break
            }
        }
        if (-not $exists) {
            [void]$targetFiles.Add($norm)
        }
    }
    if ($rejectedPaths.Count -gt 0) {
        throw ("inspect loop package: path outside project root or unsafe: {0}" -f ($rejectedPaths -join ', '))
    }

    $agentsText = Get-MetraInspectAgentsText -Root ([string]$ctx.Root)
    $treeHash = Get-MetraInspectReviewWorkingTreeInputHash -Root ([string]$ctx.Root) -Base $null
    $sourceQueueHash = Get-MetraInspectReviewFixQueueContentHash -Queue $queue
    $packageId = ('pkg-r{0}-{1}' -f $currentRound, [guid]::NewGuid().ToString('N').Substring(0, 8))
    $pkgDir = Get-MetraInspectReviewFixPackageDir -SlotKey $slotKey
    $packagePath = Join-Path $pkgDir ("{0}.json" -f $packageId)

    # Missing-file findings stay in the package for residual-risk context; Task mutates targetFiles only.
    $parentTriageRequired = @($selected | Where-Object {
            [string]::IsNullOrWhiteSpace([string](Get-MetraProp -Object $_ -Name 'file' -Default ''))
        }).Count -gt 0

    $package = [ordered]@{
        schemaVersion         = 1
        packageId             = $packageId
        createdAtUtc          = [datetime]::UtcNow.ToString('o')
        sessionId             = [string](Get-MetraProp -Object $state -Name 'startedAtUtc' -Default '')
        project               = [string]$ctx.Project
        root                  = [string]$ctx.Root
        round                 = $currentRound
        findingIds            = @($ids)
        findings              = @($selected)
        targetFiles           = @($targetFiles)
        contextFiles          = @()
        truncatedFiles        = @()
        agentsText            = [string]$agentsText
        sourceQueueHash       = $sourceQueueHash
        workingTreeFingerprint = $treeHash
        dispatchRecommended   = [bool]$dispatchRecommended
        reason                = $reason
        parentTriageRequired  = [bool]$parentTriageRequired
    }

    if (-not $PSCmdlet.ShouldProcess($packagePath, 'Write inspect fix package')) {
        $result = [PSCustomObject]@{
            WhatIf               = $true
            packagePath          = $packagePath
            findingCount         = $selected.Count
            dispatchRecommended  = [bool]$dispatchRecommended
            reason               = $reason
        }
        if ($PassThru) { return $result }
        Write-Host ("WhatIf: would write fix package ({0} findings, dispatchRecommended={1})" -f $selected.Count, $dispatchRecommended)
        return
    }

    if (-not (Test-Path -LiteralPath $pkgDir)) {
        New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null
    }
    Write-MetraAtomicUtf8Text -Path $packagePath -Text ($package | ConvertTo-Json -Depth 12)

    # Always record package id so record-fix -PackageId / lastFixPackageId match for Inline and Dispatch.
    $state | Add-Member -NotePropertyName lastFixPackageId -NotePropertyValue $packageId -Force
    if ($dispatchRecommended) {
        $state | Add-Member -NotePropertyName fixDispatchInFlight -NotePropertyValue $true -Force
    }
    $state.updatedAtUtc = [datetime]::UtcNow.ToString('o')
    $null = Save-MetraInspectReviewLoopState -SlotKey $slotKey -State $state -Confirm:$false

    $result = [PSCustomObject]@{
        packagePath          = $packagePath
        packageId            = $packageId
        findingCount         = $selected.Count
        dispatchRecommended  = [bool]$dispatchRecommended
        reason               = $reason
        targetFiles          = @($targetFiles)
        parentTriageRequired = [bool]$parentTriageRequired
    }
    Write-Host ("package: {0} findings={1} dispatchRecommended={2} reason={3}" -f $packagePath, $selected.Count, $dispatchRecommended, $reason)
    if ($parentTriageRequired) {
        Write-Host 'Note: one or more findings lack file paths - parent triage required; Task may only mutate targetFiles.' -ForegroundColor Yellow
    }
    if ($PassThru) { return $result }
    return
}

function Invoke-MetraInspectReviewLoopRecordFix {
    <#
    .SYNOPSIS
        Record Dispatch vs Inline fix execution; clear single-dispatch lock.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name,
        [Parameter(Mandatory)]
        [ValidateSet('Dispatch', 'Inline', 'Abandoned')]
        [string]$Mode,
        [string]$Summary,
        [string]$PackageId
    )

    $slot = Resolve-MetraInspectReviewLoopSlotContext -Name $Name
    $state = $slot.State
    $slotKey = $slot.SlotKey
    $currentRound = [int](Get-MetraProp -Object $state -Name 'LoopsUsed' -Default 0)
    if ($currentRound -lt 1) {
        throw 'inspect loop record-fix: no current round.'
    }
    if ([string]$state.phase -ne 'AwaitingFix') {
        throw ("inspect loop record-fix: session phase is '{0}'; expected AwaitingFix." -f [string]$state.phase)
    }

    $lastRecorded = [int](Get-MetraProp -Object $state -Name 'lastRecordedFixRound' -Default 0)
    if ($Mode -ne 'Abandoned' -and $lastRecorded -eq $currentRound) {
        throw ("inspect loop record-fix: round {0} already recorded. Duplicate record-fix is not allowed." -f $currentRound)
    }

    $lastPkg = [string](Get-MetraProp -Object $state -Name 'lastFixPackageId' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($PackageId)) {
        if (-not [string]::IsNullOrWhiteSpace($lastPkg) -and $PackageId -ne $lastPkg) {
            throw ("inspect loop record-fix: PackageId '{0}' does not match session lastFixPackageId '{1}'." -f $PackageId, $lastPkg)
        }
        $pkgId = $PackageId
    }
    else {
        $pkgId = $lastPkg
    }

    if ($Mode -ne 'Abandoned' -and -not [string]::IsNullOrWhiteSpace($pkgId)) {
        $pkg = Read-MetraInspectReviewFixPackage -SlotKey $slotKey -PackageId $pkgId
        Assert-MetraInspectReviewFixQueueHashMatchesPackage -SlotKey $slotKey -Package $pkg
    }

    if (-not $PSCmdlet.ShouldProcess("round $currentRound", "Record inspect fix mode $Mode")) {
        return [PSCustomObject]@{ WhatIf = $true; Round = $currentRound; Mode = $Mode }
    }

    $null = Initialize-MetraInspectReviewLoopStateV2Fields -State $state

    if ($Mode -eq 'Dispatch') {
        $state.dispatchFixCount = [int](Get-MetraProp -Object $state -Name 'dispatchFixCount' -Default 0) + 1
        $state.lastRecordedFixRound = $currentRound
    }
    elseif ($Mode -eq 'Inline') {
        $state.inlineFixCount = [int](Get-MetraProp -Object $state -Name 'inlineFixCount' -Default 0) + 1
        $state.lastRecordedFixRound = $currentRound
    }
    # Abandoned: clear lock only; do not increment counters or mark round recorded

    $state | Add-Member -NotePropertyName fixDispatchInFlight -NotePropertyValue $false -Force

    $rounds = @($state.rounds)
    if ($rounds.Count -gt 0 -and $Mode -ne 'Abandoned') {
        $last = $rounds[$rounds.Count - 1]
        $last | Add-Member -NotePropertyName fixMode -NotePropertyValue $Mode -Force
        $last | Add-Member -NotePropertyName fixSummary -NotePropertyValue ([string]$Summary) -Force
        $last | Add-Member -NotePropertyName fixPackageId -NotePropertyValue $pkgId -Force
        $last | Add-Member -NotePropertyName recordedUtc -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
        $state.rounds = $rounds
    }

    $state.updatedAtUtc = [datetime]::UtcNow.ToString('o')
    $null = Save-MetraInspectReviewLoopState -SlotKey $slotKey -State $state -Confirm:$false

    Write-Host ("record-fix: mode={0} round={1} dispatchCount={2} inlineCount={3} inFlight=false" -f `
            $Mode, $currentRound, $state.dispatchFixCount, $state.inlineFixCount)
    return [PSCustomObject]@{
        Round            = $currentRound
        Mode             = $Mode
        Summary          = [string]$Summary
        PackageId        = $pkgId
        dispatchFixCount = [int]$state.dispatchFixCount
        inlineFixCount   = [int]$state.inlineFixCount
        fixDispatchInFlight = $false
    }
}
