# Generated from the original Metra.psm1 domain split. Edit this file directly.

function ConvertTo-MetraDisplayPath {
    <#
    .SYNOPSIS
        Returns a context-pack-safe display path.
    .DESCRIPTION
        Prefers RawPath (often env-style). Scrubs expanded profile paths so packs do not
        leak usernames under C:\Users\...
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$RawPath
    )

    $display = $RawPath
    if ([string]::IsNullOrWhiteSpace($display)) {
        $display = $Path
    }

    if ([string]::IsNullOrWhiteSpace($display)) {
        return ''
    }

    if ($display -match '(?i)[\\/]Users[\\/][^\\/]+[\\/]') {
        if (-not [string]::IsNullOrWhiteSpace($RawPath)) {
            return $RawPath
        }
        return '%USERPROFILE%\...'
    }

    return $display
}

function Format-MetraContextText {
    <#
    .SYNOPSIS
        Collapses whitespace and bounds free-text for context-pack Markdown.
    #>
    param(
        [AllowNull()][string]$Text,
        [int]$MaxChars = 500
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $clean = ($Text -replace '\r?\n', ' ' -replace '\t', ' ' -replace '\s+', ' ').Trim()
    if ($clean.Length -gt $MaxChars) {
        return $clean.Substring(0, $MaxChars - 3) + '...'
    }
    return $clean
}

function Test-MetraOrderedKey {
    <#
    .SYNOPSIS
        True when an ordered/hashtable pack has the given key.
    .DESCRIPTION
        OrderedDictionary exposes Contains(key), not ContainsKey. Prefer this over either
        method name so StrictMode and dictionary type stay aligned.
    #>
    param(
        [Parameter(Mandatory)]$Pack,
        [Parameter(Mandatory)][string]$Key
    )

    if ($null -eq $Pack) { return $false }
    return @($Pack.Keys) -contains $Key
}

function Export-MetraContextPack {
    <#
    .SYNOPSIS
        Build a bounded agent-facing context pack (roots + present routing).
    .DESCRIPTION
        Token-safe map for humans and agents. Does not dump canvas-snapshot inventory.
        Prefer relative or env-style personal roots when echoing paths.
        Project field "root" is a configured root name (work, personal, ...), not a filesystem path.
    #>
    [CmdletBinding()]
    param(
        [string]$Query,
        [string]$Path,
        [ValidateSet('markdown', 'json')]
        [string]$Format = 'markdown',
        [ValidateRange(1, 100)]
        [int]$Limit = 25,
        [switch]$Quiet
    )

    $metraRoot = Get-MetraRoot

    $roots = @(Get-MetraRoots -IncludeMissing | ForEach-Object {
            [PSCustomObject]@{
                name     = $_.Name
                primary  = [bool]$_.Primary
                exists   = [bool]$_.Exists
                optional = [bool]$_.Optional
                path     = ConvertTo-MetraDisplayPath -Path $_.Path -RawPath $_.RawPath
            }
        })

    $registry = Get-MetraProjectRegistry
    $disk = @{}
    foreach ($p in @(Get-MetraProjects)) {
        $disk[$p.Name.ToLowerInvariant()] = $p
    }

    $tokens = @()
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $tokens = @(
            ($Query.ToLowerInvariant() -split '[^a-z0-9_+]+') |
                Where-Object { $_ -and $_.Length -gt 1 } |
                Select-Object -Unique
        )
    }

    $scored = New-Object System.Collections.Generic.List[object]
    $registryProjects = @(Get-MetraProp -Object $registry -Name 'projects' -Default @())
    foreach ($reg in $registryProjects) {
        $regName = [string]$reg.name
        $onDisk = $disk[$regName.ToLowerInvariant()]
        if (-not $onDisk) { continue }

        $purpose = [string](Get-MetraProp -Object $reg -Name 'purpose' -Default '')
        $triggers = @(Get-MetraProp -Object $reg -Name 'triggers' -Default @())
        $whenPresent = [string](Get-MetraProp -Object $reg -Name 'whenPresent' -Default '')
        $score = 0
        if ($tokens.Count -gt 0) {
            $hay = (@($regName) + $triggers + @($purpose) | ForEach-Object { [string]$_ }) -join ' '
            $hayLower = $hay.ToLowerInvariant()
            foreach ($t in $tokens) {
                if ($hayLower.Contains($t)) { $score++ }
                if ($regName.ToLowerInvariant() -eq $t) { $score += 2 }
            }
            if ($score -le 0) { continue }
        }
        else {
            $score = 1
        }

        $relatedRows = @(Get-MetraRelatedProjects -Name $regName -SourceRoot ([string]$onDisk.Root) -Registry $registry -DiskByName $disk)

        [void]$scored.Add([PSCustomObject]@{
                name         = $regName
                root         = [string]$onDisk.Root
                purpose      = $purpose
                triggers     = @($triggers)
                capabilities = @(Get-MetraProp -Object $reg -Name 'capabilities' -Default @())
                serves       = @(Get-MetraProp -Object $reg -Name 'serves' -Default @())
                whenPresent  = $whenPresent
                related      = @($relatedRows)
                entry        = [string](Get-MetraProp -Object $reg -Name 'entry' -Default 'AGENTS.md')
                score        = $score
            })
    }

    # Also include present disk projects with no registry row (bounded).
    if ($tokens.Count -eq 0) {
        foreach ($p in @(Get-MetraProjects)) {
            $exists = $false
            foreach ($s in $scored) {
                if ($s.name -eq $p.Name) { $exists = $true; break }
            }
            if ($exists) { continue }
            [void]$scored.Add([PSCustomObject]@{
                    name         = $p.Name
                    root         = [string]$p.Root
                    purpose      = ''
                    triggers     = @()
                    capabilities = @()
                    serves       = @()
                    whenPresent  = ''
                    related      = @()
                    entry        = 'AGENTS.md'
                    score        = 0
                })
        }
    }

    $projects = @(
        $scored |
            Sort-Object @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.name } } |
            Select-Object -First $Limit
    )

    $missingOptional = @(
        Get-MetraRoutingTable |
            Where-Object { -not $_.Present -and $_.Optional } |
            Select-Object -First 10 |
            ForEach-Object {
                [PSCustomObject]@{
                    name   = $_.Name
                    advice = $_.Advice
                }
            }
    )

    $pack = [ordered]@{
        version      = 1
        product      = 'Metra'
        generatedUtc = [DateTime]::UtcNow.ToString('o')
        query        = if ($Query) { $Query } else { $null }
        reminders    = @(
            'Route to one primary project; load that project AGENTS.md before broad search.'
            'Ticket/helpdesk: TicketTracker first when present, then one technical project.'
            'Keep work and personal roots isolated unless the user names a cross-root handoff.'
            'Related projects in ctx are topology only - open them only when evidence requires it.'
            'CLI: .\metra.ps1 routing | audit | chats | ctx'
        )
        roots           = @($roots)
        projects        = @($projects | ForEach-Object {
                [ordered]@{
                    name         = $_.name
                    root         = $_.root
                    purpose      = $_.purpose
                    triggers     = @($_.triggers)
                    capabilities = @($_.capabilities)
                    serves       = @($_.serves)
                    related      = @($_.related | ForEach-Object { [string]$_.Name })
                    entry        = $_.entry
                }
            })
        missingOptional = @($missingOptional)
    }

    if ($tokens.Count -gt 0 -and $projects.Count -gt 0) {
        $primaryName = [string]$projects[0].name
        $primaryProj = $projects[0]
        $pack['whyHereFor'] = $primaryName
        $pack['projectStoryFor'] = $primaryName
        $story = [ordered]@{
            purpose  = [string]$primaryProj.purpose
            triggers = @($primaryProj.triggers)
            serves   = @($primaryProj.serves)
            related  = @(
                $primaryProj.related | ForEach-Object {
                    [ordered]@{
                        name    = [string]$_.Name
                        present = [bool]$_.Present
                    }
                }
            )
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$primaryProj.whenPresent)) {
            $story['whenPresent'] = [string]$primaryProj.whenPresent
        }
        $pack['projectStory'] = $story

        $whyHits = @(Get-MetraWhyHere -Project $primaryName -Query $Query -Limit 3 -MetraRoot $metraRoot)
        $pack['relatedDecisions'] = @(
            $whyHits | ForEach-Object {
                [ordered]@{
                    id         = $_.Id
                    title      = $_.Title
                    decision   = $_.Decision
                    why        = $_.Why
                    project    = $_.Project
                    confidence = $_.Confidence
                    source     = $_.Source
                }
            }
        )

        # Bounded Atlas citations (retrieve-on-demand). Never always-on / Ask / OCC.
        $pack['atlasCitations'] = @()
        try {
            $atlasRoot = Get-MetraAtlasProjectPath -MetraRoot $metraRoot
            if ($atlasRoot -and -not [string]::IsNullOrWhiteSpace($Query)) {
                $atlasCli = Join-Path $atlasRoot 'Atlas.ps1'
                $healthOut = & $atlasCli health 2>$null
                # Prefer module import for structured hits
                Import-Module (Join-Path $atlasRoot 'module\IWU.Atlas.psd1') -Force -ErrorAction Stop
                $health = Test-AtlasHealth
                if ($health -and $health.Reachable) {
                    $hits = @(Find-AtlasPage -Query $Query -Top 3)
                    $pack['atlasCitations'] = @(
                        $hits | ForEach-Object {
                            [ordered]@{
                                stableId = $_.stableId
                                title    = $_.title
                                project  = $_.project
                                kind     = $_.kind
                                url      = $_.url
                                provider = $_.provider
                                mode     = $_.mode
                                cite     = (Format-AtlasCite -Citation $_)
                            }
                        }
                    )
                }
            }
        }
        catch {
            $pack['atlasCitations'] = @()
            $pack['atlasUnavailable'] = [string]$_.Exception.Message
        }

        $amb = Get-MetraRoutingAmbiguity -Query $Query -Source ctx
        if ($amb.IsAmbiguous -and $amb.RunnerUp) {
            $runnerName = [string]$amb.RunnerUp.Name
            $pack['whyNotFor'] = $runnerName
            $pack['favoredTokens'] = @($amb.FavoredTokens)
            $runnerHits = @(Get-MetraWhyHere -Project $runnerName -Query $Query -Limit 2 -MetraRoot $metraRoot)
            $pack['runnerUpDecisions'] = @(
                $runnerHits | ForEach-Object {
                    [ordered]@{
                        id         = $_.Id
                        title      = $_.Title
                        decision   = $_.Decision
                        why        = $_.Why
                        project    = $_.Project
                        confidence = $_.Confidence
                        source     = $_.Source
                    }
                }
            )
        }
    }

    $defaultMd = Get-MetraContextPackPath -Format md
    $defaultJson = Get-MetraContextPackPath -Format json
    $outPath = $Path
    $stdoutOnly = $false
    $writingDefault = [string]::IsNullOrWhiteSpace($Path)
    if ($writingDefault) {
        $outPath = if ($Format -eq 'json') { $defaultJson } else { $defaultMd }
        $outParent = Split-Path -Parent $outPath
        if ($outParent -and -not (Test-Path -LiteralPath $outParent)) {
            [void][System.IO.Directory]::CreateDirectory($outParent)
        }
    }
    elseif ($outPath.Trim() -eq '-') {
        $stdoutOnly = $true
    }

    $jsonText = $pack | ConvertTo-Json -Depth 12
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine('# Metra context pack')
    [void]$md.AppendLine('')
    [void]$md.AppendLine(('Generated: {0}' -f $pack.generatedUtc))
    if ($Query) {
        [void]$md.AppendLine(('Query: {0}' -f $Query))
    }
    [void]$md.AppendLine('')
    [void]$md.AppendLine('## Reminders')
    [void]$md.AppendLine('')
    foreach ($r in $pack.reminders) {
        [void]$md.AppendLine(('- {0}' -f $r))
    }
    [void]$md.AppendLine('')
    [void]$md.AppendLine('## Roots')
    [void]$md.AppendLine('')
    foreach ($root in $roots) {
        $flags = @()
        if ($root.primary) { $flags += 'primary' }
        if ($root.optional) { $flags += 'optional' }
        $flags += $(if ($root.exists) { 'exists' } else { 'missing' })
        [void]$md.AppendLine(('- **{0}** ({1}): `{2}`' -f $root.name, ($flags -join ', '), $root.path))
    }
    [void]$md.AppendLine('')
    [void]$md.AppendLine(('## Present projects (up to {0})' -f $Limit))
    [void]$md.AppendLine('')
    foreach ($proj in $projects) {
        $trig = if ($proj.triggers.Count -gt 0) { ($proj.triggers -join ', ') } else { '(none)' }
        $purp = if ($proj.purpose) {
            Format-MetraContextText -Text $proj.purpose -MaxChars 240
        }
        else {
            '(no registry purpose)'
        }
        # root is configured root name (work/personal/...), not a filesystem path
        [void]$md.AppendLine(('- **{0}** [{1}] - {2}' -f $proj.name, $proj.root, $purp))
        [void]$md.AppendLine(('  - triggers: {0}' -f $trig))
        $servesList = @($proj.serves | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($servesList.Count -gt 0) {
            [void]$md.AppendLine(('  - serves: {0}' -f ($servesList -join ', ')))
        }
        $relatedNames = @($proj.related | ForEach-Object { [string]$_.Name } | Where-Object { $_ })
        if ($relatedNames.Count -gt 0) {
            [void]$md.AppendLine(('  - related: {0}' -f ($relatedNames -join ', ')))
        }
        [void]$md.AppendLine(('  - entry: {0}' -f $proj.entry))
    }
    if ($missingOptional.Count -gt 0) {
        [void]$md.AppendLine('')
        [void]$md.AppendLine('## Missing optional stubs')
        [void]$md.AppendLine('')
        foreach ($m in $missingOptional) {
            $advice = Format-MetraContextText -Text $m.advice -MaxChars 240
            [void]$md.AppendLine(('- **{0}**: {1}' -f $m.name, $advice))
        }
    }
    if ($tokens.Count -gt 0 -and $projects.Count -gt 0) {
        $primaryServes = @($projects[0].serves | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($primaryServes.Count -gt 0) {
            [void]$md.AppendLine('')
            [void]$md.AppendLine(('## For whom? {0}' -f $projects[0].name))
            [void]$md.AppendLine('')
            foreach ($s in $primaryServes) {
                [void]$md.AppendLine(('- {0}' -f $s))
            }
        }

        if (Test-MetraOrderedKey -Pack $pack -Key 'projectStory') {
            $story = $pack.projectStory
            [void]$md.AppendLine('')
            [void]$md.AppendLine(('## Project story {0}' -f $pack.projectStoryFor))
            [void]$md.AppendLine('')
            $storyPurp = if ($story.purpose) {
                Format-MetraContextText -Text ([string]$story.purpose) -MaxChars 240
            }
            else {
                '(no registry purpose)'
            }
            [void]$md.AppendLine(('- purpose: {0}' -f $storyPurp))
            $storyTrig = if (@($story.triggers).Count -gt 0) { (@($story.triggers) -join ', ') } else { '(none)' }
            [void]$md.AppendLine(('- triggers: {0}' -f $storyTrig))
            $storyServes = @($story.serves | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($storyServes.Count -gt 0) {
                [void]$md.AppendLine(('- serves: {0}' -f ($storyServes -join ', ')))
            }
            $storyRelatedParts = @(
                @($story.related) | ForEach-Object {
                    $n = [string]$_.name
                    if ([string]::IsNullOrWhiteSpace($n)) { return }
                    if ($_.present) { '{0} (present)' -f $n } else { '{0} (missing)' -f $n }
                }
            )
            if ($storyRelatedParts.Count -gt 0) {
                [void]$md.AppendLine(('- related: {0}' -f ($storyRelatedParts -join ', ')))
            }
            if ((Test-MetraOrderedKey -Pack $story -Key 'whenPresent') -and -not [string]::IsNullOrWhiteSpace([string]$story.whenPresent)) {
                [void]$md.AppendLine(('- whenPresent: {0}' -f (Format-MetraContextText -Text $story.whenPresent -MaxChars 240)))
            }
        }
    }
    if ((Test-MetraOrderedKey -Pack $pack -Key 'relatedDecisions') -and @($pack.relatedDecisions).Count -gt 0) {
        [void]$md.AppendLine('')
        $whyFor = if (Test-MetraOrderedKey -Pack $pack -Key 'whyHereFor') { [string]$pack.whyHereFor } else { '' }
        [void]$md.AppendLine(('## Why here?{0}' -f $(if ($whyFor) { ' ' + $whyFor } else { '' })))
        [void]$md.AppendLine('')
        foreach ($d in @($pack.relatedDecisions)) {
            $conf = [string]$d.confidence
            $confPart = if ($conf -and $conf.ToLowerInvariant() -ne 'high') { ' (' + $conf + ')' } else { '' }
            [void]$md.AppendLine(('- **{0}**{1} [{2}]' -f $d.title, $confPart, $d.id))
            [void]$md.AppendLine(('  - decision: {0}' -f (Format-MetraContextText -Text $d.decision -MaxChars 300)))
            [void]$md.AppendLine(('  - why: {0}' -f (Format-MetraContextText -Text $d.why -MaxChars 300)))
        }
    }
    if ((Test-MetraOrderedKey -Pack $pack -Key 'atlasCitations') -and @($pack.atlasCitations).Count -gt 0) {
        [void]$md.AppendLine('')
        [void]$md.AppendLine('## Atlas (bounded)')
        [void]$md.AppendLine('')
        foreach ($a in @($pack.atlasCitations)) {
            [void]$md.AppendLine(('- {0} ({1}/{2}) [{3}]' -f $a.title, $a.provider, $a.mode, $a.stableId))
            if ($a.cite) {
                [void]$md.AppendLine(('  - cite: {0}' -f $a.cite))
            }
        }
    }
    if (Test-MetraOrderedKey -Pack $pack -Key 'whyNotFor') {
        [void]$md.AppendLine('')
        [void]$md.AppendLine(('## Why not? {0}' -f $pack.whyNotFor))
        [void]$md.AppendLine('')
        if ((Test-MetraOrderedKey -Pack $pack -Key 'favoredTokens') -and @($pack.favoredTokens).Count -gt 0) {
            [void]$md.AppendLine(('- Query tokens favored the primary for: {0}' -f ($pack.favoredTokens -join ', ')))
        }
        foreach ($d in @($pack.runnerUpDecisions)) {
            $conf = [string]$d.confidence
            $confPart = if ($conf -and $conf.ToLowerInvariant() -ne 'high') { ' (' + $conf + ')' } else { '' }
            [void]$md.AppendLine(('- **{0}**{1} [{2}]' -f $d.title, $confPart, $d.id))
            [void]$md.AppendLine(('  - decision: {0}' -f (Format-MetraContextText -Text $d.decision -MaxChars 300)))
            [void]$md.AppendLine(('  - why: {0}' -f (Format-MetraContextText -Text $d.why -MaxChars 300)))
        }
    }
    $mdText = $md.ToString()

    $body = if ($Format -eq 'json') { $jsonText } else { $mdText }

    $writtenPath = if ($stdoutOnly) { '-' } else { $null }

    if ($stdoutOnly) {
        if (-not $Quiet) {
            Write-Output $body
        }
    }
    else {
        $expanded = [System.Environment]::ExpandEnvironmentVariables($outPath)
        if (-not [System.IO.Path]::IsPathRooted($expanded)) {
            $expanded = Join-Path (Get-Location).Path $expanded
        }
        $destFull = [System.IO.Path]::GetFullPath($expanded)
        $destDir = Split-Path -Parent $destFull
        if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Set-Content -LiteralPath $destFull -Value $body -Encoding utf8
        $writtenPath = $destFull
        if (-not $Quiet) {
            Write-Host ("Context pack written: {0} ({1} project(s))" -f $destFull, $projects.Count) -ForegroundColor Cyan
        }
    }

    # Refresh default companion formats under docs/ only when writing the default path.
    if (-not $stdoutOnly -and $writingDefault) {
        Set-Content -LiteralPath $defaultMd -Value $mdText -Encoding utf8
        Set-Content -LiteralPath $defaultJson -Value $jsonText -Encoding utf8
    }

    return [PSCustomObject]@{
        Path         = $writtenPath
        Format       = $Format
        ProjectCount = $projects.Count
        Query        = $Query
    }
}
