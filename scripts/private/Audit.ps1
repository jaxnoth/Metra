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

function Get-MetraAuditSuggestedTriggersFromText {
    <#
    .SYNOPSIS
        Extract suggested registry triggers from README text (size-capped).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text,
        [int]$MaxChars = 200000
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $slice = [string]$Text
    if ($MaxChars -gt 0 -and $slice.Length -gt $MaxChars) {
        $slice = $slice.Substring(0, $MaxChars)
    }

    return @(
        [regex]::Matches($slice.ToLowerInvariant(), '[a-z][a-z0-9_-]{3,}') |
            ForEach-Object { $_.Value } |
            Where-Object { $_ -notin @('this', 'that', 'with', 'from', 'have', 'project', 'readme', 'table', 'contents') } |
            Group-Object |
            Sort-Object Count -Descending |
            Select-Object -First 8 -ExpandProperty Name
    )
}


function Get-MetraAgentsLineBudget {
    <#
    .SYNOPSIS
        Default-context AGENTS stub line budget from metra.config.json audit.agentsLineBudget.
    #>
    [CmdletBinding()]
    param()

    $default = 100
    try {
        $cfg = Get-MetraConfig
        $audit = Get-MetraProp -Object $cfg -Name 'audit' -Default $null
        $budget = Get-MetraProp -Object $audit -Name 'agentsLineBudget' -Default $null
        if ($null -ne $budget) {
            $parsed = 0
            if ([int]::TryParse([string]$budget, [ref]$parsed) -and $parsed -gt 0) {
                return $parsed
            }
            Write-Warning "Invalid audit.agentsLineBudget '$budget'; using default $default."
        }
    }
    catch {
        # Missing config falls back to default budget.
    }
    return $default
}

function Get-MetraFilePhysicalLineCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return @((Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)).Count
}

function Get-MetraPathRelativeToAuditRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FullPath,
        [Parameter(Mandatory)][string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($FullPath) -or [string]::IsNullOrWhiteSpace($Root)) { return $FullPath }
    $rootNorm = $Root.TrimEnd('\', '/')
    $sep = [System.IO.Path]::DirectorySeparatorChar
    if ($FullPath.Equals($rootNorm, [StringComparison]::OrdinalIgnoreCase)) { return '' }
    $prefix = $rootNorm + $sep
    if ($FullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($prefix.Length)
    }
    return $FullPath
}

function Test-MetraCursorRuleAlwaysApply {
    <#
    .SYNOPSIS
        True when a .cursor/rules/*.mdc front matter sets alwaysApply: true.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    $inFrontMatter = $false
    foreach ($line in $lines) {
        if ($line -eq '---') {
            if (-not $inFrontMatter) {
                $inFrontMatter = $true
                continue
            }
            break
        }
        if (-not $inFrontMatter) { continue }
        if ($line -match '(?i)^alwaysApply:\s*true\s*$') { return $true }
        if ($line -match '(?i)^alwaysApply:\s*false\s*$') { return $false }
    }
    return $false
}

function Get-MetraAgentsLineAuditForPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AgentsPath,
        [int]$Budget = 0
    )

    if ($Budget -le 0) { $Budget = Get-MetraAgentsLineBudget }
    if (-not (Test-Path -LiteralPath $AgentsPath)) {
        return [pscustomobject]@{
            LineCount = 0
            Budget    = $Budget
            Status    = 'missing'
            Message   = 'AGENTS.md: missing'
        }
    }

    $lines = Get-MetraFilePhysicalLineCount -Path $AgentsPath
    $status = if ($lines -gt $Budget) { 'WARN' } else { 'OK' }
    $message = if ($status -eq 'WARN') {
        "AGENTS.md: $lines lines WARN over budget $Budget"
    }
    else {
        "AGENTS.md: $lines lines OK budget $Budget"
    }

    return [pscustomobject]@{
        LineCount = $lines
        Budget    = $Budget
        Status    = $status
        Message   = $message
    }
}

function Test-MetraAgentsMarkdownHeadingPresent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string[]]$HeadingPatterns
    )

    foreach ($pattern in $HeadingPatterns) {
        if ($Content -match $pattern) { return $true }
    }
    return $false
}

function Get-MetraAgentsStubShapeAuditForPath {
    <#
    .SYNOPSIS
        Report-only A2 desk stub shape check for AGENTS.md (advisory WARN only).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AgentsPath,
        [Parameter(Mandatory)][string]$ProjectPath
    )

    if (-not (Test-Path -LiteralPath $AgentsPath)) {
        return [pscustomobject]@{
            Status                   = 'missing'
            Message                  = 'AGENTS stub shape: missing file'
            MissingSections          = @()
            UnlinkedRequestableRules = @()
        }
    }

    $content = [string](Get-Content -Raw -LiteralPath $AgentsPath -ErrorAction SilentlyContinue)
    $missing = New-Object System.Collections.Generic.List[string]

    if (-not (Test-MetraAgentsMarkdownHeadingPresent -Content $content -HeadingPatterns @('(?m)^##\s+Route here when\s*$'))) {
        [void]$missing.Add('Route here when')
    }
    if (-not (Test-MetraAgentsMarkdownHeadingPresent -Content $content -HeadingPatterns @('(?m)^##\s+Start here\s*$'))) {
        [void]$missing.Add('Start here')
    }
    if (-not (Test-MetraAgentsMarkdownHeadingPresent -Content $content -HeadingPatterns @('(?m)^##\s+Ceilings\s*$', '(?m)^##\s+Do not\s*$', '(?m)^##\s+Portfolio rules\s*$'))) {
        [void]$missing.Add('Ceilings')
    }
    if (-not (Test-MetraAgentsMarkdownHeadingPresent -Content $content -HeadingPatterns @('(?m)^##\s+Token rules\s*$'))) {
        [void]$missing.Add('Token rules')
    }

    $playbooksDir = Join-Path $ProjectPath 'docs\playbooks'
    if (Test-Path -LiteralPath $playbooksDir) {
        $playbookCount = @(Get-ChildItem -LiteralPath $playbooksDir -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
        if ($playbookCount -gt 0 -and -not (Test-MetraAgentsMarkdownHeadingPresent -Content $content -HeadingPatterns @('(?m)^##\s+On-demand playbooks\s*$'))) {
            [void]$missing.Add('On-demand playbooks')
        }
    }

    $unlinked = New-Object System.Collections.Generic.List[string]
    $rulesDir = Join-Path $ProjectPath '.cursor\rules'
    if (Test-Path -LiteralPath $rulesDir) {
        foreach ($ruleFile in @(Get-ChildItem -LiteralPath $rulesDir -Filter '*.mdc' -File -ErrorAction SilentlyContinue)) {
            if ($ruleFile.Name -like '*.example.mdc') { continue }
            if (Test-MetraCursorRuleAlwaysApply -Path $ruleFile.FullName) { continue }
            $ruleName = $ruleFile.Name
            $ruleStem = $ruleFile.BaseName
            if ($content -notmatch [regex]::Escape($ruleName) -and $content -notmatch [regex]::Escape($ruleStem)) {
                [void]$unlinked.Add($ruleName)
            }
        }
    }

    $status = if ($missing.Count -eq 0 -and $unlinked.Count -eq 0) { 'OK' } else { 'WARN' }
    $parts = @()
    if ($missing.Count -gt 0) { $parts += "missing sections: $($missing -join ', ')" }
    if ($unlinked.Count -gt 0) { $parts += "unlinked requestable rules: $($unlinked -join ', ')" }
    $message = if ($status -eq 'OK') { 'AGENTS stub shape: OK' } else { "AGENTS stub shape: WARN ($($parts -join '; '))" }

    return [pscustomobject]@{
        Status                   = $status
        Message                  = $message
        MissingSections          = @($missing.ToArray())
        UnlinkedRequestableRules = @($unlinked.ToArray())
    }
}

function Get-MetraContextFootprintEstimate {
    <#
    .SYNOPSIS
        Report-only estimate of Metra-controlled default-context prefix size.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Projects = @()
    )

    $rulesLines = 0
    $ruleDetails = New-Object System.Collections.Generic.List[object]
    $seenRulePaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $metraRoot = Get-MetraRoot

    $scanRoots = New-Object System.Collections.Generic.List[string]
    [void]$scanRoots.Add($metraRoot)
    foreach ($project in @($Projects)) {
        if ($null -ne $project.Path -and -not [string]::IsNullOrWhiteSpace([string]$project.Path)) {
            [void]$scanRoots.Add([string]$project.Path)
        }
    }

    foreach ($root in @($scanRoots | Select-Object -Unique)) {
        $rulesDir = Join-Path $root '.cursor\rules'
        if (-not (Test-Path -LiteralPath $rulesDir)) { continue }
        foreach ($ruleFile in @(Get-ChildItem -LiteralPath $rulesDir -Filter '*.mdc' -File -ErrorAction SilentlyContinue)) {
            if (-not $seenRulePaths.Add($ruleFile.FullName)) { continue }
            if (Test-MetraCursorRuleAlwaysApply -Path $ruleFile.FullName) {
                $lineCount = Get-MetraFilePhysicalLineCount -Path $ruleFile.FullName
                $rulesLines += $lineCount
                $relativePath = $ruleFile.FullName
                foreach ($candidateRoot in @($scanRoots | Select-Object -Unique | Sort-Object { $_.Length } -Descending)) {
                    $rel = Get-MetraPathRelativeToAuditRoot -FullPath $ruleFile.FullName -Root $candidateRoot
                    if ($rel -ne $ruleFile.FullName) {
                        $relativePath = $rel
                        break
                    }
                }
                [void]$ruleDetails.Add([pscustomobject]@{
                    Path  = $relativePath
                    Lines = $lineCount
                })
            }
        }
    }

    $agentsLines = 0
    foreach ($project in @($Projects)) {
        if ($null -eq $project.Path -or [string]::IsNullOrWhiteSpace([string]$project.Path)) { continue }
        $agentsPath = Join-Path $project.Path 'AGENTS.md'
        if (Test-Path -LiteralPath $agentsPath) {
            $agentsLines += Get-MetraFilePhysicalLineCount -Path $agentsPath
        }
    }

    return [pscustomobject]@{
        AlwaysApplyRulesLines = $rulesLines
        AlwaysApplyRules      = @($ruleDetails | Sort-Object -Property Lines -Descending)
        MountedAgentsLines    = $agentsLines
        TotalEstimated        = $rulesLines + $agentsLines
    }
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

                # Lowercase before Contains so case-sensitive stop lists still match.
                $triggerKey = $normalizedTrigger.ToLowerInvariant()
                if ($stopWords.Contains($triggerKey)) {
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
        [ValidateRange(1, 2147483647)]
        [int]$LargeFileBytes = 200KB,
        [ValidateRange(1, 100000)]
        [int]$HighCardinalityCount = 200,
        [ValidateRange(1, 20)]
        [int]$ScanDepth = 4
    )

    if ($DriftOnly -and $MetadataOnly) {
        throw 'DriftOnly and MetadataOnly are mutually exclusive.'
    }

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
            DriftFindings    = 0
            DriftProjects    = 0
            DriftCount       = 0 # alias of DriftFindings (backward compatible)
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
    $agentsLineBudget = Get-MetraAgentsLineBudget
    $generatedHints = Get-MetraGeneratedPathHints
    # DriftFindings = actionable finding rows; DriftProjects = distinct projects with drift.
    $driftFindings = 0
    $registryMissingNames = New-Object System.Collections.Generic.List[string]
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
                    $driftFindings++
                    [void]$registryMissingNames.Add($key)
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

        $agentsPath = Join-Path $project.Path 'AGENTS.md'
        $agentsLineAudit = Get-MetraAgentsLineAuditForPath -AgentsPath $agentsPath -Budget $agentsLineBudget
        $agentsStubShapeAudit = if ($hasAgents) {
            Get-MetraAgentsStubShapeAuditForPath -AgentsPath $agentsPath -ProjectPath $project.Path
        }
        else {
            [pscustomobject]@{
                Status                   = 'missing'
                Message                  = 'AGENTS stub shape: missing file'
                MissingSections          = @()
                UnlinkedRequestableRules = @()
            }
        }

        if (-not $inRegistry) {
            $findings += 'Missing from registry (projects.json or projects.local.json)'
            $driftFindings++
        }
        else {
            if (-not $hasAgents -and [string]$reg.entry -eq 'AGENTS.md') {
                $findings += 'Registry entry expects AGENTS.md but file is missing'
                $driftFindings++
            }
            foreach ($ex in @($reg.excludePaths)) {
                if ([string]::IsNullOrWhiteSpace([string]$ex)) { continue }
                if ((Test-MetraPathExists -Root $project.Path -Relative ([string]$ex)) -and -not $hasIgnore) {
                    if ($lightAudit) {
                        $advisories += "excludePath '$ex' exists but .cursorignore is missing"
                    }
                    else {
                        $findings += "excludePath '$ex' exists but .cursorignore is missing"
                        $driftFindings++
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
                if ($inRegistry) { $driftFindings++ }
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
                        $driftFindings++
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
                $suggestedTriggers = @(Get-MetraAuditSuggestedTriggersFromText -Text ([string]$readmeText))
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
            AgentsLineCount              = $agentsLineAudit.LineCount
            AgentsLineBudget             = $agentsLineAudit.Budget
            AgentsLineStatus             = $agentsLineAudit.Status
            AgentsLineMessage            = $agentsLineAudit.Message
            AgentsStubShapeStatus        = $agentsStubShapeAudit.Status
            AgentsStubShapeMessage       = $agentsStubShapeAudit.Message
            AgentsStubShapeMissing       = @($agentsStubShapeAudit.MissingSections)
            AgentsStubShapeUnlinkedRules = @($agentsStubShapeAudit.UnlinkedRequestableRules)
            Drift                        = ($findings.Count -gt 0 -or -not $inRegistry)
        }
        $reports += $report

        if ($DriftOnly) {
            if ($report.Drift) {
                Write-AuditHost ("DRIFT: {0} ({1})" -f $project.Name, $project.Root) -ForegroundColor Yellow
                foreach ($f in $findings) { Write-AuditHost ("  - {0}" -f $f) }
            }
            if ($agentsLineAudit.Status -eq 'WARN') {
                Write-AuditHost ("WARN {0} AGENTS.md {1} lines exceeds budget {2}" -f $project.Name, $agentsLineAudit.LineCount, $agentsLineAudit.Budget) -ForegroundColor Yellow
            }
            if ($agentsStubShapeAudit.Status -eq 'WARN') {
                Write-AuditHost ("WARN {0} {1}" -f $project.Name, $agentsStubShapeAudit.Message) -ForegroundColor Yellow
            }
            continue
        }

        Write-AuditHost ""
        Write-AuditHost ("==== {0} ({1}) ====" -f $project.Name, $project.Root) -ForegroundColor Cyan
        Write-AuditHost ("Registry: {0} | AGENTS.md: {1} | .cursorignore: {2}{3}" -f $inRegistry, $hasAgents, $hasIgnore, $(if ($lightAudit) { ' | light scan' } else { '' }))
        if ($hasAgents) {
            $agentsColor = if ($agentsLineAudit.Status -eq 'WARN') { [ConsoleColor]::Yellow } else { [ConsoleColor]::Green }
            Write-AuditHost $agentsLineAudit.Message -ForegroundColor $agentsColor
            $shapeColor = if ($agentsStubShapeAudit.Status -eq 'WARN') { [ConsoleColor]::Yellow } else { [ConsoleColor]::Green }
            Write-AuditHost $agentsStubShapeAudit.Message -ForegroundColor $shapeColor
        }
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

    $contextFootprint = Get-MetraContextFootprintEstimate -Projects $projects
    if (-not $DriftOnly) {
        Write-AuditHost ''
        Write-AuditHost 'Context Footprint Estimate'
        Write-AuditHost '--------------------------'
        Write-AuditHost ("AlwaysApply rules: {0} lines" -f $contextFootprint.AlwaysApplyRulesLines)
        foreach ($ruleRow in @($contextFootprint.AlwaysApplyRules)) {
            Write-AuditHost ("  {0,4} lines  {1}" -f $ruleRow.Lines, $ruleRow.Path)
        }
        Write-AuditHost ("Mounted AGENTS:    {0} lines" -f $contextFootprint.MountedAgentsLines)
        Write-AuditHost ("Total estimated:   {0} lines" -f $contextFootprint.TotalEstimated)
    }

    $metadataFindings = @(Get-MetraRouteMetadataIssues)
    Write-AuditHost ''
    Write-RouteMetadataAdvisories -Findings $metadataFindings

    $driftProjectKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($missingName in @($registryMissingNames)) {
        [void]$driftProjectKeys.Add([string]$missingName)
    }
    foreach ($rep in @($reports)) {
        if ($rep.Drift) {
            [void]$driftProjectKeys.Add([string]$rep.Name)
        }
    }
    $driftProjects = $driftProjectKeys.Count
    $agentsLineWarnCount = @($reports | Where-Object { $_.AgentsLineStatus -eq 'WARN' }).Count
    $agentsStubShapeWarnCount = @($reports | Where-Object { $_.AgentsStubShapeStatus -eq 'WARN' }).Count

    $summary = [PSCustomObject]@{
        ProjectCount     = @($reports).Count
        DriftFindings    = $driftFindings
        DriftProjects    = $driftProjects
        DriftCount       = $driftFindings # alias of DriftFindings (backward compatible)
        DriftOnly        = [bool]$DriftOnly
        MetadataOnly     = $false
        MetadataFindings = $metadataFindings
        MetadataCount           = $metadataFindings.Count
        AgentsLineBudget        = $agentsLineBudget
        AgentsLineWarnCount     = $agentsLineWarnCount
        AgentsStubShapeWarnCount = $agentsStubShapeWarnCount
        ContextFootprintEstimate = $contextFootprint
        Reports                 = $reports
    }

    if ($DriftOnly) {
        Write-AuditHost ""
        Write-AuditHost ("Drift projects: {0}; drift findings: {1}; AGENTS budget WARN: {2}; AGENTS stub shape WARN: {3} (advisory)" -f $driftProjects, $driftFindings, $agentsLineWarnCount, $agentsStubShapeWarnCount) -ForegroundColor $(if ($driftFindings -gt 0 -or $driftProjects -gt 0) { 'Yellow' } else { 'Green' })
        if ($driftFindings -gt 0 -or $driftProjects -gt 0) {
            $global:LASTEXITCODE = 1
        }
        else {
            $global:LASTEXITCODE = 0
        }
    }

    Write-Output $summary
}

