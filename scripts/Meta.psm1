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

Export-ModuleMember -Function @(
    'Get-MetaRoot',
    'Get-MetaConfig',
    'Get-ProjectsRoot',
    'Get-MetaProjects',
    'Invoke-AcrossProjects',
    'Get-MetaStatus',
    'Update-MetaProjects',
    'Copy-AcrossProjects',
    'New-MetaProject'
)
