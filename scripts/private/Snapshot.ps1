# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Get-MetraProjectGitCounts {
    <#
    .SYNOPSIS
        Returns dirty/ahead/behind counts for a project folder (best-effort, no network).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $result = [PSCustomObject]@{
        isGit   = $false
        dirty   = 0
        ahead   = 0
        behind  = 0
        branch  = ''
        summary = 'n/a'
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) {
        return $result
    }

    $result.isGit = $true
    Push-Location $Path
    try {
        $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
        if ($branch) { $result.branch = [string]$branch.Trim() }

        $porcelain = @(git status --porcelain 2>$null)
        $result.dirty = @($porcelain | Where-Object { $_ -and $_.Trim().Length -gt 0 }).Count

        $ab = (git rev-list --left-right --count '@{u}...HEAD' 2>$null)
        if ($ab -match '^\s*(\d+)\s+(\d+)\s*$') {
            $result.behind = [int]$Matches[1]
            $result.ahead = [int]$Matches[2]
        }

        $parts = @()
        if ($result.dirty -gt 0) { $parts += ("dirty {0}" -f $result.dirty) }
        if ($result.ahead -gt 0) { $parts += ("ahead {0}" -f $result.ahead) }
        if ($result.behind -gt 0) { $parts += ("behind {0}" -f $result.behind) }
        if ($parts.Count -eq 0) {
            $result.summary = 'clean'
        }
        else {
            $result.summary = ($parts -join ', ')
        }
    }
    catch {
        $result.summary = 'error'
    }
    finally {
        Pop-Location
    }

    return $result
}

function Get-MetraOpsCanvasPath {
    <#
    .SYNOPSIS
        Resolves the live Metra Ops canvas path for this checkout's Cursor project slug.
    #>
    [CmdletBinding()]
    param()

    $metraRoot = Get-MetraRoot
    $slug = ConvertTo-MetraCursorProjectSlug -Path $metraRoot
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = 'c-Projects-meta'
    }
    return Join-Path $env:USERPROFILE (Join-Path '.cursor\projects' (Join-Path $slug 'canvases\metra-ops-board.canvas.tsx'))
}

function ConvertTo-MetraSnapshotWhyHere {
    <#
    .SYNOPSIS
        Bounded Why Here rows for the Ops board snapshot (no evidence dumps).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Limit = 3
    )

    $rows = @()
    try {
        $rows = @(Get-MetraWhyHere -Project $Project -Limit $Limit -MetraRoot $MetraRoot)
    }
    catch {
        return @()
    }

    return @(
        $rows | ForEach-Object {
            [PSCustomObject]@{
                id         = [string](Get-MetraProp -Object $_ -Name 'Id' -Default '')
                title      = [string](Get-MetraProp -Object $_ -Name 'Title' -Default '')
                decision   = [string](Get-MetraProp -Object $_ -Name 'Decision' -Default '')
                why        = [string](Get-MetraProp -Object $_ -Name 'Why' -Default '')
                confidence = [string](Get-MetraProp -Object $_ -Name 'Confidence' -Default '')
                project    = [string](Get-MetraProp -Object $_ -Name 'Project' -Default $Project)
            }
        }
    )
}

function Get-MetraKnowledgeCoverage {
    <#
    .SYNOPSIS
        Knowledge coverage visibility for present registry-on-disk projects (not a score).
    .DESCRIPTION
        Builds one project population, then derives every with/missing/uncovered dimension
        from that set only. WithDecisions counts projects that have at least one active
        confirmed Decision Registry row tagged to that project (not candidates, not
        superseded). Gap name lists are alphabetical, deduped, and capped; counts are full.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Projects,
        [string]$MetraRoot = (Get-MetraRoot),
        [ValidateRange(1, 100)]
        [int]$GapLimit = 12,
        [hashtable]$DecisionProjectSet
    )

    $population = New-Object System.Collections.Generic.List[object]

    if ($null -ne $Projects -and @($Projects).Count -gt 0) {
        foreach ($p in @($Projects)) {
            $presentProp = Get-MetraProp -Object $p -Name 'present' -Default $null
            if ($null -eq $presentProp) {
                $presentProp = Get-MetraProp -Object $p -Name 'Present' -Default $null
            }
            if ($null -ne $presentProp -and -not [bool]$presentProp) { continue }

            $name = [string](Get-MetraProp -Object $p -Name 'name' -Default '')
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = [string](Get-MetraProp -Object $p -Name 'Name' -Default '')
            }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $hasAgents = $null
            if ($null -ne (Get-MetraProp -Object $p -Name 'hasAgentsMd' -Default $null)) {
                $hasAgents = [bool](Get-MetraProp -Object $p -Name 'hasAgentsMd' -Default $false)
            }
            $path = [string](Get-MetraProp -Object $p -Name 'path' -Default '')
            if ([string]::IsNullOrWhiteSpace($path)) {
                $path = [string](Get-MetraProp -Object $p -Name 'Path' -Default '')
            }
            $entry = [string](Get-MetraProp -Object $p -Name 'entry' -Default 'AGENTS.md')
            if ([string]::IsNullOrWhiteSpace($entry)) { $entry = 'AGENTS.md' }
            if ($null -eq $hasAgents) {
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    $hasAgents = Test-Path -LiteralPath (Join-Path $path $entry)
                }
                else {
                    $hasAgents = $false
                }
            }

            $serves = @(
                @(Get-MetraProp -Object $p -Name 'serves' -Default @()) |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            )

            [void]$population.Add([PSCustomObject]@{
                    Name      = $name
                    HasAgents = [bool]$hasAgents
                    HasServes = (@($serves).Count -gt 0)
                })
        }
    }
    else {
        $registry = Get-MetraProjectRegistry
        $disk = @{}
        foreach ($d in @(Get-MetraProjects)) {
            $disk[$d.Name.ToLowerInvariant()] = $d
        }
        foreach ($reg in @($registry.projects)) {
            $name = [string]$reg.name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $onDisk = $disk[$name.ToLowerInvariant()]
            if (-not $onDisk) { continue }
            $entry = [string](Get-MetraProp -Object $reg -Name 'entry' -Default 'AGENTS.md')
            if ([string]::IsNullOrWhiteSpace($entry)) { $entry = 'AGENTS.md' }
            $hasAgents = Test-Path -LiteralPath (Join-Path $onDisk.Path $entry)
            $serves = @(
                @(Get-MetraProp -Object $reg -Name 'serves' -Default @()) |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            )
            [void]$population.Add([PSCustomObject]@{
                    Name      = $name
                    HasAgents = [bool]$hasAgents
                    HasServes = (@($serves).Count -gt 0)
                })
        }
    }

    $pop = @($population | Sort-Object Name)
    $projectNames = @($pop | ForEach-Object { $_.Name })

    if (-not $DecisionProjectSet) {
        $DecisionProjectSet = @{}
        try {
            $shown = Show-MetraDecisionRegistry -MetraRoot $MetraRoot
            foreach ($row in @($shown.Confirmed)) {
                $status = [string](Get-MetraProp -Object $row -Name 'status' -Default 'active')
                if ($status.ToLowerInvariant() -ne 'active') { continue }
                $proj = [string](Get-MetraProp -Object $row -Name 'project' -Default '')
                if ([string]::IsNullOrWhiteSpace($proj)) { continue }
                $DecisionProjectSet[$proj.ToLowerInvariant()] = $true
            }
        }
        catch {
            # Fail-open: treat as no decisions.
        }
    }

    $missingAgentsFull = New-Object System.Collections.Generic.List[string]
    $missingServesFull = New-Object System.Collections.Generic.List[string]
    $missingDecisionsFull = New-Object System.Collections.Generic.List[string]
    $uncoveredFull = New-Object System.Collections.Generic.List[string]
    $withAgents = 0
    $withServes = 0
    $withDecisions = 0

    foreach ($row in $pop) {
        $hasDecision = $DecisionProjectSet.ContainsKey($row.Name.ToLowerInvariant())
        if ($row.HasAgents) { $withAgents++ } else { [void]$missingAgentsFull.Add($row.Name) }
        if ($row.HasServes) { $withServes++ } else { [void]$missingServesFull.Add($row.Name) }
        if ($hasDecision) { $withDecisions++ } else { [void]$missingDecisionsFull.Add($row.Name) }
        if ((-not $row.HasAgents) -and (-not $row.HasServes) -and (-not $hasDecision)) {
            [void]$uncoveredFull.Add($row.Name)
        }
    }

    return [PSCustomObject]@{
        ProjectCount          = $pop.Count
        ProjectNames          = @($projectNames)
        WithAgents            = $withAgents
        MissingAgents         = @(
            $missingAgentsFull |
                Sort-Object -Unique |
                Select-Object -First $GapLimit
        )
        MissingAgentsCount    = $missingAgentsFull.Count
        WithServes            = $withServes
        MissingServes         = @(
            $missingServesFull |
                Sort-Object -Unique |
                Select-Object -First $GapLimit
        )
        MissingServesCount    = $missingServesFull.Count
        WithDecisions         = $withDecisions
        MissingDecisions      = @(
            $missingDecisionsFull |
                Sort-Object -Unique |
                Select-Object -First $GapLimit
        )
        MissingDecisionsCount = $missingDecisionsFull.Count
        Uncovered             = @(
            $uncoveredFull |
                Sort-Object -Unique |
                Select-Object -First $GapLimit
        )
        UncoveredCount        = $uncoveredFull.Count
    }
}

function Write-MetraKnowledgeCoverage {
    <#
    .SYNOPSIS
        Host output for knowledge coverage visibility (counts + capped gap lists).
    #>
    [CmdletBinding()]
    param(
        $Coverage
    )

    if (-not $Coverage) {
        Write-Host 'No coverage data.' -ForegroundColor Yellow
        return
    }

    Write-Host ("Knowledge coverage (visibility only; not a score)") -ForegroundColor Cyan
    Write-Host ("  Present projects: {0}" -f $Coverage.ProjectCount)
    Write-Host ("  With AGENTS: {0}  | missing: {1}" -f $Coverage.WithAgents, $Coverage.MissingAgentsCount)
    if (@($Coverage.MissingAgents).Count -gt 0) {
        Write-Host ("    MissingAgents: {0}" -f ($Coverage.MissingAgents -join ', '))
    }
    Write-Host ("  With serves: {0}  | missing: {1}" -f $Coverage.WithServes, $Coverage.MissingServesCount)
    if (@($Coverage.MissingServes).Count -gt 0) {
        Write-Host ("    MissingServes: {0}" -f ($Coverage.MissingServes -join ', '))
    }
    Write-Host ("  With decisions (active confirmed): {0}  | missing: {1}" -f $Coverage.WithDecisions, $Coverage.MissingDecisionsCount)
    if (@($Coverage.MissingDecisions).Count -gt 0) {
        Write-Host ("    MissingDecisions: {0}" -f ($Coverage.MissingDecisions -join ', '))
    }
    Write-Host ("  Uncovered (missing AGENTS + serves + decisions): {0}" -f $Coverage.UncoveredCount)
    if (@($Coverage.Uncovered).Count -gt 0) {
        Write-Host ("    Uncovered: {0}" -f ($Coverage.Uncovered -join ', '))
    }
}

function Show-MetraKnowledgeCoverageCli {
    <#
    .SYNOPSIS
        CLI host output for knowledge coverage. Compatibility export for metra.ps1.
    #>
    [CmdletBinding()]
    param()

    Write-MetraKnowledgeCoverage -Coverage (Get-MetraKnowledgeCoverage)
}

function Get-MetraOpsStewardshipSummaries {
    <#
    .SYNOPSIS
        Bounded Decision Registry + OCC + coverage summaries for the Ops board.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Projects,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $decisionSummary = [ordered]@{
        ledgerExists      = $false
        confirmedCount    = 0
        candidateCount    = 0
        supersededCount   = 0
        maxConfirmed      = 50
        recent            = @()
        candidates        = @()
    }
    try {
        $shown = Show-MetraDecisionRegistry -MetraRoot $MetraRoot
        $decisionSummary.ledgerExists = [bool]$shown.LedgerExists
        $decisionSummary.confirmedCount = [int]$shown.ConfirmedCount
        $decisionSummary.candidateCount = [int]$shown.CandidateCount
        $decisionSummary.supersededCount = [int]$shown.SupersededCount
        $decisionSummary.maxConfirmed = [int]$shown.MaxConfirmed
        $decisionSummary.recent = @(
            @($shown.Confirmed) |
                Where-Object {
                    ([string](Get-MetraProp -Object $_ -Name 'status' -Default 'active')) -eq 'active'
                } |
                Sort-Object @{ Expression = { [string](Get-MetraProp -Object $_ -Name 'date' -Default '') }; Descending = $true },
                @{ Expression = { [string](Get-MetraProp -Object $_ -Name 'title' -Default '') } } |
                Select-Object -First 5 |
                ForEach-Object {
                    [PSCustomObject]@{
                        id         = [string](Get-MetraProp -Object $_ -Name 'id' -Default '')
                        title      = [string](Get-MetraProp -Object $_ -Name 'title' -Default '')
                        decision   = [string](Get-MetraProp -Object $_ -Name 'decision' -Default '')
                        why        = [string](Get-MetraProp -Object $_ -Name 'why' -Default '')
                        project    = [string](Get-MetraProp -Object $_ -Name 'project' -Default '')
                        confidence = [string](Get-MetraProp -Object $_ -Name 'confidence' -Default '')
                        date       = [string](Get-MetraProp -Object $_ -Name 'date' -Default '')
                    }
                }
        )
        $decisionSummary.candidates = @(
            @($shown.Candidates) |
                Select-Object -First 5 |
                ForEach-Object {
                    [PSCustomObject]@{
                        id      = [string](Get-MetraProp -Object $_ -Name 'id' -Default '')
                        title   = [string](Get-MetraProp -Object $_ -Name 'title' -Default '')
                        project = [string](Get-MetraProp -Object $_ -Name 'project' -Default '')
                        date    = [string](Get-MetraProp -Object $_ -Name 'date' -Default '')
                    }
                }
        )
    }
    catch {
        # Fail-open: empty stewardship block when the ledger is unreadable.
    }

    $contractSummary = [ordered]@{
        ledgerExists     = $false
        confirmedCount   = 0
        candidateCount   = 0
        maxConfirmed     = 20
        confirmed        = @()
        candidates       = @()
    }
    try {
        $contract = Show-MetraOperatorContract -MetraRoot $MetraRoot
        $contractSummary.ledgerExists = [bool]$contract.LedgerExists
        $contractSummary.confirmedCount = [int]$contract.ConfirmedCount
        $contractSummary.candidateCount = [int]$contract.CandidateCount
        $contractSummary.maxConfirmed = [int]$contract.MaxConfirmed
        $contractSummary.confirmed = @(
            @($contract.ConfirmedGuidelines) |
                Select-Object -First 10 |
                ForEach-Object {
                    [PSCustomObject]@{
                        id   = [string](Get-MetraProp -Object $_ -Name 'id' -Default '')
                        text = [string](Get-MetraProp -Object $_ -Name 'text' -Default '')
                        date = [string](Get-MetraProp -Object $_ -Name 'date' -Default '')
                    }
                }
        )
        $contractSummary.candidates = @(
            @($contract.Candidates) |
                Select-Object -First 5 |
                ForEach-Object {
                    [PSCustomObject]@{
                        id   = [string](Get-MetraProp -Object $_ -Name 'id' -Default '')
                        text = [string](Get-MetraProp -Object $_ -Name 'text' -Default '')
                        date = [string](Get-MetraProp -Object $_ -Name 'date' -Default '')
                    }
                }
        )
    }
    catch {
        # Fail-open.
    }

    $presentProjects = @($Projects | Where-Object {
            $p = Get-MetraProp -Object $_ -Name 'present' -Default $null
            if ($null -eq $p) { $true } else { [bool]$p }
        })
    # Snapshot rows always set present; keep capabilities/whyHere on full list for board compat.
    $projectsWithCapabilities = @($Projects | Where-Object { @($_.capabilities).Count -gt 0 }).Count
    $projectsWithWhyHere = @($Projects | Where-Object { @($_.whyHere).Count -gt 0 }).Count

    $kc = Get-MetraKnowledgeCoverage -Projects $presentProjects -MetraRoot $MetraRoot

    $reviewSummary = [ordered]@{
        ledgerExists           = [bool]$decisionSummary.ledgerExists
        candidateStaleDays     = 30
        staleCandidatesCount   = 0
        staleCandidates        = @()
        supersededCount        = 0
        superseded             = @()
        missingWhyCount        = 0
        missingWhy             = @()
    }
    try {
        $rev = Get-MetraDecisionRegistryReview -MetraRoot $MetraRoot
        $reviewSummary.ledgerExists = [bool]$rev.LedgerExists
        $reviewSummary.candidateStaleDays = [int]$rev.CandidateStaleDays
        $reviewSummary.staleCandidatesCount = [int]$rev.StaleCandidatesCount
        $reviewSummary.staleCandidates = @(
            @($rev.StaleCandidates) | ForEach-Object {
                [PSCustomObject]@{
                    id    = [string]$_.id
                    title = [string]$_.title
                }
            }
        )
        $reviewSummary.supersededCount = [int]$rev.SupersededCount
        $reviewSummary.superseded = @(
            @($rev.Superseded) | ForEach-Object {
                [PSCustomObject]@{
                    id    = [string]$_.id
                    title = [string]$_.title
                }
            }
        )
        $reviewSummary.missingWhyCount = [int]$rev.MissingWhyCount
        $reviewSummary.missingWhy = @(
            @($rev.MissingWhy) | ForEach-Object {
                [PSCustomObject]@{
                    id     = [string]$_.id
                    title  = [string]$_.title
                    bucket = [string]$_.bucket
                }
            }
        )
    }
    catch {
        # Fail-open.
    }

    $coverage = [ordered]@{
        projectsWithServes       = [int]$kc.WithServes
        projectsWithCapabilities = [int]$projectsWithCapabilities
        projectsWithWhyHere      = [int]$projectsWithWhyHere
        projectsWithDecisions    = [int]$kc.WithDecisions
        confirmedDecisionCount   = [int]$decisionSummary.confirmedCount
        confirmedGuidelineCount  = [int]$contractSummary.confirmedCount
        projectCount             = [int]$kc.ProjectCount
        withAgents               = [int]$kc.WithAgents
        missingAgents            = @($kc.MissingAgents)
        missingAgentsCount       = [int]$kc.MissingAgentsCount
        missingServes             = @($kc.MissingServes)
        missingServesCount        = [int]$kc.MissingServesCount
        missingDecisions         = @($kc.MissingDecisions)
        missingDecisionsCount    = [int]$kc.MissingDecisionsCount
        uncovered                = @($kc.Uncovered)
        uncoveredCount           = [int]$kc.UncoveredCount
    }

    return [PSCustomObject]@{
        decisions = [PSCustomObject]$decisionSummary
        contract  = [PSCustomObject]$contractSummary
        coverage  = [PSCustomObject]$coverage
        review    = [PSCustomObject]$reviewSummary
    }
}

function Get-MetraCanvasCodeShape {
    <#
    .SYNOPSIS
        Returns canvas text with the embedded snapshot block removed, for template drift comparison.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    foreach ($pair in (Get-MetraCanvasMarkerPairs)) {
        $bi = $Text.IndexOf($pair.Begin)
        $ei = $Text.IndexOf($pair.End)
        if ($bi -ge 0 -and $ei -gt $bi) {
            $Text = $Text.Substring(0, $bi) + $Text.Substring($ei + $pair.End.Length)
            break
        }
    }

    return (($Text -replace "`r`n", "`n").Trim())
}

function Get-MetraCanvasMarkerPairs {
    <#
    .SYNOPSIS
        Snapshot embed markers for the live canvas (legacy meta- prefix still accepted).
    #>
    [CmdletBinding()]
    param()

    return @(
        @{ Begin = '// <metra-ops-snapshot>'; End = '// </metra-ops-snapshot>' },
        @{ Begin = '// <meta-ops-snapshot>'; End = '// </meta-ops-snapshot>' }
    )
}

function Install-MetraOpsCanvas {
    <#
    .SYNOPSIS
        Ensures the live Metra Ops canvas exists and matches the tracked template component code.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CanvasPath
    )

    $metraRoot = Get-MetraRoot
    $templatePath = Join-Path $metraRoot 'integrations\cursor\metra-ops-board.canvas.tsx.template'
    $canvasDir = Split-Path -Parent $CanvasPath
    $legacyPath = Join-Path $canvasDir 'meta-ops-board.canvas.tsx'

    if (-not (Test-Path -LiteralPath $CanvasPath)) {
        if (-not (Test-Path -LiteralPath $templatePath)) {
            Write-Warning "Metra Ops canvas template missing: $templatePath"
            return $false
        }
        if ($canvasDir -and -not (Test-Path -LiteralPath $canvasDir)) {
            New-Item -ItemType Directory -Path $canvasDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $templatePath -Destination $CanvasPath -Force
        Write-Host ("Installed Metra Ops canvas from template: {0}" -f $CanvasPath) -ForegroundColor Green
    }
    elseif (Test-Path -LiteralPath $templatePath) {
        # The embedded snapshot is rewritten right after this call, so only component code drift matters.
        $liveShape = Get-MetraCanvasCodeShape -Text ([System.IO.File]::ReadAllText($CanvasPath))
        $templateShape = Get-MetraCanvasCodeShape -Text ([System.IO.File]::ReadAllText($templatePath))
        if ($liveShape -ne $templateShape) {
            Copy-Item -LiteralPath $templatePath -Destination $CanvasPath -Force
            Write-Host ("Refreshed Metra Ops canvas from template: {0}" -f $CanvasPath) -ForegroundColor Green
        }
    }

    if ((Test-Path -LiteralPath $legacyPath) -and ($legacyPath -ne $CanvasPath)) {
        Remove-Item -LiteralPath $legacyPath -Force -ErrorAction SilentlyContinue
        Write-Host ("Removed legacy canvas: {0}" -f $legacyPath) -ForegroundColor Yellow
    }

    return (Test-Path -LiteralPath $CanvasPath)
}

function Get-MetraQuickProjectHealthReports {
    <#
    .SYNOPSIS
        Light registry/disk health for snapshot -Quick (no recursive scan, no git).
    #>
    [CmdletBinding()]
    param()

    $registry = Get-MetraProjectRegistry
    $disk = @(Get-MetraProjects)
    $byDisk = @{}
    foreach ($d in $disk) {
        $byDisk[$d.Name.ToLowerInvariant()] = $d
    }

    $driftCount = 0
    $reports = @()

    foreach ($d in $disk) {
        $reg = Get-MetraRegistryProject -Registry $registry -Name $d.Name
        $inRegistry = $null -ne $reg
        $findings = @()
        $hasAgents = Test-Path -LiteralPath (Join-Path $d.Path 'AGENTS.md')
        $hasIgnore = Test-Path -LiteralPath (Join-Path $d.Path '.cursorignore')
        $hasReadme = Test-Path -LiteralPath (Join-Path $d.Path 'README.md')

        if (-not $inRegistry) {
            $findings += 'Missing from registry (projects.json or projects.local.json)'
            $driftCount++
        }
        elseif (-not $hasAgents -and [string]$reg.entry -eq 'AGENTS.md') {
            $findings += 'Registry entry expects AGENTS.md but file is missing'
            $driftCount++
        }

        $reports += [PSCustomObject]@{
            Name            = $d.Name
            Path            = $d.Path
            Root            = $d.Root
            HasAgentsMd     = $hasAgents
            HasCursorIgnore = $hasIgnore
            HasReadme       = $hasReadme
            Findings        = $findings
            LargeFiles      = @()
            Drift           = ($findings.Count -gt 0)
            InRegistry      = $inRegistry
        }
    }

    return [PSCustomObject]@{
        Reports    = $reports
        DriftCount = $driftCount
        DiskByName = $byDisk
        Registry   = $registry
    }
}

function Test-MetraCanvasSnapshotStale {
    <#
    .SYNOPSIS
        True when the Ops board snapshot is older than MaxAgeHours or newer than registry/config inputs.
    #>
    [CmdletBinding()]
    param(
        [string]$SnapshotPath,
        [double]$MaxAgeHours = 4
    )

    $metraRoot = Get-MetraRoot
    if (-not $SnapshotPath) {
        $SnapshotPath = Join-Path $metraRoot 'docs\canvas-snapshot.json'
    }
    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        return $true
    }

    $snapTime = (Get-Item -LiteralPath $SnapshotPath).LastWriteTimeUtc
    if (((Get-Date).ToUniversalTime() - $snapTime).TotalHours -gt $MaxAgeHours) {
        return $true
    }

    $watch = @(
        (Join-Path $metraRoot 'projects.json'),
        (Join-Path $metraRoot 'projects.local.json'),
        (Join-Path $metraRoot 'metra.config.json'),
        (Join-Path $metraRoot 'meta.config.json')
    )
    foreach ($root in @(Get-MetraRoots -IncludeMissing)) {
        if (-not $root.RegistryFile) { continue }
        $rootRegistryPath = [System.Environment]::ExpandEnvironmentVariables([string]$root.RegistryFile)
        if (-not [System.IO.Path]::IsPathRooted($rootRegistryPath)) {
            $rootRegistryPath = Join-Path $root.Path $rootRegistryPath
        }
        $watch += $rootRegistryPath
    }
    foreach ($path in $watch) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        if ((Get-Item -LiteralPath $path).LastWriteTimeUtc -gt $snapTime) {
            return $true
        }
    }
    return $false
}

function Export-MetraCanvasSnapshot {
    <#
    .SYNOPSIS
        Writes docs/canvas-snapshot.json from registry + quiet audit for the Metra Ops canvas embed.
    .PARAMETER Quick
        Hook-friendly refresh: registry + present/missing + AGENTS/.cursorignore/README only.
        Skips recursive large-file scan and per-project git counts.
    #>
    [CmdletBinding()]
    param(
        [string]$OutPath,
        [string]$CanvasPath,
        [int]$ScanDepth = 2,
        [switch]$Quick
    )

    $metraRoot = Get-MetraRoot
    if (-not $OutPath) {
        $OutPath = Join-Path $metraRoot 'docs\canvas-snapshot.json'
    }
    if (-not $CanvasPath) {
        $CanvasPath = Get-MetraOpsCanvasPath
    }

    $registry = Get-MetraProjectRegistry
    $cfg = Get-MetraConfig
    $pinned = @()
    if ($cfg.workspace -and $cfg.workspace.alwaysInclude) {
        $pinned = @($cfg.workspace.alwaysInclude)
    }

    $auditDriftCount = 0
    $byName = @{}
    if ($Quick) {
        Write-Host 'Running quick portfolio health for snapshot...' -ForegroundColor Cyan
        $lightHealth = Get-MetraQuickProjectHealthReports
        $auditDriftCount = [int]$lightHealth.DriftCount
        foreach ($r in @($lightHealth.Reports)) {
            $byName[[string]$r.Name.ToLowerInvariant()] = $r
        }
        $diskReports = @($lightHealth.Reports)
    }
    else {
        Write-Host 'Running quiet portfolio audit for snapshot...' -ForegroundColor Cyan
        $audit = Invoke-MetraProjectContextAudit -ScanDepth $ScanDepth -Quiet | Select-Object -Last 1
        $auditDriftCount = [int]$audit.DriftCount
        foreach ($r in @($audit.Reports)) {
            $byName[[string]$r.Name.ToLowerInvariant()] = $r
        }
        $diskReports = @($audit.Reports)
    }

    $todos = @()
    $projects = foreach ($reg in @($registry.projects)) {
        $name = [string]$reg.name
        $report = $byName[$name.ToLowerInvariant()]
        $findings = @()
        if ($report -and $report.Findings) { $findings = @($report.Findings) }

        $large = @()
        if (-not $Quick -and $report -and $report.LargeFiles) {
            $large = @(
                $report.LargeFiles | Select-Object -First 3 | ForEach-Object {
                    [PSCustomObject]@{ path = [string]$_.Path; kb = [double]$_.KB }
                }
            )
        }

        $projectPath = if ($report) { [string]$report.Path } else { Join-Path (Get-ProjectsRoot) $name }
        if ($Quick) {
            $git = [PSCustomObject]@{
                isGit   = $false
                dirty   = 0
                ahead   = 0
                behind  = 0
                branch  = ''
                summary = 'skipped'
            }
        }
        else {
            $git = Get-MetraProjectGitCounts -Path $projectPath
        }
        $optional = [bool](Get-MetraProp -Object $reg -Name 'optional' -Default $false)

        $status = 'healthy'
        if (-not $report -and $optional) { $status = 'not-installed' }
        elseif (-not $report) { $status = 'missing-audit' }
        elseif ($report.Drift -or $findings.Count -gt 0) { $status = 'drift' }

        if ($findings.Count -gt 0) {
            foreach ($f in $findings) {
                $todos += [PSCustomObject]@{
                    id      = ($name + ':' + ($f.GetHashCode()))
                    project = $name
                    content = "$name - $f"
                    status  = 'pending'
                    kind    = 'drift'
                }
            }
        }
        if ($git.isGit -and ($git.dirty -gt 0 -or $git.ahead -gt 0 -or $git.behind -gt 0)) {
            $todos += [PSCustomObject]@{
                id      = ($name + ':git')
                project = $name
                content = "$name - git $($git.summary)"
                status  = 'pending'
                kind    = 'git'
            }
        }

        $serves = @(Get-MetraProp -Object $reg -Name 'serves' -Default @())
        $whyHere = @()
        if ($report) {
            $whyHere = @(ConvertTo-MetraSnapshotWhyHere -Project $name -MetraRoot $metraRoot -Limit 3)
        }

        [PSCustomObject]@{
            name            = $name
            purpose         = [string](Get-MetraProp -Object $reg -Name 'purpose' -Default '')
            triggers        = @(Get-MetraProp -Object $reg -Name 'triggers' -Default @())
            serves          = @($serves)
            entry           = [string](Get-MetraProp -Object $reg -Name 'entry' -Default 'AGENTS.md')
            preferredPaths  = @(Get-MetraProp -Object $reg -Name 'preferredPaths' -Default @())
            excludePaths    = @(Get-MetraProp -Object $reg -Name 'excludePaths' -Default @())
            related         = @(Get-MetraProp -Object $reg -Name 'related' -Default @())
            inRegistry      = $true
            registrySource  = [string](Get-MetraProp -Object $reg -Name 'source' -Default 'shared')
            root            = if ($report) { [string]$report.Root } else { '' }
            present         = [bool]$report
            optional        = $optional
            capabilities    = @(Get-MetraProp -Object $reg -Name 'capabilities' -Default @())
            hasAgentsMd     = if ($report) { [bool]$report.HasAgentsMd } else { $false }
            hasCursorIgnore = if ($report) { [bool]$report.HasCursorIgnore } else { $false }
            hasReadme       = if ($report) { [bool]$report.HasReadme } else { $false }
            drift           = if ($report) { [bool]$report.Drift } else { -not $optional }
            findings        = $findings
            largeFiles      = $large
            status          = $status
            pinned          = ($pinned -contains $name)
            whyHere         = $whyHere
            gitIsRepo       = [bool]$git.isGit
            gitDirty        = [int]$git.dirty
            gitAhead        = [int]$git.ahead
            gitBehind       = [int]$git.behind
            gitBranch       = [string]$git.branch
            gitSummary      = [string]$git.summary
            gitChecked      = (-not $Quick)
        }
    }

    # Disk projects present but not in registry
    foreach ($r in @($diskReports)) {
        $exists = $false
        foreach ($p in @($projects)) {
            if ($p.name -eq $r.Name) { $exists = $true; break }
        }
        if (-not $exists) {
            $findings = @($r.Findings)
            if ($findings.Count -eq 0) {
                $findings = @('Missing from registry (projects.json or projects.local.json)')
            }
            foreach ($f in $findings) {
                $todos += [PSCustomObject]@{
                    id      = ($r.Name + ':' + ($f.GetHashCode()))
                    project = [string]$r.Name
                    content = "$($r.Name) - $f"
                    status  = 'pending'
                    kind    = 'drift'
                }
            }
            if ($Quick) {
                $git = [PSCustomObject]@{
                    isGit   = $false
                    dirty   = 0
                    ahead   = 0
                    behind  = 0
                    branch  = ''
                    summary = 'skipped'
                }
            }
            else {
                $git = Get-MetraProjectGitCounts -Path ([string]$r.Path)
            }
            if ($git.isGit -and ($git.dirty -gt 0 -or $git.ahead -gt 0 -or $git.behind -gt 0)) {
                $todos += [PSCustomObject]@{
                    id      = ($r.Name + ':git')
                    project = [string]$r.Name
                    content = "$($r.Name) - git $($git.summary)"
                    status  = 'pending'
                    kind    = 'git'
                }
            }
            $projects = @($projects) + @(
                [PSCustomObject]@{
                    name            = [string]$r.Name
                    purpose         = ''
                    triggers        = @()
                    serves          = @()
                    entry           = 'AGENTS.md'
                    preferredPaths  = @('README.md', 'AGENTS.md')
                    excludePaths    = @()
                    related         = @()
                    inRegistry      = $false
                    registrySource  = ''
                    root            = [string]$r.Root
                    present         = $true
                    optional        = $false
                    capabilities    = @()
                    hasAgentsMd     = [bool]$r.HasAgentsMd
                    hasCursorIgnore = [bool]$r.HasCursorIgnore
                    hasReadme       = [bool]$r.HasReadme
                    drift           = $true
                    findings        = $findings
                    largeFiles      = @()
                    status          = 'drift'
                    pinned          = $false
                    whyHere         = @()
                    gitIsRepo       = [bool]$git.isGit
                    gitDirty        = [int]$git.dirty
                    gitAhead        = [int]$git.ahead
                    gitBehind       = [int]$git.behind
                    gitBranch       = [string]$git.branch
                    gitSummary      = [string]$git.summary
                    gitChecked      = (-not $Quick)
                }
            )
        }
    }

    $missingAgents = @($projects | Where-Object { $_.present -and -not $_.hasAgentsMd }).Count
    $missingIgnore = @($projects | Where-Object { $_.present -and -not $_.hasCursorIgnore }).Count
    $driftProjects = @($projects | Where-Object { $_.drift }).Count
    $notInstalled = @($projects | Where-Object { -not $_.present }).Count
    $gitDirtyProjects = @($projects | Where-Object { $_.gitIsRepo -and $_.gitDirty -gt 0 }).Count
    $gitDirtySum = @($projects | Where-Object { $_.gitIsRepo } | Measure-Object -Property gitDirty -Sum)
    $gitDirtyFiles = if ($gitDirtySum -and $null -ne $gitDirtySum.Sum) { [int]$gitDirtySum.Sum } else { 0 }
    $gitAheadProjects = @($projects | Where-Object { $_.gitIsRepo -and $_.gitAhead -gt 0 }).Count
    $gitBehindProjects = @($projects | Where-Object { $_.gitIsRepo -and $_.gitBehind -gt 0 }).Count

    $stewardship = Get-MetraOpsStewardshipSummaries -Projects $projects -MetraRoot $metraRoot

    $verifySummary = [ordered]@{
        checked   = $false
        status    = 'skipped'
        passCount = 0
        warnCount = 0
        failCount = 0
        ok        = $null
    }
    if (-not $Quick) {
        try {
            $verify = Invoke-MetraVerify
            $status = if ([int]$verify.FailCount -gt 0) { 'FAIL' }
            elseif ([int]$verify.WarnCount -gt 0) { 'WARN' }
            else { 'PASS' }
            $verifySummary = [ordered]@{
                checked   = $true
                status    = $status
                passCount = [int]$verify.PassCount
                warnCount = [int]$verify.WarnCount
                failCount = [int]$verify.FailCount
                ok        = [bool]$verify.Ok
            }
        }
        catch {
            $verifySummary = [ordered]@{
                checked   = $true
                status    = 'FAIL'
                passCount = 0
                warnCount = 0
                failCount = 1
                ok        = $false
            }
        }
    }

    $snapshot = [ordered]@{
        generatedAt       = (Get-Date).ToString('o')
        mode              = $(if ($Quick) { 'quick' } else { 'full' })
        gitChecked        = (-not $Quick)
        verifyChecked     = (-not $Quick -and [bool]$verifySummary.checked)
        projectCount      = @($projects).Count
        driftCount        = [int]$auditDriftCount
        driftProjects     = $driftProjects
        notInstalled      = $notInstalled
        missingAgents     = $missingAgents
        missingIgnore     = $missingIgnore
        roots             = @(Get-MetraRoots -IncludeMissing | ForEach-Object {
                [PSCustomObject]@{
                    name    = $_.Name
                    path    = $_.Path
                    primary = $_.Primary
                    exists  = $_.Exists
                }
            })
        gitDirtyProjects  = [int]$gitDirtyProjects
        gitDirtyFiles     = [int]$gitDirtyFiles
        gitAheadProjects  = [int]$gitAheadProjects
        gitBehindProjects = [int]$gitBehindProjects
        pinned            = $pinned
        defaultEntry      = [string]$registry.routing.defaultEntry
        ticketFirst       = [bool]$registry.routing.ticketFirst
        todos             = @($todos | Select-Object -First 40)
        projects          = @($projects | Sort-Object name)
        decisions         = $stewardship.decisions
        contract          = $stewardship.contract
        coverage          = $stewardship.coverage
        review            = $stewardship.review
        verify            = [PSCustomObject]$verifySummary
    }

    $dir = Split-Path -Parent $OutPath
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($snapshot | ConvertTo-Json -Depth 8)
    [System.IO.File]::WriteAllText($OutPath, $json + "`r`n")
    Write-Host ("Wrote snapshot: {0}" -f $OutPath) -ForegroundColor Green

    $canvasReady = Install-MetraOpsCanvas -CanvasPath $CanvasPath
    if ($canvasReady) {
        $canvas = [System.IO.File]::ReadAllText($CanvasPath)
        $markerPairs = Get-MetraCanvasMarkerPairs
        $updatedEmbed = $false
        foreach ($pair in $markerPairs) {
            $begin = [string]$pair.Begin
            $end = [string]$pair.End
            $bi = $canvas.IndexOf($begin)
            $ei = $canvas.IndexOf($end)
            if ($bi -ge 0 -and $ei -gt $bi) {
                $embedBegin = '// <metra-ops-snapshot>'
                $embedEnd = '// </metra-ops-snapshot>'
                $embed = @"
$embedBegin
const SNAPSHOT: MetaSnapshot = $json;
$embedEnd
"@
                $updated = $canvas.Substring(0, $bi) + $embed + $canvas.Substring($ei + $end.Length)
                [System.IO.File]::WriteAllText($CanvasPath, $updated)
                Write-Host ("Updated canvas embed: {0}" -f $CanvasPath) -ForegroundColor Green
                $updatedEmbed = $true
                break
            }
        }
        if (-not $updatedEmbed) {
            Write-Warning "Canvas found but missing <metra-ops-snapshot> markers: $CanvasPath"
        }
    }

    return [PSCustomObject]@{
        OutPath      = $OutPath
        CanvasPath   = $CanvasPath
        ProjectCount = $snapshot.projectCount
        DriftCount   = $snapshot.driftCount
        TodoCount    = @($snapshot.todos).Count
    }
}

