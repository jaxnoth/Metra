# Generated from the original Metra.psm1 domain split. Edit this file directly.

$script:MetraGitProbeSkip = @(
    'node_modules', 'bin', 'obj', '.vs', '.vscode', '.idea',
    'dist', 'build', 'packages', 'venv', '.venv', '__pycache__'
)

function Get-MetraGitFolderCounts {
    <#
    .SYNOPSIS
        Reads dirty/ahead/behind for a single git working folder.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $counts = [PSCustomObject]@{
        dirty  = 0
        ahead  = 0
        behind = 0
        branch = ''
        failed = $false
    }

    Push-Location $Path
    try {
        $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
        if ($branch) { $counts.branch = [string]$branch.Trim() }

        $porcelain = @(git status --porcelain 2>$null)
        $counts.dirty = @($porcelain | Where-Object { $_ -and $_.Trim().Length -gt 0 }).Count

        $ab = (git rev-list --left-right --count '@{u}...HEAD' 2>$null)
        if ($ab -match '^\s*(\d+)\s+(\d+)\s*$') {
            $counts.behind = [int]$Matches[1]
            $counts.ahead = [int]$Matches[2]
        }
    }
    catch {
        $counts.failed = $true
    }
    finally {
        Pop-Location
    }

    return $counts
}

function Get-MetraProjectGitCounts {
    <#
    .SYNOPSIS
        Returns dirty/ahead/behind counts for a project folder (best-effort, no network).
    .DESCRIPTION
        Some projects keep the git remote in a subfolder rather than the project root
        (for example Jitterbit tracks IWU.Jitterbit/). When the root is not a repo,
        counts come from registry-declared gitPaths, or a shallow probe of immediate
        child folders. Counts across multiple nested repos are summed.
    .PARAMETER SubPath
        Registry gitPaths - relative folders to treat as the project's repos.
    .PARAMETER NoProbe
        Skip the automatic child-folder probe when the root is not a repo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$SubPath = @(),
        [switch]$NoProbe
    )

    $result = [PSCustomObject]@{
        isGit     = $false
        dirty     = 0
        ahead     = 0
        behind    = 0
        branch    = ''
        summary   = 'n/a'
        repoPath  = ''
        repoCount = 0
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    # Repo folders, relative to the project root ('' means the root itself)
    $repoRelPaths = @()
    if (Test-Path -LiteralPath (Join-Path $Path '.git')) {
        $repoRelPaths = @('')
    }
    else {
        foreach ($rel in @($SubPath)) {
            if ([string]::IsNullOrWhiteSpace($rel)) { continue }
            $candidate = Join-Path $Path $rel
            if (Test-Path -LiteralPath (Join-Path $candidate '.git')) {
                $repoRelPaths += $rel
            }
        }

        if ($repoRelPaths.Count -eq 0 -and -not $NoProbe) {
            $children = @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)
            foreach ($child in $children) {
                if ($script:MetraGitProbeSkip -contains $child.Name) { continue }
                if ($child.Name.StartsWith('.')) { continue }
                if (Test-Path -LiteralPath (Join-Path $child.FullName '.git')) {
                    $repoRelPaths += $child.Name
                }
            }
        }
    }

    if ($repoRelPaths.Count -eq 0) {
        return $result
    }

    $result.isGit = $true
    $result.repoCount = $repoRelPaths.Count
    $failed = $false

    foreach ($rel in $repoRelPaths) {
        $repoPath = if ($rel -eq '') { $Path } else { Join-Path $Path $rel }
        $counts = Get-MetraGitFolderCounts -Path $repoPath
        if ($counts.failed) { $failed = $true; continue }
        $result.dirty += [int]$counts.dirty
        $result.ahead += [int]$counts.ahead
        $result.behind += [int]$counts.behind
        if ($repoRelPaths.Count -eq 1) {
            $result.branch = [string]$counts.branch
            $result.repoPath = [string]$rel
        }
    }

    if ($failed -and $result.dirty -eq 0 -and $result.ahead -eq 0 -and $result.behind -eq 0) {
        $result.summary = 'error'
        return $result
    }

    $parts = @()
    if ($result.dirty -gt 0) { $parts += ("dirty {0}" -f $result.dirty) }
    if ($result.ahead -gt 0) { $parts += ("ahead {0}" -f $result.ahead) }
    if ($result.behind -gt 0) { $parts += ("behind {0}" -f $result.behind) }
    $result.summary = if ($parts.Count -eq 0) { 'clean' } else { ($parts -join ', ') }

    # Name the subfolder so the desk does not imply the project root is the repo
    if ($result.repoPath) {
        $result.summary = "$($result.summary) ($($result.repoPath))"
    }
    elseif ($repoRelPaths.Count -gt 1) {
        $result.summary = "$($result.summary) ($($repoRelPaths.Count) repos)"
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
                isGit     = $false
                dirty     = 0
                ahead     = 0
                behind    = 0
                branch    = ''
                summary   = 'skipped'
                repoPath  = ''
                repoCount = 0
            }
        }
        else {
            $gitPaths = @(Get-MetraProp -Object $reg -Name 'gitPaths' -Default @())
            $git = Get-MetraProjectGitCounts -Path $projectPath -SubPath $gitPaths
        }
        $optional = [bool](Get-MetraProp -Object $reg -Name 'optional' -Default $false)

        $status = 'healthy'
        if (-not $report -and $optional) { $status = 'not-installed' }
        elseif (-not $report) { $status = 'missing-audit' }
        elseif ($report.Drift -or $findings.Count -gt 0) { $status = 'drift' }

        if ($findings.Count -gt 0) {
            foreach ($f in $findings) {
                $findingText = [string]$f
                $todos += [PSCustomObject]@{
                    id      = (Get-MetraAttentionKey -Project $name -Kind 'drift' -Content $findingText)
                    project = $name
                    content = "$name - $findingText"
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
            gitRepoPath     = [string]$git.repoPath
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
                $findingText = [string]$f
                $projName = [string]$r.Name
                $todos += [PSCustomObject]@{
                    id      = (Get-MetraAttentionKey -Project $projName -Kind 'drift' -Content $findingText)
                    project = $projName
                    content = "$projName - $findingText"
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
                    gitRepoPath     = [string]$git.repoPath
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

    $selfDoc = $null
    try {
        $selfDoc = Update-MetraSelfDocumentation
    }
    catch {
        Write-Warning ("Self-documentation refresh failed: {0}" -f $_.Exception.Message)
    }

    return [PSCustomObject]@{
        OutPath      = $OutPath
        CanvasPath   = $CanvasPath
        ProjectCount = $snapshot.projectCount
        DriftCount   = $snapshot.driftCount
        TodoCount    = @($snapshot.todos).Count
        SelfDoc      = $selfDoc
    }
}

function Get-MetraDeskPreferencesPath {
    <#
    .SYNOPSIS
        Path to local HTML Ops preferences (gitignored user state).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return Join-Path $MetraRoot 'docs\ops-preferences.local.json'
}

function Get-MetraDeskAskLogPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return Join-Path $MetraRoot 'docs\ops-ask-log.local.json'
}

function Get-MetraAskJournalSchemaVersion {
    return 1
}

function Get-MetraAskMessageMaxChars {
    return 8192
}

function Truncate-MetraAskJournalMessage {
    param([string]$Message, [int]$MaxChars = (Get-MetraAskMessageMaxChars))

    if ([string]::IsNullOrEmpty($Message)) { return $Message }
    if ($Message.Length -le $MaxChars) { return $Message }
    return ($Message.Substring(0, $MaxChars) + [Environment]::NewLine + [Environment]::NewLine + '[truncated]')
}

function Resolve-MetraAskClientId {
    param(
        [string]$HeaderClient,
        [string]$BodyClient,
        [string]$UserAgent
    )

    $c = if (-not [string]::IsNullOrWhiteSpace($HeaderClient)) { $HeaderClient.Trim() }
    elseif (-not [string]::IsNullOrWhiteSpace($BodyClient)) { $BodyClient.Trim() }
    else { '' }
    if ($c -match '^(ops-web|ops-ios|cli|unknown)$') { return $c.ToLowerInvariant() }
    if (-not [string]::IsNullOrWhiteSpace($c)) { return $c }
    return 'unknown'
}

function Resolve-MetraAskClientHint {
    param(
        [string]$Client,
        [string]$UserAgent,
        [string]$BodyHint
    )

    if ($BodyHint -match '^(phone|desktop|tablet|unknown)$') { return $BodyHint.ToLowerInvariant() }
    if ($Client -eq 'ops-ios') { return 'phone' }
    $ua = [string]$UserAgent
    if ($ua -match '(?i)mobile|iphone|android') { return 'phone' }
    if ($ua -match '(?i)ipad|tablet') { return 'tablet' }
    if ($Client -eq 'ops-web' -or $Client -eq 'cli') { return 'desktop' }
    return 'unknown'
}

function Resolve-MetraAskOrigin {
    param(
        [bool]$IsLoopback,
        [bool]$HasLocalSession
    )

    if ($IsLoopback) { return 'loopback' }
    if ($HasLocalSession) { return 'localSession' }
    return 'remote'
}

function Get-MetraDeskPreferences {
    <#
    .SYNOPSIS
        Loads HTML Ops desk preferences (deskMode, optional Ops URL binding).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Get-MetraDeskPreferencesPath -MetraRoot $MetraRoot
    $defaults = [ordered]@{
        deskMode               = 'general'
        opsPort                = $null
        browserHost            = $null
        preferFriendlyUrl      = $null
        bindTailscale          = $false
        attentionVisibleCount  = 1
        editorCommand          = 'auto'
        updatedAt              = $null
    }
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]$defaults
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
        $mode = [string](Get-MetraProp -Object $raw -Name 'deskMode' -Default 'general')
        if ($mode -notin @('general', 'advanced')) { $mode = 'general' }
        $opsPort = Get-MetraProp -Object $raw -Name 'opsPort' -Default $null
        if ($null -ne $opsPort -and "$opsPort" -match '^\d+$') {
            $opsPort = [int]$opsPort
            if ($opsPort -lt 1 -or $opsPort -gt 65535) { $opsPort = $null }
        }
        else {
            $opsPort = $null
        }
        $prefer = Get-MetraProp -Object $raw -Name 'preferFriendlyUrl' -Default $null
        if ($null -ne $prefer) {
            $prefer = [bool]$prefer
        }
        $bindTs = Get-MetraProp -Object $raw -Name 'bindTailscale' -Default $false
        if ($null -ne $bindTs) {
            $bindTs = [bool]$bindTs
        }
        else {
            $bindTs = $false
        }
        $vis = Get-MetraProp -Object $raw -Name 'attentionVisibleCount' -Default 1
        try { $vis = [int]$vis } catch { $vis = 1 }
        if ($vis -lt 1) { $vis = 1 }
        if ($vis -gt 10) { $vis = 10 }
        $editorCommand = [string](Get-MetraProp -Object $raw -Name 'editorCommand' -Default 'auto')
        if ([string]::IsNullOrWhiteSpace($editorCommand)) { $editorCommand = 'auto' }
        return [PSCustomObject]@{
            deskMode               = $mode
            opsPort                = $opsPort
            browserHost            = (Get-MetraProp -Object $raw -Name 'browserHost' -Default $null)
            preferFriendlyUrl      = $prefer
            bindTailscale          = $bindTs
            attentionVisibleCount  = $vis
            editorCommand          = $editorCommand
            updatedAt              = (Get-MetraProp -Object $raw -Name 'updatedAt' -Default $null)
        }
    }
    catch {
        return [PSCustomObject]$defaults
    }
}

function Set-MetraDeskPreferences {
    <#
    .SYNOPSIS
        Writes HTML Ops desk preferences (local only).
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('general', 'advanced')]
        [string]$DeskMode,
        [int]$OpsPort,
        [string]$BrowserHost,
        [bool]$PreferFriendlyUrl,
        [bool]$BindTailscale,
        [int]$AttentionVisibleCount,
        [string]$EditorCommand,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $current = Get-MetraDeskPreferences -MetraRoot $MetraRoot
    if ($PSBoundParameters.ContainsKey('DeskMode')) {
        $current.deskMode = $DeskMode
    }
    if ($PSBoundParameters.ContainsKey('OpsPort')) {
        $current.opsPort = $OpsPort
    }
    if ($PSBoundParameters.ContainsKey('BrowserHost')) {
        $current.browserHost = $BrowserHost
    }
    if ($PSBoundParameters.ContainsKey('PreferFriendlyUrl')) {
        $current.preferFriendlyUrl = $PreferFriendlyUrl
    }
    if ($PSBoundParameters.ContainsKey('BindTailscale')) {
        $current.bindTailscale = $BindTailscale
    }
    if ($PSBoundParameters.ContainsKey('AttentionVisibleCount')) {
        $vis = $AttentionVisibleCount
        if ($vis -lt 1) { $vis = 1 }
        if ($vis -gt 10) { $vis = 10 }
        $current.attentionVisibleCount = $vis
    }
    if ($PSBoundParameters.ContainsKey('EditorCommand')) {
        $ed = $EditorCommand
        if ([string]::IsNullOrWhiteSpace($ed)) { $ed = 'auto' }
        $current.editorCommand = $ed.Trim()
    }
    $current.updatedAt = (Get-Date).ToString('o')
    $path = Get-MetraDeskPreferencesPath -MetraRoot $MetraRoot
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($current | ConvertTo-Json -Depth 4)
    [System.IO.File]::WriteAllText($path, $json + "`r`n")
    return $current
}

function Get-MetraDeskAskLog {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Limit = 20
    )

    $path = Get-MetraDeskAskLogPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
        $items = @($raw)
        if ($raw -is [PSCustomObject] -and $raw.PSObject.Properties.Name -contains 'items') {
            $items = @($raw.items)
        }
        return @($items | Select-Object -First $Limit)
    }
    catch {
        return @()
    }
}

function Add-MetraDeskAskEntry {
    <#
    .SYNOPSIS
        Appends one Session Journal turn (canonical Ask evidence). Cap 100 recent turns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [object]$Handoff,
        [string]$Message,
        [string]$SessionId,
        [string]$Origin = 'unknown',
        [string]$Client = 'unknown',
        [string]$ClientHint = 'unknown',
        [string]$Engine,
        [string]$Model,
        [bool]$Answered = $false,
        [object]$Capability,
        [string[]]$AttachmentIds = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $path = Get-MetraDeskAskLogPath -MetraRoot $MetraRoot
    $existing = @(Get-MetraDeskAskLog -MetraRoot $MetraRoot -Limit 100)
    $sess = if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $SessionId.Trim()
    }
    else {
        [guid]::NewGuid().ToString('N')
    }

    $maxIndex = 0
    foreach ($row in $existing) {
        $rowSess = [string](Get-MetraProp -Object $row -Name 'sessionId' -Default '')
        if ($rowSess -ne $sess) { continue }
        $ti = Get-MetraProp -Object $row -Name 'turnIndex' -Default $null
        if ($null -ne $ti) {
            $n = [int]$ti
            if ($n -gt $maxIndex) { $maxIndex = $n }
        }
    }

    $scrubbedPrompt = Invoke-MetraAskSecretsScrubText -Text $Prompt.Trim()
    $scrubbedMessage = Invoke-MetraAskSecretsScrubText -Text ([string]$Message)
    $cleanMessage = Truncate-MetraAskJournalMessage -Message (Remove-MetraAskUiChrome -Message ([string]$scrubbedMessage.Text))
    $entry = [PSCustomObject]@{
        id           = [guid]::NewGuid().ToString('N')
        sessionId    = $sess
        turnIndex    = $maxIndex + 1
        at           = (Get-Date).ToString('o')
        prompt       = [string]$scrubbedPrompt.Text
        message      = $cleanMessage
        handoff      = $Handoff
        engine       = $(if ([string]::IsNullOrWhiteSpace($Engine)) { $null } else { $Engine })
        model        = $(if ([string]::IsNullOrWhiteSpace($Model)) { $null } else { $Model })
        answered     = [bool]$Answered
        capability   = $Capability
        origin       = $Origin
        client       = $Client
        clientHint   = $ClientHint
        attachmentIds = @($AttachmentIds | ForEach-Object { [string]$_ } | Where-Object { $_ })
    }
    $items = @($entry) + @($existing) | Select-Object -First 100
    $payload = [ordered]@{
        schemaVersion = Get-MetraAskJournalSchemaVersion
        items         = @($items)
    }
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($path, (($payload | ConvertTo-Json -Depth 10) + "`r`n"))
    return $entry
}

function Get-MetraDeskAskSessionSummaries {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Limit = 12
    )

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
        $last = $ordered | Select-Object -Last 1
        [PSCustomObject]@{
            id         = [string]$g.Name
            sessionId  = [string]$g.Name
            turnCount  = $ordered.Count
            at         = [string](Get-MetraProp -Object $last -Name 'at' -Default '')
            prompt     = [string](Get-MetraProp -Object $first -Name 'prompt' -Default '')
            where      = [string](Get-MetraProp -Object (Get-MetraProp -Object $first -Name 'handoff' -Default $null) -Name 'where' -Default '')
            origin     = [string](Get-MetraProp -Object $first -Name 'origin' -Default '')
            client     = [string](Get-MetraProp -Object $first -Name 'client' -Default '')
            turns      = @($ordered | Select-Object id, turnIndex, at, prompt, origin, client)
        }
    }
    return @($summaries | Sort-Object at -Descending | Select-Object -First $Limit)
}

function Truncate-MetraAskContinuitySnippet {
    <#
    .SYNOPSIS
        Collapse whitespace and truncate for Ask continuity / recall prompts.
    #>
    param(
        [AllowNull()][string]$Text,
        [int]$Max = 160
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = ($Text.Trim() -replace '\s+', ' ')
    if ($t.Length -le $Max) { return $t }
    return ($t.Substring(0, [Math]::Max(1, $Max - 3)) + '...')
}

function Get-MetraDeskAskSessionTurns {
    <#
    .SYNOPSIS
        Ordered Session Journal turns for one Ask sessionId (oldest first).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Limit = 100
    )

    $sid = $SessionId.Trim()
    if ([string]::IsNullOrWhiteSpace($sid)) { return @() }

    $turns = @(Get-MetraDeskAskLog -MetraRoot $MetraRoot -Limit 100 | Where-Object {
            [string](Get-MetraProp -Object $_ -Name 'sessionId' -Default '') -eq $sid
        })
    $ordered = @($turns | Sort-Object {
            $ti = Get-MetraProp -Object $_ -Name 'turnIndex' -Default $null
            if ($null -ne $ti) { [int]$ti } else { 0 }
        }, { [string]$_.at })
    if ($Limit -gt 0 -and $ordered.Count -gt $Limit) {
        return @($ordered | Select-Object -Last $Limit)
    }
    return @($ordered)
}

function Search-MetraDeskAskJournal {
    <#
    .SYNOPSIS
        Keyword search over Session Journal prompts and answers (episodic recall).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$Limit = 20
    )

    $q = $Query.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) { return @() }

    $tokens = @(
        $q.ToLowerInvariant() -split '\s+' |
            Where-Object { $_.Length -ge 2 } |
            Select-Object -Unique
    )
    if ($tokens.Count -eq 0) {
        $tokens = @($q.ToLowerInvariant())
    }

    $hits = foreach ($row in @(Get-MetraDeskAskLog -MetraRoot $MetraRoot -Limit 100)) {
        $hay = (
            [string](Get-MetraProp -Object $row -Name 'prompt' -Default '') + ' ' +
            [string](Get-MetraProp -Object $row -Name 'message' -Default '')
        ).ToLowerInvariant()
        $ok = $true
        foreach ($tok in $tokens) {
            if ($hay.IndexOf($tok) -lt 0) { $ok = $false; break }
        }
        if (-not $ok) { continue }
        $rowSid = [string](Get-MetraProp -Object $row -Name 'sessionId' -Default '')
        if ([string]::IsNullOrWhiteSpace($rowSid)) {
            $rowSid = [string](Get-MetraProp -Object $row -Name 'id' -Default '')
        }
        [PSCustomObject]@{
            id        = [string](Get-MetraProp -Object $row -Name 'id' -Default '')
            sessionId = $rowSid
            turnIndex = Get-MetraProp -Object $row -Name 'turnIndex' -Default $null
            at        = [string](Get-MetraProp -Object $row -Name 'at' -Default '')
            prompt    = [string](Get-MetraProp -Object $row -Name 'prompt' -Default '')
            message   = Truncate-MetraAskContinuitySnippet -Text ([string](Get-MetraProp -Object $row -Name 'message' -Default '')) -Max 240
            where     = [string](Get-MetraProp -Object (Get-MetraProp -Object $row -Name 'handoff' -Default $null) -Name 'where' -Default '')
        }
    }
    return @($hits | Select-Object -First $Limit)
}

function New-MetraAskSessionSummaryText {
    <#
    .SYNOPSIS
        Extractive bullet summary of older Ask turns (not an LLM rewrite).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Turns,
        [int]$PromptMax = 120,
        [int]$MessageMax = 200,
        [int]$MaxBullets = 12
    )

    $lines = foreach ($t in @($Turns | Select-Object -First $MaxBullets)) {
        $ti = Get-MetraProp -Object $t -Name 'turnIndex' -Default $null
        $label = if ($null -ne $ti) { "Turn $ti" } else { 'Turn' }
        $p = Truncate-MetraAskContinuitySnippet -Text ([string](Get-MetraProp -Object $t -Name 'prompt' -Default '')) -Max $PromptMax
        $m = Truncate-MetraAskContinuitySnippet -Text ([string](Get-MetraProp -Object $t -Name 'message' -Default '')) -Max $MessageMax
        if ([string]::IsNullOrWhiteSpace($p) -and [string]::IsNullOrWhiteSpace($m)) { continue }
        $bit = if ($m) { "$p -> $m" } else { $p }
        "- ${label}: $bit"
    }
    return (($lines -join "`n").Trim())
}

function Get-MetraAskContinuityContext {
    <#
    .SYNOPSIS
        Build labeled Session Journal continuity for Ask (summary + recent; optional recall).
    #>
    [CmdletBinding()]
    param(
        [string]$SessionId,
        [string]$RecallSessionId,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$KeepRecent = 4,
        [int]$SummarizeAfterTurns = 4,
        [int]$CharBudget = 4000
    )

    $sid = if (-not [string]::IsNullOrWhiteSpace($SessionId)) { $SessionId.Trim() } else { '' }
    $recallSid = if (-not [string]::IsNullOrWhiteSpace($RecallSessionId)) { $RecallSessionId.Trim() } else { '' }

    $sessionSummary = $null
    $recentTurns = @()
    $usedSummarization = $false
    $summarizedTurnCount = 0
    $totalTurnCount = 0

    if ($sid) {
        $ordered = @(Get-MetraDeskAskSessionTurns -SessionId $sid -MetraRoot $MetraRoot -Limit 100)
        $totalTurnCount = $ordered.Count
        if ($ordered.Count -gt 0) {
            $keep = [Math]::Max(1, $KeepRecent)
            $needSummary = $ordered.Count -gt $SummarizeAfterTurns
            if (-not $needSummary) {
                $allChars = 0
                foreach ($t in $ordered) {
                    $allChars += ([string](Get-MetraProp -Object $t -Name 'prompt' -Default '')).Length
                    $allChars += ([string](Get-MetraProp -Object $t -Name 'message' -Default '')).Length
                }
                if ($allChars -gt $CharBudget -and $ordered.Count -gt $keep) {
                    $needSummary = $true
                }
            }

            if ($needSummary -and $ordered.Count -gt $keep) {
                $older = @($ordered | Select-Object -First ($ordered.Count - $keep))
                $recent = @($ordered | Select-Object -Last $keep)
                $sessionSummary = New-MetraAskSessionSummaryText -Turns $older
                $usedSummarization = -not [string]::IsNullOrWhiteSpace($sessionSummary)
                $summarizedTurnCount = $older.Count
                $recentTurns = @(
                    $recent | ForEach-Object {
                        [PSCustomObject]@{
                            turnIndex = Get-MetraProp -Object $_ -Name 'turnIndex' -Default $null
                            prompt    = Truncate-MetraAskContinuitySnippet -Text ([string](Get-MetraProp -Object $_ -Name 'prompt' -Default '')) -Max 200
                            message   = Truncate-MetraAskContinuitySnippet -Text ([string](Get-MetraProp -Object $_ -Name 'message' -Default '')) -Max 320
                        }
                    }
                )
            }
            else {
                $recentTurns = @(
                    $ordered | ForEach-Object {
                        [PSCustomObject]@{
                            turnIndex = Get-MetraProp -Object $_ -Name 'turnIndex' -Default $null
                            prompt    = Truncate-MetraAskContinuitySnippet -Text ([string](Get-MetraProp -Object $_ -Name 'prompt' -Default '')) -Max 200
                            message   = Truncate-MetraAskContinuitySnippet -Text ([string](Get-MetraProp -Object $_ -Name 'message' -Default '')) -Max 320
                        }
                    }
                )
            }
        }
    }

    $recallSummary = $null
    if ($recallSid -and $recallSid -ne $sid) {
        $recallTurns = @(Get-MetraDeskAskSessionTurns -SessionId $recallSid -MetraRoot $MetraRoot -Limit 100)
        if ($recallTurns.Count -gt 0) {
            $recallSummary = New-MetraAskSessionSummaryText -Turns $recallTurns -MaxBullets 10
        }
    }

    return [PSCustomObject]@{
        sessionId           = $(if ($sid) { $sid } else { $null })
        recallSessionId     = $(if ($recallSid) { $recallSid } else { $null })
        sessionSummary      = $sessionSummary
        recentTurns         = @($recentTurns)
        recallSummary       = $recallSummary
        usedSummarization   = [bool]$usedSummarization
        summarizedTurnCount = [int]$summarizedTurnCount
        recentTurnCount     = @($recentTurns).Count
        totalTurnCount      = [int]$totalTurnCount
    }
}

function Test-MetraDeskGreeting {
    <#
    .SYNOPSIS
        True when the Ask prompt is a short greeting, not a routing ask.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Query
    )

    $q = $Query.Trim()
    if ([string]::IsNullOrWhiteSpace($q) -or $q.Length -gt 64) {
        return $false
    }

    return [bool]($q -match '^(hi|hello|hey|howdy|yo|good\s+(morning|afternoon|evening))(\s*,?\s*metra)?[!?.]*$')
}

function Remove-MetraAskUiChrome {
    <#
    .SYNOPSIS
        Strip Cursor-chat persona banners and echoed routing cards from Ask answers.
    #>
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $Message }

    $droppingRouteCard = $false
    $kept = foreach ($line in ($Message -split '\r?\n')) {
        if ($line -match '^\s*\*{0,2}Metra\*{0,2}\s*[·•|]\s*Model\s*:') { continue }
        if ($line -match '^\s*\*{0,2}Metra\*{0,2}\s*[·•]' -and $line -match '(?i)model' -and $line -match '(?i)(cursor|composer|language\s+model)') {
            continue
        }
        if ($line -match '^\s*(Where|What|Why|Next|Also close|For whom)\s*:?\s*$') {
            $droppingRouteCard = $true
            continue
        }
        if ($droppingRouteCard) {
            if ($line -match '^\s*$') { $droppingRouteCard = $false; continue }
            if ($line -match '(?i)labeled preview') { continue }
            if ($line -match '^\s*(-|\*)') { continue }
            if ($line.Length -lt 120 -and $line -notmatch '^#{1,3}\s') { continue }
            $droppingRouteCard = $false
        }
        if ($line -match '(?i)labeled preview\s*-') { continue }
        $line
    }
    return (($kept -join "`n").Trim())
}

function Get-MetraDeskAskResult {
    <#
    .SYNOPSIS
        Ask result: route-first, then Ask engine when available; honest degrade otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$SessionId,
        [string]$RecallSessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $q = $Prompt.Trim()
    $handoff = Get-MetraDeskHandoff -Query $q -MetraRoot $MetraRoot
    # Ask path never uses greeting theater - route furniture only.
    if ($handoff.kind -eq 'greeting') {
        $handoff = [PSCustomObject]@{
            query     = $q
            kind      = 'route'
            preview   = $true
            where     = 'Metra'
            what      = [string]$handoff.what
            why       = @()
            forWhom   = @()
            next      = 'Stay on Metra until a stronger project route appears.'
            ambiguous = $false
            runnerUp  = $null
            score     = 0
            note      = $null
        }
    }

    $capability = Get-MetraAskCapability -MetraRoot $MetraRoot
    $cwd = Get-MetraAskRouteCwd -Where ([string]$handoff.where) -MetraRoot $MetraRoot

    # Ops owns Ask: revive a dead sidecar on demand. Ops used to start the engine once at desk
    # startup, so a sidecar that died later left Ask unavailable until the whole desk restarted.
    if (-not $capability.available -and $capability.selected) {
        $capability = Start-MetraAskEngine -MetraRoot $MetraRoot
    }

    $continuity = Get-MetraAskContinuityContext `
        -SessionId $SessionId `
        -RecallSessionId $RecallSessionId `
        -MetraRoot $MetraRoot

    if (-not $capability.available) {
        return [PSCustomObject]@{
            handoff         = $handoff
            message         = [string]$capability.message
            sessionId       = $null
            capability      = $capability
            engine          = $null
            model           = $null
            answered        = $false
            continuity      = $continuity
            secretsScrubbed = $false
            secretsNotice   = $null
            secretsKinds    = @()
            secretsReason   = $null
            scrubbedPrompt  = $q
        }
    }

    $promptScrub = Invoke-MetraAskSecretsScrubText -Text $q
    $enginePrompt = [string]$promptScrub.Text

    $context = @{
        where   = [string]$handoff.where
        what    = [string]$handoff.what
        why     = @($handoff.why)
        forWhom = @($handoff.forWhom)
        next    = [string]$handoff.next
        score   = [int]$handoff.score
    }
    if ($continuity.sessionSummary) {
        $context['sessionSummary'] = [string]$continuity.sessionSummary
    }
    if (@($continuity.recentTurns).Count -gt 0) {
        $context['recentTurns'] = @($continuity.recentTurns)
    }
    if ($continuity.recallSummary) {
        $context['recall'] = [string]$continuity.recallSummary
        $context['recallSessionId'] = [string]$continuity.recallSessionId
    }
    if ($continuity.usedSummarization -or $continuity.recallSummary) {
        $context['forceContinuity'] = $true
    }

    $ctxScrub = Invoke-MetraAskSecretsScrubObject -InputObject $context
    $safeContext = if ($null -ne $ctxScrub.Value) { $ctxScrub.Value } else { @{} }

    if ($promptScrub.Refuse -or $ctxScrub.Refuse) {
        $refuseReason = if ($promptScrub.Refuse) { [string]$promptScrub.Reason } else { [string]$ctxScrub.Reason }
        $refuseNotice = Join-MetraAskSecretsNotices -Notices @($promptScrub.Notice, $ctxScrub.Notice)
        if (-not $refuseNotice) {
            $refuseNotice = 'Private-key material was blocked and not sent to the Ask engine. Rephrase without the key block.'
        }
        return [PSCustomObject]@{
            handoff         = $handoff
            message         = [string]$refuseNotice
            sessionId       = $SessionId
            capability      = $capability
            engine          = $null
            model           = $null
            answered        = $false
            continuity      = $continuity
            secretsScrubbed = $true
            secretsNotice   = $refuseNotice
            secretsKinds    = @($promptScrub.Kinds) + @($ctxScrub.Kinds)
            secretsReason   = $refuseReason
            scrubbedPrompt  = $enginePrompt
        }
    }

    $engineResult = Invoke-MetraAskEngine -Prompt $enginePrompt -Cwd $cwd -Context $safeContext -SessionId $SessionId -MetraRoot $MetraRoot

    # A sidecar that died mid-session fails the call. Retry once after reviving, but only when
    # health says it is actually down - never re-run a prompt that merely took too long.
    if (-not $engineResult.ok -and [string](Get-MetraProp -Object $engineResult -Name 'error' -Default '') -ne 'secrets_refuse' -and -not (Test-MetraAskEngineHealth -MetraRoot $MetraRoot -TimeoutSec 2)) {
        $revived = Start-MetraAskEngine -MetraRoot $MetraRoot
        if ($revived.available) {
            $capability = $revived
            # Sessions live in the old process; start clean so the retry is not orphaned.
            # Journal continuity stays in context so the new agent can pick up the thread.
            $safeContext['forceContinuity'] = $true
            $engineResult = Invoke-MetraAskEngine -Prompt $enginePrompt -Cwd $cwd -Context $safeContext -MetraRoot $MetraRoot
        }
    }

    if ([string](Get-MetraProp -Object $engineResult -Name 'error' -Default '') -eq 'secrets_refuse' -or [bool](Get-MetraProp -Object $engineResult -Name 'secretsRefuse' -Default $false)) {
        $refuseNotice = [string](Get-MetraProp -Object $engineResult -Name 'secretsNotice' -Default '')
        if ([string]::IsNullOrWhiteSpace($refuseNotice)) {
            $refuseNotice = 'Private-key material was blocked and not sent to the Ask engine. Rephrase without the key block.'
        }
        $scrubbedFromEngine = [string](Get-MetraProp -Object $engineResult -Name 'scrubbedPrompt' -Default $enginePrompt)
        return [PSCustomObject]@{
            handoff         = $handoff
            message         = $refuseNotice
            sessionId       = $SessionId
            capability      = $capability
            engine          = $null
            model           = $null
            answered        = $false
            continuity      = $continuity
            secretsScrubbed = $true
            secretsNotice   = $refuseNotice
            secretsKinds    = @(Get-MetraProp -Object $engineResult -Name 'secretsKinds' -Default @())
            secretsReason   = [string](Get-MetraProp -Object $engineResult -Name 'secretsReason' -Default 'pem_private_key')
            scrubbedPrompt  = $scrubbedFromEngine
        }
    }

    if (-not $engineResult.ok -or [string]::IsNullOrWhiteSpace($engineResult.message)) {
        $failCap = [PSCustomObject]@{
            enabled       = $capability.enabled
            selected      = $capability.selected
            available     = $false
            engine        = $capability.engine
            providerLabel = $capability.providerLabel
            reason        = 'engine_error'
            message       = @"
Ask engine unavailable.

The Ask engine returned an error. Metra can still route work and recommend durable homes.
"@.Trim()
            port          = $capability.port
            model         = $capability.model
        }
        if ($engineResult.error) {
            $failCap | Add-Member -NotePropertyName detail -NotePropertyValue $engineResult.error -Force
        }
        $preNotice = Join-MetraAskSecretsNotices -Notices @(
            $(if ($promptScrub.Matched) { $promptScrub.Notice }),
            $(if ($ctxScrub.Matched) { $ctxScrub.Notice }),
            $(Get-MetraProp -Object $engineResult -Name 'secretsNotice' -Default $null)
        )
        return [PSCustomObject]@{
            handoff         = $handoff
            message         = Add-MetraAskSecretsNoticeToMessage -Message ([string]$failCap.message) -Notice $preNotice
            sessionId       = $null
            capability      = $failCap
            engine          = $capability.engine
            model           = $null
            answered        = $false
            continuity      = $continuity
            secretsScrubbed = [bool]($promptScrub.Matched -or $ctxScrub.Matched -or (Get-MetraProp -Object $engineResult -Name 'secretsScrubbed' -Default $false))
            secretsNotice   = $preNotice
            secretsKinds    = @($promptScrub.Kinds) + @($ctxScrub.Kinds)
            secretsReason   = $null
            scrubbedPrompt  = $enginePrompt
        }
    }

    $responseScrub = Invoke-MetraAskSecretsScrubText -Text ([string]$engineResult.message)
    $notice = Join-MetraAskSecretsNotices -Notices @(
        $(if ($promptScrub.Matched) { $promptScrub.Notice }),
        $(if ($ctxScrub.Matched) { $ctxScrub.Notice }),
        $(Get-MetraProp -Object $engineResult -Name 'secretsNotice' -Default $null),
        $(if ($responseScrub.Matched) { $responseScrub.Notice })
    )
    $cleanMessage = Remove-MetraAskUiChrome -Message ([string]$responseScrub.Text)
    $cleanMessage = Add-MetraAskSecretsNoticeToMessage -Message $cleanMessage -Notice $notice

    return [PSCustomObject]@{
        handoff         = $handoff
        message         = $cleanMessage
        sessionId       = [string]$engineResult.sessionId
        capability      = $capability
        engine          = [string]$engineResult.engine
        model           = [string]$engineResult.model
        answered        = $true
        continuity      = $continuity
        secretsScrubbed = [bool]($promptScrub.Matched -or $ctxScrub.Matched -or $responseScrub.Matched -or (Get-MetraProp -Object $engineResult -Name 'secretsScrubbed' -Default $false))
        secretsNotice   = $notice
        secretsKinds    = @($promptScrub.Kinds) + @($ctxScrub.Kinds) + @($responseScrub.Kinds)
        secretsReason   = $null
        scrubbedPrompt  = $enginePrompt
    }
}

function Get-MetraDeskHandoff {
    <#
        .SYNOPSIS
        Builds a labeled routing preview handoff for the HTML Ops Ask path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $q = $Query.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        return [PSCustomObject]@{
            query      = ''
            kind       = 'route'
            preview    = $true
            where      = $null
            what       = 'Enter a short question or symptom.'
            why        = @()
            forWhom    = @()
            next       = 'Type what you need help with, then Ask - or use Route something if you need a durable home.'
            ambiguous  = $false
            runnerUp   = $null
            score      = 0
        }
    }

    if (Test-MetraDeskGreeting -Query $q) {
        return [PSCustomObject]@{
            query     = $q
            kind      = 'greeting'
            preview   = $false
            where     = 'Metra'
            what      = 'Stay on Metra - this is home until something else is routed.'
            why       = @()
            forWhom   = @()
            next      = 'Describe the work and I will point at the right place.'
            ambiguous = $false
            runnerUp  = $null
            score     = 0
            note      = $null
        }
    }

    $amb = Get-MetraRoutingAmbiguity -Query $q
    $primary = $amb.Primary
    $runner = if ($amb.IsAmbiguous) { $amb.RunnerUp } else { $null }
    $ambiguous = [bool]$amb.IsAmbiguous

    $why = @()
    $serves = @()
    $purpose = ''
    if ($primary) {
        $why = @(ConvertTo-MetraSnapshotWhyHere -Project $primary.Name -MetraRoot $MetraRoot -Limit 3)
        try {
            $reg = Get-MetraProjectRegistry
            $row = @($reg.projects | Where-Object { [string]$_.name -eq [string]$primary.Name } | Select-Object -First 1)
            if ($row) {
                $purpose = [string](Get-MetraProp -Object $row -Name 'purpose' -Default '')
                $serves = @(Get-MetraProp -Object $row -Name 'serves' -Default @())
            }
        }
        catch { }
    }

    $whereName = if ($primary) { [string]$primary.Name } else { 'Metra' }
    $isHome = $whereName -eq (Get-MetraHomeDestinationName)
    $what = if ($purpose) { $purpose } elseif ($primary) { "Open $($primary.Name) and follow that project's AGENTS.md." } else { 'Stay on Metra until a stronger project route appears.' }
    $next = if ($isHome) {
        'Stay on Metra. Ask again with more detail, or use Route something if you need a durable home.'
    }
    elseif ($primary) {
        "Stay in $whereName. Continue Ask for answers, or open Cursor when you need to build."
    }
    else {
        'Stay on Metra, or enable Advanced desk and browse Projects.'
    }

    return [PSCustomObject]@{
        query     = $q
        kind      = 'route'
        preview   = $true
        where     = $whereName
        what      = $what
        why       = @($why | ForEach-Object {
                $d = [string](Get-MetraProp -Object $_ -Name 'decision' -Default '')
                $w = [string](Get-MetraProp -Object $_ -Name 'why' -Default '')
                if ($d -and $w) { "$d - $w" }
                elseif ($d) { $d }
                elseif ($w) { $w }
                else { [string]$_ }
            } | Where-Object { $_ })
        forWhom   = @($serves)
        next      = $next
        ambiguous = [bool]$ambiguous
        runnerUp  = if ($runner -and $ambiguous) { [string]$runner.Name } else { $null }
        score     = if ($primary) { [int]$primary.Score } else { 0 }
        note      = if ($isHome -and ([int]($primary.Score) -lt 2)) {
            'Home destination - Metra stays primary until a stronger project route wins.'
        }
        else {
            'Labeled preview - authoritative Why Here remains routing -Query / ctx -Query.'
        }
    }
}

function ConvertTo-MetraDeskPayload {
    <#
    .SYNOPSIS
        Shapes canvas-snapshot.json into the HTML Ops desk payload (one brain, many faces).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $stale = $false
    try {
        $stale = [bool](Test-MetraCanvasSnapshotStale)
    }
    catch {
        $stale = $true
    }

    $todos = @($Snapshot.todos)
    $gitChecked = $true
    if ($null -ne $Snapshot.gitChecked) {
        $gitChecked = [bool]$Snapshot.gitChecked
    }
    elseif ([string]$Snapshot.mode -eq 'quick') {
        $gitChecked = $false
    }
    $verifyChecked = [bool]$Snapshot.verifyChecked
    $scanMode = if ($gitChecked) { 'full' } else { 'quick' }
    if ([string]$Snapshot.mode -eq 'full') { $scanMode = 'full' }
    elseif ([string]$Snapshot.mode -eq 'quick') { $scanMode = 'quick' }

    # Derive queue from snapshot (do not drop git on quick - memory reconcile owns coveredKinds).
    $attentionQueue = @(
        foreach ($todo in $todos) {
            $kind = [string](Get-MetraProp -Object $todo -Name 'kind' -Default '')
            $project = [string](Get-MetraProp -Object $todo -Name 'project' -Default '')
            $content = [string](Get-MetraProp -Object $todo -Name 'content' -Default '')
            $existingId = [string](Get-MetraProp -Object $todo -Name 'id' -Default '')
            if (-not $existingId) {
                $existingId = Get-MetraAttentionKey -Project $project -Kind $kind -Content $content
            }
            $command = if ($kind -eq 'git' -and $project) {
                ".\metra.ps1 status -Name $project"
            }
            elseif ($project) {
                ".\metra.ps1 audit -Name $project"
            }
            else {
                '.\metra.ps1 audit -DriftOnly'
            }
            $source = 'snapshot'
            if ($kind -eq 'decision') { $source = 'decision' }
            elseif ($kind -eq 'contract') { $source = 'contract' }
            [PSCustomObject]@{
                id       = $existingId
                project  = $project
                content  = $content
                kind     = $kind
                command  = $command
                source   = $source
            }
        }
    )
    foreach ($decision in @((Get-MetraProp -Object (Get-MetraProp -Object $Snapshot -Name 'decisions' -Default $null) -Name 'candidates' -Default @()))) {
        $title = [string](Get-MetraProp -Object $decision -Name 'title' -Default '')
        if (-not $title) { continue }
        $id = [string](Get-MetraProp -Object $decision -Name 'id' -Default '')
        $attentionQueue += [PSCustomObject]@{
            id       = if ($id) { "decision:$id" } else { "decision:$title" }
            project  = [string](Get-MetraProp -Object $decision -Name 'project' -Default '')
            content  = $title
            kind     = 'decision'
            command  = '.\metra.ps1 decisions show'
            source   = 'decision'
        }
    }
    foreach ($guideline in @((Get-MetraProp -Object (Get-MetraProp -Object $Snapshot -Name 'contract' -Default $null) -Name 'candidates' -Default @()))) {
        $text = [string](Get-MetraProp -Object $guideline -Name 'text' -Default '')
        if (-not $text) { continue }
        $id = [string](Get-MetraProp -Object $guideline -Name 'id' -Default '')
        $attentionQueue += [PSCustomObject]@{
            id       = if ($id) { "contract:$id" } else { "contract:$text" }
            project  = ''
            content  = $text
            kind     = 'contract'
            command  = '.\metra.ps1 profile show'
            source   = 'contract'
        }
    }

    # Ticket watch: full scan only. Fail-soft - never break desk payload.
    # Quick scan must not cover ticket (no surprise help-desk polling).
    $ticketCovered = $false
    if ($scanMode -eq 'full') {
        try {
            $tt = Get-MetraTicketTrackerProject
            if ($tt) {
                $ticketCfg = Get-MetraTicketWatchConfig -MetraRoot $MetraRoot
                # Local cache by default; syncOnSnapshot opts in to pulling iSupport on a full refresh.
                $candidates = Get-MetraTicketWatchCandidates `
                    -ModulePath $tt.ModulePath `
                    -Top ([int]$ticketCfg.top) `
                    -DoSync ([bool]$ticketCfg.syncOnSnapshot)
                foreach ($t in @($candidates.Tickets)) {
                    $qi = ConvertTo-MetraTicketAttentionQueueItem -Ticket $t -TicketTrackerPath $tt.Path
                    if ($qi) { $attentionQueue += $qi }
                }
                # Truncated list is not full coverage - do not auto-close tickets past the cap.
                $ticketCovered = -not [bool](Get-MetraProp -Object $candidates -Name 'Truncated' -Default $false)
            }
            else {
                Write-Warning 'TicketTracker project or module not present; ticket watch skipped.'
            }
        }
        catch {
            Write-Warning ("Ticket watch scan skipped: {0}" -f $_.Exception.Message)
        }
    }

    $coveredKinds = @('drift', 'decision', 'contract')
    if ($gitChecked) { $coveredKinds += 'git' }
    if ($verifyChecked) { $coveredKinds += 'verify' }
    if ($ticketCovered) { $coveredKinds += 'ticket' }

    $memory = Update-MetraAttentionMemory `
        -Queue $attentionQueue `
        -CoveredKinds $coveredKinds `
        -ScanMode $scanMode `
        -MetraRoot $MetraRoot

    $prefs = Get-MetraDeskPreferences -MetraRoot $MetraRoot
    $visibleCount = 1
    try { $visibleCount = [int]$prefs.attentionVisibleCount } catch { $visibleCount = 1 }
    if ($visibleCount -lt 1) { $visibleCount = 1 }
    if ($visibleCount -gt 10) { $visibleCount = 10 }

    $ranked = @(Get-MetraAttentionActiveItems -Memory $memory)
    $held = @(
        @($memory.items) | Where-Object { [string]$_.state -eq 'held' } |
            Sort-Object @{ Expression = { [string]$_.content } }
    )
    $notRecheckedCount = @($ranked | Where-Object { $_.notRecheckedSince }).Count

    $activeViews = @()
    for ($i = 0; $i -lt $ranked.Count; $i++) {
        $activeViews += ConvertTo-MetraDeskAttentionView -MemItem $ranked[$i] -RankIndex $i -ActiveCount $ranked.Count -Snapshot $Snapshot
    }
    $heldViews = @()
    foreach ($h in $held) {
        $heldViews += ConvertTo-MetraDeskAttentionView -MemItem $h -RankIndex 0 -ActiveCount 1 -Snapshot $Snapshot
    }

    $nextAttention = $null
    if ($activeViews.Count -gt 0) {
        $nextAttention = $activeViews[0]
    }

    $attentionCount = $activeViews.Count
    $attentionBlock = [PSCustomObject]@{
        active             = @($activeViews)
        activeCount        = $activeViews.Count
        notRecheckedCount  = $notRecheckedCount
        coveredKinds       = @($coveredKinds)
        visibleCount       = $visibleCount
        held               = @($heldViews)
        heldCount          = $heldViews.Count
        holdRoutingHint    = if ($heldViews.Count -gt 0) {
            'For lasting work, prefer a ticket or a saved decision. Keep in view is only temporary parking.'
        }
        else { $null }
    }

    $projects = @(
        @($Snapshot.projects) | ForEach-Object {
            [PSCustomObject]@{
                name    = [string]$_.name
                purpose = [string]$_.purpose
                present = [bool]$_.present
                root    = [string]$_.root
                status  = [string]$_.status
                optional = [bool]$_.optional
                hasAgentsMd = [bool]$_.hasAgentsMd
                pinned      = [bool]$_.pinned
                capabilities = @($_.capabilities)
                serves       = @($_.serves)
                gitIsRepo    = [bool]$_.gitIsRepo
                gitDirty     = [int]$_.gitDirty
                gitAhead     = [int]$_.gitAhead
                gitBehind    = [int]$_.gitBehind
                gitBranch    = [string]$_.gitBranch
                gitSummary   = [string]$_.gitSummary
                gitRepoPath  = [string]$_.gitRepoPath
            }
        }
    )

    $missingAgents = @(
        $projects |
            Where-Object { $_.present -and -not $_.hasAgentsMd } |
            Select-Object -ExpandProperty name |
            Sort-Object |
            Select-Object -First 12
    )

    $manifest = $null
    try {
        $psd1 = Join-Path $MetraRoot 'scripts\Metra.psd1'
        if (Test-Path -LiteralPath $psd1) {
            $data = Import-PowerShellDataFile -Path $psd1
            $manifest = [string]$data.ModuleVersion
        }
    }
    catch { }

    $recent = @(Get-MetraDeskAskSessionSummaries -MetraRoot $MetraRoot -Limit 12)
    $captures = @(Get-MetraCaptureLedger -MetraRoot $MetraRoot -Limit 20 -Status candidate)
    $askCapability = Get-MetraAskCapability -MetraRoot $MetraRoot

    $editorInfo = $null
    try {
        $resolvedEditor = Resolve-MetraOpsEditor -Preference ([string](Get-MetraProp -Object $prefs -Name 'editorCommand' -Default 'auto')) -MetraRoot $MetraRoot
        $editorInfo = [PSCustomObject]@{
            preference = [string]$resolvedEditor.Preference
            kind       = [string]$resolvedEditor.Kind
            label      = [string]$resolvedEditor.Label
        }
    }
    catch { }

    $emptyHint = $null
    if (-not $nextAttention) {
        if ($scanMode -ne 'full' -or -not $gitChecked) {
            $emptyHint = 'Nothing waiting from this quick check. Some areas were not reviewed. Run a full refresh to confirm.'
        }
        else {
            $emptyHint = 'Nothing waiting. The last full check found no open items.'
        }
    }

    return [PSCustomObject]@{
        generatedAt        = [string]$Snapshot.generatedAt
        mode               = [string]$Snapshot.mode
        stale              = $stale
        gitChecked         = $gitChecked
        verifyChecked      = $verifyChecked
        nextAttention      = $nextAttention
        attentionCount     = $attentionCount
        attentionEmptyHint = $emptyHint
        attention          = $attentionBlock
        projects           = $projects
        health             = [PSCustomObject]@{
            missingAgents      = @($missingAgents)
            missingAgentsCount = [int]$Snapshot.missingAgents
            gitChecked         = $gitChecked
            gitStatusLabel     = $(if ($gitChecked) { 'checked' } else { 'not checked (quick snapshot)' })
            snapshotStale      = $stale
            projectCount       = [int]$Snapshot.projectCount
            driftCount         = [int]$Snapshot.driftCount
        }
        recent             = $recent
        captures           = $captures
        preferences        = $prefs
        ask                = [PSCustomObject]@{
            enabled       = [bool]$askCapability.enabled
            selected      = [bool]$askCapability.selected
            available     = [bool]$askCapability.available
            engine        = [string]$askCapability.engine
            providerLabel = [string]$askCapability.providerLabel
            reason        = [string]$askCapability.reason
        }
        meta               = [PSCustomObject]@{
            version   = $manifest
            metraRoot = $MetraRoot
            homeLabel = $MetraRoot
            editor    = $editorInfo
        }
    }
}

function Get-MetraDeskPayload {
    <#
    .SYNOPSIS
        Returns the HTML Ops desk payload from the shared canvas snapshot brain.
    .PARAMETER Refresh
        Rebuild snapshot first (Quick by default unless -Full).
    .PARAMETER Full
        With -Refresh, run a full snapshot (git + verify).
    #>
    [CmdletBinding()]
    param(
        [switch]$Refresh,
        [switch]$Full,
        [int]$ScanDepth = 2,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $snapPath = Join-Path $MetraRoot 'docs\canvas-snapshot.json'
    if ($Refresh -or -not (Test-Path -LiteralPath $snapPath)) {
        $null = Export-MetraCanvasSnapshot -Quick:(-not $Full) -ScanDepth $ScanDepth
    }

    if (-not (Test-Path -LiteralPath $snapPath)) {
        throw "Desk snapshot missing at $snapPath"
    }

    $snapshot = Get-Content -LiteralPath $snapPath -Raw | ConvertFrom-Json
    return ConvertTo-MetraDeskPayload -Snapshot $snapshot -MetraRoot $MetraRoot
}

