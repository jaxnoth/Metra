# Decision Registry (Operational Why Memory) - private helpers (CLI via metra.ps1 decisions).

$script:MetraDecisionRegistryMaxConfirmed = 50
$script:MetraDecisionRegistryStaleDays = 30
$script:MetraDecisionRegistryConfidenceValues = @('high', 'medium', 'low')

function Get-MetraDecisionRegistryPaths {
    <#
    .SYNOPSIS
        Resolves the Decision Registry ledger path under a Metra root.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    [PSCustomObject]@{
        MetraRoot  = $MetraRoot
        LedgerPath = Join-Path $MetraRoot 'docs\decision-registry.json'
    }
}

function New-MetraDecisionRegistryId {
    param([ValidateSet('c', 'd')][string]$Prefix = 'd')
    ($Prefix + [guid]::NewGuid().ToString('N').Substring(0, 10))
}

function New-MetraDecisionRegistryEmpty {
    [PSCustomObject]@{
        version            = 1
        candidateStaleDays = $script:MetraDecisionRegistryStaleDays
        maxConfirmed       = $script:MetraDecisionRegistryMaxConfirmed
        candidates         = @()
        confirmed          = @()
    }
}

function Get-MetraDecisionRegistry {
    <#
    .SYNOPSIS
        Loads the Decision Registry ledger or returns an empty registry.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $paths = Get-MetraDecisionRegistryPaths -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $paths.LedgerPath)) {
        return New-MetraDecisionRegistryEmpty
    }

    $raw = Get-Content -LiteralPath $paths.LedgerPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return New-MetraDecisionRegistryEmpty
    }

    try {
        $obj = $raw | ConvertFrom-Json
    }
    catch {
        throw ("Failed to parse Decision Registry ledger '{0}': {1}" -f $paths.LedgerPath, $_.Exception.Message)
    }
    $candidates = @()
    if ($null -ne $obj.candidates) { $candidates = @($obj.candidates) }
    $confirmed = @()
    if ($null -ne $obj.confirmed) { $confirmed = @($obj.confirmed) }

    $staleDays = $script:MetraDecisionRegistryStaleDays
    if ($null -ne $obj.candidateStaleDays) { $staleDays = [int]$obj.candidateStaleDays }
    $maxConfirmed = $script:MetraDecisionRegistryMaxConfirmed
    if ($null -ne $obj.maxConfirmed) { $maxConfirmed = [int]$obj.maxConfirmed }

    [PSCustomObject]@{
        version            = if ($null -ne $obj.version) { [int]$obj.version } else { 1 }
        candidateStaleDays = $staleDays
        maxConfirmed       = $maxConfirmed
        candidates         = $candidates
        confirmed          = $confirmed
    }
}

function Save-MetraDecisionRegistry {
    <#
    .SYNOPSIS
        Writes the Decision Registry ledger as UTF-8 JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Registry,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $paths = Get-MetraDecisionRegistryPaths -MetraRoot $MetraRoot
    $docsDir = Split-Path -Parent $paths.LedgerPath
    if (-not (Test-Path -LiteralPath $docsDir)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($docsDir)
    }

    $payload = [ordered]@{
        version            = [int]$Registry.version
        candidateStaleDays = [int]$Registry.candidateStaleDays
        maxConfirmed       = [int]$Registry.maxConfirmed
        candidates         = @($Registry.candidates)
        confirmed          = @($Registry.confirmed)
    }
    $json = $payload | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $paths.LedgerPath -Value $json -Encoding UTF8
}

function Normalize-MetraDecisionText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    ($Text -replace '\s+', ' ').Trim()
}

function ConvertTo-MetraDecisionEvidence {
    param($Evidence)
    $items = @()
    if ($null -eq $Evidence) { return @() }
    if ($Evidence -is [string]) {
        foreach ($part in @($Evidence -split ',')) {
            $t = Normalize-MetraDecisionText $part
            if ($t) { $items += $t }
        }
        return @($items)
    }
    foreach ($e in @($Evidence)) {
        $t = Normalize-MetraDecisionText ([string]$e)
        if ($t) { $items += $t }
    }
    return @($items)
}

function ConvertTo-MetraDecisionTags {
    param($Tags)
    $items = @()
    if ($null -eq $Tags) { return @() }
    if ($Tags -is [string]) {
        foreach ($part in @($Tags -split ',')) {
            $t = Normalize-MetraDecisionText $part
            if ($t) { $items += $t.ToLowerInvariant() }
        }
        return @($items)
    }
    foreach ($tag in @($Tags)) {
        $t = Normalize-MetraDecisionText ([string]$tag)
        if ($t) { $items += $t.ToLowerInvariant() }
    }
    return @($items)
}

function Test-MetraDecisionConfidence {
    param([string]$Confidence)
    $c = Normalize-MetraDecisionText $Confidence
    if (-not $c) { return $false }
    return ($script:MetraDecisionRegistryConfidenceValues -contains $c.ToLowerInvariant())
}

function Assert-MetraDecisionPromotionFields {
    param(
        [string]$Why,
        [string]$Confidence,
        $Evidence
    )

    $whyText = Normalize-MetraDecisionText $Why
    if (-not $whyText) {
        throw 'Decision Registry promote requires a non-empty why. The why is the operational scar worth preserving.'
    }
    if (-not (Test-MetraDecisionConfidence -Confidence $Confidence)) {
        throw ("Decision Registry promote requires confidence of high, medium, or low (got '{0}')." -f $Confidence)
    }
    $ev = @(ConvertTo-MetraDecisionEvidence $Evidence)
    if ($ev.Count -eq 0) {
        throw 'Decision Registry promote requires at least one evidence item (path, ticket, command, or Operator confirmed).'
    }
    return [PSCustomObject]@{
        Why        = $whyText
        Confidence = (Normalize-MetraDecisionText $Confidence).ToLowerInvariant()
        Evidence   = $ev
    }
}

function Test-MetraDecisionRegistryProductPolicyText {
    <#
    .SYNOPSIS
        Returns true when text looks like every-clone Metra product policy, not operator ops memory.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $t = $Text.ToLowerInvariant()
    $patterns = @(
        'every metra clone',
        'every clone',
        'portfolio-wide',
        'docs/decisions.md',
        'decisions.md',
        'professional sink',
        'base persona',
        'metra-persona.mdc',
        'product triangle',
        'communication discipline for all',
        'misc catch-all',
        'tickets start in tickettracker then one technical project'
    )
    foreach ($p in $patterns) {
        if ($t.Contains($p)) { return $true }
    }
    return $false
}

function Get-MetraDecisionFingerprint {
    param(
        [string]$Title,
        [string]$Decision,
        [string]$Project
    )
    $parts = @(
        (Normalize-MetraDecisionText $Project).ToLowerInvariant(),
        (Normalize-MetraDecisionText $Title).ToLowerInvariant(),
        (Normalize-MetraDecisionText $Decision).ToLowerInvariant()
    )
    return ($parts -join '|')
}

function Find-MetraDecisionByFingerprint {
    param(
        $Registry,
        [Parameter(Mandatory)][string]$Fingerprint
    )

    foreach ($c in @($Registry.candidates)) {
        $fp = Get-MetraDecisionFingerprint -Title ([string](Get-MetraProp -Object $c -Name 'title' -Default '')) `
            -Decision ([string](Get-MetraProp -Object $c -Name 'decision' -Default '')) `
            -Project ([string](Get-MetraProp -Object $c -Name 'project' -Default ''))
        if ($fp -eq $Fingerprint) {
            return [PSCustomObject]@{ Bucket = 'candidates'; Entry = $c }
        }
    }
    foreach ($c in @($Registry.confirmed)) {
        $fp = Get-MetraDecisionFingerprint -Title ([string](Get-MetraProp -Object $c -Name 'title' -Default '')) `
            -Decision ([string](Get-MetraProp -Object $c -Name 'decision' -Default '')) `
            -Project ([string](Get-MetraProp -Object $c -Name 'project' -Default ''))
        if ($fp -eq $Fingerprint) {
            return [PSCustomObject]@{ Bucket = 'confirmed'; Entry = $c }
        }
    }
    return $null
}

function Resolve-MetraDecisionRegistryEntry {
    param(
        $Registry,
        [Parameter(Mandatory)][string]$IdOrTitle
    )

    $key = $IdOrTitle.Trim()
    foreach ($c in @($Registry.candidates)) {
        if ([string](Get-MetraProp -Object $c -Name 'id' -Default '') -eq $key) {
            return [PSCustomObject]@{ Bucket = 'candidates'; Entry = $c }
        }
    }
    foreach ($c in @($Registry.confirmed)) {
        if ([string](Get-MetraProp -Object $c -Name 'id' -Default '') -eq $key) {
            return [PSCustomObject]@{ Bucket = 'confirmed'; Entry = $c }
        }
    }

    $norm = (Normalize-MetraDecisionText $key).ToLowerInvariant()
    foreach ($c in @($Registry.candidates)) {
        $title = [string](Get-MetraProp -Object $c -Name 'title' -Default '')
        $titleNorm = (Normalize-MetraDecisionText $title).ToLowerInvariant()
        if ($titleNorm -eq $norm) {
            return [PSCustomObject]@{ Bucket = 'candidates'; Entry = $c }
        }
    }
    foreach ($c in @($Registry.confirmed)) {
        $title = [string](Get-MetraProp -Object $c -Name 'title' -Default '')
        $titleNorm = (Normalize-MetraDecisionText $title).ToLowerInvariant()
        if ($titleNorm -eq $norm) {
            return [PSCustomObject]@{ Bucket = 'confirmed'; Entry = $c }
        }
    }
    return $null
}

function New-MetraDecisionCandidateObject {
    param(
        [string]$Title,
        [string]$Decision,
        [string]$Why = '',
        [string]$Project = '',
        $Tags = @(),
        $See = @(),
        [string]$Source = 'operator',
        [ValidateSet('operator', 'backfill', 'harvest')][string]$Origin = 'operator',
        [string]$Confidence = '',
        $Evidence = @(),
        [int]$Count = 1
    )

    $now = (Get-Date).ToUniversalTime().ToString('o')
    $seeItems = @(ConvertTo-MetraDecisionEvidence $See)
    $ev = @(ConvertTo-MetraDecisionEvidence $Evidence)
    $conf = Normalize-MetraDecisionText $Confidence
    if ($conf) { $conf = $conf.ToLowerInvariant() }

    [PSCustomObject]@{
        id         = New-MetraDecisionRegistryId -Prefix 'c'
        title      = Normalize-MetraDecisionText $Title
        decision   = Normalize-MetraDecisionText $Decision
        why        = Normalize-MetraDecisionText $Why
        project    = Normalize-MetraDecisionText $Project
        tags       = @(ConvertTo-MetraDecisionTags $Tags)
        see        = $seeItems
        source     = Normalize-MetraDecisionText $Source
        origin     = $Origin
        confidence = $conf
        evidence   = $ev
        count      = $Count
        lastSeen   = $now
        createdAt  = $now
        updatedAt  = $now
    }
}

function Add-MetraDecisionRegistryCandidate {
    <#
    .SYNOPSIS
        Adds or bumps a Decision Registry candidate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Decision,
        [string]$Why = '',
        [string]$Project = '',
        $Tags = @(),
        $See = @(),
        [string]$Source = 'operator',
        [ValidateSet('operator', 'backfill', 'harvest')][string]$Origin = 'operator',
        [string]$Confidence = '',
        $Evidence = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $titleText = Normalize-MetraDecisionText $Title
    $decisionText = Normalize-MetraDecisionText $Decision
    if (-not $titleText -or -not $decisionText) {
        throw 'decisions note requires -Title and -Decision (or title|decision text).'
    }

    $registry = Get-MetraDecisionRegistry -MetraRoot $MetraRoot
    $fp = Get-MetraDecisionFingerprint -Title $titleText -Decision $decisionText -Project $Project
    $existing = Find-MetraDecisionByFingerprint -Registry $registry -Fingerprint $fp
    $now = (Get-Date).ToUniversalTime().ToString('o')

    if ($existing -and $existing.Bucket -eq 'confirmed') {
        return [PSCustomObject]@{
            Action = 'already-confirmed'
            Id     = [string]$existing.Entry.id
            Title  = [string]$existing.Entry.title
        }
    }

    if ($existing -and $existing.Bucket -eq 'candidates') {
        $count = [int](Get-MetraProp -Object $existing.Entry -Name 'count' -Default 1)
        $existing.Entry.count = $count + 1
        $existing.Entry.updatedAt = $now
        $existing.Entry.lastSeen = $now
        if ($Why) { $existing.Entry.why = Normalize-MetraDecisionText $Why }
        if ($Confidence) { $existing.Entry.confidence = (Normalize-MetraDecisionText $Confidence).ToLowerInvariant() }
        $ev = @(ConvertTo-MetraDecisionEvidence $Evidence)
        if ($ev.Count -gt 0) {
            $merged = @(@(Get-MetraProp -Object $existing.Entry -Name 'evidence' -Default @()) + $ev | Select-Object -Unique)
            $existing.Entry.evidence = $merged
        }
        Save-MetraDecisionRegistry -Registry $registry -MetraRoot $MetraRoot
        return [PSCustomObject]@{
            Action = 'bumped'
            Id     = [string]$existing.Entry.id
            Title  = [string]$existing.Entry.title
            Count  = [int]$existing.Entry.count
        }
    }

    $entry = New-MetraDecisionCandidateObject `
        -Title $titleText -Decision $decisionText -Why $Why -Project $Project `
        -Tags $Tags -See $See -Source $Source -Origin $Origin `
        -Confidence $Confidence -Evidence $Evidence
    $registry.candidates = @($registry.candidates) + @($entry)
    Save-MetraDecisionRegistry -Registry $registry -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        Action = 'added'
        Id     = [string]$entry.id
        Title  = [string]$entry.title
        Count  = 1
    }
}

function Promote-MetraDecisionRegistryEntry {
    <#
    .SYNOPSIS
        Promotes a candidate to confirmed. Requires why, confidence, and evidence.
    .PARAMETER ExemptId
        Confirmed id excluded from the active budget count (supersede promote-first).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IdOrTitle,
        [string]$Why,
        [string]$Confidence,
        $Evidence,
        [string]$ExemptId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $registry = Get-MetraDecisionRegistry -MetraRoot $MetraRoot
    $resolved = Resolve-MetraDecisionRegistryEntry -Registry $registry -IdOrTitle $IdOrTitle
    if (-not $resolved) {
        throw "No Decision Registry candidate matched '$IdOrTitle'. Use decisions note first."
    }
    if ($resolved.Bucket -eq 'confirmed') {
        throw ("Already confirmed: {0}" -f $resolved.Entry.id)
    }

    $entry = $resolved.Entry
    $whyText = if ($Why) { $Why } else { [string](Get-MetraProp -Object $entry -Name 'why' -Default '') }
    $confText = if ($Confidence) { $Confidence } else { [string](Get-MetraProp -Object $entry -Name 'confidence' -Default '') }
    $evIn = if ($null -ne $Evidence -and @($Evidence).Count -gt 0) {
        $Evidence
    }
    else {
        @(Get-MetraProp -Object $entry -Name 'evidence' -Default @())
    }

    $validated = Assert-MetraDecisionPromotionFields -Why $whyText -Confidence $confText -Evidence $evIn

    $probe = (@(
            [string](Get-MetraProp -Object $entry -Name 'title' -Default ''),
            [string](Get-MetraProp -Object $entry -Name 'decision' -Default ''),
            $validated.Why
        ) -join ' ')
    if (Test-MetraDecisionRegistryProductPolicyText -Text $probe) {
        throw 'Looks like every-clone Metra product policy, not local operational memory. Record product-wide policy in docs/Decisions.md instead of the Decision Registry.'
    }

    $max = [int]$registry.maxConfirmed
    if ($max -le 0) { $max = $script:MetraDecisionRegistryMaxConfirmed }
    $exempt = Normalize-MetraDecisionText $ExemptId
    $activeConfirmed = @($registry.confirmed | Where-Object {
            $status = [string](Get-MetraProp -Object $_ -Name 'status' -Default 'active')
            if ($status -ne 'active') { return $false }
            if ($exempt) {
                $rowId = [string](Get-MetraProp -Object $_ -Name 'id' -Default '')
                if ([string]::Equals($rowId, $exempt, [StringComparison]::OrdinalIgnoreCase)) {
                    return $false
                }
            }
            return $true
        })
    if ($activeConfirmed.Count -ge $max) {
        throw ("Confirmed Decision Registry budget is full ({0}). Run decisions forget <id> or supersede before promoting another." -f $max)
    }

    $now = (Get-Date).ToUniversalTime().ToString('o')
    $id = [string]$entry.id
    if (-not $id.StartsWith('d')) {
        $id = New-MetraDecisionRegistryId -Prefix 'd'
    }

    $confirmed = [PSCustomObject]@{
        id          = $id
        date        = (Get-Date).ToString('yyyy-MM-dd')
        title       = Normalize-MetraDecisionText ([string]$entry.title)
        decision    = Normalize-MetraDecisionText ([string]$entry.decision)
        why         = $validated.Why
        project     = Normalize-MetraDecisionText ([string](Get-MetraProp -Object $entry -Name 'project' -Default ''))
        tags        = @(ConvertTo-MetraDecisionTags (Get-MetraProp -Object $entry -Name 'tags' -Default @()))
        see         = @(ConvertTo-MetraDecisionEvidence (Get-MetraProp -Object $entry -Name 'see' -Default @()))
        source      = Normalize-MetraDecisionText ([string](Get-MetraProp -Object $entry -Name 'source' -Default 'operator'))
        origin      = Normalize-MetraDecisionText ([string](Get-MetraProp -Object $entry -Name 'origin' -Default 'operator'))
        confidence  = $validated.Confidence
        evidence    = @($validated.Evidence)
        status      = 'active'
        supersedes  = $null
        confirmedAt = $now
    }

    $dropId = [string]$entry.id
    $registry.candidates = @($registry.candidates | Where-Object {
            [string](Get-MetraProp -Object $_ -Name 'id' -Default '') -ne $dropId
        })
    $registry.confirmed = @($registry.confirmed) + @($confirmed)
    Save-MetraDecisionRegistry -Registry $registry -MetraRoot $MetraRoot

    return [PSCustomObject]@{
        Action    = 'promoted'
        Id        = $id
        Title     = [string]$confirmed.title
        Confirmed = @($registry.confirmed | Where-Object {
                ([string](Get-MetraProp -Object $_ -Name 'status' -Default 'active')) -eq 'active'
            }).Count
    }
}

function Remove-MetraDecisionRegistryEntry {
    <#
    .SYNOPSIS
        Forgets a candidate or confirmed decision.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IdOrTitle,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $registry = Get-MetraDecisionRegistry -MetraRoot $MetraRoot
    $resolved = Resolve-MetraDecisionRegistryEntry -Registry $registry -IdOrTitle $IdOrTitle
    if (-not $resolved) {
        throw "Nothing to forget matching '$IdOrTitle'."
    }

    $dropId = [string]$resolved.Entry.id
    if ($resolved.Bucket -eq 'candidates') {
        $registry.candidates = @($registry.candidates | Where-Object {
                [string](Get-MetraProp -Object $_ -Name 'id' -Default '') -ne $dropId
            })
    }
    else {
        $registry.confirmed = @($registry.confirmed | Where-Object {
                [string](Get-MetraProp -Object $_ -Name 'id' -Default '') -ne $dropId
            })
    }

    Save-MetraDecisionRegistry -Registry $registry -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        Action = 'forgot'
        Id     = $dropId
        Bucket = $resolved.Bucket
    }
}

function Get-MetraDecisionRegistryUtcDateTime {
    <#
    .SYNOPSIS
        Normalizes a DateTime to UTC so Kind-safe comparisons succeed under StrictMode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$Value
    )

    if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
    if ($Value.Kind -eq [DateTimeKind]::Unspecified) {
        return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc)
    }
    return $Value.ToUniversalTime()
}

function Get-MetraDecisionRegistryCandidateTimestamp {
    <#
    .SYNOPSIS
        Parses candidate updatedAt (else createdAt) as UTC DateTime, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Candidate
    )

    $updated = [string](Get-MetraProp -Object $Candidate -Name 'updatedAt' -Default '')
    $created = [string](Get-MetraProp -Object $Candidate -Name 'createdAt' -Default '')
    $stampText = if ($updated) { $updated } else { $created }
    if (-not $stampText) { return $null }
    try {
        $parsed = [datetime]::Parse($stampText, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return (Get-MetraDecisionRegistryUtcDateTime -Value $parsed)
    }
    catch {
        return $null
    }
}

function Split-MetraDecisionRegistryCandidatesByStale {
    <#
    .SYNOPSIS
        Partitions candidates into stale vs kept using candidateStaleDays (shared by review and gc).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Registry,
        [datetime]$AsOf = (Get-Date).ToUniversalTime()
    )

    $days = [int](Get-MetraProp -Object $Registry -Name 'candidateStaleDays' -Default $script:MetraDecisionRegistryStaleDays)
    if ($days -le 0) { $days = $script:MetraDecisionRegistryStaleDays }
    $asOfUtc = Get-MetraDecisionRegistryUtcDateTime -Value $AsOf
    $cutoff = $asOfUtc.AddDays(-1 * $days)
    $stale = New-Object System.Collections.Generic.List[object]
    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($Registry.candidates)) {
        $stamp = Get-MetraDecisionRegistryCandidateTimestamp -Candidate $c
        if ($null -ne $stamp -and $stamp -lt $cutoff) {
            [void]$stale.Add($c)
        }
        else {
            [void]$kept.Add($c)
        }
    }
    return [PSCustomObject]@{
        Days   = $days
        Cutoff = $cutoff
        AsOf   = $asOfUtc
        Stale  = @($stale.ToArray())
        Kept   = @($kept.ToArray())
    }
}

function Clear-MetraDecisionRegistryStaleCandidates {
    <#
    .SYNOPSIS
        Drops candidates older than candidateStaleDays without promotion.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $registry = Get-MetraDecisionRegistry -MetraRoot $MetraRoot
    $split = Split-MetraDecisionRegistryCandidatesByStale -Registry $registry
    $registry.candidates = @($split.Kept)
    Save-MetraDecisionRegistry -Registry $registry -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        Action  = 'gc'
        Removed = @($split.Stale).Count
        Kept    = @($split.Kept).Count
        Days    = [int]$split.Days
    }
}

function Get-MetraDecisionRegistryReview {
    <#
    .SYNOPSIS
        Ledger hygiene visibility (facts only; not a score). Does not mutate the ledger.
    .DESCRIPTION
        StaleCandidates uses the same cutoff rules as decisions gc. MissingWhy is unique by id.
        Gap lists are capped; counts remain full. Command hints are derived by the CLI writer only.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [ValidateRange(1, 100)]
        [int]$GapLimit = 12,
        $Registry,
        [datetime]$AsOf = (Get-Date).ToUniversalTime()
    )

    $paths = Get-MetraDecisionRegistryPaths -MetraRoot $MetraRoot
    $ledgerExists = [bool](Test-Path -LiteralPath $paths.LedgerPath)
    if ($null -eq $Registry) {
        $Registry = Get-MetraDecisionRegistry -MetraRoot $MetraRoot
        if (-not $ledgerExists) {
            return [PSCustomObject]@{
                LedgerExists           = $false
                CandidateStaleDays     = [int]$Registry.candidateStaleDays
                StaleCandidatesCount   = 0
                StaleCandidates        = @()
                SupersededCount        = 0
                Superseded             = @()
                MissingWhyCount        = 0
                MissingWhy             = @()
            }
        }
    }

    $split = Split-MetraDecisionRegistryCandidatesByStale -Registry $Registry -AsOf $AsOf
    $staleRows = @(
        @($split.Stale) |
            ForEach-Object {
                [PSCustomObject]@{
                    id    = [string](Get-MetraProp -Object $_ -Name 'id' -Default '')
                    title = [string](Get-MetraProp -Object $_ -Name 'title' -Default '')
                }
            } |
            Sort-Object id, title
    )

    $supersededRows = @(
        @($Registry.confirmed) |
            Where-Object {
                ([string](Get-MetraProp -Object $_ -Name 'status' -Default '')) -eq 'superseded'
            } |
            ForEach-Object {
                [PSCustomObject]@{
                    id    = [string](Get-MetraProp -Object $_ -Name 'id' -Default '')
                    title = [string](Get-MetraProp -Object $_ -Name 'title' -Default '')
                }
            } |
            Sort-Object id, title
    )

    $missingById = [ordered]@{}
    foreach ($bucket in @(
            [PSCustomObject]@{ Name = 'candidates'; Items = @($Registry.candidates) },
            [PSCustomObject]@{ Name = 'confirmed'; Items = @($Registry.confirmed) }
        )) {
        foreach ($row in @($bucket.Items)) {
            $why = [string](Get-MetraProp -Object $row -Name 'why' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($why)) { continue }
            $id = [string](Get-MetraProp -Object $row -Name 'id' -Default '')
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            # OrderedDictionary has Contains(key), not ContainsKey - use Keys for clarity.
            if (@($missingById.Keys) -contains $id) { continue }
            $missingById[$id] = [PSCustomObject]@{
                id     = $id
                title  = [string](Get-MetraProp -Object $row -Name 'title' -Default '')
                bucket = [string]$bucket.Name
            }
        }
    }
    $missingWhyRows = @($missingById.Values | Sort-Object id, title)

    return [PSCustomObject]@{
        LedgerExists         = $true
        CandidateStaleDays   = [int]$split.Days
        StaleCandidatesCount = $staleRows.Count
        StaleCandidates      = @($staleRows | Select-Object -First $GapLimit)
        SupersededCount      = $supersededRows.Count
        Superseded           = @($supersededRows | Select-Object -First $GapLimit)
        MissingWhyCount      = $missingWhyRows.Count
        MissingWhy           = @($missingWhyRows | Select-Object -First $GapLimit)
    }
}

function Write-MetraDecisionRegistryReview {
    <#
    .SYNOPSIS
        Host output for decision registry hygiene (facts + derived command hints).
    #>
    [CmdletBinding()]
    param(
        $Review
    )

    if (-not $Review) {
        Write-Host 'No decision registry review data.' -ForegroundColor Yellow
        return
    }

    Write-Host ('Decision registry review (visibility only; not a score)') -ForegroundColor Cyan
    if (-not $Review.LedgerExists) {
        Write-Host '  No local Decision Registry ledger yet.'
        Write-Host '  Hint: .\metra.ps1 decisions note / harvest / promote'
        return
    }

    Write-Host ("  Candidate stale days: {0}" -f $Review.CandidateStaleDays)
    Write-Host ("  Stale candidates: {0}" -f $Review.StaleCandidatesCount)
    foreach ($row in @($Review.StaleCandidates)) {
        Write-Host ("    [{0}] {1}" -f $row.id, $row.title)
    }
    Write-Host ("  Missing why: {0}" -f $Review.MissingWhyCount)
    foreach ($row in @($Review.MissingWhy)) {
        Write-Host ("    [{0}] {1} ({2})" -f $row.id, $row.title, $row.bucket)
    }
    Write-Host ("  Superseded: {0}" -f $Review.SupersededCount)
    foreach ($row in @($Review.Superseded)) {
        Write-Host ("    [{0}] {1}" -f $row.id, $row.title)
    }

    $hints = New-Object System.Collections.Generic.List[string]
    if ([int]$Review.StaleCandidatesCount -gt 0) {
        [void]$hints.Add('.\metra.ps1 decisions gc')
    }
    if ([int]$Review.MissingWhyCount -gt 0) {
        $sample = @($Review.MissingWhy) | Select-Object -First 1
        if ($sample -and $sample.bucket -eq 'candidates' -and $sample.id) {
            [void]$hints.Add((".\metra.ps1 decisions promote {0} -Why '...'" -f $sample.id))
        }
        else {
            [void]$hints.Add(".\metra.ps1 decisions promote <id> -Why '...'")
        }
    }
    if ([int]$Review.SupersededCount -gt 0) {
        $sample = @($Review.Superseded) | Select-Object -First 1
        if ($sample -and $sample.id) {
            [void]$hints.Add((".\metra.ps1 decisions forget {0}" -f $sample.id))
        }
        else {
            [void]$hints.Add('.\metra.ps1 decisions forget <id>')
        }
    }
    if ($hints.Count -gt 0) {
        Write-Host ''
        Write-Host 'Hints (operator runs these; review does not mutate):'
        foreach ($h in @($hints)) {
            Write-Host ("  {0}" -f $h)
        }
    }
}

function Search-MetraDecisionRegistry {
    <#
    .SYNOPSIS
        Token-scores confirmed (and optionally candidate) decisions.
    #>
    [CmdletBinding()]
    param(
        [string]$Query,
        [string]$Project,
        [int]$Limit = 10,
        [switch]$IncludeCandidates,
        [switch]$IncludeSuperseded,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($Limit -lt 1) { $Limit = 10 }
    $registry = Get-MetraDecisionRegistry -MetraRoot $MetraRoot
    $tokens = @()
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $tokens = @(
            ($Query.ToLowerInvariant() -split '[^a-z0-9_+]+') |
                Where-Object { $_ -and $_.Length -gt 1 } |
                Select-Object -Unique
        )
    }
    $projectFilter = Normalize-MetraDecisionText $Project
    $projectFilterLower = if ($projectFilter) { $projectFilter.ToLowerInvariant() } else { '' }

    $rows = New-Object System.Collections.Generic.List[object]
    $buckets = @(
        [PSCustomObject]@{ Name = 'confirmed'; Items = @($registry.confirmed) }
    )
    if ($IncludeCandidates) {
        $buckets += [PSCustomObject]@{ Name = 'candidates'; Items = @($registry.candidates) }
    }

    foreach ($bucket in $buckets) {
        foreach ($item in @($bucket.Items)) {
            $status = [string](Get-MetraProp -Object $item -Name 'status' -Default 'active')
            if ($bucket.Name -eq 'confirmed' -and $status -eq 'superseded' -and -not $IncludeSuperseded) {
                continue
            }

            $itemProject = [string](Get-MetraProp -Object $item -Name 'project' -Default '')
            $itemProjectLower = $itemProject.ToLowerInvariant()
            if ($projectFilterLower -and $itemProjectLower -ne $projectFilterLower) {
                continue
            }

            $hay = @(
                [string](Get-MetraProp -Object $item -Name 'title' -Default ''),
                [string](Get-MetraProp -Object $item -Name 'decision' -Default ''),
                [string](Get-MetraProp -Object $item -Name 'why' -Default ''),
                $itemProject,
                (@(Get-MetraProp -Object $item -Name 'tags' -Default @()) -join ' '),
                [string](Get-MetraProp -Object $item -Name 'source' -Default '')
            ) -join ' '
            $hayLower = $hay.ToLowerInvariant()
            $score = 0
            if ($tokens.Count -eq 0) {
                $score = 1
                if ($projectFilterLower -and $itemProjectLower -eq $projectFilterLower) {
                    $score += 5
                }
            }
            else {
                foreach ($t in $tokens) {
                    if ($hayLower.Contains($t)) { $score++ }
                }
                if ($score -le 0) { continue }
                if ($projectFilterLower -and $itemProjectLower -eq $projectFilterLower) {
                    $score += 5
                }
            }

            [void]$rows.Add([PSCustomObject]@{
                    Id         = [string](Get-MetraProp -Object $item -Name 'id' -Default '')
                    Title      = [string](Get-MetraProp -Object $item -Name 'title' -Default '')
                    Decision   = [string](Get-MetraProp -Object $item -Name 'decision' -Default '')
                    Why        = [string](Get-MetraProp -Object $item -Name 'why' -Default '')
                    Project    = $itemProject
                    Confidence = [string](Get-MetraProp -Object $item -Name 'confidence' -Default '')
                    Status     = $status
                    Origin     = [string](Get-MetraProp -Object $item -Name 'origin' -Default '')
                    Source     = [string](Get-MetraProp -Object $item -Name 'source' -Default '')
                    Evidence   = @(Get-MetraProp -Object $item -Name 'evidence' -Default @())
                    Tags       = @(Get-MetraProp -Object $item -Name 'tags' -Default @())
                    Bucket     = $bucket.Name
                    Score      = $score
                    Date       = [string](Get-MetraProp -Object $item -Name 'date' -Default '')
                })
        }
    }

    return @(
        $rows |
            Sort-Object `
                @{ Expression = { $_.Score }; Descending = $true },
                @{ Expression = { $_.Date }; Descending = $true },
                @{ Expression = { $_.Title } } |
            Select-Object -First $Limit
    )
}

function Get-MetraWhyHere {
    <#
    .SYNOPSIS
        Bounded Decision Registry explanations for a routed project (ledger only).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$Query,
        [int]$Limit = 3,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($Limit -lt 1) { $Limit = 3 }
    $projectName = Normalize-MetraDecisionText $Project
    if (-not $projectName) { return @() }

    try {
        return @(Search-MetraDecisionRegistry -Project $projectName -Query $Query -Limit $Limit -MetraRoot $MetraRoot)
    }
    catch {
        return @()
    }
}

function Format-MetraWhyHereConfidenceSuffix {
    param([string]$Confidence)
    $c = (Normalize-MetraDecisionText $Confidence).ToLowerInvariant()
    if (-not $c -or $c -eq 'high') { return '' }
    return (' ({0})' -f $c)
}

function Format-MetraWhyHereBlock {
    <#
    .SYNOPSIS
        Builds human-readable Why here / Why not lines (decision + why; confidence only if not high).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [ValidateSet('Why here?', 'Why not?')][string]$Label = 'Why here?',
        $Decisions,
        [string[]]$FavoredTokens
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $hits = @($Decisions)
    if ($hits.Count -eq 0 -and (-not $FavoredTokens -or $FavoredTokens.Count -eq 0)) {
        return @()
    }

    [void]$lines.Add(('{0} {1}' -f $Label, $Project))
    if ($Label -eq 'Why not?' -and $FavoredTokens -and $FavoredTokens.Count -gt 0) {
        [void]$lines.Add(('  Query tokens favored the primary for: {0}' -f ($FavoredTokens -join ', ')))
    }
    foreach ($d in $hits) {
        $title = [string](Get-MetraProp -Object $d -Name 'Title' -Default '')
        if (-not $title) { $title = [string](Get-MetraProp -Object $d -Name 'title' -Default '') }
        $decision = [string](Get-MetraProp -Object $d -Name 'Decision' -Default '')
        if (-not $decision) { $decision = [string](Get-MetraProp -Object $d -Name 'decision' -Default '') }
        $why = [string](Get-MetraProp -Object $d -Name 'Why' -Default '')
        if (-not $why) { $why = [string](Get-MetraProp -Object $d -Name 'why' -Default '') }
        $id = [string](Get-MetraProp -Object $d -Name 'Id' -Default '')
        if (-not $id) { $id = [string](Get-MetraProp -Object $d -Name 'id' -Default '') }
        $conf = [string](Get-MetraProp -Object $d -Name 'Confidence' -Default '')
        if (-not $conf) { $conf = [string](Get-MetraProp -Object $d -Name 'confidence' -Default '') }
        $confSuffix = Format-MetraWhyHereConfidenceSuffix -Confidence $conf
        $idPart = if ($id) { ' [{0}]' -f $id } else { '' }
        [void]$lines.Add(('  {0}{1}{2}' -f $title, $confSuffix, $idPart))
        if ($decision) {
            [void]$lines.Add(('  {0}' -f $decision))
        }
        if ($why) {
            [void]$lines.Add(('  Why: {0}' -f $why))
        }
    }
    return [string[]]@($lines.ToArray())
}

function Write-MetraWhyHere {
    <#
    .SYNOPSIS
        Writes a Why here? block to the host.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        $Decisions
    )

    $block = @(Format-MetraWhyHereBlock -Project $Project -Label 'Why here?' -Decisions $Decisions)
    foreach ($line in $block) {
        Write-Host $line
    }
}

function Write-MetraWhyNot {
    <#
    .SYNOPSIS
        Writes a Why not? runner-up block to the host.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        $Decisions,
        [string[]]$FavoredTokens
    )

    $block = @(Format-MetraWhyHereBlock -Project $Project -Label 'Why not?' -Decisions $Decisions -FavoredTokens $FavoredTokens)
    foreach ($line in $block) {
        Write-Host $line
    }
}

function Get-MetraDecisionRegistryEntry {
    <#
    .SYNOPSIS
        Returns one decision by id or exact title.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IdOrTitle,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $registry = Get-MetraDecisionRegistry -MetraRoot $MetraRoot
    $resolved = Resolve-MetraDecisionRegistryEntry -Registry $registry -IdOrTitle $IdOrTitle
    if (-not $resolved) {
        throw "No Decision Registry entry matched '$IdOrTitle'."
    }
    return [PSCustomObject]@{
        Bucket = $resolved.Bucket
        Entry  = $resolved.Entry
    }
}

function Show-MetraDecisionRegistry {
    <#
    .SYNOPSIS
        Returns a display object for the Decision Registry.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $paths = Get-MetraDecisionRegistryPaths -MetraRoot $MetraRoot
    $registry = Get-MetraDecisionRegistry -MetraRoot $MetraRoot
    $active = @($registry.confirmed | Where-Object {
            ([string](Get-MetraProp -Object $_ -Name 'status' -Default 'active')) -eq 'active'
        })
    [PSCustomObject]@{
        LedgerPath       = $paths.LedgerPath
        LedgerExists     = [bool](Test-Path -LiteralPath $paths.LedgerPath)
        MaxConfirmed     = [int]$registry.maxConfirmed
        ConfirmedCount   = $active.Count
        SupersededCount  = @($registry.confirmed | Where-Object {
                ([string](Get-MetraProp -Object $_ -Name 'status' -Default '')) -eq 'superseded'
            }).Count
        CandidateCount   = @($registry.candidates).Count
        Confirmed        = @($registry.confirmed)
        Candidates       = @($registry.candidates)
    }
}

function Set-MetraDecisionRegistrySupersede {
    <#
    .SYNOPSIS
        Marks an old confirmed decision superseded and promotes a replacement.
    .DESCRIPTION
        Promote-first: the old decision stays active until the replacement is promoted.
        Then old status and new supersedes are written in one final save.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OldId,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Decision,
        [Parameter(Mandatory)][string]$Why,
        [Parameter(Mandatory)][string]$Confidence,
        [Parameter(Mandatory)]$Evidence,
        [string]$Project = '',
        $Tags = @(),
        $See = @(),
        [string]$Source = 'operator',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $validated = Assert-MetraDecisionPromotionFields -Why $Why -Confidence $Confidence -Evidence $Evidence

    $registry = Get-MetraDecisionRegistry -MetraRoot $MetraRoot
    $old = Resolve-MetraDecisionRegistryEntry -Registry $registry -IdOrTitle $OldId
    if (-not $old -or $old.Bucket -ne 'confirmed') {
        throw "supersede requires an existing confirmed id (got '$OldId')."
    }

    $oldStatus = Get-MetraProp -Object $old.Entry -Name 'status' -Default 'active'
    if ($oldStatus -eq 'superseded') {
        throw ("Already superseded: {0}" -f $old.Entry.id)
    }

    $note = Add-MetraDecisionRegistryCandidate `
        -Title $Title -Decision $Decision -Why $validated.Why -Project $Project `
        -Tags $Tags -See $See -Source $Source -Origin operator `
        -Confidence $validated.Confidence -Evidence $validated.Evidence `
        -MetraRoot $MetraRoot

    $promoted = Promote-MetraDecisionRegistryEntry `
        -IdOrTitle $note.Id `
        -MetraRoot $MetraRoot `
        -ExemptId ([string]$old.Entry.id)

    $registry = Get-MetraDecisionRegistry -MetraRoot $MetraRoot

    $oldAgain = Resolve-MetraDecisionRegistryEntry -Registry $registry -IdOrTitle $OldId
    if (-not $oldAgain -or $oldAgain.Bucket -ne 'confirmed') {
        throw ("Replacement was promoted, but old decision could not be reloaded for supersede: {0}" -f $OldId)
    }

    $newEntry = Resolve-MetraDecisionRegistryEntry -Registry $registry -IdOrTitle $promoted.Id
    if (-not $newEntry -or $newEntry.Bucket -ne 'confirmed') {
        throw ("Replacement was promoted, but new decision could not be reloaded: {0}" -f $promoted.Id)
    }

    $oldAgain.Entry.status = 'superseded'
    $newEntry.Entry.supersedes = [string]$oldAgain.Entry.id

    Save-MetraDecisionRegistry -Registry $registry -MetraRoot $MetraRoot

    return [PSCustomObject]@{
        Action = 'superseded'
        OldId  = [string]$oldAgain.Entry.id
        NewId  = [string]$promoted.Id
        Title  = [string]$promoted.Title
    }
}

function Get-MetraDecisionRegistrySeedCatalog {
    <#
    .SYNOPSIS
        Curated operational-scar seeds for local backfill (not product policy).
    #>
    @(
        [PSCustomObject]@{
            Title = 'Start-Automation runs on datamanager only'
            Decision = 'Never run Start-Automation from the local workstation or via UNC Scripts.'
            Why = 'Jobs need the automation host profile and IWUNET\sql.admin credential store on that server.'
            Project = 'IWUDATA-Automation'
            Tags = @('etl', 'start-automation', 'datamanager')
            See = @('etsnc datamanager IWUNET\sql.admin', 'AGENTS.md')
            Source = 'IWUDATA-Automation/AGENTS.md'
            Confidence = 'high'
            Evidence = @('IWUDATA-Automation/AGENTS.md', 'Operator confirmed')
        },
        [PSCustomObject]@{
            Title = 'Scripts Jobs alphabetical; Logs newest-first'
            Decision = 'On \\datamanager\Scripts, sort Jobs alphabetically and Logs newest-first.'
            Why = 'Operators lose runs when both folders share one sort habit; logs need recency, jobs need stable names.'
            Project = 'IWUDATA-Automation'
            Tags = @('scripts', 'jobs', 'logs')
            See = @('\\datamanager\Scripts', 'AGENTS.md')
            Source = 'IWUDATA-Automation/AGENTS.md'
            Confidence = 'high'
            Evidence = @('IWUDATA-Automation/AGENTS.md')
        },
        [PSCustomObject]@{
            Title = 'Prefer TicketTracker brief over show'
            Decision = 'Prefer TicketTracker brief over show for triage.'
            Why = 'brief is plain text, truncated, with routing terms; show pulls heavy HTML.'
            Project = 'TicketTracker'
            Tags = @('ticket', 'brief')
            See = @('AGENTS.md')
            Source = 'TicketTracker/AGENTS.md'
            Confidence = 'high'
            Evidence = @('TicketTracker/AGENTS.md', 'Operator confirmed')
        },
        [PSCustomObject]@{
            Title = 'iSupport writes use post recommend resolve'
            Decision = 'Durable iSupport writes use post / recommend / resolve; note is local-only.'
            Why = 'note never reaches the requester; confusing the two loses ticket history on the shared side.'
            Project = 'TicketTracker'
            Tags = @('ticket', 'post', 'note')
            See = @('AGENTS.md')
            Source = 'TicketTracker/AGENTS.md'
            Confidence = 'high'
            Evidence = @('TicketTracker/AGENTS.md')
        },
        [PSCustomObject]@{
            Title = 'chats means Cursor transcripts'
            Decision = 'TicketTracker chats searches Cursor agent transcripts; Outlook/Teams evidence goes through M365 then cite back.'
            Why = 'Operators confuse chat CLI with Teams history; wrong tool wastes triage time.'
            Project = 'TicketTracker'
            Tags = @('chats', 'm365', 'transcripts')
            See = @('AGENTS.md', 'M365')
            Source = 'TicketTracker/AGENTS.md'
            Confidence = 'high'
            Evidence = @('TicketTracker/AGENTS.md', 'M365/AGENTS.md')
        },
        [PSCustomObject]@{
            Title = 'M365 Graph stays read-only'
            Decision = 'Use read-only Graph helpers; do not send or write mail/Teams from M365 tooling.'
            Why = 'Write actions need human intent and audit; the module is an evidence gatherer, not a mailbox agent.'
            Project = 'M365'
            Tags = @('graph', 'readonly')
            See = @('AGENTS.md')
            Source = 'M365/AGENTS.md'
            Confidence = 'high'
            Evidence = @('M365/AGENTS.md', 'Operator confirmed')
        },
        [PSCustomObject]@{
            Title = 'Orion edits stay under src with filtered catalog'
            Decision = 'Edit Solarwinds under src/ only; use Get-OrionCatalog filters; never open catalog/index.* wholesale.'
            Why = 'Full catalog dumps burn tokens and hide the alert you came for.'
            Project = 'Solarwinds'
            Tags = @('orion', 'catalog', 'src')
            See = @('Get-OrionCatalog', 'AGENTS.md')
            Source = 'Solarwinds/AGENTS.md'
            Confidence = 'high'
            Evidence = @('Solarwinds/AGENTS.md')
        },
        [PSCustomObject]@{
            Title = 'Regenerate Trivia word-search grids'
            Decision = 'Regenerate Fun Committee word-search outputs; do not hand-edit grids.'
            Why = 'Hand edits drift from the generator and break answer keys on the next run.'
            Project = 'Trivia'
            Tags = @('wordsearch', 'fun-committee')
            See = @('python src\generate_wordsearch.py')
            Source = 'Trivia/AGENTS.md'
            Confidence = 'high'
            Evidence = @('Trivia/AGENTS.md')
        },
        [PSCustomObject]@{
            Title = 'Fun Committee stays on work root'
            Decision = 'Fun Committee / Trivia work stays on the work root; open personal iCloud games only when the operator names them.'
            Why = 'Personal Bible games share puzzle vocabulary and silently steal the wrong folder.'
            Project = 'Trivia'
            Tags = @('root', 'trivia', 'personal')
            See = @('AGENTS.md')
            Source = 'Trivia/AGENTS.md'
            Confidence = 'medium'
            Evidence = @('Trivia/AGENTS.md', 'Operator confirmed')
        },
        [PSCustomObject]@{
            Title = 'Jitterbit pushes from IWU.Jitterbit folder'
            Decision = 'Push Jitterbit git changes from the IWU.Jitterbit/ remote folder, not the parent exports tree.'
            Why = 'The parent folder is not the git root; pushing there misses the remote or commits the wrong tree.'
            Project = 'Jitterbit'
            Tags = @('git', 'jitterbit')
            See = @('IWU.Jitterbit/', 'AGENTS.md')
            Source = 'Jitterbit/AGENTS.md'
            Confidence = 'high'
            Evidence = @('Jitterbit/AGENTS.md')
        },
        [PSCustomObject]@{
            Title = 'Colleague related folders need evidence'
            Decision = 'Open Colleague / DataMover / Migration / EllucianWebService siblings only when ticket or code evidence requires it.'
            Why = 'Opening the whole family burns context without improving the first routing stop.'
            Project = 'Colleague'
            Tags = @('colleague', 'related')
            See = @('AGENTS.md')
            Source = 'Colleague/AGENTS.md'
            Confidence = 'medium'
            Evidence = @('Colleague/AGENTS.md', 'Operator confirmed')
        },
        [PSCustomObject]@{
            Title = 'PBI vs Reporting ownership'
            Decision = 'Gateway inventory and MSAL work belong in PBI; SSRS/RDL ops belong in Reporting.'
            Why = 'The two stacks share "report" vocabulary but different repos, credentials, and failure modes.'
            Project = 'PBI'
            Tags = @('pbi', 'reporting', 'ssrs')
            See = @('PBI/AGENTS.md', 'Reporting/AGENTS.md')
            Source = 'PBI/AGENTS.md'
            Confidence = 'high'
            Evidence = @('PBI/AGENTS.md', 'Reporting/AGENTS.md')
        },
        [PSCustomObject]@{
            Title = 'CredentialHelper for CredSSP remoting stores'
            Decision = 'Use CredentialHelper for cred store / CredSSP helpers when Solarwinds or other remoting evidence needs it.'
            Why = 'Credential plumbing is easy to reinvent inline and harder to rotate later.'
            Project = 'CredentialHelper'
            Tags = @('credential', 'credssp')
            See = @('AGENTS.md')
            Source = 'CredentialHelper/AGENTS.md'
            Confidence = 'medium'
            Evidence = @('CredentialHelper/AGENTS.md')
        }
    )
}

function Test-MetraDecisionHarvestPathAllowed {
    param([Parameter(Mandatory)][string]$Path)

    $p = $Path.Replace('/', '\').ToLowerInvariant()
    if ($p.EndsWith('\docs\decisions.md')) { return $false }
    if ($p.Contains('\docs\operator-contract.json')) { return $false }
    if ($p.Contains('\metra-learned.local.mdc')) { return $false }
    if ($p.Contains('\solutions\')) { return $false }
    if ($p.EndsWith('\agents.md')) { return $true }
    return $false
}

function Get-MetraDecisionHarvestLineCandidates {
    param(
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$Content
    )

    $results = New-Object System.Collections.Generic.List[object]
    $rx = [regex]'^\s*[-*]\s+(.+)$'
    foreach ($line in ($Content -split '\r?\n')) {
        $m = $rx.Match($line)
        if (-not $m.Success) { continue }
        $text = Normalize-MetraDecisionText $m.Groups[1].Value
        if ($text.Length -lt 24) { continue }
        if ($text -match '(?i)^(see|example|note|todo|param|output)\b') { continue }
        if ($text -notmatch '(?i)\b(never|prefer|only|do not|don''t|must|always|avoid|require|use|run|edit|open|push|stay)\b') {
            continue
        }
        if (Test-MetraDecisionRegistryProductPolicyText -Text $text) { continue }

        $title = if ($text.Length -gt 72) { $text.Substring(0, 69) + '...' } else { $text }
        [void]$results.Add([PSCustomObject]@{
                Title      = $title
                Decision   = $text
                Why        = ''
                Project    = $ProjectName
                Tags       = @($ProjectName.ToLowerInvariant())
                See        = @('AGENTS.md')
                Source     = $SourcePath
                Origin     = 'harvest'
                Confidence = 'low'
                Evidence   = @($SourcePath)
            })
    }
    return [object[]]@($results.ToArray())
}

function Invoke-MetraDecisionRegistryHarvest {
    <#
    .SYNOPSIS
        Discovers candidate operational decisions from project AGENTS.md files. Never promotes.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [switch]$Preview,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $projects = @(Get-MetraProjects)
    if ($Name -and $Name.Count -gt 0) {
        $wanted = @($Name | ForEach-Object { $_.ToLowerInvariant() })
        $projects = @($projects | Where-Object { $wanted -contains $_.Name.ToLowerInvariant() })
    }

    $added = New-Object System.Collections.Generic.List[object]
    $skipped = 0
    $scanned = 0

    foreach ($p in $projects) {
        $agents = Join-Path $p.Path 'AGENTS.md'
        if (-not (Test-Path -LiteralPath $agents)) { continue }
        if (-not (Test-MetraDecisionHarvestPathAllowed -Path $agents)) {
            $skipped++
            continue
        }
        $scanned++
        $content = Get-Content -LiteralPath $agents -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        $rel = ('{0}/AGENTS.md' -f $p.Name)
        $found = @(Get-MetraDecisionHarvestLineCandidates -ProjectName $p.Name -SourcePath $rel -Content $content)
        foreach ($f in $found) {
            if ($Preview) {
                [void]$added.Add([PSCustomObject]@{
                        Action   = 'preview'
                        Title    = $f.Title
                        Project  = $f.Project
                        Source   = $f.Source
                        Decision = $f.Decision
                    })
                continue
            }
            $result = Add-MetraDecisionRegistryCandidate `
                -Title $f.Title -Decision $f.Decision -Why $f.Why -Project $f.Project `
                -Tags $f.Tags -See $f.See -Source $f.Source -Origin harvest `
                -Confidence $f.Confidence -Evidence $f.Evidence `
                -MetraRoot $MetraRoot
            [void]$added.Add([PSCustomObject]@{
                    Action  = $result.Action
                    Id      = $result.Id
                    Title   = $result.Title
                    Project = $f.Project
                    Source  = $f.Source
                })
        }
    }

    return [PSCustomObject]@{
        Action       = if ($Preview) { 'harvest-preview' } else { 'harvest' }
        Scanned      = $scanned
        SkippedPaths = $skipped
        Results      = [object[]]@($added.ToArray())
        Count        = $added.Count
    }
}

function Import-MetraDecisionRegistrySeedCatalog {
    <#
    .SYNOPSIS
        Notes and promotes curated operational scars into the local ledger.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$CandidatesOnly
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($seed in @(Get-MetraDecisionRegistrySeedCatalog)) {
        $note = Add-MetraDecisionRegistryCandidate `
            -Title $seed.Title -Decision $seed.Decision -Why $seed.Why -Project $seed.Project `
            -Tags $seed.Tags -See $seed.See -Source $seed.Source -Origin backfill `
            -Confidence $seed.Confidence -Evidence $seed.Evidence `
            -MetraRoot $MetraRoot

        if ($CandidatesOnly -or $note.Action -eq 'already-confirmed') {
            [void]$results.Add($note)
            continue
        }

        try {
            $promoted = Promote-MetraDecisionRegistryEntry -IdOrTitle $note.Id -MetraRoot $MetraRoot
            [void]$results.Add($promoted)
        }
        catch {
            [void]$results.Add([PSCustomObject]@{
                    Action = 'promote-failed'
                    Id     = $note.Id
                    Title  = $note.Title
                    Error  = $_.Exception.Message
                })
        }
    }

    return [PSCustomObject]@{
        Action  = 'seed'
        Count   = $results.Count
        Results = [object[]]@($results.ToArray())
    }
}

function ConvertFrom-MetraDecisionNoteArgs {
    param([string[]]$ArgsRest)

    $map = @{}
    $i = 0
    while ($i -lt $ArgsRest.Count) {
        $token = [string]$ArgsRest[$i]
        if ($token -match '^-(Title|Decision|Why|Project|Tags|See|Source|Origin|Confidence|Evidence)$') {
            $key = $Matches[1]
            $i++
            if ($i -ge $ArgsRest.Count) { break }
            $map[$key] = [string]$ArgsRest[$i]
            $i++
            continue
        }
        break
    }

    if ($map.Count -eq 0) {
        $joined = ($ArgsRest -join ' ').Trim()
        if ($joined -match '\|') {
            $parts = @($joined -split '\|', 3)
            return [PSCustomObject]@{
                Title      = Normalize-MetraDecisionText $parts[0]
                Decision   = Normalize-MetraDecisionText $(if ($parts.Count -gt 1) { $parts[1] } else { '' })
                Why        = Normalize-MetraDecisionText $(if ($parts.Count -gt 2) { $parts[2] } else { '' })
                Project    = ''
                Tags       = @()
                See        = @()
                Source     = 'operator'
                Origin     = 'operator'
                Confidence = ''
                Evidence   = @()
            }
        }
        throw 'decisions note requires -Title and -Decision, or "Title | Decision | Why".'
    }

    return [PSCustomObject]@{
        Title      = [string](Get-MetraProp -Object ([pscustomobject]$map) -Name 'Title' -Default '')
        Decision   = [string](Get-MetraProp -Object ([pscustomobject]$map) -Name 'Decision' -Default '')
        Why        = [string](Get-MetraProp -Object ([pscustomobject]$map) -Name 'Why' -Default '')
        Project    = [string](Get-MetraProp -Object ([pscustomobject]$map) -Name 'Project' -Default '')
        Tags       = [string](Get-MetraProp -Object ([pscustomobject]$map) -Name 'Tags' -Default '')
        See        = [string](Get-MetraProp -Object ([pscustomobject]$map) -Name 'See' -Default '')
        Source     = [string](Get-MetraProp -Object ([pscustomobject]$map) -Name 'Source' -Default 'operator')
        Origin     = [string](Get-MetraProp -Object ([pscustomobject]$map) -Name 'Origin' -Default 'operator')
        Confidence = [string](Get-MetraProp -Object ([pscustomobject]$map) -Name 'Confidence' -Default '')
        Evidence   = [string](Get-MetraProp -Object ([pscustomobject]$map) -Name 'Evidence' -Default '')
    }
}

function Invoke-MetraDecisionRegistryCommand {
    <#
    .SYNOPSIS
        Dispatches metra.ps1 decisions subcommands.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot),
        [string[]]$Name,
        [switch]$Preview
    )

    $sub = $Subcommand.ToLowerInvariant()
    switch ($sub) {
        'show' {
            return Show-MetraDecisionRegistry -MetraRoot $MetraRoot
        }
        'note' {
            $parsed = ConvertFrom-MetraDecisionNoteArgs -ArgsRest $ArgsRest
            $origin = Normalize-MetraDecisionText $parsed.Origin
            if (-not $origin) { $origin = 'operator' }
            if ($origin -notin @('operator', 'backfill', 'harvest')) { $origin = 'operator' }
            return Add-MetraDecisionRegistryCandidate `
                -Title $parsed.Title -Decision $parsed.Decision -Why $parsed.Why -Project $parsed.Project `
                -Tags $parsed.Tags -See $parsed.See -Source $parsed.Source -Origin $origin `
                -Confidence $parsed.Confidence -Evidence $parsed.Evidence `
                -MetraRoot $MetraRoot
        }
        'promote' {
            if (-not $ArgsRest -or $ArgsRest.Count -eq 0) {
                throw 'decisions promote requires an id or title. Optional: -Why -Confidence -Evidence'
            }
            $why = ''
            $conf = ''
            $ev = @()
            $i = 0
            $idParts = New-Object System.Collections.Generic.List[string]
            while ($i -lt $ArgsRest.Count) {
                $token = [string]$ArgsRest[$i]
                if ($token -eq '-Why' -and ($i + 1) -lt $ArgsRest.Count) { $why = [string]$ArgsRest[$i + 1]; $i += 2; continue }
                if ($token -eq '-Confidence' -and ($i + 1) -lt $ArgsRest.Count) { $conf = [string]$ArgsRest[$i + 1]; $i += 2; continue }
                if ($token -eq '-Evidence' -and ($i + 1) -lt $ArgsRest.Count) { $ev = [string]$ArgsRest[$i + 1]; $i += 2; continue }
                [void]$idParts.Add($token)
                $i++
            }
            $idKey = ($idParts -join ' ').Trim()
            if (-not $idKey) { throw 'decisions promote requires an id or title.' }
            $params = @{ IdOrTitle = $idKey; MetraRoot = $MetraRoot }
            if ($why) { $params.Why = $why }
            if ($conf) { $params.Confidence = $conf }
            if ($ev -and @($ev).Count -gt 0) { $params.Evidence = $ev }
            return Promote-MetraDecisionRegistryEntry @params
        }
        'forget' {
            $key = ($ArgsRest -join ' ').Trim()
            if (-not $key) { throw 'decisions forget requires an id or title.' }
            return Remove-MetraDecisionRegistryEntry -IdOrTitle $key -MetraRoot $MetraRoot
        }
        'search' {
            $query = ($ArgsRest -join ' ').Trim()
            return Search-MetraDecisionRegistry -Query $query -MetraRoot $MetraRoot
        }
        'get' {
            $key = ($ArgsRest -join ' ').Trim()
            if (-not $key) { throw 'decisions get requires an id or title.' }
            return Get-MetraDecisionRegistryEntry -IdOrTitle $key -MetraRoot $MetraRoot
        }
        'supersede' {
            if (-not $ArgsRest -or $ArgsRest.Count -lt 1) {
                throw 'decisions supersede requires <oldId> -Title ... -Decision ... -Why ... -Confidence ... -Evidence ...'
            }
            $oldId = [string]$ArgsRest[0]
            $rest = @()
            if ($ArgsRest.Count -gt 1) { $rest = @($ArgsRest[1..($ArgsRest.Count - 1)]) }
            $parsed = ConvertFrom-MetraDecisionNoteArgs -ArgsRest $rest
            return Set-MetraDecisionRegistrySupersede `
                -OldId $oldId -Title $parsed.Title -Decision $parsed.Decision -Why $parsed.Why `
                -Confidence $parsed.Confidence -Evidence $parsed.Evidence -Project $parsed.Project `
                -Tags $parsed.Tags -See $parsed.See -Source $parsed.Source `
                -MetraRoot $MetraRoot
        }
        'gc' {
            return Clear-MetraDecisionRegistryStaleCandidates -MetraRoot $MetraRoot
        }
        'review' {
            $rev = Get-MetraDecisionRegistryReview -MetraRoot $MetraRoot
            Write-MetraDecisionRegistryReview -Review $rev
            return $rev
        }
        'harvest' {
            $params = @{ MetraRoot = $MetraRoot; Preview = $Preview }
            if ($Name) { $params.Name = $Name }
            # Allow -Name / -Preview in ArgsRest too
            $i = 0
            $names = New-Object System.Collections.Generic.List[string]
            $previewFlag = [bool]$Preview
            while ($i -lt $ArgsRest.Count) {
                $token = [string]$ArgsRest[$i]
                if ($token -eq '-Preview') { $previewFlag = $true; $i++; continue }
                if ($token -eq '-Name' -and ($i + 1) -lt $ArgsRest.Count) {
                    foreach ($n in @([string]$ArgsRest[$i + 1] -split ',')) {
                        $nt = Normalize-MetraDecisionText $n
                        if ($nt) { [void]$names.Add($nt) }
                    }
                    $i += 2
                    continue
                }
                $i++
            }
            if ($names.Count -gt 0) { $params.Name = @($names) }
            $params.Preview = $previewFlag
            return Invoke-MetraDecisionRegistryHarvest @params
        }
        'seed' {
            $candidatesOnly = $false
            foreach ($a in @($ArgsRest)) {
                if ($a -eq '-CandidatesOnly') { $candidatesOnly = $true }
            }
            return Import-MetraDecisionRegistrySeedCatalog -MetraRoot $MetraRoot -CandidatesOnly:$candidatesOnly
        }
        default {
            throw "Unknown decisions subcommand '$Subcommand'. Use: show, note, promote, forget, search, get, supersede, gc, review, harvest, seed"
        }
    }
}
