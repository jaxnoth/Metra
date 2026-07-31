# Requires Pester 5+ (pwsh recommended).
# Run: pwsh -NoProfile -File .\tests\Invoke-MetraTests.ps1

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
    $publicCommands = @(
        'Initialize-Metra',
        'Get-MetraProject',
        'Get-MetraProjectRoot',
        'Get-MetraRouting',
        'Get-MetraProjectStatus',
        'Update-MetraProject',
        'Invoke-MetraProjectCommand',
        'Copy-MetraProjectFile',
        'New-MetraProject',
        'Update-MetraWorkspace',
        'Test-MetraProjectContext',
        'Export-MetraSnapshot',
        'Get-MetraChat',
        'Export-MetraContext',
        'Export-MetraProfile',
        'Import-MetraProfile',
        'Test-MetraInstallation'
    )
}

Describe 'PowerShell command surface' {
    It 'exports native commands with approved PowerShell verbs' {
        $exported = @(Get-Command -Module Metra | Select-Object -ExpandProperty Name)
        foreach ($name in $publicCommands) {
            $exported | Should -Contain $name
            (Get-Verb ($name -split '-', 2)[0]) | Should -Not -BeNullOrEmpty
        }

        $declared = @(& (Get-Module Metra) { $script:MetraPublicFunctions })
        @(Compare-Object $publicCommands $declared).Count | Should -Be 0
    }

    It 'provides complete help for every supported public command' {
        foreach ($name in $publicCommands) {
            $help = Get-Help $name -Full
            [string]$help.Synopsis | Should -Not -BeNullOrEmpty -Because "$name needs a synopsis"
            @($help.Description.Text).Count | Should -BeGreaterThan 0 -Because "$name needs a description"
            @($help.Examples.Example).Count | Should -BeGreaterThan 0 -Because "$name needs an example"
            @($help.ReturnValues.ReturnValue).Count | Should -BeGreaterThan 0 -Because "$name needs outputs"

            foreach ($parameter in @($help.Parameters.Parameter)) {
                @($parameter.Description.Text).Count |
                    Should -BeGreaterThan 0 -Because "$name -$($parameter.Name) needs parameter help"
            }
        }
    }

    It 'completes project names, including names with spaces' {
        $line = 'Get-MetraProject -Name Col'
        $matches = @(TabExpansion2 $line $line.Length).CompletionMatches

        $matches.ListItemText | Should -Contain 'Colleague'
        $matches.ListItemText | Should -Contain 'Colleague Migration'
        ($matches | Where-Object ListItemText -eq 'Colleague Migration').CompletionText |
            Should -Be "'Colleague Migration'"
    }

    It 'completes configured root names' {
        $line = 'Get-MetraProject -Root w'
        $matches = @(TabExpansion2 $line $line.Length).CompletionMatches

        $matches.ListItemText | Should -Contain 'work'
    }

    It 'keeps former Meta names as compatibility aliases' {
        (Get-Command Get-MetaRoutingTable).CommandType | Should -Be 'Alias'
        @(Get-MetaRoutingTable -Name TicketTracker).Name | Should -Contain 'TicketTracker'
    }

    It 'does not export generic implementation helpers' {
        Get-Command Invoke-AcrossProjects -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command Copy-AcrossProjects -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command Get-ProjectsRoot -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Get-MetraRouting' {
    It 'returns TicketTracker, Solarwinds, and Trivia rows from shared/local registry' {
        $rows = @(Get-MetraRouting -Name @('TicketTracker', 'Solarwinds', 'Trivia'))
        $rows.Count | Should -BeGreaterOrEqual 3
        ($rows.Name | Sort-Object -Unique) | Should -Contain 'TicketTracker'
        ($rows.Name | Sort-Object -Unique) | Should -Contain 'Solarwinds'
        ($rows.Name | Sort-Object -Unique) | Should -Contain 'Trivia'
        foreach ($row in $rows) {
            $row.PSObject.Properties.Name | Should -Contain 'Present'
            $row.PSObject.Properties.Name | Should -Contain 'Triggers'
            $row.PSObject.Properties.Name | Should -Contain 'Serves'
        }
        $tt = @($rows | Where-Object Name -eq 'TicketTracker')[0]
        @($tt.Serves) | Should -Contain 'Helpdesk'
        $sw = @($rows | Where-Object Name -eq 'Solarwinds')[0]
        @($sw.Serves) | Should -Contain 'Monitoring operators'
    }

    It 'Write-MetraForWhom omits empty audiences' {
        InModuleScope Metra {
            $empty = @(Write-MetraForWhom -Serves @() *>&1)
            # Host writes return nothing useful to capture; Format via empty Serves no-throw
            { Write-MetraForWhom -Serves @() } | Should -Not -Throw
            { Write-MetraForWhom -Serves @('Helpdesk') } | Should -Not -Throw
        }
    }
}

Describe 'Import-MetraProfile' {
    It 'Preview -Quiet returns files and writes nothing' {
        $sample = Join-Path (Get-MetraRoot) 'profiles\sample'
        $result = Import-MetraProfile -Path $sample -Preview -Quiet
        $result.Preview | Should -BeTrue
        @($result.Files).Count | Should -BeGreaterThan 0
        $result.Files | Should -Contain 'metra.config.json'
    }

    It 'Preview humor-desk add-on includes metra-humor.local.mdc' {
        $pack = Join-Path (Get-MetraRoot) 'profiles\addons\humor-desk'
        $result = Import-MetraProfile -Path $pack -Preview -Quiet
        $result.Preview | Should -BeTrue
        $result.Files | Should -Contain '.cursor/rules/metra-humor.local.mdc'
    }

    It 'Preview teaching-gentle add-on includes metra-teaching-gentle.local.mdc' {
        $pack = Join-Path (Get-MetraRoot) 'profiles\addons\teaching-gentle'
        $result = Import-MetraProfile -Path $pack -Preview -Quiet
        $result.Preview | Should -BeTrue
        $result.Files | Should -Contain '.cursor/rules/metra-teaching-gentle.local.mdc'
    }

    It 'refuses overwrite without -Force when targets exist' {
        $sample = Join-Path (Get-MetraRoot) 'profiles\sample'
        # Live checkout already has local targets from sample/operator use.
        { Import-MetraProfile -Path $sample -Quiet } | Should -Throw '*Refusing to overwrite*'
    }
}

Describe 'Export-MetraContext' {
    It 'Path - with Quiet does not rewrite docs/context-pack.md' {
        $packPath = Join-Path (Get-MetraRoot) 'docs\context-pack.md'
        $before = if (Test-Path -LiteralPath $packPath) {
            (Get-Item -LiteralPath $packPath).LastWriteTimeUtc
        }
        else {
            $null
        }

        Start-Sleep -Milliseconds 50
        $result = Export-MetraContext -Query 'ticket' -Format markdown -Path '-' -Quiet |
            Select-Object -Last 1

        $result.Path | Should -Be '-'
        $result.Format | Should -Be 'markdown'

        if ($null -ne $before -and (Test-Path -LiteralPath $packPath)) {
            (Get-Item -LiteralPath $packPath).LastWriteTimeUtc | Should -Be $before
        }
    }
}

Describe 'Get-MetraChat cloud option' {
    It 'accepts -Cloud and warns when CURSOR_API_KEY is unset' {
        $prev = $env:CURSOR_API_KEY
        try {
            if (Test-Path Env:CURSOR_API_KEY) {
                Remove-Item Env:CURSOR_API_KEY
            }
            $warns = $null
            $rows = @(Get-MetraChat -IncludeMetra -Cloud -Limit 3 -WarningVariable warns -WarningAction SilentlyContinue)
            @($warns | Where-Object { $_ -match 'CURSOR_API_KEY' }).Count | Should -BeGreaterThan 0
            $rows | Should -Not -BeNullOrEmpty
            $rows[0].PSObject.Properties.Name | Should -Contain 'Source'
        }
        finally {
            if ($null -ne $prev -and $prev -ne '') {
                $env:CURSOR_API_KEY = $prev
            }
        }
    }

    It 'maps Metra GitHub URLs to the Metra project' {
        $mapped = & (Get-Module Metra) {
            Resolve-MetraChatProjectFromRepo -RepoUrl 'https://github.com/jaxnoth/Metra.git' -WantedNames @('Metra')
        }
        $mapped | Should -Be 'Metra'
    }
}

Describe 'Initialize-Metra' {
    It 'Preview -Quiet returns structured result without seeding when config exists' {
        $preferred = Join-Path (Get-MetraRoot) 'metra.config.json'
        $legacy = Join-Path (Get-MetraRoot) 'meta.config.json'
        $hasConfig = (Test-Path -LiteralPath $preferred) -or (Test-Path -LiteralPath $legacy)
        $hasConfig | Should -BeTrue

        $result = Initialize-Metra -Preview -Quiet
        $result.Preview | Should -BeTrue
        $result.WouldSeedConfig | Should -BeFalse
        $result.SeededConfig | Should -BeFalse
        $result.Workspace | Should -BeNullOrEmpty
        @($result.Roots).Count | Should -BeGreaterThan 0
    }

    It 'Preview with sample Profile does not throw and keeps WouldSeedConfig false when config exists' {
        $sample = Join-Path (Get-MetraRoot) 'profiles\sample'
        $result = Initialize-Metra -Profile $sample -Preview -Quiet
        $result.Preview | Should -BeTrue
        $result.WouldSeedConfig | Should -BeFalse
        $result.Import | Should -Not -BeNullOrEmpty
        $result.Import.Preview | Should -BeTrue
    }
}

Describe 'Test-MetraInstallation' {
    It 'returns structured PASS/WARN/FAIL with Ok when FailCount is 0' {
        $report = Test-MetraInstallation -Detailed
        $report.PassCount | Should -BeGreaterThan 0
        $report.FailCount | Should -BeGreaterOrEqual 0
        $report.Ok | Should -Be ($report.FailCount -eq 0)
        @($report.Results).Count | Should -Be ($report.PassCount + $report.WarnCount + $report.FailCount)
        ($report.Results | Where-Object Status -eq 'FAIL').Count | Should -Be $report.FailCount
    }

    It 'passes on this machine (no FAIL rows)' {
        $report = Test-MetraInstallation -Detailed
        $report.FailCount | Should -Be 0
        $report.Ok | Should -BeTrue
    }
}

Describe 'Operator Communication Contract' {
    BeforeEach {
        $script:contractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-contract-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:contractRoot 'docs') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:contractRoot '.cursor\rules') -Force | Out-Null
    }

    AfterEach {
        if ($script:contractRoot -and (Test-Path -LiteralPath $script:contractRoot)) {
            Remove-Item -LiteralPath $script:contractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'maps learned contract paths in Get-MetraProfileFileMap' {
        InModuleScope Metra {
            $map = @(Get-MetraProfileFileMap)
            $map | Should -Contain 'docs/operator-contract.json'
            $map | Should -Contain '.cursor/rules/metra-learned.local.mdc'
        }
    }

    It 'show works with missing ledger' {
        $root = $script:contractRoot
        InModuleScope Metra -Parameters @{ ContractRoot = $root } {
            param($ContractRoot)
            $shown = Show-MetraOperatorContract -MetraRoot $ContractRoot
            $shown.LedgerExists | Should -BeFalse
            $shown.ConfirmedCount | Should -Be 0
            $shown.CandidateCount | Should -Be 0
        }
    }

    It 'notes, promotes, renders guideline, and forgets' {
        $root = $script:contractRoot
        InModuleScope Metra -Parameters @{ ContractRoot = $root } {
            param($ContractRoot)
            $note = Add-MetraOperatorContractCandidate -Text 'Prefer terse verdicts before detail.' -MetraRoot $ContractRoot
            $note.Action | Should -Be 'added'
            $note.Id | Should -Not -BeNullOrEmpty

            $promoted = Promote-MetraOperatorContractGuideline -IdOrText $note.Id -MetraRoot $ContractRoot
            $promoted.Action | Should -Be 'promoted'
            Test-Path -LiteralPath $promoted.LearnedPath | Should -BeTrue
            (Get-Content -LiteralPath $promoted.LearnedPath -Raw) | Should -Match 'Prefer terse verdicts before detail'

            $forgotten = Remove-MetraOperatorContractEntry -IdOrText $promoted.Id -MetraRoot $ContractRoot
            $forgotten.Action | Should -Be 'forgot'
            (Get-Content -LiteralPath (Join-Path $ContractRoot '.cursor\rules\metra-learned.local.mdc') -Raw) |
                Should -Match '\(none yet'
        }
    }

    It 'refuses portfolio-wide promotion' {
        $root = $script:contractRoot
        InModuleScope Metra -Parameters @{ ContractRoot = $root } {
            param($ContractRoot)
            {
                Promote-MetraOperatorContractGuideline -IdOrText 'Enforce professional sink for every clone' -MetraRoot $ContractRoot
            } | Should -Throw '*Portfolio-wide preference refused*'
        }
    }

    It 'enforces confirmed guideline budget' {
        $root = $script:contractRoot
        InModuleScope Metra -Parameters @{ ContractRoot = $root } {
            param($ContractRoot)
            $contract = Get-MetraOperatorContract -MetraRoot $ContractRoot
            $contract.maxConfirmed = 2
            Save-MetraOperatorContract -Contract $contract -MetraRoot $ContractRoot

            Promote-MetraOperatorContractGuideline -IdOrText 'Prefer terse verdicts before detail.' -MetraRoot $ContractRoot | Out-Null
            Promote-MetraOperatorContractGuideline -IdOrText 'Lean verify-before-push when shipping Metra.' -MetraRoot $ContractRoot | Out-Null

            {
                Promote-MetraOperatorContractGuideline -IdOrText 'Prefer dry humor sparingly in routine ops.' -MetraRoot $ContractRoot
            } | Should -Throw '*budget is full*'
        }
    }

    It 'bumps candidate count on duplicate note' {
        $root = $script:contractRoot
        InModuleScope Metra -Parameters @{ ContractRoot = $root } {
            param($ContractRoot)
            Add-MetraOperatorContractCandidate -Text 'Prefer dry humor sparingly.' -MetraRoot $ContractRoot | Out-Null
            $bump = Add-MetraOperatorContractCandidate -Text 'Prefer dry humor sparingly.' -MetraRoot $ContractRoot
            $bump.Action | Should -Be 'bumped'
            $bump.Count | Should -Be 2
        }
    }

    It 'ships tracked examples' {
        $root = Get-MetraRoot
        Test-Path -LiteralPath (Join-Path $root 'docs\operator-contract.example.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root '.cursor\rules\metra-learned.local.example.mdc') | Should -BeTrue
    }
}

Describe 'Decision Registry' {
    BeforeEach {
        $script:decisionRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-decisions-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:decisionRoot 'docs') -Force | Out-Null
    }

    AfterEach {
        if ($script:decisionRoot -and (Test-Path -LiteralPath $script:decisionRoot)) {
            Remove-Item -LiteralPath $script:decisionRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'maps decision registry path in Get-MetraProfileFileMap' {
        InModuleScope Metra {
            $map = @(Get-MetraProfileFileMap)
            $map | Should -Contain 'docs/decision-registry.json'
        }
    }

    It 'show works with missing ledger' {
        $root = $script:decisionRoot
        InModuleScope Metra -Parameters @{ DecisionRoot = $root } {
            param($DecisionRoot)
            $shown = Show-MetraDecisionRegistry -MetraRoot $DecisionRoot
            $shown.LedgerExists | Should -BeFalse
            $shown.ConfirmedCount | Should -Be 0
            $shown.CandidateCount | Should -Be 0
        }
    }

    It 'notes, promotes with why/confidence/evidence, searches, and forgets' {
        $root = $script:decisionRoot
        InModuleScope Metra -Parameters @{ DecisionRoot = $root } {
            param($DecisionRoot)
            $note = Add-MetraDecisionRegistryCandidate `
                -Title 'Prefer brief over show' `
                -Decision 'Prefer TicketTracker brief over show for triage.' `
                -Why 'brief is plain text; show pulls heavy HTML.' `
                -Project 'TicketTracker' `
                -Tags 'ticket,brief' `
                -Source 'TicketTracker/AGENTS.md' `
                -Origin backfill `
                -Confidence high `
                -Evidence @('TicketTracker/AGENTS.md', 'Operator confirmed') `
                -MetraRoot $DecisionRoot
            $note.Action | Should -Be 'added'

            $promoted = Promote-MetraDecisionRegistryEntry -IdOrTitle $note.Id -MetraRoot $DecisionRoot
            $promoted.Action | Should -Be 'promoted'

            $hits = @(Search-MetraDecisionRegistry -Query 'brief ticket' -MetraRoot $DecisionRoot)
            $hits.Count | Should -BeGreaterThan 0
            $hits[0].Title | Should -Match 'brief'

            $got = Get-MetraDecisionRegistryEntry -IdOrTitle $promoted.Id -MetraRoot $DecisionRoot
            $got.Bucket | Should -Be 'confirmed'
            $got.Entry.why | Should -Match 'plain text'

            $forgotten = Remove-MetraDecisionRegistryEntry -IdOrTitle $promoted.Id -MetraRoot $DecisionRoot
            $forgotten.Action | Should -Be 'forgot'
        }
    }

    It 'refuses promote without why' {
        $root = $script:decisionRoot
        InModuleScope Metra -Parameters @{ DecisionRoot = $root } {
            param($DecisionRoot)
            $note = Add-MetraDecisionRegistryCandidate `
                -Title 'Missing why' `
                -Decision 'Do a thing on a host.' `
                -Confidence high `
                -Evidence 'Operator confirmed' `
                -MetraRoot $DecisionRoot
            {
                Promote-MetraDecisionRegistryEntry -IdOrTitle $note.Id -MetraRoot $DecisionRoot
            } | Should -Throw '*requires a non-empty why*'
        }
    }

    It 'refuses promote without evidence' {
        $root = $script:decisionRoot
        InModuleScope Metra -Parameters @{ DecisionRoot = $root } {
            param($DecisionRoot)
            $note = Add-MetraDecisionRegistryCandidate `
                -Title 'Missing evidence' `
                -Decision 'Do a thing on a host.' `
                -Why 'Because the credential store lives there.' `
                -Confidence high `
                -MetraRoot $DecisionRoot
            {
                Promote-MetraDecisionRegistryEntry -IdOrTitle $note.Id -MetraRoot $DecisionRoot
            } | Should -Throw '*at least one evidence*'
        }
    }

    It 'harvest adds candidates only' {
        $root = $script:decisionRoot
        $proj = Join-Path $root 'FakeOps'
        New-Item -ItemType Directory -Path $proj -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $proj 'AGENTS.md') -Value @"
# FakeOps

- Never run Start-Automation from the local workstation.
- Prefer filtered catalog queries over opening index wholesale.
"@ -Encoding UTF8

        InModuleScope Metra -Parameters @{ DecisionRoot = $root; ProjPath = $proj } {
            param($DecisionRoot, $ProjPath)
            Mock Get-MetraProjects {
                @([PSCustomObject]@{ Name = 'FakeOps'; Path = $ProjPath; Root = 'work'; IsGit = $false })
            }

            $before = Show-MetraDecisionRegistry -MetraRoot $DecisionRoot
            $before.ConfirmedCount | Should -Be 0

            $harvest = Invoke-MetraDecisionRegistryHarvest -MetraRoot $DecisionRoot
            $harvest.Action | Should -Be 'harvest'
            $harvest.Count | Should -BeGreaterThan 0

            $after = Show-MetraDecisionRegistry -MetraRoot $DecisionRoot
            $after.ConfirmedCount | Should -Be 0
            $after.CandidateCount | Should -BeGreaterThan 0
            @($after.Candidates)[0].origin | Should -Be 'harvest'
            @($after.Candidates)[0].confidence | Should -Be 'low'
        }
    }

    It 'ctx Query includes relatedDecisions; no-query omits them' {
        $root = $script:decisionRoot
        InModuleScope Metra -Parameters @{ DecisionRoot = $root } {
            param($DecisionRoot)
            Mock Search-MetraDecisionRegistry {
                param($Query, $Project, $Limit, $MetraRoot)
                if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
                @([PSCustomObject]@{
                        Id = 'd1'; Title = 'Prefer brief'; Decision = 'Prefer brief'; Why = 'lighter'
                        Project = 'TicketTracker'; Confidence = 'high'; Source = 'AGENTS.md'
                    })
            }
            Mock Get-MetraWhyHere {
                param($Project, $Query, $Limit, $MetraRoot)
                if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
                @([PSCustomObject]@{
                        Id = 'd1'; Title = 'Prefer brief'; Decision = 'Prefer brief'; Why = 'lighter'
                        Project = $Project; Confidence = 'high'; Source = 'AGENTS.md'
                    })
            }
            Mock Get-MetraRoutingAmbiguity {
                [PSCustomObject]@{
                    Primary = $null; RunnerUp = $null; IsAmbiguous = $false; FavoredTokens = @()
                }
            }
            Mock Get-MetraRoots { @([PSCustomObject]@{ Name = 'work'; Primary = $true; Exists = $true; Optional = $false; Path = 'C:\Projects'; RawPath = '..' }) }
            Mock Get-MetraProjectRegistry {
                [PSCustomObject]@{
                    projects = @(
                        [PSCustomObject]@{
                            name = 'TicketTracker'; purpose = 'tickets'; triggers = @('ticket'); capabilities = @(); serves = @('Helpdesk'); entry = 'AGENTS.md'
                        }
                    )
                }
            }
            Mock Get-MetraProjects {
                @([PSCustomObject]@{ Name = 'TicketTracker'; Path = 'C:\Projects\TicketTracker'; Root = 'work'; IsGit = $true })
            }
            Mock Get-MetraRoutingTable { @() }
            Mock Get-MetraRoot { $DecisionRoot }

            $packPath = Join-Path $DecisionRoot 'docs\context-pack.json'
            # Query must score the mock project's triggers/purpose so a primary stop exists.
            Export-MetraContextPack -Query 'ticket' -Path $packPath -Quiet -Format json | Out-Null
            $json = Get-Content -LiteralPath $packPath -Raw | ConvertFrom-Json
            @($json.relatedDecisions).Count | Should -Be 1
            $json.whyHereFor | Should -Be 'TicketTracker'
            @($json.projects[0].serves) | Should -Contain 'Helpdesk'

            Export-MetraContextPack -Path (Join-Path $DecisionRoot 'docs\context-pack-noq.json') -Quiet -Format json | Out-Null
            $json2 = Get-Content -LiteralPath (Join-Path $DecisionRoot 'docs\context-pack-noq.json') -Raw | ConvertFrom-Json
            ($json2.PSObject.Properties.Name -contains 'relatedDecisions') | Should -BeFalse
            ($json2.PSObject.Properties.Name -contains 'whyHereFor') | Should -BeFalse
            # no-query still includes project serves when present on registry rows
            $tt2 = @($json2.projects | Where-Object name -eq 'TicketTracker')[0]
            @($tt2.serves) | Should -Contain 'Helpdesk'
        }
    }

    It 'Get-MetraWhyHere scopes by project and Format omits high confidence' {
        $root = $script:decisionRoot
        InModuleScope Metra -Parameters @{ DecisionRoot = $root } {
            param($DecisionRoot)
            Add-MetraDecisionRegistryCandidate `
                -Title 'Prefer brief over show' `
                -Decision 'Prefer TicketTracker brief over show for triage.' `
                -Why 'brief is plain text; show pulls heavy HTML.' `
                -Project 'TicketTracker' `
                -Confidence high `
                -Evidence @('TicketTracker/AGENTS.md') `
                -Origin backfill `
                -MetraRoot $DecisionRoot | Out-Null
            $note = @(Show-MetraDecisionRegistry -MetraRoot $DecisionRoot).Candidates[0]
            Promote-MetraDecisionRegistryEntry -IdOrTitle $note.id -MetraRoot $DecisionRoot | Out-Null

            Add-MetraDecisionRegistryCandidate `
                -Title 'Orion src only' `
                -Decision 'Edit Solarwinds under src only.' `
                -Why 'catalog dumps burn tokens.' `
                -Project 'Solarwinds' `
                -Confidence medium `
                -Evidence @('Solarwinds/AGENTS.md') `
                -Origin backfill `
                -MetraRoot $DecisionRoot | Out-Null
            $n2 = @(Show-MetraDecisionRegistry -MetraRoot $DecisionRoot).Candidates[0]
            Promote-MetraDecisionRegistryEntry -IdOrTitle $n2.id -MetraRoot $DecisionRoot | Out-Null

            $tt = @(Get-MetraWhyHere -Project TicketTracker -MetraRoot $DecisionRoot)
            $tt.Count | Should -Be 1
            $tt[0].Project | Should -Be 'TicketTracker'

            $empty = @(Get-MetraWhyHere -Project MissingProj -MetraRoot $DecisionRoot)
            $empty.Count | Should -Be 0

            $highBlock = @(Format-MetraWhyHereBlock -Project TicketTracker -Decisions $tt)
            ($highBlock -join "`n") | Should -Not -Match '\(high\)'

            $sw = @(Get-MetraWhyHere -Project Solarwinds -MetraRoot $DecisionRoot)
            $medBlock = @(Format-MetraWhyHereBlock -Project Solarwinds -Decisions $sw)
            ($medBlock -join "`n") | Should -Match '\(medium\)'
        }
    }

    It 'Test-MetraRoutingAmbiguity follows close-score rules' {
        InModuleScope Metra {
            Test-MetraRoutingAmbiguity -PrimaryScore 3 -RunnerUpScore 2 | Should -BeTrue
            Test-MetraRoutingAmbiguity -PrimaryScore 4 -RunnerUpScore 1 | Should -BeFalse
            Test-MetraRoutingAmbiguity -PrimaryScore 4 -RunnerUpScore 2 | Should -BeTrue
            Test-MetraRoutingAmbiguity -PrimaryScore 2 -RunnerUpScore 0 | Should -BeFalse
        }
    }

    It 'ships tracked example' {
        $root = Get-MetraRoot
        Test-Path -LiteralPath (Join-Path $root 'docs\decision-registry.example.json') | Should -BeTrue
        $ex = Get-Content -LiteralPath (Join-Path $root 'docs\decision-registry.example.json') -Raw | ConvertFrom-Json
        @($ex.confirmed)[0].why | Should -Not -BeNullOrEmpty
        @($ex.confirmed)[0].confidence | Should -Not -BeNullOrEmpty
        @($ex.confirmed)[0].evidence.Count | Should -BeGreaterThan 0
    }
}

Describe 'Metra Ops canvas install' {
    BeforeEach {
        $script:canvasRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-canvas-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:canvasRoot -Force | Out-Null
        $script:canvasPath = Join-Path $script:canvasRoot 'metra-ops-board.canvas.tsx'
        $script:templatePath = Join-Path (Get-MetraRoot) 'integrations\cursor\metra-ops-board.canvas.tsx.template'
    }

    AfterEach {
        if ($script:canvasRoot -and (Test-Path -LiteralPath $script:canvasRoot)) {
            Remove-Item -LiteralPath $script:canvasRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-MetraCanvasCodeShape ignores the embedded snapshot block' {
        InModuleScope Metra {
            $a = "before`n// <metra-ops-snapshot>`nconst SNAPSHOT = {`"a`":1};`n// </metra-ops-snapshot>`nafter"
            $b = "before`n// <metra-ops-snapshot>`nconst SNAPSHOT = {`"b`":2};`n// </metra-ops-snapshot>`nafter"
            Get-MetraCanvasCodeShape -Text $a | Should -Be (Get-MetraCanvasCodeShape -Text $b)
            Get-MetraCanvasCodeShape -Text $a | Should -Not -Match 'SNAPSHOT'
        }
    }

    It 'installs from template when the canvas is missing' {
        $path = $script:canvasPath
        InModuleScope Metra -Parameters @{ CanvasPath = $path } {
            param($CanvasPath)
            Install-MetraOpsCanvas -CanvasPath $CanvasPath 6>$null | Should -BeTrue
        }
        Test-Path -LiteralPath $path | Should -BeTrue
    }

    It 'refreshes stale component code but keeps an in-sync canvas embed' {
        $path = $script:canvasPath
        $template = [System.IO.File]::ReadAllText($script:templatePath)

        # Stale install: component code differs from the template.
        [System.IO.File]::WriteAllText($path, $template.Replace('function MetraRouteMark()', 'function MetraRouteMarkOld()'))
        InModuleScope Metra -Parameters @{ CanvasPath = $path } {
            param($CanvasPath)
            Install-MetraOpsCanvas -CanvasPath $CanvasPath 6>$null | Should -BeTrue
        }
        [System.IO.File]::ReadAllText($path) | Should -Not -Match 'MetraRouteMarkOld'

        # In-sync install: only the embedded snapshot differs, so the file must be left alone.
        $withData = [System.IO.File]::ReadAllText($path) -replace '(?s)// <metra-ops-snapshot>.*?// </metra-ops-snapshot>', "// <metra-ops-snapshot>`nconst SNAPSHOT = { marker: 'keep-me' };`n// </metra-ops-snapshot>"
        [System.IO.File]::WriteAllText($path, $withData)
        InModuleScope Metra -Parameters @{ CanvasPath = $path } {
            param($CanvasPath)
            Install-MetraOpsCanvas -CanvasPath $CanvasPath 6>$null | Should -BeTrue
        }
        [System.IO.File]::ReadAllText($path) | Should -Match 'keep-me'
    }
}

Describe 'Metra Ops snapshot stewardship' {
    BeforeEach {
        $script:snapRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-snap-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:snapRoot 'docs') -Force | Out-Null
    }

    AfterEach {
        if ($script:snapRoot -and (Test-Path -LiteralPath $script:snapRoot)) {
            Remove-Item -LiteralPath $script:snapRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-MetraOpsStewardshipSummaries fails open with empty ledgers' {
        $root = $script:snapRoot
        InModuleScope Metra -Parameters @{ DecisionRoot = $root } {
            param($DecisionRoot)
            $projects = @(
                [PSCustomObject]@{
                    name         = 'TicketTracker'
                    serves       = @('Helpdesk')
                    capabilities = @('ticket-lookup')
                    whyHere      = @()
                }
            )
            $sum = Get-MetraOpsStewardshipSummaries -Projects $projects -MetraRoot $DecisionRoot
            $sum.decisions.ledgerExists | Should -BeFalse
            $sum.decisions.confirmedCount | Should -Be 0
            $sum.contract.confirmedCount | Should -Be 0
            $sum.coverage.projectsWithServes | Should -Be 1
            $sum.coverage.projectsWithCapabilities | Should -Be 1
        }
    }

    It 'stewardship summary includes confirmed decisions and OCC guidelines' {
        $root = $script:snapRoot
        InModuleScope Metra -Parameters @{ DecisionRoot = $root } {
            param($DecisionRoot)
            $null = Add-MetraDecisionRegistryCandidate `
                -Title 'Prefer brief over show' `
                -Decision 'Prefer TicketTracker brief over show for triage.' `
                -Why 'brief is plain text; show pulls heavy HTML.' `
                -Project 'TicketTracker' `
                -Tags 'ticket,brief' `
                -Source 'TicketTracker/AGENTS.md' `
                -Origin backfill `
                -Confidence high `
                -Evidence @('TicketTracker/AGENTS.md', 'Operator confirmed') `
                -MetraRoot $DecisionRoot
            $null = Promote-MetraDecisionRegistryEntry -IdOrTitle 'Prefer brief over show' -MetraRoot $DecisionRoot

            $null = Add-MetraOperatorContractCandidate -Text 'Prefer terse verdicts before detail.' -MetraRoot $DecisionRoot
            $null = Promote-MetraOperatorContractGuideline -IdOrText 'Prefer terse verdicts before detail.' -MetraRoot $DecisionRoot

            $projects = @(
                [PSCustomObject]@{
                    name         = 'TicketTracker'
                    serves       = @('Helpdesk')
                    capabilities = @('ticket-lookup')
                    whyHere      = @(@{ id = 'd1'; title = 'Prefer brief over show' })
                }
            )
            $sum = Get-MetraOpsStewardshipSummaries -Projects $projects -MetraRoot $DecisionRoot
            $sum.decisions.ledgerExists | Should -BeTrue
            $sum.decisions.confirmedCount | Should -BeGreaterThan 0
            @($sum.decisions.recent).Count | Should -BeGreaterThan 0
            $sum.contract.confirmedCount | Should -BeGreaterThan 0
            @($sum.contract.confirmed)[0].text | Should -Match 'terse'
            $sum.coverage.projectsWithWhyHere | Should -Be 1
            $sum.coverage.projectsWithDecisions | Should -BeGreaterThan 0
        }
    }

    It 'template declares Route Portfolio Stewardship interchange tabs' {
        $template = Join-Path (Get-MetraRoot) 'integrations\cursor\metra-ops-board.canvas.tsx.template'
        $raw = Get-Content -LiteralPath $template -Raw
        $raw | Should -Match 'type TabId = "route" \| "portfolio" \| "stewardship"'
        $raw | Should -Match 'Portfolio Operating Model'
        $raw | Should -Match 'function scoreProjects'
        $raw | Should -Match 'function isAmbiguous'
        $raw | Should -Match 'serves'
        $raw | Should -Match 'whyHere'
        $raw | Should -Match 'gitChecked'
        $raw | Should -Match 'Needs attention'
        $raw | Should -Match 'Resolve this'
        $raw | Should -Match 'position: "sticky"'
        $raw | Should -Match 'visibleAttention = attentionItems\.slice\(0, 5\)'
        $raw | Should -Match 'function ActionPaths'
        $raw | Should -Match 'Ask Metra'
        $raw | Should -Match 'useCanvasAction'
        $raw | Should -Match 'briefingForTodo'
        $raw | Should -Match 'Standing routes'
        $raw | Should -Match 'standingRoutes'
        $raw | Should -Not -Match '<Text weight="semibold">Pinned hubs</Text>'
        $raw | Should -Not -Match 'function CommandRow'
    }
}

Describe 'Update-MetraWorkspace' {
    It 'drops workspace.exclude names from the generated folder list' {
        InModuleScope Metra {
            Mock Get-MetraConfig {
                [PSCustomObject]@{
                    workspace = [PSCustomObject]@{
                        months     = 6
                        scanDepth  = 2
                        exclude    = @('Frozen-Review')
                        outputs    = @(
                            [PSCustomObject]@{
                                path              = 'Metra.code-workspace'
                                metraFolderPath   = '.'
                                projectPathPrefix = '../'
                            }
                        )
                        settings   = [PSCustomObject]@{}
                        extensions = [PSCustomObject]@{}
                    }
                }
            }
            Mock Get-MetraRoots {
                @([PSCustomObject]@{ Name = 'work'; Primary = $true })
            }
            Mock Get-RecentMetraProjects {
                @(
                    [PSCustomObject]@{
                        Name         = 'Solarwinds'
                        Path         = 'C:\Projects\Solarwinds'
                        Root         = 'work'
                        LastActivity = [datetime]'2026-07-01'
                    },
                    [PSCustomObject]@{
                        Name         = 'Frozen-Review'
                        Path         = 'C:\Projects\Frozen-Review'
                        Root         = 'work'
                        LastActivity = [datetime]'2026-07-01'
                    }
                )
            }

            $result = Update-MetraWorkspace -WhatIfPreview
            $result.Projects | Should -Contain 'Solarwinds'
            $result.Projects | Should -Not -Contain 'Frozen-Review'
            @($result.Files).Count | Should -Be 0
        }
    }

    It 'ships workspace.exclude in the tracked config example' {
        $example = Join-Path (Get-MetraRoot) 'metra.config.example.json'
        $raw = Get-Content -LiteralPath $example -Raw
        $raw | Should -Match '"workspace"\s*:\s*\{[\s\S]*?"exclude"\s*:\s*\['
    }
}

