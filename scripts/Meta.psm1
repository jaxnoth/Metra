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

function Get-ProjectsRoot {
    $cfg = Get-MetaConfig
    $metaRoot = Get-MetaRoot
    $root = Join-Path $metaRoot $cfg.projectsRoot
    return (Resolve-Path $root).Path
}

function Test-ExcludedProjectName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Config
    )

    $exclude = @($Config.exclude)
    if ($exclude -contains $Name) { return $true }

    foreach ($pattern in @($Config.excludeNamePatterns)) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

function Get-MetaProjects {
    <#
    .SYNOPSIS
        Lists project directories under the configured projects root.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [switch]$GitOnly,
        [switch]$IncludeNonGit
    )

    $cfg = Get-MetaConfig
    $projectsRoot = Get-ProjectsRoot

    Get-ChildItem -Path $projectsRoot -Directory -Force |
        Where-Object {
            -not (Test-ExcludedProjectName -Name $_.Name -Config $cfg) -and
            ($_.Name -like $Filter)
        } |
        ForEach-Object {
            $isGit = Test-Path (Join-Path $_.FullName '.git')
            if ($GitOnly -and -not $isGit) { return }
            if (-not $IncludeNonGit -and -not $GitOnly -and -not $isGit) {
                # default: include both; caller can filter
            }
            [PSCustomObject]@{
                Name   = $_.Name
                Path   = $_.FullName
                IsGit  = $isGit
            }
        } |
        Sort-Object Name
}

function Resolve-MetaProjectSet {
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [switch]$GitOnly
    )

    $projects = Get-MetaProjects -Filter $Filter -GitOnly:$GitOnly
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
        [switch]$GitOnly,
        [switch]$ContinueOnError,
        [switch]$Quiet
    )

    $projects = Resolve-MetaProjectSet -Filter $Filter -Name $Name -GitOnly:$GitOnly
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
        [string[]]$Name
    )

    Invoke-AcrossProjects -Command 'git status -sb' -Filter $Filter -Name $Name -GitOnly -ContinueOnError
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
        [switch]$FetchOnly
    )

    $cmd = if ($FetchOnly) { 'git fetch --all --prune' } else { 'git pull --ff-only' }
    Invoke-AcrossProjects -Command $cmd -Filter $Filter -Name $Name -GitOnly -ContinueOnError
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
        [switch]$Force
    )

    $sourcePath = (Resolve-Path $Source).Path
    if (-not $RelativePath) {
        $RelativePath = Split-Path -Leaf $sourcePath
    }

    $projects = Resolve-MetaProjectSet -Filter $Filter -Name $Name
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
        [switch]$NoGit,
        [switch]$Force
    )

    $cfg = Get-MetaConfig
    $projectsRoot = Get-ProjectsRoot
    $metaRoot = Get-MetaRoot

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
    $ws = $cfg.workspace
    if (-not $PSBoundParameters.ContainsKey('Months')) {
        $Months = if ($ws -and $ws.months) { [int]$ws.months } else { 6 }
    }
    if (-not $PSBoundParameters.ContainsKey('ScanDepth')) {
        $ScanDepth = if ($ws -and $null -ne $ws.scanDepth) { [int]$ws.scanDepth } else { 2 }
    }

    $cutoff = (Get-Date).AddMonths(-1 * $Months)
    $always = @()
    if ($ws -and $ws.alwaysInclude) { $always = @($ws.alwaysInclude) }

    $projects = Get-MetaProjects | ForEach-Object {
        $last = Get-ProjectLastActivity -Path $_.Path -ScanDepth $ScanDepth
        $forced = $always -contains $_.Name
        [PSCustomObject]@{
            Name         = $_.Name
            Path         = $_.Path
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
        Rebuilds Meta.code-workspace file(s) with meta plus projects active in the lookback window.
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
    $outputs = @($ws.outputs)
    if ($outputs.Count -eq 0) {
        throw 'workspace.outputs is empty in meta.config.json.'
    }

    Write-Host ("Lookback: {0} month(s) | {1} project(s) (+ meta)" -f $Months, $recent.Count) -ForegroundColor Cyan
    $recent | ForEach-Object {
        Write-Host ("  {0,-24} {1:yyyy-MM-dd}" -f $_.Name, $_.LastActivity)
    }

    $written = @()
    foreach ($out in $outputs) {
        $outPath = Join-Path $metaRoot $out.path
        $prefix = [string]$out.projectPathPrefix
        $folders = @(
            [ordered]@{
                name = 'meta'
                path = [string]$out.metaFolderPath
            }
        )
        foreach ($project in $recent) {
            $folders += [ordered]@{
                name = $project.Name
                path = ($prefix + $project.Name)
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

function Get-MetaProjectRegistry {
    <#
    .SYNOPSIS
        Loads _meta/projects.json agent routing registry.
    #>
    [CmdletBinding()]
    param()

    $path = Join-Path (Get-MetaRoot) 'projects.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing project registry: $path"
    }
    return Get-Content -Raw -Path $path | ConvertFrom-Json
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
        [switch]$DriftOnly,
        [switch]$Quiet,
        [int]$LargeFileBytes = 200KB,
        [int]$HighCardinalityCount = 200,
        [int]$ScanDepth = 4
    )

    $registry = Get-MetaProjectRegistry
    $projects = @(Resolve-MetaProjectSet -Filter $Filter -Name $Name)
    $generatedHints = Get-MetaGeneratedPathHints
    $driftCount = 0
    $reports = @()

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
                $driftCount++
                Write-AuditHost ("DRIFT: registry project missing on disk: {0}" -f $reg.name) -ForegroundColor Yellow
            }
        }
    }

    foreach ($project in $projects) {
        $reg = Get-MetaRegistryProject -Registry $registry -Name $project.Name
        $inRegistry = $null -ne $reg
        $findings = @()
        $largeFiles = @()
        $highCard = @()
        $generatedHits = @()

        $hasAgents = Test-Path -LiteralPath (Join-Path $project.Path 'AGENTS.md')
        $hasIgnore = Test-Path -LiteralPath (Join-Path $project.Path '.cursorignore')
        $hasReadme = Test-Path -LiteralPath (Join-Path $project.Path 'README.md')

        if (-not $inRegistry) {
            $findings += 'Missing from projects.json registry'
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
                    $findings += "excludePath '$ex' exists but .cursorignore is missing"
                    $driftCount++
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
                    $findings += "Generated/cache path not covered by registry exclude or .cursorignore: $hint"
                    $driftCount++
                }
            }
        }

        $largeFileList = New-Object System.Collections.ArrayList
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
        $largeFiles = @($largeFileList.ToArray())

        $highCardList = New-Object System.Collections.ArrayList
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
            InRegistry        = $inRegistry
            HasAgentsMd       = $hasAgents
            HasCursorIgnore   = $hasIgnore
            HasReadme         = $hasReadme
            GeneratedPaths    = $generatedHits
            LargeFiles        = $largeFiles
            HighCardinality   = $highCard
            Findings          = $findings
            SuggestedTriggers = $suggestedTriggers
            Drift             = ($findings.Count -gt 0 -or -not $inRegistry)
        }
        $reports += $report

        if ($DriftOnly) {
            if ($report.Drift) {
                Write-AuditHost ("DRIFT: {0}" -f $project.Name) -ForegroundColor Yellow
                foreach ($f in $findings) { Write-AuditHost ("  - {0}" -f $f) }
            }
            continue
        }

        Write-AuditHost ""
        Write-AuditHost ("==== {0} ====" -f $project.Name) -ForegroundColor Cyan
        Write-AuditHost ("Registry: {0} | AGENTS.md: {1} | .cursorignore: {2}" -f $inRegistry, $hasAgents, $hasIgnore)
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

function Export-MetaCanvasSnapshot {
    <#
    .SYNOPSIS
        Writes docs/canvas-snapshot.json from registry + quiet audit for the Ops canvas embed.
    #>
    [CmdletBinding()]
    param(
        [string]$OutPath,
        [string]$CanvasPath,
        [int]$ScanDepth = 2
    )

    $metaRoot = Get-MetaRoot
    if (-not $OutPath) {
        $OutPath = Join-Path $metaRoot 'docs\canvas-snapshot.json'
    }
    if (-not $CanvasPath) {
        $CanvasPath = Join-Path $env:USERPROFILE '.cursor\projects\c-Projects-meta\canvases\meta-ops-board.canvas.tsx'
    }

    $registry = Get-MetaProjectRegistry
    $cfg = Get-MetaConfig
    $pinned = @()
    if ($cfg.workspace -and $cfg.workspace.alwaysInclude) {
        $pinned = @($cfg.workspace.alwaysInclude)
    }

    Write-Host 'Running quiet portfolio audit for snapshot...' -ForegroundColor Cyan
    $audit = Invoke-MetaProjectContextAudit -ScanDepth $ScanDepth -Quiet | Select-Object -Last 1
    $byName = @{}
    foreach ($r in @($audit.Reports)) {
        $byName[[string]$r.Name] = $r
    }

    $todos = @()
    $projects = foreach ($reg in @($registry.projects)) {
        $name = [string]$reg.name
        $report = $byName[$name]
        $findings = @()
        if ($report -and $report.Findings) { $findings = @($report.Findings) }

        $large = @()
        if ($report -and $report.LargeFiles) {
            $large = @(
                $report.LargeFiles | Select-Object -First 3 | ForEach-Object {
                    [PSCustomObject]@{ path = [string]$_.Path; kb = [double]$_.KB }
                }
            )
        }

        $projectPath = if ($report) { [string]$report.Path } else { Join-Path (Get-ProjectsRoot) $name }
        $git = Get-MetaProjectGitCounts -Path $projectPath

        $status = 'healthy'
        if (-not $report) { $status = 'missing-audit' }
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
            purpose         = [string]$reg.purpose
            triggers        = @($reg.triggers)
            entry           = [string]$reg.entry
            preferredPaths  = @($reg.preferredPaths)
            excludePaths    = @($reg.excludePaths)
            related         = @($reg.related)
            inRegistry      = $true
            hasAgentsMd     = if ($report) { [bool]$report.HasAgentsMd } else { $false }
            hasCursorIgnore = if ($report) { [bool]$report.HasCursorIgnore } else { $false }
            hasReadme       = if ($report) { [bool]$report.HasReadme } else { $false }
            drift           = if ($report) { [bool]$report.Drift } else { $true }
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

    # Disk projects present in audit but not registry
    foreach ($r in @($audit.Reports)) {
        if ($byName.ContainsKey([string]$r.Name) -and -not (@($registry.projects.name) -contains $r.Name)) {
            # already handled via registry loop only; add orphans
        }
    }
    foreach ($r in @($audit.Reports)) {
        $exists = $false
        foreach ($p in @($projects)) {
            if ($p.name -eq $r.Name) { $exists = $true; break }
        }
        if (-not $exists) {
            $findings = @($r.Findings)
            foreach ($f in $findings) {
                $todos += [PSCustomObject]@{
                    id      = ($r.Name + ':' + ($f.GetHashCode()))
                    project = [string]$r.Name
                    content = "$($r.Name) - $f"
                    status  = 'pending'
                }
            }
            $git = Get-MetaProjectGitCounts -Path ([string]$r.Path)
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

    $missingAgents = @($projects | Where-Object { -not $_.hasAgentsMd }).Count
    $missingIgnore = @($projects | Where-Object { -not $_.hasCursorIgnore }).Count
    $driftProjects = @($projects | Where-Object { $_.drift }).Count
    $gitDirtyProjects = @($projects | Where-Object { $_.gitIsRepo -and $_.gitDirty -gt 0 }).Count
    $gitDirtyFiles = (@($projects | Where-Object { $_.gitIsRepo } | Measure-Object -Property gitDirty -Sum).Sum)
    if ($null -eq $gitDirtyFiles) { $gitDirtyFiles = 0 }
    $gitAheadProjects = @($projects | Where-Object { $_.gitIsRepo -and $_.gitAhead -gt 0 }).Count
    $gitBehindProjects = @($projects | Where-Object { $_.gitIsRepo -and $_.gitBehind -gt 0 }).Count

    $snapshot = [ordered]@{
        generatedAt       = (Get-Date).ToString('o')
        projectCount      = @($projects).Count
        driftCount        = [int]$audit.DriftCount
        driftProjects     = $driftProjects
        missingAgents     = $missingAgents
        missingIgnore     = $missingIgnore
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

    if (Test-Path -LiteralPath $CanvasPath) {
        $canvas = [System.IO.File]::ReadAllText($CanvasPath)
        $begin = '// <meta-ops-snapshot>'
        $end = '// </meta-ops-snapshot>'
        $bi = $canvas.IndexOf($begin)
        $ei = $canvas.IndexOf($end)
        if ($bi -ge 0 -and $ei -gt $bi) {
            $embed = @"
$begin
const SNAPSHOT: MetaSnapshot = $json;
$end
"@
            $updated = $canvas.Substring(0, $bi) + $embed + $canvas.Substring($ei + $end.Length)
            [System.IO.File]::WriteAllText($CanvasPath, $updated)
            Write-Host ("Updated canvas embed: {0}" -f $CanvasPath) -ForegroundColor Green
        }
        else {
            Write-Warning "Canvas found but missing <meta-ops-snapshot> markers: $CanvasPath"
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
    param([Parameter(Mandatory)][string]$Name)
    $trimmed = $Name.Trim()
    if ($trimmed -eq '_meta' -or $trimmed -eq 'meta') { return 'c-Projects-meta' }
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
        if (-not ($wanted | Where-Object { $_ -eq '_meta' -or $_ -eq 'meta' })) {
            $wanted.Add('_meta')
        }
    }

    $seen = @{}
    foreach ($projectName in $wanted) {
        $slug = ConvertTo-MetaCursorProjectSlug -Name $projectName
        if ($seen.ContainsKey($slug)) { continue }
        $seen[$slug] = $true
        $transcriptRoot = Join-Path $cursorProjects (Join-Path $slug 'agent-transcripts')
        if (-not (Test-Path -LiteralPath $transcriptRoot)) { continue }
        [PSCustomObject]@{
            Name           = if ($projectName -eq 'meta') { '_meta' } else { $projectName }
            CursorSlug     = $slug
            TranscriptRoot = $transcriptRoot
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

Export-ModuleMember -Function @(
    'Get-MetaRoot',
    'Get-MetaConfig',
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
    'Invoke-MetaProjectContextAudit',
    'Get-MetaProjectGitCounts',
    'Export-MetaCanvasSnapshot',
    'Get-MetaProjectChats',
    'Get-MetaCursorTranscriptRoots'
)
