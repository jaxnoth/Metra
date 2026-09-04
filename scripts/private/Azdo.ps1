# Azure DevOps remote evidence - read-only REST client for Metra portfolio gap mapping and gated Ask excerpts.

function Get-MetraAzdoApiVersion {
    return '7.1'
}

function Get-MetraAzdoConfigPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return Get-MetraAzdoLocalConfigPath -MetraRoot $MetraRoot
}

function Get-MetraAzdoCacheDir {
    return Join-Path $env:LOCALAPPDATA 'Metra\azdo'
}

function Get-MetraAzdoDefaultConfig {
    return [ordered]@{
        organization         = ''
        project              = ''
        maxRepos             = 200
        maxSearchHits        = 25
        maxFileChars         = 120000
        maxAskFileChars      = 16000
        maxAskSearchHits     = 3
        maxTreeDepth         = 4
        maxTreeItems         = 500
        gapListLimit         = 25
        ideaRepoNamePatterns = @('*Experience*', '*Ethos*')
        ideaPathPatterns     = @('**/cards/**', '**/pages/**')
    }
}

function Get-MetraAzdoConfig {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $defaults = Get-MetraAzdoDefaultConfig
    $path = Get-MetraAzdoConfigPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]$defaults
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return [PSCustomObject]$defaults
    }

    $cfg = [ordered]@{}
    foreach ($key in $defaults.Keys) {
        $val = Get-MetraProp -Object $raw -Name $key -Default $null
        if ($null -eq $val) {
            $cfg[$key] = $defaults[$key]
        }
        elseif ($defaults[$key] -is [array]) {
            $cfg[$key] = @($val)
        }
        else {
            $cfg[$key] = $val
        }
    }
    return [PSCustomObject]$cfg
}

function Resolve-MetraAzdoPatPrecedence {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$ProcessPat,
        [AllowEmptyString()][string]$UserPat,
        [AllowEmptyString()][string]$MachinePat
    )

    foreach ($entry in @(
            @{ Pat = $ProcessPat; Scope = 'Process' }
            @{ Pat = $UserPat; Scope = 'User' }
            @{ Pat = $MachinePat; Scope = 'Machine' }
        )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.Pat)) {
            return [PSCustomObject]@{
                Pat   = ([string]$entry.Pat).Trim()
                Scope = [string]$entry.Scope
            }
        }
    }
    return $null
}

function Get-MetraAzdoPatFromEnvironment {
    <#
    .SYNOPSIS
        PAT from env scopes only: Process, then User, then Machine.
    #>
    [CmdletBinding()]
    param()

    $resolved = Resolve-MetraAzdoPatPrecedence `
        -ProcessPat ([string]$env:METRA_AZDO_PAT) `
        -UserPat ([Environment]::GetEnvironmentVariable('METRA_AZDO_PAT', 'User')) `
        -MachinePat ([Environment]::GetEnvironmentVariable('METRA_AZDO_PAT', 'Machine'))
    if ($null -ne $resolved) {
        $env:METRA_AZDO_PAT = [string]$resolved.Pat
    }
    return $resolved
}

function Get-MetraAzdoPat {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $fromEnv = Get-MetraAzdoPatFromEnvironment
    if ($null -ne $fromEnv) {
        return [string]$fromEnv.Pat
    }

    $path = Get-MetraAzdoConfigPath -MetraRoot $MetraRoot
    if (Test-Path -LiteralPath $path) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $filePat = [string](Get-MetraProp -Object $raw -Name 'pat' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($filePat)) {
                return $filePat.Trim()
            }
        }
        catch { }
    }
    return $null
}

function Test-MetraAzdoAuthenticated {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return -not [string]::IsNullOrWhiteSpace((Get-MetraAzdoPat -MetraRoot $MetraRoot))
}

function Get-MetraAzdoAuthHeader {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $pat = Get-MetraAzdoPat -MetraRoot $MetraRoot
    if ([string]::IsNullOrWhiteSpace($pat)) {
        throw 'Azure DevOps PAT not configured. Set METRA_AZDO_PAT or %LOCALAPPDATA%/Metra/azdo.local.json (see docs/examples/azdo.local.example.json).'
    }
    $pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
    return @{
        Authorization = "Basic $pair"
    }
}

function Get-MetraAzdoBaseUrl {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$Organization
    )

    $cfg = Get-MetraAzdoConfig -MetraRoot $MetraRoot
    $org = if ($Organization) { $Organization } else { [string]$cfg.organization }
    if ([string]::IsNullOrWhiteSpace($org)) {
        throw 'Azure DevOps organization not configured. Set organization in %LOCALAPPDATA%/Metra/azdo.local.json.'
    }
    return "https://dev.azure.com/$org"
}

function Normalize-MetraAzdoName {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $n = $Name.ToLowerInvariant()
    $n = $n -replace '[\s\-_]+', ''
    return $n
}

function Test-MetraAzdoWildcardMatch {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Pattern,
        [AllowEmptyString()][string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) { return $true }
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $escaped = [regex]::Escape($Pattern).Replace('\*', '.*')
    return [bool]($Value -match ("(?i)^{0}$" -f $escaped))
}

function Invoke-MetraAzdoRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get', 'Post')]
        [string]$Method = 'Get',
        [object]$Body = $null,
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$Organization,
        [int]$TimeoutSec = 120
    )

    $base = Get-MetraAzdoBaseUrl -MetraRoot $MetraRoot -Organization $Organization
    $sep = if ($Path -match '\?') { '&' } else { '?' }
    $uri = "$base/$($Path.TrimStart('/'))${sep}api-version=$(Get-MetraAzdoApiVersion)"
    $headers = Get-MetraAzdoAuthHeader -MetraRoot $MetraRoot
    $headers['Content-Type'] = 'application/json'

    if ($Method -eq 'Post') {
        $json = if ($null -eq $Body) { '{}' } else { ($Body | ConvertTo-Json -Depth 12 -Compress) }
        return Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $json -TimeoutSec $TimeoutSec
    }
    return Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec $TimeoutSec
}

function Invoke-MetraAzdoTruncateText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$MaxChars
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if ($Text.Length -le $MaxChars) { return $Text }
    if ($MaxChars -le 40) { return $Text.Substring(0, $MaxChars) }
    return ($Text.Substring(0, $MaxChars - 37) + '... [truncated by maxFileChars cap]')
}

function Get-MetraAzdoStatus {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $cfg = Get-MetraAzdoConfig -MetraRoot $MetraRoot
    $patFromEnv = $null -ne (Get-MetraAzdoPatFromEnvironment)
    $patPresent = Test-MetraAzdoAuthenticated -MetraRoot $MetraRoot
    $orgConfigured = -not [string]::IsNullOrWhiteSpace([string]$cfg.organization)

    return [PSCustomObject]@{
        authenticated  = [bool]$patPresent
        patFromEnv     = [bool]$patFromEnv
        organization   = [string]$cfg.organization
        projectFilter  = [string]$cfg.project
        orgConfigured  = [bool]$orgConfigured
        configPath     = Get-MetraAzdoConfigPath -MetraRoot $MetraRoot
        configExists   = (Test-Path -LiteralPath (Get-MetraAzdoConfigPath -MetraRoot $MetraRoot))
        cacheDir       = Get-MetraAzdoCacheDir
        apiVersion     = Get-MetraAzdoApiVersion
        ready          = ($patPresent -and $orgConfigured)
        exampleConfig  = 'docs/examples/azdo.local.example.json'
    }
}

function Get-MetraAzdoRepoRecords {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [object[]]$Repos = $null
    )

    if ($null -ne $Repos) {
        return @($Repos)
    }

    $cfg = Get-MetraAzdoConfig -MetraRoot $MetraRoot
    $max = [int]$cfg.maxRepos
    $project = [string]$cfg.project
    $records = [System.Collections.Generic.List[object]]::new()

    if (-not [string]::IsNullOrWhiteSpace($project)) {
        $resp = Invoke-MetraAzdoRest -Path "$project/_apis/git/repositories" -MetraRoot $MetraRoot
        foreach ($r in @($resp.value)) {
            [void]$records.Add($r)
            if ($records.Count -ge $max) { break }
        }
    }
    else {
        $projects = Invoke-MetraAzdoRest -Path '_apis/projects?%24top=200&stateFilter=WellFormed' -MetraRoot $MetraRoot
        foreach ($p in @($projects.value)) {
            $pName = [string]$p.name
            if ([string]::IsNullOrWhiteSpace($pName)) { continue }
            try {
                $resp = Invoke-MetraAzdoRest -Path "$pName/_apis/git/repositories" -MetraRoot $MetraRoot
                foreach ($r in @($resp.value)) {
                    [void]$records.Add($r)
                    if ($records.Count -ge $max) { break }
                }
            }
            catch {
                # Skip projects without git.
            }
            if ($records.Count -ge $max) { break }
        }
    }

    return @($records | Select-Object -First $max)
}

function Test-MetraAzdoExactTargetName {
    <#
    .SYNOPSIS
        Reject wildcard-like project/repo tokens for direct REST resolve (exact match only).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][string]$Kind
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "$Kind name is required for exact Azure DevOps target resolution."
    }
    if ($Name -match '[\*\?\[\]]') {
        throw "$Kind name must be exact (no wildcards): $Name"
    }
    return $true
}

function Test-MetraAzdoResolvedRepoIdentity {
    <#
    .SYNOPSIS
        Fail closed when REST (or inventory) repo object does not match requested project/repo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Repo,
        [Parameter(Mandatory)][string]$ExpectedProject,
        [Parameter(Mandatory)][string]$ExpectedRepo
    )

    $ident = Get-MetraAzdoRepoIdentity -Repo $Repo
    if ($ident.Project -cne $ExpectedProject -or $ident.Name -cne $ExpectedRepo) {
        throw "Repository identity mismatch: expected $ExpectedProject/$ExpectedRepo, got $($ident.Project)/$($ident.Name)"
    }
    return $true
}

function Resolve-MetraAzdoRepository {
    <#
    .SYNOPSIS
        Resolve a git repo by project + name. Uses bounded inventory when present, else direct REST.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Repo,
        [string]$MetraRoot = (Get-MetraRoot),
        [object[]]$Inventory = $null
    )

    Test-MetraAzdoExactTargetName -Name $Project -Kind 'Project' | Out-Null
    Test-MetraAzdoExactTargetName -Name $Repo -Kind 'Repository' | Out-Null

    if ($null -eq $Inventory) {
        $Inventory = Get-MetraAzdoRepoRecords -MetraRoot $MetraRoot
    }

    $repoRow = @($Inventory | Where-Object {
            $ident = Get-MetraAzdoRepoIdentity -Repo $_
            $ident.Project -ieq $Project -and $ident.Name -ieq $Repo
        } | Select-Object -First 1)
    if ($repoRow.Count -gt 0) {
        Test-MetraAzdoResolvedRepoIdentity -Repo $repoRow[0] -ExpectedProject $Project -ExpectedRepo $Repo | Out-Null
        return $repoRow[0]
    }

    $encodedProject = [uri]::EscapeDataString($Project)
    $encodedRepo = [uri]::EscapeDataString($Repo)
    try {
        $resolved = Invoke-MetraAzdoRest -Path "$encodedProject/_apis/git/repositories/$encodedRepo" -MetraRoot $MetraRoot
        Test-MetraAzdoResolvedRepoIdentity -Repo $resolved -ExpectedProject $Project -ExpectedRepo $Repo | Out-Null
        return $resolved
    }
    catch {
        if ($_.Exception.Message -match 'identity mismatch') {
            throw
        }
        throw "Repository not found: $Project/$Repo"
    }
}

function Get-MetraAzdoRepoDefaultBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Repo,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $branch = [string](Get-MetraProp -Object $Repo -Name 'defaultBranch' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($branch)) {
        return $branch
    }

    $project = [string](Get-MetraProp -Object $Repo -Name 'project' -Default '')
    if ($project -is [PSCustomObject]) {
        $project = [string](Get-MetraProp -Object $project -Name 'name' -Default '')
    }
    $repoId = [string](Get-MetraProp -Object $Repo -Name 'id' -Default '')
    $repoName = [string](Get-MetraProp -Object $Repo -Name 'name' -Default '')
    if ([string]::IsNullOrWhiteSpace($project) -or [string]::IsNullOrWhiteSpace($repoId)) {
        throw 'Cannot resolve default branch without repo project/id.'
    }

    $detail = Invoke-MetraAzdoRest -Path "$project/_apis/git/repositories/$repoId" -MetraRoot $MetraRoot
    return [string](Get-MetraProp -Object $detail -Name 'defaultBranch' -Default '')
}

function Get-MetraAzdoRepoTipCommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Repo,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $project = [string](Get-MetraProp -Object $Repo -Name 'project' -Default '')
    if ($project -is [PSCustomObject]) {
        $project = [string](Get-MetraProp -Object $project -Name 'name' -Default '')
    }
    $repoId = [string](Get-MetraProp -Object $Repo -Name 'id' -Default '')
    $branch = Get-MetraAzdoRepoDefaultBranch -Repo $Repo -MetraRoot $MetraRoot
    if ([string]::IsNullOrWhiteSpace($branch)) { return $null }

    $refPath = if ($branch -like 'refs/*') { $branch } else { "refs/heads/$branch" }
    $resp = Invoke-MetraAzdoRest -Path "$project/_apis/git/repositories/$repoId/refs?filter=$([uri]::EscapeDataString($refPath))&%24top=1" -MetraRoot $MetraRoot
    $ref = @($resp.value | Select-Object -First 1)
    if ($ref.Count -eq 0) { return $null }
    return [string](Get-MetraProp -Object $ref[0] -Name 'objectId' -Default '')
}

function Get-MetraLocalGitHead {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $gitDir = Join-Path $Path '.git'
    if (-not (Test-Path -LiteralPath $gitDir)) { return $null }
    try {
        Push-Location -LiteralPath $Path
        $head = git rev-parse HEAD 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return [string]$head.Trim()
    }
    catch {
        return $null
    }
    finally {
        Pop-Location
    }
}

function Get-MetraAzdoRegistryMappings {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $registry = Get-MetraProjectRegistry
    $disk = @{}
    foreach ($d in @(Get-MetraProjects -IncludeNonGit -ErrorAction SilentlyContinue)) {
        $disk[$d.Name.ToLowerInvariant()] = $d
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($reg in @($registry.projects)) {
        $name = [string](Get-MetraProp -Object $reg -Name 'name' -Default '')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $key = $name.ToLowerInvariant()
        $onDisk = $disk.ContainsKey($key)
        $path = if ($onDisk) { [string]$disk[$key].Path } else { $null }
        [void]$rows.Add([PSCustomObject]@{
                RegistryName   = $name
                NormalizedName = Normalize-MetraAzdoName -Name $name
                AzdoProject    = [string](Get-MetraProp -Object $reg -Name 'azdoProject' -Default '')
                AzdoRepo       = [string](Get-MetraProp -Object $reg -Name 'azdoRepo' -Default '')
                RemoteUrl      = [string](Get-MetraProp -Object $reg -Name 'remoteUrl' -Default '')
                CheckoutPath   = $path
                OnDisk         = [bool]$onDisk
            })
    }
    return @($rows)
}

function Get-MetraAzdoRepoIdentity {
    param($Repo)

    $projectRaw = Get-MetraProp -Object $Repo -Name 'project' -Default ''
    if ($projectRaw -is [PSCustomObject]) {
        $project = [string](Get-MetraProp -Object $projectRaw -Name 'name' -Default '')
    }
    else {
        $project = [string]$projectRaw
    }
    return [PSCustomObject]@{
        Id              = [string](Get-MetraProp -Object $Repo -Name 'id' -Default '')
        Name            = [string](Get-MetraProp -Object $Repo -Name 'name' -Default '')
        Project         = $project
        NormalizedName  = Normalize-MetraAzdoName -Name ([string](Get-MetraProp -Object $Repo -Name 'name' -Default ''))
        WebUrl          = [string](Get-MetraProp -Object $Repo -Name 'webUrl' -Default '')
        RemoteUrl       = [string](Get-MetraProp -Object $Repo -Name 'remoteUrl' -Default '')
    }
}

function Resolve-MetraAzdoRepoNameFromRemoteUrl {
    param([string]$RemoteUrl)

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { return $null }
    $m = [regex]::Match($RemoteUrl, '(?i)/_git/([^/?#]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    $m2 = [regex]::Match($RemoteUrl, '(?i)/([^/?#]+?)(?:\.git)?/?$')
    if ($m2.Success) { return $m2.Groups[1].Value }
    return $null
}

function Find-MetraAzdoPlausibleRepos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$QueryName,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Repos,
        [string]$AzdoProject = '',
        [string]$AzdoRepo = '',
        [string]$RemoteUrl = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($AzdoRepo)) {
        $exact = @($Repos | Where-Object {
                [string](Get-MetraProp -Object $_ -Name 'name' -Default '') -ieq $AzdoRepo
            })
        return @($exact)
    }

    if (-not [string]::IsNullOrWhiteSpace($RemoteUrl)) {
        $fromUrl = Resolve-MetraAzdoRepoNameFromRemoteUrl -RemoteUrl $RemoteUrl
        if ($fromUrl) {
            $urlMatch = @($Repos | Where-Object {
                    [string](Get-MetraProp -Object $_ -Name 'name' -Default '') -ieq $fromUrl
                })
            if ($urlMatch.Count -gt 0) { return @($urlMatch) }
        }
    }

    $normQuery = Normalize-MetraAzdoName -Name $QueryName
    if ([string]::IsNullOrWhiteSpace($normQuery)) { return @() }

    $hits = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @($Repos)) {
        $ident = Get-MetraAzdoRepoIdentity -Repo $r
        if (-not [string]::IsNullOrWhiteSpace($AzdoProject) -and $ident.Project -ne $AzdoProject) { continue }
        $normRepo = $ident.NormalizedName
        if ($normRepo -eq $normQuery) {
            [void]$hits.Add($r)
            continue
        }
        if ($normRepo.StartsWith($normQuery) -or $normQuery.StartsWith($normRepo)) {
            [void]$hits.Add($r)
        }
    }
    return @($hits)
}

function Test-MetraAzdoAmbiguousRepoMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$QueryName,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Repos,
        [string]$AzdoProject = '',
        [string]$AzdoRepo = '',
        [string]$RemoteUrl = '',
        [string]$ExplicitRepo = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitRepo) -or -not [string]::IsNullOrWhiteSpace($AzdoRepo)) {
        return $false
    }
    $matches = Find-MetraAzdoPlausibleRepos -QueryName $QueryName -Repos $Repos `
        -AzdoProject $AzdoProject -AzdoRepo $AzdoRepo -RemoteUrl $RemoteUrl
    return (@($matches).Count -gt 1)
}

function Compare-MetraAzdoGaps {
    <#
    .SYNOPSIS
        Pure gap bucket logic for AzDO repos vs registry/disk (testable without live PAT).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$RegistryMappings,
        [Parameter(Mandatory)][object[]]$Repos,
        [switch]$CompareStale,
        [int]$ListLimit = 25
    )

    $repoIdentities = @($Repos | ForEach-Object { Get-MetraAzdoRepoIdentity -Repo $_ })
    $matchedRepoIds = @{}

    $inAzdoNotInRegistryFull = [System.Collections.Generic.List[string]]::new()
    $inRegistryMissingCheckoutFull = [System.Collections.Generic.List[string]]::new()
    $matchedPresentFull = [System.Collections.Generic.List[string]]::new()
    $matchedPossiblyStaleFull = [System.Collections.Generic.List[string]]::new()

    foreach ($map in @($RegistryMappings)) {
        $name = [string]$map.RegistryName
        $plausible = @(Find-MetraAzdoPlausibleRepos -QueryName $name -Repos $Repos `
            -AzdoProject ([string]$map.AzdoProject) -AzdoRepo ([string]$map.AzdoRepo) -RemoteUrl ([string]$map.RemoteUrl))

        if ($plausible.Count -gt 1 -and [string]::IsNullOrWhiteSpace([string]$map.AzdoRepo)) {
            # Ambiguous registry row - still report missing checkout if no disk.
            if (-not [bool]$map.OnDisk) {
                [void]$inRegistryMissingCheckoutFull.Add($name)
            }
            continue
        }

        $repo = @($plausible | Select-Object -First 1)
        if ($repo.Count -eq 0) {
            if (-not [bool]$map.OnDisk) {
                [void]$inRegistryMissingCheckoutFull.Add($name)
            }
            continue
        }

        $ident = Get-MetraAzdoRepoIdentity -Repo $repo[0]
        $matchedRepoIds[$ident.Id] = $true
        $label = "$($ident.Project)/$($ident.Name)"

        if ([bool]$map.OnDisk) {
            [void]$matchedPresentFull.Add("$name -> $label")
            if ($CompareStale) {
                $localHead = Get-MetraLocalGitHead -Path ([string]$map.CheckoutPath)
                $remoteTip = Get-MetraAzdoRepoTipCommit -Repo $repo[0] -ErrorAction SilentlyContinue
                if ($localHead -and $remoteTip -and ($localHead -ne $remoteTip)) {
                    [void]$matchedPossiblyStaleFull.Add("$name -> $label")
                }
            }
        }
        else {
            [void]$inRegistryMissingCheckoutFull.Add("$name (AzDO: $label)")
        }
    }

    foreach ($ident in @($repoIdentities)) {
        if ($matchedRepoIds.ContainsKey($ident.Id)) { continue }
        [void]$inAzdoNotInRegistryFull.Add("$($ident.Project)/$($ident.Name)")
    }

    $cap = {
        param($list)
        @($list | Sort-Object -Unique | Select-Object -First $ListLimit)
    }

    return [PSCustomObject]@{
        InAzdoNotInRegistry         = & $cap $inAzdoNotInRegistryFull
        InAzdoNotInRegistryCount    = $inAzdoNotInRegistryFull.Count
        InRegistryMissingCheckout   = & $cap $inRegistryMissingCheckoutFull
        InRegistryMissingCheckoutCount = $inRegistryMissingCheckoutFull.Count
        MatchedPresent              = & $cap $matchedPresentFull
        MatchedPresentCount         = $matchedPresentFull.Count
        MatchedPossiblyStale        = & $cap $matchedPossiblyStaleFull
        MatchedPossiblyStaleCount   = $matchedPossiblyStaleFull.Count
        GeneratedUtc                = [DateTime]::UtcNow.ToString('o')
    }
}

function Save-MetraAzdoGapSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Summary,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $dir = Get-MetraAzdoCacheDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $path = Join-Path $dir 'gaps-latest.json'
    $tmp = "$path.tmp"
    [System.IO.File]::WriteAllText($tmp, (($Summary | ConvertTo-Json -Depth 8) + "`r`n"))
    Move-Item -LiteralPath $tmp -Destination $path -Force
    return $path
}

function Get-MetraAzdoCoverageAdvisory {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Join-Path (Get-MetraAzdoCacheDir) 'gaps-latest.json'
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{
            available = $false
            line      = 'AzDO gaps: no cached summary. Run .\metra.ps1 azdo gaps after PAT setup.'
        }
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        return [PSCustomObject]@{
            available = $false
            line      = 'AzDO gaps: cached summary unreadable. Re-run .\metra.ps1 azdo gaps.'
        }
    }

    $line = ("AzDO gaps (advisory): {0} in AzDO not in registry; {1} registry missing checkout; {2} matched present; {3} possibly stale." -f `
            [int](Get-MetraProp -Object $raw -Name 'InAzdoNotInRegistryCount' -Default 0), `
            [int](Get-MetraProp -Object $raw -Name 'InRegistryMissingCheckoutCount' -Default 0), `
            [int](Get-MetraProp -Object $raw -Name 'MatchedPresentCount' -Default 0), `
            [int](Get-MetraProp -Object $raw -Name 'MatchedPossiblyStaleCount' -Default 0))
    return [PSCustomObject]@{
        available = $true
        line      = $line
        generatedUtc = [string](Get-MetraProp -Object $raw -Name 'GeneratedUtc' -Default '')
    }
}

function Get-MetraAzdoGaps {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$CompareStale,
        [object[]]$Repos = $null
    )

    if (-not (Test-MetraAzdoAuthenticated -MetraRoot $MetraRoot)) {
        throw 'Azure DevOps not authenticated. Set METRA_AZDO_PAT or %LOCALAPPDATA%/Metra/azdo.local.json.'
    }

    $cfg = Get-MetraAzdoConfig -MetraRoot $MetraRoot
    $repoRows = Get-MetraAzdoRepoRecords -MetraRoot $MetraRoot -Repos $Repos
    $mappings = Get-MetraAzdoRegistryMappings -MetraRoot $MetraRoot
    $summary = Compare-MetraAzdoGaps -RegistryMappings $mappings -Repos $repoRows `
        -CompareStale:$CompareStale -ListLimit ([int]$cfg.gapListLimit)
    $summary | Add-Member -NotePropertyName 'RepoCount' -NotePropertyValue (@($repoRows).Count) -Force
    $summary | Add-Member -NotePropertyName 'RegistryCount' -NotePropertyValue (@($mappings).Count) -Force
    Save-MetraAzdoGapSummary -Summary $summary -MetraRoot $MetraRoot | Out-Null
    return $summary
}

function Get-MetraAzdoFileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Path,
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$Branch = '',
        [ValidateSet('Operator', 'Ask')]
        [string]$Purpose = 'Operator'
    )

    $cfg = Get-MetraAzdoConfig -MetraRoot $MetraRoot
    $maxChars = if ($Purpose -eq 'Ask') { [int]$cfg.maxAskFileChars } else { [int]$cfg.maxFileChars }
    $repoRow = Resolve-MetraAzdoRepository -Project $Project -Repo $Repo -MetraRoot $MetraRoot

    $repoId = [string](Get-MetraProp -Object $repoRow -Name 'id' -Default '')
    if (-not $Branch) {
        $Branch = Get-MetraAzdoRepoDefaultBranch -Repo $repoRow -MetraRoot $MetraRoot
    }
    $versionDescriptor = if ($Branch -like 'refs/*') { $Branch } else { "GB$Branch" }
    $itemPath = if ($Path.StartsWith('/')) { $Path } else { "/$Path" }
    $encodedPath = [uri]::EscapeDataString($itemPath)
    $resp = Invoke-MetraAzdoRest -Path "$Project/_apis/git/repositories/$repoId/items?path=$encodedPath&includeContent=true&versionDescriptor.version=$([uri]::EscapeDataString($versionDescriptor))" -MetraRoot $MetraRoot

    $content = [string](Get-MetraProp -Object $resp -Name 'content' -Default '')
    $truncated = $false
    if ($content.Length -gt $maxChars) {
        $content = Invoke-MetraAzdoTruncateText -Text $content -MaxChars $maxChars
        $truncated = $true
    }

    return [PSCustomObject]@{
        project    = $Project
        repo       = $Repo
        path       = $Path
        branch     = $Branch
        size       = [int](Get-MetraProp -Object $resp -Name 'size' -Default 0)
        truncated  = [bool]$truncated
        maxFileChars = $maxChars
        content    = $content
        source     = 'azure-devops'
    }
}

function Get-MetraAzdoFlattenedTreeItems {
    param(
        $Node,
        [int]$Depth,
        [int]$MaxDepth,
        [System.Collections.Generic.List[object]]$Acc,
        [int]$MaxItems
    )

    if ($null -eq $Node -or $Acc.Count -ge $MaxItems) { return }
    $path = [string](Get-MetraProp -Object $Node -Name 'path' -Default '')
    $isFolder = [bool](Get-MetraProp -Object $Node -Name 'isFolder' -Default $false)
    if ($path) {
        [void]$Acc.Add([PSCustomObject]@{
                path     = $path
                isFolder = $isFolder
                depth    = $Depth
            })
    }
    if ($Depth -ge $MaxDepth) { return }
    foreach ($child in @(Get-MetraProp -Object $Node -Name 'treeEntries' -Default @())) {
        if ($Acc.Count -ge $MaxItems) { break }
        Get-MetraAzdoFlattenedTreeItems -Node $child -Depth ($Depth + 1) -MaxDepth $MaxDepth -Acc $Acc -MaxItems $MaxItems
    }
}

function Get-MetraAzdoRepoTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Repo,
        [string]$Path = '/',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $cfg = Get-MetraAzdoConfig -MetraRoot $MetraRoot
    $maxItems = [int]$cfg.maxTreeItems
    $maxDepth = [int]$cfg.maxTreeDepth

    $repoRow = Resolve-MetraAzdoRepository -Project $Project -Repo $Repo -MetraRoot $MetraRoot

    $repoId = [string](Get-MetraProp -Object $repoRow -Name 'id' -Default '')
    $branch = Get-MetraAzdoRepoDefaultBranch -Repo $repoRow -MetraRoot $MetraRoot
    $versionDescriptor = if ($branch -like 'refs/*') { $branch } else { "GB$branch" }
    $itemPath = if ($Path.StartsWith('/')) { $Path } else { "/$Path" }
    $encodedPath = [uri]::EscapeDataString($itemPath)

    $resp = Invoke-MetraAzdoRest -Path "$Project/_apis/git/repositories/$repoId/items?scopePath=$encodedPath&recursionLevel=Full&versionDescriptor.version=$([uri]::EscapeDataString($versionDescriptor))" -MetraRoot $MetraRoot
    $items = [System.Collections.Generic.List[object]]::new()
    Get-MetraAzdoFlattenedTreeItems -Node $resp -Depth 0 -MaxDepth $maxDepth -Acc $items -MaxItems $maxItems

    if ($items.Count -ge $maxItems) {
        throw "Tree exceeds maxTreeItems cap ($maxItems). Narrow -Path or raise maxTreeItems in %LOCALAPPDATA%/Metra/azdo.local.json."
    }

    return [PSCustomObject]@{
        project      = $Project
        repo         = $Repo
        branch       = $branch
        itemCount    = $items.Count
        maxTreeItems = $maxItems
        truncated    = $false
        items        = @($items)
        source       = 'azure-devops'
    }
}

function Get-MetraAzdoSearchHitName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][ValidateSet('project', 'repository')][string]$Property
    )

    $raw = Get-MetraProp -Object $Object -Name $Property -Default $null
    if ($null -eq $raw) { return '' }
    if ($raw -is [string]) { return [string]$raw }
    $name = [string](Get-MetraProp -Object $raw -Name 'name' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($name)) { return $name }
    return [string]$raw
}

function Search-MetraAzdoCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [string[]]$Projects = @(),
        [string[]]$Repositories = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $cfg = Get-MetraAzdoConfig -MetraRoot $MetraRoot
    $maxHits = [int]$cfg.maxSearchHits
    $org = [string](Get-MetraAzdoConfig -MetraRoot $MetraRoot).organization

    $filters = @{}
    if (@($Projects).Count -gt 0) { $filters['Project'] = @($Projects) }
    if (@($Repositories).Count -gt 0) { $filters['Repository'] = @($Repositories) }

    $body = [ordered]@{
        searchText = $Query
    }
    $body['$top'] = $maxHits
    if ($filters.Count -gt 0) { $body['filters'] = $filters }

    try {
        $resp = Invoke-MetraAzdoRest -Method Post -Path '_apis/search/codesearchresults' -Body $body -MetraRoot $MetraRoot
        $hits = @(
            @($resp.results) | Select-Object -First $maxHits | ForEach-Object {
                $repoName = Get-MetraAzdoSearchHitName -Object $_ -Property 'repository'
                $projName = Get-MetraAzdoSearchHitName -Object $_ -Property 'project'
                [PSCustomObject]@{
                    path       = [string](Get-MetraProp -Object $_ -Name 'path' -Default '')
                    fileName   = [string](Get-MetraProp -Object $_ -Name 'fileName' -Default '')
                    repository = $repoName
                    project    = $projName
                }
            }
        )
        return [PSCustomObject]@{
            searchUsed = $true
            fallback   = $null
            query      = $Query
            hits       = $hits
            hitCount   = $hits.Count
            source     = 'azure-devops'
        }
    }
    catch {
        return [PSCustomObject]@{
            searchUsed = $false
            fallback   = 'items'
            query      = $Query
            hits       = @()
            hitCount   = 0
            source     = 'azure-devops'
            error      = [string]$_.Exception.Message
        }
    }
}

function Get-MetraAzdoIdeaCandidateFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Repo,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $cfg = Get-MetraAzdoConfig -MetraRoot $MetraRoot
    $ident = Get-MetraAzdoRepoIdentity -Repo $Repo
    $patterns = @($cfg.ideaPathPatterns)
    $maxHits = [int]$cfg.maxSearchHits

    $search = Search-MetraAzdoCode -Query 'card OR page OR experience' `
        -Projects @($ident.Project) -Repositories @($ident.Name) -MetraRoot $MetraRoot
    if ($search.searchUsed -and $search.hitCount -gt 0) {
        return [PSCustomObject]@{
            searchUsed = $true
            fallback   = $null
            files      = @($search.hits | Select-Object -First $maxHits)
        }
    }

    $tree = Get-MetraAzdoRepoTree -Project $ident.Project -Repo $ident.Name -Path '/' -MetraRoot $MetraRoot
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($it in @($tree.items)) {
        if ([bool]$it.isFolder) { continue }
        $path = [string]$it.path
        $keep = $false
        foreach ($pat in @($patterns)) {
            $glob = $pat -replace '\*\*/', '' -replace '\*', '.*'
            if ($path -match ("(?i){0}" -f [regex]::Escape($glob).Replace('\\\.\\\*', '.*'))) {
                $keep = $true
                break
            }
            if ($path -match '(?i)(card|page|experience)') { $keep = $true; break }
        }
        if ($keep) {
            [void]$files.Add([PSCustomObject]@{ path = $path; project = $ident.Project; repository = $ident.Name })
        }
        if ($files.Count -ge $maxHits) { break }
    }

    return [PSCustomObject]@{
        searchUsed = $false
        fallback   = 'items'
        files      = @($files)
    }
}

function Test-MetraAskAzdoRemoteGating {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [string]$Where,
        [switch]$Remote,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($Remote) {
        return [PSCustomObject]@{ UseRemote = $true; Reason = 'operator_remote' }
    }

    $hasCheckout = $false
    if (-not [string]::IsNullOrWhiteSpace($Where) -and $Where -ne (Get-MetraHomeDestinationName)) {
        $cwd = Get-MetraAskRouteCwd -Where $Where -MetraRoot $MetraRoot
        $projects = @(Get-MetraProjects -IncludeNonGit -ErrorAction SilentlyContinue)
        $onDisk = @($projects | Where-Object { [string]$_.Name -ieq $Where }).Count -gt 0
        $hasAgents = Test-Path -LiteralPath (Join-Path $cwd 'AGENTS.md')
        $hasCheckout = ($onDisk -and $hasAgents)
    }

    if (-not $hasCheckout) {
        return [PSCustomObject]@{ UseRemote = $true; Reason = 'missing_checkout' }
    }

    if ($Prompt -match '(?i)\b(production|devops|azure devops|experience|latest|remote repo)\b') {
        return [PSCustomObject]@{ UseRemote = $true; Reason = 'prompt_keyword' }
    }

    return [PSCustomObject]@{ UseRemote = $false; Reason = 'local_authoritative' }
}

function Get-MetraAskAzdoEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [string]$Where,
        [string]$ExplicitRepo = '',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if (-not (Test-MetraAzdoAuthenticated -MetraRoot $MetraRoot)) {
        throw 'Azure DevOps evidence unavailable: not authenticated.'
    }

    $registry = Get-MetraProjectRegistry
    $reg = @($registry.projects | Where-Object { [string]$_.name -ieq $Where } | Select-Object -First 1)
    if ($reg.Count -eq 0 -and [string]::IsNullOrWhiteSpace($ExplicitRepo)) {
        return [PSCustomObject]@{ ok = $false; ambiguous = $false; error = 'No routed project for AzDO evidence.'; items = @() }
    }

    $repos = @(Get-MetraAzdoRepoRecords -MetraRoot $MetraRoot)
    $queryName = if ($reg.Count -gt 0) { [string]$reg[0].name } else { $Where }
    $azdoProject = if ($reg.Count -gt 0) { [string](Get-MetraProp -Object $reg[0] -Name 'azdoProject' -Default '') } else { '' }
    $azdoRepo = if ($reg.Count -gt 0) { [string](Get-MetraProp -Object $reg[0] -Name 'azdoRepo' -Default '') } else { '' }
    $remoteUrl = if ($reg.Count -gt 0) { [string](Get-MetraProp -Object $reg[0] -Name 'remoteUrl' -Default '') } else { '' }

    if ([string]::IsNullOrWhiteSpace($ExplicitRepo)) { $ExplicitRepo = $azdoRepo }

    if (Test-MetraAzdoAmbiguousRepoMatch -QueryName $queryName -Repos $repos `
            -AzdoProject $azdoProject -AzdoRepo $azdoRepo -RemoteUrl $remoteUrl -ExplicitRepo $ExplicitRepo) {
        return [PSCustomObject]@{
            ok        = $false
            ambiguous = $true
            error     = 'Ambiguous Azure DevOps target. Use -Repo or refine routing.'
            items     = @()
        }
    }

    $plausible = Find-MetraAzdoPlausibleRepos -QueryName $queryName -Repos $repos `
        -AzdoProject $azdoProject -AzdoRepo $ExplicitRepo -RemoteUrl $remoteUrl

    $repo = $null
    if (@($plausible).Count -gt 0) {
        $repo = $plausible[0]
    }
    elseif (-not [string]::IsNullOrWhiteSpace($azdoProject) -and -not [string]::IsNullOrWhiteSpace($ExplicitRepo)) {
        try {
            $repo = Resolve-MetraAzdoRepository -Project $azdoProject -Repo $ExplicitRepo `
                -MetraRoot $MetraRoot -Inventory $repos
        }
        catch { }
    }

    $limits = Get-MetraAskEvidenceLimits

    if ($null -eq $repo) {
        return [PSCustomObject]@{ ok = $false; ambiguous = $false; error = "No AzDO repo match for $queryName."; items = @() }
    }

    $ident = Get-MetraAzdoRepoIdentity -Repo $repo
    $excerptPaths = @('AGENTS.md', 'README.md')
    $items = [System.Collections.Generic.List[object]]::new()
    $askSearchHits = [int](Get-MetraAzdoConfig -MetraRoot $MetraRoot).maxAskSearchHits

    foreach ($rel in @($excerptPaths)) {
        try {
            $file = Get-MetraAzdoFileContent -Project $ident.Project -Repo $ident.Name -Path $rel `
                -MetraRoot $MetraRoot -Purpose Ask
            if (-not [string]::IsNullOrWhiteSpace($file.content)) {
                [void]$items.Add([PSCustomObject]@{
                        label   = "$($ident.Project)/$($ident.Name):$rel"
                        source  = 'azure-devops'
                        excerpt = Truncate-MetraAskEvidenceText -Text $file.content -Max ([int]$limits.maxCharsPerItem)
                        path    = $rel
                    })
                break
            }
        }
        catch { }
    }

    if ($items.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Prompt)) {
        $searchQuery = $Prompt.Trim()
        if ($searchQuery.Length -gt 200) {
            $searchQuery = $searchQuery.Substring(0, 200)
        }
        $search = Search-MetraAzdoCode -Query $searchQuery `
            -Projects @($ident.Project) -Repositories @($ident.Name) -MetraRoot $MetraRoot
        if ($search.searchUsed -and $search.hitCount -gt 0) {
            foreach ($hit in @($search.hits | Select-Object -First $askSearchHits)) {
                $hitPath = [string]$hit.path
                if ([string]::IsNullOrWhiteSpace($hitPath)) { continue }
                if ([string]$hit.project -and ($hit.project -ne $ident.Project)) { continue }
                if ([string]$hit.repository -and ($hit.repository -ne $ident.Name)) { continue }
                try {
                    $relPath = $hitPath.TrimStart('/')
                    $file = Get-MetraAzdoFileContent -Project $ident.Project -Repo $ident.Name -Path $relPath `
                        -MetraRoot $MetraRoot -Purpose Ask
                    if (-not [string]::IsNullOrWhiteSpace($file.content)) {
                        [void]$items.Add([PSCustomObject]@{
                                label   = "$($ident.Project)/$($ident.Name):$relPath"
                                source  = 'azure-devops-search'
                                excerpt = Truncate-MetraAskEvidenceText -Text $file.content -Max ([int]$limits.maxCharsPerItem)
                                path    = $relPath
                            })
                    }
                }
                catch { }
                if ($items.Count -ge $askSearchHits) { break }
            }
        }
    }

    if ($items.Count -eq 0) {
        return [PSCustomObject]@{
            ok        = $false
            ambiguous = $false
            error     = "AzDO repo $($ident.Project)/$($ident.Name) has no AGENTS.md, README.md, or repo-scoped search excerpt."
            items     = @()
        }
    }

    return [PSCustomObject]@{
        ok        = $true
        ambiguous = $false
        error     = $null
        repo      = $ident
        items     = @($items)
    }
}

function Invoke-MetraAzdoIdeas {
    [CmdletBinding()]
    param(
        [string]$Topic = 'Ellucian Experience card and page ideas',
        [string]$OutFile = '',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if (-not (Test-MetraAzdoAuthenticated -MetraRoot $MetraRoot)) {
        throw 'Azure DevOps not authenticated. Set METRA_AZDO_PAT or %LOCALAPPDATA%/Metra/azdo.local.json.'
    }

    $cfg = Get-MetraAzdoConfig -MetraRoot $MetraRoot
    $repos = Get-MetraAzdoRepoRecords -MetraRoot $MetraRoot
    $patterns = @($cfg.ideaRepoNamePatterns)
    $ideaRepos = @(
        $repos | Where-Object {
            $name = [string](Get-MetraProp -Object $_ -Name 'name' -Default '')
            $matched = $false
            foreach ($pat in @($patterns)) {
                if (Test-MetraAzdoWildcardMatch -Pattern $pat -Value $name) { $matched = $true; break }
            }
            $matched
        }
    )

    if ($ideaRepos.Count -eq 0) {
        throw 'No idea repos matched ideaRepoNamePatterns. Adjust %LOCALAPPDATA%/Metra/azdo.local.json or registry azdoRepo overrides.'
    }

    $evidenceLines = [System.Collections.Generic.List[string]]::new()
    $gatherMeta = [System.Collections.Generic.List[object]]::new()
    foreach ($repo in @($ideaRepos | Select-Object -First 5)) {
        $ident = Get-MetraAzdoRepoIdentity -Repo $repo
        $gather = Get-MetraAzdoIdeaCandidateFiles -Repo $repo -MetraRoot $MetraRoot
        [void]$gatherMeta.Add([PSCustomObject]@{
                repo       = "$($ident.Project)/$($ident.Name)"
                searchUsed = [bool]$gather.searchUsed
                fallback   = [string]$gather.fallback
                fileCount  = @($gather.files).Count
            })
        foreach ($f in @($gather.files | Select-Object -First 5)) {
            $path = [string](Get-MetraProp -Object $f -Name 'path' -Default '')
            if ($path) {
                [void]$evidenceLines.Add("- $($ident.Project)/$($ident.Name):$path")
            }
        }
    }

    $capability = Get-MetraAskCapability -MetraRoot $MetraRoot
    $draft = ''
    if ($capability.available) {
        $prompt = @"
Topic: $Topic

Ground a pasteable coworker draft for Ellucian Experience learning cards/pages.
Use ONLY the evidence paths below. Cite repo/path for each idea. Flat professional coworker voice.
Do not invent features without evidence. If evidence is thin, say so.

Evidence paths:
$($evidenceLines -join "`n")
"@
        $engine = Invoke-MetraAskEngine -Prompt $prompt -Cwd $MetraRoot -MetraRoot $MetraRoot -TimeoutSec 120
        $draft = [string](Get-MetraProp -Object $engine -Name 'message' -Default '')
        if ([string]::IsNullOrWhiteSpace($draft)) {
            $draft = [string](Get-MetraProp -Object $engine -Name 'content' -Default '')
        }
    }
    else {
        $draft = @"
# Experience ideas (degraded - Ask engine unavailable)

Evidence paths only:
$($evidenceLines -join "`n")

Next: run `.\metra.ps1 ask engine show` and retry after engine is available.
"@
    }

    if ($OutFile) {
        $dir = Split-Path -Parent $OutFile
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($OutFile, $draft)
    }

    return [PSCustomObject]@{
        topic      = $Topic
        draft      = $draft
        outFile    = $OutFile
        gather     = @($gatherMeta)
        source     = 'azure-devops'
        degraded   = -not $capability.available
    }
}

function ConvertFrom-MetraAzdoCliArgs {
    [CmdletBinding()]
    param([string[]]$ArgsRest)

    $result = [ordered]@{
        Project      = ''
        Repo         = ''
        Path         = ''
        Query        = ''
        Topic        = ''
        OutFile      = ''
        Json         = $false
        Remote       = $false
        CompareStale = $false
        Positional   = @()
    }

    $i = 0
    while ($i -lt @($ArgsRest).Count) {
        $tok = [string]$ArgsRest[$i]
        switch -Regex ($tok) {
            '^-(?i)Project$' {
                $i++
                if ($i -lt $ArgsRest.Count) { $result.Project = [string]$ArgsRest[$i] }
            }
            '^-(?i)Repo$' {
                $i++
                if ($i -lt $ArgsRest.Count) { $result.Repo = [string]$ArgsRest[$i] }
            }
            '^-(?i)(Path|File|ItemPath|RepoPath)$' {
                $i++
                if ($i -lt $ArgsRest.Count) { $result.Path = [string]$ArgsRest[$i] }
            }
            '^-(?i)Query$' {
                $i++
                if ($i -lt $ArgsRest.Count) { $result.Query = [string]$ArgsRest[$i] }
            }
            '^-(?i)Topic$' {
                $i++
                if ($i -lt $ArgsRest.Count) { $result.Topic = [string]$ArgsRest[$i] }
            }
            '^-(?i)OutFile$' {
                $i++
                if ($i -lt $ArgsRest.Count) { $result.OutFile = [string]$ArgsRest[$i] }
            }
            '^-(?i)(Json|Remote|CompareStale)$' {
                $key = ($Matches[1].Substring(0, 1).ToUpper() + $Matches[1].Substring(1).ToLower())
                $result[$key] = $true
            }
            default {
                if ($tok -notmatch '^-') {
                    [void]$result.Positional.Add($tok)
                }
            }
        }
        $i++
    }

    if ($result.Positional.Count -ge 3 -and -not $result.Project) {
        $result.Project = [string]$result.Positional[0]
        $result.Repo = [string]$result.Positional[1]
        $result.Path = [string]$result.Positional[2]
    }
    elseif ($result.Positional.Count -gt 0 -and -not $result.Query) {
        $result.Query = [string]$result.Positional[0]
    }
    if ($result.Positional.Count -gt 1 -and -not $result.Path -and [string]::IsNullOrWhiteSpace($result.Project)) {
        $result.Path = [string]$result.Positional[1]
    }

    return [PSCustomObject]$result
}

function Invoke-MetraAzdoCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $sub = $Subcommand.ToLowerInvariant()
    $cli = ConvertFrom-MetraAzdoCliArgs -ArgsRest $ArgsRest

    switch ($sub) {
        'status' {
            return Get-MetraAzdoStatus -MetraRoot $MetraRoot
        }
        'repos' {
            if (-not (Test-MetraAzdoAuthenticated -MetraRoot $MetraRoot)) {
                throw 'Azure DevOps not authenticated.'
            }
            $rows = Get-MetraAzdoRepoRecords -MetraRoot $MetraRoot
            return @($rows | ForEach-Object {
                    $ident = Get-MetraAzdoRepoIdentity -Repo $_
                    [PSCustomObject]@{
                        project = $ident.Project
                        name    = $ident.Name
                        id      = $ident.Id
                        webUrl  = $ident.WebUrl
                    }
                })
        }
        'get' {
            if (-not $cli.Project -or -not $cli.Repo -or -not $cli.Path) {
                throw 'azdo get requires -Project, -Repo, and -ItemPath (aliases: -File, -RepoPath). Example: .\metra.ps1 azdo get -Project PowerShell -Repo Colleague -ItemPath README.md'
            }
            Test-MetraAzdoExactTargetName -Name $cli.Project -Kind 'Project' | Out-Null
            Test-MetraAzdoExactTargetName -Name $cli.Repo -Kind 'Repository' | Out-Null
            return Get-MetraAzdoFileContent -Project $cli.Project -Repo $cli.Repo -Path $cli.Path -MetraRoot $MetraRoot
        }
        'gaps' {
            return Get-MetraAzdoGaps -MetraRoot $MetraRoot -CompareStale
        }
        'tree' {
            if (-not $cli.Project -or -not $cli.Repo) {
                throw 'azdo tree requires -Project and -Repo.'
            }
            Test-MetraAzdoExactTargetName -Name $cli.Project -Kind 'Project' | Out-Null
            Test-MetraAzdoExactTargetName -Name $cli.Repo -Kind 'Repository' | Out-Null
            $path = if ($cli.Path) { $cli.Path } else { '/' }
            return Get-MetraAzdoRepoTree -Project $cli.Project -Repo $cli.Repo -Path $path -MetraRoot $MetraRoot
        }
        'search' {
            if (-not $cli.Query) {
                throw 'azdo search requires a query (positional or -Query).'
            }
            $projects = @()
            $repos = @()
            if ($cli.Project) {
                Test-MetraAzdoExactTargetName -Name $cli.Project -Kind 'Project' | Out-Null
                $projects = @($cli.Project)
            }
            if ($cli.Repo) {
                Test-MetraAzdoExactTargetName -Name $cli.Repo -Kind 'Repository' | Out-Null
                $repos = @($cli.Repo)
            }
            return Search-MetraAzdoCode -Query $cli.Query -Projects $projects -Repositories $repos -MetraRoot $MetraRoot
        }
        'ideas' {
            $topic = if ($cli.Topic) { $cli.Topic } else { 'Ellucian Experience card and page ideas' }
            $out = $cli.OutFile
            if (-not $out) {
                $dir = Get-MetraAzdoCacheDir
                if (-not (Test-Path -LiteralPath $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
                $out = Join-Path $dir ("ideas-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
            }
            return Invoke-MetraAzdoIdeas -Topic $topic -OutFile $out -MetraRoot $MetraRoot
        }
        default {
            throw "Unknown azdo subcommand '$Subcommand'. Try: status, repos, get, gaps, tree, search, ideas"
        }
    }
}

function Show-MetraAzdoCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Result,
        [switch]$Json
    )

    if ($Json) {
        $Result | ConvertTo-Json -Depth 10
        return
    }

    if ($Result -is [System.Array]) {
        $Result | Format-Table -AutoSize
        return
    }

    $Result | Format-List
}
