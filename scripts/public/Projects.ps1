# Generated from the original Metra.psm1 domain split. Edit this file directly.

function New-MetraProject {
    <#
    .SYNOPSIS
        Creates a project under a configured Metra root.
    .DESCRIPTION
        Creates a folder from a Metra template, replaces template tokens, adds a README
        when needed, and initializes a Git repository unless NoGit is specified.
    .PARAMETER Name
        Name of the new project folder.
    .PARAMETER Description
        Description used for the README and template token replacement.
    .PARAMETER Template
        Template folder name under the configured templates directory. Uses defaultTemplate
        from metra.config.json when omitted.
    .PARAMETER Root
        Configured root name in which to create the project. Uses the primary root by default.
    .PARAMETER NoGit
        Creates the project without initializing a Git repository.
    .PARAMETER Force
        Reuses an existing folder and allows template files to be overwritten.
    .EXAMPLE
        New-MetraProject -Name ReportingOps -Description 'Reporting operations scripts'
    .EXAMPLE
        New-MetraProject -Name PersonalNotes -Root personal -NoGit
    .OUTPUTS
        PSCustomObject describing the created project.
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

    $cfg = Get-MetraConfig
    $metraRoot = Get-MetraRoot

    if ($Root) {
        $targetRoot = @(Get-MetraRoots -Name $Root -IncludeMissing) | Select-Object -First 1
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
    $templateDir = Join-Path $metraRoot (Join-Path $cfg.templatesDir $templateName)

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

function Get-MetraProject {
    <#
    .SYNOPSIS
        Gets project directories from configured Metra roots.
    .DESCRIPTION
        Scans roots in configuration order. The first project with a given name wins unless
        IncludeShadowed is used. Results are objects suitable for filtering and pipelines.
    .PARAMETER Filter
        Wildcard applied to project folder names.
    .PARAMETER Name
        One or more exact project names. Tab completion uses projects found on disk.
    .PARAMETER Root
        One or more configured root names. Tab completion uses metra.config.json.
    .PARAMETER GitOnly
        Returns only folders containing a .git entry.
    .PARAMETER IncludeShadowed
        Includes duplicate project names found in later roots.
    .EXAMPLE
        Get-MetraProject -Root work -GitOnly
    .EXAMPLE
        Get-MetraProject -Name TicketTracker,Solarwinds
    .OUTPUTS
        PSCustomObject with Name, Path, IsGit, Root, Primary, and Shadowed properties.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$GitOnly,
        [switch]$IncludeShadowed
    )

    $params = @{
        Filter          = $Filter
        GitOnly         = [bool]$GitOnly
        IncludeShadowed = [bool]$IncludeShadowed
    }
    if ($Root) { $params.Root = $Root }

    $projects = @(Get-MetraProjects @params)
    if ($Name) {
        $wanted = @($Name | ForEach-Object { $_.ToLowerInvariant() })
        $projects = @($projects | Where-Object { $wanted -contains $_.Name.ToLowerInvariant() })
    }
    return $projects
}

function Get-MetraProjectRoot {
    <#
    .SYNOPSIS
        Gets configured project roots and their availability.
    .DESCRIPTION
        Resolves configured root paths, expands environment variables, and reports whether
        each root exists on the current machine.
    .PARAMETER Name
        One or more exact configured root names.
    .PARAMETER IncludeMissing
        Includes optional roots that are not present on this machine.
    .EXAMPLE
        Get-MetraProjectRoot -IncludeMissing
    .EXAMPLE
        Get-MetraProjectRoot -Name work
    .OUTPUTS
        PSCustomObject describing each configured root.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [switch]$IncludeMissing
    )

    Get-MetraRoots @PSBoundParameters
}

function Get-MetraProjectStatus {
    <#
    .SYNOPSIS
        Gets git status from matching projects.
    .DESCRIPTION
        Runs git status -sb in every matching Git project. A failed project is returned
        as an unsuccessful result without stopping the remaining projects.
    .PARAMETER Filter
        Wildcard applied to project folder names.
    .PARAMETER Name
        One or more exact project names.
    .PARAMETER Root
        One or more configured root names.
    .EXAMPLE
        Get-MetraProjectStatus -Name TicketTracker,Solarwinds
    .OUTPUTS
        PSCustomObject with project identity, exit code, success state, and command output.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root
    )

    Get-MetraStatus @PSBoundParameters
}

function Update-MetraProject {
    <#
    .SYNOPSIS
        Pulls or fetches matching git projects.
    .DESCRIPTION
        Runs git pull --ff-only by default. FetchOnly runs git fetch --all --prune.
        Processing continues when an individual repository fails.
    .PARAMETER Filter
        Wildcard applied to project folder names.
    .PARAMETER Name
        One or more exact project names.
    .PARAMETER Root
        One or more configured root names.
    .PARAMETER FetchOnly
        Fetches and prunes remotes without changing working branches.
    .EXAMPLE
        Update-MetraProject -Root work
    .EXAMPLE
        Update-MetraProject -Name Reporting -FetchOnly
    .OUTPUTS
        PSCustomObject with project identity, exit code, success state, and command output.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$FetchOnly
    )

    Update-MetraProjects @PSBoundParameters
}

function Invoke-MetraProjectCommand {
    <#
    .SYNOPSIS
        Runs a command or script block in matching projects.
    .DESCRIPTION
        Changes to each matching project directory and invokes trusted operator-provided
        content. Command text is evaluated as PowerShell and must not contain untrusted input.
    .PARAMETER Command
        PowerShell command text to evaluate in each project directory.
    .PARAMETER ScriptBlock
        Script block to invoke in each project directory.
    .PARAMETER Filter
        Wildcard applied to project folder names.
    .PARAMETER Name
        One or more exact project names.
    .PARAMETER Root
        One or more configured root names.
    .PARAMETER GitOnly
        Runs only in projects containing a .git entry.
    .PARAMETER ContinueOnError
        Continues after a terminating error in an individual project.
    .PARAMETER Quiet
        Suppresses per-project headings and command output written to the host.
    .EXAMPLE
        Invoke-MetraProjectCommand -Command 'git remote -v' -GitOnly
    .EXAMPLE
        Invoke-MetraProjectCommand -ScriptBlock { Get-ChildItem -Filter AGENTS.md } -Root work
    .OUTPUTS
        PSCustomObject with project identity, exit code, success state, and captured output.
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

    Invoke-AcrossProjects @PSBoundParameters
}

function Copy-MetraProjectFile {
    <#
    .SYNOPSIS
        Copies a file into matching projects.
    .DESCRIPTION
        Copies one source file to a relative destination in each matching project. Supports
        PowerShell WhatIf and Confirm semantics.
    .PARAMETER Source
        Source file to copy.
    .PARAMETER RelativePath
        Destination path relative to each project root. Defaults to the source file name.
    .PARAMETER Filter
        Wildcard applied to project folder names.
    .PARAMETER Name
        One or more exact project names.
    .PARAMETER Root
        One or more configured root names.
    .PARAMETER Force
        Allows an existing destination file to be overwritten.
    .EXAMPLE
        Copy-MetraProjectFile -Source .\shared\.editorconfig -Name App1,App2
    .EXAMPLE
        Copy-MetraProjectFile -Source .\shared\.gitignore -Root work -WhatIf
    .OUTPUTS
        None.
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

    Copy-AcrossProjects @PSBoundParameters
}

