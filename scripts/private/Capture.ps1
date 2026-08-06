# Capture Inbox - thin portfolio intake that references Journal / Place evidence.
# Never auto-loaded into routing or Ask prompts. derivedFrom is immutable after create.

function Get-MetraCaptureLedgerPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return Join-Path $MetraRoot 'docs\ops-capture.local.json'
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
    [System.IO.File]::WriteAllText($path, (($payload | ConvertTo-Json -Depth 10) + "`r`n"))
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

function Resolve-MetraCaptureSuggestedHome {
    [CmdletBinding()]
    param(
        [string]$Text,
        [string]$Where,
        [string]$HomeId
    )

    $whereText = if (-not [string]::IsNullOrWhiteSpace($HomeId)) { $HomeId } else { $Where }
    $blob = (('{0} {1}' -f $Text, $whereText) -replace '\s+', ' ').Trim().ToLowerInvariant()

    if ($blob -match '\b(ticket|isupport|helpdesk|incident)\b' -or $blob -match '\b\d{6,8}\b') {
        return [PSCustomObject]@{ suggestedHome = 'TicketTracker'; suggestedProject = 'TicketTracker' }
    }
    if ($blob -match '\b(always do|prefer terse|collaboration rhythm|operator contract|occ)\b') {
        return [PSCustomObject]@{ suggestedHome = 'OCC'; suggestedProject = 'Metra' }
    }
    if ($blob -match '\b(why we chose|decision registry|scar)\b') {
        return [PSCustomObject]@{ suggestedHome = 'DecisionRegistry'; suggestedProject = 'Metra' }
    }
    if ($blob -match '\b(agents\.md|playbook|runbook)\b' -and $whereText -and $whereText -notin @('Metra', 'Future Development', 'future-development')) {
        return [PSCustomObject]@{ suggestedHome = 'ProjectAgents'; suggestedProject = [string]$whereText }
    }
    if ($blob -match '\b(future development|backlog|feature idea|ios app|metadata audit|should (add|build|ship))\b' -or
        $whereText -match '(?i)future' -or $whereText -eq 'Metra') {
        return [PSCustomObject]@{ suggestedHome = 'FutureDevelopment'; suggestedProject = 'Metra' }
    }
    if ($whereText -and $whereText -ne 'Metra') {
        return [PSCustomObject]@{ suggestedHome = 'FutureDevelopment'; suggestedProject = [string]$whereText }
    }
    return [PSCustomObject]@{ suggestedHome = 'FutureDevelopment'; suggestedProject = 'Metra' }
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
    $guess = Resolve-MetraCaptureSuggestedHome -Text $Summary -Where $SuggestedProject -HomeId $SuggestedHome
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
    $guess = Resolve-MetraCaptureSuggestedHome -Text $sum -Where $where
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
    $guess = Resolve-MetraCaptureSuggestedHome -Text $Text -HomeId $HomeId
    return Add-MetraCaptureItem `
        -Summary $sum `
        -Body $null `
        -Source place `
        -DerivedFrom $derived `
        -SuggestedHome ([string]$guess.suggestedHome) `
        -SuggestedProject ([string]$guess.suggestedProject) `
        -MetraRoot $MetraRoot
}

function Invoke-MetraCapturePromote {
    <#
    .SYNOPSIS
        Affirms a capture into a local durable home. Future Development append is Ask-class local.
        Tracked homes create candidates via existing CLI helpers only - never silent OCC promote.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Home,
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
        default {
            throw ("Promote home '{0}' is not supported for automatic write in this release. Use FutureDevelopment or DecisionRegistry, or promote tracked homes via Host/CLI." -f $target)
        }
    }

    $item.status = 'promoted'
    $item.promoted = [PSCustomObject]@{
        at   = (Get-Date).ToString('o')
        home = $target
        ref  = $ref
    }
    # Preserve derivedFrom exactly - immutable
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
    $title = ($Summary -replace '[\r\n]+', ' ').Trim()
    if ($title.Length -gt 80) { $title = $title.Substring(0, 80) }
    $block = @"

## $stamp - Capture: $title

**Parked via Capture Inbox (recommend-only until activated).**

- Summary: $Summary
$(if ($Body) { "- Note: $Body" } else { '' })
- Lineage: $Lineage
- Capture id: $CaptureId
- Verify when activated: You (+ Bing plan). Do not auto-implement from Capture.

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
        CLI surface: capture list|note|dismiss|promote|get
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
            for ($i = 1; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Home' -and ($i + 1) -lt $ArgsRest.Count) {
                    $home = [string]$ArgsRest[$i + 1]
                }
            }
            if ([string]::IsNullOrWhiteSpace($id)) { throw 'capture promote <id> [-Home FutureDevelopment]' }
            return Invoke-MetraCapturePromote -Id $id -Home $home -MetraRoot $MetraRoot
        }
        'from-ask' {
            $turnId = [string]$ArgsRest[0]
            if ([string]::IsNullOrWhiteSpace($turnId)) { throw 'capture from-ask <turnId>' }
            return Add-MetraCaptureFromAskTurn -TurnId $turnId -MetraRoot $MetraRoot
        }
        default {
            throw "Unknown capture subcommand: $Subcommand. Use list|get|note|dismiss|promote|from-ask."
        }
    }
}

function Invoke-MetraAskLogCommand {
    <#
    .SYNOPSIS
        CLI surface: ask log|sessions - read Session Journal summaries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    switch ($Subcommand.ToLowerInvariant()) {
        { $_ -in @('log', 'list') } {
            $limit = 20
            if ($ArgsRest.Count -gt 0 -and $ArgsRest[0] -match '^\d+$') { $limit = [int]$ArgsRest[0] }
            return ,@(Get-MetraDeskAskLog -MetraRoot $MetraRoot -Limit $limit)
        }
        'sessions' {
            $turns = @(Get-MetraDeskAskLog -MetraRoot $MetraRoot -Limit 100)
            $groups = $turns | Group-Object -Property {
                $sid = [string](Get-MetraProp -Object $_ -Name 'sessionId' -Default '')
                if ([string]::IsNullOrWhiteSpace($sid)) { [string]$_.id } else { $sid }
            }
            $summaries = foreach ($g in $groups) {
                $ordered = @($g.Group | Sort-Object {
                        $ti = Get-MetraProp -Object $_ -Name 'turnIndex' -Default $null
                        if ($null -ne $ti) { [int]$ti } else { 0 }
                    }, { [string]$_.at })
                $first = $ordered | Select-Object -First 1
                [PSCustomObject]@{
                    sessionId  = [string]$g.Name
                    turnCount  = $ordered.Count
                    at         = [string](Get-MetraProp -Object $first -Name 'at' -Default '')
                    prompt     = [string](Get-MetraProp -Object $first -Name 'prompt' -Default '')
                    where      = [string](Get-MetraProp -Object (Get-MetraProp -Object $first -Name 'handoff' -Default $null) -Name 'where' -Default '')
                    origin     = [string](Get-MetraProp -Object $first -Name 'origin' -Default '')
                    client     = [string](Get-MetraProp -Object $first -Name 'client' -Default '')
                }
            }
            return @($summaries | Sort-Object at -Descending)
        }
        default {
            throw "Unknown ask subcommand: $Subcommand. Use log|sessions."
        }
    }
}
