#Fix-AgentsStubShape.ps1 - one-time helper for Phase 6b stub hygiene (ceilings content + section order).
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string[]]$ProjectRoot = @('C:\Projects'),
    [switch]$WhatIfOnly
)

$oldCeilings = @'
## Ceilings

- Do not scan sibling repos first - `_meta/projects.json` already routed you here.
- Prefer project CLI/docs over dumping large generated files.
'@

$newCeilings = @'
## Ceilings

- Do not perform destructive or external writes without explicit operator confirmation.
- Do not invent missing system access or claim CLI success without running commands.
'@

function Update-AgentsCeilingsText {
    param([string]$Text)

    $pattern = '(?ms)^## Ceilings\s*\r?\n\s*\r?\n- Do not scan sibling repos first[^\r\n]*\r?\n- Prefer project CLI/docs over dumping large generated files\.[^\r\n]*\r?\n'
    if ($Text -match $pattern) {
        return [regex]::Replace($Text, $pattern, ($newCeilings + "`n"), 1)
    }

    return $Text
}

function Ensure-TokenRulesComplete {
    param([string[]]$Lines)

    $token = Get-AgentsSection -Lines $Lines -HeadingPatterns @('^## Token rules\b')
    if (-not $token) { return $Lines }

    $body = $token.Lines[1..($token.Lines.Count - 1)]
    $hasPrefer = $body | Where-Object { $_ -match 'Prefer ' }
    if ($hasPrefer) { return $Lines }

    $insertAt = $token.End
    $newLines = @()
    $newLines += $Lines[0..$insertAt]
    $newLines += '- Prefer project CLI/docs over dumping large generated files.'
    if ($insertAt -lt ($Lines.Count - 1)) {
        $newLines += $Lines[($insertAt + 1)..($Lines.Count - 1)]
    }

    return $newLines
}

function Get-AgentsSection {
    param(
        [string[]]$Lines,
        [string[]]$HeadingPatterns
    )

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        foreach ($pattern in $HeadingPatterns) {
            if ($line -match $pattern) {
                $start = $i
                $end = $Lines.Count - 1
                for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
                    if ($Lines[$j] -match '^## ') {
                        $end = $j - 1
                        break
                    }
                }
                return [pscustomobject]@{
                    Name     = $line.Trim()
                    Start    = $start
                    End      = $end
                    Lines    = $Lines[$start..$end]
                }
            }
        }
    }

    return $null
}

function Test-AgentsNeedsSectionReorder {
    param([string[]]$Lines)

    $related = Get-AgentsSection -Lines $Lines -HeadingPatterns @('^## Related projects\b', '^## Related\b')
    if (-not $related) { return $false }

    $anchors = @(
        (Get-AgentsSection -Lines $Lines -HeadingPatterns @('^## Ceilings\b', '^## Do not\b', '^## Portfolio rules\b')),
        (Get-AgentsSection -Lines $Lines -HeadingPatterns @('^## On-demand playbooks\b')),
        (Get-AgentsSection -Lines $Lines -HeadingPatterns @('^## Token rules\b'))
    ) | Where-Object { $_ }

    foreach ($anchor in $anchors) {
        if ($related.Start -lt $anchor.Start) {
            return $true
        }
    }

    return $false
}

function Repair-AgentsSectionOrder {
    param([string[]]$Lines)

    if (-not (Test-AgentsNeedsSectionReorder -Lines $Lines)) {
        return $Lines
    }

    $sectionNames = @(
        '^## Ceilings\b|^## Do not\b|^## Portfolio rules\b',
        '^## On-demand playbooks\b',
        '^## Token rules\b',
        '^## Related projects\b|^## Related\b'
    )

    $sections = @()
    foreach ($name in $sectionNames) {
        $section = Get-AgentsSection -Lines $Lines -HeadingPatterns @($name)
        if ($section) { $sections += $section }
    }

    if ($sections.Count -lt 2) {
        return $Lines
    }

    $firstTail = ($sections | Sort-Object Start | Select-Object -First 1).Start
    $prefix = if ($firstTail -gt 0) { $Lines[0..($firstTail - 1)] } else { @() }

    $tail = @()
    foreach ($section in $sections) {
        $tail += $section.Lines
        if ($section -ne $sections[-1]) {
            $tail += ''
        }
    }

    while ($prefix.Count -gt 0 -and [string]::IsNullOrWhiteSpace($prefix[-1])) {
        $prefix = $prefix[0..($prefix.Count - 2)]
    }

    if ($prefix.Count -gt 0 -and $tail.Count -gt 0) {
        $prefix += ''
    }

    return @($prefix + $tail)
}

$agentsFiles = Get-ChildItem -Path $ProjectRoot -Directory -ErrorAction SilentlyContinue |
    ForEach-Object {
        $path = Join-Path $_.FullName 'AGENTS.md'
        if (Test-Path $path) { $path }
    } |
    Sort-Object -Unique

$changed = @()

foreach ($file in $agentsFiles) {
    $lines = [System.IO.File]::ReadAllLines($file)
    $original = ($lines -join "`n")

    $text = Update-AgentsCeilingsText -Text $original
    if ($text -ne $original) {
        $lines = $text -split "`n"
    }

    $lines = Ensure-TokenRulesComplete -Lines $lines
    $reordered = Repair-AgentsSectionOrder -Lines $lines
    $text = ($reordered -join "`n").TrimEnd() + "`n"

    if ($text -ne ($original.TrimEnd() + "`n")) {
        $changed += $file
        if ($WhatIfOnly) {
            Write-Output "Would update: $file"
        }
        elseif ($PSCmdlet.ShouldProcess($file, 'Fix AGENTS stub shape')) {
            Set-Content -Path $file -Value $text -NoNewline -Encoding utf8
            Write-Output "Updated: $file"
        }
    }
}

Write-Output "Changed $($changed.Count) file(s)."
