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
    .\meta.ps1 workspace
    .\meta.ps1 workspace -Months 6
    .\meta.ps1 audit
    .\meta.ps1 audit -Name Solarwinds,TicketTracker
    .\meta.ps1 audit -DriftOnly
    .\meta.ps1 snapshot
    .\meta.ps1 chats -Name Solarwinds -Query "disk alert"
    .\meta.ps1 chats -Name TicketTracker,Solarwinds -Ticket 12345
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('list', 'status', 'pull', 'fetch', 'run', 'new', 'apply', 'workspace', 'audit', 'snapshot', 'chats', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Rest,

    [string]$Filter = '*',
    [string[]]$Name,
    [string]$Description = '',
    [string]$Template,
    [string]$RelativePath,
    [int]$Months = -1,
    [int]$ScanDepth = -1,
    [string]$Query,
    [string]$Ticket,
    [int]$Days = 90,
    [int]$Limit = 10,
    [switch]$GitOnly,
    [switch]$Force,
    [switch]$NoGit,
    [switch]$ContinueOnError,
    [switch]$Preview,
    [switch]$DriftOnly,
    [switch]$IncludeMeta
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
  .\meta.ps1 workspace [-Months 6] [-ScanDepth 2] [-Preview]
  .\meta.ps1 audit [-Filter '*'] [-Name ProjA,ProjB] [-DriftOnly] [-ScanDepth 4]
  .\meta.ps1 snapshot [-ScanDepth 2]
  .\meta.ps1 chats [-Name ProjA,ProjB] [-Query 'terms'] [-Ticket 12345] [-Days 90] [-Limit 10] [-IncludeMeta]

Examples:
  .\meta.ps1 list -GitOnly
  .\meta.ps1 status -Filter 'Colleague*'
  .\meta.ps1 run 'git remote -v' -GitOnly
  .\meta.ps1 new ReportingOps -Description 'Ops scripts for reporting'
  .\meta.ps1 apply .\shared\.gitignore -RelativePath .gitignore -Filter 'IWU*'
  .\meta.ps1 workspace
  .\meta.ps1 workspace -Months 3 -Preview
  .\meta.ps1 audit -Name Solarwinds,TicketTracker
  .\meta.ps1 audit -DriftOnly
  .\meta.ps1 snapshot
  .\meta.ps1 chats -Name Solarwinds -Query 'disk alert'
  .\meta.ps1 chats -Name TicketTracker,Solarwinds -Ticket 12345 -IncludeMeta
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

    'workspace' {
        $params = @{
            WhatIfPreview = [bool]$Preview
        }
        if ($Months -ge 0) { $params.Months = $Months }
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        Update-MetaWorkspace @params | Format-List
    }

    'audit' {
        $params = @{
            Filter    = $Filter
            DriftOnly = [bool]$DriftOnly
        }
        if ($Name) { $params.Name = $Name }
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        $result = Invoke-MetaProjectContextAudit @params | Select-Object -Last 1
        Write-Host ""
        Write-Host ("Audited {0} project(s); drift signals: {1}" -f $result.ProjectCount, $result.DriftCount)
    }

    'snapshot' {
        $params = @{}
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        Export-MetaCanvasSnapshot @params | Format-List
    }

    'chats' {
        # Allow: .\meta.ps1 chats "disk alert" -Name Solarwinds
        $queryText = $Query
        if (-not $queryText -and $Rest -and $Rest.Count -gt 0 -and -not $Ticket) {
            $queryText = ($Rest -join ' ').Trim()
        }
        $params = @{
            Days        = $Days
            Limit       = $Limit
            IncludeMeta = [bool]$IncludeMeta
        }
        if ($Name) { $params.Name = $Name }
        if ($queryText) { $params.Query = $queryText }
        if ($Ticket) { $params.Ticket = $Ticket }
        $rows = @(Get-MetaProjectChats @params)
        if ($rows.Count -eq 0) {
            Write-Host 'No matching chats (try broader -Query, more -Days, or other -Name projects).' -ForegroundColor Yellow
        }
        else {
            $rows |
                Select-Object Project, ChatId, Modified, MatchedTerms, Title, Snippet1, Cite |
                Format-List
            Write-Host ("{0} chat(s). Cite with [title](ChatId); promote useful findings via TicketTracker note -Tags chat." -f $rows.Count)
        }
    }
}
