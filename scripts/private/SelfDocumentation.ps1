# SelfDocumentation.ps1 - regenerate Metra self-doc from live routing behavior (present projects)

function Get-MetraSelfDocCanvasPath {
    <#
    .SYNOPSIS
        Resolves the live Metra self-documentation canvas path for this checkout's Cursor project slug.
    #>
    [CmdletBinding()]
    param()

    $metraRoot = Get-MetraRoot
    $slug = ConvertTo-MetraCursorProjectSlug -Path $metraRoot
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = 'c-Projects-meta'
    }
    return Join-Path $env:USERPROFILE (Join-Path '.cursor\projects' (Join-Path $slug 'canvases\metra-self-documentation.canvas.tsx'))
}

function ConvertTo-MetraSelfDocRouteId {
    param([Parameter(Mandatory)][string]$Name)
    $id = ($Name -replace '[^A-Za-z0-9]+', '').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($id)) { return 'project' }
    if ($id.Length -gt 24) { return $id.Substring(0, 24) }
    return $id
}

function Get-MetraSelfDocFeaturedNames {
    <#
    .SYNOPSIS
        Ordered featured project names from registry (routing.featuredProjects + featured:true rows).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Registry
    )

    $routing = Get-MetraProp -Object $Registry -Name 'routing' -Default $null
    $fromRouting = @(Get-MetraProp -Object $routing -Name 'featuredProjects' -Default @()) |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $ordered = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($name in $fromRouting) {
        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$ordered.Add($name)
    }

    foreach ($p in @($Registry.projects)) {
        $name = [string](Get-MetraProp -Object $p -Name 'name' -Default '')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $featured = [bool](Get-MetraProp -Object $p -Name 'featured' -Default $false)
        if (-not $featured) { continue }
        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$ordered.Add($name)
    }

    return @($ordered.ToArray())
}

function Get-MetraSelfDocRouteReason {
    <#
    .SYNOPSIS
        Compact reason label from a Get-MetraRoutingAmbiguity result.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ambiguity,
        [string]$Query = ''
    )

    if (-not $Ambiguity -or -not $Ambiguity.Primary) { return 'unknown' }

    $matched = @($Ambiguity.Primary.MatchedTokens | ForEach-Object { [string]$_ })
    if ($matched -contains 'ticket-id') { return 'ticket-id' }
    if ($matched -contains 'ticket-vocab') { return 'ticket-vocab' }
    if ($matched -contains 'solutions-keyword') { return 'solutions-keyword' }
    if (@($matched | Where-Object { $_ -like 'phrase:*' }).Count -gt 0) { return 'trigger-phrase' }

    $isHome = [bool](Get-MetraProp -Object $Ambiguity.Primary -Name 'IsHomeDefault' -Default $false)
    $score = [int](Get-MetraProp -Object $Ambiguity.Primary -Name 'Score' -Default 0)
    if ($isHome -or $score -lt 2) { return 'home-default' }
    if ($matched.Count -gt 0) { return 'registry-score' }
    if (-not [string]::IsNullOrWhiteSpace($Query) -and (Test-MetraTicketShapedQuery -Query $Query)) {
        return 'ticket-id'
    }
    return 'registry-score'
}

function Resolve-MetraSelfDocVerifiedAsk {
    <#
    .SYNOPSIS
        Finds a sample ask that the live router sends to ExpectedName (or null).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExpectedName,
        [string[]]$CandidateAsks
    )

    $homeName = Get-MetraHomeDestinationName
    foreach ($ask in @($CandidateAsks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        $query = [string]$ask
        try {
            $amb = Get-MetraRoutingAmbiguity -Query $query -SkipTelemetry
        }
        catch {
            continue
        }
        if (-not $amb -or -not $amb.Primary) { continue }
        $primary = [string]$amb.Primary.Name
        if ($primary -ne $ExpectedName) { continue }

        $reason = Get-MetraSelfDocRouteReason -Ambiguity $amb -Query $query
        # Home rows may win only as weak/home-default; other projects need a real win.
        if ($ExpectedName -ne $homeName -and $reason -eq 'home-default') { continue }

        return [PSCustomObject]@{
            sampleAsk = $query
            reason    = $reason
            score     = [int](Get-MetraProp -Object $amb.Primary -Name 'Score' -Default 0)
            matched   = [string[]]@(
                @($amb.Primary.MatchedTokens | ForEach-Object { [string]$_ } | Select-Object -First 8)
            )
        }
    }
    return $null
}

function Get-MetraSelfDocRouteExamples {
    <#
    .SYNOPSIS
        Builds standing route examples verified by Get-MetraRoutingAmbiguity (present projects only).
    .DESCRIPTION
        Featured order comes from registry routing.featuredProjects and/or project featured:true.
        Each sampleAsk is confirmed against the live routing engine so docs match ticket precedence,
        home fallback, and scoring - not raw trigger[0] guesswork.
    #>
    [CmdletBinding()]
    param(
        [int]$DiagramLimit = 3,
        [int]$TableLimit = 8
    )

    $registry = Get-MetraProjectRegistry
    $table = @(Get-MetraRoutingTable)
    $presentByName = @{}
    foreach ($row in $table) {
        if (-not $row.Present) { continue }
        $presentByName[[string]$row.Name] = $row
    }

    $regByName = @{}
    foreach ($p in @($registry.projects)) {
        $n = [string](Get-MetraProp -Object $p -Name 'name' -Default '')
        if ($n) { $regByName[$n] = $p }
    }

    $featuredNames = @(Get-MetraSelfDocFeaturedNames -Registry $registry)
    $orderedNames = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($name in $featuredNames) {
        if (-not $presentByName.ContainsKey($name)) { continue }
        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$orderedNames.Add($name)
    }
    foreach ($name in @($presentByName.Keys | Sort-Object)) {
        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$orderedNames.Add($name)
    }

    $homeName = Get-MetraHomeDestinationName
    $rows = @()
    foreach ($name in $orderedNames) {
        if ($rows.Count -ge $TableLimit) { break }
        if ($name -eq $homeName -and $rows.Count -gt 0) { continue }

        $reg = $regByName[$name]
        $triggers = @()
        $purpose = ''
        if ($reg) {
            $triggers = @(Get-MetraProp -Object $reg -Name 'triggers' -Default @()) | Where-Object { $_ }
            $purpose = [string](Get-MetraProp -Object $reg -Name 'purpose' -Default '')
        }
        else {
            $purpose = [string](Get-MetraProp -Object $presentByName[$name] -Name 'Advice' -Default '')
        }

        $candidates = [System.Collections.Generic.List[string]]::new()
        foreach ($t in $triggers) { [void]$candidates.Add([string]$t) }
        [void]$candidates.Add($name)
        if ($name -eq $homeName) {
            [void]$candidates.Add('help me organize my portfolio')
            [void]$candidates.Add('zzqx-noroute-xyzzy-qwerty')
        }

        $verified = Resolve-MetraSelfDocVerifiedAsk -ExpectedName $name -CandidateAsks @($candidates.ToArray())
        if (-not $verified) {
            # Skip unverified rows so Overview never claims a route the engine will not take.
            continue
        }

        $rows += [PSCustomObject]@{
            id        = (ConvertTo-MetraSelfDocRouteId -Name $name)
            name      = $name
            sampleAsk = [string]$verified.sampleAsk
            purpose   = $purpose
            triggers  = @($triggers | Select-Object -First 5)
            reason    = [string]$verified.reason
            score     = [int]$verified.score
            present   = $true
        }
    }

    $diagram = @($rows | Select-Object -First $DiagramLimit)
    $chosen = $diagram | Where-Object { $_.name -eq 'TicketTracker' } | Select-Object -First 1
    if (-not $chosen -and $diagram.Count -gt 0) { $chosen = $diagram[0] }

    return [PSCustomObject]@{
        generatedAt = (Get-Date).ToString('o')
        source      = 'routing-engine'
        chosenId    = if ($chosen) { [string]$chosen.id } else { '' }
        diagram     = @($diagram)
        routes      = @($rows)
        precedence  = @(
            'ticket-id',
            'ticket-vocab',
            'solutions-keyword',
            'registry-score',
            'home-default'
        )
    }
}

function Get-MetraSelfDocBehaviorExamples {
    <#
    .SYNOPSIS
        Living routing validation suite: fixed probes + verified standing asks.
    .DESCRIPTION
        Writes machine-readable examples of how Metra thinks (ticket precedence, home fallback,
        trigger phrases). Suitable for smoke diffs and adoption desks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RoutePayload
    )

    $examples = New-Object System.Collections.Generic.List[object]
    $seenQuery = @{}

    $add = {
        param([string]$Query, [string]$ExpectedPrimary = '')
        if ([string]::IsNullOrWhiteSpace($Query)) { return }
        $key = $Query.ToLowerInvariant()
        if ($seenQuery.ContainsKey($key)) { return }
        $seenQuery[$key] = $true
        try {
            $amb = Get-MetraRoutingAmbiguity -Query $Query -SkipTelemetry
        }
        catch {
            [void]$examples.Add([PSCustomObject]@{
                    query    = $Query
                    primary  = ''
                    reason   = 'error'
                    score    = 0
                    matched  = [string[]]@()
                    expected = $ExpectedPrimary
                    ok       = $false
                    detail   = [string]$_.Exception.Message
                })
            return
        }
        $primary = if ($amb -and $amb.Primary) { [string]$amb.Primary.Name } else { '' }
        $reason = Get-MetraSelfDocRouteReason -Ambiguity $amb -Query $Query
        $score = if ($amb -and $amb.Primary) {
            [int](Get-MetraProp -Object $amb.Primary -Name 'Score' -Default 0)
        }
        else { 0 }
        $matched = if ($amb -and $amb.Primary) {
            [string[]]@(@($amb.Primary.MatchedTokens | ForEach-Object { [string]$_ } | Select-Object -First 8))
        }
        else { [string[]]@() }
        $ok = if ([string]::IsNullOrWhiteSpace($ExpectedPrimary)) {
            -not [string]::IsNullOrWhiteSpace($primary)
        }
        else {
            $primary -eq $ExpectedPrimary
        }
        [void]$examples.Add([PSCustomObject]@{
                query    = $Query
                primary  = $primary
                reason   = $reason
                score    = $score
                matched  = $matched
                expected = $ExpectedPrimary
                ok       = [bool]$ok
            })
    }

    $homeName = Get-MetraHomeDestinationName
    $ttPresent = $null -ne (Get-MetraTicketTrackerProject)

    # Fixed adoption probes (how Metra thinks - not only what projects exist).
    if ($ttPresent) {
        & $add '1035666' 'TicketTracker'
        & $add 'Look at 1035666' 'TicketTracker'
        & $add 'ticket disk alert' 'TicketTracker'
    }
    & $add 'solarwinds alerts' 'Solarwinds'
    & $add 'help me organize my portfolio' $homeName
    & $add 'zzqx-noroute-xyzzy-qwerty' $homeName

    foreach ($r in @($RoutePayload.routes)) {
        & $add ([string]$r.sampleAsk) ([string]$r.name)
    }

    $failCount = @($examples | Where-Object { -not $_.ok }).Count
    return [PSCustomObject]@{
        generatedAt = [string]$RoutePayload.generatedAt
        source      = 'routing-engine'
        precedence  = @($RoutePayload.precedence)
        failCount   = $failCount
        examples    = @($examples.ToArray())
    }
}

function Install-MetraSelfDocCanvas {
    <#
    .SYNOPSIS
        Ensures the live self-documentation canvas exists and matches the tracked template component code.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CanvasPath
    )

    $metraRoot = Get-MetraRoot
    $templatePath = Join-Path $metraRoot 'integrations\cursor\metra-self-documentation.canvas.tsx.template'
    $canvasDir = Split-Path -Parent $CanvasPath

    if (-not (Test-Path -LiteralPath $CanvasPath)) {
        if (-not (Test-Path -LiteralPath $templatePath)) {
            Write-Warning "Metra self-doc canvas template missing: $templatePath"
            return $false
        }
        if ($canvasDir -and -not (Test-Path -LiteralPath $canvasDir)) {
            [void][System.IO.Directory]::CreateDirectory($canvasDir)
        }
        Copy-Item -LiteralPath $templatePath -Destination $CanvasPath -Force
        Write-Host ("Installed Metra self-doc canvas from template: {0}" -f $CanvasPath) -ForegroundColor Green
    }
    elseif (Test-Path -LiteralPath $templatePath) {
        $liveText = [System.IO.File]::ReadAllText($CanvasPath)
        $templateText = [System.IO.File]::ReadAllText($templatePath)
        $liveHasMarkers = $liveText.Contains('// <metra-selfdoc-routes>')
        $templateHasMarkers = $templateText.Contains('// <metra-selfdoc-routes>')
        if ($liveHasMarkers -and -not $templateHasMarkers) {
            Copy-Item -LiteralPath $CanvasPath -Destination $templatePath -Force
            Write-Host ("Promoted live self-doc canvas to template (template lacked route markers): {0}" -f $templatePath) -ForegroundColor Green
        }
        else {
            # Strip route embed before shape compare so regenerated data does not look like template drift.
            $liveShape = Get-MetraCanvasCodeShape -Text (Remove-MetraSelfDocRouteEmbed -Text $liveText)
            $templateShape = Get-MetraCanvasCodeShape -Text (Remove-MetraSelfDocRouteEmbed -Text $templateText)
            if ($liveShape -ne $templateShape) {
                Copy-Item -LiteralPath $templatePath -Destination $CanvasPath -Force
                Write-Host ("Refreshed Metra self-doc canvas from template: {0}" -f $CanvasPath) -ForegroundColor Green
            }
        }
    }

    return (Test-Path -LiteralPath $CanvasPath)
}

function Remove-MetraSelfDocRouteEmbed {
    param([Parameter(Mandatory)][string]$Text)
    $begin = '// <metra-selfdoc-routes>'
    $end = '// </metra-selfdoc-routes>'
    $bi = $Text.IndexOf($begin)
    $ei = $Text.IndexOf($end)
    if ($bi -ge 0 -and $ei -gt $bi) {
        return $Text.Substring(0, $bi) + $Text.Substring($ei + $end.Length)
    }
    return $Text
}

function Update-MetraSelfDocCanvasEmbed {
    param(
        [Parameter(Mandatory)][string]$CanvasPath,
        [Parameter(Mandatory)]$Payload
    )

    $json = ($Payload | ConvertTo-Json -Depth 8 -Compress)
    $begin = '// <metra-selfdoc-routes>'
    $end = '// </metra-selfdoc-routes>'
    $embed = @"
$begin
type SelfDocRoute = { id: string; name: string; sampleAsk: string; purpose: string; triggers: string[]; reason?: string; score?: number; present?: boolean };
type SelfDocRoutesPayload = { generatedAt: string; source?: string; chosenId: string; diagram: SelfDocRoute[]; routes: SelfDocRoute[]; precedence?: string[] };
const SELFDOC_ROUTES: SelfDocRoutesPayload = $json;
$end
"@

    $canvas = [System.IO.File]::ReadAllText($CanvasPath)
    $bi = $canvas.IndexOf($begin)
    $ei = $canvas.IndexOf($end)
    if ($bi -ge 0 -and $ei -gt $bi) {
        $updated = $canvas.Substring(0, $bi) + $embed + $canvas.Substring($ei + $end.Length)
        # Caption outside markers: behavior docs, not registry dump.
        $updated = $updated.Replace(
            'Registry-driven diagram. Refresh with',
            'Live routing diagram (verified asks). Refresh with'
        )
        [System.IO.File]::WriteAllText($CanvasPath, $updated)
        Write-Host ("Updated self-doc canvas route embed: {0}" -f $CanvasPath) -ForegroundColor Green
        return $true
    }

    Write-Warning "Self-doc canvas missing <metra-selfdoc-routes> markers: $CanvasPath"
    return $false
}

function Update-MetraSelfDocOverview {
    param(
        [Parameter(Mandatory)]$Payload,
        [string]$OverviewPath = (Join-Path (Get-MetraRoot) 'docs\Overview.md')
    )

    if (-not (Test-Path -LiteralPath $OverviewPath)) {
        Write-Warning "Overview.md missing: $OverviewPath"
        return $false
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<!-- metra-selfdoc-routes-begin -->')
    $lines.Add('')
    $lines.Add('| Project | Verified ask | Why | Purpose |')
    $lines.Add('|---------|--------------|-----|---------|')
    foreach ($r in @($Payload.routes)) {
        $purpose = ([string]$r.purpose) -replace '\|', '/'
        $ask = ([string]$r.sampleAsk) -replace '\|', '/'
        $why = ([string]$r.reason) -replace '\|', '/'
        $lines.Add(("| {0} | {1} | {2} | {3} |" -f $r.name, $ask, $why, $purpose))
    }
    $lines.Add('')
    $lines.Add('Precedence (live engine): ticket id > helpdesk vocabulary > solutions keywords > registry score; weak signals stay at Metra.')
    if ($null -ne (Get-MetraTicketTrackerProject)) {
        $lines.Add('Example: ask `1035666` -> TicketTracker (ticket-id), even when no project name appears in the ask.')
    }
    $lines.Add('')
    $lines.Add(('Generated {0} by `.\metra.ps1 selfdoc` from live `Get-MetraRoutingAmbiguity` (present projects only).' -f $Payload.generatedAt))
    $lines.Add('<!-- metra-selfdoc-routes-end -->')
    $block = ($lines -join "`r`n")

    $text = [System.IO.File]::ReadAllText($OverviewPath)
    $begin = '<!-- metra-selfdoc-routes-begin -->'
    $end = '<!-- metra-selfdoc-routes-end -->'
    $bi = $text.IndexOf($begin)
    $ei = $text.IndexOf($end)
    if ($bi -ge 0 -and $ei -gt $bi) {
        $updated = $text.Substring(0, $bi) + $block + $text.Substring($ei + $end.Length)
        [System.IO.File]::WriteAllText($OverviewPath, $updated)
        Write-Host ("Updated Overview route table: {0}" -f $OverviewPath) -ForegroundColor Green
        return $true
    }

    # First-time inject after "## What Metra does" section intro if markers absent.
    $anchor = "## What Metra does"
    $ai = $text.IndexOf($anchor)
    if ($ai -ge 0) {
        $inject = "`r`n`r`n### Standing route examples`r`n`r`n$block`r`n"
        $nl = $text.IndexOf("`n", $ai)
        if ($nl -lt 0) { $nl = $text.Length - 1 }
        $updated = $text.Substring(0, $nl + 1) + $inject + $text.Substring($nl + 1)
        [System.IO.File]::WriteAllText($OverviewPath, $updated)
        Write-Host ("Injected Overview route table: {0}" -f $OverviewPath) -ForegroundColor Green
        return $true
    }

    Write-Warning "Could not find Overview markers or What Metra does heading."
    return $false
}

function Update-MetraSelfDocumentation {
    <#
    .SYNOPSIS
        Regenerates self-documentation from live routing into canvas, Overview.md, and JSON sidecars.
    .DESCRIPTION
        Repeatable operation after registry / trigger / route changes. Also invoked from Export-MetraSnapshot.
        Standing examples are verified with Get-MetraRoutingAmbiguity so docs track ticket precedence and
        home fallback. Writes docs/selfdoc-routing-examples.json as a living validation suite.
    #>
    [CmdletBinding()]
    param(
        [int]$DiagramLimit = 3,
        [int]$TableLimit = 8
    )

    $metraRoot = Get-MetraRoot
    $payload = Get-MetraSelfDocRouteExamples -DiagramLimit $DiagramLimit -TableLimit $TableLimit
    $behavior = Get-MetraSelfDocBehaviorExamples -RoutePayload $payload

    $docsDir = Join-Path $metraRoot 'docs'
    if (-not (Test-Path -LiteralPath $docsDir)) {
        [void][System.IO.Directory]::CreateDirectory($docsDir)
    }

    $jsonPath = Join-Path $docsDir 'selfdoc-routes.json'
    [System.IO.File]::WriteAllText($jsonPath, (($payload | ConvertTo-Json -Depth 8) + "`r`n"))
    Write-Host ("Wrote self-doc routes: {0}" -f $jsonPath) -ForegroundColor Green

    $behaviorPath = Join-Path $docsDir 'selfdoc-routing-examples.json'
    [System.IO.File]::WriteAllText($behaviorPath, (($behavior | ConvertTo-Json -Depth 8) + "`r`n"))
    Write-Host ("Wrote self-doc routing examples: {0} (failCount={1})" -f $behaviorPath, $behavior.failCount) -ForegroundColor Green

    $canvasPath = Get-MetraSelfDocCanvasPath
    $canvasReady = Install-MetraSelfDocCanvas -CanvasPath $canvasPath
    $embedOk = $false
    if ($canvasReady) {
        $embedOk = Update-MetraSelfDocCanvasEmbed -CanvasPath $canvasPath -Payload $payload
    }

    $overviewOk = Update-MetraSelfDocOverview -Payload $payload

    # Keep tracked template in sync only when the live canvas embed succeeded.
    $templatePath = Join-Path $metraRoot 'integrations\cursor\metra-self-documentation.canvas.tsx.template'
    if ($embedOk -and (Test-Path -LiteralPath $templatePath) -and (Test-Path -LiteralPath $canvasPath)) {
        Copy-Item -LiteralPath $canvasPath -Destination $templatePath -Force
        Write-Host ("Synced self-doc template from live canvas: {0}" -f $templatePath) -ForegroundColor Green
    }

    return [PSCustomObject]@{
        JsonPath              = $jsonPath
        BehaviorJsonPath      = $behaviorPath
        BehaviorFailCount     = [int]$behavior.failCount
        CanvasPath            = $canvasPath
        CanvasReady           = [bool]$canvasReady
        EmbedUpdated          = [bool]$embedOk
        OverviewUpdated       = [bool]$overviewOk
        RouteCount            = @($payload.routes).Count
        GeneratedAt           = [string]$payload.generatedAt
        Source                = [string]$payload.source
    }
}
