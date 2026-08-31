# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Read-MetraRegistryFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($p in @(Get-MetraProp -Object $doc -Name 'projects' -Default @())) {
        $p | Add-Member -NotePropertyName 'source' -NotePropertyValue $Source -Force
    }
    return $doc
}

function Get-MetraRegistryFileStampPart {
    <#
    .SYNOPSIS
        Stable path|ticks fragment for registry cache invalidation.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ('{0}|0' -f $Path)
    }
    $ticks = (Get-Item -LiteralPath $Path).LastWriteTimeUtc.Ticks
    return ('{0}|{1}' -f $Path, $ticks)
}

function Get-MetraRegistrySourceStamp {
    <#
    .SYNOPSIS
        Fingerprint of registry files that feed Get-MetraProjectRegistry.
    .DESCRIPTION
        Shared projects.json, each configured root registryFile, and projects.local.json
        (unless -SharedOnly). Any LastWriteTimeUtc change invalidates the in-memory cache.
    #>
    [CmdletBinding()]
    param(
        [switch]$SharedOnly
    )

    $metraRoot = Get-MetraRoot
    $parts = New-Object System.Collections.Generic.List[string]
    [void]$parts.Add((Get-MetraRegistryFileStampPart -Path (Join-Path $metraRoot 'projects.json')))

    if (-not $SharedOnly) {
        foreach ($projectRoot in @(Get-MetraRoots)) {
            if (-not $projectRoot.RegistryFile) { continue }
            $rootRegistryPath = [System.Environment]::ExpandEnvironmentVariables([string]$projectRoot.RegistryFile)
            if (-not [System.IO.Path]::IsPathRooted($rootRegistryPath)) {
                $rootRegistryPath = Join-Path $projectRoot.Path $rootRegistryPath
            }
            [void]$parts.Add((Get-MetraRegistryFileStampPart -Path $rootRegistryPath))
        }
        [void]$parts.Add((Get-MetraRegistryFileStampPart -Path (Join-Path $metraRoot 'projects.local.json')))
    }

    return ($parts -join ';')
}

function Get-MetraProjectRegistry {
    <#
    .SYNOPSIS
        Loads the agent routing registry: shared projects.json plus optional overlays.
    .DESCRIPTION
        Merge precedence (later replaces earlier by project name):
        1. shared registry (projects.json)
        2. each configured root registryFile (in Get-MetraRoots order)
        3. projects.local.json (machine-private; not committed)

        projects.json is the git-tracked, shareable subset. Root registries travel with a
        root folder (for example a cloud-synced personal root). Local entries with the same
        name replace earlier layers, so a coworker clone never sees them. Use -SharedOnly to
        inspect exactly what ships to others.

        Results are cached until any contributing registry file LastWriteTimeUtc changes
        (or Clear-MetraRoutingCache / TTL expiry).
    #>
    [CmdletBinding()]
    param(
        [switch]$SharedOnly
    )

    $cacheKey = if ($SharedOnly) { 'shared' } else { 'merged' }
    $sourceStamp = Get-MetraRegistrySourceStamp -SharedOnly:$SharedOnly
    $cached = $script:MetraCache.RegistryByKey[$cacheKey]
    if (
        $null -ne $cached -and
        [string]$cached.Stamp -eq $sourceStamp -and
        (Test-MetraCacheEntryFresh -CachedUtc $cached.Utc)
    ) {
        return $cached.Value
    }

    $metraRoot = Get-MetraRoot
    $sharedPath = Join-Path $metraRoot 'projects.json'
    $localPath = Join-Path $metraRoot 'projects.local.json'

    $shared = Read-MetraRegistryFile -Path $sharedPath -Source 'shared'
    if (-not $shared) {
        throw "Missing project registry: $sharedPath"
    }

    $projects = [System.Collections.Generic.List[object]]::new()
    $index = @{}
    foreach ($p in @(Get-MetraProp -Object $shared -Name 'projects' -Default @())) {
        $key = ([string]$p.name).ToLowerInvariant()
        $index[$key] = $projects.Count
        [void]$projects.Add($p)
    }

    $routing = Get-MetraProp -Object $shared -Name 'routing'
    $localLoaded = $false
    $extraSources = @()

    if (-not $SharedOnly) {
        # A root may carry its own registry file so entries travel with the folder itself
        # (for example a cloud-synced personal root that reaches a second machine).
        foreach ($projectRoot in @(Get-MetraRoots)) {
            if (-not $projectRoot.RegistryFile) { continue }
            $rootRegistryPath = [System.Environment]::ExpandEnvironmentVariables($projectRoot.RegistryFile)
            if (-not [System.IO.Path]::IsPathRooted($rootRegistryPath)) {
                $rootRegistryPath = Join-Path $projectRoot.Path $rootRegistryPath
            }
            $rootRegistry = Read-MetraRegistryFile -Path $rootRegistryPath -Source $projectRoot.Name
            if (-not $rootRegistry) { continue }
            $extraSources += $rootRegistryPath
            foreach ($p in @(Get-MetraProp -Object $rootRegistry -Name 'projects' -Default @())) {
                $key = ([string]$p.name).ToLowerInvariant()
                if (-not (Get-MetraProp -Object $p -Name 'root')) {
                    $p | Add-Member -NotePropertyName 'root' -NotePropertyValue $projectRoot.Name -Force
                }
                if ($index.ContainsKey($key)) {
                    $projects[$index[$key]] = $p
                }
                else {
                    $index[$key] = $projects.Count
                    [void]$projects.Add($p)
                }
            }
        }

        $local = Read-MetraRegistryFile -Path $localPath -Source 'local'
        if ($local) {
            $localLoaded = $true
            foreach ($p in @(Get-MetraProp -Object $local -Name 'projects' -Default @())) {
                $key = ([string]$p.name).ToLowerInvariant()
                if ($index.ContainsKey($key)) {
                    $projects[$index[$key]] = $p
                }
                else {
                    $index[$key] = $projects.Count
                    [void]$projects.Add($p)
                }
            }
            $localRouting = Get-MetraProp -Object $local -Name 'routing'
            if ($localRouting -and $routing) {
                foreach ($prop in $localRouting.PSObject.Properties) {
                    $routing | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
            }
            elseif ($localRouting) {
                $routing = $localRouting
            }
        }
    }

    $result = [PSCustomObject]@{
        version      = Get-MetraProp -Object $shared -Name 'version' -Default 1
        updated      = Get-MetraProp -Object $shared -Name 'updated' -Default ''
        routing      = $routing
        projects     = @($projects.ToArray())
        sharedPath   = $sharedPath
        localPath    = $localPath
        localLoaded  = $localLoaded
        rootRegistry = @($extraSources)
    }
    # Re-stamp after load so the fingerprint matches the files just read.
    $sourceStamp = Get-MetraRegistrySourceStamp -SharedOnly:$SharedOnly
    $script:MetraCache.RegistryByKey[$cacheKey] = @{
        Value = $result
        Stamp = $sourceStamp
        Utc   = [datetime]::UtcNow
    }
    return $result
}

function Get-MetraRoutingTable {
    <#
    .SYNOPSIS
        Resolves registry entries against what is actually on disk, with stub advice.
    .DESCRIPTION
        Every registry entry may declare "optional": true plus "whenPresent" / "whenMissing"
        advice. Present projects expose their real entry file and commands; absent optional
        projects return advice instead of counting as drift. That lets one shared registry
        describe capabilities a coworker may or may not have installed.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [switch]$SharedOnly,

        [switch]$MissingOnly
    )

    $registry = Get-MetraProjectRegistry -SharedOnly:$SharedOnly
    $disk = @{}
    foreach ($p in @(Get-MetraProjects)) {
        $disk[$p.Name.ToLowerInvariant()] = $p
    }

    $rows = foreach ($reg in @($registry.projects)) {
        $regName = [string]$reg.name
        if ($Name -and $Name.Count -gt 0) {
            $wanted = @($Name | ForEach-Object { $_.ToLowerInvariant() })
            if ($wanted -notcontains $regName.ToLowerInvariant()) { continue }
        }

        $onDisk = $disk[$regName.ToLowerInvariant()]
        $present = $null -ne $onDisk
        if ($MissingOnly -and $present) { continue }

        $optional = [bool](Get-MetraProp -Object $reg -Name 'optional' -Default $false)
        $advice = if ($present) {
            [string](Get-MetraProp -Object $reg -Name 'whenPresent' -Default '')
        }
        else {
            [string](Get-MetraProp -Object $reg -Name 'whenMissing' -Default '')
        }
        if (-not $advice -and -not $present) {
            $advice = "Not on this machine. Ask the user for the details this project would have provided; do not invent them."
        }

        [PSCustomObject]@{
            Name         = $regName
            Source       = [string](Get-MetraProp -Object $reg -Name 'source' -Default 'shared')
            Root         = if ($present) { [string]$onDisk.Root } else { '' }
            Present      = $present
            Optional     = $optional
            Entry        = [string](Get-MetraProp -Object $reg -Name 'entry' -Default 'AGENTS.md')
            Capabilities = @(Get-MetraProp -Object $reg -Name 'capabilities' -Default @())
            Triggers     = @(Get-MetraProp -Object $reg -Name 'triggers' -Default @())
            Serves       = @(Get-MetraProp -Object $reg -Name 'serves' -Default @())
            Advice       = $advice
            Path         = if ($present) { [string]$onDisk.Path } else { '' }
        }
    }

    return @($rows | Sort-Object @{ Expression = 'Present'; Descending = $true }, Name)
}

function Get-MetraRegistryProject {
    param(
        [Parameter(Mandatory)]$Registry,
        [Parameter(Mandatory)][string]$Name
    )

    @($Registry.projects) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Get-MetraHomeDestinationName {
    <#
    .SYNOPSIS
        Registry home destination name (defaults to Metra).
    #>
    [CmdletBinding()]
    param()

    $registry = Get-MetraProjectRegistry
    $routing = Get-MetraProp -Object $registry -Name 'routing' -Default $null
    $name = [string](Get-MetraProp -Object $routing -Name 'homeDestination' -Default '')
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = [string](Get-MetraProp -Object $routing -Name 'defaultEntry' -Default 'Metra')
    }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Metra' }
    return $name
}

function New-MetraHomeScoredProject {
    <#
    .SYNOPSIS
        Builds a scored routing row for the Metra home destination.
    #>
    [CmdletBinding()]
    param(
        [int]$Score = 0
    )

    $homeName = Get-MetraHomeDestinationName
    $onDisk = Get-MetraOrchestrationProject
    $registry = Get-MetraProjectRegistry
    $reg = @($registry.projects | Where-Object { [string]$_.name -eq $homeName } | Select-Object -First 1)
    $purpose = if ($reg) { [string](Get-MetraProp -Object $reg -Name 'purpose' -Default '') } else { 'Portfolio orchestration home.' }
    $triggers = if ($reg) { @(Get-MetraProp -Object $reg -Name 'triggers' -Default @()) } else { @('metra') }
    $serves = if ($reg) { @(Get-MetraProp -Object $reg -Name 'serves' -Default @()) } else { @() }

    return [PSCustomObject]@{
        Name          = $homeName
        Root          = [string]$onDisk.Root
        Path          = [string]$onDisk.Path
        Purpose       = $purpose
        Triggers      = @($triggers)
        Serves        = @($serves)
        Score         = $Score
        MatchedTokens = @()
        HayLower      = (@($homeName) + $triggers + @($purpose) | ForEach-Object { [string]$_ }) -join ' '
        IsHomeDefault = $true
    }
}

function Get-MetraRoutingStopWords {
    <#
    .SYNOPSIS
        Common English tokens that must not score registry haystacks via substring noise.
    #>
    return [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@(
            'a', 'an', 'and', 'as', 'at', 'be', 'by', 'do', 'for', 'from', 'get', 'got',
            'how', 'if', 'in', 'into', 'is', 'it', 'its', 'me', 'my', 'no', 'not', 'of', 'on',
            'or', 'our', 'out', 'so', 'than', 'that', 'the', 'then', 'there', 'these', 'this',
            'those', 'to', 'up', 'us', 'via', 'we', 'what', 'when', 'where', 'who', 'why',
            'with', 'you', 'your', 'today', 'now', 'here', 'please', 'help', 'try', 'find',
            'need', 'needs', 'want', 'like', 'also', 'any', 'all', 'just', 'about', 'into'
        ),
        [StringComparer]::OrdinalIgnoreCase
    )
}

function Get-MetraQueryTokens {
    param([string]$Query)
    if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
    $stop = Get-MetraRoutingStopWords
    # Normalize hyphens/underscores so Power-BI / Power_BI tokenize like "power bi".
    $normalized = $Query.ToLowerInvariant() -replace '[-_]+', ' '
    return @(
        ($normalized -split '\W+') |
            Where-Object { $_ -and $_.Length -gt 1 -and -not $stop.Contains($_) }
    )
}

function Test-MetraTicketShapedQuery {
    <#
    .SYNOPSIS
        True when the query contains a 6-8 digit token (iSupport-style ticket id).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query
    )

    return [bool]([regex]::IsMatch($Query, '(?<!\d)\d{6,8}(?!\d)'))
}

function Test-MetraTicketHelpdeskVocabulary {
    <#
    .SYNOPSIS
        True when query tokens include durable ticket/helpdesk workflow vocabulary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query
    )

    $tokens = @(Get-MetraQueryTokens -Query $Query)
    $ticketTokens = @('ticket', 'tickets', 'isupport', 'helpdesk', 'incident', 'incidents')
    return @($tokens | Where-Object { $ticketTokens -contains $_ }).Count -gt 0
}

function Get-MetraTicketTrackerProject {
    <#
    .SYNOPSIS
        Resolves TicketTracker on disk for routing and TicketWatch (Path, Root, ModulePath).
    .DESCRIPTION
        Canonical helper - do not redefine in TicketWatch.ps1 (later private files overwrite).
        TicketWatch callers should use Resolve-MetraTicketTrackerModule + Import-MetraTicketTrackerModule.
        Requires src\TicketTracker.psm1 so TicketWatch can Import-Module; Root supports scoring.
    #>
    [CmdletBinding()]
    param()

    $onDisk = Get-MetraProjects | Where-Object { $_.Name -eq 'TicketTracker' } | Select-Object -First 1
    if (-not $onDisk) { return $null }

    $path = [string](Get-MetraProp -Object $onDisk -Name 'Path' -Default '')
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { return $null }

    $module = Join-Path $path 'src\TicketTracker.psm1'
    if (-not (Test-Path -LiteralPath $module)) { return $null }

    return [PSCustomObject]@{
        Name       = 'TicketTracker'
        Path       = $path
        Root       = [string](Get-MetraProp -Object $onDisk -Name 'Root' -Default '')
        ModulePath = $module
        IsGit      = [bool](Get-MetraProp -Object $onDisk -Name 'IsGit' -Default $false)
    }
}

function Get-MetraTicketTrackerSolutionsKeywords {
    <#
    .SYNOPSIS
        Distinctive keywords from TicketTracker solutions/README.md (keywords column).
    .DESCRIPTION
        Product/app names enter routing via solutions write-ups, not projects.json triggers.
        Parses pipe-table rows; takes the last cell as keywords; splits on commas.
        Cached until the README LastWriteTime changes (or Clear-MetraRoutingCache).
    #>
    [CmdletBinding()]
    param()

    $tt = Get-MetraTicketTrackerProject
    if (-not $tt -or [string]::IsNullOrWhiteSpace($tt.Path)) { return @() }

    $readme = Join-Path $tt.Path 'solutions\README.md'
    if (-not (Test-Path -LiteralPath $readme)) { return @() }

    $lwt = (Get-Item -LiteralPath $readme).LastWriteTimeUtc
    if (
        $script:MetraCache.SolutionsPath -eq $readme -and
        $script:MetraCache.SolutionsLwt -eq $lwt -and
        $null -ne $script:MetraCache.SolutionsKeywords
    ) {
        return @($script:MetraCache.SolutionsKeywords)
    }

    $keywords = New-Object System.Collections.Generic.List[string]
    foreach ($line in @(Get-Content -LiteralPath $readme -ErrorAction SilentlyContinue)) {
        $trim = [string]$line
        if ($trim -notmatch '^\|') { continue }
        if ($trim -match '^\|\s*-+') { continue }
        if ($trim -match '(?i)\|\s*File\s*\|') { continue }
        $cells = @($trim.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 2) { continue }
        $keywordCell = [string]$cells[-1]
        if ([string]::IsNullOrWhiteSpace($keywordCell)) { continue }
        foreach ($piece in @($keywordCell -split ',')) {
            $k = $piece.Trim()
            if ($k.Length -lt 3) { continue }
            # Skip pure ticket-id tokens - those are handled by ticket-shaped preference.
            if ($k -match '^\d{6,8}$') { continue }
            [void]$keywords.Add($k)
        }
    }

    $unique = @($keywords | Select-Object -Unique)
    $script:MetraCache.SolutionsPath = $readme
    $script:MetraCache.SolutionsLwt = $lwt
    $script:MetraCache.SolutionsKeywords = $unique
    return $unique
}

function Test-MetraQueryContainsRoutingKeyword {
    <#
    .SYNOPSIS
        True when Query contains Keyword with word boundaries (phrases use substring).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query,
        [Parameter(Mandatory)][string]$Keyword
    )

    $qLower = $Query.ToLowerInvariant()
    $kLower = $Keyword.ToLowerInvariant().Trim()
    if ([string]::IsNullOrWhiteSpace($kLower)) { return $false }

    # Multi-word phrases stay substring (e.g. "thrive 360"); single tokens use boundaries
    # so short keywords like "api" do not match inside "rapid".
    if ($kLower -match '\s') {
        return $qLower.Contains($kLower)
    }

    $escaped = [regex]::Escape($kLower)
    return [regex]::IsMatch($qLower, "(?<![\p{L}\p{N}_])$escaped(?![\p{L}\p{N}_])")
}

function Test-MetraTicketTrackerSolutionsKeywordHit {
    <#
    .SYNOPSIS
        True when the query contains a solutions-index keyword/phrase (length >= 3).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query
    )

    foreach ($k in @(Get-MetraTicketTrackerSolutionsKeywords)) {
        if (Test-MetraQueryContainsRoutingKeyword -Query $Query -Keyword ([string]$k)) {
            return $true
        }
    }
    return $false
}

function Test-MetraQueryNamesProject {
    <#
    .SYNOPSIS
        True when the query clearly names a registry project (whole-word / phrase).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query,
        [Parameter(Mandatory)][string]$ProjectName
    )

    if ([string]::IsNullOrWhiteSpace($ProjectName)) { return $false }
    $qLower = $Query.ToLowerInvariant()
    $nameLower = $ProjectName.ToLowerInvariant()
    if ($qLower.Contains($nameLower)) { return $true }
    $tokens = @(Get-MetraQueryTokens -Query $Query)
    return ($tokens -contains $nameLower)
}

function New-MetraTicketTrackerScoredProject {
    <#
    .SYNOPSIS
        Builds a scored routing row for TicketTracker (ticket-id / solutions preference).
    #>
    [CmdletBinding()]
    param(
        [int]$Score = 2,
        [string[]]$MatchedTokens = @()
    )

    $onDisk = Get-MetraTicketTrackerProject
    if (-not $onDisk) { return $null }

    $root = [string](Get-MetraProp -Object $onDisk -Name 'Root' -Default '')
    $path = [string](Get-MetraProp -Object $onDisk -Name 'Path' -Default '')

    $registry = Get-MetraProjectRegistry
    $reg = @($registry.projects | Where-Object { [string]$_.name -eq 'TicketTracker' } | Select-Object -First 1)
    $purpose = if ($reg) { [string](Get-MetraProp -Object $reg -Name 'purpose' -Default '') } else { '' }
    $triggers = if ($reg) { @(Get-MetraProp -Object $reg -Name 'triggers' -Default @()) } else { @() }
    $serves = if ($reg) { @(Get-MetraProp -Object $reg -Name 'serves' -Default @()) } else { @() }

    return [PSCustomObject]@{
        Name          = 'TicketTracker'
        Root          = $root
        Path          = $path
        Purpose       = $purpose
        Triggers      = @($triggers)
        Serves        = @($serves)
        Score         = $Score
        MatchedTokens = [string[]]@($MatchedTokens)
        HayLower      = (@('TicketTracker') + $triggers + @($purpose) | ForEach-Object { [string]$_ }) -join ' '
        IsHomeDefault = $false
    }
}

function Test-MetraRoutingQueryHasTerm {
    <#
    .SYNOPSIS
        True when Query contains Term with Unicode letter/digit/underscore boundaries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query,
        [Parameter(Mandatory)][string]$Term
    )

    $t = ([string]$Term).Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return $false }
    $pattern = '(?i)(?<![\p{L}\p{N}_])' + [regex]::Escape($t) + '(?![\p{L}\p{N}_])'
    return [regex]::IsMatch($Query, $pattern)
}

function Get-MetraCompoundRoutingCueHits {
    <#
    .SYNOPSIS
        Class-level compound cue hits from the raw query (not stop-word filtered tokens).
    .DESCRIPTION
        Returns OpsHits and SqlHits. today/morning stay visible here (routing stop words).
        Multiple words support one class; they are not multiple elections.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query
    )

    $opsLex = @(
        'run', 'ran', 'job', 'status', 'failed', 'failure', 'today', 'morning',
        'load', 'etl', 'start-automation'
    )
    $sqlLex = @('sql', 'procedure', 'deploy', 'script')

    $opsHits = New-Object System.Collections.Generic.List[string]
    foreach ($term in $opsLex) {
        if (Test-MetraRoutingQueryHasTerm -Query $Query -Term $term) {
            [void]$opsHits.Add($term)
        }
    }
    $sqlHits = New-Object System.Collections.Generic.List[string]
    foreach ($term in $sqlLex) {
        if (Test-MetraRoutingQueryHasTerm -Query $Query -Term $term) {
            [void]$sqlHits.Add($term)
        }
    }

    return [PSCustomObject]@{
        OpsHits = [string[]]@($opsHits.ToArray())
        SqlHits = [string[]]@($sqlHits.ToArray())
    }
}

function Get-MetraRoutingStemFromName {
    <#
    .SYNOPSIS
        Product stem = project name before its final hyphen segment (or null if unusable).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $n = ([string]$Name).Trim()
    if ([string]::IsNullOrWhiteSpace($n)) { return $null }
    $idx = $n.LastIndexOf('-')
    if ($idx -lt 1 -or $idx -ge ($n.Length - 1)) { return $null }
    $stem = $n.Substring(0, $idx).Trim()
    if ([string]::IsNullOrWhiteSpace($stem)) { return $null }
    return $stem
}

function Resolve-MetraRoutingGraphRole {
    <#
    .SYNOPSIS
        Fail-closed Ops|Sql role from name/purpose/triggers (not related topology).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Purpose,
        [string[]]$Triggers
    )

    $parts = New-Object System.Collections.Generic.List[string]
    [void]$parts.Add([string]$Name)
    if (-not [string]::IsNullOrWhiteSpace($Purpose)) { [void]$parts.Add([string]$Purpose) }
    foreach ($tr in @($Triggers)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$tr)) { [void]$parts.Add([string]$tr) }
    }
    $text = ($parts -join ' ').ToLowerInvariant()

    $opsEvidence = [regex]::IsMatch($text, '(?i)\b(automation|etl|load|job|jobs|run)\b') -or
        ($Name -match '(?i)automation')
    $sqlEvidence = [regex]::IsMatch($text, '(?i)\b(sql|procedure|deploy|script)\b') -or
        ($Name -match '(?i)(^|-)sql($|-)')

    if ($opsEvidence -and -not $sqlEvidence) { return 'Ops' }
    if ($sqlEvidence -and -not $opsEvidence) { return 'Sql' }
    return $null
}

function Get-MetraRoutingGraph {
    <#
    .SYNOPSIS
        Registry-derived routing graph slice (stem + Ops|Sql members + concepts).
    .DESCRIPTION
        Phase 2 in-memory builder only. Families require mutual related + equal stem and
        fail-closed Ops and Sql roles. Concepts are harvested; not scored in Phase 2.
        Persistence / learned edges are later phases - scorer consumes this shape either way.
    #>
    [CmdletBinding()]
    param(
        [object]$Registry
    )

    if (-not $Registry) {
        $Registry = Get-MetraProjectRegistry
    }

    $rows = @{}
    foreach ($reg in @($Registry.projects)) {
        $name = [string]$reg.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $stem = Get-MetraRoutingStemFromName -Name $name
        if (-not $stem) { continue }
        $purpose = [string](Get-MetraProp -Object $reg -Name 'purpose' -Default '')
        $triggers = @(Get-MetraProp -Object $reg -Name 'triggers' -Default @())
        $related = @(Get-MetraProp -Object $reg -Name 'related' -Default @()) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $role = Resolve-MetraRoutingGraphRole -Name $name -Purpose $purpose -Triggers $triggers
        if (-not $role) { continue }

        $rows[$name.ToLowerInvariant()] = [PSCustomObject]@{
            Name     = $name
            Stem     = $stem
            Role     = $role
            Purpose  = $purpose
            Triggers = @($triggers)
            Related  = @($related)
        }
    }

    $pairKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $families = New-Object System.Collections.Generic.List[object]

    foreach ($key in @($rows.Keys)) {
        $a = $rows[$key]
        foreach ($relName in @($a.Related)) {
            $bKey = $relName.ToLowerInvariant()
            if (-not $rows.ContainsKey($bKey)) { continue }
            $b = $rows[$bKey]
            if ($a.Stem -ne $b.Stem) { continue }
            # Mutual related required
            $aListsB = @($a.Related | Where-Object { $_.Equals($b.Name, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            $bListsA = @($b.Related | Where-Object { $_.Equals($a.Name, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            if (-not ($aListsB -and $bListsA)) { continue }
            if ($a.Role -eq $b.Role) { continue }
            if (@($a.Role, $b.Role) -notcontains 'Ops' -or @($a.Role, $b.Role) -notcontains 'Sql') { continue }

            $pairKey = (@($a.Name, $b.Name) | Sort-Object) -join '|'
            if (-not $pairKeys.Add($pairKey)) { continue }

            $opsMember = if ($a.Role -eq 'Ops') { $a } else { $b }
            $sqlMember = if ($a.Role -eq 'Sql') { $a } else { $b }

            $conceptSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($src in @($opsMember, $sqlMember)) {
                foreach ($w in @((($src.Purpose + ' ' + ($src.Triggers -join ' ')).ToLowerInvariant() -split '\W+'))) {
                    if ($w.Length -lt 4) { continue }
                    if (@('with', 'from', 'that', 'this', 'have', 'warehouse', 'primary', 'home') -contains $w) { continue }
                    [void]$conceptSet.Add($w)
                }
            }

            [void]$families.Add([PSCustomObject]@{
                    Stem     = $a.Stem
                    Roles    = @('Ops', 'Sql')
                    Concepts = [string[]]@(@($conceptSet) | Select-Object -First 12)
                    Members  = @{
                        Ops = $opsMember.Name
                        Sql = $sqlMember.Name
                    }
                    Edges    = @(
                        [PSCustomObject]@{
                            Stem         = $a.Stem
                            IntentFamily = 'ops'
                            TargetRole   = 'Ops'
                            Weight       = 4
                            Evidence     = @('registry-derived')
                            Source       = 'registry'
                        },
                        [PSCustomObject]@{
                            Stem         = $a.Stem
                            IntentFamily = 'sql'
                            TargetRole   = 'Sql'
                            Weight       = 4
                            Evidence     = @('registry-derived')
                            Source       = 'registry'
                        }
                    )
                })
        }
    }

    return @($families.ToArray())
}

function New-MetraCompoundScoredRoutingRow {
    <#
    .SYNOPSIS
        Builds a scored routing row for a sibling inserted by compound apply (live schema).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$RegistryRow,
        [Parameter(Mandatory)]$OnDisk,
        [Parameter(Mandatory)][int]$Score,
        [Parameter(Mandatory)][string[]]$MatchedTokens
    )

    $purpose = [string](Get-MetraProp -Object $RegistryRow -Name 'purpose' -Default '')
    $triggers = @(Get-MetraProp -Object $RegistryRow -Name 'triggers' -Default @())
    $serves = @(Get-MetraProp -Object $RegistryRow -Name 'serves' -Default @())
    $hay = (@($Name) + $triggers + @($purpose) | ForEach-Object { [string]$_ }) -join ' '
    return [PSCustomObject]@{
        Name          = $Name
        Root          = [string]$OnDisk.Root
        Path          = [string]$OnDisk.Path
        Purpose       = $purpose
        Triggers      = @($triggers)
        Serves        = @($serves)
        Score         = $Score
        MatchedTokens = [string[]]@($MatchedTokens)
        HayLower      = $hay.ToLowerInvariant()
    }
}

function Update-MetraScoredRoutingWithCompoundCues {
    <#
    .SYNOPSIS
        Applies at most one compound stem+intent edge boost per family (idempotent).
    .DESCRIPTION
        SQL cue class wins over Ops when both present. +4 once per family; tags compound:ops
        or compound:sql. Inserts missing sibling with the live scored-row schema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Scored,
        [object]$Registry,
        [hashtable]$DiskByName
    )

    if (-not $Registry) {
        $Registry = Get-MetraProjectRegistry
    }
    if (-not $DiskByName) {
        $DiskByName = @{}
        foreach ($p in @(Get-MetraProjects)) {
            $DiskByName[$p.Name.ToLowerInvariant()] = $p
        }
    }

    $cues = Get-MetraCompoundRoutingCueHits -Query $Query
    $hasSql = @($cues.SqlHits).Count -gt 0
    $hasOps = @($cues.OpsHits).Count -gt 0
    if (-not $hasSql -and -not $hasOps) {
        return @($Scored)
    }

    $intentFamily = if ($hasSql) { 'sql' } else { 'ops' }
    $targetRole = if ($hasSql) { 'Sql' } else { 'Ops' }
    $tag = if ($hasSql) { 'compound:sql' } else { 'compound:ops' }

    $families = @(Get-MetraRoutingGraph -Registry $Registry)
    if ($families.Count -eq 0) {
        return @($Scored)
    }

    $regByName = @{}
    foreach ($reg in @($Registry.projects)) {
        $n = [string]$reg.name
        if (-not [string]::IsNullOrWhiteSpace($n)) {
            $regByName[$n.ToLowerInvariant()] = $reg
        }
    }

    $list = New-Object System.Collections.Generic.List[object]
    $byName = @{}
    foreach ($row in @($Scored)) {
        if (-not $row) { continue }
        [void]$list.Add($row)
        $byName[$row.Name.ToLowerInvariant()] = $row
    }

    foreach ($family in $families) {
        $stem = [string]$family.Stem
        if (-not (Test-MetraRoutingQueryHasTerm -Query $Query -Term $stem)) { continue }

        $memberName = [string]$family.Members[$targetRole]
        if ([string]::IsNullOrWhiteSpace($memberName)) { continue }

        $existing = $byName[$memberName.ToLowerInvariant()]
        if ($existing) {
            $tokens = New-Object System.Collections.Generic.List[string]
            foreach ($t in @($existing.MatchedTokens)) { [void]$tokens.Add([string]$t) }
            if ($tokens -contains $tag) { continue }
            [void]$tokens.Add($tag)
            $existing.Score = [int]$existing.Score + 4
            $existing.MatchedTokens = [string[]]@($tokens.ToArray())
            continue
        }

        $regRow = $regByName[$memberName.ToLowerInvariant()]
        $onDisk = $DiskByName[$memberName.ToLowerInvariant()]
        if (-not $regRow -or -not $onDisk) { continue }

        $inserted = New-MetraCompoundScoredRoutingRow `
            -Name $memberName `
            -RegistryRow $regRow `
            -OnDisk $onDisk `
            -Score 4 `
            -MatchedTokens @($tag)
        [void]$list.Add($inserted)
        $byName[$memberName.ToLowerInvariant()] = $inserted
    }

    return @($list.ToArray())
}

function Get-MetraRoutingDurableGraphPath {
    <#
    .SYNOPSIS
        Path to machine-local routing graph.json (does not create file or directory).
    #>
    [CmdletBinding()]
    param()

    Join-Path (Get-MetraRoutingTelemetryRoot) 'graph.json'
}

function Get-MetraRoutingAcceptedEdgeId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Stem,
        [Parameter(Mandatory)][string]$CueClass,
        [Parameter(Mandatory)][string]$Target
    )

    $stemNorm = ([string]$Stem).Trim().ToUpperInvariant()
    $cueNorm = ([string]$CueClass).Trim().ToLowerInvariant()
    $targetSlug = ([string]$Target).Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '_'
    $targetSlug = $targetSlug.Trim('_')
    if ([string]::IsNullOrWhiteSpace($targetSlug)) { $targetSlug = 'unknown' }
    return "e_${stemNorm}_${cueNorm}_${targetSlug}"
}

function Test-MetraRoutingAcceptedEdgeRecord {
    <#
    .SYNOPSIS
        True when a parsed edge object meets schema v1 minimum requirements.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Edge)

    if ($null -eq $Edge) { return $false }

    $id = [string](Get-MetraProp -Object $Edge -Name 'id' -Default '')
    $stem = [string](Get-MetraProp -Object $Edge -Name 'stem' -Default '')
    $target = [string](Get-MetraProp -Object $Edge -Name 'target' -Default '')
    $cueClass = [string](Get-MetraProp -Object $Edge -Name 'cueClass' -Default '').Trim().ToLowerInvariant()
    $source = [string](Get-MetraProp -Object $Edge -Name 'source' -Default '')
    $acceptedRaw = [string](Get-MetraProp -Object $Edge -Name 'acceptedAtUtc' -Default '')
    $noteRaw = Get-MetraProp -Object $Edge -Name 'note' -Default $null

    if ([string]::IsNullOrWhiteSpace($id)) { return $false }
    if ([string]::IsNullOrWhiteSpace($stem)) { return $false }
    if ([string]::IsNullOrWhiteSpace($target)) { return $false }
    if ($cueClass -notin @('ops', 'sql')) { return $false }
    if ($source -ne 'operator') { return $false }
    if ($null -eq $noteRaw) { return $false }

    try {
        $null = [datetime]::Parse($acceptedRaw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
    }
    catch {
        return $false
    }

    return $true
}

function Get-MetraRoutingDurableGraph {
    <#
    .SYNOPSIS
        Loads operator-accepted routing edges (fail-soft empty v1; never rewrites on read).
    #>
    [CmdletBinding()]
    param()

    $empty = [PSCustomObject]@{ version = 1; edges = @() }
    $path = Get-MetraRoutingDurableGraphPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $empty
    }

    try {
        $raw = [System.IO.File]::ReadAllText($path)
    }
    catch {
        return $empty
    }

    if ([string]::IsNullOrWhiteSpace($raw)) { return $empty }

    try {
        $doc = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $empty
    }

    $version = [int](Get-MetraProp -Object $doc -Name 'version' -Default 0)
    if ($version -ne 1) { return $empty }

    $edgeRaw = Get-MetraProp -Object $doc -Name 'edges' -Default $null
    if ($null -eq $edgeRaw) { return $empty }

    $valid = New-Object System.Collections.Generic.List[object]
    foreach ($edge in @($edgeRaw)) {
        if (Test-MetraRoutingAcceptedEdgeRecord -Edge $edge) {
            [void]$valid.Add($edge)
        }
    }

    return [PSCustomObject]@{
        version = 1
        edges   = @($valid.ToArray())
    }
}

function Save-MetraRoutingDurableGraph {
    <#
    .SYNOPSIS
        Validates and atomically writes routing graph.json (fail-loud).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Graph
    )

    $version = [int](Get-MetraProp -Object $Graph -Name 'version' -Default 0)
    if ($version -ne 1) {
        throw 'unsupported graph version'
    }

    $edgeRaw = Get-MetraProp -Object $Graph -Name 'edges' -Default @()
    $edges = @($edgeRaw)
    foreach ($edge in $edges) {
        if (-not (Test-MetraRoutingAcceptedEdgeRecord -Edge $edge)) {
            throw 'invalid edge record'
        }
    }

    $payload = [ordered]@{
        version = 1
        edges   = @(
            foreach ($edge in $edges) {
                [ordered]@{
                    id            = [string]$edge.id
                    stem          = ([string]$edge.stem).Trim().ToUpperInvariant()
                    cueClass      = ([string]$edge.cueClass).Trim().ToLowerInvariant()
                    target        = [string]$edge.target
                    acceptedAtUtc = [string]$edge.acceptedAtUtc
                    source        = 'operator'
                    note          = [string](Get-MetraProp -Object $edge -Name 'note' -Default '')
                }
            }
        )
    }

    $path = Get-MetraRoutingDurableGraphPath
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    $json = ($payload | ConvertTo-Json -Depth 6 -Compress)
    $tmp = "$path.tmp"
    [System.IO.File]::WriteAllText($tmp, ($json + "`r`n"))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Add-MetraRoutingAcceptedEdge {
    <#
    .SYNOPSIS
        Operator accept: replace same stem+cueClass; save once; return resulting edge.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Stem,
        [Parameter(Mandatory)]
        [ValidateSet('ops', 'sql')]
        [string]$CueClass,
        [Parameter(Mandatory)][string]$Target,
        [string]$Note = ''
    )

    $stemNorm = ([string]$Stem).Trim().ToUpperInvariant()
    $cueNorm = ([string]$CueClass).Trim().ToLowerInvariant()
    $targetName = ([string]$Target).Trim()
    if ([string]::IsNullOrWhiteSpace($stemNorm)) { throw 'Stem required' }
    if ([string]::IsNullOrWhiteSpace($targetName)) { throw 'Target required' }

    $reg = Get-MetraRegistryProject -Registry (Get-MetraProjectRegistry) -Name $targetName
    if (-not $reg) { throw "Unknown registry target: $targetName" }

    $canonicalTarget = [string]$reg.name
    $graph = Get-MetraRoutingDurableGraph
    $remaining = New-Object System.Collections.Generic.List[object]
    $replaced = $false
    foreach ($edge in @($graph.edges)) {
        $eStem = ([string]$edge.stem).Trim().ToUpperInvariant()
        $eCue = ([string]$edge.cueClass).Trim().ToLowerInvariant()
        if ($eStem -eq $stemNorm -and $eCue -eq $cueNorm) {
            $replaced = $true
            continue
        }
        [void]$remaining.Add($edge)
    }

    $newEdge = [PSCustomObject]@{
        id            = (Get-MetraRoutingAcceptedEdgeId -Stem $stemNorm -CueClass $cueNorm -Target $canonicalTarget)
        stem          = $stemNorm
        cueClass      = $cueNorm
        target        = $canonicalTarget
        acceptedAtUtc = [datetime]::UtcNow.ToString('o')
        source        = 'operator'
        note          = [string]$Note
        replaced      = $replaced
    }

    [void]$remaining.Add($newEdge)
    Save-MetraRoutingDurableGraph -Graph ([PSCustomObject]@{ version = 1; edges = @($remaining.ToArray()) })
    return $newEdge
}

function Remove-MetraRoutingAcceptedEdge {
    <#
    .SYNOPSIS
        Removes one edge by exact id. No rewrite when id is missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id
    )

    $want = ([string]$Id).Trim()
    if ([string]::IsNullOrWhiteSpace($want)) { throw 'Id required' }

    $graph = Get-MetraRoutingDurableGraph
    $removed = $null
    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($edge in @($graph.edges)) {
        if ([string]$edge.id -eq $want) {
            $removed = $edge
            continue
        }
        [void]$kept.Add($edge)
    }

    if (-not $removed) {
        return [PSCustomObject]@{ removed = $false; edge = $null }
    }

    Save-MetraRoutingDurableGraph -Graph ([PSCustomObject]@{ version = 1; edges = @($kept.ToArray()) })
    return [PSCustomObject]@{ removed = $true; edge = $removed }
}

function Update-MetraScoredRoutingWithAcceptedEdges {
    <#
    .SYNOPSIS
        Applies operator-accepted durable edges after compound cues (+4 once via edge:id token).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Scored,
        [object]$Registry,
        [hashtable]$DiskByName
    )

    $graph = Get-MetraRoutingDurableGraph
    if (@($graph.edges).Count -eq 0) {
        return @($Scored)
    }

    if (-not $Registry) {
        $Registry = Get-MetraProjectRegistry
    }
    if (-not $DiskByName) {
        $DiskByName = @{}
        foreach ($p in @(Get-MetraProjects)) {
            $DiskByName[$p.Name.ToLowerInvariant()] = $p
        }
    }

    $cues = Get-MetraCompoundRoutingCueHits -Query $Query
    $hasSql = @($cues.SqlHits).Count -gt 0
    $hasOps = @($cues.OpsHits).Count -gt 0

    $regByName = @{}
    foreach ($reg in @($Registry.projects)) {
        $n = [string]$reg.name
        if (-not [string]::IsNullOrWhiteSpace($n)) {
            $regByName[$n.ToLowerInvariant()] = $reg
        }
    }

    $list = New-Object System.Collections.Generic.List[object]
    $byName = @{}
    foreach ($row in @($Scored)) {
        if (-not $row) { continue }
        [void]$list.Add($row)
        $byName[$row.Name.ToLowerInvariant()] = $row
    }

    foreach ($edge in @($graph.edges)) {
        $stem = ([string]$edge.stem).Trim()
        $cueClass = ([string]$edge.cueClass).Trim().ToLowerInvariant()
        $targetName = [string]$edge.target
        $edgeId = [string]$edge.id
        $token = "edge:$edgeId"

        if (-not (Test-MetraRoutingQueryHasTerm -Query $Query -Term $stem)) { continue }
        if ($cueClass -eq 'ops' -and -not $hasOps) { continue }
        if ($cueClass -eq 'sql' -and -not $hasSql) { continue }

        $existing = $byName[$targetName.ToLowerInvariant()]
        if ($existing) {
            $tokens = New-Object System.Collections.Generic.List[string]
            foreach ($t in @($existing.MatchedTokens)) { [void]$tokens.Add([string]$t) }
            if ($tokens -contains $token) { continue }
            [void]$tokens.Add($token)
            $existing.Score = [int]$existing.Score + 4
            $existing.MatchedTokens = [string[]]@($tokens.ToArray())
            continue
        }

        $regRow = $regByName[$targetName.ToLowerInvariant()]
        $onDisk = $DiskByName[$targetName.ToLowerInvariant()]
        if (-not $regRow -or -not $onDisk) { continue }

        $inserted = New-MetraCompoundScoredRoutingRow `
            -Name $targetName `
            -RegistryRow $regRow `
            -OnDisk $onDisk `
            -Score 4 `
            -MatchedTokens @($token)
        [void]$list.Add($inserted)
        $byName[$targetName.ToLowerInvariant()] = $inserted
    }

    return @($list.ToArray())
}

function Get-MetraRoutingEdgeCandidates {
    <#
    .SYNOPSIS
        Aggregates ambiguous telemetry into stem/cue/primary/runner-up counts (Observe-only).
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Last = 200
    )

    $events = @(Get-MetraRoutingTelemetryEvents -Last $Last)
    if ($events.Count -eq 0) { return @() }

    $counts = @{}
    foreach ($evt in $events) {
        if ([string]$evt.outcome -ne 'ambiguous') { continue }

        $primaryName = [string]$evt.primary
        $runnerName = if ($null -eq $evt.runnerUp -or [string]::IsNullOrWhiteSpace([string]$evt.runnerUp)) { '' } else { [string]$evt.runnerUp }
        $stem = Get-MetraRoutingStemFromName -Name $primaryName
        if (-not $stem) { $stem = Get-MetraRoutingStemFromName -Name $runnerName }
        if (-not $stem) { continue }

        $cueClass = $null
        $favored = @($evt.favoredTokens)
        $matched = @($evt.matchedTokens)
        if ($favored -contains 'compound:sql') { $cueClass = 'sql' }
        elseif ($favored -contains 'compound:ops') { $cueClass = 'ops' }
        elseif ($matched -contains 'compound:sql') { $cueClass = 'sql' }
        elseif ($matched -contains 'compound:ops') { $cueClass = 'ops' }
        if (-not $cueClass) { continue }

        $key = (@($stem.ToUpperInvariant(), $cueClass, $primaryName, $runnerName) -join '|')
        if (-not $counts.ContainsKey($key)) {
            $counts[$key] = [PSCustomObject]@{
                Stem     = $stem.ToUpperInvariant()
                CueClass = $cueClass
                Primary  = $primaryName
                RunnerUp = $runnerName
                Count    = 0
            }
        }
        $counts[$key].Count++
    }

    return @(
        $counts.Values |
            Sort-Object `
                @{ Expression = 'Count'; Descending = $true },
                Stem,
                CueClass,
                Primary,
                RunnerUp
    )
}

function Get-MetraScoredRoutingProjects {
    <#
    .SYNOPSIS
        Scores present registry projects for a query (same rules as ctx).
    .DESCRIPTION
        Tokens match whole words in the project name / triggers / purpose haystack - not
        substrings. Stop words are dropped first so "to" / "in" / "the" / "or" cannot steal
        the primary route from noise inside purpose text (e.g. "get-together", "authority").
        After haystack scoring, a compound cue pass may boost Ops|Sql siblings from the
        registry-derived routing graph (Phase 2).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query,
        [int]$Limit = 25
    )

    if ($Limit -lt 1) { $Limit = 25 }
    $tokens = @(Get-MetraQueryTokens -Query $Query)
    if ($tokens.Count -eq 0) { return @() }

    $registry = Get-MetraProjectRegistry
    $disk = @{}
    foreach ($p in @(Get-MetraProjects)) {
        $disk[$p.Name.ToLowerInvariant()] = $p
    }

    $qLower = $Query.ToLowerInvariant()
    $scored = New-Object System.Collections.Generic.List[object]
    foreach ($reg in @($registry.projects)) {
        $regName = [string]$reg.name
        $onDisk = $disk[$regName.ToLowerInvariant()]
        if (-not $onDisk) { continue }

        $purpose = [string](Get-MetraProp -Object $reg -Name 'purpose' -Default '')
        $triggers = @(Get-MetraProp -Object $reg -Name 'triggers' -Default @())
        $serves = @(Get-MetraProp -Object $reg -Name 'serves' -Default @())
        $hay = (@($regName) + $triggers + @($purpose) | ForEach-Object { [string]$_ }) -join ' '
        $hayLower = $hay.ToLowerInvariant()
        $hayWords = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($w in @($hayLower -split '\W+')) {
            if ($w) { [void]$hayWords.Add($w) }
        }

        $score = 0
        $matchedTokens = New-Object System.Collections.Generic.List[string]
        foreach ($t in $tokens) {
            if ($hayWords.Contains($t)) {
                $score++
                [void]$matchedTokens.Add($t)
            }
            if ($regName.ToLowerInvariant() -eq $t) { $score += 2 }
        }

        # Multi-word / distinctive triggers beat scattered word noise when the query names them.
        foreach ($tr in $triggers) {
            $trLower = ([string]$tr).ToLowerInvariant().Trim()
            if ([string]::IsNullOrWhiteSpace($trLower)) { continue }
            if ($trLower.Length -lt 3) { continue }
            if ($qLower.Contains($trLower)) {
                $score += 3
                [void]$matchedTokens.Add("phrase:$trLower")
            }
        }

        if ($score -le 0) { continue }

        [void]$scored.Add([PSCustomObject]@{
                Name          = $regName
                Root          = [string]$onDisk.Root
                Path          = [string]$onDisk.Path
                Purpose       = $purpose
                Triggers      = @($triggers)
                Serves        = @($serves)
                Score         = $score
                MatchedTokens = [string[]]@($matchedTokens.ToArray())
                HayLower      = $hayLower
            })
    }

    $withCompound = @(Update-MetraScoredRoutingWithCompoundCues -Query $Query -Scored @($scored.ToArray()) -Registry $registry -DiskByName $disk)
    $withEdges = @(Update-MetraScoredRoutingWithAcceptedEdges -Query $Query -Scored $withCompound -Registry $registry -DiskByName $disk)

    # Prefer compound:sql over compound:ops on equal scores (mixed-cue SQL precedence).
    return @(
        $withEdges |
            Sort-Object `
                @{ Expression = 'Score'; Descending = $true },
                @{ Expression = {
                        $tags = @($_.MatchedTokens)
                        if ($tags -contains 'compound:sql') { 0 }
                        elseif ($tags -contains 'compound:ops') { 1 }
                        else { 2 }
                    }
                },
                Name |
            Select-Object -First $Limit
    )
}

function Test-MetraRoutingAmbiguity {
    <#
    .SYNOPSIS
        True when primary and runner-up scores are close per Why Here v1 rules.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$PrimaryScore,
        [int]$RunnerUpScore
    )

    if ($RunnerUpScore -le 0) { return $false }
    $diff = $PrimaryScore - $RunnerUpScore
    if ($diff -le 1) { return $true }
    if ($PrimaryScore -ge 2 -and $RunnerUpScore -ge ([math]::Ceiling($PrimaryScore * 0.5))) {
        return $true
    }
    return $false
}

function Get-MetraRoutingTelemetryRoot {
    <#
    .SYNOPSIS
        Machine-local routing telemetry directory path (does not create it).
    #>
    [CmdletBinding()]
    param()

    Join-Path $env:LOCALAPPDATA 'Metra\routing'
}

function Get-MetraRoutingTelemetryEventsPath {
    <#
    .SYNOPSIS
        Path to routing telemetry events.jsonl (does not create it).
    #>
    [CmdletBinding()]
    param()

    Join-Path (Get-MetraRoutingTelemetryRoot) 'events.jsonl'
}

function Get-MetraRoutingTelemetryOutcome {
    <#
    .SYNOPSIS
        Classifies a completed ambiguity result as confident, ambiguous, or home.
    .DESCRIPTION
        Witness-only: reads Primary / IsAmbiguous / home name. Does not re-score.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$RoutingResult
    )

    if ([bool]$RoutingResult.IsAmbiguous) {
        return 'ambiguous'
    }

    $homeName = Get-MetraHomeDestinationName
    $primary = $RoutingResult.Primary
    $primaryName = if ($primary) { [string]$primary.Name } else { '' }
    $primaryScore = if ($primary) { [int]$primary.Score } else { 0 }
    if ($primaryName -eq $homeName -and $primaryScore -lt 2) {
        return 'home'
    }

    return 'confident'
}

function Add-MetraRoutingTelemetryEvent {
    <#
    .SYNOPSIS
        Appends one Observe-only routing event to machine-local JSONL.
    .DESCRIPTION
        Creates the telemetry directory if needed. Never throws into the routing hot path.
        Maps fields from the completed ambiguity result only - no re-scoring.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query,

        [string]$Source = 'other',

        [Parameter(Mandatory)]
        [object]$RoutingResult
    )

    try {
        $src = [string]$Source
        if ($src -notin @('routing', 'ctx', 'other')) {
            $src = 'other'
        }

        $root = Get-MetraRoutingTelemetryRoot
        $path = Get-MetraRoutingTelemetryEventsPath
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $root -Force
        }

        $queryText = ([string]$Query -replace '\r?\n', ' ').Trim()
        if ($queryText.Length -gt 512) {
            $queryText = $queryText.Substring(0, 512)
        }

        $outcome = Get-MetraRoutingTelemetryOutcome -RoutingResult $RoutingResult
        $primary = $RoutingResult.Primary
        $runnerUp = $RoutingResult.RunnerUp
        $isAmbiguous = [bool]$RoutingResult.IsAmbiguous

        $matchedTokens = @(if ($primary) { @($primary.MatchedTokens) } else { @() })
        $favoredTokens = [string[]]@(
            if ($isAmbiguous) { @($RoutingResult.FavoredTokens) }
        )

        $event = [ordered]@{
            tsUtc          = [datetime]::UtcNow.ToString('o')
            source         = $src
            query          = $queryText
            outcome        = [string]$outcome
            primary        = if ($primary) { [string]$primary.Name } else { $null }
            primaryScore   = if ($primary) { [int]$primary.Score } else { 0 }
            runnerUp       = if ($runnerUp) { [string]$runnerUp.Name } else { $null }
            runnerUpScore  = if ($runnerUp) { [int]$runnerUp.Score } else { $null }
            isAmbiguous    = $isAmbiguous
            matchedTokens  = [string[]]@($matchedTokens)
            favoredTokens  = $favoredTokens
        }

        $line = ($event | ConvertTo-Json -Compress -Depth 6)
        Add-Content -LiteralPath $path -Value $line -Encoding utf8 -ErrorAction Stop
    }
    catch {
        # Telemetry must never interrupt routing.
    }
}

function Get-MetraRoutingTelemetryEvents {
    <#
    .SYNOPSIS
        Reads the last N routing telemetry events (read-only; never creates the sink).
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Last = 20
    )

    $path = Get-MetraRoutingTelemetryEventsPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }

    try {
        $lines = @(Get-Content -LiteralPath $path -Tail $Last -ErrorAction Stop)
    }
    catch {
        return @()
    }

    if ($lines.Count -eq 0) { return @() }
    $parsed = New-Object System.Collections.Generic.List[object]
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
            [void]$parsed.Add($obj)
        }
        catch {
            # Skip malformed or partial trailing lines.
        }
    }
    return @($parsed.ToArray())
}

function Show-MetraRoutingEventsCli {
    <#
    .SYNOPSIS
        Host table of recent routing telemetry events (read-only).
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Last = 20
    )

    $path = Get-MetraRoutingTelemetryEventsPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host 'No routing events recorded.'
        return
    }

    $events = @(Get-MetraRoutingTelemetryEvents -Last $Last)
    if ($events.Count -eq 0) {
        Write-Host 'No routing events recorded.'
        return
    }

    $rows = @(
        foreach ($e in $events) {
            $q = [string]$e.query
            if ($q.Length -gt 60) { $q = $q.Substring(0, 57) + '...' }
            [PSCustomObject]@{
                ts       = [string]$e.tsUtc
                outcome  = [string]$e.outcome
                primary  = [string]$e.primary
                runnerUp = if ($null -eq $e.runnerUp -or [string]::IsNullOrWhiteSpace([string]$e.runnerUp)) { '' } else { [string]$e.runnerUp }
                query    = $q
            }
        }
    )
    $rows | Format-Table -AutoSize
}

function Get-MetraRoutingAmbiguity {
    <#
    .SYNOPSIS
        Picks primary (+ optional close runner-up) for a routing query.
    .DESCRIPTION
        Metra is the home destination until another project wins with a confident score
        (score >= 2). Weak incidental matches do not displace Metra.
        Precedence before technical score: ticket-shaped id > ticket/helpdesk vocabulary >
        TicketTracker solutions-index keywords. Product names are not registry triggers.
        After the result is built, optionally appends Observe-only telemetry (never influences the result).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Query,

        [string]$Source = 'other',

        [switch]$SkipTelemetry
    )

    $scored = @(Get-MetraScoredRoutingProjects -Query $Query -Limit 10)
    $homeName = Get-MetraHomeDestinationName
    $tokens = @(Get-MetraQueryTokens -Query $Query)
    $ttPresent = $null -ne (Get-MetraTicketTrackerProject)
    $namedOther = $false
    if ($ttPresent) {
        foreach ($row in @($scored | Where-Object { $_.Name -ne 'TicketTracker' })) {
            if (Test-MetraQueryNamesProject -Query $Query -ProjectName $row.Name) {
                $namedOther = $true
                break
            }
        }
    }

    $ticketPrefer = $null
    $ticketPreferForce = $false
    if ($ttPresent) {
        if (Test-MetraTicketShapedQuery -Query $Query) {
            # Ticket id is a workflow artifact - always prefer TicketTracker when present.
            $ticketPrefer = New-MetraTicketTrackerScoredProject -Score 3 -MatchedTokens @('ticket-id')
            $ticketPreferForce = $true
        }
        elseif (-not $namedOther) {
            if (Test-MetraTicketHelpdeskVocabulary -Query $Query) {
                $ticketPrefer = $scored | Where-Object { $_.Name -eq 'TicketTracker' -and [int]$_.Score -ge 1 } | Select-Object -First 1
                if (-not $ticketPrefer) {
                    $ticketPrefer = New-MetraTicketTrackerScoredProject -Score 2 -MatchedTokens @('ticket-vocab')
                }
            }
            elseif (Test-MetraTicketTrackerSolutionsKeywordHit -Query $Query) {
                $ticketPrefer = New-MetraTicketTrackerScoredProject -Score 2 -MatchedTokens @('solutions-keyword')
            }
        }
    }

    $confident = $scored | Where-Object { [int]$_.Score -ge 2 } | Select-Object -First 1

    if ($ticketPrefer) {
        if ($ticketPreferForce -or -not $confident -or $confident.Name -eq 'TicketTracker' -or -not $namedOther) {
            $confident = $ticketPrefer
        }
    }

    if (-not $confident) {
        $homeFromScore = $scored | Where-Object { $_.Name -eq $homeName } | Select-Object -First 1
        $primary = if ($homeFromScore) { $homeFromScore } else { New-MetraHomeScoredProject -Score 0 }
        $result = [PSCustomObject]@{
            Primary       = $primary
            RunnerUp      = $null
            IsAmbiguous   = $false
            FavoredTokens = @()
        }
        if (-not $SkipTelemetry) {
            Add-MetraRoutingTelemetryEvent -Query $Query -Source $Source -RoutingResult $result
        }
        return $result
    }

    $primary = $confident
    # Keep original order for runner-up among remaining scored rows
    $runnerUp = $scored | Where-Object { $_.Name -ne $primary.Name } | Select-Object -First 1
    $ambiguous = $false
    $favored = @()
    if ($runnerUp) {
        $ambiguous = Test-MetraRoutingAmbiguity -PrimaryScore ([int]$primary.Score) -RunnerUpScore ([int]$runnerUp.Score)
        if ($ambiguous) {
            $favoredList = New-Object System.Collections.Generic.List[string]
            # Prefer compound evidence when it decided the primary.
            foreach ($t in @($primary.MatchedTokens | Where-Object { $_ -like 'compound:*' } | Select-Object -Unique)) {
                [void]$favoredList.Add($t)
            }
            foreach ($t in $tokens) {
                $inPrimary = $primary.HayLower.Contains($t)
                $inRunner = $runnerUp.HayLower.Contains($t)
                if ($inPrimary -and -not $inRunner -and -not ($favoredList -contains $t)) {
                    [void]$favoredList.Add($t)
                }
            }
            if ($favoredList.Count -eq 0) {
                foreach ($t in @($primary.MatchedTokens | Select-Object -Unique)) {
                    [void]$favoredList.Add($t)
                }
            }
            $favored = [string[]]@($favoredList.ToArray())
        }
        else {
            $runnerUp = $null
        }
    }

    $result = [PSCustomObject]@{
        Primary       = $primary
        RunnerUp      = $runnerUp
        IsAmbiguous   = $ambiguous
        FavoredTokens = $favored
    }
    if (-not $SkipTelemetry) {
        Add-MetraRoutingTelemetryEvent -Query $Query -Source $Source -RoutingResult $result
    }
    return $result
}

function Write-MetraForWhom {
    <#
    .SYNOPSIS
        Writes a For whom? audience block to the host (omit when empty).
    #>
    [CmdletBinding()]
    param(
        [string[]]$Serves
    )

    $audiences = @($Serves | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($audiences.Count -eq 0) { return }

    Write-Host 'For whom?'
    foreach ($s in $audiences) {
        Write-Host ("  {0}" -f $s)
    }
}

function Get-MetraRelatedProjects {
    <#
    .SYNOPSIS
        Canonical same-root related neighbors for a registry project (topology only).
    .DESCRIPTION
        Preserves registry related order; dedupes case-insensitive (first wins); drops
        unknown names; keeps same-root only; caps at Limit (default 6). Does not sort.
        Related is topology, not permission to multi-repo search.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$SourceRoot,
        [object]$Registry,
        [hashtable]$DiskByName,
        [ValidateRange(1, 50)]
        [int]$Limit = 6
    )

    if (-not $Registry) {
        $Registry = Get-MetraProjectRegistry
    }
    if (-not $DiskByName) {
        $DiskByName = @{}
        foreach ($p in @(Get-MetraProjects)) {
            $DiskByName[$p.Name.ToLowerInvariant()] = $p
        }
    }

    $regByName = @{}
    foreach ($reg in @($Registry.projects)) {
        $key = ([string]$reg.name).ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $regByName[$key] = $reg
        }
    }

    $sourceKey = $Name.ToLowerInvariant()
    $sourceReg = $regByName[$sourceKey]
    if (-not $sourceReg) { return @() }

    $primaryRootName = ''
    foreach ($r in @(Get-MetraRoots -IncludeMissing)) {
        if ($r.Primary) {
            $primaryRootName = [string]$r.Name
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($primaryRootName)) {
        $first = @(Get-MetraRoots -IncludeMissing) | Select-Object -First 1
        if ($first) { $primaryRootName = [string]$first.Name }
    }

    $resolveRoot = {
        param($ProjectKey, $RegRow, $Disk, $FallbackRoot)
        $onDisk = $Disk[$ProjectKey]
        if ($onDisk -and -not [string]::IsNullOrWhiteSpace([string]$onDisk.Root)) {
            return [string]$onDisk.Root
        }
        if ($RegRow) {
            $explicit = [string](Get-MetraProp -Object $RegRow -Name 'root' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($explicit)) {
                return $explicit
            }
        }
        return $FallbackRoot
    }

    $resolvedSourceRoot = $SourceRoot
    if ([string]::IsNullOrWhiteSpace($resolvedSourceRoot)) {
        $resolvedSourceRoot = & $resolveRoot $sourceKey $sourceReg $DiskByName $primaryRootName
    }
    if ([string]::IsNullOrWhiteSpace($resolvedSourceRoot)) {
        return @()
    }

    $rawRelated = @(Get-MetraProp -Object $sourceReg -Name 'related' -Default @())
    $seen = @{}
    $out = New-Object System.Collections.Generic.List[object]

    foreach ($raw in $rawRelated) {
        $relName = [string]$raw
        if ([string]::IsNullOrWhiteSpace($relName)) { continue }
        $relKey = $relName.ToLowerInvariant()
        if ($seen.ContainsKey($relKey)) { continue }
        $seen[$relKey] = $true

        $relReg = $regByName[$relKey]
        if (-not $relReg) { continue }

        $relRoot = & $resolveRoot $relKey $relReg $DiskByName $primaryRootName
        if ([string]::IsNullOrWhiteSpace($relRoot)) { continue }
        if ($relRoot.ToLowerInvariant() -ne $resolvedSourceRoot.ToLowerInvariant()) { continue }

        $canonicalName = [string]$relReg.name
        if ([string]::IsNullOrWhiteSpace($canonicalName)) { $canonicalName = $relName }

        [void]$out.Add([PSCustomObject]@{
                Name    = $canonicalName
                Present = [bool]$DiskByName.ContainsKey($relKey)
            })
        if ($out.Count -ge $Limit) { break }
    }

    return @($out.ToArray())
}

function Write-MetraRelatedProjects {
    param(
        [object[]]$Related
    )

    $rows = @($Related | Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) })
    if ($rows.Count -eq 0) { return }
    $parts = @(
        $rows | ForEach-Object {
            $label = [string]$_.Name
            if (-not $_.Present) { $label = "$label (missing)" }
            $label
        }
    )
    Write-Host ("Related: {0}" -f ($parts -join ', '))
}

function Show-MetraRoutingCli {
    <#
    .SYNOPSIS
        CLI host output for routing (For whom? / Why Here). Compatibility export for metra.ps1.
    #>
    [CmdletBinding()]
    param(
        [string]$Query,
        [string[]]$Name,
        [switch]$SharedOnly,
        [switch]$MissingOnly
    )

    if (-not [string]::IsNullOrWhiteSpace($Query) -and (-not $Name -or $Name.Count -eq 0) -and -not $SharedOnly -and -not $MissingOnly) {
        $amb = Get-MetraRoutingAmbiguity -Query $Query -Source routing
        if (-not $amb.Primary) {
            Write-Host ("No present projects matched query: {0}" -f $Query) -ForegroundColor Yellow
            return
        }

        $primary = $amb.Primary
        Write-Host ("Primary: {0} (score={1})" -f $primary.Name, $primary.Score) -ForegroundColor Cyan
        if ($primary.Purpose) {
            Write-Host ("  {0}" -f $primary.Purpose)
        }
        Write-Host ("  triggers: {0}" -f ($(if ($primary.Triggers.Count -gt 0) { $primary.Triggers -join ', ' } else { '(none)' })))
        if (@($primary.Serves).Count -gt 0) {
            Write-Host ''
            Write-MetraForWhom -Serves $primary.Serves
        }
        $relatedTopo = @(Get-MetraRelatedProjects -Name $primary.Name -SourceRoot $primary.Root)
        if ($relatedTopo.Count -gt 0) {
            Write-Host ''
            Write-MetraRelatedProjects -Related $relatedTopo
        }
        $compoundTag = @($primary.MatchedTokens | Where-Object { $_ -like 'compound:*' } | Select-Object -First 1)
        $cueLabel = $null
        if ($compoundTag.Count -gt 0) {
            $cueLabel = if ($compoundTag[0] -eq 'compound:sql') { 'product+sql' } else { 'product+ops' }
        }
        $why = @(Get-MetraWhyHere -Project $primary.Name -Query $Query -Limit 3)
        if ($why.Count -gt 0) {
            Write-Host ''
            Write-MetraWhyHere -Project $primary.Name -Decisions $why
            if ($cueLabel) {
                Write-Host ("  Compound cue: {0}" -f $cueLabel)
            }
        }
        elseif ($cueLabel) {
            Write-Host ''
            Write-Host ("Why here? {0}" -f $primary.Name)
            Write-Host ("  Compound cue: {0}" -f $cueLabel)
        }
        if ($amb.IsAmbiguous -and $amb.RunnerUp) {
            $runner = $amb.RunnerUp
            Write-Host ''
            Write-Host ("Runner-up: {0} (score={1})" -f $runner.Name, $runner.Score) -ForegroundColor Yellow
            if (@($runner.Serves).Count -gt 0) {
                Write-MetraForWhom -Serves $runner.Serves
                Write-Host ''
            }
            $whyNot = @(Get-MetraWhyHere -Project $runner.Name -Query $Query -Limit 2)
            Write-MetraWhyNot -Project $runner.Name -Decisions $whyNot -FavoredTokens $amb.FavoredTokens
        }
        return
    }

    $rows = @(Get-MetraRoutingTable -Name $Name -SharedOnly:$SharedOnly -MissingOnly:$MissingOnly)
    if ($rows.Count -eq 0) {
        Write-Host 'No registry entries matched.' -ForegroundColor Yellow
        return
    }

    $rows |
        Select-Object Name, Source, Root, Present, Optional,
            @{ n = 'Triggers'; e = { ($_.Triggers -join ', ') } } |
        Format-Table -AutoSize
    foreach ($row in @($rows | Where-Object { -not $_.Present })) {
        Write-Host ("{0}: {1}" -f $row.Name, $row.Advice) -ForegroundColor Yellow
    }
    Write-Host ("{0} entr(ies); {1} present" -f $rows.Count, @($rows | Where-Object Present).Count)

    # For whom / Why Here only when -Name scopes the stop (not full-table dump)
    if ($Name -and $Name.Count -gt 0 -and -not $MissingOnly) {
        foreach ($row in @($rows | Where-Object Present)) {
            if (@($row.Serves).Count -gt 0) {
                Write-Host ''
                Write-MetraForWhom -Serves $row.Serves
            }
            $relatedTopo = @(Get-MetraRelatedProjects -Name $row.Name -SourceRoot $row.Root)
            if ($relatedTopo.Count -gt 0) {
                Write-Host ''
                Write-MetraRelatedProjects -Related $relatedTopo
            }
            $why = @(Get-MetraWhyHere -Project $row.Name -Query $Query -Limit 3)
            if ($why.Count -gt 0) {
                Write-Host ''
                Write-MetraWhyHere -Project $row.Name -Decisions $why
            }
        }
    }
}

function Show-MetraRoutingEdgesCli {
    <#
    .SYNOPSIS
        Operator CLI for durable accepted routing edges (list / candidates / accept / remove).
    .DESCRIPTION
        Only accept and remove mutate graph.json. Candidates and list are read-only.
    #>
    [CmdletBinding()]
    param(
        [string[]]$SubCommand = @(),
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Last = 200,
        [string]$Stem,
        [string]$CueClass,
        [string]$Target,
        [string]$Note,
        [string]$Id
    )

    $action = if ($SubCommand.Count -gt 0) { [string]$SubCommand[0].Trim().ToLowerInvariant() } else { 'list' }

    switch ($action) {
        'list' {
            $graph = Get-MetraRoutingDurableGraph
            $edges = @($graph.edges)
            if ($edges.Count -eq 0) {
                Write-Host 'No accepted routing edges.'
                return
            }
            $rows = @(
                foreach ($e in $edges) {
                    [PSCustomObject]@{
                        Id            = [string]$e.id
                        Stem          = [string]$e.stem
                        CueClass      = [string]$e.cueClass
                        Target        = [string]$e.target
                        AcceptedAtUtc = [string]$e.acceptedAtUtc
                        Note          = [string](Get-MetraProp -Object $e -Name 'note' -Default '')
                    }
                }
            )
            $rows | Format-Table -AutoSize
        }
        'candidates' {
            $candidates = @(Get-MetraRoutingEdgeCandidates -Last $Last)
            if ($candidates.Count -eq 0) {
                Write-Host 'No ambiguous routing candidates in telemetry tail.'
                return
            }
            $candidates |
                Select-Object Stem, CueClass, Primary, RunnerUp, Count |
                Format-Table -AutoSize
        }
        'accept' {
            if ([string]::IsNullOrWhiteSpace($Stem)) { throw 'accept requires -Stem' }
            if ([string]::IsNullOrWhiteSpace($CueClass)) { throw 'accept requires -CueClass ops|sql' }
            if ([string]::IsNullOrWhiteSpace($Target)) { throw 'accept requires -Target' }
            $cue = $CueClass.Trim().ToLowerInvariant()
            if ($cue -notin @('ops', 'sql')) { throw 'CueClass must be ops or sql' }
            $edge = Add-MetraRoutingAcceptedEdge -Stem $Stem -CueClass $cue -Target $Target -Note $Note
            if ($edge.replaced) {
                Write-Host ("Replaced prior {0}+{1} edge -> {2} ({3})" -f $edge.stem, $edge.cueClass, $edge.target, $edge.id) -ForegroundColor Cyan
            }
            else {
                Write-Host ("Accepted edge {0}+{1} -> {2} ({3})" -f $edge.stem, $edge.cueClass, $edge.target, $edge.id) -ForegroundColor Green
            }
        }
        'remove' {
            if ([string]::IsNullOrWhiteSpace($Id)) { throw 'remove requires -Id' }
            $result = Remove-MetraRoutingAcceptedEdge -Id $Id
            if (-not $result.removed) {
                Write-Host ("Edge not found: {0}" -f $Id) -ForegroundColor Yellow
                return
            }
            $e = $result.edge
            Write-Host ("Removed edge {0} ({1}+{2} -> {3})" -f $e.id, $e.stem, $e.cueClass, $e.target) -ForegroundColor Green
        }
        default {
            throw "Unknown routing edges subcommand '$action'. Use list, candidates, accept, or remove."
        }
    }
}

