<#
.SYNOPSIS
    Metra CLI for managing sibling projects under configured roots.

.EXAMPLE
    .\metra.ps1 list
    .\metra.ps1 status
    .\metra.ps1 pull
    .\metra.ps1 new MyApp -Description "Demo app"
    .\metra.ps1 run "git status -sb"
    .\metra.ps1 run -Filter "IWU*" "git pull --ff-only"
    .\metra.ps1 apply .\shared\.editorconfig -RelativePath .editorconfig
    .\metra.ps1 workspace
    .\metra.ps1 workspace -Months 6
    .\metra.ps1 audit
    .\metra.ps1 audit -Name Solarwinds,TicketTracker
    .\metra.ps1 audit -DriftOnly
    .\metra.ps1 snapshot
    .\metra.ps1 snapshot -Quick
    .\metra.ps1 chats -Name Solarwinds -Query "disk alert"
    .\metra.ps1 chats -Name TicketTracker,Solarwinds -Ticket 12345
    .\metra.ps1 roots
    .\metra.ps1 routing
    .\metra.ps1 list -Root personal
    .\metra.ps1 import-profile -Path .\profiles\sample -Preview
    .\metra.ps1 export-profile -Path $env:TEMP\my-metra-profile.zip
    .\metra.ps1 ctx
    .\metra.ps1 ctx -Query "ticket disk"
    .\metra.ps1 ctx -IncludeAgent
    .\metra.ps1 setup
    .\metra.ps1 setup -Profile .\profiles\sample -Force
    .\metra.ps1 verify
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        'list', 'status', 'pull', 'fetch', 'run', 'new', 'apply', 'workspace',
        'audit', 'snapshot', 'chats', 'roots', 'routing',
        'export-profile', 'import-profile', 'ctx', 'setup', 'verify', 'help'
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
    [string]$Profile,
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
    [Alias('IncludeMeta')]
    [switch]$IncludeMetra,
    [switch]$SharedOnly,
    [switch]$MissingOnly,
    [switch]$Quick,
    [switch]$IncludeAgent
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\Metra.psd1') -Force

function Show-Help {
    @"
Metra CLI - operate on sibling folders under configured project roots.

Usage:
  .\metra.ps1 list [-Filter '*'] [-Root work,personal] [-GitOnly]
  .\metra.ps1 status [-Filter '*'] [-Name ProjA,ProjB] [-Root personal]
  .\metra.ps1 pull [-Filter '*'] [-Root work]
  .\metra.ps1 fetch [-Filter '*'] [-Root work]
  .\metra.ps1 run <command...> [-Filter '*'] [-Name ...] [-Root ...] [-GitOnly] [-ContinueOnError]
      Runs operator-provided shell text in each matching project (trusted input only - see SECURITY.md).
  .\metra.ps1 new <ProjectName> [-Description '...'] [-Template basic] [-Root personal] [-NoGit] [-Force]
  .\metra.ps1 apply <SourceFile> [-RelativePath path\in\project] [-Filter '*'] [-Root ...] [-Force]
  .\metra.ps1 workspace [-Months 6] [-ScanDepth 2] [-Preview]
  .\metra.ps1 audit [-Filter '*'] [-Name ProjA,ProjB] [-Root ...] [-DriftOnly] [-ScanDepth 4]
  .\metra.ps1 snapshot [-ScanDepth 2] [-Quick]
  .\metra.ps1 chats [-Name ProjA,ProjB] [-Query 'terms'] [-Ticket 12345] [-Days 90] [-Limit 10] [-IncludeMetra]
  .\metra.ps1 roots
  .\metra.ps1 routing [-Name ProjA] [-SharedOnly] [-MissingOnly]
  .\metra.ps1 export-profile -Path <dir-or-zip>
  .\metra.ps1 import-profile -Path <dir-or-zip> [-Preview] [-Force]
  .\metra.ps1 ctx [-Query 'terms'] [-Path <file|->] [-Format markdown|json] [-Limit 25] [-IncludeAgent]
  .\metra.ps1 setup [-Profile <dir-or-zip>] [-Force] [-Preview] [-Months 6] [-ScanDepth 2]
      One-shot onboarding: seed config if missing, optional profile, roots, workspace, routing, ctx.
  .\metra.ps1 verify

Roots:
  Projects can live in more than one folder (see roots in metra.config.json).
  A name found in two roots resolves to the earlier root; the later copy is ignored.

Registries:
  projects.json              shared with coworkers (git)
  projects.local.json        machine-private, never committed
  <root>/projects.*.json     travels with that root (registryFile in metra.config.json)

Operator profile:
  profiles/sample/           anonymized pack to import on a new machine
  export-profile             pack local metra.config / projects.local / Metra overlay (+ humor add-on if present)
  import-profile             restore a pack (refuse overwrite unless -Force)

Examples:
  .\metra.ps1 list -GitOnly
  .\metra.ps1 list -Root personal
  .\metra.ps1 status -Filter 'Colleague*'
  .\metra.ps1 run 'git remote -v' -GitOnly
  .\metra.ps1 new ReportingOps -Description 'Ops scripts for reporting'
  .\metra.ps1 new SermonNotes -Root personal
  .\metra.ps1 apply .\shared\.gitignore -RelativePath .gitignore -Filter 'IWU*'
  .\metra.ps1 workspace
  .\metra.ps1 workspace -Months 3 -Preview
  .\metra.ps1 audit -Name Solarwinds,TicketTracker
  .\metra.ps1 audit -DriftOnly
  .\metra.ps1 routing -MissingOnly
  .\metra.ps1 routing -SharedOnly
  .\metra.ps1 snapshot
  .\metra.ps1 chats -Name Solarwinds -Query 'disk alert'
  .\metra.ps1 chats -Name TicketTracker,Solarwinds -Ticket 12345 -IncludeMetra
  .\metra.ps1 import-profile -Path .\profiles\sample -Preview
  .\metra.ps1 import-profile -Path .\profiles\sample -Force
  .\metra.ps1 export-profile -Path `$env:TEMP\my-metra-profile.zip
  .\metra.ps1 ctx
  .\metra.ps1 ctx -Query 'ticket disk'
  .\metra.ps1 ctx -IncludeAgent
  .\metra.ps1 ctx -Format json -Path `$env:TEMP\metra-ctx.json
  .\metra.ps1 setup
  .\metra.ps1 setup -Profile .\profiles\sample -Force
  .\metra.ps1 setup -Preview
  .\metra.ps1 verify
"@ | Write-Host
}

switch ($Command) {
    'help' { Show-Help }

    'list' {
        $projects = Get-MetraProject -Filter $Filter -Root $Root -GitOnly:$GitOnly
        $projects |
            Select-Object Name, Root, IsGit, Path |
            Format-Table -AutoSize
        Write-Host ("{0} project(s) across {1} root(s)" -f $projects.Count, @($projects.Root | Sort-Object -Unique).Count)
    }

    'roots' {
        $roots = @(Get-MetraProjectRoot -IncludeMissing)
        $roots |
            Select-Object Name, Primary, Exists, Optional, Audit, ScanDepth, RegistryFile, Path |
            Format-Table -AutoSize
        $missing = @($roots | Where-Object { -not $_.Exists })
        if ($missing.Count -gt 0) {
            Write-Host ("Not present on this machine: {0}" -f (($missing.Name) -join ', ')) -ForegroundColor Yellow
        }
    }

    'routing' {
        $rows = @(Get-MetraRouting -Name $Name -SharedOnly:$SharedOnly -MissingOnly:$MissingOnly)
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
        Get-MetraProjectStatus -Filter $Filter -Name $Name -Root $Root | Out-Null
    }

    'pull' {
        Update-MetraProject -Filter $Filter -Name $Name -Root $Root | Out-Null
    }

    'fetch' {
        Update-MetraProject -Filter $Filter -Name $Name -Root $Root -FetchOnly | Out-Null
    }

    'run' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "run requires a command. Example: .\metra.ps1 run 'git status -sb'"
        }
        $cmdText = ($Rest -join ' ').Trim()
        # Allow callers to pass -- then the command
        if ($cmdText.StartsWith('-- ')) { $cmdText = $cmdText.Substring(3) }
        Invoke-MetraProjectCommand -Command $cmdText -Filter $Filter -Name $Name -Root $Root -GitOnly:$GitOnly -ContinueOnError:$ContinueOnError |
            Out-Null
    }

    'new' {
        $projectName = $null
        if ($Rest -and $Rest.Count -gt 0) { $projectName = $Rest[0] }
        if (-not $projectName) {
            throw "new requires a project name. Example: .\metra.ps1 new MyProject"
        }
        $newParams = @{
            Name        = $projectName
            Description = $Description
            Template    = $Template
            NoGit       = [bool]$NoGit
            Force       = [bool]$Force
        }
        if ($Root -and $Root.Count -gt 0) { $newParams.Root = $Root[0] }
        New-MetraProject @newParams | Format-List
    }

    'apply' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "apply requires a source file. Example: .\metra.ps1 apply .\shared\.editorconfig"
        }
        $source = $Rest[0]
        Copy-MetraProjectFile -Source $source -RelativePath $RelativePath -Filter $Filter -Name $Name -Root $Root -Force:$Force
    }

    'workspace' {
        $params = @{
            WhatIfPreview = [bool]$Preview
        }
        if ($Months -ge 0) { $params.Months = $Months }
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        Update-MetraWorkspace @params | Format-List
    }

    'audit' {
        $params = @{
            Filter    = $Filter
            DriftOnly = [bool]$DriftOnly
        }
        if ($Name) { $params.Name = $Name }
        if ($Root) { $params.Root = $Root }
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        $result = Test-MetraProjectContext @params | Select-Object -Last 1
        Write-Host ""
        Write-Host ("Audited {0} project(s); drift signals: {1}" -f $result.ProjectCount, $result.DriftCount)
    }

    'snapshot' {
        $params = @{
            Quick = [bool]$Quick
        }
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        Export-MetraSnapshot @params | Format-List
    }

    'chats' {
        # Allow: .\metra.ps1 chats "disk alert" -Name Solarwinds
        $queryText = $Query
        if (-not $queryText -and $Rest -and $Rest.Count -gt 0 -and -not $Ticket) {
            $queryText = ($Rest -join ' ').Trim()
        }
        $params = @{
            Days        = $Days
            Limit       = $Limit
            IncludeMetra = [bool]$IncludeMetra
        }
        if ($Name) { $params.Name = $Name }
        if ($queryText) { $params.Query = $queryText }
        if ($Ticket) { $params.Ticket = $Ticket }
        $rows = @(Get-MetraChat @params)
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
            throw "export-profile requires -Path <dir-or-zip>. Example: .\metra.ps1 export-profile -Path `$env:TEMP\my-metra-profile.zip"
        }
        Export-MetraProfile -Path $exportPath | Format-List
    }

    'import-profile' {
        $importPath = $Path
        if (-not $importPath -and $Rest -and $Rest.Count -gt 0) { $importPath = $Rest[0] }
        if (-not $importPath) {
            throw "import-profile requires -Path <dir-or-zip>. Example: .\metra.ps1 import-profile -Path .\profiles\sample -Preview"
        }
        Import-MetraProfile -Path $importPath -Preview:$Preview -Force:$Force | Format-List
    }

    'ctx' {
        $queryText = $Query
        if (-not $queryText -and $Rest -and $Rest.Count -gt 0) {
            $queryText = ($Rest -join ' ').Trim()
        }
        $params = @{
            Format       = $Format
            IncludeAgent = [bool]$IncludeAgent
        }
        if ($queryText) { $params.Query = $queryText }
        if ($Path) { $params.Path = $Path }
        if ($Limit -gt 0 -and $Limit -ne 10) { $params.Limit = $Limit }
        # Default Limit for ctx is 25; metra.ps1 default Limit is 10 for chats.
        if (-not $PSBoundParameters.ContainsKey('Limit')) {
            $params.Limit = 25
        }
        else {
            $params.Limit = $Limit
        }
        Export-MetraContext @params | Format-List
    }

    'setup' {
        $profilePath = $Profile
        if (-not $profilePath -and $Path) { $profilePath = $Path }
        if (-not $profilePath -and $Rest -and $Rest.Count -gt 0) { $profilePath = $Rest[0] }
        $params = @{
            Preview = [bool]$Preview
            Force   = [bool]$Force
        }
        if ($profilePath) { $params.Profile = $profilePath }
        if ($Months -ge 0) { $params.Months = $Months }
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        Initialize-Metra @params | Format-List Preview, WouldSeedConfig, SeededConfig, Profile
    }

    'verify' {
        $report = Test-MetraInstallation -Detailed
        $report.Results |
            Select-Object Status, Name, Detail |
            Format-Table -AutoSize
        Write-Host ("PASS={0} WARN={1} FAIL={2}" -f $report.PassCount, $report.WarnCount, $report.FailCount)
        if (-not $report.Ok) {
            exit 1
        }
    }
}

