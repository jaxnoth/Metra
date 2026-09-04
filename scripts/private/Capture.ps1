# Capture Inbox - thin portfolio intake that references Journal / Place evidence.
# Never auto-loaded into routing or Ask prompts. derivedFrom is immutable after create.

function Get-MetraCaptureLedgerPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return Get-MetraOpsCapturePath -MetraRoot $MetraRoot
}

function Get-MetraCaptureSchemaVersion {
    return 1
}

function Get-MetraCaptureLedger {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Limit = 40,
        [ValidateSet('candidate', 'promoted', 'dismissed', 'all')]
        [string]$Status = 'all'
    )

    $path = Get-MetraCaptureLedgerPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
        $items = @()
        if ($raw -is [PSCustomObject] -and $raw.PSObject.Properties.Name -contains 'items') {
            $items = @($raw.items)
        }
        elseif ($raw -is [System.Array]) {
            $items = @($raw)
        }
        # Newest first by timestamp - do not rely on file write order alone.
        $items = @(
            $items | Sort-Object {
                $at = [string](Get-MetraProp -Object $_ -Name 'at' -Default '')
                try {
                    [datetime]::Parse($at, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                }
                catch {
                    [datetime]::MinValue
                }
            } -Descending
        )
        if ($Status -ne 'all') {
            $items = @($items | Where-Object { [string](Get-MetraProp -Object $_ -Name 'status' -Default '') -eq $Status })
        }
        return @($items | Select-Object -First $Limit)
    }
    catch {
        return @()
    }
}

function Save-MetraCaptureLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $path = Get-MetraCaptureLedgerPath -MetraRoot $MetraRoot
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $payload = [ordered]@{
        schemaVersion = Get-MetraCaptureSchemaVersion
        items         = @($Items | Select-Object -First 80)
    }
    $tmp = "$path.tmp"
    [System.IO.File]::WriteAllText($tmp, (($payload | ConvertTo-Json -Depth 10) + "`r`n"))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Format-MetraCaptureMarkdownSummary {
    <#
    .SYNOPSIS
        Flatten multiline capture summaries for Markdown stubs (single line, length-capped).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Summary,
        [int]$MaxLength = 160
    )

    $safe = ([string]$Summary -replace '[\r\n]+', ' ').Trim()
    if ($MaxLength -gt 0 -and $safe.Length -gt $MaxLength) {
        $safe = $safe.Substring(0, $MaxLength).TrimEnd() + '...'
    }
    return $safe
}

function New-MetraCaptureDerivedFrom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('askTurn', 'routeSomething', 'manual')]
        [string]$Type,
        [string]$SessionId,
        [string]$TurnId,
        [string]$PlaceId,
        [string[]]$AttachmentIds = @()
    )

    switch ($Type) {
        'askTurn' {
            return [PSCustomObject]@{
                type      = 'askTurn'
                sessionId = [string]$SessionId
                turnId    = [string]$TurnId
            }
        }
        'routeSomething' {
            return [PSCustomObject]@{
                type          = 'routeSomething'
                placeId       = [string]$PlaceId
                attachmentIds = @($AttachmentIds | ForEach-Object { [string]$_ } | Where-Object { $_ })
            }
        }
        default {
            return [PSCustomObject]@{ type = 'manual' }
        }
    }
}

function Test-MetraLocalAuthority {
    <#
    .SYNOPSIS
        Write-boundary authority check for project-tree Capture promotes.
        Proposal may flag requiresHostSession; only promote enforces this.
    #>
    [CmdletBinding()]
    param(
        [bool]$HasLocalAuthority = $true
    )
    return [bool]$HasLocalAuthority
}

function Test-MetraCaptureRegisteredProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $home = Get-MetraHomeDestinationName
    foreach ($p in @(Get-MetraProjects)) {
        if ([string]$p.Name -ieq $Name) { return $p }
    }
    try {
        $reg = Get-MetraProjectRegistry
        $row = @($reg.projects | Where-Object { [string]$_.name -ieq $Name } | Select-Object -First 1)
        if ($row) {
            # Registry-only (not on disk) - still refuse invent but cannot write TODO without path
            return [PSCustomObject]@{
                Name = [string]$row.name
                Path = $null
                Root = $null
            }
        }
    }
    catch { }
    if ($Name -ieq $home) {
        return [PSCustomObject]@{ Name = $home; Path = $MetraRoot; Root = 'metra' }
    }
    return $null
}

function Get-MetraCaptureCrossRootFlags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ProjectInfo,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $homeName = Get-MetraHomeDestinationName
    $metraProj = @(Get-MetraProjects | Where-Object { [string]$_.Name -ieq $homeName } | Select-Object -First 1)
    $metraRootLabel = if ($metraProj) { [string]$metraProj.Root } else { 'work' }
    $projRoot = [string](Get-MetraProp -Object $ProjectInfo -Name 'Root' -Default '')
    $requiresCrossRoot = $false
    if ($projRoot -and $metraRootLabel -and ($projRoot -ine $metraRootLabel)) {
        $requiresCrossRoot = $true
    }
    elseif ($ProjectInfo.Path -and $MetraRoot) {
        # Path-boundary containment (not StartsWith) - avoids C:\Projects\_meta2 matching \_meta.
        $underMetra = Test-MetraPathWithinRoot -Path ([string]$ProjectInfo.Path) -Root $MetraRoot
        if (-not $underMetra) {
            if ($projRoot -and $metraRootLabel -and ($projRoot -ieq $metraRootLabel)) {
                $requiresCrossRoot = $false
            }
            else {
                $requiresCrossRoot = $true
            }
        }
    }
    return [PSCustomObject]@{
        requiresCrossRoot   = $requiresCrossRoot
        requiresHostSession = $true
        rootLabel           = $(if ($projRoot) { $projRoot } else { [string]$ProjectInfo.Name })
    }
}

function New-MetraCaptureSuggestedTargetObject {
    param(
        [string]$Home,
        [string]$Project,
        [string]$Confidence = 'usable',
        [string]$Reason = '',
        [bool]$RequiresCrossRoot = $false,
        [bool]$RequiresHostSession = $false,
        [string]$RootLabel = ''
    )
    return [PSCustomObject]@{
        suggestedHome       = $Home
        suggestedProject    = $Project
        confidence          = $Confidence
        reason              = $Reason
        rootLabel           = $(if ($RootLabel) { $RootLabel } else { $Project })
        requiresCrossRoot   = $RequiresCrossRoot
        requiresHostSession = $RequiresHostSession
    }
}

function Resolve-MetraCaptureSuggestedTarget {
    <#
    .SYNOPSIS
        Registry-aware Capture home/project suggestion (Ladder 2b).
    #>
    [CmdletBinding()]
    param(
        [string]$Text,
        [string]$Where,
        [string]$HomeId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $homeName = Get-MetraHomeDestinationName
    $whereText = if (-not [string]::IsNullOrWhiteSpace($HomeId)) { $HomeId } else { $Where }
    $blob = (('{0} {1}' -f $Text, $whereText) -replace '\s+', ' ').Trim()
    $blobLower = $blob.ToLowerInvariant()

    # 1) Metra portfolio homes
    if ($blobLower -match '\b(always do|prefer terse|collaboration rhythm|operator contract|\bocc\b)\b') {
        return New-MetraCaptureSuggestedTargetObject -Home 'OCC' -Project $homeName -Confidence 'high' -Reason 'occ-regex'
    }
    if ($blobLower -match '\b(why we chose|decision registry|operational scar)\b') {
        return New-MetraCaptureSuggestedTargetObject -Home 'DecisionRegistry' -Project $homeName -Confidence 'high' -Reason 'decision-registry-regex'
    }
    if ($blobLower -match '\b(future development|future-dev)\b' -or
        ($whereText -ieq $homeName -and $blobLower -match '\b(metadata audit|should (add|build|ship))\b')) {
        return New-MetraCaptureSuggestedTargetObject -Home 'FutureDevelopment' -Project $homeName -Confidence 'high' -Reason 'future-dev-regex'
    }

    # 2) Registry / routing scores
    $scored = @()
    try {
        $q = if ($blob) { $blob } else { [string]$whereText }
        if ($q) { $scored = @(Get-MetraScoredRoutingProjects -Query $q -Limit 10) }
    }
    catch { $scored = @() }

    $topNonTt = $null
    foreach ($s in $scored) {
        if ([string]$s.Name -ine 'TicketTracker') { $topNonTt = $s; break }
    }
    $whereProj = $null
    if ($whereText) {
        $whereProj = Test-MetraCaptureRegisteredProject -Name $whereText -MetraRoot $MetraRoot
    }

    # 3) Strong TicketTracker (not greedy)
    $strongTicketId = [bool]($blob -match '\b\d{6,8}\b')
    $helpdeskVocab = [bool]($blobLower -match '\b(isupport|helpdesk|incident)\b' `
            -or $blobLower -match '\b(ticket tracker|tickettracker)\b')
    $strongNonTt = $topNonTt -and [int]$topNonTt.Score -ge 2
    if ($strongTicketId -or ($helpdeskVocab -and -not $strongNonTt)) {
        return New-MetraCaptureSuggestedTargetObject -Home 'TicketTracker' -Project 'TicketTracker' `
            -Confidence 'usable' -Reason 'strong-ticket'
    }

    # 4) Registered non-Metra project
    $pick = $null
    $pickScorePath = $null
    if ($whereProj -and [string]$whereProj.Name -ine $homeName -and [string]$whereProj.Name -ine 'TicketTracker') {
        $pick = $whereProj
    }
    elseif ($topNonTt -and [string]$topNonTt.Name -ine $homeName) {
        $pick = Test-MetraCaptureRegisteredProject -Name ([string]$topNonTt.Name) -MetraRoot $MetraRoot
        if (-not $pick) {
            $pick = [PSCustomObject]@{
                Name = [string]$topNonTt.Name
                Path = [string]$topNonTt.Path
                Root = [string]$topNonTt.Root
            }
        }
        $pickScorePath = $topNonTt
    }

    if ($pick -and [string]$pick.Name -and [string]$pick.Name -ine $homeName) {
        if (-not $pick.Path -and $pickScorePath) {
            $pick = [PSCustomObject]@{
                Name = [string]$pick.Name
                Path = [string]$pickScorePath.Path
                Root = [string]$pickScorePath.Root
            }
        }
        $flags = Get-MetraCaptureCrossRootFlags -ProjectInfo $pick -MetraRoot $MetraRoot
        $home = 'ProjectBacklog'
        $reason = 'registry-routing'
        if ($blobLower -match '\b(agents\.md|playbook|runbook)\b') {
            $home = 'ProjectAgents'
            $reason = 'agents-playbook-language'
        }
        return New-MetraCaptureSuggestedTargetObject -Home $home -Project ([string]$pick.Name) `
            -Confidence 'usable' -Reason $reason `
            -RequiresCrossRoot:([bool]$flags.requiresCrossRoot) -RequiresHostSession:$true `
            -RootLabel ([string]$flags.rootLabel)
    }

    # 5) Fallback
    return New-MetraCaptureSuggestedTargetObject -Home 'FutureDevelopment' -Project $homeName `
        -Confidence 'thin' -Reason 'metra-fallback'
}

function Resolve-MetraCaptureSuggestedHome {
    <#
    .SYNOPSIS
        Compatibility wrapper - returns suggestedHome + suggestedProject (v1 shape).
    #>
    [CmdletBinding()]
    param(
        [string]$Text,
        [string]$Where,
        [string]$HomeId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $t = Resolve-MetraCaptureSuggestedTarget -Text $Text -Where $Where -HomeId $HomeId -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        suggestedHome       = [string]$t.suggestedHome
        suggestedProject    = [string]$t.suggestedProject
        confidence          = [string]$t.confidence
        reason              = [string]$t.reason
        rootLabel           = [string]$t.rootLabel
        requiresCrossRoot   = [bool]$t.requiresCrossRoot
        requiresHostSession = [bool]$t.requiresHostSession
    }
}

function Add-MetraCaptureItem {
    <#
    .SYNOPSIS
        Creates a thin Capture Inbox candidate. derivedFrom is set once and never rewritten by normal APIs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Summary,
        [string]$Body,
        [Parameter(Mandatory)][ValidateSet('ask', 'place', 'manual')]
        [string]$Source,
        [Parameter(Mandatory)]$DerivedFrom,
        [string]$SuggestedHome,
        [string]$SuggestedProject,
        [string]$Origin,
        [string]$Client,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $existing = @(Get-MetraCaptureLedger -MetraRoot $MetraRoot -Limit 80 -Status all)
    $guess = Resolve-MetraCaptureSuggestedHome -Text $Summary -Where $SuggestedProject -HomeId $SuggestedHome -MetraRoot $MetraRoot
    $home = if (-not [string]::IsNullOrWhiteSpace($SuggestedHome)) { $SuggestedHome } else { [string]$guess.suggestedHome }
    $project = if (-not [string]::IsNullOrWhiteSpace($SuggestedProject)) { $SuggestedProject } else { [string]$guess.suggestedProject }

    $entry = [PSCustomObject]@{
        id               = [guid]::NewGuid().ToString('N')
        at               = (Get-Date).ToString('o')
        status           = 'candidate'
        summary          = $Summary.Trim()
        body             = $(if ([string]::IsNullOrWhiteSpace($Body)) { $null } else { $Body.Trim() })
        source           = $Source
        derivedFrom      = $DerivedFrom
        suggestedHome    = $home
        suggestedProject = $project
        origin           = $(if ([string]::IsNullOrWhiteSpace($Origin)) { $null } else { $Origin })
        client           = $(if ([string]::IsNullOrWhiteSpace($Client)) { $null } else { $Client })
        promoted         = $null
    }
    $items = @($entry) + @($existing)
    Save-MetraCaptureLedger -Items $items -MetraRoot $MetraRoot
    return $entry
}

function Update-MetraCaptureItem {
    <#
    .SYNOPSIS
        Updates framing fields on a capture. Rejects derivedFrom mutation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Summary,
        [string]$Body,
        [string]$SuggestedHome,
        [string]$SuggestedProject,
        [ValidateSet('candidate', 'promoted', 'dismissed')]
        [string]$Status,
        [object]$DerivedFrom,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($PSBoundParameters.ContainsKey('DerivedFrom')) {
        throw 'derivedFrom is immutable after capture creation. Only migration/repair tooling may rewrite lineage.'
    }

    $items = @(Get-MetraCaptureLedger -MetraRoot $MetraRoot -Limit 80 -Status all)
    $found = $false
    $updated = foreach ($item in $items) {
        if ([string]$item.id -ne $Id) {
            $item
            continue
        }
        $found = $true
        if ($PSBoundParameters.ContainsKey('Summary') -and -not [string]::IsNullOrWhiteSpace($Summary)) {
            $item.summary = $Summary.Trim()
        }
        if ($PSBoundParameters.ContainsKey('Body')) {
            $item.body = $(if ([string]::IsNullOrWhiteSpace($Body)) { $null } else { $Body.Trim() })
        }
        if ($PSBoundParameters.ContainsKey('SuggestedHome') -and -not [string]::IsNullOrWhiteSpace($SuggestedHome)) {
            $item.suggestedHome = $SuggestedHome.Trim()
        }
        if ($PSBoundParameters.ContainsKey('SuggestedProject') -and -not [string]::IsNullOrWhiteSpace($SuggestedProject)) {
            $item.suggestedProject = $SuggestedProject.Trim()
        }
        if ($PSBoundParameters.ContainsKey('Status')) {
            $item.status = $Status
        }
        $item
    }
    if (-not $found) {
        throw "Capture not found: $Id"
    }
    Save-MetraCaptureLedger -Items $updated -MetraRoot $MetraRoot
    return @($updated | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1)
}

function Dismiss-MetraCaptureItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    return Update-MetraCaptureItem -Id $Id -Status dismissed -MetraRoot $MetraRoot
}

function Add-MetraCaptureFromAskTurn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TurnId,
        [string]$SessionId,
        [string]$Summary,
        [string]$Body,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $turns = @(Get-MetraDeskAskLog -MetraRoot $MetraRoot -Limit 100)
    $turn = $turns | Where-Object { [string]$_.id -eq $TurnId } | Select-Object -First 1
    if (-not $turn) {
        throw "Ask journal turn not found: $TurnId"
    }

    $prompt = [string](Get-MetraProp -Object $turn -Name 'prompt' -Default '')
    $where = [string](Get-MetraProp -Object (Get-MetraProp -Object $turn -Name 'handoff' -Default $null) -Name 'where' -Default 'Metra')
    $sum = if (-not [string]::IsNullOrWhiteSpace($Summary)) { $Summary } else {
        $t = ($prompt -replace '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { $t = 'Ask capture' }
        if ($t.Length -gt 120) { $t.Substring(0, 120) } else { $t }
    }
    $sess = if (-not [string]::IsNullOrWhiteSpace($SessionId)) { $SessionId } else {
        [string](Get-MetraProp -Object $turn -Name 'sessionId' -Default '')
    }
    $derived = New-MetraCaptureDerivedFrom -Type askTurn -SessionId $sess -TurnId $TurnId
    $guess = Resolve-MetraCaptureSuggestedHome -Text $sum -Where $where -MetraRoot $MetraRoot
    return Add-MetraCaptureItem `
        -Summary $sum `
        -Body $Body `
        -Source ask `
        -DerivedFrom $derived `
        -SuggestedHome ([string]$guess.suggestedHome) `
        -SuggestedProject ([string]$guess.suggestedProject) `
        -Origin ([string](Get-MetraProp -Object $turn -Name 'origin' -Default $null)) `
        -Client ([string](Get-MetraProp -Object $turn -Name 'client' -Default $null)) `
        -MetraRoot $MetraRoot
}

function Add-MetraCaptureFromPlace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$HomeId,
        [string]$PlaceId,
        [string[]]$AttachmentIds = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $sum = ($Text -replace '\s+', ' ').Trim()
    if ($sum.Length -gt 120) { $sum = $sum.Substring(0, 120) }
    $derived = New-MetraCaptureDerivedFrom -Type routeSomething -PlaceId $PlaceId -AttachmentIds $AttachmentIds
    $guess = Resolve-MetraCaptureSuggestedHome -Text $Text -HomeId $HomeId -MetraRoot $MetraRoot
    return Add-MetraCaptureItem `
        -Summary $sum `
        -Body $null `
        -Source place `
        -DerivedFrom $derived `
        -SuggestedHome ([string]$guess.suggestedHome) `
        -SuggestedProject ([string]$guess.suggestedProject) `
        -MetraRoot $MetraRoot
}

function Propose-MetraCaptureSplit {
    <#
    .SYNOPSIS
        Propose up to 5 Capture rows from an Ask turn and/or session. Never writes the ledger.
    #>
    [CmdletBinding()]
    param(
        [string]$TurnId,
        [string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ([string]::IsNullOrWhiteSpace($TurnId) -and [string]::IsNullOrWhiteSpace($SessionId)) {
        throw 'Propose-MetraCaptureSplit requires TurnId and/or SessionId.'
    }

    $turns = @(Get-MetraDeskAskLog -MetraRoot $MetraRoot -Limit 100)
    $primary = $null
    if ($TurnId) {
        $primary = $turns | Where-Object { [string]$_.id -eq $TurnId } | Select-Object -First 1
        if (-not $primary) { throw "Ask journal turn not found: $TurnId" }
    }
    $sess = $SessionId
    if ([string]::IsNullOrWhiteSpace($sess) -and $primary) {
        $sess = [string](Get-MetraProp -Object $primary -Name 'sessionId' -Default '')
    }

    $seeds = [System.Collections.Generic.List[object]]::new()
    if ($primary) {
        $prompt = [string](Get-MetraProp -Object $primary -Name 'prompt' -Default '')
        $where = [string](Get-MetraProp -Object (Get-MetraProp -Object $primary -Name 'handoff' -Default $null) -Name 'where' -Default '')
        [void]$seeds.Add([PSCustomObject]@{
                Text    = $prompt
                Where   = $where
                TurnId  = [string]$primary.id
                Session = $sess
            })
    }

    if ($sess) {
        $sessionTurns = @($turns | Where-Object { [string](Get-MetraProp -Object $_ -Name 'sessionId' -Default '') -eq $sess } |
                Select-Object -First 20)
        $seenWhere = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($t in $sessionTurns) {
            $w = [string](Get-MetraProp -Object (Get-MetraProp -Object $t -Name 'handoff' -Default $null) -Name 'where' -Default '')
            if ([string]::IsNullOrWhiteSpace($w)) { continue }
            if (-not $seenWhere.Add($w)) { continue }
            $p = [string](Get-MetraProp -Object $t -Name 'prompt' -Default '')
            [void]$seeds.Add([PSCustomObject]@{
                    Text    = $p
                    Where   = $w
                    TurnId  = [string]$t.id
                    Session = $sess
                })
        }
    }

    if ($seeds.Count -eq 0) {
        $guess = Resolve-MetraCaptureSuggestedTarget -Text 'Ask capture' -Where (Get-MetraHomeDestinationName) -MetraRoot $MetraRoot
        return @(
            [PSCustomObject]@{
                proposalId          = [guid]::NewGuid().ToString('n')
                summary             = 'Ask capture'
                suggestedHome       = [string]$guess.suggestedHome
                suggestedProject    = [string]$guess.suggestedProject
                derivedFrom         = @{ source = 'ask'; turnId = $TurnId; sessionId = $sess }
                rootLabel           = [string]$guess.rootLabel
                requiresCrossRoot   = [bool]$guess.requiresCrossRoot
                requiresHostSession = [bool]$guess.requiresHostSession
                accepted            = $true
            }
        )
    }

    $out = [System.Collections.Generic.List[object]]::new()
    $dedupe = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($seed in $seeds) {
        if ($out.Count -ge 5) { break }
        $target = Resolve-MetraCaptureSuggestedTarget -Text $seed.Text -Where $seed.Where -MetraRoot $MetraRoot
        $sum = ($seed.Text -replace '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($sum)) { $sum = "Capture for $($target.suggestedProject)" }
        if ($sum.Length -gt 120) { $sum = $sum.Substring(0, 120) }
        $key = '{0}|{1}|{2}' -f $target.suggestedHome, $target.suggestedProject, ($sum.ToLowerInvariant())
        if (-not $dedupe.Add($key)) { continue }
        [void]$out.Add([PSCustomObject]@{
                proposalId          = [guid]::NewGuid().ToString('n')
                summary             = $sum
                suggestedHome       = [string]$target.suggestedHome
                suggestedProject    = [string]$target.suggestedProject
                derivedFrom         = @{
                    source    = 'ask'
                    turnId    = [string]$seed.TurnId
                    sessionId = [string]$seed.Session
                }
                rootLabel           = [string]$target.rootLabel
                requiresCrossRoot   = [bool]$target.requiresCrossRoot
                requiresHostSession = [bool]$target.requiresHostSession
                accepted            = $true
            })
    }

    if ($out.Count -eq 0) {
        $t0 = $seeds[0]
        $target = Resolve-MetraCaptureSuggestedTarget -Text $t0.Text -Where $t0.Where -MetraRoot $MetraRoot
        [void]$out.Add([PSCustomObject]@{
                proposalId          = [guid]::NewGuid().ToString('n')
                summary             = 'Ask capture'
                suggestedHome       = [string]$target.suggestedHome
                suggestedProject    = [string]$target.suggestedProject
                derivedFrom         = @{ source = 'ask'; turnId = [string]$t0.TurnId; sessionId = [string]$t0.Session }
                rootLabel           = [string]$target.rootLabel
                requiresCrossRoot   = [bool]$target.requiresCrossRoot
                requiresHostSession = [bool]$target.requiresHostSession
                accepted            = $true
            })
    }
    return @($out)
}

function Add-MetraCaptureFromAskSplit {
    <#
    .SYNOPSIS
        Create Capture candidates from affirmed proposal rows only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Proposals,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $created = [System.Collections.Generic.List[object]]::new()
    foreach ($raw in @($Proposals)) {
        $accepted = [bool](Get-MetraProp -Object $raw -Name 'accepted' -Default $false)
        if (-not $accepted) { continue }
        $summary = ([string](Get-MetraProp -Object $raw -Name 'summary' -Default '')).Trim()
        if ([string]::IsNullOrWhiteSpace($summary)) { continue }
        $home = [string](Get-MetraProp -Object $raw -Name 'suggestedHome' -Default '')
        $project = [string](Get-MetraProp -Object $raw -Name 'suggestedProject' -Default '')
        $homeDest = Get-MetraHomeDestinationName
        if ($project -and $project -ine 'Metra' -and $project -ine 'TicketTracker' -and $project -ine $homeDest) {
            $reg = Test-MetraCaptureRegisteredProject -Name $project -MetraRoot $MetraRoot
            if (-not $reg) {
                throw "suggestedProject '$project' is not a registered project. Refuse invent."
            }
        }
        $dfIn = Get-MetraProp -Object $raw -Name 'derivedFrom' -Default $null
        $turnId = ''
        $sessionId = ''
        if ($dfIn -is [System.Collections.IDictionary]) {
            if ($dfIn.Contains('turnId')) { $turnId = [string]$dfIn['turnId'] }
            elseif ($dfIn.Contains('TurnId')) { $turnId = [string]$dfIn['TurnId'] }
            if ($dfIn.Contains('sessionId')) { $sessionId = [string]$dfIn['sessionId'] }
            elseif ($dfIn.Contains('SessionId')) { $sessionId = [string]$dfIn['SessionId'] }
        }
        else {
            $turnId = [string](Get-MetraProp -Object $dfIn -Name 'turnId' -Default '')
            $sessionId = [string](Get-MetraProp -Object $dfIn -Name 'sessionId' -Default '')
            if (-not $turnId) { $turnId = [string](Get-MetraProp -Object $dfIn -Name 'TurnId' -Default '') }
            if (-not $sessionId) { $sessionId = [string](Get-MetraProp -Object $dfIn -Name 'SessionId' -Default '') }
        }
        $derived = New-MetraCaptureDerivedFrom -Type askTurn -SessionId $sessionId -TurnId $turnId
        $item = Add-MetraCaptureItem `
            -Summary $summary `
            -Source ask `
            -DerivedFrom $derived `
            -SuggestedHome $home `
            -SuggestedProject $project `
            -MetraRoot $MetraRoot
        [void]$created.Add($item)
    }
    return @($created)
}

function Add-MetraProjectBacklogCaptureStub {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$Summary,
        [string]$Lineage,
        [string]$CaptureId
    )

    $todo = Join-Path $ProjectPath 'TODO.md'
    $stamp = (Get-Date).ToString('yyyy-MM-dd')
    $safeSummary = Format-MetraCaptureMarkdownSummary -Summary $Summary -MaxLength 160
    $block = @"
- [ ] $stamp Capture: $safeSummary
  - Source: $Lineage
  - Home: ProjectBacklog
  - CaptureId: $CaptureId
"@
    if (-not (Test-Path -LiteralPath $todo)) {
        $header = "# TODO`r`n`r`n"
        [System.IO.File]::WriteAllText($todo, $header + $block + "`r`n")
    }
    else {
        [System.IO.File]::AppendAllText($todo, "`r`n" + $block + "`r`n")
    }
    return $todo
}

function Invoke-MetraCapturePromote {
    <#
    .SYNOPSIS
        Affirms a capture into a durable home. ProjectBacklog requires local authority + optional cross-root confirm.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Home,
        [string]$Project,
        [switch]$CrossRootConfirm,
        [bool]$HasLocalAuthority = $true,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $items = @(Get-MetraCaptureLedger -MetraRoot $MetraRoot -Limit 80 -Status all)
    $item = $items | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
    if (-not $item) { throw "Capture not found: $Id" }
    if ([string]$item.status -eq 'dismissed') { throw 'Cannot promote a dismissed capture.' }

    $target = if (-not [string]::IsNullOrWhiteSpace($Home)) { $Home } else { [string]$item.suggestedHome }
    $summary = [string]$item.summary
    $body = [string](Get-MetraProp -Object $item -Name 'body' -Default '')
    $derived = Get-MetraProp -Object $item -Name 'derivedFrom' -Default $null
    $lineage = 'manual'
    if ($derived) {
        $lineage = '{0}' -f [string](Get-MetraProp -Object $derived -Name 'type' -Default 'manual')
        $sid = [string](Get-MetraProp -Object $derived -Name 'sessionId' -Default '')
        $tid = [string](Get-MetraProp -Object $derived -Name 'turnId' -Default '')
        if ($sid -or $tid) {
            $lineage = '{0} session={1} turn={2}' -f $lineage, $sid, $tid
        }
    }

    $ref = $null
    switch -Regex ($target) {
        '^(FutureDevelopment|future-development|Future Development)$' {
            $ref = Add-MetraFutureDevelopmentCaptureStub -Summary $summary -Body $body -Lineage $lineage -CaptureId $Id -MetraRoot $MetraRoot
            $target = 'FutureDevelopment'
        }
        '^(DecisionRegistry|decision-registry|Decision Registry)$' {
            $added = Add-MetraDecisionRegistryCandidate `
                -Title $summary `
                -Decision $summary `
                -Why $(if ($body) { $body } else { "Capture intake. Lineage: $lineage" }) `
                -Tags @('capture', 'intake') `
                -Source 'ops-capture' `
                -Origin operator `
                -MetraRoot $MetraRoot
            $ref = [string](Get-MetraProp -Object $added -Name 'Id' -Default '')
            $target = 'DecisionRegistry'
        }
        '^(OCC|occ|OperatorContract)$' {
            $null = Add-MetraOperatorContractCandidate -Text $summary -MetraRoot $MetraRoot
            $ref = 'profile-candidate'
            $target = 'OCC'
        }
        '^(ProjectBacklog|project-backlog|Project Backlog)$' {
            if (-not (Test-MetraLocalAuthority -HasLocalAuthority:$HasLocalAuthority)) {
                throw 'ProjectBacklog promote requires a local Metra session. Remote Capture clients may create candidates, but project-tree writes must be performed from Host/CLI authority.'
            }
            $projName = if (-not [string]::IsNullOrWhiteSpace($Project)) { $Project } else {
                [string](Get-MetraProp -Object $item -Name 'suggestedProject' -Default '')
            }
            $proj = Test-MetraCaptureRegisteredProject -Name $projName -MetraRoot $MetraRoot
            if (-not $proj -or [string]::IsNullOrWhiteSpace([string]$proj.Path)) {
                throw "ProjectBacklog promote requires a registered on-disk project. Unknown or pathless project: '$projName'."
            }
            $flags = Get-MetraCaptureCrossRootFlags -ProjectInfo $proj -MetraRoot $MetraRoot
            if ($flags.requiresCrossRoot -and -not $CrossRootConfirm) {
                throw ("Cross-root ProjectBacklog promote to '{0}' requires -CrossRootConfirm / crossRootConfirm:true." -f $projName)
            }
            $ref = Add-MetraProjectBacklogCaptureStub -ProjectPath ([string]$proj.Path) -Summary $summary -Lineage $lineage -CaptureId $Id
            $target = 'ProjectBacklog'
        }
        '^(ProjectAgents|project-agents|Project Agents)$' {
            throw 'ProjectAgents is suggest-only in Ladder 2b. Edit the registered project AGENTS.md in Cursor, or promote this Capture item to ProjectBacklog TODO.md instead.'
        }
        '^(TicketTracker|tickettracker|Ticket Tracker)$' {
            throw 'TicketTracker Capture promote is suggest-only. Create a TicketTracker note or brief from this Capture item; Capture does not write to iSupport.'
        }
        default {
            throw ("Unknown Capture promote home '{0}'. Choose FutureDevelopment, DecisionRegistry, OCC, or ProjectBacklog." -f $target)
        }
    }

    $item.status = 'promoted'
    $item.promoted = [PSCustomObject]@{
        at   = (Get-Date).ToString('o')
        home = $target
        ref  = $ref
    }
    $newItems = foreach ($row in $items) {
        if ([string]$row.id -eq $Id) { $item } else { $row }
    }
    Save-MetraCaptureLedger -Items $newItems -MetraRoot $MetraRoot
    return $item
}

function Add-MetraFutureDevelopmentCaptureStub {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Summary,
        [string]$Body,
        [string]$Lineage,
        [string]$CaptureId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $path = Join-Path $MetraRoot 'docs\Future-Development.local.md'
    $stamp = (Get-Date).ToString('yyyy-MM-dd')
    $title = Format-MetraCaptureMarkdownSummary -Summary $Summary -MaxLength 80
    $safeSummary = Format-MetraCaptureMarkdownSummary -Summary $Summary -MaxLength 160
    $safeBody = if ([string]::IsNullOrWhiteSpace($Body)) {
        $null
    }
    else {
        Format-MetraCaptureMarkdownSummary -Summary $Body -MaxLength 400
    }
    $block = @"

## $stamp - Capture: $title

**Parked via Capture Inbox (recommend-only until activated).**

- Summary: $safeSummary
$(if ($safeBody) { "- Note: $safeBody" } else { '' })
- Lineage: $Lineage
- Capture id: $CaptureId
- Verify when activated: operator review required. Do not auto-implement from Capture.

"@.TrimEnd() + "`r`n"

    if (-not (Test-Path -LiteralPath $path)) {
        $header = @"
# Metra future development (operator parking lot)

Gitignored (`docs/*.local.md`). Index of deferred ideas.

"@
        [System.IO.File]::WriteAllText($path, $header + $block)
    }
    else {
        [System.IO.File]::AppendAllText($path, "`r`n" + $block)
    }
    return ("Future-Development.local.md#$stamp-capture")
}

function Invoke-MetraCaptureCommand {
    <#
    .SYNOPSIS
        CLI surface: capture list|note|dismiss|promote|get|from-ask|propose-from-ask
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    switch ($Subcommand.ToLowerInvariant()) {
        'list' {
            $status = 'candidate'
            if ($ArgsRest -contains '-All') { $status = 'all' }
            return ,@(Get-MetraCaptureLedger -MetraRoot $MetraRoot -Limit 40 -Status $status)
        }
        'get' {
            $id = [string]$ArgsRest[0]
            if ([string]::IsNullOrWhiteSpace($id)) { throw 'capture get <id>' }
            $hit = $null
            $hit = Get-MetraCaptureLedger -MetraRoot $MetraRoot -Limit 80 -Status all |
                Where-Object { $_.id -eq $id } |
                Select-Object -First 1
            if (-not $hit) { throw "Capture not found: $id" }
            return $hit
        }
        'note' {
            $text = ($ArgsRest -join ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($text)) { throw 'capture note "summary text"' }
            $derived = New-MetraCaptureDerivedFrom -Type manual
            return Add-MetraCaptureItem -Summary $text -Source manual -DerivedFrom $derived -MetraRoot $MetraRoot
        }
        'dismiss' {
            $id = [string]$ArgsRest[0]
            if ([string]::IsNullOrWhiteSpace($id)) { throw 'capture dismiss <id>' }
            return Dismiss-MetraCaptureItem -Id $id -MetraRoot $MetraRoot
        }
        'promote' {
            $id = [string]$ArgsRest[0]
            $home = $null
            $project = $null
            $cross = $false
            for ($i = 1; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Home' -and ($i + 1) -lt $ArgsRest.Count) {
                    $home = [string]$ArgsRest[$i + 1]
                    $i++
                }
                elseif ($ArgsRest[$i] -eq '-Project' -and ($i + 1) -lt $ArgsRest.Count) {
                    $project = [string]$ArgsRest[$i + 1]
                    $i++
                }
                elseif ($ArgsRest[$i] -eq '-CrossRootConfirm') {
                    $cross = $true
                }
            }
            if ([string]::IsNullOrWhiteSpace($id)) {
                throw 'capture promote <id> [-Home ProjectBacklog] [-Project Name] [-CrossRootConfirm]'
            }
            return Invoke-MetraCapturePromote -Id $id -Home $home -Project $project -CrossRootConfirm:$cross `
                -HasLocalAuthority $true -MetraRoot $MetraRoot
        }
        'propose-from-ask' {
            $turnId = [string]$ArgsRest[0]
            $sessionId = $null
            for ($i = 1; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-SessionId' -and ($i + 1) -lt $ArgsRest.Count) {
                    $sessionId = [string]$ArgsRest[$i + 1]
                }
            }
            if ([string]::IsNullOrWhiteSpace($turnId) -and [string]::IsNullOrWhiteSpace($sessionId)) {
                throw 'capture propose-from-ask <turnId> [-SessionId <sessionId>]'
            }
            return ,@(Propose-MetraCaptureSplit -TurnId $turnId -SessionId $sessionId -MetraRoot $MetraRoot)
        }
        'from-ask' {
            $turnId = [string]$ArgsRest[0]
            if ([string]::IsNullOrWhiteSpace($turnId)) { throw 'capture from-ask <turnId>' }
            return Add-MetraCaptureFromAskTurn -TurnId $turnId -MetraRoot $MetraRoot
        }
        default {
            throw "Unknown capture subcommand: $Subcommand. Use list|get|note|dismiss|promote|from-ask|propose-from-ask."
        }
    }
}

function Invoke-MetraAskJournalRemote {
    <#
    .SYNOPSIS
        Query HQ GET /api/ask/journal and unwrap to local CLI shapes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [Parameter(Mandatory)][string]$OpsBaseUrl
    )

    $base = $OpsBaseUrl.Trim().TrimEnd('/')
    $unreachable = @"
HQ Ask host unreachable ($base).

Check:
  - Tailscale connected
  - METRA_OPS_BASE_URL (or %LOCALAPPDATA%/Metra/profile-sync.local.json opsBaseUrl)
  - HQ machine available

For local troubleshooting:
  .\metra.ps1 ask sessions -Local
"@

    try {
        switch ($Subcommand.ToLowerInvariant()) {
            { $_ -in @('log', 'list') } {
                $limit = 20
                if ($ArgsRest.Count -gt 0 -and $ArgsRest[0] -match '^\d+$') { $limit = [int]$ArgsRest[0] }
                $url = '{0}/api/ask/journal?limit={1}' -f $base, $limit
                $payload = Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 30
                return ,@($payload.turns)
            }
            'sessions' {
                $url = '{0}/api/ask/journal' -f $base
                $payload = Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 30
                return ,@($payload.sessions)
            }
            { $_ -in @('get', 'resume') } {
                if ($ArgsRest.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$ArgsRest[0])) {
                    throw "ask get requires a sessionId. Example: .\metra.ps1 ask get <sessionId>"
                }
                $sid = [uri]::EscapeDataString([string]$ArgsRest[0])
                $url = '{0}/api/ask/journal?sessionId={1}' -f $base, $sid
                $payload = Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 30
                return [PSCustomObject]@{
                    sessionId  = [string](Get-MetraProp -Object $payload -Name 'sessionId' -Default $ArgsRest[0])
                    turnCount  = [int](Get-MetraProp -Object $payload -Name 'turnCount' -Default @($payload.turns).Count)
                    continuity = (Get-MetraProp -Object $payload -Name 'continuity' -Default $null)
                    turns      = @($payload.turns)
                }
            }
            'recall' {
                if ($ArgsRest.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$ArgsRest[0])) {
                    throw "ask recall requires a query. Example: .\metra.ps1 ask recall `"gateway msal`""
                }
                $limit = 20
                $queryParts = [System.Collections.Generic.List[string]]::new()
                foreach ($a in $ArgsRest) {
                    if ($a -match '^\d+$' -and $queryParts.Count -gt 0) {
                        $limit = [int]$a
                        continue
                    }
                    [void]$queryParts.Add([string]$a)
                }
                $query = ($queryParts -join ' ').Trim()
                $url = '{0}/api/ask/journal?q={1}&limit={2}' -f $base, [uri]::EscapeDataString($query), $limit
                $payload = Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 30
                return ,@($payload.hits)
            }
            default {
                throw "Unknown ask subcommand: $Subcommand. Use log|sessions|get|recall."
            }
        }
    }
    catch {
        $msg = [string]$_.Exception.Message
        if ($msg -match '(?i)(ask get requires|ask recall requires|Unknown ask subcommand)') {
            throw
        }
        throw ($unreachable.TrimEnd() + "`n`nDetail: $msg")
    }
}

function Invoke-MetraAskLogCommand {
    <#
    .SYNOPSIS
        CLI surface: ask log|sessions|get|recall - Session Journal continuity and episodic search.
    .DESCRIPTION
        Desk Mode B (HQ Client) routes to GET /api/ask/journal on OpsBaseUrl.
        -Local / ForceLocal reads %LOCALAPPDATA%/Metra/ops/ask-log.json. Never auto-falls back.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$OpsBaseUrl,
        [switch]$Local,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $forceLocal = [bool]$Local
    $effectiveOpsUrl = $OpsBaseUrl
    $filtered = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt @($ArgsRest).Count; $i++) {
        $a = [string]$ArgsRest[$i]
        if ($a -match '^(?i)-Local$') {
            $forceLocal = $true
            continue
        }
        if ($a -match '^(?i)-OpsBaseUrl$' -and ($i + 1) -lt $ArgsRest.Count) {
            $effectiveOpsUrl = [string]$ArgsRest[$i + 1]
            $i++
            continue
        }
        if ($a -match '^(?i)-OpsBaseUrl=(.+)$') {
            $effectiveOpsUrl = $Matches[1]
            continue
        }
        [void]$filtered.Add($a)
    }
    $ArgsRest = @($filtered)

    $mode = Get-MetraDeskMode -ForceLocal:$forceLocal -OpsBaseUrl $effectiveOpsUrl -MetraRoot $MetraRoot
    if ($mode -eq 'HqClient') {
        $base = Get-MetraProfileOpsBaseUrlOrNull -OpsBaseUrl $effectiveOpsUrl -MetraRoot $MetraRoot
        if ([string]::IsNullOrWhiteSpace($base)) {
            throw 'Desk Mode is HQ Client but OpsBaseUrl could not be resolved.'
        }
        return Invoke-MetraAskJournalRemote -Subcommand $Subcommand -ArgsRest $ArgsRest -OpsBaseUrl $base
    }

    switch ($Subcommand.ToLowerInvariant()) {
        { $_ -in @('log', 'list') } {
            $limit = 20
            if ($ArgsRest.Count -gt 0 -and $ArgsRest[0] -match '^\d+$') { $limit = [int]$ArgsRest[0] }
            return ,@(Get-MetraDeskAskLog -MetraRoot $MetraRoot -Limit $limit)
        }
        'sessions' {
            return ,@(Get-MetraDeskAskSessionSummaries -MetraRoot $MetraRoot -Limit 40)
        }
        { $_ -in @('get', 'resume') } {
            if ($ArgsRest.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$ArgsRest[0])) {
                throw "ask get requires a sessionId. Example: .\metra.ps1 ask get <sessionId>"
            }
            $sid = [string]$ArgsRest[0]
            $turns = @(Get-MetraDeskAskSessionTurns -SessionId $sid -MetraRoot $MetraRoot)
            $continuity = Get-MetraAskContinuityContext -SessionId $sid -MetraRoot $MetraRoot
            return [PSCustomObject]@{
                sessionId  = $sid
                turnCount  = $turns.Count
                continuity = $continuity
                turns      = $turns
            }
        }
        'recall' {
            if ($ArgsRest.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$ArgsRest[0])) {
                throw "ask recall requires a query. Example: .\metra.ps1 ask recall `"gateway msal`""
            }
            $limit = 20
            $queryParts = [System.Collections.Generic.List[string]]::new()
            foreach ($a in $ArgsRest) {
                if ($a -match '^\d+$' -and $queryParts.Count -gt 0) {
                    $limit = [int]$a
                    continue
                }
                [void]$queryParts.Add([string]$a)
            }
            $query = ($queryParts -join ' ').Trim()
            return ,@(Search-MetraDeskAskJournal -Query $query -Limit $limit -MetraRoot $MetraRoot)
        }
        default {
            throw "Unknown ask subcommand: $Subcommand. Use log|sessions|get|recall."
        }
    }
}
