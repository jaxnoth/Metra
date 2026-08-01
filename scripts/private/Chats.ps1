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
        & $add $Query.Trim()
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

function Get-MetraCursorApiKey {
    <#
    .SYNOPSIS
        Resolves a Cursor API key for Cloud Agents reads.
    .DESCRIPTION
        Prefers process $env:CURSOR_API_KEY, then User scope, then Machine scope.
        Cursor agent shells often miss User vars set after the IDE started - User lookup
        covers that. Never prompts and never writes secrets to disk. Returns $null when
        unset so callers can skip cloud search quietly.
    #>
    [CmdletBinding()]
    param()

    foreach ($candidate in @(
            [string]$env:CURSOR_API_KEY
            [Environment]::GetEnvironmentVariable('CURSOR_API_KEY', 'User')
            [Environment]::GetEnvironmentVariable('CURSOR_API_KEY', 'Machine')
        )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $trimmed = $candidate.Trim()
            # Keep process env warm for later calls in this session
            $env:CURSOR_API_KEY = $trimmed
            return $trimmed
        }
    }
    return $null
}

function Resolve-MetraChatProjectFromRepo {
    <#
    .SYNOPSIS
        Maps a Cloud Agent repository URL to a Metra project name when possible.
    #>
    [CmdletBinding()]
    param(
        [string]$RepoUrl,
        [string[]]$WantedNames
    )

    if ([string]::IsNullOrWhiteSpace($RepoUrl)) { return $null }
    $normalized = $RepoUrl.Trim() -replace '\\', '/' -replace '\.git$', ''
    $leaf = ($normalized -split '/')[-1]
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $null }

    if ($leaf -match '^(?i)Metra$') {
        if (-not $WantedNames -or $WantedNames.Count -eq 0) { return 'Metra' }
        foreach ($wanted in $WantedNames) {
            if ((Test-MetraSelfFolderName -Name $wanted) -or ($wanted -match '^(?i)Metra$')) {
                return $(if (Test-MetraSelfFolderName -Name $wanted) { $wanted } else { 'Metra' })
            }
        }
        return $null
    }

    if (-not $WantedNames -or $WantedNames.Count -eq 0) {
        return $leaf
    }
    foreach ($wanted in $WantedNames) {
        if ([string]::Equals($wanted, $leaf, [StringComparison]::OrdinalIgnoreCase)) {
            return $wanted
        }
    }
    return $null
}

function Invoke-MetraCursorApi {
    <#
    .SYNOPSIS
        GET helper for api.cursor.com with Bearer auth.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)][string]$Path
    )

    $uri = if ($Path.StartsWith('http', [StringComparison]::OrdinalIgnoreCase)) {
        $Path
    }
    else {
        'https://api.cursor.com' + $Path
    }
    $headers = @{
        Authorization = "Bearer $ApiKey"
        Accept        = 'application/json'
    }
    return Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
}

function Get-MetraCloudAgentChats {
    <#
    .SYNOPSIS
        Search Cursor Cloud Agent runs via the Cloud Agents API (bounded summaries).
    .DESCRIPTION
        Lists recent cloud agents, scopes by repository when -Name is set, and searches
        agent names plus latest run result text. Requires $env:CURSOR_API_KEY.
        Returns snippets and agent URLs - not full transcripts.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [string]$Query,
        [string]$Ticket,
        [int]$Days = 90,
        [int]$Limit = 10,
        [int]$SnippetChars = 160,
        [int]$MaxFetch = 20,
        [Alias('IncludeMeta')]
        [switch]$IncludeMetra,
        [string]$ApiKey
    )

    if ($Limit -lt 1) { $Limit = 10 }
    if ($Days -lt 1) { $Days = 90 }
    if ($MaxFetch -lt 1) { $MaxFetch = 20 }

    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        $ApiKey = Get-MetraCursorApiKey
    }
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        Write-Warning 'Cloud chat search skipped: no CURSOR_API_KEY. Ask the operator for a session key (Cursor Dashboard -> API Keys), then set $env:CURSOR_API_KEY for this session.'
        return @()
    }

    $wanted = [System.Collections.Generic.List[string]]::new()
    if ($Name -and $Name.Count -gt 0) {
        foreach ($n in $Name) {
            if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$wanted.Add($n.Trim()) }
        }
    }
    if ($IncludeMetra) {
        $hasSelf = $false
        foreach ($n in $wanted) {
            if ((Test-MetraSelfFolderName -Name $n) -or ($n -match '^(?i)Metra$')) { $hasSelf = $true; break }
        }
        if (-not $hasSelf) { [void]$wanted.Add('Metra') }
    }

    $terms = @(Get-MetraChatSearchTerms -Query $Query -Ticket $Ticket | ForEach-Object { [string]$_ })
    $cutoffUtc = [DateTime]::UtcNow.AddDays(-1 * $Days)
    $listLimit = [Math]::Max($Limit * 3, 30)
    if ($listLimit -gt 100) { $listLimit = 100 }

    try {
        $list = Invoke-MetraCursorApi -ApiKey $ApiKey -Path ("/v1/agents?limit={0}" -f $listLimit)
    }
    catch {
        Write-Warning ("Cloud Agents API list failed: {0}" -f $_.Exception.Message)
        return @()
    }

    $agents = @($list.items)
    if ($agents.Count -eq 0 -and $list.agents) { $agents = @($list.agents) }

    $scoped = [System.Collections.Generic.List[object]]::new()
    foreach ($agent in $agents) {
        $updatedRaw = [string]$agent.updatedAt
        if (-not $updatedRaw) { $updatedRaw = [string]$agent.createdAt }
        $updatedUtc = $null
        if ($updatedRaw) {
            try { $updatedUtc = [DateTime]::Parse($updatedRaw, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() } catch { $updatedUtc = $null }
        }
        if ($updatedUtc -and $updatedUtc -lt $cutoffUtc) { continue }

        $repoUrl = $null
        if ($agent.repos -and @($agent.repos).Count -gt 0) {
            $repoUrl = [string]@($agent.repos)[0].url
        }
        elseif ($agent.source -and $agent.source.repository) {
            $repoUrl = [string]$agent.source.repository
        }

        $project = Resolve-MetraChatProjectFromRepo -RepoUrl $repoUrl -WantedNames @($wanted.ToArray())
        if ($wanted.Count -gt 0 -and -not $project) { continue }
        if (-not $project) {
            if ($repoUrl) {
                $project = ($repoUrl.Trim() -replace '\\', '/' -replace '\.git$', '' -split '/')[-1]
            }
            else {
                $project = '(cloud)'
            }
        }

        [void]$scoped.Add([PSCustomObject]@{
            Agent      = $agent
            Project    = $project
            RepoUrl    = $repoUrl
            UpdatedUtc = $updatedUtc
        })
    }

    $ordered = @($scoped | Sort-Object @{ Expression = { if ($_.UpdatedUtc) { $_.UpdatedUtc } else { [DateTime]::MinValue } }; Descending = $true })
    $results = [System.Collections.Generic.List[object]]::new()
    $fetched = 0
    foreach ($row in $ordered) {
        if ($results.Count -ge $Limit) { break }

        $agent = $row.Agent
        $agentId = [string]$agent.id
        $title = [string]$agent.name
        if (-not $title) { $title = $agentId }
        $url = [string]$agent.url
        if (-not $url -and $agentId) { $url = "https://cursor.com/agents/$agentId" }

        $hay = @(
            $title
            $agentId
            [string]$row.RepoUrl
            [string]$row.Project
        ) -join "`n"

        $resultText = ''
        $shouldFetch = ($terms.Count -gt 0) -or ($fetched -lt [Math]::Min($MaxFetch, $Limit))
        $runId = [string]$agent.latestRunId
        if ($shouldFetch -and $runId -and $fetched -lt $MaxFetch) {
            $fetched++
            try {
                $run = Invoke-MetraCursorApi -ApiKey $ApiKey -Path ("/v1/agents/{0}/runs/{1}" -f $agentId, $runId)
                $resultText = [string]$run.result
                if ($resultText) { $hay = $hay + "`n" + $resultText }
            }
            catch {
                Write-Verbose ("Cloud run fetch failed for {0}: {1}" -f $agentId, $_.Exception.Message)
            }
        }

        $matched = New-Object System.Collections.Generic.List[string]
        $snippets = New-Object System.Collections.Generic.List[string]
        if ($terms.Count -eq 0) {
            [void]$matched.Add('(recent)')
            if ($resultText) {
                $plain = ($resultText -replace '\s+', ' ').Trim()
                if ($plain.Length -gt $SnippetChars) { $plain = $plain.Substring(0, $SnippetChars - 3) + '...' }
                if ($plain) { [void]$snippets.Add($plain) }
            }
        }
        else {
            foreach ($termObj in $terms) {
                $term = [string]$termObj
                if ([string]::IsNullOrWhiteSpace($term)) { continue }
                if ($hay.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    [void]$matched.Add($term)
                    if ($snippets.Count -lt 2) {
                        $snip = Get-MetraChatSnippet -Text $hay -Term $term -MaxChars $SnippetChars
                        if ($snip) { [void]$snippets.Add([string]$snip) }
                    }
                }
            }
            if ($matched.Count -eq 0) { continue }
        }

        $modified = if ($row.UpdatedUtc) {
            $row.UpdatedUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
        }
        else {
            ''
        }

        $results.Add([PSCustomObject]@{
            Project      = [string]$row.Project
            Source       = 'cloud'
            ChatId       = $agentId
            Title        = $title
            Modified     = $modified
            MatchedTerms = [string]::Join(', ', @($matched.ToArray()))
            Snippet1     = if ($snippets.Count -gt 0) { [string]$snippets[0] } else { '' }
            Snippet2     = if ($snippets.Count -gt 1) { [string]$snippets[1] } else { '' }
            Path         = $url
            Url          = $url
            Cite         = ('[{0}]({1})' -f $title, $(if ($url) { $url } else { $agentId }))
        })
    }

    return [object[]]$results.ToArray()
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
        [switch]$IncludeMetra,
        [switch]$Cloud
    )

    if ($Limit -lt 1) { $Limit = 10 }
    if ($Days -lt 1) { $Days = 90 }

    $terms = @(Get-MetraChatSearchTerms -Query $Query -Ticket $Ticket | ForEach-Object { [string]$_ })
    Write-Verbose ("Chat search terms ({0}): {1}" -f $terms.Count, ($terms -join ' | '))

    $combined = [System.Collections.Generic.List[object]]::new()

    $roots = @(Get-MetraCursorTranscriptRoots -Name $Name -IncludeMetra:$IncludeMetra)
    if ($roots.Count -eq 0) {
        if (-not $Cloud) {
            Write-Warning 'No Cursor transcript folders found for the selected projects.'
            return @()
        }
    }
    else {
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
                        Project  = $root.Name
                        ChatId   = $chatId
                        Path     = $item.FullName
                        Modified = $item.LastWriteTime
                    }
                }
        }

        $ordered = @($candidates | Sort-Object Modified -Descending)
        foreach ($c in $ordered) {
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
            $combined.Add([PSCustomObject]@{
                Project      = [string]$c.Project
                Source       = 'local'
                ChatId       = [string]$c.ChatId
                Title        = [string]$title
                Modified     = $c.Modified.ToString('yyyy-MM-dd HH:mm')
                MatchedTerms = [string]::Join(', ', @($matched.ToArray()))
                Snippet1     = if ($snippets.Count -gt 0) { [string]$snippets[0] } else { '' }
                Snippet2     = if ($snippets.Count -gt 1) { [string]$snippets[1] } else { '' }
                Path         = [string]$c.Path
                Url          = ''
                Cite         = ('[{0}]({1})' -f $title, $c.ChatId)
                _Sort        = $c.Modified
            })
        }
    }

    if ($Cloud) {
        $cloudRows = @(Get-MetraCloudAgentChats -Name $Name -Query $Query -Ticket $Ticket -Days $Days -Limit $Limit -SnippetChars $SnippetChars -IncludeMetra:$IncludeMetra)
        foreach ($row in $cloudRows) {
            $sort = [DateTime]::MinValue
            if ($row.Modified) {
                try { $sort = [DateTime]::ParseExact([string]$row.Modified, 'yyyy-MM-dd HH:mm', $null) } catch { $sort = [DateTime]::MinValue }
            }
            $combined.Add([PSCustomObject]@{
                Project      = $row.Project
                Source       = $row.Source
                ChatId       = $row.ChatId
                Title        = $row.Title
                Modified     = $row.Modified
                MatchedTerms = $row.MatchedTerms
                Snippet1     = $row.Snippet1
                Snippet2     = $row.Snippet2
                Path         = $row.Path
                Url          = $row.Url
                Cite         = $row.Cite
                _Sort        = $sort
            })
        }
    }

    $final = @(
        $combined |
            Sort-Object @{ Expression = '_Sort'; Descending = $true }, Source, Title |
            Select-Object -First $Limit |
            ForEach-Object {
                [PSCustomObject]@{
                    Project      = $_.Project
                    Source       = $_.Source
                    ChatId       = $_.ChatId
                    Title        = $_.Title
                    Modified     = $_.Modified
                    MatchedTerms = $_.MatchedTerms
                    Snippet1     = $_.Snippet1
                    Snippet2     = $_.Snippet2
                    Path         = $_.Path
                    Url          = $_.Url
                    Cite         = $_.Cite
                }
            }
    )
    return [object[]]$final
}

