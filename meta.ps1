<#
.SYNOPSIS
    Meta CLI for managing sibling projects under C:\Projects.

.EXAMPLE
    .\meta.ps1 list
    .\meta.ps1 status
    .\meta.ps1 pull
    .\meta.ps1 new MyApp -Description "Demo app"
    .\meta.ps1 run "git status -sb"
    .\meta.ps1 run -Filter "IWU*" "git pull --ff-only"
    .\meta.ps1 apply .\shared\.editorconfig -RelativePath .editorconfig
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('list', 'status', 'pull', 'fetch', 'run', 'new', 'apply', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Rest,

    [string]$Filter = '*',
    [string[]]$Name,
    [string]$Description = '',
    [string]$Template,
    [string]$RelativePath,
    [switch]$GitOnly,
    [switch]$Force,
    [switch]$NoGit,
    [switch]$ContinueOnError
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\Meta.psm1') -Force

function Show-Help {
    @"
Meta repo CLI - operate on sibling folders under the projects root.

Usage:
  .\meta.ps1 list [-Filter '*'] [-GitOnly]
  .\meta.ps1 status [-Filter '*'] [-Name ProjA,ProjB]
  .\meta.ps1 pull [-Filter '*']
  .\meta.ps1 fetch [-Filter '*']
  .\meta.ps1 run <command...> [-Filter '*'] [-Name ...] [-GitOnly] [-ContinueOnError]
  .\meta.ps1 new <ProjectName> [-Description '...'] [-Template basic] [-NoGit] [-Force]
  .\meta.ps1 apply <SourceFile> [-RelativePath path\in\project] [-Filter '*'] [-Force]

Examples:
  .\meta.ps1 list -GitOnly
  .\meta.ps1 status -Filter 'Colleague*'
  .\meta.ps1 run 'git remote -v' -GitOnly
  .\meta.ps1 new ReportingOps -Description 'Ops scripts for reporting'
  .\meta.ps1 apply .\shared\.gitignore -RelativePath .gitignore -Filter 'IWU*'
"@ | Write-Host
}

switch ($Command) {
    'help' { Show-Help }

    'list' {
        $projects = Get-MetaProjects -Filter $Filter -GitOnly:$GitOnly
        $projects |
            Select-Object Name, IsGit, Path |
            Format-Table -AutoSize
        Write-Host ("{0} project(s)" -f $projects.Count)
    }

    'status' {
        Get-MetaStatus -Filter $Filter -Name $Name | Out-Null
    }

    'pull' {
        Update-MetaProjects -Filter $Filter -Name $Name | Out-Null
    }

    'fetch' {
        Update-MetaProjects -Filter $Filter -Name $Name -FetchOnly | Out-Null
    }

    'run' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "run requires a command. Example: .\meta.ps1 run 'git status -sb'"
        }
        $cmdText = ($Rest -join ' ').Trim()
        # Allow callers to pass -- then the command
        if ($cmdText.StartsWith('-- ')) { $cmdText = $cmdText.Substring(3) }
        Invoke-AcrossProjects -Command $cmdText -Filter $Filter -Name $Name -GitOnly:$GitOnly -ContinueOnError:$ContinueOnError |
            Out-Null
    }

    'new' {
        $projectName = $null
        if ($Rest -and $Rest.Count -gt 0) { $projectName = $Rest[0] }
        if (-not $projectName) {
            throw "new requires a project name. Example: .\meta.ps1 new MyProject"
        }
        New-MetaProject -Name $projectName -Description $Description -Template $Template -NoGit:$NoGit -Force:$Force |
            Format-List
    }

    'apply' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "apply requires a source file. Example: .\meta.ps1 apply .\shared\.editorconfig"
        }
        $source = $Rest[0]
        Copy-AcrossProjects -Source $source -RelativePath $RelativePath -Filter $Filter -Name $Name -Force:$Force
    }
}
