# Attention memory - continuity of observations and operator intentions.
# Not a work management system; does not claim completion status.

function Get-MetraAttentionHash {
    <#
    .SYNOPSIS
        Stable short SHA256 hex prefix for attention keys and evidence signatures.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }
    $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
    return $hex.Substring(0, [Math]::Min(16, $hex.Length))
}

function Get-MetraAttentionNormalizedContent {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return '' }
    $c = $Content.Trim() -replace '\s+', ' '
    return $c.ToLowerInvariant()
}

function Get-MetraAttentionKey {
    <#
    .SYNOPSIS
        Stable attention identity key (project|kind|normalized base content).
    .NOTES
        Git items use project:git. Decision/contract keep prefixed ids when provided.
    #>
    [CmdletBinding()]
    param(
        [string]$Project = '',
        [Parameter(Mandatory)][string]$Kind,
        [string]$Content = '',
        [string]$ExistingId = ''
    )

    $kind = $Kind.Trim().ToLowerInvariant()
    if ($ExistingId -and ($ExistingId.StartsWith('decision:') -or $ExistingId.StartsWith('contract:'))) {
        return $ExistingId
    }
    if ($kind -eq 'git' -and $Project) {
        return "$Project`:git"
    }
    $norm = Get-MetraAttentionNormalizedContent -Content $Content
    $material = "{0}|{1}|{2}" -f $Project, $kind, $norm
    $hash = Get-MetraAttentionHash -Text $material
    if ($Project) {
        return "{0}:{1}:{2}" -f $Project, $kind, $hash
    }
    return "{0}:{1}" -f $kind, $hash
}

function Get-MetraAttentionEvidenceSignature {
    <#
    .SYNOPSIS
        Hash of the distinguishing fact - sticky dismiss stays until this changes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Kind,
        [string]$Content = '',
        [string]$Command = ''
    )

    $kind = $Kind.Trim().ToLowerInvariant()
    $norm = Get-MetraAttentionNormalizedContent -Content $Content
    $cmd = Get-MetraAttentionNormalizedContent -Content $Command
    return Get-MetraAttentionHash -Text ("{0}|{1}|{2}" -f $kind, $norm, $cmd)
}

function Get-MetraAttentionMemoryPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return Join-Path $MetraRoot 'docs\ops-attention.local.json'
}

function Get-MetraAttentionMemoryDefaults {
    return [PSCustomObject]@{
        version   = 1
        updatedAt = $null
        items     = @()
    }
}

function Add-MetraAttentionEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$Type,
        [string]$Note = ''
    )

    $events = @()
    if ($Item.events) { $events = @($Item.events) }
    $entry = [PSCustomObject]@{
        type = $Type
        at   = (Get-Date).ToString('o')
    }
    if ($Note) {
        $entry | Add-Member -NotePropertyName note -NotePropertyValue $Note -Force
    }
    $events += $entry
    if ($events.Count -gt 12) {
        $events = @($events | Select-Object -Last 12)
    }
    $Item.events = $events
    return $Item
}

function Get-MetraAttentionMemory {
    <#
    .SYNOPSIS
        Loads local attention memory (gitignored). Tolerant of missing/corrupt files.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Get-MetraAttentionMemoryPath -MetraRoot $MetraRoot
    $defaults = Get-MetraAttentionMemoryDefaults
    if (-not (Test-Path -LiteralPath $path)) {
        return $defaults
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
        $items = @()
        foreach ($i in @((Get-MetraProp -Object $raw -Name 'items' -Default @()))) {
            if (-not $i) { continue }
            $items += [PSCustomObject]@{
                key                = [string](Get-MetraProp -Object $i -Name 'key' -Default '')
                project            = [string](Get-MetraProp -Object $i -Name 'project' -Default '')
                kind               = [string](Get-MetraProp -Object $i -Name 'kind' -Default '')
                source             = [string](Get-MetraProp -Object $i -Name 'source' -Default 'snapshot')
                content            = [string](Get-MetraProp -Object $i -Name 'content' -Default '')
                command            = [string](Get-MetraProp -Object $i -Name 'command' -Default '')
                evidenceSignature  = [string](Get-MetraProp -Object $i -Name 'evidenceSignature' -Default '')
                state              = [string](Get-MetraProp -Object $i -Name 'state' -Default 'active')
                confidence         = [string](Get-MetraProp -Object $i -Name 'confidence' -Default 'fresh')
                firstSeenAt        = (Get-MetraProp -Object $i -Name 'firstSeenAt' -Default $null)
                lastSeenAt         = (Get-MetraProp -Object $i -Name 'lastSeenAt' -Default $null)
                lastScanMode       = [string](Get-MetraProp -Object $i -Name 'lastScanMode' -Default '')
                notRecheckedSince  = (Get-MetraProp -Object $i -Name 'notRecheckedSince' -Default $null)
                snoozedUntil       = (Get-MetraProp -Object $i -Name 'snoozedUntil' -Default $null)
                closedAt           = (Get-MetraProp -Object $i -Name 'closedAt' -Default $null)
                closedBy           = [string](Get-MetraProp -Object $i -Name 'closedBy' -Default '')
                note               = [string](Get-MetraProp -Object $i -Name 'note' -Default '')
                events             = @((Get-MetraProp -Object $i -Name 'events' -Default @()))
            }
        }
        return [PSCustomObject]@{
            version   = [int](Get-MetraProp -Object $raw -Name 'version' -Default 1)
            updatedAt = (Get-MetraProp -Object $raw -Name 'updatedAt' -Default $null)
            items     = $items
        }
    }
    catch {
        return $defaults
    }
}

function Set-MetraAttentionMemory {
    <#
    .SYNOPSIS
        Writes local attention memory after prune/cap.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Memory,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$MaxItems = 200,
        [int]$RetainClosedDays = 30
    )

    $cutoff = (Get-Date).AddDays(-1 * $RetainClosedDays)
    $items = @()
    foreach ($i in @($Memory.items)) {
        if (-not $i -or -not [string]$i.key) { continue }
        $state = [string]$i.state
        if ($state -in @('autoClosed', 'dismissed') -and $i.closedAt) {
            try {
                $closed = [datetime]::Parse([string]$i.closedAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                if ($closed -lt $cutoff) { continue }
            }
            catch { }
        }
        $items += $i
    }
    if ($items.Count -gt $MaxItems) {
        $items = @(
            $items |
                Sort-Object {
                    $ls = $_.lastSeenAt
                    if ($ls) {
                        try { [datetime]::Parse([string]$ls, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) }
                        catch { [datetime]::MinValue }
                    }
                    else { [datetime]::MinValue }
                } -Descending |
                Select-Object -First $MaxItems
        )
    }

    $Memory.items = $items
    $Memory.updatedAt = (Get-Date).ToString('o')
    $path = Get-MetraAttentionMemoryPath -MetraRoot $MetraRoot
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Memory | ConvertTo-Json -Depth 8)
    [System.IO.File]::WriteAllText($path, $json + "`r`n")
    return $Memory
}

function Get-MetraAttentionKindPriority {
    [CmdletBinding()]
    param([string]$Kind)

    switch ([string]$Kind) {
        'verify' { return 0 }
        'drift' { return 1 }
        'decision' { return 2 }
        'contract' { return 3 }
        'git' { return 4 }
        default { return 5 }
    }
}

function Get-MetraAttentionConfidenceRank {
    [CmdletBinding()]
    param([string]$Confidence)

    switch ([string]$Confidence) {
        'fresh' { return 0 }
        'likelyStale' { return 1 }
        'needsRevalidation' { return 2 }
        default { return 3 }
    }
}

function Get-MetraAttentionConfidenceFromAge {
    [CmdletBinding()]
    param(
        [datetime]$LastSeenAt,
        [switch]$ConfirmedThisScan
    )

    if ($ConfirmedThisScan) { return 'fresh' }
    $ageHours = ((Get-Date) - $LastSeenAt).TotalHours
    if ($ageHours -lt 24) { return 'likelyStale' }
    return 'needsRevalidation'
}

function Get-MetraAttentionPlainSummary {
    <#
    .SYNOPSIS
        Operator-facing headline for an attention item (plain language first).
    #>
    [CmdletBinding()]
    param(
        [string]$Project = '',
        [string]$Kind = '',
        [string]$Content = ''
    )

    $kind = $Kind.Trim().ToLowerInvariant()
    $content = [string]$Content
    $project = [string]$Project

    if ($kind -eq 'git') {
        $parts = @()
        if ($content -match '(?i)\bdirty\s+(\d+)') {
            $n = [int]$Matches[1]
            $parts += if ($n -eq 1) { '1 unfinished local change' } else { "$n unfinished local changes" }
        }
        if ($content -match '(?i)\bahead\s+(\d+)') {
            $n = [int]$Matches[1]
            $parts += if ($n -eq 1) { '1 change waiting to be published' } else { "$n changes waiting to be published" }
        }
        if ($content -match '(?i)\bbehind\s+(\d+)') {
            $n = [int]$Matches[1]
            $parts += if ($n -eq 1) { '1 update available from the shared copy' } else { "$n updates available from the shared copy" }
        }
        if ($parts.Count -gt 0) {
            $body = $parts -join '; '
            if ($project) { return "$project has $body." }
            return (Get-Culture).TextInfo.ToTitleCase($body) + '.'
        }
        if ($project) { return "$project has unpublished work." }
        return 'Unpublished work needs a look.'
    }

    if ($kind -eq 'verify') {
        if ($project) { return "$project failed a health check." }
        return 'A health check needs attention.'
    }
    if ($kind -eq 'drift') {
        if ($project) { return "$project does not match the expected setup." }
        return 'A project setup does not match what Metra expects.'
    }
    if ($kind -eq 'decision') {
        if ($content) { return $content }
        return 'A decision is waiting for your call.'
    }
    if ($kind -eq 'contract') {
        if ($content) { return $content }
        return 'A working preference is waiting for review.'
    }

    if ($project -and $content -and -not $content.StartsWith("$project -", [StringComparison]::OrdinalIgnoreCase)) {
        return "$project - $content"
    }
    if ($content) { return $content }
    if ($project) { return $project }
    return 'Something needs attention.'
}

function Get-MetraAttentionWhyNext {
    <#
    .SYNOPSIS
        Plain-language reason this item is surfaced now.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        [int]$ActiveCount = 1,
        [int]$RankIndex = 0
    )

    $kind = [string]$Item.kind
    $confidence = [string]$Item.confidence
    $state = [string]$Item.state

    if ($state -eq 'held') {
        return 'You asked Metra to keep this in view.'
    }
    if ($Item.notRecheckedSince -and $confidence -ne 'fresh') {
        return 'Metra has not double-checked this lately. A full refresh will confirm whether it still needs attention.'
    }
    if ($RankIndex -eq 0 -and $ActiveCount -eq 1) {
        switch ($kind) {
            'verify' { return 'This is the only health check waiting right now.' }
            'drift' { return 'This is the only setup mismatch waiting right now.' }
            'decision' { return 'This is the only open decision waiting right now.' }
            'contract' { return 'This is the only preference waiting for review right now.' }
            'git' { return 'This is the only unpublished work waiting right now.' }
            default { return 'This is the only item waiting right now.' }
        }
    }
    if ($RankIndex -eq 0) {
        switch ($kind) {
            'verify' { return 'This is the top health check to look at next.' }
            'drift' { return 'This is the top setup mismatch to look at next.' }
            'decision' { return 'This is the top open decision to look at next.' }
            'contract' { return 'This is the top preference to review next.' }
            'git' { return 'This is the top unpublished work to look at next.' }
            default { return 'This is the top item to look at next.' }
        }
    }
    switch ($kind) {
        'verify' { return 'A health check is still waiting.' }
        'drift' { return 'A setup mismatch is still waiting.' }
        'decision' { return 'An open decision is still waiting.' }
        'contract' { return 'A preference is still waiting for review.' }
        'git' { return 'Unpublished work is still waiting.' }
        default { return 'Still waiting for attention.' }
    }
}

function Update-MetraAttentionMemory {
    <#
    .SYNOPSIS
        Reconciles derived attention queue into local attention memory.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Queue = @(),
        [Parameter(Mandatory)][string[]]$CoveredKinds,
        [ValidateSet('quick', 'full')]
        [string]$ScanMode = 'quick',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $now = Get-Date
    $nowIso = $now.ToString('o')
    $memory = Get-MetraAttentionMemory -MetraRoot $MetraRoot
    $byKey = @{}
    foreach ($existing in @($memory.items)) {
        if ($existing.key) { $byKey[[string]$existing.key] = $existing }
    }

    $seenKeys = @{}
    foreach ($q in @($Queue)) {
        if (-not $q) { continue }
        $key = [string](Get-MetraProp -Object $q -Name 'id' -Default '')
        $project = [string](Get-MetraProp -Object $q -Name 'project' -Default '')
        $kind = [string](Get-MetraProp -Object $q -Name 'kind' -Default '')
        $content = [string](Get-MetraProp -Object $q -Name 'content' -Default '')
        $command = [string](Get-MetraProp -Object $q -Name 'command' -Default '')
        $source = [string](Get-MetraProp -Object $q -Name 'source' -Default 'snapshot')
        if (-not $key) {
            $key = Get-MetraAttentionKey -Project $project -Kind $kind -Content $content
        }
        $sig = Get-MetraAttentionEvidenceSignature -Kind $kind -Content $content -Command $command
        $seenKeys[$key] = $true

        $item = $byKey[$key]
        if (-not $item) {
            $item = [PSCustomObject]@{
                key               = $key
                project           = $project
                kind              = $kind
                source            = $source
                content           = $content
                command           = $command
                evidenceSignature = $sig
                state             = 'active'
                confidence        = 'fresh'
                firstSeenAt       = $nowIso
                lastSeenAt        = $nowIso
                lastScanMode      = $ScanMode
                notRecheckedSince = $null
                snoozedUntil      = $null
                closedAt          = $null
                closedBy          = ''
                note              = ''
                events            = @()
            }
            $item = Add-MetraAttentionEvent -Item $item -Type 'firstSeen'
            $byKey[$key] = $item
            continue
        }

        $prevState = [string]$item.state
        $prevSig = [string]$item.evidenceSignature
        $item.content = $content
        $item.command = $command
        $item.project = $project
        $item.kind = $kind
        if ($source) { $item.source = $source }
        $item.lastSeenAt = $nowIso
        $item.lastScanMode = $ScanMode
        $item.notRecheckedSince = $null
        $item.confidence = 'fresh'

        if ($prevState -eq 'held') {
            # Operator intention - observations do not override hold.
            $item.evidenceSignature = $sig
            $item = Add-MetraAttentionEvent -Item $item -Type 'seen'
            $byKey[$key] = $item
            continue
        }

        if ($prevState -eq 'dismissed') {
            if ($prevSig -and $prevSig -eq $sig) {
                $item.evidenceSignature = $sig
                $item = Add-MetraAttentionEvent -Item $item -Type 'seen' -Note 'sticky dismiss'
                $byKey[$key] = $item
                continue
            }
            $item.state = 'active'
            $item.closedAt = $null
            $item.closedBy = ''
            $item.evidenceSignature = $sig
            $item = Add-MetraAttentionEvent -Item $item -Type 'reactivated' -Note 'evidenceSignature changed'
            $byKey[$key] = $item
            continue
        }

        if ($prevState -eq 'autoClosed') {
            $item.state = 'active'
            $item.closedAt = $null
            $item.closedBy = ''
            $item.evidenceSignature = $sig
            $item = Add-MetraAttentionEvent -Item $item -Type 'reactivated' -Note 'observation returned'
            $byKey[$key] = $item
            continue
        }

        if ($prevState -eq 'snoozed') {
            $until = $null
            if ($item.snoozedUntil) {
                try {
                    $until = [datetime]::Parse([string]$item.snoozedUntil, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                }
                catch { }
            }
            if ($until -and $until -gt $now) {
                $item.evidenceSignature = $sig
                $item = Add-MetraAttentionEvent -Item $item -Type 'seen'
                $byKey[$key] = $item
                continue
            }
            $item.state = 'active'
            $item.snoozedUntil = $null
            $item.evidenceSignature = $sig
            $item = Add-MetraAttentionEvent -Item $item -Type 'reactivated' -Note 'snooze expired'
            $byKey[$key] = $item
            continue
        }

        $item.state = 'active'
        $item.evidenceSignature = $sig
        $item = Add-MetraAttentionEvent -Item $item -Type 'seen'
        $byKey[$key] = $item
    }

    $coveredSet = @{}
    foreach ($k in @($CoveredKinds)) {
        if ($k) { $coveredSet[$k.ToLowerInvariant()] = $true }
    }

    foreach ($key in @($byKey.Keys)) {
        if ($seenKeys.ContainsKey($key)) { continue }
        $item = $byKey[$key]
        $kind = ([string]$item.kind).ToLowerInvariant()
        $state = [string]$item.state

        if ($state -eq 'held') { continue }
        if ($state -in @('dismissed', 'autoClosed')) { continue }

        if ($state -eq 'snoozed') {
            $until = $null
            if ($item.snoozedUntil) {
                try {
                    $until = [datetime]::Parse([string]$item.snoozedUntil, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                }
                catch { }
            }
            if ($until -and $until -gt $now) { continue }
            $item.state = 'active'
            $item.snoozedUntil = $null
        }

        $kindCovered = $coveredSet.ContainsKey($kind)
        if ($ScanMode -eq 'full' -and $kindCovered) {
            $item.state = 'autoClosed'
            $item.closedAt = $nowIso
            $item.closedBy = 'scan'
            $item.confidence = 'fresh'
            $item.notRecheckedSince = $null
            $item = Add-MetraAttentionEvent -Item $item -Type 'autoClosed' -Note 'missing on full scan'
            $byKey[$key] = $item
            continue
        }

        # Skipped kind or quick scan - stay active, age confidence.
        if (-not $item.notRecheckedSince) {
            $item.notRecheckedSince = $nowIso
        }
        $lastSeen = $now
        if ($item.lastSeenAt) {
            try {
                $lastSeen = [datetime]::Parse([string]$item.lastSeenAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            }
            catch { }
        }
        $item.confidence = Get-MetraAttentionConfidenceFromAge -LastSeenAt $lastSeen
        $item.lastScanMode = $ScanMode
        $byKey[$key] = $item
    }

    $memory.items = @($byKey.Values)
    return Set-MetraAttentionMemory -Memory $memory -MetraRoot $MetraRoot
}

function Get-MetraAttentionActiveItems {
    <#
    .SYNOPSIS
        Ranked active (and optionally held) attention items for desk payload.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Memory,
        [switch]$IncludeHeld
    )

    $now = Get-Date
    $active = @()
    foreach ($item in @($Memory.items)) {
        $state = [string]$item.state
        if ($state -eq 'held') {
            if ($IncludeHeld) { $active += $item }
            continue
        }
        if ($state -eq 'snoozed') {
            $until = $null
            if ($item.snoozedUntil) {
                try {
                    $until = [datetime]::Parse([string]$item.snoozedUntil, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                }
                catch { }
            }
            if ($until -and $until -gt $now) { continue }
            $item.state = 'active'
            $item.snoozedUntil = $null
        }
        if ($state -notin @('active', 'snoozed')) { continue }
        if ([string]$item.state -ne 'active') { continue }
        $active += $item
    }

    return @(
        $active |
            Sort-Object `
            @{ Expression = { Get-MetraAttentionKindPriority -Kind $_.kind } }, `
            @{ Expression = { Get-MetraAttentionConfidenceRank -Confidence $_.confidence } }, `
            @{ Expression = { [string]$_.content } }
    )
}

function ConvertTo-MetraDeskAttentionView {
    <#
    .SYNOPSIS
        Enriches a memory item for the Ops desk payload (resolve actions + whyNext).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$MemItem,
        [int]$RankIndex = 0,
        [int]$ActiveCount = 1,
        $Snapshot
    )

    $projectName = [string]$MemItem.project
    $kind = [string]$MemItem.kind
    $content = [string]$MemItem.content
    $command = [string]$MemItem.command
    $key = [string]$MemItem.key

    $proposalId = $null
    $proposalStatus = $null
    if ($projectName) {
        try {
            $activeProposal = Find-MetraActiveProposalForProject -Project $projectName
            if ($activeProposal) {
                $proposalId = [string]$activeProposal.Id
                $proposalStatus = [string]$activeProposal.Status
            }
        }
        catch { }
    }

    $editCapability = Get-MetraAttentionEditCapability -Kind $kind -ProposalId $proposalId
    $summary = Get-MetraAttentionPlainSummary -Project $projectName -Kind $kind -Content $content
    $askPrompt = if ($projectName) {
        "In project $projectName, help with: $content. Prefer that project's AGENTS.md and Metra routing. When done, summarize what changed and what I should verify."
    }
    else {
        "Help with: $content. Prefer Metra routing and AGENTS.md. When done, summarize what changed and what I should verify."
    }
    $doneWhen = switch ($editCapability) {
        'git' { 'The changes are published, or you have reviewed them and decided what to do next.' }
        'safe' { 'You confirmed the change in the Metra tray (or rejected it), and it looks right.' }
        default { 'You understand the issue and either fixed it or handed it off with a clear next step.' }
    }
    $resolveCopy = switch ($editCapability) {
        'safe' { 'Metra can make this small change after you confirm in the Metra tray.' }
        'git' { 'Open the project in your editor to review and publish the changes. Metra will not publish from this page.' }
        default { 'Open this in your editor to work on it. Metra can help prepare context, but will not change files from this page.' }
    }

    $projectPath = $null
    if ($projectName) {
        if ($Snapshot) {
            $projRow = @($Snapshot.projects) | Where-Object { [string]$_.name -eq $projectName } | Select-Object -First 1
            if ($projRow) {
                $projectPath = [string](Get-MetraProp -Object $projRow -Name 'path' -Default '')
                if (-not $projectPath) {
                    $rel = [string](Get-MetraProp -Object $projRow -Name 'gitRepoPath' -Default '')
                    if ($rel -and (Test-Path -LiteralPath $rel)) { $projectPath = $rel }
                }
            }
        }
        if (-not $projectPath) {
            try {
                $proj = Get-MetraProject -Name $projectName -ErrorAction Stop
                $projectPath = [string](Get-MetraProp -Object $proj -Name 'Path' -Default '')
                if (-not $projectPath) {
                    $projectPath = [string](Get-MetraProp -Object $proj -Name 'path' -Default '')
                }
            }
            catch { }
        }
        if (-not $projectPath) {
            try {
                $projectPath = [string](Get-MetraProjectRoot -Name $projectName)
            }
            catch { }
        }
    }

    $whyNext = Get-MetraAttentionWhyNext -Item $MemItem -ActiveCount $ActiveCount -RankIndex $RankIndex

    return [PSCustomObject]@{
        id                = $key
        key               = $key
        project           = $projectName
        content           = $content
        kind              = $kind
        command           = $command
        summary           = $summary
        askPrompt         = $askPrompt
        doneWhen          = $doneWhen
        editCapability    = $editCapability
        resolveCopy       = $resolveCopy
        proposalId        = $proposalId
        proposalStatus    = $proposalStatus
        projectPath       = $projectPath
        whyNext           = $whyNext
        confidence        = [string]$MemItem.confidence
        source            = [string]$MemItem.source
        state             = [string]$MemItem.state
        evidenceSignature = [string]$MemItem.evidenceSignature
        firstSeenAt       = $MemItem.firstSeenAt
        lastSeenAt        = $MemItem.lastSeenAt
        lastScanMode      = [string]$MemItem.lastScanMode
        notRecheckedSince = $MemItem.notRecheckedSince
        snoozedUntil      = $MemItem.snoozedUntil
        closedAt          = $MemItem.closedAt
        closedBy          = [string]$MemItem.closedBy
        note              = [string]$MemItem.note
    }
}

function Invoke-MetraAttentionMutation {
    <#
    .SYNOPSIS
        Operator mutations: dismiss, snooze, reopen, hold, release.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)]
        [ValidateSet('dismiss', 'snooze', 'reopen', 'hold', 'release')]
        [string]$Action,
        [int]$Days = 1,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $memory = Get-MetraAttentionMemory -MetraRoot $MetraRoot
    $item = @($memory.items) | Where-Object { [string]$_.key -eq $Key } | Select-Object -First 1
    if (-not $item) {
        throw "Attention item not found: $Key"
    }

    $nowIso = (Get-Date).ToString('o')
    switch ($Action) {
        'dismiss' {
            $item.state = 'dismissed'
            $item.closedAt = $nowIso
            $item.closedBy = 'operator'
            $item.snoozedUntil = $null
            $item = Add-MetraAttentionEvent -Item $item -Type 'dismissed'
        }
        'snooze' {
            if ($Days -lt 1) { $Days = 1 }
            if ($Days -gt 90) { $Days = 90 }
            $item.state = 'snoozed'
            $item.snoozedUntil = (Get-Date).AddDays($Days).ToString('o')
            $item.closedAt = $null
            $item.closedBy = ''
            $item = Add-MetraAttentionEvent -Item $item -Type 'snoozed' -Note ("days=$Days")
        }
        'reopen' {
            $item.state = 'active'
            $item.closedAt = $null
            $item.closedBy = ''
            $item.snoozedUntil = $null
            $item.confidence = 'fresh'
            $item = Add-MetraAttentionEvent -Item $item -Type 'reactivated' -Note 'operator reopen'
        }
        'hold' {
            $item.state = 'held'
            $item.source = 'operator'
            $item.closedAt = $null
            $item.closedBy = ''
            $item.snoozedUntil = $null
            $item = Add-MetraAttentionEvent -Item $item -Type 'held'
        }
        'release' {
            $item.state = 'dismissed'
            $item.closedAt = $nowIso
            $item.closedBy = 'operator'
            $item = Add-MetraAttentionEvent -Item $item -Type 'released'
        }
    }

    $newItems = @()
    foreach ($i in @($memory.items)) {
        if ([string]$i.key -eq $Key) { $newItems += $item }
        else { $newItems += $i }
    }
    $memory.items = $newItems
    return Set-MetraAttentionMemory -Memory $memory -MetraRoot $MetraRoot
}
