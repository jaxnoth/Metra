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
        'export-profile', 'import-profile', 'ctx', 'setup', 'verify', 'unblock', 'profile', 'decisions', 'coverage', 'ask', 'capture', 'watch', 'inspect', 'azdo', 'help'
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
    [string]$Base,
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
    [switch]$RefreshSelfDocumentation,
    [switch]$NoBrowser,
    [switch]$NoRefresh,
    [switch]$Full,
    [switch]$Stop,
    [switch]$ForceLocal,
    [switch]$Local,
    [switch]$Draft,
    [switch]$SkipSync,
    [Alias('PassThru')]
    [switch]$AsString,
    [switch]$Confirm,
    [int]$Port = 0,
    [string]$OpsBaseUrl,
    [string]$SyncToken,
    [ValidateSet('Hq', 'Satellite', 'Standalone')]
    [string]$Role,
    [switch]$Advanced,
    [switch]$PreferFriendly,
    [switch]$NoPreferFriendly,
    [switch]$BindTailscale,
    [switch]$AcceptAsk,
    [switch]$Quiet,
    [switch]$WhatIf
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
  .\metra.ps1 snapshot [-ScanDepth 2] [-Quick] [-RefreshSelfDocumentation]
  .\metra.ps1 selfdoc
  .\metra.ps1 ops [-Quick] [-Full] [-Port 7380] [-NoBrowser] [-NoRefresh] [-Stop] [-ForceLocal]
      Console Ops desk (operator/debug). -Stop frees the port when a desk outlived its console.
      Mode B (remote OpsBaseUrl) refuses local Ops unless -ForceLocal.
  .\metra.ps1 host [-Port 7380] [-NoBrowser] [-NoRefresh] [-Quick] [-Stop] [-ForceLocal]
      User-session tray host so Metra stays alive without a console. Host starts Ops only (Ops owns Ask).
      Second launch opens the browser when the desk is already up. Mode B refuses unless -ForceLocal.
  .\metra.ps1 chats [-Name ProjA,ProjB] [-Query 'terms'] [-Ticket 12345] [-Days 90] [-Limit 10] [-IncludeMetra]
  .\metra.ps1 roots
  .\metra.ps1 routing [-Name ProjA] [-Query 'terms'] [-SharedOnly] [-MissingOnly]
      With -Query: primary stop + Why here? (and Why not? when scores are close).
      With -Name: registry row(s) + Why here? for present named projects.
      With neither: full registry table (no Why Here dump).
  .\metra.ps1 export-profile -Path <dir-or-zip> [-Force]
  .\metra.ps1 import-profile -Path <dir-or-zip> [-Preview] [-Force]
  .\metra.ps1 ctx [-Query 'terms'] [-Path <file|->] [-Format markdown|json] [-Limit 25]
  .\metra.ps1 setup [-Profile <dir-or-zip>] [-Force] [-Preview] [-Quiet] [-Role Hq|Satellite|Standalone] [-OpsBaseUrl https://...] [-SyncToken ...] [-PreferFriendly|-NoPreferFriendly] [-BindTailscale] [-AcceptAsk] [-Advanced] [-Months 6] [-ScanDepth 2]
      First-run / refresh. Role picks HQ, Satellite, or Standalone; -Quiet skips prompts (installer path).
      Installer passes PreferFriendly / BindTailscale / AcceptAsk / SyncToken. -Advanced keeps interactive local Ops knobs.
  .\metra.ps1 unblock [-Preview]
      Clear mark-of-the-web from checkout script files (ZIP / OneDrive / email). Supports -Preview.
  .\metra.ps1 profile show|note|promote|forget|render|gc
  .\metra.ps1 profile sync [-WhatIf] [-Force] [-OpsBaseUrl https://...] [-SyncToken ...]
  .\metra.ps1 profile status [-OpsBaseUrl https://...] [-SyncToken ...]
      Satellite freshness vs HQ: Current / Behind / Unknown (no import).
  .\metra.ps1 profile issue-sync-token [-Force]
      Profile Sync v1 (HQ-published, satellite-pulled). issue-sync-token on HQ; sync on laptop/Mac.
      Operator Communication Contract (candidates -> promote -> soft guidelines).
  .\metra.ps1 decisions show|note|promote|forget|search|get|supersede|gc|review|harvest|seed
      Decision Registry / Operational Why Memory (candidates -> promote; review = hygiene visibility).
  .\metra.ps1 ask log|sessions|get|recall [-Local] [-OpsBaseUrl https://...]
      Session Journal. Mode B (remote OpsBaseUrl) queries HQ; -Local reads the local journal file.
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
  .\metra.ps1 inspect [-Name Metra] [-Base <rev>] [-WhatIf]
  .\metra.ps1 inspect plan [-Latest] [-Path <file>] [<filename-fragment>] -Name <Project> [-WhatIf]
  .\metra.ps1 inspect pack [plan] [-WhatIf]
  .\metra.ps1 inspect pack-only [-Name <Project>] [-Base <rev>] [-WhatIf]
  .\metra.ps1 inspect pack-only plan [-Latest] [-Path <file>] [<fragment>] -Name <Project> [-WhatIf]
      pack-only: Bing comparison lane without Ask engine (scrubbed diff/plan + preamble).
      inspect pack: requires a prior inspect run; includes assessed findings.
      Local AI-assisted inspection of git diffs or Cursor plans (Ask/Ollama). Recommend-only.
  .\metra.ps1 azdo status|repos|get|gaps|tree|search|ideas
      Read-only Azure DevOps remote evidence (PAT: METRA_AZDO_PAT or docs/azdo.local.json). gaps maps AzDO vs registry/disk.
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
      Default: Attention only (no iSupport writes). -Draft forces TT analyze (local draft). Opt-in autoAnalyze in docs/ticket-watch.local.json analyzes Added/Refreshed only. Opt-in evidenceRouter appends Next evidence (or Ready for recommendation) after analyze - never iSupport recommend.
  .\metra.ps1 watch recommend <id> [-Preview] [-Confirm] [-Force]
      M3: Preview writes local recommend-draft. Confirm writes Affirm A store-as-review via TT recommend (supersedes Metra AI Recommendation). Gates on E1 recommendable unless -Force. Never resolve/close. autoStoreRecommend stays false.
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
        }
        if ($Root -and $Root.Count -gt 0) { $newParams.Root = $Root[0] }
        if ($NoGit) { $newParams.NoGit = $true }
        if ($Force) { $newParams.Force = $true }
        New-MetraProject @newParams | Format-List
    }

    'apply' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "apply requires a source file. Example: .\metra.ps1 apply .\shared\.editorconfig"
        }
        $source = $Rest[0]
        $applyParams = @{
            Source = $source
            Filter = $Filter
        }
        if ($RelativePath) { $applyParams.RelativePath = $RelativePath }
        if ($Name) { $applyParams.Name = $Name }
        if ($Root) { $applyParams.Root = $Root }
        if ($Force) { $applyParams.Force = $true }
        Copy-MetraProjectFile @applyParams
    }

    'workspace' {
        $params = @{}
        if ($Preview) { $params.WhatIfPreview = $true }
        if ($WhatIf) { $params.WhatIf = $true }
        if ($Months -ge 1) { $params.Months = $Months }
        if ($ScanDepth -ge 1) { $params.ScanDepth = $ScanDepth }
        Update-MetraWorkspace @params | Format-List
    }

    'audit' {
        if ($DriftOnly -and $MetadataOnly) {
            throw 'audit: -DriftOnly and -MetadataOnly are mutually exclusive.'
        }
        $params = @{
            Filter = $Filter
        }
        # Only splat mode switches when true - false switch keys break exclusive parameter sets.
        if ($DriftOnly) { $params.DriftOnly = $true }
        if ($MetadataOnly) { $params.MetadataOnly = $true }
        if ($Name) { $params.Name = $Name }
        if ($Root) { $params.Root = $Root }
        if ($ScanDepth -ge 0) { $params.ScanDepth = $ScanDepth }
        $result = Test-MetraProjectContext @params | Select-Object -Last 1
        Write-Host ""
        if ($MetadataOnly) {
            Write-Host ("Route metadata advisories: {0} (not drift)" -f $result.MetadataCount)
        }
        else {
            $driftProjects = if ($null -ne $result.DriftProjects) { [int]$result.DriftProjects } else { [int]$result.DriftCount }
            $driftFindings = if ($null -ne $result.DriftFindings) { [int]$result.DriftFindings } else { [int]$result.DriftCount }
            Write-Host ("Audited {0} project(s); drift projects: {1}; drift findings: {2}; route metadata advisories: {3}" -f $result.ProjectCount, $driftProjects, $driftFindings, $result.MetadataCount)
        }
    }

    'snapshot' {
        $params = @{}
        if ($Quick) { $params.Quick = $true }
        if ($RefreshSelfDocumentation) { $params.RefreshSelfDocumentation = $true }
        if ($WhatIf) { $params.WhatIf = $true }
        if ($ScanDepth -ge 1) { $params.ScanDepth = $ScanDepth }
        Export-MetraSnapshot @params | Format-List
    }

    'selfdoc' {
        Update-MetraSelfDocumentation | Format-List
    }

    'ops' {
        if ($Full -and $Quick) {
            throw 'ops: -Full and -Quick cannot both be specified.'
        }
        if ($Port -le 0) {
            $Port = [int](Resolve-MetraOpsDeskBinding).Port
        }
        if ($Stop) {
            Stop-MetraOpsServer -Port $Port
            return
        }
        $params = @{
            Port = $Port
        }
        if ($Quick) { $params.Quick = $true }
        if ($Full) { $params.Full = $true }
        if ($NoBrowser) { $params.NoBrowser = $true }
        if ($NoRefresh) { $params.NoRefresh = $true }
        if ($ForceLocal) { $params.ForceLocal = $true }
        if ($OpsBaseUrl) { $params.OpsBaseUrl = $OpsBaseUrl }
        Start-MetraOpsServer @params
    }

    'host' {
        if ($Stop -and ($Quick -or $NoBrowser -or $NoRefresh -or $ForceLocal)) {
            throw 'host: -Stop cannot be combined with startup options.'
        }
        if ($Port -le 0) {
            $Port = [int](Resolve-MetraOpsDeskBinding).Port
        }
        if ($Port -lt 1 -or $Port -gt 65535) {
            throw ("host: resolved Ops port is invalid: {0}" -f $Port)
        }
        if ($Stop) {
            Stop-MetraOpsHost -Port $Port
            return
        }
        $params = @{ Port = $Port }
        if ($NoBrowser) { $params.NoBrowser = $true }
        if ($NoRefresh) { $params.NoRefresh = $true }
        if ($Quick) { $params.Quick = $true }
        if ($ForceLocal) { $params.ForceLocal = $true }
        if ($OpsBaseUrl) { $params.OpsBaseUrl = $OpsBaseUrl }
        Start-MetraOpsHost @params
    }

    'chats' {
        # Allow: .\metra.ps1 chats "disk alert" -Name Solarwinds
        $queryText = $Query
        if (-not $queryText -and $Rest -and $Rest.Count -gt 0 -and -not $Ticket) {
            $queryText = ($Rest -join ' ').Trim()
        }
        if ($queryText -and $Ticket) {
            throw 'chats: -Query and -Ticket are mutually exclusive.'
        }
        if (-not $Name -and -not $queryText -and -not $Ticket -and -not $IncludeMetra) {
            throw 'chats: specify -Name, -Query, -Ticket, or -IncludeMetra.'
        }
        $params = @{
            Days  = $Days
            Limit = $Limit
        }
        # Only splat switches when true - false switch keys can confuse exclusive parameter sets.
        if ($IncludeMetra) { $params.IncludeMetra = $true }
        if ($Cloud) { $params.Cloud = $true }
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
        Export-MetraProfile -Path $exportPath -Force:$Force | Format-List
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
        if ($AsString -and $Path -and $Path -ne '-') {
            throw "ctx: -AsString cannot be combined with a file -Path. Use -AsString alone, or -Path '-'."
        }
        $params = @{
            Format = $Format
        }
        if ($queryText) { $params.Query = $queryText }
        if ($AsString) {
            $params.AsString = $true
        }
        elseif ($Path) {
            $params.Path = $Path
        }
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
        # Never treat leading-dash $Rest tokens as a profile path (PS 5.1 array-splat footgun).
        if (-not $profilePath -and $Rest -and $Rest.Count -gt 0 -and $Rest[0] -notlike '-*') {
            $profilePath = $Rest[0]
        }
        if ($PreferFriendly -and $NoPreferFriendly) {
            throw 'setup: -PreferFriendly and -NoPreferFriendly cannot both be specified.'
        }
        $params = @{}
        if ($Preview) { $params.Preview = $true }
        if ($Force) { $params.Force = $true }
        if ($Advanced) { $params.Advanced = $true }
        if ($Quiet) { $params.Quiet = $true }
        if ($PreferFriendly) { $params.PreferFriendly = $true }
        if ($NoPreferFriendly) { $params.NoPreferFriendly = $true }
        if ($BindTailscale) { $params.BindTailscale = $true }
        if ($AcceptAsk) { $params.AcceptAsk = $true }
        if ($WhatIf) { $params.WhatIf = $true }
        if ($profilePath) { $params.Profile = $profilePath }
        if ($Role) { $params.Role = $Role }
        if ($OpsBaseUrl) { $params.OpsBaseUrl = $OpsBaseUrl }
        if ($SyncToken) { $params.SyncToken = $SyncToken }
        if ($Months -ge 1) { $params.Months = $Months }
        if ($ScanDepth -ge 1) { $params.ScanDepth = $ScanDepth }
        $setupResult = Initialize-Metra @params
        if (-not $Quiet) {
            $setupResult | Format-List Preview, SeededConfig, MachineRole, SetupLogPath, Success
        }
    }

    'verify' {
        $report = Test-MetraInstallation -Detailed
        $report.Results |
            Select-Object Status, Category, Name, Detail |
            Format-Table -AutoSize
        $ver = if ($null -ne $report.VerifyVersion) { [int]$report.VerifyVersion } else { 0 }
        Write-Host ("VerifyVersion={0} PASS={1} WARN={2} FAIL={3}" -f $ver, $report.PassCount, $report.WarnCount, $report.FailCount)
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
            throw "profile requires a subcommand. Example: .\metra.ps1 profile show | profile status | profile sync | profile issue-sync-token"
        }
        $sub = $Rest[0]
        $subArgs = @()
        if ($Rest.Count -gt 1) {
            $subArgs = @($Rest[1..($Rest.Count - 1)])
        }
        switch ($sub.ToLowerInvariant()) {
            'status' {
                $statusParams = @{}
                if ($OpsBaseUrl) { $statusParams.OpsBaseUrl = $OpsBaseUrl }
                if ($SyncToken) { $statusParams.SyncToken = $SyncToken }
                if (-not $OpsBaseUrl -and $subArgs.Count -gt 0 -and $subArgs[0] -notlike '-*') {
                    $statusParams.OpsBaseUrl = $subArgs[0]
                }
                Get-MetraProfileSyncClientStatus @statusParams | Format-List
            }
            'sync' {
                $syncParams = @{}
                # Only splat true switches - false WhatIf keys confuse SupportsShouldProcess binding.
                if ($WhatIf) { $syncParams.WhatIf = $true }
                if ($Force) { $syncParams.Force = $true }
                if ($OpsBaseUrl) { $syncParams.OpsBaseUrl = $OpsBaseUrl }
                if ($SyncToken) { $syncParams.SyncToken = $SyncToken }
                # Allow trailing positional OpsBaseUrl for convenience.
                if (-not $OpsBaseUrl -and $subArgs.Count -gt 0 -and $subArgs[0] -notlike '-*') {
                    $syncParams.OpsBaseUrl = $subArgs[0]
                }
                Sync-MetraProfile @syncParams | Format-List
            }
            'issue-sync-token' {
                $issued = Initialize-MetraProfileSyncToken -Rotate:$Force
                if ($issued.Token) {
                    Write-Host 'Profile sync token (copy to satellite docs/profile-sync.local.json as syncToken):' -ForegroundColor Yellow
                    Write-Host $issued.Token
                    Write-Host ''
                    Write-Host $issued.Message
                }
                else {
                    Write-Host $issued.Message
                    Write-Host 'Re-run with -Force to rotate and show a new plaintext token.'
                }
                $issued | Select-Object Created, HasToken, Header, Path, Message | Format-List
            }
            default {
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
        }
    }

    'coverage' {
        # Helper stays private; Show-MetraKnowledgeCoverageCli is a thin compatibility export for the CLI.
        Show-MetraKnowledgeCoverageCli
    }

    'inspect' {
        # Helper stays private; Show-MetraInspectCli is a thin compatibility export for the CLI.
        try {
            $inspectParams = @{
                Rest = @($Rest)
            }
            if ($Name) { $inspectParams.Name = $Name }
            if ($Path) { $inspectParams.Path = $Path }
            if ($Base) { $inspectParams.Base = $Base }
            if ($WhatIf) { $inspectParams.WhatIf = $true }
            $null = Show-MetraInspectCli @inspectParams
        }
        catch {
            Write-Error $_
            exit 1
        }
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
            $askParams = @{
                Subcommand = $sub
                ArgsRest   = $subArgs
                Local      = [bool]$Local
            }
            if ($OpsBaseUrl) { $askParams.OpsBaseUrl = $OpsBaseUrl }
            $result = Invoke-MetraAskLogCommand @askParams
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
        switch ($target.ToLowerInvariant()) {
            'tickets' {
                Invoke-MetraTicketWatchScan -Draft:$Draft -SkipSync:$SkipSync | Out-Null
            }
            'recommend' {
                if (-not $Rest -or $Rest.Count -lt 2 -or -not $Rest[1]) {
                    throw "watch recommend requires a ticket id. Example: .\metra.ps1 watch recommend 1035020 -Preview"
                }
                $recId = [string]$Rest[1]
                if (-not $Preview -and -not $Confirm) { $Preview = $true }
                $store = Invoke-MetraTicketWatchStoreRecommend -Id $recId -Preview:$Preview -Confirm:$Confirm -Force:$Force
                if (-not $store.ok -and $store.warning) {
                    Write-Warning $store.warning
                }
                $store | Format-List ok, id, preview, confirm, force, mineEligible, recommendable, noteId, recommendationWritten, iSupportWrite, warning
            }
            default {
                throw "watch supports 'tickets' or 'recommend'. Examples: .\metra.ps1 watch tickets | .\metra.ps1 watch recommend <id> -Preview"
            }
        }
    }

    'azdo' {
        if (-not $Rest -or $Rest.Count -eq 0) {
            throw "azdo requires a subcommand. Example: .\metra.ps1 azdo status"
        }
        $sub = $Rest[0]
        $subArgs = @()
        if ($Rest.Count -gt 1) {
            $subArgs = @($Rest[1..($Rest.Count - 1)])
        }
        $result = Invoke-MetraAzdoCommand -Subcommand $sub -ArgsRest $subArgs
        if ($sub -eq 'ideas' -and $result.draft) {
            Write-Host $result.draft
            if ($result.outFile) {
                Write-Host ("Draft also written: {0}" -f $result.outFile) -ForegroundColor DarkGray
            }
        }
        elseif ($subArgs -contains '-Json' -or $subArgs -contains '-json') {
            $result | ConvertTo-Json -Depth 10
        }
        else {
            if ($result -is [System.Array]) {
                $result | Format-Table -AutoSize
            }
            else {
                $result | Format-List
            }
        }
    }
}

