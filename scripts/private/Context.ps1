# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Export-MetraContextPack {
    <#
    .SYNOPSIS
        Build a bounded agent-facing context pack (roots + present routing).
    .DESCRIPTION
        Token-safe map for humans and agents. Does not dump canvas-snapshot inventory.
        Prefer relative or env-style personal roots when echoing paths.
    #>
    [CmdletBinding()]
    param(
        [string]$Query,
        [string]$Path,
        [ValidateSet('markdown', 'json')]
        [string]$Format = 'markdown',
        [int]$Limit = 25,
        [switch]$Quiet
    )

    $metraRoot = Get-MetraRoot
    if ($Limit -lt 1) { $Limit = 25 }

    $roots = @(Get-MetraRoots -IncludeMissing | ForEach-Object {
        $displayPath = [string]$_.RawPath
        if ([string]::IsNullOrWhiteSpace($displayPath)) { $displayPath = $_.Path }
        # Avoid leaking expanded username paths into packs when RawPath used env vars.
        if ($displayPath -match '(?i)[\\/]Users[\\/][^\\/]+[\\/]') {
            $displayPath = $_.RawPath
            if ([string]::IsNullOrWhiteSpace($displayPath)) {
                $displayPath = '%USERPROFILE%\...'
            }
        }
        [PSCustomObject]@{
            name     = $_.Name
            primary  = [bool]$_.Primary
            exists   = [bool]$_.Exists
            optional = [bool]$_.Optional
            path     = $displayPath
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
            ($Query.ToLowerInvariant() -split '\W+') |
                Where-Object { $_ -and $_.Length -gt 1 }
        )
    }

    $scored = New-Object System.Collections.Generic.List[object]
    foreach ($reg in @($registry.projects)) {
        $regName = [string]$reg.name
        $onDisk = $disk[$regName.ToLowerInvariant()]
        if (-not $onDisk) { continue }

        $purpose = [string](Get-MetraProp -Object $reg -Name 'purpose' -Default '')
        $triggers = @(Get-MetraProp -Object $reg -Name 'triggers' -Default @())
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

        [void]$scored.Add([PSCustomObject]@{
            name         = $regName
            root         = [string]$onDisk.Root
            purpose      = $purpose
            triggers     = @($triggers)
            capabilities = @(Get-MetraProp -Object $reg -Name 'capabilities' -Default @())
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
                entry        = 'AGENTS.md'
                score        = 0
            })
        }
    }

    $projects = @(
        $scored |
            Sort-Object @{ Expression = 'score'; Descending = $true }, name |
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
        version     = 1
        product     = 'Metra'
        generatedUtc = [DateTime]::UtcNow.ToString('o')
        query       = if ($Query) { $Query } else { $null }
        reminders   = @(
            'Route to one primary project; load that project AGENTS.md before broad search.',
            'Ticket/helpdesk: TicketTracker first when present, then one technical project.',
            'Keep work and personal roots isolated unless the user names a cross-root handoff.',
            'CLI: .\metra.ps1 routing | audit | chats | ctx'
        )
        roots       = @($roots)
        projects    = @($projects | ForEach-Object {
            [ordered]@{
                name         = $_.name
                root         = $_.root
                purpose      = $_.purpose
                triggers     = @($_.triggers)
                capabilities = @($_.capabilities)
                entry        = $_.entry
            }
        })
        missingOptional = @($missingOptional)
    }

    if ($tokens.Count -gt 0) {
        $related = @(Search-MetraDecisionRegistry -Query $Query -Limit 3 -MetraRoot $metraRoot)
        $pack['relatedDecisions'] = @(
            $related | ForEach-Object {
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

    $defaultMd = Join-Path $metraRoot 'docs\context-pack.md'
    $defaultJson = Join-Path $metraRoot 'docs\context-pack.json'
    $outPath = $Path
    $stdoutOnly = $false
    if ([string]::IsNullOrWhiteSpace($outPath)) {
        $outPath = if ($Format -eq 'json') { $defaultJson } else { $defaultMd }
    }
    elseif ($outPath.Trim() -eq '-') {
        $stdoutOnly = $true
    }

    $jsonText = ($pack | ConvertTo-Json -Depth 8)
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine('# Metra context pack')
    [void]$md.AppendLine('')
    [void]$md.AppendLine(("Generated: {0}" -f $pack.generatedUtc))
    if ($Query) {
        [void]$md.AppendLine(("Query: {0}" -f $Query))
    }
    [void]$md.AppendLine('')
    [void]$md.AppendLine('## Reminders')
    [void]$md.AppendLine('')
    foreach ($r in $pack.reminders) {
        [void]$md.AppendLine(("- {0}" -f $r))
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
        $purp = if ($proj.purpose) { $proj.purpose } else { '(no registry purpose)' }
        [void]$md.AppendLine(('- **{0}** [{1}] - {2}' -f $proj.name, $proj.root, $purp))
        [void]$md.AppendLine(('  - triggers: {0}' -f $trig))
        [void]$md.AppendLine(('  - entry: {0}' -f $proj.entry))
    }
    if ($missingOptional.Count -gt 0) {
        [void]$md.AppendLine('')
        [void]$md.AppendLine('## Missing optional stubs')
        [void]$md.AppendLine('')
        foreach ($m in $missingOptional) {
            [void]$md.AppendLine(('- **{0}**: {1}' -f $m.name, $m.advice))
        }
    }
    if ($pack.Contains('relatedDecisions') -and @($pack.relatedDecisions).Count -gt 0) {
        [void]$md.AppendLine('')
        [void]$md.AppendLine('## Related decisions (up to 3)')
        [void]$md.AppendLine('')
        foreach ($d in @($pack.relatedDecisions)) {
            [void]$md.AppendLine(('- **{0}** [{1}] conf={2}' -f $d.title, $d.project, $d.confidence))
            [void]$md.AppendLine(('  - decision: {0}' -f $d.decision))
            [void]$md.AppendLine(('  - why: {0}' -f $d.why))
        }
    }
    $mdText = $md.ToString()

    $body = if ($Format -eq 'json') { $jsonText } else { $mdText }

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
        Set-Content -Path $destFull -Value $body -Encoding utf8
        if (-not $Quiet) {
            Write-Host ("Context pack written: {0} ({1} project(s))" -f $destFull, $projects.Count) -ForegroundColor Cyan
        }
    }

    # Always refresh default companion formats under docs/ when writing the default path
    if (-not $stdoutOnly -and ($outPath -eq $defaultMd -or $outPath -eq $defaultJson -or [string]::IsNullOrWhiteSpace($Path))) {
        Set-Content -Path $defaultMd -Value $mdText -Encoding utf8
        Set-Content -Path $defaultJson -Value $jsonText -Encoding utf8
    }

    return [PSCustomObject]@{
        Path         = if ($stdoutOnly) { '-' } else { $outPath }
        Format       = $Format
        ProjectCount = $projects.Count
        Query        = $Query
    }
}

