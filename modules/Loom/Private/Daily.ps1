# Slice 5 — daily gate (intake, pack-diff, approve, per-project acceptance gate).

$script:LoomDailyApproveActive = $false

function Get-LoomListArray {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.Generic.List[object]]) { return $Value.ToArray() }
    if ($Value -is [System.Collections.Generic.List[string]]) { return $Value.ToArray() }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { return @($Value) }
    return @($Value)
}

function Get-LoomContractArray {
    param([AllowNull()][object]$Value)
    return [object[]](Get-LoomListArray $Value)
}

function Get-LoomOperatorName {
    if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) { return $env:USERNAME }
    if (-not [string]::IsNullOrWhiteSpace($env:USER)) { return $env:USER }
    return 'operator'
}

function Get-LoomDailyReviewDate {
    [CmdletBinding()]
    param(
        [datetime]$Date = (Get-Date)
    )
    return $Date.ToString('yyyy-MM-dd')
}

function Get-LoomProjectKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryName,
        [hashtable]$KeyRegistryMap
    )

    if ([string]::IsNullOrWhiteSpace($RegistryName)) {
        throw 'RegistryName is required for project key normalization.'
    }
    if ($RegistryName -match '[\\/]' -or $RegistryName -match '^\.' -or $RegistryName -match '\.\.') {
        throw "Invalid registry name for project key: $RegistryName"
    }

    $key = ($RegistryName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($key)) {
        throw "Registry name normalizes to empty project key: $RegistryName"
    }

    if ($KeyRegistryMap) {
        $lookupKey = $RegistryName.ToLowerInvariant()
        if ($KeyRegistryMap.ContainsKey($lookupKey)) {
            return [string]$KeyRegistryMap[$lookupKey]
        }
        foreach ($existingKey in $KeyRegistryMap.Keys) {
            if ([string]$KeyRegistryMap[$existingKey] -eq $key) {
                throw "Project key collision: '$key' (registry '$RegistryName')"
            }
        }
        $KeyRegistryMap[$lookupKey] = $key
    }
    return $key
}

function Get-LoomCompletionCycleId {
    param(
        [Parameter(Mandatory)][string]$ItemId,
        [Parameter(Mandatory)][string]$CompletedCommit
    )
    return "$ItemId`:$CompletedCommit"
}

function Get-LoomItemBaselineCommit {
    param([Parameter(Mandatory)]$Item)
    $sha = [string](Get-LoomProp -Object $Item.execution -Name 'baselineSha' -Default '')
    if ([string]::IsNullOrWhiteSpace($sha)) {
        $sha = [string](Get-LoomProp -Object $Item.execution -Name 'baselineCommit' -Default '')
    }
    return $sha
}

function Get-LoomItemVerifyOutcome {
    param(
        [Parameter(Mandatory)]$Item,
        [string]$Root
    )
    $runDir = [string](Get-LoomProp -Object $Item.execution -Name 'runDir' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($runDir)) {
        $state = Get-LoomReviewState -RunDir $runDir
        if ($state) {
            $vo = [string](Get-LoomProp -Object $state -Name 'verifyOutcome' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($vo)) { return $vo }
        }
    }
    return 'unknown'
}

function Test-LoomProjectAcceptanceGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RegistryName,
        [string]$ExcludeItemId
    )

    foreach ($item in @(Get-MetraLoomQueueItems -Root $Root)) {
        if ([string]$item.status -ne 'completed') { continue }
        $reg = [string](Get-LoomProp -Object $item.project -Name 'registryName' -Default '')
        if ($reg -ne $RegistryName) { continue }
        if ($ExcludeItemId -and [string]$item.id -eq $ExcludeItemId) { continue }
        return [PSCustomObject]@{
            blocked         = $true
            blockingItemId  = [string]$item.id
            reason          = 'pending-acceptance'
            message         = "pending-acceptance:$($item.id)"
        }
    }
    return [PSCustomObject]@{
        blocked        = $false
        blockingItemId = $null
        reason         = $null
        message        = $null
    }
}

function Assert-LoomProjectAcceptanceGate {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RegistryName,
        [string]$ExcludeItemId
    )
    $gate = Test-LoomProjectAcceptanceGate -Root $Root -RegistryName $RegistryName -ExcludeItemId $ExcludeItemId
    if ($gate.blocked) {
        throw $gate.message
    }
}

function Get-LoomJournalCompletionTransitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ReviewDate
    )

    $day = [datetime]::ParseExact($ReviewDate, 'yyyy-MM-dd', $null)
    $entries = @(Get-MetraLoomJournalEntries -Root $Root -On $day)
    $byItem = @{}
    foreach ($e in $entries) {
        if ([string](Get-LoomProp -Object $e -Name 'to' -Default '') -ne 'completed') { continue }
        $itemId = [string](Get-LoomProp -Object $e -Name 'itemId' -Default '')
        if ([string]::IsNullOrWhiteSpace($itemId)) { continue }
        $ts = [string](Get-LoomProp -Object $e -Name 'timestamp' -Default '')
        if (-not $byItem.ContainsKey($itemId) -or $ts -gt [string]$byItem[$itemId].timestamp) {
            $byItem[$itemId] = $e
        }
    }
    return @($byItem.Values)
}

function Get-LoomCompletedItemsForReviewDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ReviewDate
    )

    $transitions = @(Get-LoomJournalCompletionTransitions -Root $Root -ReviewDate $ReviewDate)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($t in $transitions) {
        $itemId = [string](Get-LoomProp -Object $t -Name 'itemId' -Default '')
        $item = Get-MetraLoomQueueItem -Root $Root -Id $itemId
        if (-not $item) { continue }
        if ([string]$item.status -ne 'completed' -and [string]$item.status -ne 'accepted') { continue }
        $items.Add([PSCustomObject]@{
            item                   = $item
            completionTransitionAt = [string](Get-LoomProp -Object $t -Name 'timestamp' -Default '')
        })
    }
    return @($items | Sort-Object { [string]$_.item.id })
}

function Read-LoomDailyPlanDirectives {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Daily plan not found: $Path"
    }
    $text = [System.IO.File]::ReadAllText($Path, (Get-LoomUtf8NoBomEncoding))
    $lines = $text -split "`r?`n"
    $pattern = '^- \[(x|X)\] (ACCEPT|MANUAL-TEST-DONE|RETRY|BLOCK) (AP-\d{8}-\d{4})$'
    $directives = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $trim = $line.TrimEnd()
        if ($trim -match '^- \[( |x|X)\]') {
            if ($trim -notmatch $pattern) {
                if ($trim -match '^- \[(x|X)\]') {
                    [void]$errors.Add("Invalid directive line: $trim")
                }
                continue
            }
            $verb = $Matches[2].ToUpperInvariant()
            $itemId = $Matches[3]
            if (-not (Test-MetraLoomItemId -Id $itemId -Kind queue)) {
                [void]$errors.Add("Invalid queue id in directive: $itemId")
                continue
            }
            $directives.Add([PSCustomObject]@{
                verb   = $verb
                itemId = $itemId
                line   = $trim
            })
        }
    }

    if ($errors.Count -gt 0) {
        throw ("Daily plan parse failed: {0}" -f ($errors -join '; '))
    }

    $byItem = @{}
    foreach ($d in $directives) {
        $id = [string]$d.itemId
        if (-not $byItem.ContainsKey($id)) {
            $byItem[$id] = @{
                ACCEPT             = $false
                ManualTestDone     = $false
                RETRY              = $false
                BLOCK              = $false
            }
        }
        $verb = [string]$d.verb
        $flagKey = switch ($verb) {
            'MANUAL-TEST-DONE' { 'ManualTestDone' }
            default            { $verb }
        }
        if ($byItem[$id][$flagKey]) {
            throw "Duplicate directive for $id : $verb"
        }
        $byItem[$id][$flagKey] = $true
    }

    foreach ($id in $byItem.Keys) {
        $flags = $byItem[$id]
        $terminals = @()
        if ($flags['ACCEPT']) { $terminals += 'ACCEPT' }
        if ($flags['RETRY']) { $terminals += 'RETRY' }
        if ($flags['BLOCK']) { $terminals += 'BLOCK' }
        if (@($terminals).Count -gt 1) {
            throw "Conflicting terminal directives for ${id}: $($terminals -join ', ')"
        }
        if ($flags['ManualTestDone'] -and -not $flags['ACCEPT']) {
            throw "MANUAL-TEST-DONE without ACCEPT for $id"
        }
    }

    return @($directives.ToArray())
}

function Get-LoomAcceptanceRecordPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId
    )
    if (-not (Test-MetraLoomItemId -Id $ItemId -Kind queue)) {
        throw "Invalid queue item id for acceptance record: $ItemId"
    }
    $path = Join-Path (Join-Path $Root 'daily/acceptance') ("$ItemId.json")
    if (-not (Test-LoomPathWithinRoot -Path $path -Root $Root)) {
        throw "Acceptance record path escapes loom root: $ItemId"
    }
    return $path
}

function Get-LoomAcceptanceRecord {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId
    )
    $path = Get-LoomAcceptanceRecordPath -Root $Root -ItemId $ItemId
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Write-LoomAcceptanceRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Record
    )

    Test-LoomContract -Schema 'acceptance-record' -Object $Record | Out-Null
    $itemId = [string]$Record.itemId
    $dir = Join-Path $Root 'daily/acceptance'
    if (-not (Test-Path -LiteralPath $dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $final = Get-LoomAcceptanceRecordPath -Root $Root -ItemId $itemId
    $json = ($Record | ConvertTo-Json -Depth 12) + "`n"
    Write-LoomAtomicUtf8Text -Path $final -Text $json
    return $final
}

function Test-LoomAcceptanceRecordMatches {
    param(
        $Existing,
        $Proposed
    )
    $fields = @('completionCycleId', 'completedCommit', 'baselineCommit', 'packDiffPath', 'branch')
    foreach ($f in $fields) {
        $a = [string](Get-LoomProp -Object $Existing -Name $f -Default '')
        $b = [string](Get-LoomProp -Object $Proposed -Name $f -Default '')
        if ($a -ne $b) { return $false }
    }
    return $true
}

function Get-LoomPackDiffManifestPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ReviewDate
    )
    return Join-Path (Join-Path $Root "daily/$ReviewDate-pack-diff") 'manifest.json'
}

function Get-LoomPackDiffManifest {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ReviewDate
    )
    $path = Get-LoomPackDiffManifestPath -Root $Root -ReviewDate $ReviewDate
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Find-LoomManifestItemEntry {
    param(
        $Manifest,
        [Parameter(Mandatory)][string]$ItemId,
        [string]$RegistryName
    )

    foreach ($proj in @($Manifest.projects)) {
        if ($RegistryName -and [string]$proj.registryName -ne $RegistryName) { continue }
        foreach ($entry in @($proj.items)) {
            if ([string](Get-LoomProp -Object $entry -Name 'itemId' -Default '') -eq $ItemId) {
                return [PSCustomObject]@{ project = $proj; entry = $entry }
            }
        }
    }
    return $null
}

function Test-LoomGitObjectExists {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Commit
    )
    if ([string]::IsNullOrWhiteSpace($Commit)) { return $false }
    $gitDir = Join-Path $ProjectRoot '.git'
    if (-not (Test-Path -LiteralPath $gitDir)) { return $false }
    try {
        $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('cat-file', '-e', "${Commit}^{commit}")
        return ($r.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}

function Test-LoomManifestEvidenceForAccept {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$ReviewDate
    )

    if ($ReviewDate -notmatch '^\d{4}-\d{2}-\d{2}$') {
        return [PSCustomObject]@{ ok = $false; reason = 'invalid-review-date' }
    }

    $manifest = Get-LoomPackDiffManifest -Root $Root -ReviewDate $ReviewDate
    if (-not $manifest) {
        return [PSCustomObject]@{ ok = $false; reason = 'pack-diff-manifest-missing' }
    }

    $registry = [string](Get-LoomProp -Object $Item.project -Name 'registryName' -Default '')
    $found = Find-LoomManifestItemEntry -Manifest $manifest -ItemId ([string]$Item.id) -RegistryName $registry
    if (-not $found) {
        return [PSCustomObject]@{ ok = $false; reason = 'manifest-item-missing' }
    }

    $entry = $found.entry
    $proj = $found.project
    $projectRoot = [System.IO.Path]::GetFullPath([string]$Item.project.root)
    $registeredRoot = [System.IO.Path]::GetFullPath([string]$proj.projectRoot)
    if ($projectRoot -ne $registeredRoot) {
        return [PSCustomObject]@{ ok = $false; reason = 'project-root-mismatch' }
    }

    $baseline = Get-LoomItemBaselineCommit -Item $Item
    $completed = [string](Get-LoomProp -Object $Item.execution -Name 'completedCommit' -Default '')
    $cycleId = Get-LoomCompletionCycleId -ItemId ([string]$Item.id) -CompletedCommit $completed

    if ([string]$entry.itemId -ne [string]$Item.id) {
        return [PSCustomObject]@{ ok = $false; reason = 'manifest-item-id-mismatch' }
    }
    if ([string]$entry.baselineCommit -ne $baseline) {
        return [PSCustomObject]@{ ok = $false; reason = 'manifest-baseline-mismatch' }
    }
    if ([string]$entry.completedCommit -ne $completed) {
        return [PSCustomObject]@{ ok = $false; reason = 'manifest-completed-commit-mismatch' }
    }
    if ([string]$entry.completionCycleId -ne $cycleId) {
        return [PSCustomObject]@{ ok = $false; reason = 'manifest-cycle-mismatch' }
    }

    $packRel = [string](Get-LoomProp -Object $entry -Name 'packDiffPath' -Default '')
    $packFull = if ([System.IO.Path]::IsPathRooted($packRel)) { $packRel } else { Join-Path $Root $packRel }
    if (-not (Test-LoomPathWithinRoot -Path $packFull -Root $Root)) {
        return [PSCustomObject]@{ ok = $false; reason = 'pack-diff-path-escape' }
    }
    if (-not (Test-Path -LiteralPath $packFull)) {
        return [PSCustomObject]@{ ok = $false; reason = 'pack-diff-artifact-missing' }
    }
    if (-not (Test-LoomGitObjectExists -ProjectRoot $projectRoot -Commit $completed)) {
        return [PSCustomObject]@{ ok = $false; reason = 'completed-commit-not-in-repo' }
    }

    return [PSCustomObject]@{
        ok           = $true
        reason       = $null
        packDiffPath = $packRel
        manifestEntry = $entry
    }
}

function Test-LoomItemNeedsManualTest {
    param([Parameter(Mandatory)]$Item)
    $class = [string](Get-LoomProp -Object $Item.classification -Name 'manualTestClass' -Default 'none')
    return ($class -ne 'none')
}

function Invoke-MetraLoomDailyPackDiff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-LoomHostRoot),
        [string]$ReviewDate,
        [scriptblock]$PackScript
    )

    Initialize-MetraLoomLayout -Root $Root
    if ([string]::IsNullOrWhiteSpace($ReviewDate)) {
        $ReviewDate = Get-LoomDailyReviewDate -Date ((Get-Date).AddDays(-1))
    }
    elseif ($ReviewDate -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw "Invalid ReviewDate format (expected yyyy-MM-dd): $ReviewDate"
    }

    $completedRows = @(Get-LoomCompletedItemsForReviewDate -Root $Root -ReviewDate $ReviewDate)
    $keyRegistryMap = @{}
    $projects = @{}
    $skippedItems = New-Object System.Collections.Generic.List[object]

    foreach ($row in $completedRows) {
        $item = $row.item
        $registry = [string](Get-LoomProp -Object $item.project -Name 'registryName' -Default '')
        $projectRoot = [System.IO.Path]::GetFullPath([string]$item.project.root)
        $completed = [string](Get-LoomProp -Object $item.execution -Name 'completedCommit' -Default '')
        $baseline = Get-LoomItemBaselineCommit -Item $item

        if ([string]::IsNullOrWhiteSpace($completed) -or [string]::IsNullOrWhiteSpace($registry)) {
            [void]$skippedItems.Add([PSCustomObject]@{
                itemId = [string]$item.id; reason = 'missing-evidence'
            })
            continue
        }

        try {
            $projectKey = Get-LoomProjectKey -RegistryName $registry -KeyRegistryMap $keyRegistryMap
        }
        catch {
            [void]$skippedItems.Add([PSCustomObject]@{
                itemId = [string]$item.id; reason = $_.Exception.Message
            })
            continue
        }

        if (-not $projects.ContainsKey($projectKey)) {
            $projects[$projectKey] = [PSCustomObject]@{
                registryName = $registry
                projectKey   = $projectKey
                projectRoot  = $projectRoot
                sections     = New-Object System.Collections.Generic.List[object]
                skipped      = New-Object System.Collections.Generic.List[object]
            }
        }

        $packResult = Invoke-LoomInspectPackAdapter -Name $registry -Base $baseline -ProjectRoot $projectRoot -PackScript $PackScript
        $packDiffRel = "daily/$ReviewDate-pack-diff/$projectKey/pack-diff.md"
        $bingItemRel = "daily/$ReviewDate-bing/$projectKey/$($item.id)/pack-diff.md"
        $bingItemFull = Join-Path $Root $bingItemRel

        $packBody = $null
        $packMessage = [string](Get-LoomProp -Object $packResult -Name 'message' -Default '')
        if ($packResult.packPath -and (Test-Path -LiteralPath $packResult.packPath)) {
            $packBody = [System.IO.File]::ReadAllText($packResult.packPath, (Get-LoomUtf8NoBomEncoding))
            $bingDir = Split-Path -Parent $bingItemFull
            if (-not (Test-Path -LiteralPath $bingDir)) {
                [void][System.IO.Directory]::CreateDirectory($bingDir)
            }
            $srcFull = [System.IO.Path]::GetFullPath([string]$packResult.packPath)
            $dstFull = [System.IO.Path]::GetFullPath($bingItemFull)
            if ($srcFull -ne $dstFull) {
                Copy-Item -LiteralPath $packResult.packPath -Destination $bingItemFull -Force
            }
        }

        [void]$projects[$projectKey].sections.Add([PSCustomObject]@{
            itemId      = [string]$item.id
            header      = "Range: $baseline..$completed`nBranch: $([string]$item.execution.branch)"
            bingRel     = $bingItemRel
            packBody    = $packBody
            packMessage = $packMessage
            entry       = [PSCustomObject]@{
                itemId                 = [string]$item.id
                completionTransitionAt = [string]$row.completionTransitionAt
                baselineCommit         = $baseline
                completedCommit        = $completed
                branch                 = [string](Get-LoomProp -Object $item.execution -Name 'branch' -Default '')
                packDiffPath           = $packDiffRel
                bingPackPath           = $bingItemRel
                verifyOutcome          = (Get-LoomItemVerifyOutcome -Item $item -Root $Root)
                completionCycleId      = (Get-LoomCompletionCycleId -ItemId ([string]$item.id) -CompletedCommit $completed)
            }
        })
    }

    $projectList = @(
        @($projects.Values) |
            Sort-Object { [string]$_.projectKey } |
            ForEach-Object {
                $projectKey = [string]$_.projectKey
                $packDiffRel = "daily/$ReviewDate-pack-diff/$projectKey/pack-diff.md"
                $packDiffFull = Join-Path $Root $packDiffRel
                $packDir = Split-Path -Parent $packDiffFull
                if (-not (Test-Path -LiteralPath $packDir)) {
                    [void][System.IO.Directory]::CreateDirectory($packDir)
                }

                $doc = New-Object System.Text.StringBuilder
                [void]$doc.AppendLine("# Project: $([string]$_.registryName)")
                [void]$doc.AppendLine('')

                $manifestItems = New-Object System.Collections.Generic.List[object]
                foreach ($sec in (@(Get-LoomListArray $_.sections) | Sort-Object { [string]$_.itemId })) {
                    [void]$doc.AppendLine("## $($sec.itemId)")
                    [void]$doc.AppendLine([string]$sec.header)
                    [void]$doc.AppendLine('')
                    if ($sec.packBody) {
                        [void]$doc.AppendLine("Full inspect pack (daily copy): [$($sec.bingRel)]($($sec.bingRel))")
                        [void]$doc.AppendLine('')
                        [void]$doc.AppendLine('---')
                        [void]$doc.AppendLine('')
                        [void]$doc.AppendLine([string]$sec.packBody)
                    }
                    else {
                        [void]$doc.AppendLine("Inspect pack: $($sec.packMessage)")
                    }
                    [void]$doc.AppendLine('')

                    $entry = $sec.entry
                    $entry.packDiffPath = $packDiffRel
                    [void]$manifestItems.Add($entry)
                }

                Write-LoomAtomicUtf8Text -Path $packDiffFull -Text $doc.ToString()

                $projHash = @{
                    registryName = $_.registryName
                    projectKey   = $projectKey
                    projectRoot  = $_.projectRoot
                    items        = @(Get-LoomListArray $manifestItems | Sort-Object { [string]$_.itemId })
                }
                $projSkipped = Get-LoomListArray $_.skipped
                if (@($projSkipped).Count -gt 0) {
                    $projHash['skipped'] = $projSkipped
                }
                [PSCustomObject]$projHash
            }
    )

    $manifestHash = @{
        schemaVersion  = 1
        reviewDate     = [string]$ReviewDate
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        projects       = @($projectList)
    }
    $topSkipped = Get-LoomListArray $skippedItems
    if (@($topSkipped).Count -gt 0) {
        $manifestHash['skippedItems'] = $topSkipped
    }
    Test-LoomContract -Schema 'pack-diff-manifest' -Object $manifestHash | Out-Null
    $manifest = [PSCustomObject]$manifestHash

    $manifestDir = Join-Path $Root "daily/$ReviewDate-pack-diff"
    if (-not (Test-Path -LiteralPath $manifestDir)) {
        [void][System.IO.Directory]::CreateDirectory($manifestDir)
    }
    $manifestPath = Join-Path $manifestDir 'manifest.json'
    Write-LoomAtomicUtf8Text -Path $manifestPath -Text (($manifest | ConvertTo-Json -Depth 12) + "`n")

    $readme = New-Object System.Text.StringBuilder
    [void]$readme.AppendLine("# Pack-diff index ($ReviewDate)")
    [void]$readme.AppendLine('')
    [void]$readme.AppendLine('| Project | Key | Items |')
    [void]$readme.AppendLine('|---------|-----|-------|')
    foreach ($p in $projectList) {
        [void]$readme.AppendLine("| $($p.registryName) | $($p.projectKey) | $($p.items.Count) |")
    }
    if ($skippedItems.Count -gt 0) {
        [void]$readme.AppendLine('')
        [void]$readme.AppendLine('## Skipped items')
        [void]$readme.AppendLine('')
        [void]$readme.AppendLine('| Item | Reason |')
        [void]$readme.AppendLine('|------|--------|')
        foreach ($s in $skippedItems) {
            [void]$readme.AppendLine("| $($s.itemId) | $($s.reason) |")
        }
    }
    Write-LoomAtomicUtf8Text -Path (Join-Path $manifestDir 'README.md') -Text $readme.ToString()

    Add-MetraLoomJournalEntry -Root $Root -Entry @{
        itemId = 'daily'
        from   = 'daily'
        to     = 'daily'
        actor  = 'operator'
        reason = "daily-pack-diff-built:$ReviewDate"
    }

    return [PSCustomObject]@{
        reviewDate   = $ReviewDate
        manifestPath = $manifestPath
        projectCount = $projectList.Count
        skippedCount = $skippedItems.Count
    }
}

function Invoke-MetraLoomDailyBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-LoomHostRoot),
        [string]$ReviewDate,
        [scriptblock]$PackScript
    )

    Initialize-MetraLoomLayout -Root $Root
    $today = Get-LoomDailyReviewDate
    if ([string]::IsNullOrWhiteSpace($ReviewDate)) {
        $ReviewDate = Get-LoomDailyReviewDate -Date ((Get-Date).AddDays(-1))
    }

    $packResult = Invoke-MetraLoomDailyPackDiff -Root $Root -MetraRoot $MetraRoot -ReviewDate $ReviewDate -PackScript $PackScript

    $pending = @(
        Get-MetraLoomFormalPlans -MetraRoot $MetraRoot |
            Where-Object { -not $_.approved }
    )

    $completedItems = @(Get-MetraLoomQueueItems -Root $Root | Where-Object { [string]$_.status -eq 'completed' })
    $manualItems = @($completedItems | Where-Object { Test-LoomItemNeedsManualTest -Item $_ })

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Metra Daily Intake')
    [void]$sb.AppendLine("Date: $today")
    [void]$sb.AppendLine("Review period: $ReviewDate (previous day changes)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 1. Overarching changes made')
    if (@($completedItems).Count -eq 0) {
        [void]$sb.AppendLine('(none)')
    }
    else {
        foreach ($ci in ($completedItems | Sort-Object { [string]$_.id })) {
            $reg = [string](Get-LoomProp -Object $ci.project -Name 'registryName' -Default '')
            [void]$sb.AppendLine("- $($ci.id) ($reg): $($ci.summary)")
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("See: daily/$ReviewDate-pack-diff/README.md")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 2. Manual testing required')
    if (@($manualItems).Count -eq 0) {
        [void]$sb.AppendLine('(none)')
    }
    else {
        foreach ($mi in ($manualItems | Sort-Object { [string]$_.id })) {
            [void]$sb.AppendLine("- [ ] MANUAL-TEST-DONE $($mi.id) # class: $([string]$mi.classification.manualTestClass)")
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 3. Next plan(s) for review')
    if (@($pending).Count -eq 0) {
        [void]$sb.AppendLine('(none pending)')
    }
    else {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| Plan | Path | Status |')
        [void]$sb.AppendLine('|------|------|--------|')
        foreach ($p in ($pending | Sort-Object { [string]$_.name })) {
            [void]$sb.AppendLine("| $($p.name) | $($p.path) | $($p.planStatus) |")
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Archive candidates (knowledge score >= 5)')
    [void]$sb.AppendLine('(none - Slice 8 deferred)')

    $intakePath = Join-Path (Join-Path $Root 'daily') ("$today-intake.md")
    Write-LoomAtomicUtf8Text -Path $intakePath -Text $sb.ToString()

    return [PSCustomObject]@{
        path         = $intakePath
        reviewDate   = $ReviewDate
        packResult   = $packResult
        pendingPlans = @($pending).Count
    }
}

function Get-LoomDailyApprovePlan {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PlanPath,
        [string]$ReviewDate,
        [switch]$OverrideManualTest,
        [string]$OverrideReason,
        [switch]$Merge
    )

    $directives = @(Read-LoomDailyPlanDirectives -Path $PlanPath)
    if ([string]::IsNullOrWhiteSpace($ReviewDate)) {
        $ReviewDate = Get-LoomDailyReviewDate -Date ((Get-Date).AddDays(-1))
    }

    $byItem = @{}
    foreach ($d in $directives) {
        $id = [string]$d.itemId
        if (-not $byItem.ContainsKey($id)) {
            $byItem[$id] = @{
                ACCEPT         = $false
                ManualTestDone = $false
                RETRY          = $false
                BLOCK          = $false
            }
        }
        $verb = [string]$d.verb
        $flagKey = switch ($verb) {
            'MANUAL-TEST-DONE' { 'ManualTestDone' }
            default            { $verb }
        }
        $byItem[$id][$flagKey] = $true
    }

    $actions = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($id in ($byItem.Keys | Sort-Object)) {
        $flags = $byItem[$id]
        $item = Get-MetraLoomQueueItem -Root $Root -Id $id
        if (-not $item) {
            [void]$errors.Add("Queue item not found: $id")
            continue
        }

        if ($flags['BLOCK']) {
            if ([string]$item.status -ne 'completed') {
                [void]$errors.Add("$id BLOCK requires status completed (got $($item.status))")
            }
            else {
                $actions.Add([PSCustomObject]@{ itemId = $id; action = 'BLOCK'; item = $item })
            }
            continue
        }
        if ($flags['RETRY']) {
            if ([string]$item.status -ne 'completed') {
                [void]$errors.Add("$id RETRY requires status completed (got $($item.status))")
            }
            else {
                $actions.Add([PSCustomObject]@{ itemId = $id; action = 'RETRY'; item = $item })
            }
            continue
        }
        if ($flags['ACCEPT']) {
            if ([string]$item.status -eq 'accepted') {
                $existing = Get-LoomAcceptanceRecord -Root $Root -ItemId $id
                $actions.Add([PSCustomObject]@{
                    itemId = $id; action = 'ACCEPT'; item = $item; alreadyAccepted = $true; existing = $existing
                })
                continue
            }
            if ([string]$item.status -ne 'completed') {
                [void]$errors.Add("$id ACCEPT requires status completed (got $($item.status))")
                continue
            }
            $evidence = Test-LoomManifestEvidenceForAccept -Root $Root -Item $item -ReviewDate $ReviewDate
            if (-not $evidence.ok) {
                [void]$errors.Add("$id ACCEPT blocked: $($evidence.reason)")
                continue
            }
            $needsManual = Test-LoomItemNeedsManualTest -Item $item
            $manualDone = [bool]$flags['ManualTestDone']
            if ($needsManual -and -not $manualDone -and -not $OverrideManualTest) {
                [void]$errors.Add("$id ACCEPT blocked: manual-test-open")
                continue
            }
            if ($OverrideManualTest -and [string]::IsNullOrWhiteSpace($OverrideReason)) {
                [void]$errors.Add("$id OverrideManualTest requires -OverrideReason")
                continue
            }
            $actions.Add([PSCustomObject]@{
                itemId    = $id
                action    = 'ACCEPT'
                item      = $item
                evidence  = $evidence
                manualDone = $manualDone
            })
        }
    }

    return [PSCustomObject]@{
        reviewDate = $ReviewDate
        directives = $directives
        actions    = Get-LoomContractArray $actions
        errors     = Get-LoomContractArray $errors
        merge      = [bool]$Merge
        overrideManualTest = [bool]$OverrideManualTest
        overrideReason     = $OverrideReason
    }
}

function New-LoomAcceptanceRecordDraft {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ReviewDate,
        [Parameter(Mandatory)]$Evidence,
        [bool]$ManualDone,
        [switch]$OverrideManualTest,
        [string]$OverrideReason,
        [string]$Operator = (Get-LoomOperatorName),
        [bool]$MergeRequested
    )

    $completed = [string](Get-LoomProp -Object $Item.execution -Name 'completedCommit' -Default '')
    $source = $Item.source
    $formalPath = ''
    $todoOrSlice = ''
    if ($source -and [string](Get-LoomProp -Object $source -Name 'type' -Default '') -eq 'formal-plan') {
        $formalPath = [string](Get-LoomProp -Object $source -Name 'path' -Default '')
        $todoOrSlice = [string](Get-LoomProp -Object $source -Name 'todoOrSlice' -Default '')
        if ([string]::IsNullOrWhiteSpace($todoOrSlice)) {
            $todoOrSlice = [string](Get-LoomProp -Object $source -Name 'slice' -Default '')
        }
    }

    $override = $null
    if ($OverrideManualTest) {
        $override = [PSCustomObject]@{
            manualTest              = $true
            reason                  = $OverrideReason
            operator                = $Operator
            at                      = (Get-Date).ToString('o')
            originalManualTestClass = [string](Get-LoomProp -Object $Item.classification -Name 'manualTestClass' -Default 'none')
        }
    }

    $recordHash = @{
        schemaVersion      = 1
        recordProfile      = 'loom-daily-acceptance-v1'
        itemId             = [string]$Item.id
        acceptanceOutcome  = 'accepted'
        operator           = $Operator
        acceptedAt         = (Get-Date).ToString('o')
        branch             = [string](Get-LoomProp -Object $Item.execution -Name 'branch' -Default '')
        completedCommit    = $completed
        baselineCommit     = (Get-LoomItemBaselineCommit -Item $Item)
        verifyOutcome      = (Get-LoomItemVerifyOutcome -Item $Item -Root $Root)
        packDiffPath       = [string]$Evidence.packDiffPath
        formalPlanPath     = $formalPath
        todoOrSlice        = $todoOrSlice
        manualTestComplete = $ManualDone -or $OverrideManualTest -or -not (Test-LoomItemNeedsManualTest -Item $Item)
        completionCycleId  = (Get-LoomCompletionCycleId -ItemId ([string]$Item.id) -CompletedCommit $completed)
        merge              = [PSCustomObject]@{
            requested   = [bool]$MergeRequested
            attempted   = $false
            succeeded   = $false
            mergeCommit = $null
            error       = $null
        }
    }
    if ($override) {
        $recordHash['override'] = $override
    }
    return [PSCustomObject]$recordHash
}

function Test-LoomGitMergePreconditions {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$CompletedCommit,
        [string]$TargetBranch = 'main'
    )

    if (-not (Test-LoomGitWorkingTreeClean -ProjectRoot $ProjectRoot)) {
        return [PSCustomObject]@{ ok = $false; reason = 'dirty-worktree' }
    }
    $inProgress = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('rev-parse', '-q', '--verify', 'MERGE_HEAD')
    if ($inProgress.ExitCode -eq 0) {
        return [PSCustomObject]@{ ok = $false; reason = 'merge-in-progress' }
    }
    if (-not (Test-LoomGitObjectExists -ProjectRoot $ProjectRoot -Commit $CompletedCommit)) {
        return [PSCustomObject]@{ ok = $false; reason = 'completed-commit-missing' }
    }
    $branchCheck = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('rev-parse', '--verify', $Branch)
    if ($branchCheck.ExitCode -ne 0) {
        return [PSCustomObject]@{ ok = $false; reason = 'branch-missing' }
    }
    $contains = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('merge-base', '--is-ancestor', $CompletedCommit, $Branch)
    if ($contains.ExitCode -ne 0) {
        return [PSCustomObject]@{ ok = $false; reason = 'branch-lacks-completed-commit' }
    }
    $targetCheck = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('rev-parse', '--verify', $TargetBranch)
    if ($targetCheck.ExitCode -ne 0) {
        return [PSCustomObject]@{ ok = $false; reason = 'target-branch-missing'; detail = (Get-LoomGitErrorDetail $targetCheck) }
    }
    return [PSCustomObject]@{ ok = $true; reason = $null; targetBranch = $TargetBranch }
}

function Invoke-LoomDailyMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$CompletedCommit,
        [string]$TargetBranch = 'main'
    )

    $pre = Test-LoomGitMergePreconditions -ProjectRoot $ProjectRoot -Branch $Branch -CompletedCommit $CompletedCommit -TargetBranch $TargetBranch
    if (-not $pre.ok) {
        return [PSCustomObject]@{
            attempted   = $true
            succeeded   = $false
            mergeCommit = $null
            error       = $pre.reason
            detail      = [string](Get-LoomProp -Object $pre -Name 'detail' -Default '')
        }
    }

    $originalBranch = (Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')).Stdout.Trim()
    $checkout = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('checkout', $TargetBranch)
    if ($checkout.ExitCode -ne 0) {
        return [PSCustomObject]@{
            attempted   = $true
            succeeded   = $false
            mergeCommit = $null
            error       = 'target-checkout-failed'
            detail      = (Get-LoomGitErrorDetail $checkout)
        }
    }

    $merge = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('merge', '--no-ff', $Branch, '-m', "loom: merge $Branch")
    if ($merge.ExitCode -ne 0) {
        Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('merge', '--abort') | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($originalBranch)) {
            Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('checkout', $originalBranch) | Out-Null
        }
        return [PSCustomObject]@{
            attempted   = $true
            succeeded   = $false
            mergeCommit = $null
            error       = 'merge-conflict'
            detail      = (Get-LoomGitErrorDetail $merge)
        }
    }
    $sha = Get-LoomGitHeadCommit -ProjectRoot $ProjectRoot
    return [PSCustomObject]@{
        attempted   = $true
        succeeded   = $true
        mergeCommit = $sha
        error       = $null
        detail      = $merge.Stdout
    }
}

function Invoke-LoomDailyStateChange {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To,
        [string]$Reason,
        [string]$Actor = 'operator'
    )
    $script:LoomDailyApproveActive = $true
    try {
        return Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From $From -To $To -Reason $Reason -Actor $Actor
    }
    finally {
        $script:LoomDailyApproveActive = $false
    }
}

function Invoke-MetraLoomDailyApprove {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PlanPath,
        [string]$ReviewDate,
        [switch]$Confirm,
        [switch]$Merge,
        [switch]$OverrideManualTest,
        [string]$OverrideReason,
        [string]$Operator = (Get-LoomOperatorName)
    )

    Initialize-MetraLoomLayout -Root $Root
    $plan = Get-LoomDailyApprovePlan -Root $Root -PlanPath $PlanPath -ReviewDate $ReviewDate `
        -OverrideManualTest:$OverrideManualTest -OverrideReason $OverrideReason -Merge:$Merge

    if (@(Get-LoomListArray $plan.errors).Count -gt 0) {
        return [PSCustomObject]@{
            dryRun  = -not $Confirm
            applied = $false
            errors  = Get-LoomListArray $plan.errors
            actions = Get-LoomListArray $plan.actions
            message = 'Validation failed; zero mutations.'
        }
    }

    if (-not $Confirm) {
        return [PSCustomObject]@{
            dryRun  = $true
            applied = $false
            errors  = @()
            actions = @(Get-LoomListArray $plan.actions | ForEach-Object {
                [PSCustomObject]@{
                    itemId = $_.itemId
                    action = $_.action
                    status = [string]$_.item.status
                }
            })
            mergeCandidates = @(
                $plan.actions | Where-Object { $_.action -eq 'ACCEPT' } | ForEach-Object { $_.itemId }
            )
            message = 'Preview only; no writes.'
        }
    }

    if (@(Get-LoomListArray $plan.actions).Count -eq 0) {
        return [PSCustomObject]@{ dryRun = $false; applied = $false; message = 'No active directives.' }
    }

    $records = New-Object System.Collections.Generic.List[object]
    $acceptActions = @($plan.actions | Where-Object { $_.action -eq 'ACCEPT' -and -not $_.alreadyAccepted })

    foreach ($act in $acceptActions) {
        $draft = New-LoomAcceptanceRecordDraft -Item $act.item -Root $Root -ReviewDate $plan.reviewDate `
            -Evidence $act.evidence -ManualDone $act.manualDone `
            -OverrideManualTest:$OverrideManualTest -OverrideReason $OverrideReason `
            -Operator $Operator -MergeRequested:$Merge
        $existing = Get-LoomAcceptanceRecord -Root $Root -ItemId ([string]$act.item.id)
        if ($existing) {
            if (-not (Test-LoomAcceptanceRecordMatches -Existing $existing -Proposed $draft)) {
                throw "Acceptance record evidence mismatch for $($act.item.id); refusing overwrite."
            }
        }
        else {
            $records.Add($draft)
        }
    }

    foreach ($rec in $records) {
        Write-LoomAcceptanceRecord -Root $Root -Record $rec
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($act in (Get-LoomListArray $plan.actions)) {
        switch ($act.action) {
            'ACCEPT' {
                if ($act.alreadyAccepted) {
                    $results.Add([PSCustomObject]@{ itemId = $act.itemId; action = 'ACCEPT'; outcome = 'already-accepted' })
                    continue
                }
                $final = Invoke-LoomDailyStateChange -Root $Root -ItemId $act.itemId -From 'completed' -To 'accepted' -Reason 'daily-accept'
                $results.Add([PSCustomObject]@{ itemId = $act.itemId; action = 'ACCEPT'; outcome = 'accepted'; status = $final.status })

                if ($Merge) {
                    $rec = Get-LoomAcceptanceRecord -Root $Root -ItemId $act.itemId
                    $projectRoot = [System.IO.Path]::GetFullPath([string]$act.item.project.root)
                    $branch = [string](Get-LoomProp -Object $act.item.execution -Name 'branch' -Default '')
                    $completed = [string](Get-LoomProp -Object $act.item.execution -Name 'completedCommit' -Default '')
                    $mergeResult = Invoke-LoomDailyMerge -ProjectRoot $projectRoot -Branch $branch -CompletedCommit $completed
                    $rec.merge = [PSCustomObject]@{
                        requested   = $true
                        attempted   = $mergeResult.attempted
                        succeeded   = $mergeResult.succeeded
                        mergeCommit = $mergeResult.mergeCommit
                        error       = $mergeResult.error
                    }
                    Write-LoomAcceptanceRecord -Root $Root -Record $rec
                    $results.Add([PSCustomObject]@{ itemId = $act.itemId; action = 'MERGE'; outcome = $(if ($mergeResult.succeeded) { 'merged' } else { 'merge-failed' }) })
                }
            }
            'RETRY' {
                $final = Invoke-LoomDailyStateChange -Root $Root -ItemId $act.itemId -From 'completed' -To 'implementing' -Reason 'daily-retry'
                $results.Add([PSCustomObject]@{ itemId = $act.itemId; action = 'RETRY'; outcome = 'implementing'; status = $final.status })
            }
            'BLOCK' {
                $final = Invoke-LoomDailyStateChange -Root $Root -ItemId $act.itemId -From 'completed' -To 'blocked' -Reason 'daily-block'
                $results.Add([PSCustomObject]@{ itemId = $act.itemId; action = 'BLOCK'; outcome = 'blocked'; status = $final.status })
            }
        }
    }

    return [PSCustomObject]@{
        dryRun  = $false
        applied = $true
        results = Get-LoomListArray $results
        message = 'Daily approve applied.'
    }
}

function Invoke-MetraLoomDailyStub {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$MetraRoot = (Get-LoomHostRoot),
        [datetime]$Date = (Get-Date)
    )
    return Invoke-MetraLoomDailyBuild -Root $Root -MetraRoot $MetraRoot -ReviewDate (Get-LoomDailyReviewDate -Date $Date)
}
