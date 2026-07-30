<#
.SYNOPSIS
    Metra CLI for managing sibling projects under configured roots.

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
    .\meta.ps1 snapshot -Quick
    .\meta.ps1 chats -Name Solarwinds -Query "disk alert"
    .\meta.ps1 chats -Name TicketTracker,Solarwinds -Ticket 12345
    .\meta.ps1 roots
    .\meta.ps1 routing
    .\meta.ps1 list -Root personal
    .\meta.ps1 import-profile -Path .\profiles\sample -Preview
    .\meta.ps1 export-profile -Path $env:TEMP\my-meta-profile.zip
    .\meta.ps1 ctx
    .\meta.ps1 ctx -Query "ticket disk"
    .\meta.ps1 verify
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        'list', 'status', 'pull', 'fetch', 'run', 'new', 'apply', 'workspace',
        'audit', 'snapshot', 'chats', 'roots', 'routing',
        'export-profile', 'import-profile', 'ctx', 'verify', 'help'
    )]
    [string]$Command = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Rest,

    [string]$Filter = '*',
    [string[]]$Name,
    [string[]]$Root,
    [string]$Description = '',
    [string]$Template,
    [string]$RelativePath,
    [string]$Path,
    [int]$Months = -1,
    [int]$ScanDepth = -1,
    [string]$Query,
    [string]$Ticket,
    [int]$Days = 90,
    [int]$Limit = 10,
    [ValidateSet('markdown', 'json')]
    [string]$Format = 'markdown',
    [switch]$GitOnly,
    [switch]$Force,
    [switch]$NoGit,
    [switch]$ContinueOnError,
    [switch]$Preview,
    [switch]$DriftOnly,
    [switch]$IncludeMeta,
    [switch]$SharedOnly,
    [switch]$MissingOnly,
    [switch]$Quick
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\Meta.psm1') -Force

function Show-Help {
    @"
Metra CLI - operate on sibling folders under configured project roots.

Usage:
  .\meta.ps1 list [-Filter '*'] [-Root work,personal] [-GitOnly]
  .\meta.ps1 status [-Filter '*'] [-Name ProjA,ProjB] [-Root personal]
  .\meta.ps1 pull [-Filter '*'] [-Root work]
  .\meta.ps1 fetch [-Filter '*'] [-Root work]
  .\meta.ps1 run <command...> [-Filter '*'] [-Name ...] [-Root ...] [-GitOnly] [-ContinueOnError]
  .\meta.ps1 new <ProjectName> [-Description '...'] [-Template basic] [-Root personal] [-NoGit] [-Force]
  .\meta.ps1 apply <SourceFile> [-RelativePath path\in\project] [-Filter '*'] [-Root ...] [-Force]
  .\meta.ps1 workspace [-Months 6] [-ScanDepth 2] [-Preview]
  .\meta.ps1 audit [-Filter '*'] [-Name ProjA,ProjB] [-Root ...] [-DriftOnly] [-ScanDepth 4]
  .\meta.ps1 snapshot [-ScanDepth 2] [-Quick]
  .\meta.ps1 chats [-Name ProjA,ProjB] [-Query 'terms'] [-Ticket 12345] [-Days 90] [-Limit 10] [-IncludeMeta]
  .\meta.ps1 roots
  .\meta.ps1 routing [-Name ProjA] [-SharedOnly] [-MissingOnly]
  .\meta.ps1 export-profile -Path <dir-or-zip>
  .\meta.ps1 import-profile -Path <dir-or-zip> [-Preview] [-Force]
  .\meta.ps1 ctx [-Query 'terms'] [-Path <file|->] [-Format markdown|json] [-Limit 25]
  .\meta.ps1 verify

Roots:
  Projects can live in more than one folder (see roots in meta.config.json).
  A name found in two roots resolves to the earlier root; the later copy is ignored.

Registries:
  projects.json              shared with coworkers (git)
  projects.local.json        machine-private, never committed
  <root>/projects.*.json     travels with that root (registryFile in meta.config.json)

Operator profile:
  profiles/sample/           anonymized pack to import on a new machine
  export-profile             pack local meta.config / projects.local / Metra overlay
  import-profile             restore a pack (refuse overwrite unless -Force)

Examples:
  .\meta.ps1 list -GitOnly
  .\meta.ps1 list -Root personal
  .\meta.ps1 status -Filter 'Colleague*'
  .\meta.ps1 run 'git remote -v' -GitOnly
  .\meta.ps1 new ReportingOps -Description 'Ops scripts for reporting'
  .\meta.ps1 new SermonNotes -Root personal
  .\meta.ps1 apply .\shared\.gitignore -RelativePath .gitignore -Filter 'IWU*'
  .\meta.ps1 workspace
  .\meta.ps1 workspace -Months 3 -Preview
  .\meta.ps1 audit -Name Solarwinds,TicketTracker
  .\meta.ps1 audit -DriftOnly
  .\meta.ps1 routing -MissingOnly
  .\meta.ps1 routing -SharedOnly
  .\meta.ps1 snapshot
  .\meta.ps1 chats -Name Solarwinds -Query 'disk alert'
  .\meta.ps1 chats -Name TicketTracker,Solarwinds -Ticket 12345 -IncludeMeta
  .\meta.ps1 import-profile -Path .\profiles\sample -Preview
  .\meta.ps1 import-profile -Path .\profiles\sample -Force
  .\meta.ps1 export-profile -Path `$env:TEMP\my-meta-profile.zip
  .\meta.ps1 ctx
  .\meta.ps1 ctx -Query 'ticket disk'
  .\meta.ps1 ctx -Format json -Path `$env:TEMP\metra-ctx.json
  .\meta.ps1 verify
"@ | Write-Host
}

switch ($Command) {
    'help' { Show-Help }

    'list' {
        $projects = Get-MetaProjects -Filter $Filter -Root $Root -GitOnly:$GitOnly
        $projects |
            Select-Object Name, Root, IsGit, Path |
            Format-Table -AutoSize
        Write-Host ("{0} project(s) across {1} root(s)" -f $projects.Count, @($projects.Root | Sort-Object -Unique).Count)
    }

    'roots' {
        $roots = @(Get-MetaRoots -IncludeMissing)
        $roots |
            Select-Object Name, Primary, Exists, Optional, Audit, ScanDepth, RegistryFile, Path |
            Format-Table -AutoSize
        $missing = @($roots | Where-Object { -not $_.Exists })
        if ($missing.Count -gt 0) {
            Write-Host ("Not present on this machine: {0}" -f (($missing.Name) -join ', ')) -ForegroundColor Yellow
        }
    }

    'routing' {
        $rows = @(Get-MetaRoutingTable -Name $Name -SharedOnly:$SharedOnly -MissingOnly:$MissingOnly)
        if ($rows.Count -eq 0) {
            Write-Host 'No registry entries matched.' -ForegroundColor Yellow
        }
        else {
            $rows |
                Select-Object Name, Source, Root, Present, Optional,
                    @{ n = 'Triggers'; e = { ($_.Triggers -join ', ') } } |
                Format-Table -AutoSize
            foreach ($row in @($rows | Where-Object { -not $_.Present })) {
                Write-Host ("{0}: {1}" -f $row.Name, $row.Advice) -ForegroundColor Yellow
            }
            Write-Host ("{0} entr(ies); {1} present" -f $rows.Count, @($rows | Where-Object Present).Count)
        }
    }

    'status' {
        Get-MetaStatus -Filter $Filter -Name $Name -Root $Root | Out-Null
    }

    'pull' {
        Update-MetaProjects -Filter $Filter -Name $Name -Root $Root | Out-Null
    }

    'fetch' {
        Update-MetaProjects -Filter $Filter -Name $Name -Root $Root -FetchOnly | Out-Null
    }

    'run' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "run requires a command. Example: .\meta.ps1 run 'git status -sb'"
        }
        $cmdText = ($Rest -join ' ').Trim()
        # Allow callers to pass -- then the command
        if ($cmdText.StartsWith('-- ')) { $cmdText = $cmdText.Substring(3) }
        Invoke-AcrossProjects -Command $cmdText -Filter $Filter -Name $Name -Root $Root -GitOnly:$GitOnly -ContinueOnError:$ContinueOnError |
            Out-Null
    }

    'new' {
        $projectName = $null
        if ($Rest -and $Rest.Count -gt 0) { $projectName = $Rest[0] }
        if (-not $projectName) {
            throw "new requires a project name. Example: .\meta.ps1 new MyProject"
        }
        $newParams = @{
            Name        = $projectName
            Description = $Description
            Template    = $Template
            NoGit       = [bool]$NoGit
            Force       = [bool]$Force
        }
        if ($Root -and $Root.Count -gt 0) { $newParams.Root = $Root[0] }
        New-MetaProject @newParams | Format-List
    }

    'apply' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "apply requires a source file. Example: .\meta.ps1 apply .\shared\.editorconfig"
        }
        $source = $Rest[0]
        Copy-AcrossProjects -Source $source -RelativePath $RelativePath -Filter $Filter -Name $Name -Root $Root -Force:$Force
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
        if ($Root) { $params.Root = $Root }
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        $result = Invoke-MetaProjectContextAudit @params | Select-Object -Last 1
        Write-Host ""
        Write-Host ("Audited {0} project(s); drift signals: {1}" -f $result.ProjectCount, $result.DriftCount)
    }

    'snapshot' {
        $params = @{
            Quick = [bool]$Quick
        }
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

    'export-profile' {
        $exportPath = $Path
        if (-not $exportPath -and $Rest -and $Rest.Count -gt 0) { $exportPath = $Rest[0] }
        if (-not $exportPath) {
            throw "export-profile requires -Path <dir-or-zip>. Example: .\meta.ps1 export-profile -Path `$env:TEMP\my-meta-profile.zip"
        }
        Export-MetaProfile -Path $exportPath | Format-List
    }

    'import-profile' {
        $importPath = $Path
        if (-not $importPath -and $Rest -and $Rest.Count -gt 0) { $importPath = $Rest[0] }
        if (-not $importPath) {
            throw "import-profile requires -Path <dir-or-zip>. Example: .\meta.ps1 import-profile -Path .\profiles\sample -Preview"
        }
        Import-MetaProfile -Path $importPath -Preview:$Preview -Force:$Force | Format-List
    }

    'ctx' {
        $queryText = $Query
        if (-not $queryText -and $Rest -and $Rest.Count -gt 0) {
            $queryText = ($Rest -join ' ').Trim()
        }
        $params = @{
            Format = $Format
        }
        if ($queryText) { $params.Query = $queryText }
        if ($Path) { $params.Path = $Path }
        if ($Limit -gt 0 -and $Limit -ne 10) { $params.Limit = $Limit }
        # Default Limit for ctx is 25; meta.ps1 default Limit is 10 for chats.
        if (-not $PSBoundParameters.ContainsKey('Limit')) {
            $params.Limit = 25
        }
        else {
            $params.Limit = $Limit
        }
        Export-MetaContextPack @params | Format-List
    }

    'verify' {
        $report = Invoke-MetaVerify
        $report.Results |
            Select-Object Status, Name, Detail |
            Format-Table -AutoSize
        Write-Host ("PASS={0} WARN={1} FAIL={2}" -f $report.PassCount, $report.WarnCount, $report.FailCount)
        if (-not $report.Ok) {
            exit 1
        }
    }
}
