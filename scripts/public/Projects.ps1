# Generated from the original Metra.psm1 domain split. Edit this file directly.

function New-MetraProject {
    <#
    .SYNOPSIS
        Creates a project under a configured Metra root.
    .DESCRIPTION
        Creates a folder from a Metra template, replaces template tokens, adds a README
        when needed, and initializes a Git repository unless NoGit is specified.
        Supports -WhatIf / -Confirm.
    .PARAMETER Name
        Name of the new project folder (required; not null or empty).
    .PARAMETER Description
        Description used for the README and template token replacement.
    .PARAMETER Template
        Single-segment template folder name under the configured templates directory
        (letters, digits, dot, underscore, hyphen only). Uses defaultTemplate from
        metra.config.json when omitted.
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
    .EXAMPLE
        New-MetraProject -Name ScratchOps -WhatIf
    .OUTPUTS
        PSCustomObject describing the created project.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$Description = '',

        [string]$Template,

        [string]$Root,

        [switch]$NoGit,

        [switch]$Force
    )

    $cfg = Get-MetraConfig
    $metraRoot = Get-MetraRoot
    $Name = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Name cannot be empty or whitespace.'
    }

    if ($Root) {
        $targetRoot = @(Get-MetraRoots -Name $Root -IncludeMissing) | Select-Object -First 1
        if (-not $targetRoot) {
            throw ("Unknown root '{0}'." -f $Root)
        }
        if (-not $targetRoot.Exists) {
            throw ("Root '{0}' is not available on this machine: {1}" -f $targetRoot.Name, $targetRoot.Path)
        }
        $projectsRoot = $targetRoot.Path
        $rootName = [string]$targetRoot.Name
    }
    else {
        $primary = @(Get-MetraRoots -IncludeMissing | Where-Object { $_.Primary }) | Select-Object -First 1
        if (-not $primary) {
            $primary = @(Get-MetraRoots -IncludeMissing) | Select-Object -First 1
        }
        if (-not $primary -or -not $primary.Exists) {
            throw 'No primary project root is available on this machine.'
        }
        $projectsRoot = $primary.Path
        $rootName = [string]$primary.Name
    }

    if ($Name -match '[\\/:*?"<>|]') {
        throw "Invalid project name: $Name"
    }

    $target = Join-Path $projectsRoot $Name
    if ((Test-Path -LiteralPath $target) -and -not $Force) {
        throw "Project already exists: $target (use -Force to reuse)"
    }

    $templateName = if (-not [string]::IsNullOrWhiteSpace($Template)) { $Template.Trim() } else { [string]$cfg.defaultTemplate }
    if ([string]::IsNullOrWhiteSpace($templateName)) {
        throw 'Template name is missing and metra.config.json defaultTemplate is not set.'
    }
    if ($templateName -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Invalid template name: $templateName"
    }

    $templatesRoot = Join-Path $metraRoot ([string]$cfg.templatesDir)
    $templateDir = Join-Path $templatesRoot $templateName
    if (-not (Test-MetraPathWithinRoot -Path $templateDir -Root $templatesRoot)) {
        throw "Template path escapes templates directory: $templateDir"
    }

    $descLine = if ($Description) { $Description } else { "Project $Name" }
    $action = if ((Test-Path -LiteralPath $target)) { "Reuse project folder $target" } else { "Create project $target" }

    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        return
    }

    if (-not (Test-Path -LiteralPath $target)) {
        [void][System.IO.Directory]::CreateDirectory($target)
    }

    if (Test-Path -LiteralPath $templateDir) {
        Copy-Item -Path (Join-Path $templateDir '*') -Destination $target -Recurse -Force
        Get-ChildItem -LiteralPath $target -Recurse -File | ForEach-Object {
            $text = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
            if ($null -eq $text) { return }
            if ($text -notmatch '\{\{ProjectName\}\}|\{\{Description\}\}') { return }
            $updated = $text.
                Replace('{{ProjectName}}', $Name).
                Replace('{{Description}}', $descLine)
            Set-Content -LiteralPath $_.FullName -Value $updated -Encoding UTF8 -NoNewline
        }
    }
    else {
        Write-Warning "Template not found: $templateDir (creating empty project)"
    }

    $readme = Join-Path $target 'README.md'
    if (-not (Test-Path -LiteralPath $readme)) {
        @"
# $Name

$descLine
"@ | Set-Content -LiteralPath $readme -Encoding UTF8
    }

    if (-not $NoGit) {
        $gitDir = Join-Path $target '.git'
        if (-not (Test-Path -LiteralPath $gitDir)) {
            git -C $target init | Out-Null
            git -C $target add .
            $msg = "Initial commit for $Name"
            git -C $target commit -m $msg 2>$null | Out-Null
        }
    }

    Write-Host ("Created project: {0}" -f $target) -ForegroundColor Green
    return [PSCustomObject]@{
        Name     = $Name
        Path     = $target
        Root     = $rootName
        Template = $templateName
        IsGit    = (Test-Path -LiteralPath (Join-Path $target '.git'))
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
        Wildcard applied to project folder names (not -Name).
    .PARAMETER Name
        One or more exact project names. Wildcards are not supported (use -Filter for wildcards).
        Accepts pipeline input by value (string) or by property name (Name).
        Tab completion uses projects found on disk.
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
    .EXAMPLE
        'TicketTracker', 'Solarwinds' | Get-MetraProject
    .OUTPUTS
        PSCustomObject with Name, Path, IsGit, Root, Primary, and Shadowed properties.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Filter = '*',

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [string[]]$Root,

        [switch]$GitOnly,

        [switch]$IncludeShadowed
    )

    begin {
        $nameBuf = New-Object System.Collections.Generic.List[string]
    }
    process {
        foreach ($n in @($Name)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$n)) {
                [void]$nameBuf.Add([string]$n)
            }
        }
    }
    end {
        $params = @{
            Filter          = $Filter
            GitOnly         = [bool]$GitOnly
            IncludeShadowed = [bool]$IncludeShadowed
        }
        if ($Root) { $params.Root = $Root }

        $projects = @(Get-MetraProjects @params)
        if ($nameBuf.Count -gt 0) {
            $wanted = @($nameBuf | ForEach-Object { $_.ToLowerInvariant() })
            $projects = @($projects | Where-Object { $wanted -contains $_.Name.ToLowerInvariant() })
        }
        return $projects
    }
}

function Get-MetraProjectRoot {
    <#
    .SYNOPSIS
        Gets configured project roots and their availability.
    .DESCRIPTION
        Resolves configured root paths, expands environment variables, and reports whether
        each root exists on the current machine.
    .PARAMETER Name
        One or more exact configured root names. Accepts pipeline input by value or property name.
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
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [switch]$IncludeMissing
    )

    begin {
        $nameBuf = New-Object System.Collections.Generic.List[string]
    }
    process {
        foreach ($n in @($Name)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$n)) {
                [void]$nameBuf.Add([string]$n)
            }
        }
    }
    end {
        $params = @{}
        if ($nameBuf.Count -gt 0) { $params.Name = @($nameBuf.ToArray()) }
        if ($IncludeMissing) { $params.IncludeMissing = $true }
        Get-MetraRoots @params
    }
}

function Get-MetraProjectStatus {
    <#
    .SYNOPSIS
        Gets git status from matching projects.
    .DESCRIPTION
        Runs git status -sb in every matching Git project. A failed project is returned
        as an unsuccessful result without stopping the remaining projects.
    .PARAMETER Filter
        Wildcard applied to project folder names (not -Name).
    .PARAMETER Name
        One or more exact project names. Wildcards are not supported (use -Filter).
        Accepts pipeline input by value (string) or by property name (Name).
    .PARAMETER Root
        One or more configured root names.
    .EXAMPLE
        Get-MetraProjectStatus -Name TicketTracker,Solarwinds
    .EXAMPLE
        Get-MetraProject -Name TicketTracker | Get-MetraProjectStatus
    .OUTPUTS
        PSCustomObject with project identity, exit code, success state, and command output.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Filter = '*',

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [string[]]$Root
    )

    begin {
        $nameBuf = New-Object System.Collections.Generic.List[string]
    }
    process {
        foreach ($n in @($Name)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$n)) {
                [void]$nameBuf.Add([string]$n)
            }
        }
    }
    end {
        $params = @{ Filter = $Filter }
        if ($nameBuf.Count -gt 0) { $params.Name = @($nameBuf.ToArray()) }
        if ($Root) { $params.Root = $Root }
        Get-MetraStatus @params
    }
}

function Update-MetraProject {
    <#
    .SYNOPSIS
        Pulls or fetches matching git projects.
    .DESCRIPTION
        Runs git pull --ff-only by default. FetchOnly runs git fetch --all --prune.
        Processing continues when an individual repository fails. Supports -WhatIf / -Confirm.
    .PARAMETER Filter
        Wildcard applied to project folder names (not -Name).
    .PARAMETER Name
        One or more exact project names. Wildcards are not supported (use -Filter).
        Accepts pipeline input by value (string) or by property name (Name).
    .PARAMETER Root
        One or more configured root names.
    .PARAMETER FetchOnly
        Fetches and prunes remotes without changing working branches.
    .EXAMPLE
        Update-MetraProject -Root work
    .EXAMPLE
        Update-MetraProject -Name Reporting -FetchOnly
    .EXAMPLE
        Get-MetraProject -Name Reporting | Update-MetraProject -WhatIf
    .OUTPUTS
        PSCustomObject with project identity, exit code, success state, and command output.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [string]$Filter = '*',

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [string[]]$Root,

        [switch]$FetchOnly
    )

    begin {
        $nameBuf = New-Object System.Collections.Generic.List[string]
    }
    process {
        foreach ($n in @($Name)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$n)) {
                [void]$nameBuf.Add([string]$n)
            }
        }
    }
    end {
        $params = @{ Filter = $Filter }
        if ($nameBuf.Count -gt 0) { $params.Name = @($nameBuf.ToArray()) }
        if ($Root) { $params.Root = $Root }
        if ($FetchOnly) { $params.FetchOnly = $true }
        $params.WhatIf = [bool]$WhatIfPreference
        if ($PSBoundParameters.ContainsKey('Confirm')) { $params.Confirm = $Confirm }
        Update-MetraProjects @params
    }
}

function Invoke-MetraProjectCommand {
    <#
    .SYNOPSIS
        Runs a command or script block in matching projects.
    .DESCRIPTION
        Changes to each matching project directory and runs trusted operator-provided content.
        -Command is a simple whitespace-separated executable and arguments (never Invoke-Expression).
        Prefer -ScriptBlock for PowerShell. See SECURITY.md. Supports -WhatIf / -Confirm.
    .PARAMETER Command
        Whitespace-separated executable and arguments to run in each project directory.
        Quoting is not shell-compatible. For arguments containing spaces or shell-style
        quoting, use -ScriptBlock instead.
    .PARAMETER ScriptBlock
        Script block to invoke in each project directory.
    .PARAMETER Filter
        Wildcard applied to project folder names (not -Name).
    .PARAMETER Name
        One or more exact project names. Wildcards are not supported (use -Filter).
        Accepts pipeline input by value (string) or by property name (Name).
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
    .EXAMPLE
        Get-MetraProject -Name TicketTracker | Invoke-MetraProjectCommand -Command 'git status -sb' -WhatIf
    .OUTPUTS
        PSCustomObject with project identity, exit code, success state, and captured output.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Command', SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Command', Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [Parameter(ParameterSetName = 'Script', Mandatory)]
        [scriptblock]$ScriptBlock,

        [string]$Filter = '*',

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [string[]]$Root,

        [switch]$GitOnly,

        [switch]$ContinueOnError,

        [switch]$Quiet
    )

    begin {
        $nameBuf = New-Object System.Collections.Generic.List[string]
    }
    process {
        foreach ($n in @($Name)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$n)) {
                [void]$nameBuf.Add([string]$n)
            }
        }
    }
    end {
        $params = @{ Filter = $Filter }
        if ($nameBuf.Count -gt 0) { $params.Name = @($nameBuf.ToArray()) }
        if ($Root) { $params.Root = $Root }
        if ($GitOnly) { $params.GitOnly = $true }
        if ($ContinueOnError) { $params.ContinueOnError = $true }
        if ($Quiet) { $params.Quiet = $true }

        if ($PSCmdlet.ParameterSetName -eq 'Script') {
            $params.ScriptBlock = $ScriptBlock
        }
        else {
            $params.Command = $Command
        }

        $params.WhatIf = [bool]$WhatIfPreference
        if ($PSBoundParameters.ContainsKey('Confirm')) { $params.Confirm = $Confirm }
        Invoke-AcrossProjects @params
    }
}

function Copy-MetraProjectFile {
    <#
    .SYNOPSIS
        Copies a file into matching projects.
    .DESCRIPTION
        Copies one source file to a relative destination in each matching project. Supports
        PowerShell WhatIf and Confirm semantics. Source must exist as a file.
    .PARAMETER Source
        Source file to copy.
    .PARAMETER RelativePath
        Destination path relative to each project root (no rooted paths, no '..' segments).
        Defaults to the source file name.
    .PARAMETER Filter
        Wildcard applied to project folder names (not -Name).
    .PARAMETER Name
        One or more exact project names. Wildcards are not supported (use -Filter).
        Accepts pipeline input by value (string) or by property name (Name).
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
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [string]$RelativePath,

        [string]$Filter = '*',

        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [string[]]$Root,

        [switch]$Force
    )

    begin {
        $nameBuf = New-Object System.Collections.Generic.List[string]
    }
    process {
        foreach ($n in @($Name)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$n)) {
                [void]$nameBuf.Add([string]$n)
            }
        }
    }
    end {
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
            throw ("Source file not found: {0}" -f $Source)
        }

        if (-not [string]::IsNullOrWhiteSpace($RelativePath)) {
            if ([System.IO.Path]::IsPathRooted($RelativePath)) {
                throw "RelativePath must be relative, not rooted: $RelativePath"
            }
            if (($RelativePath -split '[\\/]') -contains '..') {
                throw "RelativePath cannot contain '..': $RelativePath"
            }
            if ($RelativePath -match '[\x00-\x1F]') {
                throw 'RelativePath contains invalid control characters.'
            }
        }

        $params = @{
            Source = $Source
            Filter = $Filter
            WhatIf = [bool]$WhatIfPreference
        }
        if (-not [string]::IsNullOrWhiteSpace($RelativePath)) { $params.RelativePath = $RelativePath }
        if ($nameBuf.Count -gt 0) { $params.Name = @($nameBuf.ToArray()) }
        if ($Root) { $params.Root = $Root }
        if ($Force) { $params.Force = $true }
        if ($PSBoundParameters.ContainsKey('Confirm')) { $params.Confirm = $Confirm }
        Copy-AcrossProjects @params
    }
}
