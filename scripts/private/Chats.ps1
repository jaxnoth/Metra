# Generated from the original Metra.psm1 domain split. Edit this file directly.

function ConvertTo-MetraCursorProjectSlug {
    <#
    .SYNOPSIS
        Builds the Cursor per-project folder slug for a project name or full path.
    .DESCRIPTION
        Cursor names its state folder after the workspace path: C:\Projects\_metra becomes
        c-Projects-metra (leading underscores stripped). C:\Projects\_meta becomes c-Projects-meta.
        Projects outside the primary root (for example a cloud-synced
        personal folder) therefore need the path form, not the name form.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Name')][string]$Name,
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $segments = @(
            ($Path -split '[\\/:]') |
                ForEach-Object { ($_ -replace '[^\w]+', '-').Trim('-').TrimStart('_') } |
                Where-Object { $_ }
        )
        if ($segments.Count -eq 0) { return '' }
        $segments[0] = $segments[0].ToLowerInvariant()
        return ($segments -join '-')
    }

    $trimmed = $Name.Trim()
    if (Test-MetraSelfFolderName -Name $trimmed) {
        $leaf = ($trimmed.TrimStart('_')).ToLowerInvariant()
        return "c-Projects-$leaf"
    }
    $slug = ($trimmed -replace '[^\w]+', '-').Trim('-')
    return "c-Projects-$slug"
}

function Get-MetraCursorTranscriptRoots {
    <#
    .SYNOPSIS
        Maps project names to local Cursor agent-transcript folders.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [Alias('IncludeMeta')]
        [switch]$IncludeMetra
    )

    $cursorProjects = Join-Path $env:USERPROFILE '.cursor\projects'
    if (-not (Test-Path -LiteralPath $cursorProjects)) {
        return @()
    }

    $wanted = [System.Collections.Generic.List[string]]::new()
    if ($Name -and $Name.Count -gt 0) {
        foreach ($n in $Name) {
            if (-not [string]::IsNullOrWhiteSpace($n)) {
                $wanted.Add($n.Trim())
            }
        }
    }
    else {
        $projects = Get-MetraProjects
        foreach ($p in $projects) { $wanted.Add([string]$p.Name) }
    }
    if ($IncludeMetra -or -not $Name -or $Name.Count -eq 0) {
        if (-not ($wanted | Where-Object { Test-MetraSelfFolderName -Name $_ })) {
            $wanted.Add('_metra')
        }
    }

    $pathByName = @{}
    foreach ($p in @(Get-MetraProjects)) {
        $pathByName[$p.Name.ToLowerInvariant()] = $p.Path
    }

    $seen = @{}
    foreach ($projectName in $wanted) {
        $candidates = [System.Collections.Generic.List[string]]::new()
        $known = $pathByName[$projectName.ToLowerInvariant()]
        if ($known) {
            [void]$candidates.Add((ConvertTo-MetraCursorProjectSlug -Path $known))
        }
        [void]$candidates.Add((ConvertTo-MetraCursorProjectSlug -Name $projectName))

        foreach ($slug in $candidates) {
            if (-not $slug -or $seen.ContainsKey($slug)) { continue }
            $seen[$slug] = $true
            $transcriptRoot = Join-Path $cursorProjects (Join-Path $slug 'agent-transcripts')
            if (-not (Test-Path -LiteralPath $transcriptRoot)) { continue }
            [PSCustomObject]@{
                Name           = $projectName
                CursorSlug     = $slug
                TranscriptRoot = $transcriptRoot
            }
        }
    }
}

function Get-MetraChatSearchTerms {
    param(
        [string]$Query,
        [string]$Ticket
    )

    $bag = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $add = {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        $key = $Value.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        [void]$bag.Add($Value)
    }

    if (-not [string]::IsNullOrWhiteSpace($Ticket)) {
        $t = $Ticket.Trim()
        & $add $t
        if ($t -match '^\d+$') {
            & $add "ticket $t"
            & $add "#$t"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        foreach ($p in @($Query.ToLowerInvariant() -split '[^a-z0-9_+]+')) {
            if ($p -and $p.Length -ge 2) {
                & $add $p
            }
        }
    }
    return $bag.ToArray()
}

function Get-MetraChatSnippet {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Term,
        [int]$MaxChars = 160
    )

    if ([string]::IsNullOrWhiteSpace($Term)) { return $null }
    $idx = $Text.IndexOf($Term, [System.StringComparison]::OrdinalIgnoreCase)
    if ($idx -lt 0) { return $null }
    $start = [Math]::Max(0, $idx - 40)
    $len = [Math]::Min($MaxChars, $Text.Length - $start)
    $snip = $Text.Substring($start, $len) -replace '\\n', ' ' -replace '\\t', ' ' -replace '\s+', ' '
    if ($start -gt 0) { $snip = '...' + $snip }
    if (($start + $len) -lt $Text.Length) { $snip = $snip + '...' }
    return $snip.Trim()
}

function Get-MetraChatTitle {
    param([Parameter(Mandatory)][string]$Raw)

    $text = $Raw
    if ($Raw -match '<user_query>\s*(.*?)\s*</user_query>') {
        $text = $Matches[1]
    }
    else {
        $text = ($Raw -split "`n" | Select-Object -First 1)
    }
    $plain = $text -replace '\\n', ' ' -replace '\\t', ' ' -replace '\\"', '"' -replace '<[^>]+>', '' -replace '\s+', ' '
    $plain = $plain.Trim()
    if ($plain.Length -gt 120) { return $plain.Substring(0, 117) + '...' }
    if ($plain) { return $plain }
    return '(no title)'
}

function Get-MetraProjectChats {
    <#
    .SYNOPSIS
        Search local Cursor agent transcripts for ticket / keyword clues (bounded summaries).
    .DESCRIPTION
        Scans parent *.jsonl under ~/.cursor/projects/c-Projects-*/agent-transcripts
        (skips subagents/). Returns chat uuid, title, matched terms, and short snippets -
        not full transcripts. Canonical ticket memory remains TicketTracker notes/solutions.
    .EXAMPLE
        Get-MetraProjectChats -Name Solarwinds -Query 'disk alert' -Limit 10
    .EXAMPLE
        Get-MetraProjectChats -Name TicketTracker,Solarwinds -Ticket 12345 -Days 90
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [string]$Query,
        [string]$Ticket,
        [int]$Days = 90,
        [int]$Limit = 10,
        [int]$SnippetChars = 160,
        [Alias('IncludeMeta')]
        [switch]$IncludeMetra
    )

    if ($Limit -lt 1) { $Limit = 10 }
    if ($Days -lt 1) { $Days = 90 }

    $terms = @(Get-MetraChatSearchTerms -Query $Query -Ticket $Ticket | ForEach-Object { [string]$_ })
    Write-Verbose ("Chat search terms ({0}): {1}" -f $terms.Count, ($terms -join ' | '))
    $roots = @(Get-MetraCursorTranscriptRoots -Name $Name -IncludeMetra:$IncludeMetra)
    if ($roots.Count -eq 0) {
        Write-Warning 'No Cursor transcript folders found for the selected projects.'
        return @()
    }

    $cutoff = (Get-Date).AddDays(-1 * $Days)
    $candidates = foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root.TranscriptRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $chatId = $_.Name
                $jsonl = Join-Path $_.FullName "$chatId.jsonl"
                if (-not (Test-Path -LiteralPath $jsonl)) { return }
                $item = Get-Item -LiteralPath $jsonl
                if ($item.LastWriteTime -lt $cutoff) { return }
                [PSCustomObject]@{
                    Project    = $root.Name
                    ChatId     = $chatId
                    Path       = $item.FullName
                    Modified   = $item.LastWriteTime
                }
            }
    }

    $ordered = @($candidates | Sort-Object Modified -Descending)
    if ($ordered.Count -eq 0) {
        return @()
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $ordered) {
        if ($results.Count -ge $Limit) { break }

        # Bound read: first ~512KB is enough for titles + recent clue search without dumping huge files.
        $fs = [System.IO.File]::Open($c.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $max = [Math]::Min(512KB, $fs.Length)
            $buf = New-Object byte[] $max
            $read = $fs.Read($buf, 0, $max)
            $raw = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
        }
        finally {
            $fs.Dispose()
        }

        $matched = New-Object System.Collections.Generic.List[string]
        $snippets = New-Object System.Collections.Generic.List[string]
        if ($terms.Count -eq 0) {
            # No query: list recent chats for scoped projects (metadata + title only).
            [void]$matched.Add('(recent)')
        }
        else {
            foreach ($termObj in $terms) {
                $term = [string]$termObj
                if ([string]::IsNullOrWhiteSpace($term)) { continue }
                if ($raw.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    [void]$matched.Add($term)
                    if ($snippets.Count -lt 2) {
                        $snip = Get-MetraChatSnippet -Text $raw -Term $term -MaxChars $SnippetChars
                        if ($snip) { [void]$snippets.Add([string]$snip) }
                    }
                }
            }
            if ($matched.Count -eq 0) { continue }
        }

        $title = Get-MetraChatTitle -Raw $raw
        $results.Add([PSCustomObject]@{
            Project      = [string]$c.Project
            ChatId       = [string]$c.ChatId
            Title        = [string]$title
            Modified     = $c.Modified.ToString('yyyy-MM-dd HH:mm')
            MatchedTerms = [string]::Join(', ', @($matched.ToArray()))
            Snippet1     = if ($snippets.Count -gt 0) { [string]$snippets[0] } else { '' }
            Snippet2     = if ($snippets.Count -gt 1) { [string]$snippets[1] } else { '' }
            Path         = [string]$c.Path
            Cite         = ('[{0}]({1})' -f $title, $c.ChatId)
        })
    }

    return [object[]]$results.ToArray()
}

