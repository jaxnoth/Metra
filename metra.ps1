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
    .\metra.ps1 audit -MetadataOnly
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
    .\metra.ps1 setup
    .\metra.ps1 setup -Profile .\profiles\sample -Force
    .\metra.ps1 verify
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        'list', 'status', 'pull', 'fetch', 'run', 'new', 'apply', 'workspace',
        'audit', 'snapshot', 'selfdoc', 'ops', 'host', 'chats', 'roots', 'routing',
        'export-profile', 'import-profile', 'ctx', 'setup', 'verify', 'unblock', 'profile', 'decisions', 'coverage', 'ask', 'capture', 'watch', 'help'
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
    [switch]$MetadataOnly,
    [Alias('IncludeMeta')]
    [switch]$IncludeMetra,
    [switch]$Cloud,
    [switch]$SharedOnly,
    [switch]$MissingOnly,
    [switch]$Quick,
    [switch]$NoBrowser,
    [switch]$NoRefresh,
    [switch]$Full,
    [switch]$Stop,
    [switch]$Draft,
    [switch]$SkipSync,
    [int]$Port = 0
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
  .\metra.ps1 audit [-Filter '*'] [-Name ProjA,ProjB] [-Root ...] [-DriftOnly] [-MetadataOnly] [-ScanDepth 4]
      -MetadataOnly: route registry metadata advisories only (skips recursive tree scan; never fails as drift).
  .\metra.ps1 snapshot [-ScanDepth 2] [-Quick]
  .\metra.ps1 selfdoc
  .\metra.ps1 ops [-Quick] [-Full] [-Port 7380] [-NoBrowser] [-NoRefresh] [-Stop]
      Console Ops desk (operator/debug). -Stop frees the port when a desk outlived its console.
  .\metra.ps1 host [-Port 7380] [-NoBrowser] [-NoRefresh] [-Quick] [-Stop]
      User-session tray host so Metra stays alive without a console. Host starts Ops only (Ops owns Ask).
      Second launch opens the browser when the desk is already up.
  .\metra.ps1 chats [-Name ProjA,ProjB] [-Query 'terms'] [-Ticket 12345] [-Days 90] [-Limit 10] [-IncludeMetra]
  .\metra.ps1 roots
  .\metra.ps1 routing [-Name ProjA] [-Query 'terms'] [-SharedOnly] [-MissingOnly]
      With -Query: primary stop + Why here? (and Why not? when scores are close).
      With -Name: registry row(s) + Why here? for present named projects.
      With neither: full registry table (no Why Here dump).
  .\metra.ps1 export-profile -Path <dir-or-zip>
  .\metra.ps1 import-profile -Path <dir-or-zip> [-Preview] [-Force]
  .\metra.ps1 ctx [-Query 'terms'] [-Path <file|->] [-Format markdown|json] [-Limit 25]
  .\metra.ps1 setup [-Profile <dir-or-zip>] [-Force] [-Preview] [-Months 6] [-ScanDepth 2]
      One-shot onboarding: seed config if missing, optional profile, roots, workspace, routing, ctx.
  .\metra.ps1 unblock [-Preview]
      Clear mark-of-the-web from checkout script files (ZIP / OneDrive / email). Supports -Preview.
  .\metra.ps1 profile show|note|promote|forget|render|gc
      Operator Communication Contract (candidates -> promote -> soft guidelines).
  .\metra.ps1 decisions show|note|promote|forget|search|get|supersede|gc|review|harvest|seed
      Decision Registry / Operational Why Memory (candidates -> promote; review = hygiene visibility).
  .\metra.ps1 ask log|sessions|get|recall
      Session Journal (recent Ask conversations - continuity window, not permanent memory).
      get <sessionId> resumes/reads one session; recall "<query>" searches prompts/answers.
  .\metra.ps1 ask engine show|set|recommend|menu
  .\metra.ps1 ask key status|set|clear
  .\metra.ps1 ask recommend|accept [-RuntimeOnly] [-SkipInstall] [-WhatIf]
      Ask engine: Ollama recommended path; Cursor premium; enterprise when configured.
  .\metra.ps1 capture list|get|note|dismiss|promote|from-ask
      Capture Inbox (thin portfolio intake; promote on affirm - never auto).
  .\metra.ps1 coverage
      Knowledge coverage visibility (AGENTS / serves / decisions / uncovered) - counts and gap lists, not a score.
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
  export-profile             pack local config / registry / overlays / learned contract
  import-profile             restore a pack (refuse overwrite unless -Force)
  profile                    Operator Communication Contract (learned soft guidelines)
  decisions                  Decision Registry (operational why-we-chose; gitignored ledger)

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
  .\metra.ps1 audit -MetadataOnly
  .\metra.ps1 routing -MissingOnly
  .\metra.ps1 routing -SharedOnly
  .\metra.ps1 snapshot
  .\metra.ps1 chats -Name Solarwinds -Query 'disk alert'
  .\metra.ps1 chats -Name TicketTracker,Solarwinds -Ticket 12345 -IncludeMetra
  .\metra.ps1 import-profile -Path .\profiles\sample -Preview
  .\metra.ps1 import-profile -Path .\profiles\sample -Force
  .\metra.ps1 export-profile -Path `$env:TEMP\my-metra-profile.zip
  .\metra.ps1 profile note 'Prefer terse verdicts before detail.'
  .\metra.ps1 profile promote 'Prefer terse verdicts before detail.'
  .\metra.ps1 profile show
  .\metra.ps1 decisions search 'datamanager'
  .\metra.ps1 decisions harvest -Preview
  .\metra.ps1 ctx
  .\metra.ps1 ctx -Query 'ticket disk'
  .\metra.ps1 ctx -Format json -Path `$env:TEMP\metra-ctx.json
  .\metra.ps1 setup
  .\metra.ps1 watch tickets [-Draft] [-SkipSync]
      Ticket-first watch intake: sync/list open+watched -> Attention observations.
      Default: Attention only (no iSupport writes). -Draft writes local TicketTracker notes.
  .\metra.ps1 setup -Profile .\profiles\sample -Force
  .\metra.ps1 setup -Preview
  .\metra.ps1 unblock
  .\metra.ps1 unblock -Preview
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
        # Why Here helpers stay private; Show-MetraRoutingCli is a thin compatibility export for the CLI.
        Show-MetraRoutingCli -Query $Query -Name $Name -SharedOnly:$SharedOnly -MissingOnly:$MissingOnly
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
            Filter       = $Filter
            DriftOnly    = [bool]$DriftOnly
            MetadataOnly = [bool]$MetadataOnly
        }
        if ($Name) { $params.Name = $Name }
        if ($Root) { $params.Root = $Root }
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        $result = Test-MetraProjectContext @params | Select-Object -Last 1
        Write-Host ""
        if ($MetadataOnly) {
            Write-Host ("Route metadata advisories: {0} (not drift)" -f $result.MetadataCount)
        }
        else {
            Write-Host ("Audited {0} project(s); drift signals: {1}; route metadata advisories: {2}" -f $result.ProjectCount, $result.DriftCount, $result.MetadataCount)
        }
    }

    'snapshot' {
        $params = @{
            Quick = [bool]$Quick
        }
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        Export-MetraSnapshot @params | Format-List
    }

    'selfdoc' {
        Update-MetraSelfDocumentation | Format-List
    }

    'ops' {
        if ($Port -le 0) {
            $Port = [int](Resolve-MetraOpsDeskBinding).Port
        }
        if ($Stop) {
            Stop-MetraOpsServer -Port $Port
            return
        }
        $params = @{
            Port      = $Port
            Quick     = [bool]$Quick
            Full      = [bool]$Full
            NoBrowser = [bool]$NoBrowser
            NoRefresh = [bool]$NoRefresh
        }
        Start-MetraOpsServer @params
    }

    'host' {
        if ($Port -le 0) {
            $Port = [int](Resolve-MetraOpsDeskBinding).Port
        }
        if ($Stop) {
            Stop-MetraOpsHost -Port $Port
            return
        }
        $params = @{
            Port      = $Port
            NoBrowser = [bool]$NoBrowser
            NoRefresh = [bool]$NoRefresh
            Quick     = [bool]$Quick
        }
        Start-MetraOpsHost @params
    }

    'chats' {
        # Allow: .\metra.ps1 chats "disk alert" -Name Solarwinds
        $queryText = $Query
        if (-not $queryText -and $Rest -and $Rest.Count -gt 0 -and -not $Ticket) {
            $queryText = ($Rest -join ' ').Trim()
        }
        $params = @{
            Days         = $Days
            Limit        = $Limit
            IncludeMetra = [bool]$IncludeMetra
            Cloud        = [bool]$Cloud
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
                Select-Object Project, Source, ChatId, Modified, MatchedTerms, Title, Snippet1, Cite |
                Format-List
            Write-Host ("{0} chat(s). Cite with [title](ChatId or URL); promote useful findings via TicketTracker note -Tags chat." -f $rows.Count)
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
            Format = $Format
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

    'unblock' {
        # Helper stays private; Show-MetraUnblockCli is a thin compatibility export for the CLI.
        Show-MetraUnblockCli -Preview:$Preview | Format-List Path, Preview, ScannedCount, BlockedDetected, FilesUnblocked, AlreadyClean, Failed
    }

    'profile' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "profile requires a subcommand. Example: .\metra.ps1 profile show"
        }
        $sub = $Rest[0]
        $subArgs = @()
        if ($Rest.Count -gt 1) {
            $subArgs = @($Rest[1..($Rest.Count - 1)])
        }
        $result = Invoke-MetraOperatorContractCommand -Subcommand $sub -ArgsRest $subArgs
        switch ($sub.ToLowerInvariant()) {
            'show' {
                Write-Host ("Ledger:  {0} (exists={1})" -f $result.LedgerPath, $result.LedgerExists)
                Write-Host ("Learned: {0} (exists={1})" -f $result.LearnedPath, $result.LearnedExists)
                Write-Host ("Confirmed {0}/{1}" -f $result.ConfirmedCount, $result.MaxConfirmed)
                if ($result.ConfirmedCount -gt 0) {
                    Write-Host ''
                    Write-Host 'Confirmed guidelines:'
                    foreach ($g in @($result.ConfirmedGuidelines)) {
                        Write-Host ("  [{0}] {1}" -f $g.id, $g.text)
                    }
                }
                Write-Host ''
                Write-Host ("Candidates: {0}" -f $result.CandidateCount)
                foreach ($c in @($result.Candidates)) {
                    Write-Host ("  [{0}] (count={1}) {2}" -f $c.id, $c.count, $c.text)
                }
            }
            default {
                $result | Format-List
            }
        }
    }

    'coverage' {
        # Helper stays private; Show-MetraKnowledgeCoverageCli is a thin compatibility export for the CLI.
        Show-MetraKnowledgeCoverageCli
    }

    'decisions' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "decisions requires a subcommand. Example: .\metra.ps1 decisions show"
        }
        $sub = $Rest[0]
        $subArgs = @()
        if ($Rest.Count -gt 1) {
            $subArgs = @($Rest[1..($Rest.Count - 1)])
        }
        $result = Invoke-MetraDecisionRegistryCommand -Subcommand $sub -ArgsRest $subArgs -Name $Name -Preview:$Preview
        switch ($sub.ToLowerInvariant()) {
            'show' {
                Write-Host ("Ledger: {0} (exists={1})" -f $result.LedgerPath, $result.LedgerExists)
                Write-Host ("Confirmed {0}/{1} (superseded={2})" -f $result.ConfirmedCount, $result.MaxConfirmed, $result.SupersededCount)
                Write-Host ("Candidates: {0}" -f $result.CandidateCount)
                if ($result.ConfirmedCount -gt 0) {
                    Write-Host ''
                    Write-Host 'Active decisions:'
                    foreach ($d in @($result.Confirmed | Where-Object { $_.status -eq 'active' })) {
                        Write-Host ("  [{0}] {1} ({2}) conf={3}" -f $d.id, $d.title, $d.project, $d.confidence)
                    }
                }
                if ($result.CandidateCount -gt 0) {
                    Write-Host ''
                    Write-Host 'Candidates:'
                    foreach ($c in @($result.Candidates)) {
                        Write-Host ("  [{0}] {1} ({2})" -f $c.id, $c.title, $c.project)
                    }
                }
            }
            'review' {
                # Host output already written inside Invoke-MetraDecisionRegistryCommand.
            }
            'search' {
                $result |
                    Select-Object Score, Id, Project, Confidence, Title, Why |
                    Format-Table -AutoSize
            }
            'harvest' {
                Write-Host ("{0}: scanned={1} results={2}" -f $result.Action, $result.Scanned, $result.Count)
                @($result.Results) |
                    Select-Object Action, Project, Id, Title, Source |
                    Format-Table -AutoSize
            }
            default {
                $result | Format-List
            }
        }
    }

    'ask' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "ask requires a subcommand. Example: .\metra.ps1 ask sessions"
        }
        $sub = $Rest[0]
        $subArgs = @()
        if ($Rest.Count -gt 1) {
            $subArgs = @($Rest[1..($Rest.Count - 1)])
        }
        if ($sub -match '^(?i)(engine|key|recommend|accept|menu)$') {
            $result = Invoke-MetraAskEngineCommand -Subcommand $sub -ArgsRest $subArgs
            if ($sub -match '^(?i)(recommend|accept|menu)$' -or ($sub -match '^(?i)engine$' -and $subArgs.Count -gt 0 -and $subArgs[0] -match '^(?i)(recommend|menu)$')) {
                $result | Format-List
            }
            else {
                $result | Format-List
            }
        }
        else {
            $result = Invoke-MetraAskLogCommand -Subcommand $sub -ArgsRest $subArgs
            if ($sub -match '^(?i)(get|resume)$') {
                $result | Format-List
            }
            else {
                $result | Format-Table -AutoSize
            }
        }
    }

    'capture' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "capture requires a subcommand. Example: .\metra.ps1 capture list"
        }
        $sub = $Rest[0]
        $subArgs = @()
        if ($Rest.Count -gt 1) {
            $subArgs = @($Rest[1..($Rest.Count - 1)])
        }
        $result = Invoke-MetraCaptureCommand -Subcommand $sub -ArgsRest $subArgs
        $result | Format-List
    }

    'watch' {
        $target = 'tickets'
        if ($Rest -and $Rest.Count -gt 0) { $target = [string]$Rest[0] }
        if ($target -ne 'tickets') {
            throw "watch supports 'tickets' only in v1. Example: .\metra.ps1 watch tickets"
        }
        Invoke-MetraTicketWatchScan -Draft:$Draft -SkipSync:$SkipSync | Out-Null
    }
}

