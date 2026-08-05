# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Test-MetraPathExists {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Relative
    )

    $full = Join-Path $Root ($Relative -replace '/', '\')
    return (Test-Path -LiteralPath $full)
}

function Get-MetraGeneratedPathHints {
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

function Get-MetraRouteMetadataIssues {
    <#
    .SYNOPSIS
        Report-only route registry metadata advisories (never counted as drift).
    .DESCRIPTION
        Walks merged registry rows for empty purpose/triggers, optional stubs missing
        whenMissing, single-character triggers, and exact stop-word trigger matches.
    #>
    [CmdletBinding()]
    param()

    $issues = New-Object System.Collections.Generic.List[object]
    $registry = Get-MetraProjectRegistry
    $stopWords = Get-MetraRoutingStopWords

    foreach ($row in @($registry.projects)) {
        $routeKey = [string](Get-MetraProp -Object $row -Name 'name' -Default '')
        if ([string]::IsNullOrWhiteSpace($routeKey)) { continue }

        $source = [string](Get-MetraProp -Object $row -Name 'source' -Default '')
        $purpose = [string](Get-MetraProp -Object $row -Name 'purpose' -Default '')

        if ([string]::IsNullOrWhiteSpace($purpose)) {
            [void]$issues.Add([pscustomobject]@{
                Kind     = 'RouteMetadata'
                Severity = 'Advisory'
                Route    = $routeKey
                Source   = $source
                Field    = 'purpose'
                Issue    = 'EmptyPurpose'
                Value    = $purpose
                Message  = "Route '$routeKey' has an empty purpose."
            })
        }

        $triggers = @(Get-MetraProp -Object $row -Name 'triggers' -Default @())
        $nonEmptyTriggers = @(
            $triggers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )

        if ($nonEmptyTriggers.Count -eq 0) {
            [void]$issues.Add([pscustomobject]@{
                Kind     = 'RouteMetadata'
                Severity = 'Advisory'
                Route    = $routeKey
                Source   = $source
                Field    = 'triggers'
                Issue    = 'EmptyTriggers'
                Value    = $triggers
                Message  = "Route '$routeKey' has no usable triggers."
            })
        }
        else {
            foreach ($trigger in $nonEmptyTriggers) {
                $normalizedTrigger = ([string]$trigger).Trim()

                if ($normalizedTrigger.Length -eq 1) {
                    [void]$issues.Add([pscustomobject]@{
                        Kind     = 'RouteMetadata'
                        Severity = 'Advisory'
                        Route    = $routeKey
                        Source   = $source
                        Field    = 'triggers'
                        Issue    = 'SingleCharacterTrigger'
                        Value    = $normalizedTrigger
                        Message  = "Route '$routeKey' has a one-character trigger '$normalizedTrigger'."
                    })
                }

                if ($stopWords.Contains($normalizedTrigger)) {
                    [void]$issues.Add([pscustomobject]@{
                        Kind     = 'RouteMetadata'
                        Severity = 'Advisory'
                        Route    = $routeKey
                        Source   = $source
                        Field    = 'triggers'
                        Issue    = 'StopWordTrigger'
                        Value    = $normalizedTrigger
                        Message  = "Route '$routeKey' has stop-word trigger '$normalizedTrigger'."
                    })
                }
            }
        }

        $optional = [bool](Get-MetraProp -Object $row -Name 'optional' -Default $false)
        $whenMissing = [string](Get-MetraProp -Object $row -Name 'whenMissing' -Default '')
        if ($optional -and [string]::IsNullOrWhiteSpace($whenMissing)) {
            [void]$issues.Add([pscustomobject]@{
                Kind     = 'RouteMetadata'
                Severity = 'Advisory'
                Route    = $routeKey
                Source   = $source
                Field    = 'whenMissing'
                Issue    = 'OptionalRouteMissingWhenMissing'
                Value    = $whenMissing
                Message  = "Route '$routeKey' is optional but has no whenMissing guidance."
            })
        }
    }

    return @($issues.ToArray())
}

function Invoke-MetraProjectContextAudit {
    <#
    .SYNOPSIS
        Read-only context audit for one or more projects; optional drift check against projects.json.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$DriftOnly,
        [switch]$MetadataOnly,
        [switch]$Quiet,
        [int]$LargeFileBytes = 200KB,
        [int]$HighCardinalityCount = 200,
        [int]$ScanDepth = 4
    )

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

    function Write-RouteMetadataAdvisories {
        param([object[]]$Findings)

        $count = @($Findings).Count
        if ($count -eq 0) {
            Write-AuditHost 'Route metadata advisories: none' -ForegroundColor Green
            return
        }

        Write-AuditHost ("Route metadata advisories: {0}" -f $count)
        foreach ($f in @($Findings)) {
            Write-AuditHost ("[Advisory] {0} {1} {2} - {3}" -f $f.Route, $f.Field, $f.Issue, $f.Message)
        }
    }

    if ($MetadataOnly) {
        $metadataFindings = @(Get-MetraRouteMetadataIssues)
        Write-AuditHost ''
        Write-RouteMetadataAdvisories -Findings $metadataFindings
        $global:LASTEXITCODE = 0
        Write-Output ([PSCustomObject]@{
            ProjectCount     = 0
            DriftCount       = 0
            DriftOnly        = [bool]$DriftOnly
            MetadataOnly     = $true
            MetadataFindings = $metadataFindings
            MetadataCount    = $metadataFindings.Count
            Reports          = @()
        })
        return
    }

    $registry = Get-MetraProjectRegistry
    $projects = @(Resolve-MetraProjectSet -Filter $Filter -Name $Name -Root $Root)
    $generatedHints = Get-MetraGeneratedPathHints
    $driftCount = 0
    $reports = @()

    $rootInfo = @{}
    foreach ($r in @(Get-MetraRoots -IncludeMissing)) {
        $rootInfo[$r.Name] = $r
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
                if ([bool](Get-MetraProp -Object $reg -Name 'optional' -Default $false)) {
                    Write-AuditHost ("optional: {0} not installed here (advice-only routing)" -f $reg.name)
                }
                else {
                    $driftCount++
                    Write-AuditHost ("DRIFT: registry project missing on disk: {0}" -f $reg.name) -ForegroundColor Yellow
                }
            }
        }
    }

    foreach ($project in $projects) {
        $reg = Get-MetraRegistryProject -Registry $registry -Name $project.Name
        $inRegistry = $null -ne $reg
        $findings = @()
        $advisories = @()
        $largeFiles = @()
        $highCard = @()
        $generatedHits = @()

        $projectRoot = if ($rootInfo.ContainsKey($project.Root)) { $rootInfo[$project.Root] } else { $null }
        # Light roots (cloud-synced personal folders) get metadata checks only: a deep recursive
        # scan would hydrate placeholder files just to measure them.
        $lightAudit = $null -ne $projectRoot -and ($projectRoot.Audit -eq 'light')

        $hasAgents = Test-Path -LiteralPath (Join-Path $project.Path 'AGENTS.md')
        $hasIgnore = Test-Path -LiteralPath (Join-Path $project.Path '.cursorignore')
        $hasReadme = Test-Path -LiteralPath (Join-Path $project.Path 'README.md')

        if (-not $inRegistry) {
            $findings += 'Missing from registry (projects.json or projects.local.json)'
            $driftCount++
        }
        else {
            if (-not $hasAgents -and [string]$reg.entry -eq 'AGENTS.md') {
                $findings += 'Registry entry expects AGENTS.md but file is missing'
                $driftCount++
            }
            foreach ($ex in @($reg.excludePaths)) {
                if ([string]::IsNullOrWhiteSpace([string]$ex)) { continue }
                if ((Test-MetraPathExists -Root $project.Path -Relative ([string]$ex)) -and -not $hasIgnore) {
                    if ($lightAudit) {
                        $advisories += "excludePath '$ex' exists but .cursorignore is missing"
                    }
                    else {
                        $findings += "excludePath '$ex' exists but .cursorignore is missing"
                        $driftCount++
                    }
                    break
                }
            }
            foreach ($pref in @($reg.preferredPaths)) {
                if ([string]::IsNullOrWhiteSpace([string]$pref)) { continue }
                if ($pref -eq 'AGENTS.md' -or $pref -eq 'README.md') { continue }
                if (-not (Test-MetraPathExists -Root $project.Path -Relative ([string]$pref))) {
                    $findings += "preferredPath missing: $pref"
                }
            }
        }

        if (-not $lightAudit) {
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
                    if ($lightAudit) {
                        $advisories += "Generated/cache path not covered by registry exclude or .cursorignore: $hint"
                    }
                    else {
                        $findings += "Generated/cache path not covered by registry exclude or .cursorignore: $hint"
                        $driftCount++
                    }
                }
            }
        }

        $largeFileList = New-Object System.Collections.ArrayList
        $highCardList = New-Object System.Collections.ArrayList

        if (-not $lightAudit) {
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
        }

        $largeFiles = @($largeFileList.ToArray())
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
            Root              = $project.Root
            LightAudit        = $lightAudit
            RegistrySource    = if ($inRegistry) { [string](Get-MetraProp -Object $reg -Name 'source' -Default 'shared') } else { '' }
            InRegistry        = $inRegistry
            HasAgentsMd       = $hasAgents
            HasCursorIgnore   = $hasIgnore
            HasReadme         = $hasReadme
            GeneratedPaths    = $generatedHits
            LargeFiles        = $largeFiles
            HighCardinality   = $highCard
            Findings          = $findings
            Advisories        = $advisories
            SuggestedTriggers = $suggestedTriggers
            Drift             = ($findings.Count -gt 0 -or -not $inRegistry)
        }
        $reports += $report

        if ($DriftOnly) {
            if ($report.Drift) {
                Write-AuditHost ("DRIFT: {0} ({1})" -f $project.Name, $project.Root) -ForegroundColor Yellow
                foreach ($f in $findings) { Write-AuditHost ("  - {0}" -f $f) }
            }
            continue
        }

        Write-AuditHost ""
        Write-AuditHost ("==== {0} ({1}) ====" -f $project.Name, $project.Root) -ForegroundColor Cyan
        Write-AuditHost ("Registry: {0} | AGENTS.md: {1} | .cursorignore: {2}{3}" -f $inRegistry, $hasAgents, $hasIgnore, $(if ($lightAudit) { ' | light scan' } else { '' }))
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
        if ($advisories.Count -gt 0) {
            Write-AuditHost 'Advisory (light root, not counted as drift):'
            foreach ($a in $advisories) { Write-AuditHost ("  - {0}" -f $a) }
        }
        if ($suggestedTriggers.Count -gt 0 -and -not $inRegistry) {
            Write-AuditHost ("Suggested triggers: {0}" -f ($suggestedTriggers -join ', '))
        }
    }

    $metadataFindings = @(Get-MetraRouteMetadataIssues)
    Write-AuditHost ''
    Write-RouteMetadataAdvisories -Findings $metadataFindings

    $summary = [PSCustomObject]@{
        ProjectCount     = @($reports).Count
        DriftCount       = $driftCount
        DriftOnly        = [bool]$DriftOnly
        MetadataOnly     = $false
        MetadataFindings = $metadataFindings
        MetadataCount    = $metadataFindings.Count
        Reports          = $reports
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

