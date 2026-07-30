# Meta.psm1 - helpers for the C:\Projects meta repo

Set-StrictMode -Version Latest

function Get-MetaRoot {
    # Module lives in <meta>/scripts
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-MetaConfig {
    $root = Get-MetaRoot
    $configPath = Join-Path $root 'meta.config.json'
    if (-not (Test-Path $configPath)) {
        throw "Missing config: $configPath"
    }
    return Get-Content -Raw -Path $configPath | ConvertFrom-Json
}

function Get-MetaProp {
    <#
    .SYNOPSIS
        Reads an optional property from a JSON-derived object without tripping StrictMode.
    #>
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop) { return $Default }
    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function Get-MetaRoots {
    <#
    .SYNOPSIS
        Resolves the configured project roots (multi-root aware, env vars expanded).
    .DESCRIPTION
        Reads config.roots when present, else falls back to the legacy single projectsRoot.
        Roots marked optional may be absent (for example a cloud-synced folder that is not
        set up on this machine); they are reported with Exists = $false instead of throwing.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [switch]$IncludeMissing
    )

    $cfg = Get-MetaConfig
    $metaRoot = Get-MetaRoot

    $defs = @(Get-MetaProp -Object $cfg -Name 'roots' -Default @())
    if ($defs.Count -eq 0) {
        $legacy = Get-MetaProp -Object $cfg -Name 'projectsRoot'
        if ($legacy) {
            $defs = @([PSCustomObject]@{ name = 'projects'; path = $legacy; primary = $true })
        }
    }
    if ($defs.Count -eq 0) {
        throw 'meta.config.json defines no project roots (expected a roots array or projectsRoot).'
    }

    $primarySeen = $false
    $results = foreach ($def in $defs) {
        $rootName = [string](Get-MetaProp -Object $def -Name 'name' -Default 'projects')
        $rawPath = [string](Get-MetaProp -Object $def -Name 'path' -Default '..')
        $expanded = [System.Environment]::ExpandEnvironmentVariables($rawPath)
        if (-not [System.IO.Path]::IsPathRooted($expanded)) {
            $expanded = Join-Path $metaRoot $expanded
        }

        $exists = Test-Path -LiteralPath $expanded
        $fullPath = if ($exists) {
            (Resolve-Path -LiteralPath $expanded).Path
        }
        else {
            [System.IO.Path]::GetFullPath($expanded)
        }

        $isPrimary = [bool](Get-MetaProp -Object $def -Name 'primary' -Default $false)
        if ($isPrimary) { $primarySeen = $true }

        [PSCustomObject]@{
            Name      = $rootName
            Path      = $fullPath
            RawPath   = $rawPath
            Primary   = $isPrimary
            Optional  = [bool](Get-MetaProp -Object $def -Name 'optional' -Default $false)
            Cloud     = [bool](Get-MetaProp -Object $def -Name 'cloud' -Default $false)
            ScanDepth = Get-MetaProp -Object $def -Name 'scanDepth'
            Audit     = [string](Get-MetaProp -Object $def -Name 'audit' -Default 'full')
            Registry  = [string](Get-MetaProp -Object $def -Name 'registry' -Default 'shared')
            RegistryFile = [string](Get-MetaProp -Object $def -Name 'registryFile' -Default '')
            Exclude   = @(Get-MetaProp -Object $def -Name 'exclude' -Default @())
            Exists    = $exists
        }
    }

    $results = @($results)
    if (-not $primarySeen -and $results.Count -gt 0) {
        $results[0].Primary = $true
    }

    foreach ($r in $results) {
        if (-not $r.Exists -and -not $r.Optional) {
            throw ("Project root '{0}' not found: {1}" -f $r.Name, $r.Path)
        }
    }

    if ($Name -and $Name.Count -gt 0) {
        $wanted = @($Name | ForEach-Object { $_.ToLowerInvariant() })
        $results = @($results | Where-Object { $wanted -contains $_.Name.ToLowerInvariant() })
        if ($results.Count -eq 0) {
            throw ("No configured root matches: {0}" -f ($Name -join ', '))
        }
    }

    if ($IncludeMissing) { return @($results) }
    return @($results | Where-Object { $_.Exists })
}

function Get-ProjectsRoot {
    <#
    .SYNOPSIS
        Returns the primary project root (creation target and legacy single-root callers).
    #>
    $roots = @(Get-MetaRoots -IncludeMissing)
    $primary = @($roots | Where-Object { $_.Primary }) | Select-Object -First 1
    if (-not $primary) { $primary = $roots[0] }
    return $primary.Path
}

function Test-MetaSelfFolderName {
    <#
    .SYNOPSIS
        True when the folder is this orchestration checkout (Metra product, _meta convention).
    #>
    param([Parameter(Mandatory)][string]$Name)
    $n = $Name.Trim()
    return @('_meta', 'meta', 'Metra', 'metra') -contains $n
}

function Test-ExcludedProjectName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Config,
        $Root
    )

    # Always skip the Metra orchestration folder under any accepted name.
    if (Test-MetaSelfFolderName -Name $Name) { return $true }

    $exclude = @(Get-MetaProp -Object $Config -Name 'exclude' -Default @())
    if ($exclude -contains $Name) { return $true }

    if ($Root) {
        foreach ($rootExclude in @($Root.Exclude)) {
            if ([string]$rootExclude -eq $Name) { return $true }
        }
    }

    foreach ($pattern in @(Get-MetaProp -Object $Config -Name 'excludeNamePatterns' -Default @())) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

function Get-MetaProjects {
    <#
    .SYNOPSIS
        Lists project directories across every configured root.
    .DESCRIPTION
        Roots are scanned in configuration order. When the same folder name appears in more
        than one root, the earlier root wins and the later one is marked Shadowed (surfaced
        only with -IncludeShadowed) so a duplicate never silently replaces the primary copy.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Root,
        [switch]$GitOnly,
        [switch]$IncludeNonGit,
        [switch]$IncludeShadowed
    )

    $cfg = Get-MetaConfig
    $roots = @(Get-MetaRoots -Name $Root)
    $seen = @{}

    $items = foreach ($projectRoot in $roots) {
        Get-ChildItem -Path $projectRoot.Path -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Test-ExcludedProjectName -Name $_.Name -Config $cfg -Root $projectRoot) -and
                ($_.Name -like $Filter)
            } |
            ForEach-Object {
                $isGit = Test-Path (Join-Path $_.FullName '.git')
                if ($GitOnly -and -not $isGit) { return }

                $key = $_.Name.ToLowerInvariant()
                $shadowed = $seen.ContainsKey($key)
                if (-not $shadowed) { $seen[$key] = $projectRoot.Name }
                if ($shadowed -and -not $IncludeShadowed) {
                    Write-Verbose ("Shadowed duplicate ignored: {0} in root '{1}' (already provided by '{2}')" -f $_.Name, $projectRoot.Name, $seen[$key])
                    return
                }

                [PSCustomObject]@{
                    Name     = $_.Name
                    Path     = $_.FullName
                    IsGit    = $isGit
                    Root     = $projectRoot.Name
                    Primary  = $projectRoot.Primary
                    Shadowed = $shadowed
                }
            }
    }

    return @($items | Sort-Object Name, Root)
}

function Resolve-MetaProjectSet {
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$GitOnly
    )

    $projects = Get-MetaProjects -Filter $Filter -Root $Root -GitOnly:$GitOnly
    if ($Name -and $Name.Count -gt 0) {
        $wanted = $Name | ForEach-Object { $_.ToLowerInvariant() }
        $projects = $projects | Where-Object { $wanted -contains $_.Name.ToLowerInvariant() }
    }
    return @($projects)
}

function Invoke-AcrossProjects {
    <#
    .SYNOPSIS
        Runs a script block or shell command in each matching project directory.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Command')]
    param(
        [Parameter(ParameterSetName = 'Command', Mandatory, Position = 0)]
        [string]$Command,

        [Parameter(ParameterSetName = 'Script', Mandatory)]
        [scriptblock]$ScriptBlock,

        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$GitOnly,
        [switch]$ContinueOnError,
        [switch]$Quiet
    )

    $projects = Resolve-MetaProjectSet -Filter $Filter -Name $Name -Root $Root -GitOnly:$GitOnly
    if ($projects.Count -eq 0) {
        Write-Warning 'No matching projects.'
        return @()
    }

    $results = foreach ($project in $projects) {
        if (-not $Quiet) {
            Write-Host ""
            Write-Host ("==== {0} ====" -f $project.Name) -ForegroundColor Cyan
        }

        Push-Location $project.Path
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Script') {
                $output = & $ScriptBlock
                $exit = $LASTEXITCODE
                if ($null -eq $exit) { $exit = 0 }
            }
            else {
                $output = Invoke-Expression $Command 2>&1
                $exit = $LASTEXITCODE
                if ($null -eq $exit) { $exit = 0 }
            }

            if (-not $Quiet -and $null -ne $output) {
                $output | ForEach-Object { Write-Host $_ }
            }

            [PSCustomObject]@{
                Name       = $project.Name
                Path       = $project.Path
                Root       = $project.Root
                ExitCode   = $exit
                Success    = ($exit -eq 0)
                Output     = $output
            }
        }
        catch {
            if (-not $Quiet) {
                Write-Host $_.Exception.Message -ForegroundColor Red
            }
            if (-not $ContinueOnError) { throw }
            [PSCustomObject]@{
                Name       = $project.Name
                Path       = $project.Path
                Root       = $project.Root
                ExitCode   = 1
                Success    = $false
                Output     = $_.Exception.Message
            }
        }
        finally {
            Pop-Location
        }
    }

    return $results
}

function Get-MetaStatus {
    <#
    .SYNOPSIS
        Shows git status --short for each git project.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root
    )

    Invoke-AcrossProjects -Command 'git status -sb' -Filter $Filter -Name $Name -Root $Root -GitOnly -ContinueOnError
}

function Update-MetaProjects {
    <#
    .SYNOPSIS
        Runs git pull --ff-only (or fetch) across git projects.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$FetchOnly
    )

    $cmd = if ($FetchOnly) { 'git fetch --all --prune' } else { 'git pull --ff-only' }
    Invoke-AcrossProjects -Command $cmd -Filter $Filter -Name $Name -Root $Root -GitOnly -ContinueOnError
}

function Copy-AcrossProjects {
    <#
    .SYNOPSIS
        Copies a file into matching projects, preserving relative path under each root.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Source,
        [string]$RelativePath,
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$Force
    )

    $sourcePath = (Resolve-Path $Source).Path
    if (-not $RelativePath) {
        $RelativePath = Split-Path -Leaf $sourcePath
    }

    $projects = Resolve-MetaProjectSet -Filter $Filter -Name $Name -Root $Root
    foreach ($project in $projects) {
        $dest = Join-Path $project.Path $RelativePath
        $destDir = Split-Path -Parent $dest
        if ($PSCmdlet.ShouldProcess($dest, "Copy $sourcePath")) {
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -Path $sourcePath -Destination $dest -Force:$Force
            Write-Host ("Copied -> {0}" -f $dest) -ForegroundColor Green
        }
    }
}

function New-MetaProject {
    <#
    .SYNOPSIS
        Creates a new project folder under the projects root, optionally from a template, and inits git.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Description = '',
        [string]$Template,
        [string]$Root,
        [switch]$NoGit,
        [switch]$Force
    )

    $cfg = Get-MetaConfig
    $metaRoot = Get-MetaRoot

    if ($Root) {
        $targetRoot = @(Get-MetaRoots -Name $Root -IncludeMissing) | Select-Object -First 1
        if (-not $targetRoot.Exists) {
            throw ("Root '{0}' is not available on this machine: {1}" -f $targetRoot.Name, $targetRoot.Path)
        }
        $projectsRoot = $targetRoot.Path
    }
    else {
        $projectsRoot = Get-ProjectsRoot
    }

    if ($Name -match '[\\/:*?"<>|]') {
        throw "Invalid project name: $Name"
    }

    $target = Join-Path $projectsRoot $Name
    if ((Test-Path $target) -and -not $Force) {
        throw "Project already exists: $target (use -Force to reuse)"
    }

    if (-not (Test-Path $target)) {
        New-Item -ItemType Directory -Path $target | Out-Null
    }

    $templateName = if ($Template) { $Template } else { $cfg.defaultTemplate }
    $templateDir = Join-Path $metaRoot (Join-Path $cfg.templatesDir $templateName)

    $descLine = if ($Description) { $Description } else { "Project $Name" }

    if (Test-Path $templateDir) {
        Copy-Item -Path (Join-Path $templateDir '*') -Destination $target -Recurse -Force
        Get-ChildItem -Path $target -Recurse -File | ForEach-Object {
            $text = Get-Content -Raw -Path $_.FullName -ErrorAction SilentlyContinue
            if ($null -eq $text) { return }
            if ($text -notmatch '\{\{ProjectName\}\}|\{\{Description\}\}') { return }
            $updated = $text.
                Replace('{{ProjectName}}', $Name).
                Replace('{{Description}}', $descLine)
            Set-Content -Path $_.FullName -Value $updated -Encoding UTF8 -NoNewline
        }
    }
    else {
        Write-Warning "Template not found: $templateDir (creating empty project)"
    }

    $readme = Join-Path $target 'README.md'
    if (-not (Test-Path $readme)) {
        @"
# $Name

$descLine
"@ | Set-Content -Path $readme -Encoding UTF8
    }

    if (-not $NoGit) {
        if (-not (Test-Path (Join-Path $target '.git'))) {
            Push-Location $target
            try {
                git init | Out-Null
                git add .
                $msg = "Initial commit for $Name"
                git commit -m $msg 2>$null | Out-Null
            }
            finally {
                Pop-Location
            }
        }
    }

    Write-Host ("Created project: {0}" -f $target) -ForegroundColor Green
    return [PSCustomObject]@{
        Name = $Name
        Path = $target
        Root = if ($Root) { $Root } else { 'primary' }
        Template = $templateName
        IsGit = (Test-Path (Join-Path $target '.git'))
    }
}

function Get-ProjectLastActivity {
    <#
    .SYNOPSIS
        Estimates last activity for a project folder using directory time, git metadata, and a shallow file scan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$ScanDepth = 2
    )

    $timestamps = [System.Collections.Generic.List[datetime]]::new()
    $item = Get-Item -LiteralPath $Path -Force
    $timestamps.Add($item.LastWriteTime)

    foreach ($rel in @('.git\HEAD', '.git\FETCH_HEAD', '.git\COMMIT_EDITMSG', '.git\logs\HEAD', '.git\index')) {
        $gitPath = Join-Path $Path $rel
        if (Test-Path -LiteralPath $gitPath) {
            $timestamps.Add((Get-Item -LiteralPath $gitPath -Force).LastWriteTime)
        }
    }

    if ($ScanDepth -ge 0) {
        Get-ChildItem -LiteralPath $Path -Recurse -File -Force -Depth $ScanDepth -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' } |
            ForEach-Object { $timestamps.Add($_.LastWriteTime) }
    }

    return ($timestamps | Measure-Object -Maximum).Maximum
}

function Get-RecentMetaProjects {
    <#
    .SYNOPSIS
        Returns sibling projects with activity within the lookback window (default from config: 6 months).
    #>
    [CmdletBinding()]
    param(
        [int]$Months,
        [int]$ScanDepth,
        [switch]$IncludeAlways
    )

    $cfg = Get-MetaConfig
    $ws = Get-MetaProp -Object $cfg -Name 'workspace'
    if (-not $PSBoundParameters.ContainsKey('Months')) {
        $Months = [int](Get-MetaProp -Object $ws -Name 'months' -Default 6)
    }
    if (-not $PSBoundParameters.ContainsKey('ScanDepth')) {
        $ScanDepth = [int](Get-MetaProp -Object $ws -Name 'scanDepth' -Default 2)
    }

    $cutoff = (Get-Date).AddMonths(-1 * $Months)
    $always = @(Get-MetaProp -Object $ws -Name 'alwaysInclude' -Default @())

    $rootDepths = @{}
    foreach ($r in @(Get-MetaRoots)) {
        $rootDepths[$r.Name] = if ($null -ne $r.ScanDepth) { [int]$r.ScanDepth } else { $ScanDepth }
    }

    $projects = Get-MetaProjects | ForEach-Object {
        $depth = if ($rootDepths.ContainsKey($_.Root)) { $rootDepths[$_.Root] } else { $ScanDepth }
        $last = Get-ProjectLastActivity -Path $_.Path -ScanDepth $depth
        $forced = $always -contains $_.Name
        [PSCustomObject]@{
            Name         = $_.Name
            Path         = $_.Path
            Root         = $_.Root
            IsGit        = $_.IsGit
            LastActivity = $last
            Recent       = ($last -ge $cutoff) -or $forced
            Always       = $forced
            Cutoff       = $cutoff
        }
    }

    if ($IncludeAlways) {
        return @($projects | Sort-Object LastActivity -Descending)
    }
    return @($projects | Where-Object Recent | Sort-Object Name)
}

function Update-MetaWorkspace {
    <#
    .SYNOPSIS
        Rebuilds Metra.code-workspace file(s) with Metra plus projects active in the lookback window.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [int]$Months,
        [int]$ScanDepth,
        [switch]$WhatIfPreview
    )

    $cfg = Get-MetaConfig
    $metaRoot = Get-MetaRoot
    $ws = $cfg.workspace
    if (-not $ws) {
        throw 'meta.config.json is missing a workspace section.'
    }

    if (-not $PSBoundParameters.ContainsKey('Months')) {
        $Months = [int]$ws.months
    }
    if (-not $PSBoundParameters.ContainsKey('ScanDepth')) {
        $ScanDepth = [int]$ws.scanDepth
    }

    $recent = Get-RecentMetaProjects -Months $Months -ScanDepth $ScanDepth
    $outputs = @(Get-MetaProp -Object $ws -Name 'outputs' -Default @())
    if ($outputs.Count -eq 0) {
        throw 'workspace.outputs is empty in meta.config.json.'
    }

    $primaryRootName = (@(Get-MetaRoots -IncludeMissing) | Where-Object { $_.Primary } | Select-Object -First 1).Name

    Write-Host ("Lookback: {0} month(s) | {1} project(s) (+ Metra)" -f $Months, $recent.Count) -ForegroundColor Cyan
    $recent | ForEach-Object {
        Write-Host ("  {0,-24} {1,-10} {2:yyyy-MM-dd}" -f $_.Name, $_.Root, $_.LastActivity)
    }

    $written = @()
    foreach ($out in $outputs) {
        $outPath = Join-Path $metaRoot $out.path
        $prefix = [string]$out.projectPathPrefix
        $folderLabel = [string](Get-MetaProp -Object $out -Name 'metaFolderName' -Default 'Metra')
        if ([string]::IsNullOrWhiteSpace($folderLabel)) { $folderLabel = 'Metra' }
        $folders = @(
            [ordered]@{
                name = $folderLabel
                path = [string]$out.metaFolderPath
            }
        )
        foreach ($project in $recent) {
            # Projects outside the primary root cannot be reached by the relative prefix.
            $folderPath = if ($project.Root -eq $primaryRootName) {
                $prefix + $project.Name
            }
            else {
                $project.Path
            }
            $folders += [ordered]@{
                name = $project.Name
                path = $folderPath
            }
        }

        $doc = [ordered]@{
            folders    = $folders
            settings   = $ws.settings
            extensions = $ws.extensions
        }

        $json = $doc | ConvertTo-Json -Depth 8
        # ConvertTo-Json can emit awkward escaping; normalize to UTF8 workspace JSON
        if ($WhatIfPreview -or $PSCmdlet.ShouldProcess($outPath, 'Write workspace')) {
            if ($WhatIfPreview) {
                Write-Host ("Would write: {0}" -f $outPath) -ForegroundColor Yellow
            }
            else {
                $dir = Split-Path -Parent $outPath
                if ($dir -and -not (Test-Path $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
                [System.IO.File]::WriteAllText($outPath, $json + "`r`n")
                Write-Host ("Wrote {0}" -f $outPath) -ForegroundColor Green
                $written += $outPath
            }
        }
    }

    return [PSCustomObject]@{
        Months       = $Months
        ProjectCount = $recent.Count
        Projects     = @($recent.Name)
        Files        = $written
    }
}

function Read-MetaRegistryFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $doc = Get-Content -Raw -Path $Path | ConvertFrom-Json
    foreach ($p in @(Get-MetaProp -Object $doc -Name 'projects' -Default @())) {
        $p | Add-Member -NotePropertyName 'source' -NotePropertyValue $Source -Force
    }
    return $doc
}

function Get-MetaProjectRegistry {
    <#
    .SYNOPSIS
        Loads the agent routing registry: shared projects.json plus optional projects.local.json.
    .DESCRIPTION
        projects.json is the git-tracked, shareable subset. projects.local.json is machine or
        person specific (personal folders, private work entries) and is not committed. Local
        entries with the same name replace the shared entry, so a coworker clone never sees
        them. Use -SharedOnly to inspect exactly what ships to others.
    #>
    [CmdletBinding()]
    param(
        [switch]$SharedOnly
    )

    $metaRoot = Get-MetaRoot
    $sharedPath = Join-Path $metaRoot 'projects.json'
    $localPath = Join-Path $metaRoot 'projects.local.json'

    $shared = Read-MetaRegistryFile -Path $sharedPath -Source 'shared'
    if (-not $shared) {
        throw "Missing project registry: $sharedPath"
    }

    $projects = [System.Collections.Generic.List[object]]::new()
    $index = @{}
    foreach ($p in @(Get-MetaProp -Object $shared -Name 'projects' -Default @())) {
        $key = ([string]$p.name).ToLowerInvariant()
        $index[$key] = $projects.Count
        [void]$projects.Add($p)
    }

    $routing = Get-MetaProp -Object $shared -Name 'routing'
    $localLoaded = $false
    $extraSources = @()

    if (-not $SharedOnly) {
        # A root may carry its own registry file so entries travel with the folder itself
        # (for example a cloud-synced personal root that reaches a second machine).
        foreach ($projectRoot in @(Get-MetaRoots)) {
            if (-not $projectRoot.RegistryFile) { continue }
            $rootRegistryPath = [System.Environment]::ExpandEnvironmentVariables($projectRoot.RegistryFile)
            if (-not [System.IO.Path]::IsPathRooted($rootRegistryPath)) {
                $rootRegistryPath = Join-Path $projectRoot.Path $rootRegistryPath
            }
            $rootRegistry = Read-MetaRegistryFile -Path $rootRegistryPath -Source $projectRoot.Name
            if (-not $rootRegistry) { continue }
            $extraSources += $rootRegistryPath
            foreach ($p in @(Get-MetaProp -Object $rootRegistry -Name 'projects' -Default @())) {
                $key = ([string]$p.name).ToLowerInvariant()
                if (-not (Get-MetaProp -Object $p -Name 'root')) {
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

        $local = Read-MetaRegistryFile -Path $localPath -Source 'local'
        if ($local) {
            $localLoaded = $true
            foreach ($p in @(Get-MetaProp -Object $local -Name 'projects' -Default @())) {
                $key = ([string]$p.name).ToLowerInvariant()
                if ($index.ContainsKey($key)) {
                    $projects[$index[$key]] = $p
                }
                else {
                    $index[$key] = $projects.Count
                    [void]$projects.Add($p)
                }
            }
            $localRouting = Get-MetaProp -Object $local -Name 'routing'
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

    return [PSCustomObject]@{
        version      = Get-MetaProp -Object $shared -Name 'version' -Default 1
        updated      = Get-MetaProp -Object $shared -Name 'updated' -Default ''
        routing      = $routing
        projects     = @($projects.ToArray())
        sharedPath   = $sharedPath
        localPath    = $localPath
        localLoaded  = $localLoaded
        rootRegistry = @($extraSources)
    }
}

function Get-MetaRoutingTable {
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
    param(
        [string[]]$Name,
        [switch]$SharedOnly,
        [switch]$MissingOnly
    )

    $registry = Get-MetaProjectRegistry -SharedOnly:$SharedOnly
    $disk = @{}
    foreach ($p in @(Get-MetaProjects)) {
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

        $optional = [bool](Get-MetaProp -Object $reg -Name 'optional' -Default $false)
        $advice = if ($present) {
            [string](Get-MetaProp -Object $reg -Name 'whenPresent' -Default '')
        }
        else {
            [string](Get-MetaProp -Object $reg -Name 'whenMissing' -Default '')
        }
        if (-not $advice -and -not $present) {
            $advice = "Not on this machine. Ask the user for the details this project would have provided; do not invent them."
        }

        [PSCustomObject]@{
            Name         = $regName
            Source       = [string](Get-MetaProp -Object $reg -Name 'source' -Default 'shared')
            Root         = if ($present) { [string]$onDisk.Root } else { '' }
            Present      = $present
            Optional     = $optional
            Entry        = [string](Get-MetaProp -Object $reg -Name 'entry' -Default 'AGENTS.md')
            Capabilities = @(Get-MetaProp -Object $reg -Name 'capabilities' -Default @())
            Triggers     = @(Get-MetaProp -Object $reg -Name 'triggers' -Default @())
            Advice       = $advice
            Path         = if ($present) { [string]$onDisk.Path } else { '' }
        }
    }

    return @($rows | Sort-Object @{ Expression = 'Present'; Descending = $true }, Name)
}

function Get-MetaRegistryProject {
    param(
        [Parameter(Mandatory)]$Registry,
        [Parameter(Mandatory)][string]$Name
    )

    @($Registry.projects) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Test-MetaPathExists {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Relative
    )

    $full = Join-Path $Root ($Relative -replace '/', '\')
    return (Test-Path -LiteralPath $full)
}

function Get-MetaGeneratedPathHints {
    return @(
        'node_modules',
        'browser\node_modules',
        'inventory',
        'artifacts',
        'catalog\index.json',
        'catalog\index.yaml',
        'data',
        'bin',
        'obj',
        'tests\results',
        'runtime\assemblies',
        '.vs',
        'packages'
    )
}

function Invoke-MetaProjectContextAudit {
    <#
    .SYNOPSIS
        Read-only context audit for one or more projects; optional drift check against projects.json.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$DriftOnly,
        [switch]$Quiet,
        [int]$LargeFileBytes = 200KB,
        [int]$HighCardinalityCount = 200,
        [int]$ScanDepth = 4
    )

    $registry = Get-MetaProjectRegistry
    $projects = @(Resolve-MetaProjectSet -Filter $Filter -Name $Name -Root $Root)
    $generatedHints = Get-MetaGeneratedPathHints
    $driftCount = 0
    $reports = @()

    $rootInfo = @{}
    foreach ($r in @(Get-MetaRoots -IncludeMissing)) {
        $rootInfo[$r.Name] = $r
    }

    function Write-AuditHost {
        param(
            [AllowEmptyString()][string]$Message = '',
            [ConsoleColor]$ForegroundColor
        )
        if ($Quiet) { return }
        if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
            Write-Host $Message -ForegroundColor $ForegroundColor
        }
        else {
            Write-Host $Message
        }
    }

    # Registry entries with no matching disk project
    $diskNameSet = @{}
    foreach ($p in $projects) {
        $diskNameSet[$p.Name.ToLowerInvariant()] = $true
    }
    foreach ($reg in @($registry.projects)) {
        $key = [string]$reg.name
        if (-not $diskNameSet.ContainsKey($key.ToLowerInvariant())) {
            if (-not $Name -or (@($Name) -contains $reg.name)) {
                if ([bool](Get-MetaProp -Object $reg -Name 'optional' -Default $false)) {
                    Write-AuditHost ("optional: {0} not installed here (advice-only routing)" -f $reg.name)
                }
                else {
                    $driftCount++
                    Write-AuditHost ("DRIFT: registry project missing on disk: {0}" -f $reg.name) -ForegroundColor Yellow
                }
            }
        }
    }

    foreach ($project in $projects) {
        $reg = Get-MetaRegistryProject -Registry $registry -Name $project.Name
        $inRegistry = $null -ne $reg
        $findings = @()
        $advisories = @()
        $largeFiles = @()
        $highCard = @()
        $generatedHits = @()

        $projectRoot = if ($rootInfo.ContainsKey($project.Root)) { $rootInfo[$project.Root] } else { $null }
        # Light roots (cloud-synced personal folders) get metadata checks only: a deep recursive
        # scan would hydrate placeholder files just to measure them.
        $lightAudit = $null -ne $projectRoot -and ($projectRoot.Audit -eq 'light')

        $hasAgents = Test-Path -LiteralPath (Join-Path $project.Path 'AGENTS.md')
        $hasIgnore = Test-Path -LiteralPath (Join-Path $project.Path '.cursorignore')
        $hasReadme = Test-Path -LiteralPath (Join-Path $project.Path 'README.md')

        if (-not $inRegistry) {
            $findings += 'Missing from registry (projects.json or projects.local.json)'
            $driftCount++
        }
        else {
            if (-not $hasAgents -and [string]$reg.entry -eq 'AGENTS.md') {
                $findings += 'Registry entry expects AGENTS.md but file is missing'
                $driftCount++
            }
            foreach ($ex in @($reg.excludePaths)) {
                if ([string]::IsNullOrWhiteSpace([string]$ex)) { continue }
                if ((Test-MetaPathExists -Root $project.Path -Relative ([string]$ex)) -and -not $hasIgnore) {
                    if ($lightAudit) {
                        $advisories += "excludePath '$ex' exists but .cursorignore is missing"
                    }
                    else {
                        $findings += "excludePath '$ex' exists but .cursorignore is missing"
                        $driftCount++
                    }
                    break
                }
            }
            foreach ($pref in @($reg.preferredPaths)) {
                if ([string]::IsNullOrWhiteSpace([string]$pref)) { continue }
                if ($pref -eq 'AGENTS.md' -or $pref -eq 'README.md') { continue }
                if (-not (Test-MetaPathExists -Root $project.Path -Relative ([string]$pref))) {
                    $findings += "preferredPath missing: $pref"
                }
            }
        }

        if (-not $lightAudit) {
            if (-not $hasAgents) {
                $findings += 'Missing AGENTS.md'
                if ($inRegistry) { $driftCount++ }
            }
            if (-not $hasIgnore) {
                $findings += 'Missing .cursorignore'
            }
            if (-not $hasReadme) {
                $findings += 'Missing README.md'
            }
        }

        foreach ($hint in $generatedHints) {
            $hintPath = Join-Path $project.Path $hint
            if (Test-Path -LiteralPath $hintPath) {
                $generatedHits += $hint
                $covered = $false
                if ($inRegistry) {
                    foreach ($ex in @($reg.excludePaths)) {
                        $exNorm = ([string]$ex) -replace '/', '\'
                        if ([string]::IsNullOrWhiteSpace($exNorm)) { continue }
                        if ($hint -like $exNorm -or $exNorm -like $hint -or $hint.StartsWith($exNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $covered = $true
                            break
                        }
                    }
                }
                if ($hasIgnore) {
                    $ignoreText = [string](Get-Content -Raw -Path (Join-Path $project.Path '.cursorignore') -ErrorAction SilentlyContinue)
                    $hintSlash = $hint -replace '\\', '/'
                    if ($ignoreText -and (
                            $ignoreText.IndexOf($hint, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                            $ignoreText.IndexOf($hintSlash, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                            ($hint -match 'node_modules' -and $ignoreText -match 'node_modules') -or
                            ($hint -match '^inventory' -and $ignoreText -match 'inventory') -or
                            ($hint -match '^artifacts' -and $ignoreText -match 'artifacts') -or
                            ($hint -match '^data$' -and $ignoreText -match '(?m)^data') -or
                            ($hint -match 'assemblies' -and $ignoreText -match 'assemblies') -or
                            ($hint -match 'index\.json' -and $ignoreText -match 'index\.json') -or
                            ($hint -match 'index\.yaml' -and $ignoreText -match 'index\.yaml') -or
                            ($hint -match 'tests\\results' -and $ignoreText -match 'tests/results|tests\\results') -or
                            ($hint -eq 'runtime\assemblies' -and $ignoreText -match 'runtime')
                        )) {
                        $covered = $true
                    }
                }
                if (-not $covered -and ($hint -notin @('bin', 'obj'))) {
                    if ($lightAudit) {
                        $advisories += "Generated/cache path not covered by registry exclude or .cursorignore: $hint"
                    }
                    else {
                        $findings += "Generated/cache path not covered by registry exclude or .cursorignore: $hint"
                        $driftCount++
                    }
                }
            }
        }

        $largeFileList = New-Object System.Collections.ArrayList
        $highCardList = New-Object System.Collections.ArrayList

        if (-not $lightAudit) {
            $null = Get-ChildItem -LiteralPath $project.Path -Recurse -File -Force -Depth $ScanDepth -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.FullName -notmatch '[\\/]\.git([\\/]|$)' -and
                    $_.FullName -notmatch '[\\/]node_modules([\\/]|$)' -and
                    $_.Length -ge $LargeFileBytes
                } |
                Sort-Object Length -Descending |
                Select-Object -First 15 |
                ForEach-Object {
                    $rel = $_.FullName.Substring($project.Path.Length).TrimStart('\')
                    [void]$largeFileList.Add([PSCustomObject]@{
                        Path = $rel
                        KB   = [math]::Round($_.Length / 1KB, 1)
                    })
                }

            $null = Get-ChildItem -LiteralPath $project.Path -Recurse -Directory -Force -Depth ([Math]::Max(1, $ScanDepth - 1)) -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.FullName -notmatch '[\\/]\.git([\\/]|$)' -and
                    $_.FullName -notmatch '[\\/]node_modules([\\/]|$)'
                } |
                ForEach-Object {
                    $fileCount = @(Get-ChildItem -LiteralPath $_.FullName -File -Force -ErrorAction SilentlyContinue).Count
                    if ($fileCount -ge $HighCardinalityCount) {
                        $rel = $_.FullName.Substring($project.Path.Length).TrimStart('\')
                        [void]$highCardList.Add([PSCustomObject]@{ Path = $rel; FileCount = $fileCount })
                    }
                }
        }

        $largeFiles = @($largeFileList.ToArray())
        $highCard = @($highCardList.ToArray())

        $suggestedTriggers = @()
        if ($hasReadme) {
            $readmeText = Get-Content -Raw -Path (Join-Path $project.Path 'README.md') -ErrorAction SilentlyContinue
            if ($readmeText) {
                $suggestedTriggers = @(
                    [regex]::Matches([string]$readmeText.ToLowerInvariant(), '[a-z][a-z0-9_-]{3,}') |
                        ForEach-Object { $_.Value } |
                        Where-Object { $_ -notin @('this','that','with','from','have','project','readme','table','contents') } |
                        Group-Object |
                        Sort-Object Count -Descending |
                        Select-Object -First 8 -ExpandProperty Name
                )
            }
        }

        $report = [PSCustomObject]@{
            Name              = $project.Name
            Path              = $project.Path
            Root              = $project.Root
            LightAudit        = $lightAudit
            RegistrySource    = if ($inRegistry) { [string](Get-MetaProp -Object $reg -Name 'source' -Default 'shared') } else { '' }
            InRegistry        = $inRegistry
            HasAgentsMd       = $hasAgents
            HasCursorIgnore   = $hasIgnore
            HasReadme         = $hasReadme
            GeneratedPaths    = $generatedHits
            LargeFiles        = $largeFiles
            HighCardinality   = $highCard
            Findings          = $findings
            Advisories        = $advisories
            SuggestedTriggers = $suggestedTriggers
            Drift             = ($findings.Count -gt 0 -or -not $inRegistry)
        }
        $reports += $report

        if ($DriftOnly) {
            if ($report.Drift) {
                Write-AuditHost ("DRIFT: {0} ({1})" -f $project.Name, $project.Root) -ForegroundColor Yellow
                foreach ($f in $findings) { Write-AuditHost ("  - {0}" -f $f) }
            }
            continue
        }

        Write-AuditHost ""
        Write-AuditHost ("==== {0} ({1}) ====" -f $project.Name, $project.Root) -ForegroundColor Cyan
        Write-AuditHost ("Registry: {0} | AGENTS.md: {1} | .cursorignore: {2}{3}" -f $inRegistry, $hasAgents, $hasIgnore, $(if ($lightAudit) { ' | light scan' } else { '' }))
        if ($generatedHits.Count -gt 0) {
            Write-AuditHost ("Generated/cache: {0}" -f ($generatedHits -join ', '))
        }
        if ($largeFiles.Count -gt 0) {
            Write-AuditHost 'Large files:'
            foreach ($lf in @($largeFiles | Select-Object -First 5)) {
                Write-AuditHost ("  {0,8} KB  {1}" -f $lf.KB, $lf.Path)
            }
        }
        if ($highCard.Count -gt 0) {
            Write-AuditHost 'High-cardinality dirs:'
            foreach ($hc in @($highCard | Select-Object -First 5)) {
                Write-AuditHost ("  {0,5} files  {1}" -f $hc.FileCount, $hc.Path)
            }
        }
        if ($findings.Count -gt 0) {
            Write-AuditHost 'Findings:' -ForegroundColor Yellow
            foreach ($f in $findings) { Write-AuditHost ("  - {0}" -f $f) }
        }
        else {
            Write-AuditHost 'Findings: none' -ForegroundColor Green
        }
        if ($advisories.Count -gt 0) {
            Write-AuditHost 'Advisory (light root, not counted as drift):'
            foreach ($a in $advisories) { Write-AuditHost ("  - {0}" -f $a) }
        }
        if ($suggestedTriggers.Count -gt 0 -and -not $inRegistry) {
            Write-AuditHost ("Suggested triggers: {0}" -f ($suggestedTriggers -join ', '))
        }
    }

    $summary = [PSCustomObject]@{
        ProjectCount = @($reports).Count
        DriftCount   = $driftCount
        DriftOnly    = [bool]$DriftOnly
        Reports      = $reports
    }

    if ($DriftOnly) {
        Write-AuditHost ""
        Write-AuditHost ("Drift findings: {0}" -f $driftCount) -ForegroundColor $(if ($driftCount -gt 0) { 'Yellow' } else { 'Green' })
        if ($driftCount -gt 0) {
            $global:LASTEXITCODE = 1
        }
        else {
            $global:LASTEXITCODE = 0
        }
    }

    Write-Output $summary
}

function Get-MetaProjectGitCounts {
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

function Get-MetaOpsCanvasPath {
    <#
    .SYNOPSIS
        Resolves the live Metra Ops canvas path for this checkout's Cursor project slug.
    #>
    [CmdletBinding()]
    param()

    $metaRoot = Get-MetaRoot
    $slug = ConvertTo-MetaCursorProjectSlug -Path $metaRoot
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = 'c-Projects-meta'
    }
    return Join-Path $env:USERPROFILE (Join-Path '.cursor\projects' (Join-Path $slug 'canvases\metra-ops-board.canvas.tsx'))
}

function Install-MetaOpsCanvas {
    <#
    .SYNOPSIS
        Ensures the live Metra Ops canvas exists, installing from the tracked template when needed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CanvasPath
    )

    $metaRoot = Get-MetaRoot
    $templatePath = Join-Path $metaRoot 'integrations\cursor\metra-ops-board.canvas.tsx.template'
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

    if ((Test-Path -LiteralPath $legacyPath) -and ($legacyPath -ne $CanvasPath)) {
        Remove-Item -LiteralPath $legacyPath -Force -ErrorAction SilentlyContinue
        Write-Host ("Removed legacy canvas: {0}" -f $legacyPath) -ForegroundColor Yellow
    }

    return (Test-Path -LiteralPath $CanvasPath)
}

function Get-MetaQuickProjectHealthReports {
    <#
    .SYNOPSIS
        Light registry/disk health for snapshot -Quick (no recursive scan, no git).
    #>
    [CmdletBinding()]
    param()

    $registry = Get-MetaProjectRegistry
    $disk = @(Get-MetaProjects)
    $byDisk = @{}
    foreach ($d in $disk) {
        $byDisk[$d.Name.ToLowerInvariant()] = $d
    }

    $driftCount = 0
    $reports = @()

    foreach ($d in $disk) {
        $reg = Get-MetaRegistryProject -Registry $registry -Name $d.Name
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

function Test-MetaCanvasSnapshotStale {
    <#
    .SYNOPSIS
        True when the Ops board snapshot is older than MaxAgeHours or newer than registry/config inputs.
    #>
    [CmdletBinding()]
    param(
        [string]$SnapshotPath,
        [double]$MaxAgeHours = 4
    )

    $metaRoot = Get-MetaRoot
    if (-not $SnapshotPath) {
        $SnapshotPath = Join-Path $metaRoot 'docs\canvas-snapshot.json'
    }
    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        return $true
    }

    $snapTime = (Get-Item -LiteralPath $SnapshotPath).LastWriteTimeUtc
    if (((Get-Date).ToUniversalTime() - $snapTime).TotalHours -gt $MaxAgeHours) {
        return $true
    }

    $watch = @(
        (Join-Path $metaRoot 'projects.json'),
        (Join-Path $metaRoot 'projects.local.json'),
        (Join-Path $metaRoot 'meta.config.json')
    )
    foreach ($root in @(Get-MetaRoots -IncludeMissing)) {
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

function Export-MetaCanvasSnapshot {
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

    $metaRoot = Get-MetaRoot
    if (-not $OutPath) {
        $OutPath = Join-Path $metaRoot 'docs\canvas-snapshot.json'
    }
    if (-not $CanvasPath) {
        $CanvasPath = Get-MetaOpsCanvasPath
    }

    $registry = Get-MetaProjectRegistry
    $cfg = Get-MetaConfig
    $pinned = @()
    if ($cfg.workspace -and $cfg.workspace.alwaysInclude) {
        $pinned = @($cfg.workspace.alwaysInclude)
    }

    $auditDriftCount = 0
    $byName = @{}
    if ($Quick) {
        Write-Host 'Running quick portfolio health for snapshot...' -ForegroundColor Cyan
        $lightHealth = Get-MetaQuickProjectHealthReports
        $auditDriftCount = [int]$lightHealth.DriftCount
        foreach ($r in @($lightHealth.Reports)) {
            $byName[[string]$r.Name.ToLowerInvariant()] = $r
        }
        $diskReports = @($lightHealth.Reports)
    }
    else {
        Write-Host 'Running quiet portfolio audit for snapshot...' -ForegroundColor Cyan
        $audit = Invoke-MetaProjectContextAudit -ScanDepth $ScanDepth -Quiet | Select-Object -Last 1
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
            $git = Get-MetaProjectGitCounts -Path $projectPath
        }
        $optional = [bool](Get-MetaProp -Object $reg -Name 'optional' -Default $false)

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
                }
            }
        }
        if ($git.isGit -and ($git.dirty -gt 0 -or $git.ahead -gt 0 -or $git.behind -gt 0)) {
            $todos += [PSCustomObject]@{
                id      = ($name + ':git')
                project = $name
                content = "$name - git $($git.summary)"
                status  = 'pending'
            }
        }

        [PSCustomObject]@{
            name            = $name
            purpose         = [string](Get-MetaProp -Object $reg -Name 'purpose' -Default '')
            triggers        = @(Get-MetaProp -Object $reg -Name 'triggers' -Default @())
            entry           = [string](Get-MetaProp -Object $reg -Name 'entry' -Default 'AGENTS.md')
            preferredPaths  = @(Get-MetaProp -Object $reg -Name 'preferredPaths' -Default @())
            excludePaths    = @(Get-MetaProp -Object $reg -Name 'excludePaths' -Default @())
            related         = @(Get-MetaProp -Object $reg -Name 'related' -Default @())
            inRegistry      = $true
            registrySource  = [string](Get-MetaProp -Object $reg -Name 'source' -Default 'shared')
            root            = if ($report) { [string]$report.Root } else { '' }
            present         = [bool]$report
            optional        = $optional
            capabilities    = @(Get-MetaProp -Object $reg -Name 'capabilities' -Default @())
            hasAgentsMd     = if ($report) { [bool]$report.HasAgentsMd } else { $false }
            hasCursorIgnore = if ($report) { [bool]$report.HasCursorIgnore } else { $false }
            hasReadme       = if ($report) { [bool]$report.HasReadme } else { $false }
            drift           = if ($report) { [bool]$report.Drift } else { -not $optional }
            findings        = $findings
            largeFiles      = $large
            status          = $status
            pinned          = ($pinned -contains $name)
            gitIsRepo       = [bool]$git.isGit
            gitDirty        = [int]$git.dirty
            gitAhead        = [int]$git.ahead
            gitBehind       = [int]$git.behind
            gitBranch       = [string]$git.branch
            gitSummary      = [string]$git.summary
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
                $git = Get-MetaProjectGitCounts -Path ([string]$r.Path)
            }
            if ($git.isGit -and ($git.dirty -gt 0 -or $git.ahead -gt 0 -or $git.behind -gt 0)) {
                $todos += [PSCustomObject]@{
                    id      = ($r.Name + ':git')
                    project = [string]$r.Name
                    content = "$($r.Name) - git $($git.summary)"
                    status  = 'pending'
                }
            }
            $projects = @($projects) + @(
                [PSCustomObject]@{
                    name            = [string]$r.Name
                    purpose         = ''
                    triggers        = @()
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
                    gitIsRepo       = [bool]$git.isGit
                    gitDirty        = [int]$git.dirty
                    gitAhead        = [int]$git.ahead
                    gitBehind       = [int]$git.behind
                    gitBranch       = [string]$git.branch
                    gitSummary      = [string]$git.summary
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

    $snapshot = [ordered]@{
        generatedAt       = (Get-Date).ToString('o')
        mode              = $(if ($Quick) { 'quick' } else { 'full' })
        projectCount      = @($projects).Count
        driftCount        = [int]$auditDriftCount
        driftProjects     = $driftProjects
        notInstalled      = $notInstalled
        missingAgents     = $missingAgents
        missingIgnore     = $missingIgnore
        roots             = @(Get-MetaRoots -IncludeMissing | ForEach-Object {
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
    }

    $dir = Split-Path -Parent $OutPath
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($snapshot | ConvertTo-Json -Depth 8)
    [System.IO.File]::WriteAllText($OutPath, $json + "`r`n")
    Write-Host ("Wrote snapshot: {0}" -f $OutPath) -ForegroundColor Green

    $canvasReady = Install-MetaOpsCanvas -CanvasPath $CanvasPath
    if ($canvasReady) {
        $canvas = [System.IO.File]::ReadAllText($CanvasPath)
        $markerPairs = @(
            @{ Begin = '// <metra-ops-snapshot>'; End = '// </metra-ops-snapshot>' },
            @{ Begin = '// <meta-ops-snapshot>'; End = '// </meta-ops-snapshot>' }
        )
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

function ConvertTo-MetaCursorProjectSlug {
    <#
    .SYNOPSIS
        Builds the Cursor per-project folder slug for a project name or full path.
    .DESCRIPTION
        Cursor names its state folder after the workspace path: C:\Projects\_meta becomes
        c-Projects-meta. Projects outside the primary root (for example a cloud-synced
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
    if (Test-MetaSelfFolderName -Name $trimmed) { return 'c-Projects-meta' }
    $slug = ($trimmed -replace '[^\w]+', '-').Trim('-')
    return "c-Projects-$slug"
}

function Get-MetaCursorTranscriptRoots {
    <#
    .SYNOPSIS
        Maps project names to local Cursor agent-transcript folders.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [switch]$IncludeMeta
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
        $projects = Get-MetaProjects
        foreach ($p in $projects) { $wanted.Add([string]$p.Name) }
    }
    if ($IncludeMeta -or -not $Name -or $Name.Count -eq 0) {
        if (-not ($wanted | Where-Object { Test-MetaSelfFolderName -Name $_ })) {
            $wanted.Add('_meta')
        }
    }

    $pathByName = @{}
    foreach ($p in @(Get-MetaProjects)) {
        $pathByName[$p.Name.ToLowerInvariant()] = $p.Path
    }

    $seen = @{}
    foreach ($projectName in $wanted) {
        $candidates = [System.Collections.Generic.List[string]]::new()
        $known = $pathByName[$projectName.ToLowerInvariant()]
        if ($known) {
            [void]$candidates.Add((ConvertTo-MetaCursorProjectSlug -Path $known))
        }
        [void]$candidates.Add((ConvertTo-MetaCursorProjectSlug -Name $projectName))

        foreach ($slug in $candidates) {
            if (-not $slug -or $seen.ContainsKey($slug)) { continue }
            $seen[$slug] = $true
            $transcriptRoot = Join-Path $cursorProjects (Join-Path $slug 'agent-transcripts')
            if (-not (Test-Path -LiteralPath $transcriptRoot)) { continue }
            [PSCustomObject]@{
                Name           = if (Test-MetaSelfFolderName -Name $projectName) { '_meta' } else { $projectName }
                CursorSlug     = $slug
                TranscriptRoot = $transcriptRoot
            }
        }
    }
}

function Get-MetaChatSearchTerms {
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

function Get-MetaChatSnippet {
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

function Get-MetaChatTitle {
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

function Get-MetaProjectChats {
    <#
    .SYNOPSIS
        Search local Cursor agent transcripts for ticket / keyword clues (bounded summaries).
    .DESCRIPTION
        Scans parent *.jsonl under ~/.cursor/projects/c-Projects-*/agent-transcripts
        (skips subagents/). Returns chat uuid, title, matched terms, and short snippets -
        not full transcripts. Canonical ticket memory remains TicketTracker notes/solutions.
    .EXAMPLE
        Get-MetaProjectChats -Name Solarwinds -Query 'disk alert' -Limit 10
    .EXAMPLE
        Get-MetaProjectChats -Name TicketTracker,Solarwinds -Ticket 12345 -Days 90
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [string]$Query,
        [string]$Ticket,
        [int]$Days = 90,
        [int]$Limit = 10,
        [int]$SnippetChars = 160,
        [switch]$IncludeMeta
    )

    if ($Limit -lt 1) { $Limit = 10 }
    if ($Days -lt 1) { $Days = 90 }

    $terms = @(Get-MetaChatSearchTerms -Query $Query -Ticket $Ticket | ForEach-Object { [string]$_ })
    Write-Verbose ("Chat search terms ({0}): {1}" -f $terms.Count, ($terms -join ' | '))
    $roots = @(Get-MetaCursorTranscriptRoots -Name $Name -IncludeMeta:$IncludeMeta)
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
                        $snip = Get-MetaChatSnippet -Text $raw -Term $term -MaxChars $SnippetChars
                        if ($snip) { [void]$snippets.Add([string]$snip) }
                    }
                }
            }
            if ($matched.Count -eq 0) { continue }
        }

        $title = Get-MetaChatTitle -Raw $raw
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

function Get-MetaProfileFileMap {
    <#
    .SYNOPSIS
        Relative paths that make up an operator profile pack (same layout as profiles/sample).
    #>
    return @(
        'meta.config.json',
        'projects.local.json',
        '.cursor/rules/metra-persona.local.mdc'
    )
}

function Resolve-MetaProfileSourceDir {
    <#
    .SYNOPSIS
        Resolves a profile pack path to an unpacked directory (extracts zip to temp when needed).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $expanded = [System.Environment]::ExpandEnvironmentVariables($Path)
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path (Get-Location).Path $expanded
    }
    $full = [System.IO.Path]::GetFullPath($expanded)

    if (-not (Test-Path -LiteralPath $full)) {
        throw "Profile path not found: $full"
    }

    $item = Get-Item -LiteralPath $full
    if ($item.PSIsContainer) {
        return [PSCustomObject]@{
            Directory = $item.FullName
            TempDir   = $null
            Source    = $item.FullName
            IsZip     = $false
        }
    }

    if ($item.Extension -ne '.zip') {
        throw "Profile path must be a directory or .zip file: $full"
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('meta-profile-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Expand-Archive -LiteralPath $item.FullName -DestinationPath $tempRoot -Force

    $manifest = Get-ChildItem -LiteralPath $tempRoot -Filter 'meta-profile.json' -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $dir = if ($manifest) {
        $manifest.Directory.FullName
    }
    else {
        $children = @(Get-ChildItem -LiteralPath $tempRoot -Directory)
        if ($children.Count -eq 1 -and (Test-Path (Join-Path $children[0].FullName 'meta-profile.json'))) {
            $children[0].FullName
        }
        else {
            $tempRoot
        }
    }

    return [PSCustomObject]@{
        Directory = $dir
        TempDir   = $tempRoot
        Source    = $item.FullName
        IsZip     = $true
    }
}

function Export-MetaProfile {
    <#
    .SYNOPSIS
        Pack local operator customizations into a portable folder (or zip if path ends in .zip).
    .DESCRIPTION
        Same layout as profiles/sample/. Does not include secrets, ticket caches, canvas snapshots,
        or personal-root registryFile (copy that with the personal root separately).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $metaRoot = Get-MetaRoot
    $fileMap = @(Get-MetaProfileFileMap)
    $present = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $fileMap) {
        $src = Join-Path $metaRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $src) {
            [void]$present.Add($rel)
        }
    }
    if ($present.Count -eq 0) {
        throw 'Nothing to export: no meta.config.json, projects.local.json, or metra-persona.local.mdc found.'
    }

    $expanded = [System.Environment]::ExpandEnvironmentVariables($Path)
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path (Get-Location).Path $expanded
    }
    $destFull = [System.IO.Path]::GetFullPath($expanded)
    $asZip = $destFull.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)

    $staging = if ($asZip) {
        Join-Path ([System.IO.Path]::GetTempPath()) ('meta-profile-export-' + [guid]::NewGuid().ToString('N'))
    }
    else {
        $destFull
    }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    foreach ($rel in $present) {
        $src = Join-Path $metaRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $dst = Join-Path $staging ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    $manifest = [ordered]@{
        version     = 1
        id          = 'export'
        description = 'Operator profile exported from local _meta customizations.'
        exportedUtc = [DateTime]::UtcNow.ToString('o')
        files       = @($present.ToArray())
        notes       = @(
            'Personal-root registryFile (e.g. projects.personal.json beside personal projects) is not included; copy it with that root separately.',
            'Do not pack secrets, ticket caches, or canvas snapshots.'
        )
    }
    $manifestPath = Join-Path $staging 'meta-profile.json'
    ($manifest | ConvertTo-Json -Depth 6) | Set-Content -Path $manifestPath -Encoding utf8

    $readmePath = Join-Path $staging 'README.md'
    @"
# Exported Meta operator profile

Created: $($manifest.exportedUtc)

Import into another `_meta` clone:

``````powershell
.\meta.ps1 import-profile -Path <this-folder-or-zip> -Force
# Then edit meta.config.json roots / operator name in metra-persona.local.mdc
``````

Personal-root ``registryFile`` is not included in this pack.
"@ | Set-Content -Path $readmePath -Encoding utf8

    $resultPath = $destFull
    $manifestOut = $manifestPath
    if ($asZip) {
        $zipDir = Split-Path -Parent $destFull
        if ($zipDir -and -not (Test-Path -LiteralPath $zipDir)) {
            New-Item -ItemType Directory -Path $zipDir -Force | Out-Null
        }
        if (Test-Path -LiteralPath $destFull) {
            Remove-Item -LiteralPath $destFull -Force
        }
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $destFull -Force
        Remove-Item -LiteralPath $staging -Recurse -Force
        $manifestOut = 'meta-profile.json (inside zip)'
    }

    return [PSCustomObject]@{
        Path      = $resultPath
        Files     = @($present.ToArray())
        IsZip     = $asZip
        Manifest  = $manifestOut
    }
}

function Import-MetaProfile {
    <#
    .SYNOPSIS
        Restore an operator profile pack into _meta (same layout as profiles/sample).
    .PARAMETER Preview
        List what would copy; do not write.
    .PARAMETER Force
        Overwrite existing local files. Without -Force, refuse if any target already exists.
    .PARAMETER Quiet
        Suppress host messages (useful for verify / automated callers).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Preview,
        [switch]$Force,
        [switch]$Quiet
    )

    $metaRoot = Get-MetaRoot
    $resolved = Resolve-MetaProfileSourceDir -Path $Path
    try {
        $srcDir = $resolved.Directory
        $manifestPath = Join-Path $srcDir 'meta-profile.json'
        $fileMap = @(Get-MetaProfileFileMap)
        $fromManifest = @()
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
            $fromManifest = @(Get-MetaProp -Object $manifest -Name 'files' -Default @())
        }
        $candidates = if ($fromManifest.Count -gt 0) { $fromManifest } else { $fileMap }

        $plan = New-Object System.Collections.Generic.List[object]
        foreach ($rel in $candidates) {
            $relNorm = [string]$rel -replace '\\', '/'
            if ($fileMap -notcontains $relNorm -and $fileMap -notcontains ($relNorm -replace '/', '\')) {
                # Still allow known map paths only
                $allowed = $false
                foreach ($known in $fileMap) {
                    if ($known -eq $relNorm) { $allowed = $true; break }
                }
                if (-not $allowed) { continue }
            }
            $src = Join-Path $srcDir ($relNorm -replace '/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $src)) { continue }
            $dst = Join-Path $metaRoot ($relNorm -replace '/', [IO.Path]::DirectorySeparatorChar)
            $exists = Test-Path -LiteralPath $dst
            [void]$plan.Add([PSCustomObject]@{
                Relative = $relNorm
                Source   = $src
                Dest     = $dst
                Exists   = $exists
            })
        }

        if ($plan.Count -eq 0) {
            throw "No importable profile files found under: $srcDir"
        }

        if ($Preview) {
            if (-not $Quiet) {
                Write-Host 'Preview import (no writes):' -ForegroundColor Cyan
                foreach ($row in $plan) {
                    $flag = if ($row.Exists) { 'OVERWRITE' } else { 'NEW' }
                    Write-Host ("  [{0}] {1}" -f $flag, $row.Relative)
                }
                Write-Host ''
                Write-Host 'Post-import checklist (after a real import):'
                Write-Host '  - Edit meta.config.json roots / workspace.alwaysInclude for this machine'
                Write-Host '  - Edit .cursor/rules/metra-persona.local.mdc operator display name'
                Write-Host '  - Personal-root registryFile is not in the pack; copy separately if needed'
                Write-Host '  - Run .\meta.ps1 workspace and .\meta.ps1 audit'
            }
            return [PSCustomObject]@{
                Preview = $true
                Files   = @($plan | ForEach-Object { $_.Relative })
                Source  = $resolved.Source
            }
        }

        $blocked = @($plan | Where-Object { $_.Exists })
        if ($blocked.Count -gt 0 -and -not $Force) {
            $names = ($blocked | ForEach-Object { $_.Relative }) -join ', '
            throw "Refusing to overwrite existing files without -Force: $names"
        }

        foreach ($row in $plan) {
            $dstDir = Split-Path -Parent $row.Dest
            if (-not (Test-Path -LiteralPath $dstDir)) {
                New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $row.Source -Destination $row.Dest -Force
            if (-not $Quiet) {
                Write-Host ("Imported {0}" -f $row.Relative)
            }
        }

        if (-not $Quiet) {
            Write-Host ''
            Write-Host 'Post-import checklist:' -ForegroundColor Yellow
            Write-Host '  - Edit meta.config.json roots / workspace.alwaysInclude for this machine'
            Write-Host '  - Edit .cursor/rules/metra-persona.local.mdc operator display name'
            Write-Host '  - Personal-root registryFile is not in the pack; copy separately if needed'
            Write-Host '  - Run .\meta.ps1 workspace and .\meta.ps1 audit'
        }

        return [PSCustomObject]@{
            Preview = $false
            Files   = @($plan | ForEach-Object { $_.Relative })
            Source  = $resolved.Source
            Dest    = $metaRoot
        }
    }
    finally {
        if ($resolved.TempDir -and (Test-Path -LiteralPath $resolved.TempDir)) {
            Remove-Item -LiteralPath $resolved.TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Export-MetaContextPack {
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

    $metaRoot = Get-MetaRoot
    if ($Limit -lt 1) { $Limit = 25 }

    $roots = @(Get-MetaRoots -IncludeMissing | ForEach-Object {
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

    $registry = Get-MetaProjectRegistry
    $disk = @{}
    foreach ($p in @(Get-MetaProjects)) {
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

        $purpose = [string](Get-MetaProp -Object $reg -Name 'purpose' -Default '')
        $triggers = @(Get-MetaProp -Object $reg -Name 'triggers' -Default @())
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
            capabilities = @(Get-MetaProp -Object $reg -Name 'capabilities' -Default @())
            entry        = [string](Get-MetaProp -Object $reg -Name 'entry' -Default 'AGENTS.md')
            score        = $score
        })
    }

    # Also include present disk projects with no registry row (bounded).
    if ($tokens.Count -eq 0) {
        foreach ($p in @(Get-MetaProjects)) {
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
        Get-MetaRoutingTable |
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
            'CLI: .\meta.ps1 routing | audit | chats | ctx'
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

    $defaultMd = Join-Path $metaRoot 'docs\context-pack.md'
    $defaultJson = Join-Path $metaRoot 'docs\context-pack.json'
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

function Invoke-MetaVerify {
    <#
    .SYNOPSIS
        Runs Routing-Scenarios fixture smoke checks; returns PASS/WARN/FAIL rows.
    .DESCRIPTION
        Required checks FAIL when missing. Soft sibling paths WARN when absent (optional stubs)
        and FAIL when present but expected patterns are missing. Live CLI checks FAIL on
        exception; WARN when a named project is not Present on disk.
        Exit code semantics for callers: 0 when FailCount is 0; otherwise 1.
    #>
    [CmdletBinding()]
    param()

    $metaRoot = Get-MetaRoot
    $projectsRoot = Get-ProjectsRoot
    $results = New-Object System.Collections.ArrayList

    function Add-VerifyResult {
        param(
            [string]$Name,
            [ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status,
            [string]$Detail = ''
        )
        [void]$results.Add([PSCustomObject]@{
            Name   = $Name
            Status = $Status
            Detail = $Detail
        })
    }

    function Test-SoftSiblingPath {
        param(
            [string]$Name,
            [string]$RelativeUnderProjectsRoot
        )
        $full = Join-Path $projectsRoot $RelativeUnderProjectsRoot
        if (Test-Path -LiteralPath $full) {
            Add-VerifyResult -Name $Name -Status 'PASS' -Detail $full
            return $full
        }
        Add-VerifyResult -Name $Name -Status 'WARN' -Detail "absent (optional stub): $full"
        return $null
    }

    # Required files
    $requiredPaths = @(
        @{ Name = 'projects.json'; Path = (Join-Path $metaRoot 'projects.json') },
        @{ Name = 'profiles/sample/meta-profile.json'; Path = (Join-Path $metaRoot 'profiles\sample\meta-profile.json') }
    )
    foreach ($item in $requiredPaths) {
        if (Test-Path -LiteralPath $item.Path) {
            Add-VerifyResult -Name $item.Name -Status 'PASS' -Detail $item.Path
        }
        else {
            Add-VerifyResult -Name $item.Name -Status 'FAIL' -Detail "missing: $($item.Path)"
        }
    }

    # Soft sibling paths from Routing-Scenarios fixtures
    $null = Test-SoftSiblingPath -Name 'TicketTracker/AGENTS.md' -RelativeUnderProjectsRoot 'TicketTracker\AGENTS.md'
    $null = Test-SoftSiblingPath -Name 'Trivia/AGENTS.md' -RelativeUnderProjectsRoot 'Trivia\AGENTS.md'
    $null = Test-SoftSiblingPath -Name 'Solarwinds/docs/Ticket-Triage.md' -RelativeUnderProjectsRoot 'Solarwinds\docs\Ticket-Triage.md'

    $ttPs1 = Join-Path $projectsRoot 'TicketTracker\TicketTracker.ps1'
    if (Test-Path -LiteralPath $ttPs1) {
        foreach ($pat in @("'brief'", "'chats'")) {
            $hit = Select-String -Path $ttPs1 -Pattern $pat -SimpleMatch -ErrorAction SilentlyContinue
            if ($hit) {
                Add-VerifyResult -Name ("TicketTracker.ps1 $pat") -Status 'PASS' -Detail $ttPs1
            }
            else {
                Add-VerifyResult -Name ("TicketTracker.ps1 $pat") -Status 'FAIL' -Detail "pattern not found: $pat"
            }
        }
    }
    else {
        Add-VerifyResult -Name 'TicketTracker.ps1 patterns' -Status 'WARN' -Detail 'TicketTracker.ps1 absent (optional stub)'
    }

    # Live CLI: roots
    try {
        $roots = @(Get-MetaRoots -IncludeMissing)
        if ($roots.Count -gt 0) {
            Add-VerifyResult -Name 'meta.ps1 roots' -Status 'PASS' -Detail ("{0} root(s)" -f $roots.Count)
        }
        else {
            Add-VerifyResult -Name 'meta.ps1 roots' -Status 'FAIL' -Detail 'no roots returned'
        }
    }
    catch {
        Add-VerifyResult -Name 'meta.ps1 roots' -Status 'FAIL' -Detail $_.Exception.Message
    }

    # Live CLI: routing for fixture names
    try {
        $routing = @(Get-MetaRoutingTable -Name @('TicketTracker', 'Solarwinds', 'Trivia'))
        if ($routing.Count -eq 0) {
            Add-VerifyResult -Name 'routing TicketTracker,Solarwinds,Trivia' -Status 'FAIL' -Detail 'no routing rows'
        }
        else {
            foreach ($row in $routing) {
                $label = "routing $($row.Name)"
                if ($row.Present) {
                    Add-VerifyResult -Name $label -Status 'PASS' -Detail $row.Path
                }
                elseif ($row.Optional) {
                    Add-VerifyResult -Name $label -Status 'WARN' -Detail 'not Present (optional)'
                }
                else {
                    Add-VerifyResult -Name $label -Status 'WARN' -Detail 'not Present on disk'
                }
            }
        }
    }
    catch {
        Add-VerifyResult -Name 'routing TicketTracker,Solarwinds,Trivia' -Status 'FAIL' -Detail $_.Exception.Message
    }

    # Live CLI: ctx (no docs write during smoke)
    try {
        $ctx = Export-MetaContextPack -Query 'ticket' -Format markdown -Path '-' -Quiet |
            Select-Object -Last 1
        if ($ctx -and [string]$ctx.Path -eq '-') {
            Add-VerifyResult -Name 'ctx -Query ticket' -Status 'PASS' -Detail 'stdout-only (no file write)'
        }
        else {
            Add-VerifyResult -Name 'ctx -Query ticket' -Status 'FAIL' -Detail 'expected Path=- for quiet ctx'
        }
    }
    catch {
        Add-VerifyResult -Name 'ctx -Query ticket' -Status 'FAIL' -Detail $_.Exception.Message
    }

    # Live CLI: import-profile Preview (quiet)
    try {
        $sample = Join-Path $metaRoot 'profiles\sample'
        $preview = Import-MetaProfile -Path $sample -Preview -Quiet
        if ($preview.Preview -and @($preview.Files).Count -gt 0) {
            Add-VerifyResult -Name 'import-profile sample -Preview' -Status 'PASS' -Detail $sample
        }
        else {
            Add-VerifyResult -Name 'import-profile sample -Preview' -Status 'FAIL' -Detail 'preview returned no files'
        }
    }
    catch {
        Add-VerifyResult -Name 'import-profile sample -Preview' -Status 'FAIL' -Detail $_.Exception.Message
    }

    # Soft: chats (Cursor-specific; may be empty)
    try {
        $chats = @(Get-MetaProjectChats -Name 'Solarwinds' -Query 'alert' -Limit 3 -ErrorAction Stop)
        Add-VerifyResult -Name 'chats Solarwinds alert' -Status 'PASS' -Detail ("{0} row(s)" -f $chats.Count)
    }
    catch {
        Add-VerifyResult -Name 'chats Solarwinds alert' -Status 'WARN' -Detail $_.Exception.Message
    }

    # Soft: audit DriftOnly on fixture trio when present
    try {
        $presentNames = @(
            Get-MetaRoutingTable -Name @('Solarwinds', 'TicketTracker', 'Trivia') |
                Where-Object { $_.Present } |
                ForEach-Object { $_.Name }
        )
        if ($presentNames.Count -eq 0) {
            Add-VerifyResult -Name 'audit -DriftOnly fixtures' -Status 'WARN' -Detail 'no fixture projects Present'
        }
        else {
            $audit = Invoke-MetaProjectContextAudit -Name $presentNames -DriftOnly -Quiet | Select-Object -Last 1
            Add-VerifyResult -Name 'audit -DriftOnly fixtures' -Status 'PASS' -Detail ("driftSignals={0}" -f $audit.DriftCount)
        }
    }
    catch {
        Add-VerifyResult -Name 'audit -DriftOnly fixtures' -Status 'FAIL' -Detail $_.Exception.Message
    }

    $pass = @($results | Where-Object Status -eq 'PASS').Count
    $warn = @($results | Where-Object Status -eq 'WARN').Count
    $fail = @($results | Where-Object Status -eq 'FAIL').Count

    return [PSCustomObject]@{
        Results   = @($results)
        PassCount = $pass
        WarnCount = $warn
        FailCount = $fail
        Ok        = ($fail -eq 0)
    }
}

Export-ModuleMember -Function @(
    'Get-MetaRoot',
    'Get-MetaConfig',
    'Get-MetaProp',
    'Get-MetaRoots',
    'Get-ProjectsRoot',
    'Get-MetaProjects',
    'Invoke-AcrossProjects',
    'Get-MetaStatus',
    'Update-MetaProjects',
    'Copy-AcrossProjects',
    'New-MetaProject',
    'Get-ProjectLastActivity',
    'Get-RecentMetaProjects',
    'Update-MetaWorkspace',
    'Get-MetaProjectRegistry',
    'Get-MetaRoutingTable',
    'Invoke-MetaProjectContextAudit',
    'Get-MetaProjectGitCounts',
    'Export-MetaCanvasSnapshot',
    'Test-MetaCanvasSnapshotStale',
    'Get-MetaQuickProjectHealthReports',
    'Invoke-MetaVerify',
    'Export-MetaContextPack',
    'Get-MetaProjectChats',
    'Get-MetaCursorTranscriptRoots',
    'Get-MetaProfileFileMap',
    'Export-MetaProfile',
    'Import-MetaProfile'
)

