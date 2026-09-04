# Metra Ops "Route something" - durable-home placement (recommend only).

$script:MetraPlaceMaxUploadBytes = 8MB
$script:MetraPlaceMaxMemoryItems = 80
$script:MetraPlaceUploadMaxAgeDays = 30
$script:MetraPlaceAllowedExtensions = @(
    '.txt', '.md', '.json', '.csv', '.log', '.png', '.jpg', '.jpeg', '.gif', '.webp',
    '.pdf', '.xml', '.yaml', '.yml', '.ps1', '.sql', '.html', '.htm'
)

function Get-MetraPlaceQuarantineRoot {
    [CmdletBinding()]
    param()
    $root = Join-Path $env:LOCALAPPDATA 'Metra\ops-place-quarantine'
    if (-not (Test-Path -LiteralPath $root)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($root)
    }
    return $root
}

function Get-MetraPlaceMemoryPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return (Get-MetraOpsPlacePath -MetraRoot $MetraRoot)
}

function Get-MetraPlaceHomeCatalog {
    <#
    .SYNOPSIS
        Durable homes with educational "what happens there" copy (Portfolio Operations Principles).
    #>
    [CmdletBinding()]
    param()

    return @(
        [PSCustomObject]@{
            id              = 'tickettracker'
            label           = 'TicketTracker'
            whatHappensThere = 'TicketTracker is the shared durable store for helpdesk work - brief, notes, and iSupport posts live there so the next session still has the trail.'
            draftHint       = 'Open TicketTracker, sync if needed, then brief or note the intake.'
        }
        [PSCustomObject]@{
            id              = 'decision-registry'
            label           = 'Decision Registry'
            whatHappensThere = 'Decision records are searchable portfolio memory. Future discussions can reference this choice without re-deriving why.'
            draftHint       = 'Capture as a Decision Registry candidate with a short decision + why (do not auto-promote).'
        }
        [PSCustomObject]@{
            id              = 'decisions-md'
            label           = 'Decisions.md'
            whatHappensThere = 'Decisions.md holds portfolio-wide Metra product and routing policy that should travel with the repo.'
            draftHint       = 'Draft a Decisions.md entry when the rule is product-wide, not a personal preference.'
        }
        [PSCustomObject]@{
            id              = 'occ'
            label           = 'OCC'
            whatHappensThere = 'OCC captures shared ways of working across the portfolio rather than project-specific instructions.'
            draftHint       = 'Propose an OCC guideline only after classifying the home - soft collaboration rhythm, never product policy.'
        }
        [PSCustomObject]@{
            id              = 'agents-md'
            label           = 'Project AGENTS.md'
            whatHappensThere = 'Project AGENTS.md holds runbooks and triage order that stay local to one project root.'
            draftHint       = 'Add or update that project AGENTS.md when the note is project-local operating guidance.'
        }
        [PSCustomObject]@{
            id              = 'keep-in-view'
            label           = 'Keep in view'
            whatHappensThere = 'Keep in view parks the item on Next attention so Metra keeps it visible - temporary, not a durable home.'
            draftHint       = 'Use Keep in view when you want Metra to remember it on the desk without writing a durable artifact yet.'
        }
        [PSCustomObject]@{
            id              = 'future-development'
            label           = 'Future Development'
            whatHappensThere = 'Future Development (local) is a parking lot for ideas that are not ready for a durable home.'
            draftHint       = 'Park a short note in Future Development when the home is still unclear.'
        }
    )
}

function Resolve-MetraPlaceHome {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$IdOrLabel)

    $key = $IdOrLabel.Trim()
    $catalog = Get-MetraPlaceHomeCatalog
    $hit = @($catalog | Where-Object {
            [string]$_.id -eq $key -or [string]$_.label -eq $key
        } | Select-Object -First 1)
    if ($hit) { return $hit }
    return $null
}

function Get-MetraPlaceMemory {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Get-MetraPlaceMemoryPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{ version = 1; items = @() }
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [PSCustomObject]@{ version = 1; items = @() }
        }
        $obj = $raw | ConvertFrom-Json
        $items = @($obj.items)
        return [PSCustomObject]@{
            version = 1
            items   = @($items)
        }
    }
    catch {
        return [PSCustomObject]@{ version = 1; items = @() }
    }
}

function Set-MetraPlaceMemory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Memory,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $path = Get-MetraPlaceMemoryPath -MetraRoot $MetraRoot
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $payload = [PSCustomObject]@{
        version = 1
        items   = @($Memory.items | Select-Object -First $script:MetraPlaceMaxMemoryItems)
    }
    ($payload | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8
    return $payload
}

function Add-MetraPlaceMemoryItem {
    <#
    .SYNOPSIS
        Records an operator placement confirmation or correction (local learning ledger).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Summary,
        [Parameter(Mandatory)][string]$HomeId,
        [string]$Project = '',
        [string]$Source = 'confirm',
        [string[]]$AttachmentIds = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $home = Resolve-MetraPlaceHome -IdOrLabel $HomeId
    if (-not $home) {
        throw "Unknown place home: $HomeId"
    }

    $snippet = ($Summary -replace '\s+', ' ').Trim()
    if ($snippet.Length -gt 280) { $snippet = $snippet.Substring(0, 280) }
    if ([string]::IsNullOrWhiteSpace($snippet)) {
        throw 'Summary required for place memory'
    }

    # Attachments stay in quarantine; memory keeps id pointers only (no absolute filesystem paths).
    $attachments = @(
        Get-MetraPlaceUploadMeta -Id $AttachmentIds | ForEach-Object {
            [PSCustomObject]@{
                id          = [string]$_.id
                storageKey  = [string]$_.id
                fileName    = [string]$_.fileName
                contentType = [string]$_.contentType
                size        = [int64]$_.size
            }
        }
    )

    $memory = Get-MetraPlaceMemory -MetraRoot $MetraRoot
    $entry = [PSCustomObject]@{
        id          = [guid]::NewGuid().ToString('N')
        at          = (Get-Date).ToUniversalTime().ToString('o')
        summary     = $snippet
        homeId      = [string]$home.id
        homeLabel   = [string]$home.label
        project     = $Project
        source      = $Source
        attachments = $attachments
    }
    $memory.items = @($entry) + @($memory.items)
    $null = Set-MetraPlaceMemory -Memory $memory -MetraRoot $MetraRoot
    return $entry
}

function Find-MetraPlaceSimilarMemory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Limit = 3
    )

    $memory = Get-MetraPlaceMemory -MetraRoot $MetraRoot
    $tokens = @(
        ($Text.ToLowerInvariant() -split '\W+') |
            Where-Object { $_.Length -ge 4 } |
            Select-Object -Unique
    )
    if ($tokens.Count -eq 0) { return @() }

    $scored = foreach ($item in @($memory.items)) {
        $hay = ([string]$item.summary).ToLowerInvariant()
        $hits = 0
        foreach ($t in $tokens) {
            if ($hay.Contains($t)) { $hits++ }
        }
        if ($hits -le 0) { continue }
        # Prefer denser overlap so shared words like "ticket" do not all collide equally.
        $ratio = [double]$hits / [double]$tokens.Count
        [PSCustomObject]@{
            Score     = $hits
            Ratio     = [math]::Round($ratio, 3)
            HomeId    = [string]$item.homeId
            HomeLabel = [string]$item.homeLabel
            Summary   = [string]$item.summary
            At        = [string]$item.at
        }
    }

    return @(
        $scored |
            Sort-Object @{ Expression = 'Ratio'; Descending = $true }, @{ Expression = 'Score'; Descending = $true } |
            Select-Object -First $Limit
    )
}

function Test-MetraPlacePathReference {
    <#
    .SYNOPSIS
        Returns jail-checked path refs found in free text (files or folders under Metra roots).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $pattern = '(?i)(?:[A-Za-z]:\\|\\\\)[^\s''"<>|*?]+'
    $pathMatches = [regex]::Matches($Text, $pattern)
    $found = @()
    $seen = @{}

    foreach ($m in $pathMatches) {
        $raw = $m.Value.TrimEnd('.,;:)]}')
        if ($seen.ContainsKey($raw.ToLowerInvariant())) { continue }
        $seen[$raw.ToLowerInvariant()] = $true

        $full = $null
        try { $full = [System.IO.Path]::GetFullPath($raw) } catch { continue }
        if (-not (Test-Path -LiteralPath $full)) { continue }

        $isDir = Test-Path -LiteralPath $full -PathType Container
        $openPath = if ($isDir) { $full } else { Split-Path -Parent $full }
        $jail = Resolve-MetraOpsOpenPath -Path $openPath -MetraRoot $MetraRoot
        if (-not $jail.Ok) { continue }

        $found += [PSCustomObject]@{
            path     = $full
            openPath = [string]$jail.Path
            isFile   = (-not $isDir)
        }
    }

    return @($found)
}

function Get-MetraPlaceHeuristicHome {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $t = $Text.ToLowerInvariant()

    if ($t -match '\b(ticket|isupport|helpdesk|incident|work\s*item|brief|post\s+to\s+ticket)\b' -or $t -match '\b\d{6,8}\b') {
        return 'tickettracker'
    }
    if ($t -match '\b(why we|why we chose|operational why|decision registry|scar)\b') {
        return 'decision-registry'
    }
    if ($t -match '\b(portfolio[- ]wide|product policy|routing policy|decisions\.md|persona rule)\b') {
        return 'decisions-md'
    }
    if ($t -match '\b(prefer terse|working preference|collaboration|operator contract|occ)\b') {
        return 'occ'
    }
    if ($t -match '\b(agents\.md|runbook|project[- ]local|triage order|deploy notes)\b') {
        return 'agents-md'
    }
    if ($t -match '\b(keep\s+in\s+view|hold\s+for\s+now|park\s+this|temporary)\b') {
        return 'keep-in-view'
    }
    if ($t -match '\b(later|someday|not sure|future development|backlog idea)\b') {
        return 'future-development'
    }

    return 'future-development'
}

function Get-MetraDeskPlaceRecommendation {
    <#
    .SYNOPSIS
        Recommend a durable home for free-text (+ optional attachment names). Recommend only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string[]]$AttachmentIds = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $body = ($Text -replace '\s+', ' ').Trim()
    $attachmentNames = @(
        Get-MetraPlaceUploadMeta -Id $AttachmentIds | ForEach-Object { [string]$_.fileName }
    )

    $combined = $body
    if ($attachmentNames.Count -gt 0) {
        $combined = ($combined + ' ' + ($attachmentNames -join ' ')).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($combined)) {
        return [PSCustomObject]@{
            ok               = $false
            error            = 'Describe the item or attach a file before Route something.'
            homeId           = $null
            homeLabel        = $null
            why              = @()
            whatHappensThere = $null
            nextStep         = $null
            draft            = $null
            pathRefs         = @()
            attachments      = @()
            learning         = $null
            recommendOnly    = $true
        }
    }

    $heuristicId = Get-MetraPlaceHeuristicHome -Text $combined
    $similar = @(Find-MetraPlaceSimilarMemory -Text $combined -MetraRoot $MetraRoot -Limit 3)
    $homeId = $heuristicId
    $learningNote = $null
    $confidence = 'weak'
    if ($similar.Count -gt 0) {
        $top = $similar[0]
        if ([int]$top.Score -ge 2) {
            $homeId = [string]$top.HomeId
            $learningNote = "Past similar items were stored as $($top.HomeLabel)."
            $confidence = if ([double]$top.Ratio -ge 0.5 -or [int]$top.Score -ge 3) { 'strong' } else { 'moderate' }
        }
        elseif ($similar.Count -ge 2) {
            $byHome = $similar | Group-Object HomeId | Sort-Object Count -Descending | Select-Object -First 1
            if ($byHome -and $byHome.Count -ge 2) {
                $homeId = [string]$byHome.Name
                $label = [string]$byHome.Group[0].HomeLabel
                $learningNote = "You usually place similar notes in $label."
                $confidence = 'moderate'
            }
        }
    }
    elseif ($homeId -ne 'future-development') {
        $confidence = 'moderate'
    }

    $home = Resolve-MetraPlaceHome -IdOrLabel $homeId
    $why = New-Object System.Collections.Generic.List[string]
    switch ($home.id) {
        'tickettracker' { [void]$why.Add('This looks like helpdesk or ticket work that belongs in the shared ticket trail.') }
        'decision-registry' { [void]$why.Add('This describes why a choice was made and is likely to matter again later.') }
        'decisions-md' { [void]$why.Add('This reads like portfolio-wide Metra product or routing policy.') }
        'occ' { [void]$why.Add('This appears to describe collaboration expectations rather than a single project runbook.') }
        'agents-md' { [void]$why.Add('This looks like project-local operating guidance.') }
        'keep-in-view' { [void]$why.Add('This seems temporary - keep it visible on the desk without writing a durable home yet.') }
        default { [void]$why.Add('Home is still unclear - park it where unfinished ideas wait.') }
    }
    if ($learningNote) {
        [void]$why.Insert(0, $learningNote)
    }
    if ($attachmentNames.Count -gt 0) {
        [void]$why.Add(('Staged file(s): {0}' -f ($attachmentNames -join ', ')))
    }

    $pathRefs = @(Test-MetraPlacePathReference -Text $body -MetraRoot $MetraRoot)
    $draft = @"
Recommended home: $($home.label)
Confidence: $confidence

Why:
$($why -join "`n")

What happens there:
$($home.whatHappensThere)

Next:
$($home.draftHint)
"@.Trim()

    return [PSCustomObject]@{
        ok               = $true
        homeId           = [string]$home.id
        homeLabel        = [string]$home.label
        confidence       = $confidence
        why              = @($why)
        whatHappensThere = [string]$home.whatHappensThere
        nextStep         = [string]$home.draftHint
        draft            = $draft
        pathRefs         = @($pathRefs)
        attachments      = @($AttachmentIds)
        learning         = if ($learningNote) {
            [PSCustomObject]@{ note = $learningNote; similar = @($similar) }
        }
        else { $null }
        recommendOnly    = $true
        note             = 'Recommendation only - nothing is created until you choose a next step.'
    }
}

function Save-MetraPlaceUpload {
    <#
    .SYNOPSIS
        Stages a file into the local place quarantine (Ask-class reach).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [string]$ContentType = 'application/octet-stream'
    )

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        throw 'Empty upload'
    }
    if ($Bytes.Length -gt $script:MetraPlaceMaxUploadBytes) {
        throw ("Upload exceeds {0} MB limit" -f [math]::Round($script:MetraPlaceMaxUploadBytes / 1MB, 1))
    }

    $base = [System.IO.Path]::GetFileName($FileName)
    if ([string]::IsNullOrWhiteSpace($base)) { throw 'fileName required' }
    $ext = [System.IO.Path]::GetExtension($base).ToLowerInvariant()
    if ($ext -and ($script:MetraPlaceAllowedExtensions -notcontains $ext)) {
        throw "File type not allowed: $ext"
    }

    $id = [guid]::NewGuid().ToString('N')
    $root = Get-MetraPlaceQuarantineRoot
    $safeName = ($base -replace '[^\w\.\- ]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "upload$ext" }
    # Store under randomized id only - never use the original filename for filesystem location.
    $storedExt = if ($ext) { $ext } else { '.bin' }
    $binPath = Join-Path $root "$id$storedExt"
    $metaPath = Join-Path $root "$id.json"
    [System.IO.File]::WriteAllBytes($binPath, $Bytes)
    $meta = [PSCustomObject]@{
        id          = $id
        storageKey  = $id
        fileName    = $safeName
        contentType = $ContentType
        size        = $Bytes.Length
        # path stays on the quarantine sidecar for AskImage / local readers only.
        path        = $binPath
        at          = (Get-Date).ToUniversalTime().ToString('o')
    }
    ($meta | ConvertTo-Json) | Set-Content -LiteralPath $metaPath -Encoding UTF8

    try { $null = Remove-MetraPlaceExpiredUploads -MaxAgeDays $script:MetraPlaceUploadMaxAgeDays } catch { }

    return $meta
}

function ConvertTo-MetraPlaceUploadPublicMeta {
    <#
    .SYNOPSIS
        Public upload metadata without absolute filesystem paths.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Meta)

    return [PSCustomObject]@{
        id          = [string](Get-MetraProp -Object $Meta -Name 'id' -Default '')
        storageKey  = [string](Get-MetraProp -Object $Meta -Name 'storageKey' -Default (Get-MetraProp -Object $Meta -Name 'id' -Default ''))
        fileName    = [string](Get-MetraProp -Object $Meta -Name 'fileName' -Default '')
        contentType = [string](Get-MetraProp -Object $Meta -Name 'contentType' -Default '')
        size        = [int64](Get-MetraProp -Object $Meta -Name 'size' -Default 0)
        at          = [string](Get-MetraProp -Object $Meta -Name 'at' -Default '')
    }
}

function Get-MetraPlaceUploadMeta {
    <#
    .SYNOPSIS
        Resolves quarantine upload ids to their sidecar metadata. Unknown ids are skipped.
    .PARAMETER Public
        Omit absolute path (safe for API / memory surfaces). Internal readers omit this switch.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Id = @(),
        [switch]$Public
    )

    $quarantine = Get-MetraPlaceQuarantineRoot
    foreach ($raw in @($Id)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $safe = ($raw -replace '[^a-zA-Z0-9_-]', '')
        if (-not $safe) { continue }
        $metaPath = Join-Path $quarantine "$safe.json"
        if (-not (Test-Path -LiteralPath $metaPath)) { continue }
        try {
            $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($Public) {
                ConvertTo-MetraPlaceUploadPublicMeta -Meta $meta
            }
            else {
                $meta
            }
        }
        catch { }
    }
}

function Remove-MetraPlaceExpiredUploads {
    <#
    .SYNOPSIS
        Deletes quarantine upload sidecars (and binaries) older than MaxAgeDays.
    .DESCRIPTION
        Place uploads are temporary staging, not durable portfolio storage. Default retention
        is 30 days. Safe to re-run; unknown/corrupt sidecars are skipped.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [int]$MaxAgeDays = $(if ($script:MetraPlaceUploadMaxAgeDays) { [int]$script:MetraPlaceUploadMaxAgeDays } else { 30 })
    )

    if ($MaxAgeDays -lt 1) {
        throw "MaxAgeDays must be >= 1 (got $MaxAgeDays)"
    }

    $root = Join-Path $env:LOCALAPPDATA 'Metra\ops-place-quarantine'
    if (-not (Test-Path -LiteralPath $root)) {
        return [PSCustomObject]@{
            Ok      = $true
            Removed = 0
            Kept    = 0
            MaxAgeDays = $MaxAgeDays
        }
    }

    $cutoff = [datetime]::UtcNow.AddDays(-1 * $MaxAgeDays)
    $removed = 0
    $kept = 0
    foreach ($metaFile in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $meta = $null
        try {
            $meta = Get-Content -LiteralPath $metaFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            continue
        }

        $stamp = $null
        $atRaw = [string](Get-MetraProp -Object $meta -Name 'at' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($atRaw)) {
            try { $stamp = [datetime]::Parse($atRaw, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() } catch { }
        }
        if ($null -eq $stamp) {
            $stamp = $metaFile.LastWriteTimeUtc
        }
        if ($stamp -gt $cutoff) {
            $kept++
            continue
        }

        $id = [string](Get-MetraProp -Object $meta -Name 'id' -Default ([System.IO.Path]::GetFileNameWithoutExtension($metaFile.Name)))
        $binPath = [string](Get-MetraProp -Object $meta -Name 'path' -Default '')
        if ($PSCmdlet.ShouldProcess($metaFile.FullName, 'Remove expired Place quarantine upload')) {
            $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
            $safeBin = $false
            if (-not [string]::IsNullOrWhiteSpace($binPath)) {
                try {
                    $binFull = [System.IO.Path]::GetFullPath($binPath)
                    if ($binFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -and
                        (Test-Path -LiteralPath $binFull)) {
                        Remove-Item -LiteralPath $binFull -Force -ErrorAction SilentlyContinue
                        $safeBin = $true
                    }
                }
                catch { }
            }
            if (-not $safeBin) {
                foreach ($extra in @(Get-ChildItem -LiteralPath $root -Filter "$id*" -File -ErrorAction SilentlyContinue)) {
                    if ($extra.Extension -eq '.json') { continue }
                    Remove-Item -LiteralPath $extra.FullName -Force -ErrorAction SilentlyContinue
                }
            }
            Remove-Item -LiteralPath $metaFile.FullName -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }

    return [PSCustomObject]@{
        Ok         = $true
        Removed    = $removed
        Kept       = $kept
        MaxAgeDays = $MaxAgeDays
    }
}

function Add-MetraAttentionKeepInView {
    <#
    .SYNOPSIS
        Creates an operator-sourced attention item already in held (Keep in view) state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Summary,
        [string]$Project = 'Metra',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $content = ($Summary -replace '\s+', ' ').Trim()
    if ($content.Length -gt 400) { $content = $content.Substring(0, 400) }
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw 'Summary required for Keep in view'
    }

    $kind = 'place'
    $key = Get-MetraAttentionKey -Project $Project -Kind $kind -Content $content
    $sig = Get-MetraAttentionEvidenceSignature -Kind $kind -Content $content -Command ''
    $nowIso = (Get-Date).ToString('o')

    $memory = Get-MetraAttentionMemory -MetraRoot $MetraRoot
    $existing = @($memory.items) | Where-Object { [string]$_.key -eq $key } | Select-Object -First 1
    if ($existing) {
        $null = Invoke-MetraAttentionMutation -Key $key -Action hold -MetraRoot $MetraRoot
        return $key
    }

    $item = [PSCustomObject]@{
        key               = $key
        project           = $Project
        kind              = $kind
        source            = 'operator'
        content           = $content
        command           = ''
        evidenceSignature = $sig
        state             = 'held'
        confidence        = 'fresh'
        firstSeenAt       = $nowIso
        lastSeenAt        = $nowIso
        lastScanMode      = 'quick'
        notRecheckedSince = $null
        snoozedUntil      = $null
        closedAt          = $null
        closedBy          = ''
        note              = 'Keep in view from Route something'
        events            = @()
    }
    $item = Add-MetraAttentionEvent -Item $item -Type 'held' -Note 'place keep-in-view'
    $memory.items = @($item) + @($memory.items)
    $null = Set-MetraAttentionMemory -Memory $memory -MetraRoot $MetraRoot
    return $key
}

function Invoke-MetraPlaceConfirm {
    <#
    .SYNOPSIS
        Operator affirms a recommendation - records learning; optional Keep in view and/or Save for portfolio (Capture).
        Never auto-creates durable tracked homes. Keep in view != Save for portfolio.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$HomeId,
        [switch]$KeepInView,
        [switch]$SaveForPortfolio,
        [string[]]$AttachmentIds = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $entry = Add-MetraPlaceMemoryItem -Summary $Text -HomeId $HomeId -Source 'confirm' -AttachmentIds $AttachmentIds -MetraRoot $MetraRoot
    $attachments = @($entry.attachments)
    $attentionKey = $null
    if ($KeepInView -or $HomeId -eq 'keep-in-view') {
        $keepSummary = $Text
        if ($attachments.Count -gt 0) {
            $keepSummary = ('{0} [{1}]' -f $Text, (@($attachments | ForEach-Object { $_.fileName }) -join ', '))
        }
        $attentionKey = Add-MetraAttentionKeepInView -Summary $keepSummary -MetraRoot $MetraRoot
    }

    $captureId = $null
    if ($SaveForPortfolio) {
        $cap = Add-MetraCaptureFromPlace `
            -Text $Text `
            -HomeId $HomeId `
            -PlaceId ([string]$entry.id) `
            -AttachmentIds @($AttachmentIds) `
            -MetraRoot $MetraRoot
        $captureId = [string]$cap.id
    }

    $note = 'Recorded for learning. Durable homes are not created automatically - Keep in view parks on Attention; Save for portfolio creates a Capture candidate.'
    if ($attachments.Count -gt 0) {
        $note = ('{0} Linked file(s) stay in quarantine: {1}.' -f $note, (@($attachments | ForEach-Object { $_.fileName }) -join ', '))
    }
    if ($captureId) {
        $note = ('{0} Capture id: {1}.' -f $note, $captureId)
    }

    return [PSCustomObject]@{
        ok            = $true
        memoryId      = [string]$entry.id
        homeId        = [string]$entry.homeId
        attachments   = $attachments
        attentionKey  = $attentionKey
        captureId     = $captureId
        recommendOnly = $true
        note          = $note
    }
}

function Invoke-MetraPlaceCorrect {
    <#
    .SYNOPSIS
        Operator correction ("This belongs in...") - Decision Registry candidate + place memory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$HomeId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $home = Resolve-MetraPlaceHome -IdOrLabel $HomeId
    if (-not $home) { throw "Unknown place home: $HomeId" }

    $entry = Add-MetraPlaceMemoryItem -Summary $Text -HomeId $home.id -Source 'correct' -MetraRoot $MetraRoot

    $title = ("Route correction: {0}" -f $home.label)
    $snippet = ($Text -replace '\s+', ' ').Trim()
    if ($snippet.Length -gt 120) { $snippet = $snippet.Substring(0, 120) }
    $added = Add-MetraDecisionRegistryCandidate `
        -Title $title `
        -Decision ("This belongs in {0}." -f $home.label) `
        -Why ("Operator correction from Ops Route/Ask. Intake: {0}" -f $snippet) `
        -Tags @('place', 'correction', 'ops') `
        -Source 'ops-place' `
        -Origin operator `
        -MetraRoot $MetraRoot

    return [PSCustomObject]@{
        ok             = $true
        memoryId       = [string]$entry.id
        homeId         = [string]$home.id
        homeLabel      = [string]$home.label
        decisionId     = [string](Get-MetraProp -Object $added -Name 'Id' -Default '')
        decisionAction = [string](Get-MetraProp -Object $added -Name 'Action' -Default '')
        note           = 'Saved as a Decision Registry candidate and place-memory correction. Not auto-promoted.'
    }
}

function Test-MetraAskShowWhere {
    <#
    .SYNOPSIS
        True when Ask should surface a quiet Where chip (weak / ambiguous / home fallback).
        Chat lane turns never show Where (secretary path - no dispatch theater).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Handoff,
        [string]$Lane = '',
        [string]$LaneReason = ''
    )

    if (-not $Handoff) { return $false }

    $laneVal = $Lane
    if ([string]::IsNullOrWhiteSpace($laneVal)) {
        $laneVal = [string](Get-MetraProp -Object $Handoff -Name 'lane' -Default '')
    }
    $reasonVal = $LaneReason
    if ([string]::IsNullOrWhiteSpace($reasonVal)) {
        $reasonVal = [string](Get-MetraProp -Object $Handoff -Name 'chatLaneReason' -Default '')
    }

    $chatReasons = @(
        'social_greeting', 'personal_observation', 'capture_intent',
        'adequate_route_thin_evidence', 'sparse_intake_clarify',
        'authority_requires_confirm', 'high_intent_no_route'
    )
    if ($laneVal -eq 'chat') { return $false }
    if ($reasonVal -in $chatReasons) { return $false }

    $kind = [string](Get-MetraProp -Object $Handoff -Name 'kind' -Default '')
    if ($kind -in @('greeting', 'observation', 'park')) { return $false }
    if ([bool](Get-MetraProp -Object $Handoff -Name 'ambiguous' -Default $false)) { return $true }
    $score = [int](Get-MetraProp -Object $Handoff -Name 'score' -Default 0)
    if ($score -lt 2) { return $true }
    $where = [string](Get-MetraProp -Object $Handoff -Name 'where' -Default '')
    $home = Get-MetraHomeDestinationName
    if ($where -eq $home) { return $true }
    return $false
}

