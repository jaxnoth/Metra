# SelfDocumentation.ps1 - regenerate Metra self-doc canvas + Overview route examples from the registry

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

function Get-MetraSelfDocRouteExamples {
    <#
    .SYNOPSIS
        Builds standing route examples for self-documentation from the merged registry.
    #>
    [CmdletBinding()]
    param(
        [int]$DiagramLimit = 3,
        [int]$TableLimit = 8
    )

    $registry = Get-MetraProjectRegistry
    $projects = @($registry.projects)
    $byName = @{}
    foreach ($p in $projects) {
        $n = [string](Get-MetraProp -Object $p -Name 'name' -Default '')
        if ($n) { $byName[$n] = $p }
    }

    $preferred = @(
        'TicketTracker', 'Solarwinds', 'Trivia', 'Colleague',
        'IWUDATA-Automation', 'Reporting', 'Jitterbit', 'Metra'
    )

    $ordered = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $preferred) {
        if ($byName.ContainsKey($name)) {
            $ordered.Add($byName[$name])
            $byName.Remove($name)
        }
    }
    foreach ($name in ($byName.Keys | Sort-Object)) {
        $ordered.Add($byName[$name])
    }

    $rows = @()
    foreach ($reg in $ordered) {
        if ($rows.Count -ge $TableLimit) { break }
        $name = [string](Get-MetraProp -Object $reg -Name 'name' -Default '')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name -eq 'Metra' -and $rows.Count -gt 0) { continue }

        $triggers = @(Get-MetraProp -Object $reg -Name 'triggers' -Default @()) | Where-Object { $_ }
        $purpose = [string](Get-MetraProp -Object $reg -Name 'purpose' -Default '')
        $sampleAsk = if ($triggers.Count -gt 0) { [string]$triggers[0] } else { "help with $name" }
        $id = ConvertTo-MetraSelfDocRouteId -Name $name

        $rows += [ordered]@{
            id        = $id
            name      = $name
            sampleAsk = $sampleAsk
            purpose   = $purpose
            triggers  = @($triggers | Select-Object -First 5)
        }
    }

    $diagram = @($rows | Select-Object -First $DiagramLimit)
    $chosen = $diagram | Where-Object { $_.name -eq 'TicketTracker' } | Select-Object -First 1
    if (-not $chosen -and $diagram.Count -gt 0) { $chosen = $diagram[0] }

    return [ordered]@{
        generatedAt = (Get-Date).ToString('o')
        chosenId    = if ($chosen) { [string]$chosen.id } else { '' }
        diagram     = @($diagram)
        routes      = @($rows)
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
            New-Item -ItemType Directory -Path $canvasDir -Force | Out-Null
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

    $json = ($Payload | ConvertTo-Json -Depth 6 -Compress)
    $begin = '// <metra-selfdoc-routes>'
    $end = '// </metra-selfdoc-routes>'
    $embed = @"
$begin
type SelfDocRoute = { id: string; name: string; sampleAsk: string; purpose: string; triggers: string[] };
type SelfDocRoutesPayload = { generatedAt: string; chosenId: string; diagram: SelfDocRoute[]; routes: SelfDocRoute[] };
const SELFDOC_ROUTES: SelfDocRoutesPayload = $json;
$end
"@

    $canvas = [System.IO.File]::ReadAllText($CanvasPath)
    $bi = $canvas.IndexOf($begin)
    $ei = $canvas.IndexOf($end)
    if ($bi -ge 0 -and $ei -gt $bi) {
        $updated = $canvas.Substring(0, $bi) + $embed + $canvas.Substring($ei + $end.Length)
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
    $lines.Add('| Project | Sample ask / trigger | Purpose |')
    $lines.Add('|---------|----------------------|---------|')
    foreach ($r in @($Payload.routes)) {
        $purpose = ([string]$r.purpose) -replace '\|', '/'
        $ask = ([string]$r.sampleAsk) -replace '\|', '/'
        $lines.Add(("| {0} | {1} | {2} |" -f $r.name, $ask, $purpose))
    }
    $lines.Add('')
    $lines.Add(('Generated {0} by `.\metra.ps1 selfdoc` from the merged registry.' -f $Payload.generatedAt))
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
        Regenerates self-documentation route examples from the registry into the canvas, Overview.md, and JSON sidecar.
    .DESCRIPTION
        Repeatable operation after registry / trigger / route changes. Also invoked from Export-MetraSnapshot.
    #>
    [CmdletBinding()]
    param(
        [int]$DiagramLimit = 3,
        [int]$TableLimit = 8
    )

    $metraRoot = Get-MetraRoot
    $payload = Get-MetraSelfDocRouteExamples -DiagramLimit $DiagramLimit -TableLimit $TableLimit

    $jsonPath = Join-Path $metraRoot 'docs\selfdoc-routes.json'
    $jsonDir = Split-Path -Parent $jsonPath
    if (-not (Test-Path -LiteralPath $jsonDir)) {
        New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($jsonPath, (($payload | ConvertTo-Json -Depth 6) + "`r`n"))
    Write-Host ("Wrote self-doc routes: {0}" -f $jsonPath) -ForegroundColor Green

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
        JsonPath       = $jsonPath
        CanvasPath     = $canvasPath
        CanvasReady    = [bool]$canvasReady
        EmbedUpdated   = [bool]$embedOk
        OverviewUpdated = [bool]$overviewOk
        RouteCount     = @($payload.routes).Count
        GeneratedAt    = [string]$payload.generatedAt
    }
}
