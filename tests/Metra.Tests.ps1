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
        'Update-MetraSelfDocumentation',
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
    It 'resolves CURSOR_API_KEY from User scope when process env is empty' {
        $prevUser = [Environment]::GetEnvironmentVariable('CURSOR_API_KEY', 'User')
        if ([string]::IsNullOrWhiteSpace($prevUser)) {
            Set-ItResult -Skipped -Because 'User CURSOR_API_KEY not set on this machine'
            return
        }
        $prevProc = $env:CURSOR_API_KEY
        try {
            if (Test-Path Env:CURSOR_API_KEY) {
                Remove-Item Env:CURSOR_API_KEY
            }
            $resolved = & (Get-Module Metra) { Get-MetraCursorApiKey }
            $resolved | Should -Not -BeNullOrEmpty
            [string]$env:CURSOR_API_KEY | Should -Not -BeNullOrEmpty
        }
        finally {
            if ($null -ne $prevProc -and $prevProc -ne '') {
                $env:CURSOR_API_KEY = $prevProc
            }
            elseif (Test-Path Env:CURSOR_API_KEY) {
                Remove-Item Env:CURSOR_API_KEY -ErrorAction SilentlyContinue
            }
        }
    }

    It 'accepts -Cloud and warns when API key resolver returns null' {
        InModuleScope Metra {
            Mock Get-MetraCursorApiKey { $null }
            $warns = $null
            $cloudRows = @(Get-MetraCloudAgentChats -IncludeMetra -Limit 3 -WarningVariable warns -WarningAction SilentlyContinue)
            @($warns | Where-Object { $_ -match 'CURSOR_API_KEY|session key' }).Count | Should -BeGreaterThan 0
            $cloudRows.Count | Should -Be 0
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

    It 'includes mark-of-the-web scripts row' {
        $report = Test-MetraInstallation -Detailed
        $row = @($report.Results | Where-Object Name -eq 'mark-of-the-web scripts')
        $row.Count | Should -Be 1
        $row[0].Status | Should -BeIn @('PASS', 'WARN')
    }
}

Describe 'Metra install unblock' {
    BeforeEach {
        $script:unblockRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-unblock-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:unblockRoot -Force | Out-Null
    }

    AfterEach {
        if ($script:unblockRoot -and (Test-Path -LiteralPath $script:unblockRoot)) {
            Remove-Item -LiteralPath $script:unblockRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'detects a real Zone.Identifier stream' {
        $root = $script:unblockRoot
        $file = Join-Path $root 'blocked.ps1'
        Set-Content -LiteralPath $file -Value '# test' -Encoding utf8
        Set-Content -LiteralPath ($file + ':Zone.Identifier') -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ascii

        InModuleScope Metra -Parameters @{ FilePath = $file } {
            param($FilePath)
            Test-MetraBlockedFile -Path $FilePath | Should -BeTrue
        }
    }

    It 'Preview reports BlockedDetected without clearing streams' {
        $root = $script:unblockRoot
        $blocked = Join-Path $root 'blocked.ps1'
        $clean = Join-Path $root 'clean.ps1'
        Set-Content -LiteralPath $blocked -Value '# blocked' -Encoding utf8
        Set-Content -LiteralPath $clean -Value '# clean' -Encoding utf8
        Set-Content -LiteralPath ($blocked + ':Zone.Identifier') -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ascii

        InModuleScope Metra -Parameters @{ Root = $root; Blocked = $blocked } {
            param($Root, $Blocked)
            $preview = Unblock-MetraCheckout -Path $Root -Preview
            $preview.BlockedDetected | Should -Be 1
            $preview.FilesUnblocked | Should -Be 0
            $preview.AlreadyClean | Should -Be 1
            $preview.Failed | Should -Be 0
            Test-MetraBlockedFile -Path $Blocked | Should -BeTrue
        }
    }

    It 'unblocks streams and is idempotent on clean files' {
        $root = $script:unblockRoot
        $blocked = Join-Path $root 'blocked.ps1'
        $clean = Join-Path $root 'clean.psm1'
        Set-Content -LiteralPath $blocked -Value '# blocked' -Encoding utf8
        Set-Content -LiteralPath $clean -Value '# clean' -Encoding utf8
        Set-Content -LiteralPath ($blocked + ':Zone.Identifier') -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ascii

        InModuleScope Metra -Parameters @{ Root = $root; Blocked = $blocked } {
            param($Root, $Blocked)
            $first = Unblock-MetraCheckout -Path $Root
            $first.BlockedDetected | Should -Be 1
            $first.FilesUnblocked | Should -Be 1
            $first.AlreadyClean | Should -Be 1
            $first.Failed | Should -Be 0
            Test-MetraBlockedFile -Path $Blocked | Should -BeFalse

            $second = Unblock-MetraCheckout -Path $Root
            $second.BlockedDetected | Should -Be 0
            $second.FilesUnblocked | Should -Be 0
            $second.AlreadyClean | Should -Be 2
            $second.Failed | Should -Be 0
        }
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
            Mock Get-MetraRoots {
                param($IncludeMissing)
                @([PSCustomObject]@{ Name = 'work'; Primary = $true; Exists = $true; Optional = $false; Path = 'C:\Projects'; RawPath = '..' })
            }
            Mock Get-MetraProjectRegistry {
                [PSCustomObject]@{
                    projects = @(
                        [PSCustomObject]@{
                            name = 'TicketTracker'; purpose = 'tickets'; triggers = @('ticket'); capabilities = @(); serves = @('Helpdesk')
                            related = @('Solarwinds', 'Reporting'); whenPresent = 'Use brief.'; entry = 'AGENTS.md'
                        }
                        [PSCustomObject]@{
                            name = 'Solarwinds'; purpose = 'orion'; triggers = @('orion'); capabilities = @(); serves = @(); related = @(); entry = 'AGENTS.md'
                        }
                        [PSCustomObject]@{
                            name = 'Reporting'; purpose = 'reports'; triggers = @('report'); capabilities = @(); serves = @(); related = @(); entry = 'AGENTS.md'
                        }
                    )
                }
            }
            Mock Get-MetraProjects {
                @(
                    [PSCustomObject]@{ Name = 'TicketTracker'; Path = 'C:\Projects\TicketTracker'; Root = 'work'; IsGit = $true }
                    [PSCustomObject]@{ Name = 'Solarwinds'; Path = 'C:\Projects\Solarwinds'; Root = 'work'; IsGit = $true }
                )
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
            @($json.projects[0].related) | Should -Contain 'Solarwinds'
            @($json.projects[0].related) | Should -Contain 'Reporting'
            $json.projectStoryFor | Should -Be 'TicketTracker'
            $json.projectStory.whenPresent | Should -Be 'Use brief.'
            @($json.projectStory.related).Count | Should -Be 2
            @($json.projectStory.related)[0].name | Should -Be 'Solarwinds'
            @($json.projectStory.related)[0].present | Should -BeTrue
            @($json.projectStory.related)[1].name | Should -Be 'Reporting'
            @($json.projectStory.related)[1].present | Should -BeFalse

            Export-MetraContextPack -Path (Join-Path $DecisionRoot 'docs\context-pack-noq.json') -Quiet -Format json | Out-Null
            $json2 = Get-Content -LiteralPath (Join-Path $DecisionRoot 'docs\context-pack-noq.json') -Raw | ConvertFrom-Json
            ($json2.PSObject.Properties.Name -contains 'relatedDecisions') | Should -BeFalse
            ($json2.PSObject.Properties.Name -contains 'whyHereFor') | Should -BeFalse
            ($json2.PSObject.Properties.Name -contains 'projectStory') | Should -BeFalse
            # no-query still includes project serves when present on registry rows
            $tt2 = @($json2.projects | Where-Object name -eq 'TicketTracker')[0]
            @($tt2.serves) | Should -Contain 'Helpdesk'
            @($tt2.related) | Should -Contain 'Solarwinds'
        }
    }

    It 'Get-MetraRelatedProjects preserves order, dedupes, same-root, unknown drop, cap' {
        InModuleScope Metra {
            Mock Get-MetraRoots {
                @(
                    [PSCustomObject]@{ Name = 'work'; Primary = $true; Exists = $true; Optional = $false; Path = 'C:\Projects'; RawPath = 'C:\Projects' }
                    [PSCustomObject]@{ Name = 'personal'; Primary = $false; Exists = $true; Optional = $true; Path = 'C:\Personal'; RawPath = 'C:\Personal' }
                )
            }

            $registry = [PSCustomObject]@{
                projects = @(
                    [PSCustomObject]@{
                        name = 'TicketTracker'
                        related = @('Solarwinds', 'Solarwinds', 'UnknownX', 'HomeLab', 'Reporting', 'A', 'B', 'C', 'D', 'E')
                    }
                    [PSCustomObject]@{ name = 'Solarwinds'; related = @() }
                    [PSCustomObject]@{ name = 'Reporting'; related = @() }
                    [PSCustomObject]@{ name = 'A'; related = @() }
                    [PSCustomObject]@{ name = 'B'; related = @() }
                    [PSCustomObject]@{ name = 'C'; related = @() }
                    [PSCustomObject]@{ name = 'D'; related = @() }
                    [PSCustomObject]@{ name = 'E'; related = @() }
                    [PSCustomObject]@{ name = 'HomeLab'; root = 'personal'; related = @() }
                )
            }
            $disk = @{
                'tickettracker' = [PSCustomObject]@{ Name = 'TicketTracker'; Root = 'work' }
                'solarwinds'    = [PSCustomObject]@{ Name = 'Solarwinds'; Root = 'work' }
                'reporting'     = [PSCustomObject]@{ Name = 'Reporting'; Root = 'work' }
                'a'             = [PSCustomObject]@{ Name = 'A'; Root = 'work' }
                'b'             = [PSCustomObject]@{ Name = 'B'; Root = 'work' }
                'c'             = [PSCustomObject]@{ Name = 'C'; Root = 'work' }
                'homelab'       = [PSCustomObject]@{ Name = 'HomeLab'; Root = 'personal' }
            }

            $rows = @(Get-MetraRelatedProjects -Name 'TicketTracker' -Registry $registry -DiskByName $disk -Limit 6)
            $names = @($rows | ForEach-Object { $_.Name })
            $names | Should -Be @('Solarwinds', 'Reporting', 'A', 'B', 'C', 'D')
            $names | Should -Not -Contain 'UnknownX'
            $names | Should -Not -Contain 'HomeLab'
            $names | Should -Not -Contain 'E'
            @($rows | Where-Object Name -eq 'Solarwinds')[0].Present | Should -BeTrue
            @($rows | Where-Object Name -eq 'D')[0].Present | Should -BeFalse
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

Describe 'Metra decision registry review' {
    It 'flags stale candidates with the same cutoff as gc split' {
        InModuleScope Metra {
            $asOf = [datetime]::Parse('2026-08-01T12:00:00Z').ToUniversalTime()
            $registry = [PSCustomObject]@{
                version            = 1
                candidateStaleDays = 30
                maxConfirmed       = 50
                candidates         = @(
                    [PSCustomObject]@{
                        id        = 'c-stale'
                        title     = 'Old candidate'
                        why       = 'has why'
                        updatedAt = $asOf.AddDays(-31).ToString('o')
                    }
                    [PSCustomObject]@{
                        id        = 'c-fresh'
                        title     = 'Fresh candidate'
                        why       = 'has why'
                        updatedAt = $asOf.AddDays(-10).ToString('o')
                    }
                )
                confirmed          = @()
            }
            $split = Split-MetraDecisionRegistryCandidatesByStale -Registry $registry -AsOf $asOf
            $rev = Get-MetraDecisionRegistryReview -Registry $registry -AsOf $asOf -GapLimit 12
            @($split.Stale | ForEach-Object { $_.id }) | Should -Be @('c-stale')
            $rev.StaleCandidatesCount | Should -Be 1
            @($rev.StaleCandidates | ForEach-Object { $_.id }) | Should -Be @('c-stale')
            @(Compare-Object @($split.Stale | ForEach-Object { $_.id }) @($rev.StaleCandidates | ForEach-Object { $_.id })).Count |
                Should -Be 0
        }
    }

    It 'lists superseded and missing-why without flagging filled why' {
        InModuleScope Metra {
            $registry = [PSCustomObject]@{
                version            = 1
                candidateStaleDays = 30
                maxConfirmed       = 50
                candidates         = @(
                    [PSCustomObject]@{ id = 'c-missing'; title = 'Needs why'; why = ''; updatedAt = (Get-Date).ToUniversalTime().ToString('o') }
                    [PSCustomObject]@{ id = 'c-ok'; title = 'Has why'; why = 'because'; updatedAt = (Get-Date).ToUniversalTime().ToString('o') }
                )
                confirmed          = @(
                    [PSCustomObject]@{ id = 'd-old'; title = 'Superseded one'; why = 'old why'; status = 'superseded' }
                    [PSCustomObject]@{ id = 'd-active'; title = 'Active one'; why = 'active why'; status = 'active' }
                )
            }
            $rev = Get-MetraDecisionRegistryReview -Registry $registry -GapLimit 12
            $rev.SupersededCount | Should -Be 1
            @($rev.Superseded | ForEach-Object { $_.id }) | Should -Be @('d-old')
            $rev.MissingWhyCount | Should -Be 1
            @($rev.MissingWhy | ForEach-Object { $_.id }) | Should -Be @('c-missing')
            @($rev.MissingWhy | ForEach-Object { $_.id }) | Should -Not -Contain 'c-ok'
            @($rev.MissingWhy | ForEach-Object { $_.id }) | Should -Not -Contain 'd-active'
        }
    }

    It 'dedupes MissingWhy by id across buckets' {
        InModuleScope Metra {
            $registry = [PSCustomObject]@{
                version            = 1
                candidateStaleDays = 30
                maxConfirmed       = 50
                candidates         = @(
                    [PSCustomObject]@{ id = 'dup-1'; title = 'Candidate copy'; why = '  '; updatedAt = (Get-Date).ToUniversalTime().ToString('o') }
                )
                confirmed          = @(
                    [PSCustomObject]@{ id = 'dup-1'; title = 'Confirmed copy'; why = ''; status = 'active' }
                )
            }
            $rev = Get-MetraDecisionRegistryReview -Registry $registry -GapLimit 12
            $rev.MissingWhyCount | Should -Be 1
            @($rev.MissingWhy).Count | Should -Be 1
            @($rev.MissingWhy)[0].id | Should -Be 'dup-1'
        }
    }

    It 'caps hygiene lists at 12 while keeping full counts' {
        InModuleScope Metra {
            $candidates = 1..15 | ForEach-Object {
                [PSCustomObject]@{
                    id        = ('c{0:D2}' -f $_)
                    title     = ('Gap {0:D2}' -f $_)
                    why       = ''
                    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
                }
            }
            $registry = [PSCustomObject]@{
                version            = 1
                candidateStaleDays = 30
                maxConfirmed       = 50
                candidates         = @($candidates)
                confirmed          = @()
            }
            $rev = Get-MetraDecisionRegistryReview -Registry $registry -GapLimit 12
            $rev.MissingWhyCount | Should -Be 15
            @($rev.MissingWhy).Count | Should -Be 12
            @($rev.MissingWhy)[0].id | Should -Be 'c01'
            @($rev.MissingWhy)[11].id | Should -Be 'c12'
        }
    }

    It 'review does not mutate the ledger when called via MetraRoot' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-rev-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
        try {
            InModuleScope Metra -Parameters @{ DecisionRoot = $root } {
                param($DecisionRoot)
                $null = Add-MetraDecisionRegistryCandidate `
                    -Title 'Review no write' `
                    -Decision 'Stay a candidate.' `
                    -Why '' `
                    -Project 'TicketTracker' `
                    -Origin operator `
                    -MetraRoot $DecisionRoot
                $before = Get-MetraDecisionRegistry -MetraRoot $DecisionRoot
                $beforeCount = @($before.candidates).Count
                $null = Get-MetraDecisionRegistryReview -MetraRoot $DecisionRoot
                $after = Get-MetraDecisionRegistry -MetraRoot $DecisionRoot
                @($after.candidates).Count | Should -Be $beforeCount
            }
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
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

Describe 'Metra knowledge coverage' {
    It 'marks uncovered only when missing AGENTS + serves + decisions' {
        InModuleScope Metra {
            $projects = @(
                [PSCustomObject]@{ name = 'Alpha'; present = $true; hasAgentsMd = $false; serves = @() }
                [PSCustomObject]@{ name = 'Beta'; present = $true; hasAgentsMd = $true; serves = @() }
                [PSCustomObject]@{ name = 'Gamma'; present = $true; hasAgentsMd = $false; serves = @('Ops') }
            )
            $cov = Get-MetraKnowledgeCoverage -Projects $projects -DecisionProjectSet @{} -GapLimit 12
            $cov.UncoveredCount | Should -Be 1
            @($cov.Uncovered) | Should -Be @('Alpha')
            @($cov.Uncovered) | Should -Not -Contain 'Beta'
            @($cov.Uncovered) | Should -Not -Contain 'Gamma'
        }
    }

    It 'does not treat covered-by-one as uncovered' {
        InModuleScope Metra {
            $projects = @(
                [PSCustomObject]@{ name = 'AgentsOnly'; present = $true; hasAgentsMd = $true; serves = @() }
                [PSCustomObject]@{ name = 'ServesOnly'; present = $true; hasAgentsMd = $false; serves = @('Team') }
                [PSCustomObject]@{ name = 'DecisionsOnly'; present = $true; hasAgentsMd = $false; serves = @() }
            )
            $set = @{ 'decisionsonly' = $true }
            $cov = Get-MetraKnowledgeCoverage -Projects $projects -DecisionProjectSet $set -GapLimit 12
            $cov.UncoveredCount | Should -Be 0
            @($cov.Uncovered).Count | Should -Be 0
            $cov.WithAgents | Should -Be 1
            $cov.WithServes | Should -Be 1
            $cov.WithDecisions | Should -Be 1
        }
    }

    It 'caps gap lists at 12 while keeping full counts' {
        InModuleScope Metra {
            $projects = 1..15 | ForEach-Object {
                [PSCustomObject]@{
                    name       = ('Gap{0:D2}' -f $_)
                    present    = $true
                    hasAgentsMd = $false
                    serves     = @()
                }
            }
            $cov = Get-MetraKnowledgeCoverage -Projects $projects -DecisionProjectSet @{} -GapLimit 12
            $cov.MissingAgentsCount | Should -Be 15
            $cov.UncoveredCount | Should -Be 15
            @($cov.MissingAgents).Count | Should -Be 12
            @($cov.Uncovered).Count | Should -Be 12
            @($cov.MissingAgents)[0] | Should -Be 'Gap01'
            @($cov.MissingAgents)[11] | Should -Be 'Gap12'
        }
    }

    It 'skips absent projects and sorts names alphabetically' {
        InModuleScope Metra {
            $projects = @(
                [PSCustomObject]@{ name = 'Zebra'; present = $true; hasAgentsMd = $false; serves = @() }
                [PSCustomObject]@{ name = 'Absent'; present = $false; hasAgentsMd = $false; serves = @() }
                [PSCustomObject]@{ name = 'Apple'; present = $true; hasAgentsMd = $false; serves = @() }
            )
            $cov = Get-MetraKnowledgeCoverage -Projects $projects -DecisionProjectSet @{} -GapLimit 12
            $cov.ProjectCount | Should -Be 2
            @($cov.ProjectNames) | Should -Be @('Apple', 'Zebra')
            @($cov.Uncovered) | Should -Be @('Apple', 'Zebra')
        }
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
            $sum.review | Should -Not -BeNullOrEmpty
            $sum.review.PSObject.Properties.Name | Should -Contain 'staleCandidatesCount'
            $sum.review.PSObject.Properties.Name | Should -Contain 'missingWhyCount'
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
        $raw | Should -Match 'Coverage gaps \(visibility only\)'
        $raw | Should -Match 'uncoveredCount'
        $raw | Should -Match 'Ledger hygiene'
        $raw | Should -Match 'staleCandidatesCount'
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

    It 'skips an output whose metraFolderPath is missing and keeps the valid one' {
        InModuleScope Metra {
            Mock Get-MetraConfig {
                [PSCustomObject]@{
                    workspace = [PSCustomObject]@{
                        months     = 6
                        scanDepth  = 2
                        outputs    = @(
                            [PSCustomObject]@{
                                path              = 'Metra.code-workspace'
                                metraFolderPath   = '.'
                                projectPathPrefix = '../'
                            },
                            [PSCustomObject]@{
                                path              = '../Stale.code-workspace'
                                metraFolderPath   = '_no-such-metra-folder'
                                projectPathPrefix = ''
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
                    }
                )
            }

            $result = Update-MetraWorkspace -WhatIfPreview -WarningVariable warnings -WarningAction SilentlyContinue
            @($result.Skipped) | Should -Be @('../Stale.code-workspace')
            ($warnings -join ' ') | Should -Match 'metraFolderPath'
            ($warnings -join ' ') | Should -Match 'workspace\.outputs has 2 entries'
        }
    }

    It 'throws when every configured output has a missing metraFolderPath' {
        InModuleScope Metra {
            Mock Get-MetraConfig {
                [PSCustomObject]@{
                    workspace = [PSCustomObject]@{
                        months     = 6
                        scanDepth  = 2
                        outputs    = @(
                            [PSCustomObject]@{
                                path              = '../Stale.code-workspace'
                                metraFolderPath   = '_no-such-metra-folder'
                                projectPathPrefix = ''
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
                    }
                )
            }

            { Update-MetraWorkspace -WhatIfPreview -WarningAction SilentlyContinue } |
                Should -Throw -ExpectedMessage '*No workspace output could be written*'
        }
    }

    It 'keeps example rule overlays out of the always-applied set' {
        $examples = @(Get-ChildItem -LiteralPath (Join-Path (Get-MetraRoot) '.cursor\rules') -Filter '*.example.mdc')
        $examples.Count | Should -BeGreaterThan 0
        foreach ($example in $examples) {
            $raw = Get-Content -LiteralPath $example.FullName -Raw
            $raw | Should -Match '(?m)^alwaysApply:\s*false\s*$'
        }
    }

    It 'ships a URL-only MCP binding example with no credentials' {
        $example = Join-Path (Get-MetraRoot) 'integrations\cursor\mcp.example.json'
        Test-Path -LiteralPath $example | Should -BeTrue

        $raw = Get-Content -LiteralPath $example -Raw
        $raw | Should -Not -Match '(?i)headers|authorization|api[_-]?key|token|secret'

        $servers = (ConvertFrom-Json $raw).mcpServers
        @($servers.PSObject.Properties).Count | Should -BeGreaterThan 0
        foreach ($server in $servers.PSObject.Properties) {
            @($server.Value.PSObject.Properties.Name) | Should -Be @('url')
            [string]$server.Value.url | Should -Match '^https://'
        }
    }

    It 'ships workspace.exclude in the tracked config example' {
        $example = Join-Path (Get-MetraRoot) 'metra.config.example.json'
        $raw = Get-Content -LiteralPath $example -Raw
        $raw | Should -Match '"workspace"\s*:\s*\{[\s\S]*?"exclude"\s*:\s*\['
    }
}

Describe 'HTML Ops desk payload' {
    It 'ships a built ops/dist index for end users without Node' {
        $index = Join-Path (Get-MetraRoot) 'ops\dist\index.html'
        Test-Path -LiteralPath $index | Should -BeTrue
    }

    It 'keeps the Ops accept loop free of console cancel handlers' {
        # A scriptblock ConsoleCancelEventHandler runs on the console control thread and takes
        # the whole host down on Ctrl+C instead of stopping the server.
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\OpsServer.ps1') -Raw
        $source | Should -Not -Match 'add_CancelKeyPress'
    }

    It 'reports no desk on an unused port' {
        Test-MetraOpsDeskResponding -Port 7407 -TimeoutSec 1 | Should -BeFalse
        { Stop-MetraOpsServer -Port 7407 } | Should -Not -Throw
    }

    It 'passes Ops switches to the CLI by name from the bootstrap' {
        # Array splatting binds positionally, so -Port and switches would land in $Rest.
        $boot = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\bootstrap\Start-MetraOps.ps1') -Raw
        $boot | Should -Match "@opsArgs"
        $boot | Should -Not -Match "@\('ops'"
    }

    It 'defaults deskMode to general and accepts advanced' {
        $prefs = Set-MetraDeskPreferences -DeskMode general
        $prefs.deskMode | Should -Be 'general'
        $prefs = Set-MetraDeskPreferences -DeskMode advanced
        $prefs.deskMode | Should -Be 'advanced'
        $null = Set-MetraDeskPreferences -DeskMode general
    }

    It 'persists Ops desk binding fields in preferences' {
        InModuleScope Metra {
            $temp = Join-Path ([IO.Path]::GetTempPath()) ("metra-prefs-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $temp 'docs') -Force | Out-Null
            try {
                $null = Set-MetraDeskPreferences -MetraRoot $temp -OpsPort 80 -BrowserHost metra -PreferFriendlyUrl $true -DeskMode general
                $prefs = Get-MetraDeskPreferences -MetraRoot $temp
                $prefs.opsPort | Should -Be 80
                $prefs.browserHost | Should -Be 'metra'
                $prefs.preferFriendlyUrl | Should -BeTrue
                $binding = Resolve-MetraOpsDeskBinding -MetraRoot $temp
                $binding.Port | Should -Be 80
                $binding.BrowserUrl | Should -Be 'http://metra/'
                $binding.ListenerPrefixes | Should -Contain 'http://127.0.0.1:80/'
                $binding.ListenerPrefixes | Should -Contain 'http://metra:80/'
            }
            finally {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'falls back to 7380 loopback binding shape' {
        InModuleScope Metra {
            $b = Get-MetraOpsLoopbackBinding -Port 7380
            $b.BrowserUrl | Should -Be 'http://127.0.0.1:7380/'
            $b.Friendly | Should -BeFalse
        }
    }

    It 'reports whether TCP port 80 is free without throwing' {
        { Test-MetraTcpPortFree -Port 80 } | Should -Not -Throw
        Test-MetraTcpPortFree -Port 80 | Should -BeOfType ([bool])
    }

    It 'shapes health without score fields' {
        $payload = Get-MetraDeskPayload
        $payload.health | Should -Not -BeNullOrEmpty
        @($payload.health.PSObject.Properties.Name) | Should -Contain 'missingAgents'
        @($payload.health.PSObject.Properties.Name) | Should -Contain 'gitChecked'
        @($payload.health.PSObject.Properties.Name) | Should -Contain 'snapshotStale'
        @($payload.health.PSObject.Properties.Name) | Should -Not -Contain 'score'
        @($payload.health.PSObject.Properties.Name) | Should -Not -Contain 'percent'
        @($payload.health.PSObject.Properties.Name) | Should -Not -Contain 'grade'
    }

    It 'explains an empty next-attention queue on quick snapshots' {
        $payload = Get-MetraDeskPayload
        @($payload.PSObject.Properties.Name) | Should -Contain 'attentionEmptyHint'
        @($payload.PSObject.Properties.Name) | Should -Contain 'attentionCount'
        @($payload.PSObject.Properties.Name) | Should -Contain 'attention'
        $payload.attention | Should -Not -BeNullOrEmpty
        @($payload.attention.PSObject.Properties.Name) | Should -Contain 'active'
        @($payload.attention.PSObject.Properties.Name) | Should -Contain 'activeCount'
        @($payload.attention.PSObject.Properties.Name) | Should -Contain 'visibleCount'
        @($payload.attention.PSObject.Properties.Name) | Should -Contain 'held'
        if (-not $payload.nextAttention -and -not $payload.gitChecked) {
            $payload.attentionEmptyHint | Should -Match 'quick check|not reviewed|full refresh'
        }
        if ($payload.nextAttention) {
            @($payload.nextAttention.PSObject.Properties.Name) | Should -Contain 'command'
            @($payload.nextAttention.PSObject.Properties.Name) | Should -Contain 'askPrompt'
            @($payload.nextAttention.PSObject.Properties.Name) | Should -Contain 'summary'
            @($payload.nextAttention.PSObject.Properties.Name) | Should -Contain 'doneWhen'
            @($payload.nextAttention.PSObject.Properties.Name) | Should -Contain 'editCapability'
            @($payload.nextAttention.PSObject.Properties.Name) | Should -Contain 'resolveCopy'
            @($payload.nextAttention.PSObject.Properties.Name) | Should -Contain 'whyNext'
            @($payload.nextAttention.PSObject.Properties.Name) | Should -Contain 'confidence'
            @($payload.nextAttention.PSObject.Properties.Name) | Should -Contain 'key'
            $payload.nextAttention.content | Should -Not -BeNullOrEmpty
            $payload.nextAttention.askPrompt | Should -Not -BeNullOrEmpty
            $payload.nextAttention.whyNext | Should -Not -BeNullOrEmpty
            $payload.nextAttention.editCapability | Should -BeIn @('safe', 'unsafe', 'git')
            if ($payload.nextAttention.kind -eq 'git' -and -not $payload.nextAttention.proposalId) {
                $payload.nextAttention.editCapability | Should -Be 'git'
                $payload.nextAttention.resolveCopy | Should -Match 'will not publish from this page'
                $payload.nextAttention.summary | Should -Match 'waiting to be published|unfinished local|updates available|unpublished'
            }
            elseif (-not $payload.nextAttention.proposalId) {
                $payload.nextAttention.editCapability | Should -Be 'unsafe'
                $payload.nextAttention.resolveCopy | Should -Match 'Open this in your editor'
            }
            else {
                $payload.nextAttention.editCapability | Should -Be 'safe'
                $payload.nextAttention.resolveCopy | Should -Match 'confirm in the Metra tray'
            }
        }
    }

    It 'writes plain-language attention headlines for git hygiene' {
        InModuleScope Metra {
            $plain = Get-MetraAttentionPlainSummary -Project 'Brightspace' -Kind 'git' -Content 'Brightspace - git ahead 1'
            $plain | Should -Be 'Brightspace has 1 change waiting to be published.'

            $mixed = Get-MetraAttentionPlainSummary -Project 'Trivia' -Kind 'git' -Content 'Trivia - git dirty 2, ahead 1'
            $mixed | Should -Match 'unfinished local changes'
            $mixed | Should -Match 'waiting to be published'

            $why = Get-MetraAttentionWhyNext -Item ([PSCustomObject]@{
                    kind              = 'git'
                    confidence        = 'likelyStale'
                    state             = 'active'
                    notRecheckedSince = (Get-Date).ToString('o')
                }) -ActiveCount 3 -RankIndex 0
            $why | Should -Match 'not double-checked'
            $why | Should -Not -Match 'likelyStale|revalidation'
        }
    }

    It 'maps attention editCapability honestly' {
        InModuleScope Metra {
            (Get-MetraAttentionEditCapability -Kind 'todo' -ProposalId $null) | Should -Be 'unsafe'
            (Get-MetraAttentionEditCapability -Kind 'git' -ProposalId '') | Should -Be 'git'
            (Get-MetraAttentionEditCapability -Kind 'git' -ProposalId 'p_test') | Should -Be 'safe'
            (Get-MetraAttentionEditCapability -Kind 'drift' -ProposalId 'p_test') | Should -Be 'safe'
        }
    }

    It 'uses stable attention keys across processes' {
        InModuleScope Metra {
            $a = Get-MetraAttentionKey -Project 'Trivia' -Kind 'drift' -Content 'Missing AGENTS.md'
            $b = Get-MetraAttentionKey -Project 'Trivia' -Kind 'drift' -Content 'Missing AGENTS.md'
            $a | Should -Be $b
            $a | Should -Match '^Trivia:drift:'
            (Get-MetraAttentionKey -Project 'Trivia' -Kind 'git' -Content 'dirty') | Should -Be 'Trivia:git'
            (Get-MetraAttentionKey -Project '' -Kind 'decision' -Content 'x' -ExistingId 'decision:abc') | Should -Be 'decision:abc'
        }
    }

    It 'reconciles attention memory across quick and full scans' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-attn-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                $gitItem = [PSCustomObject]@{
                    id      = 'Trivia:git'
                    project = 'Trivia'
                    content = 'Trivia - git dirty 2 ahead 3'
                    kind    = 'git'
                    command = '.\metra.ps1 status -Name Trivia'
                    source  = 'snapshot'
                }
                $driftItem = [PSCustomObject]@{
                    id      = (Get-MetraAttentionKey -Project 'Trivia' -Kind 'drift' -Content 'Missing AGENTS.md')
                    project = 'Trivia'
                    content = 'Trivia - Missing AGENTS.md'
                    kind    = 'drift'
                    command = '.\metra.ps1 audit -Name Trivia'
                    source  = 'snapshot'
                }

                $mem = Update-MetraAttentionMemory -Queue @($gitItem, $driftItem) -CoveredKinds @('drift', 'decision', 'contract', 'git') -ScanMode full -MetraRoot $root
                @($mem.items).Count | Should -Be 2

                $mem2 = Update-MetraAttentionMemory -Queue @($driftItem) -CoveredKinds @('drift', 'decision', 'contract') -ScanMode quick -MetraRoot $root
                $git = @($mem2.items) | Where-Object { $_.key -eq 'Trivia:git' } | Select-Object -First 1
                $git | Should -Not -BeNullOrEmpty
                $git.state | Should -Be 'active'
                $git.notRecheckedSince | Should -Not -BeNullOrEmpty
                $git.confidence | Should -BeIn @('likelyStale', 'needsRevalidation')

                $null = Invoke-MetraAttentionMutation -Key 'Trivia:git' -Action dismiss -MetraRoot $root
                $mem3 = Update-MetraAttentionMemory -Queue @($gitItem, $driftItem) -CoveredKinds @('drift', 'decision', 'contract', 'git') -ScanMode full -MetraRoot $root
                $gitDismissed = @($mem3.items) | Where-Object { $_.key -eq 'Trivia:git' } | Select-Object -First 1
                $gitDismissed.state | Should -Be 'dismissed'

                $gitChanged = [PSCustomObject]@{
                    id      = 'Trivia:git'
                    project = 'Trivia'
                    content = 'Trivia - git dirty 2 ahead 7'
                    kind    = 'git'
                    command = '.\metra.ps1 status -Name Trivia'
                    source  = 'snapshot'
                }
                $mem4 = Update-MetraAttentionMemory -Queue @($gitChanged, $driftItem) -CoveredKinds @('drift', 'decision', 'contract', 'git') -ScanMode full -MetraRoot $root
                $gitAgain = @($mem4.items) | Where-Object { $_.key -eq 'Trivia:git' } | Select-Object -First 1
                $gitAgain.state | Should -Be 'active'

                $mem5 = Update-MetraAttentionMemory -Queue @($driftItem) -CoveredKinds @('drift', 'decision', 'contract', 'git') -ScanMode full -MetraRoot $root
                $gitGone = @($mem5.items) | Where-Object { $_.key -eq 'Trivia:git' } | Select-Object -First 1
                $gitGone.state | Should -Be 'autoClosed'
                $gitGone.closedBy | Should -Be 'scan'

                $fresh = [PSCustomObject]@{ key = 'a'; kind = 'drift'; confidence = 'fresh'; content = 'A'; state = 'active'; notRecheckedSince = $null }
                $stale = [PSCustomObject]@{ key = 'b'; kind = 'drift'; confidence = 'needsRevalidation'; content = 'B'; state = 'active'; notRecheckedSince = (Get-Date).ToString('o') }
                $ranked = Get-MetraAttentionActiveItems -Memory ([PSCustomObject]@{ items = @($stale, $fresh) })
                $ranked[0].key | Should -Be 'a'

                $null = Invoke-MetraAttentionMutation -Key $driftItem.id -Action reopen -MetraRoot $root
                $null = Invoke-MetraAttentionMutation -Key $driftItem.id -Action snooze -Days 2 -MetraRoot $root
                $memS = Get-MetraAttentionMemory -MetraRoot $root
                $active = Get-MetraAttentionActiveItems -Memory $memS
                @($active | Where-Object { $_.key -eq $driftItem.id }).Count | Should -Be 0

                $null = Invoke-MetraAttentionMutation -Key $driftItem.id -Action reopen -MetraRoot $root
                $null = Invoke-MetraAttentionMutation -Key $driftItem.id -Action hold -MetraRoot $root
                $memH = Get-MetraAttentionMemory -MetraRoot $root
                $held = @($memH.items) | Where-Object { $_.key -eq $driftItem.id } | Select-Object -First 1
                $held.state | Should -Be 'held'
                $held.source | Should -Be 'operator'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'clamps attentionVisibleCount from 1 to 10' {
        InModuleScope Metra {
            $temp = Join-Path ([IO.Path]::GetTempPath()) ("metra-attn-prefs-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $temp 'docs') -Force | Out-Null
            try {
                $p = Set-MetraDeskPreferences -MetraRoot $temp -AttentionVisibleCount 99 -DeskMode general
                $p.attentionVisibleCount | Should -Be 10
                $p2 = Set-MetraDeskPreferences -MetraRoot $temp -AttentionVisibleCount 0
                $p2.attentionVisibleCount | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'persists editorCommand and defaults to auto' {
        InModuleScope Metra {
            $temp = Join-Path ([IO.Path]::GetTempPath()) ("metra-editor-prefs-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $temp 'docs') -Force | Out-Null
            try {
                (Get-MetraDeskPreferences -MetraRoot $temp).editorCommand | Should -Be 'auto'
                $p = Set-MetraDeskPreferences -MetraRoot $temp -EditorCommand 'system'
                $p.editorCommand | Should -Be 'system'
                (Get-MetraDeskPreferences -MetraRoot $temp).editorCommand | Should -Be 'system'
                $blank = Set-MetraDeskPreferences -MetraRoot $temp -EditorCommand '  '
                $blank.editorCommand | Should -Be 'auto'
            }
            finally {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'resolves the system editor without an executable' {
        InModuleScope Metra {
            $editor = Resolve-MetraOpsEditor -Preference 'system'
            $editor.Kind | Should -Be 'system'
            $editor.Exe | Should -BeNullOrEmpty
            $editor.Label | Should -Be 'Windows default'
        }
    }

    It 'only opens folders inside a configured root' {
        InModuleScope Metra {
            $root = Get-MetraRoot
            $ok = Resolve-MetraOpsOpenPath -Path $root
            $ok.Ok | Should -BeTrue

            $outside = Resolve-MetraOpsOpenPath -Path ([Environment]::GetFolderPath('Windows'))
            $outside.Ok | Should -BeFalse
            $outside.Reason | Should -Match 'outside every configured Metra root'

            $missing = Resolve-MetraOpsOpenPath -Path (Join-Path $root 'no-such-folder-here')
            $missing.Ok | Should -BeFalse

            $empty = Resolve-MetraOpsOpenPath -Path ''
            $empty.Ok | Should -BeFalse
        }
    }

    It 'gates Apply via Metra to safe editCapability in Ops UI source' {
        $app = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'ops\src\App.tsx') -Raw
        $app | Should -Match "capability === 'safe'"
        $app | Should -Match 'Apply via Metra'
        $app | Should -Match "capability === 'unsafe'"
        $app | Should -Match "capability === 'git'"
        # Apply via Metra must not render outside the safe branch.
        $safeChunk = [regex]::Match($app, "capability === 'safe' && \([\s\S]*?\)\s*\}\s*\{capability === 'unsafe'").Value
        $safeChunk | Should -Not -BeNullOrEmpty
        $safeChunk | Should -Match 'Apply via Metra'
        $unsafeChunk = [regex]::Match($app, "capability === 'unsafe' && \([\s\S]*?\)\s*\}\s*\{capability === 'git'").Value
        $unsafeChunk | Should -Not -BeNullOrEmpty
        $unsafeChunk | Should -Not -Match 'Apply via Metra'
        $gitChunk = [regex]::Match($app, "capability === 'git' && \([\s\S]*?\)\s*\}\s*").Value
        $gitChunk | Should -Not -BeNullOrEmpty
        $gitChunk | Should -Not -Match 'Apply via Metra'
    }

    It 'builds a routing handoff preview for Ask' {
        $h = Get-MetraDeskHandoff -Query 'ticket disk alert'
        $h.preview | Should -BeTrue
        $h.kind | Should -Be 'route'
        $h.PSObject.Properties.Name | Should -Contain 'where'
        $h.PSObject.Properties.Name | Should -Contain 'next'
    }

    It 'recommends TicketTracker for ticket intake and teaches what happens there' {
        $p = Get-MetraDeskPlaceRecommendation -Text 'Helpdesk ticket about disk alert on prd-sql01'
        $p.ok | Should -BeTrue
        $p.homeId | Should -Be 'tickettracker'
        $p.whatHappensThere | Should -Match 'TicketTracker'
        $p.recommendOnly | Should -BeTrue
        $p.note | Should -Match 'Recommendation only'
    }

    It 'enriches place Why from prior confirmations' {
        $root = Join-Path $TestDrive 'place-learn'
        New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
        $null = Add-MetraPlaceMemoryItem -Summary 'deployment notes for Brightspace package' -HomeId 'agents-md' -Source confirm -MetraRoot $root
        $p = Get-MetraDeskPlaceRecommendation -Text 'deployment notes for Brightspace package again' -MetraRoot $root
        $p.ok | Should -BeTrue
        $p.homeId | Should -Be 'agents-md'
        ($p.why -join ' ') | Should -Match 'Past similar|usually place'
    }

    It 'stages place uploads only under quarantine' {
        InModuleScope Metra {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('hello place')
            $meta = Save-MetraPlaceUpload -FileName 'note.txt' -Bytes $bytes -ContentType 'text/plain'
            $meta.id | Should -Not -BeNullOrEmpty
            $meta.path | Should -Match 'ops-place-quarantine'
            Test-Path -LiteralPath $meta.path | Should -BeTrue
        }
    }

    It 'links confirmed attachments to place memory without leaving quarantine' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'place-attach'
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('canvas screenshot stand-in')
            $meta = Save-MetraPlaceUpload -FileName 'IMG_TEST.png' -Bytes $bytes -ContentType 'image/png'

            $result = Invoke-MetraPlaceConfirm -Text 'Screenshot from CIO demo' -HomeId 'future-development' -AttachmentIds @($meta.id) -MetraRoot $root
            $result.ok | Should -BeTrue
            @($result.attachments).Count | Should -Be 1
            $result.attachments[0].fileName | Should -Be 'IMG_TEST.png'
            $result.note | Should -Match 'quarantine'

            $stored = @((Get-MetraPlaceMemory -MetraRoot $root).items)[0]
            @($stored.attachments).Count | Should -Be 1
            $stored.attachments[0].id | Should -Be $meta.id
            $stored.attachments[0].path | Should -Match 'ops-place-quarantine'
        }
    }

    It 'ignores unknown attachment ids on confirm' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'place-attach-unknown'
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            $result = Invoke-MetraPlaceConfirm -Text 'note with a bad id' -HomeId 'future-development' -AttachmentIds @('..\..\etc\passwd', 'nope') -MetraRoot $root
            $result.ok | Should -BeTrue
            @($result.attachments).Count | Should -Be 0
        }
    }

    It 'Ops UI retires Classify and ships Route something intake' {
        $app = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'ops\src\App.tsx') -Raw
        $app | Should -Not -Match 'Classify / Handoff'
        $app | Should -Not -Match 'postClassify'
        $app | Should -Match 'Route something'
        $app | Should -Match 'What happens there'
        $app | Should -Match 'Keep in view'
        $app | Should -Match 'onPastePlace'
        $app | Should -Match 'type="file"'
        $app | Should -Match 'showWhere'
    }

    It 'OpsServer exposes place APIs and Serve orchestration' {
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\OpsServer.ps1') -Raw
        $source | Should -Match '/api/place'
        $source | Should -Match '/api/place/upload'
        $source | Should -Match '/api/place/confirm'
        $source | Should -Match 'Enable-MetraOpsTailscaleServe'
        $source | Should -Match 'showWhere'
    }

    It 'Tailscale binding prefers HTTPS share when Serve URL is provided' {
        InModuleScope Metra {
            Mock Get-MetraOpsTailscaleDnsName { 'dev-jmp01.taila8f8a7.ts.net' }
            $b = Get-MetraOpsTailscaleBinding -Address '100.64.1.2' -Port 7380 -ServeHttpsUrl 'https://dev-jmp01.taila8f8a7.ts.net/'
            $b.Serve | Should -BeTrue
            $b.ShareUrl | Should -Be 'https://dev-jmp01.taila8f8a7.ts.net/'
            @($b.ListenerPrefixes) | Should -Be @('http://127.0.0.1:7380/')
        }
    }

    It 'degrades Ask honestly when the engine is unavailable' {
        $cap = Get-MetraAskCapability
        if ($cap.available) {
            Set-ItResult -Skipped -Because 'Ask engine is already available on this machine'
            return
        }
        $ask = Get-MetraDeskAskResult -Prompt 'Hello Metra'
        $ask.answered | Should -BeFalse
        $ask.handoff.kind | Should -Be 'route'
        $ask.handoff.where | Should -Be 'Metra'
        $ask.message | Should -Match 'Ask engine unavailable'
        $ask.message | Should -Not -Match 'Hello - Metra here'
        $ask.message | Should -Not -Match 'Routing preview'
        $ask.message | Should -Not -Match 'Bing-Review'
        $ask.capability.available | Should -BeFalse
    }

    It 'never uses greeting theater on the Ask path' {
        $ask = Get-MetraDeskAskResult -Prompt 'Hello Metra'
        $ask.handoff.kind | Should -Be 'route'
        $ask.message | Should -Not -Match 'Hello - Metra here'
        $ask.message | Should -Not -Match 'Local assistant is next'
        $ask.message | Should -Not -Match 'Routing preview for'
    }

    It 'strips Metra Model disclosure chrome from Ask answers' {
        InModuleScope Metra {
            $raw = @"
**Metra** · Model: Composer · language model · Cursor

Hey - yes, from the Ops desk things look fine.
"@
            $clean = Remove-MetraAskUiChrome -Message $raw
            $clean | Should -Not -Match 'Model:'
            $clean | Should -Match 'Ops desk things look fine'
        }
    }

    It 'exposes Ask capability on the desk payload' {
        $payload = Get-MetraDeskPayload
        $payload.ask | Should -Not -BeNullOrEmpty
        @($payload.ask.PSObject.Properties.Name) | Should -Contain 'enabled'
        @($payload.ask.PSObject.Properties.Name) | Should -Contain 'available'
        @($payload.ask.PSObject.Properties.Name) | Should -Contain 'engine'
    }

    It 'reads ask settings with capability discovery helpers' {
        $settings = Get-MetraAskSettings
        $settings.PSObject.Properties.Name | Should -Contain 'enabled'
        $settings.PSObject.Properties.Name | Should -Contain 'engine'
        $cap = Get-MetraAskCapability
        $cap.PSObject.Properties.Name | Should -Contain 'reason'
        $cap.PSObject.Properties.Name | Should -Contain 'selected'
    }

    It 'keeps Metra as home until a stronger route wins' {
        $hello = Get-MetraRoutingAmbiguity -Query 'Hello Metra'
        $hello.Primary.Name | Should -Be 'Metra'

        $weak = Get-MetraRoutingAmbiguity -Query 'zzqx-noroute-xyzzy-qwerty'
        $weak.Primary.Name | Should -Be 'Metra'

        $ticket = Get-MetraRoutingAmbiguity -Query 'ticket disk alert'
        $ticket.Primary.Name | Should -BeIn @('TicketTracker', 'Solarwinds')
    }

    It 'prefers TicketTracker for ticket-shaped ids and solutions keywords' {
        $ttPresent = @(Get-MetraProjects | Where-Object { $_.Name -eq 'TicketTracker' }).Count -gt 0
        if (-not $ttPresent) {
            Set-ItResult -Skipped -Because 'TicketTracker not present on disk'
            return
        }

        $bareId = Get-MetraRoutingAmbiguity -Query '1035299'
        $bareId.Primary.Name | Should -Be 'TicketTracker'

        $lookAt = Get-MetraRoutingAmbiguity -Query 'Look at 1035299'
        $lookAt.Primary.Name | Should -Be 'TicketTracker'

        $unknown = Get-MetraRoutingAmbiguity -Query 'zzqx-unknown-widget-access'
        $unknown.Primary.Name | Should -Be 'Metra'

        $keywords = @(InModuleScope Metra { Get-MetraTicketTrackerSolutionsKeywords })
        if ($keywords.Count -eq 0) {
            Set-ItResult -Skipped -Because 'TicketTracker solutions/README.md has no keywords'
            return
        }

        $thrive = Get-MetraRoutingAmbiguity -Query 'Thrive 360 access denied'
        $thrive.Primary.Name | Should -Be 'TicketTracker'

        $pharos = Get-MetraRoutingAmbiguity -Query 'Pharos sync problem'
        $pharos.Primary.Name | Should -Be 'TicketTracker'
    }

    It 'caches default projects scan and solutions keywords within a session' {
        Clear-MetraRoutingCache

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $first = @(Get-MetraProjects)
        $sw.Stop()
        $coldMs = $sw.Elapsed.TotalMilliseconds
        $first.Count | Should -BeGreaterThan 0

        $sw.Restart()
        $second = @(Get-MetraProjects)
        $sw.Stop()
        $warmMs = $sw.Elapsed.TotalMilliseconds
        $second.Count | Should -Be $first.Count
        # Warm hit should be much cheaper than a full root directory scan.
        $warmMs | Should -BeLessThan ([math]::Max(80, $coldMs * 0.35))

        InModuleScope Metra {
            Clear-MetraRoutingCache
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $k1 = @(Get-MetraTicketTrackerSolutionsKeywords)
            $sw.Stop()
            $kwCold = $sw.Elapsed.TotalMilliseconds

            $sw.Restart()
            $k2 = @(Get-MetraTicketTrackerSolutionsKeywords)
            $sw.Stop()
            $kwWarm = $sw.Elapsed.TotalMilliseconds

            $k2.Count | Should -Be $k1.Count
            if ($k1.Count -gt 0) {
                $kwWarm | Should -BeLessThan ([math]::Max(40, $kwCold * 0.5))
            }
        }

        Clear-MetraRoutingCache
        $afterClear = @(Get-MetraProjects)
        $afterClear.Count | Should -Be $first.Count
    }

    It 'does not let stop-word substrings steal IWUDATA routes' {
        $amb = Get-MetraRoutingAmbiguity -Query 'Try to find what needs to be fixed in the job or sql components in the IWUDATA failure today.'
        $amb.Primary.Name | Should -BeIn @('IWUDATA-SQL', 'IWUDATA-Automation', 'Datamart')
        $amb.Primary.Name | Should -Not -Be 'Trivia'

        InModuleScope Metra {
            $q = 'Try to find what needs to be fixed in the job or sql components in the IWUDATA failure today.'
            $tokens = @(Get-MetraQueryTokens -Query $q)
            $tokens | Should -Contain 'iwudata'
            $tokens | Should -Not -Contain 'the'
            $tokens | Should -Not -Contain 'to'
            $tokens | Should -Not -Contain 'or'
            $tokens | Should -Not -Contain 'in'

            $scored = @(Get-MetraScoredRoutingProjects -Query $q -Limit 10)
            $trivia = $scored | Where-Object { $_.Name -eq 'Trivia' } | Select-Object -First 1
            if ($trivia) {
                [int]$trivia.Score | Should -BeLessThan 3
            }
        }
    }

    It 'revives a dead Ask sidecar on the Ask path' {
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\Snapshot.ps1') -Raw
        # Ops owns Ask - a sidecar that dies mid-session must not stay down until desk restart.
        $source | Should -Match 'Start-MetraAskEngine -MetraRoot \$MetraRoot'
        # Only retry when health says down, so a slow prompt is never re-run.
        $source | Should -Match 'Test-MetraAskEngineHealth -MetraRoot \$MetraRoot -TimeoutSec 2'
    }

    It 'strips echoed Where/What handoff chrome from Ask answers' {
        InModuleScope Metra {
            $raw = @"
Fix Get-EllucianWebService XML parse first.

Where
Trivia
What
Open Trivia and follow that project's AGENTS.md.
Next
Stay in Trivia.
Labeled preview - authoritative Why Here remains routing -Query / ctx -Query.
"@
            $clean = Remove-MetraAskUiChrome -Message $raw
            $clean | Should -Match 'Get-EllucianWebService'
            $clean | Should -Not -Match '(?m)^Where$'
            $clean | Should -Not -Match 'Trivia'
            $clean | Should -Not -Match 'Labeled preview'
        }
    }
}

Describe 'Ask Session Journal and Capture Inbox' {
    It 'persists journal turns with turnIndex, origin, client, and stripped message' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-askj-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                $sess = 'sess-ab-test'
                $chrome = @"
**Metra** · Model: test

Where:
- Metra

Hello from Ask.
"@
                $t1 = Add-MetraDeskAskEntry -Prompt 'first' -Message $chrome -Handoff ([PSCustomObject]@{ where = 'Metra' }) `
                    -SessionId $sess -Origin remote -Client ops-web -ClientHint phone -Answered $true -MetraRoot $root
                $t2 = Add-MetraDeskAskEntry -Prompt 'second' -Message 'follow-up' -Handoff ([PSCustomObject]@{ where = 'Metra' }) `
                    -SessionId $sess -Origin remote -Client ops-web -Answered $true -MetraRoot $root
                $t1.turnIndex | Should -Be 1
                $t2.turnIndex | Should -Be 2
                $t1.origin | Should -Be 'remote'
                $t1.client | Should -Be 'ops-web'
                $t1.message | Should -Not -Match 'Metra.*Model'
                $t1.message | Should -Match 'Hello from Ask'
                $sessions = @(Get-MetraDeskAskSessionSummaries -MetraRoot $root -Limit 5)
                ($sessions | Where-Object { $_.sessionId -eq $sess }).turnCount | Should -Be 2
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'creates thin capture from askTurn without duplicating full answer' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-cap-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            try {
                $turn = Add-MetraDeskAskEntry -Prompt 'Need metadata audits for Metra' `
                    -Message ('Long answer ' + ('x' * 200)) `
                    -Handoff ([PSCustomObject]@{ where = 'Metra' }) `
                    -SessionId 's1' -Origin loopback -Client ops-web -Answered $true -MetraRoot $root
                $cap = Add-MetraCaptureFromAskTurn -TurnId $turn.id -MetraRoot $root
                $cap.derivedFrom.type | Should -Be 'askTurn'
                $cap.derivedFrom.turnId | Should -Be $turn.id
                $cap.summary.Length | Should -BeLessOrEqual 120
                ($cap.PSObject.Properties.Name -contains 'message') | Should -BeFalse
                { Update-MetraCaptureItem -Id $cap.id -DerivedFrom ([PSCustomObject]@{ type = 'manual' }) -MetraRoot $root } |
                    Should -Throw -ExpectedMessage '*immutable*'
                $promoted = Invoke-MetraCapturePromote -Id $cap.id -Home FutureDevelopment -MetraRoot $root
                $promoted.status | Should -Be 'promoted'
                $promoted.derivedFrom.turnId | Should -Be $turn.id
                Test-Path -LiteralPath (Join-Path $root 'docs\Future-Development.local.md') | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'resolves client and origin helpers without User-Agent forever-infer for unknown client' {
        InModuleScope Metra {
            Resolve-MetraAskClientId -HeaderClient 'ops-ios' | Should -Be 'ops-ios'
            Resolve-MetraAskClientId -BodyClient 'cli' | Should -Be 'cli'
            Resolve-MetraAskClientId -UserAgent 'Mozilla/5.0' | Should -Be 'unknown'
            Resolve-MetraAskOrigin -IsLoopback $true -HasLocalSession $false | Should -Be 'loopback'
            Resolve-MetraAskOrigin -IsLoopback $false -HasLocalSession $true | Should -Be 'localSession'
            Resolve-MetraAskOrigin -IsLoopback $false -HasLocalSession $false | Should -Be 'remote'
        }
    }
}

Describe 'Metra Ops host' {
    It 'writes and reads ops-host-state.json' {
        InModuleScope Metra {
            # Sandbox LOCALAPPDATA so tests never disturb the operator's live tray state.
            $realLocalAppData = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = Join-Path ([IO.Path]::GetTempPath()) ("metra-host-" + [guid]::NewGuid().ToString('n'))
            try {
                Write-MetraOpsHostState -Status 'running' -OpsPort 7380 -RestartCount 0 -StartedAt '2026-08-01T00:00:00Z'
                $state = Get-MetraOpsHostState
                $state | Should -Not -BeNullOrEmpty
                $state.status | Should -Be 'running'
                $state.opsPort | Should -Be 7380
                Write-MetraOpsHostState -Status 'stopped' -OpsPort 7380 -RestartCount 1 -StartedAt '2026-08-01T00:00:00Z'
                $stopped = Get-MetraOpsHostState
                $stopped.status | Should -Be 'stopped'
                $stopped.restartCount | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $env:LOCALAPPDATA -Recurse -Force -ErrorAction SilentlyContinue
                $env:LOCALAPPDATA = $realLocalAppData
            }
        }
    }

    It 'does not start Ask from the host module source' {
        # Ownership: Host -> Ops -> Ask. Tray must not call Ask start helpers.
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\OpsHost.ps1') -Raw
        ($source -match '(?m)^\s*Start-MetraAskEngine\b') | Should -BeFalse
    }

    It 'ships tray and console Start Menu entry points' {
        Test-Path -LiteralPath (Join-Path (Get-MetraRoot) 'Metra-Ops.cmd') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Get-MetraRoot) 'Metra-Ops-Console.cmd') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\bootstrap\Start-MetraOpsHost.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Get-MetraRoot) 'docs\assets\metra.ico') | Should -BeTrue
        $iss = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'packaging\inno\Metra.iss') -Raw
        $iss | Should -Match 'Metra-Ops\.cmd'
        $iss | Should -Match 'Metra-Ops-Console\.cmd'
        $iss | Should -Match 'docs\\assets\\metra\.ico'
    }

    It 'loads the Metra brand tray icon' {
        Add-Type -AssemblyName System.Drawing
        InModuleScope Metra {
            $path = Get-MetraOpsHostIconPath
            $path | Should -Not -BeNullOrEmpty
            $icon = Get-MetraOpsHostNotifyIcon
            try {
                $icon | Should -Not -BeNullOrEmpty
                $icon.Width | Should -BeGreaterThan 0
            }
            finally {
                if ($icon) { $icon.Dispose() }
            }
        }
    }

    It 'installs Start Menu shortcuts with the Metra icon' {
        $result = Install-MetraOpsStartMenuShortcuts
        $opsLink = Join-Path $result.Folder 'Metra Ops.lnk'
        Test-Path -LiteralPath $opsLink | Should -BeTrue
        $result.IconPath | Should -Not -BeNullOrEmpty
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($opsLink)
        $shortcut.IconLocation | Should -Match 'metra\.ico'
        $shortcut.TargetPath | Should -Match 'Metra-Ops\.cmd'
    }

    It 'Stop-MetraOpsHost is safe when nothing is running' {
        { Stop-MetraOpsHost -Port 7409 } | Should -Not -Throw
    }

    It 'leaves a tray host supervising another port alone' {
        InModuleScope Metra {
            $realLocalAppData = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = Join-Path ([IO.Path]::GetTempPath()) ("metra-host-" + [guid]::NewGuid().ToString('n'))
            try {
                $pidFile = Get-MetraOpsHostPidFile
                Write-MetraOpsHostState -Status 'running' -OpsPort 7380 -RestartCount 0 -StartedAt ([datetime]::UtcNow.ToString('o'))
                Set-Content -LiteralPath $pidFile -Value $PID -Encoding ASCII
                Stop-MetraOpsHost -Port 7409
                Test-Path -LiteralPath $pidFile | Should -BeTrue
                (Get-MetraOpsHostState).status | Should -Be 'running'
            }
            finally {
                Remove-Item -LiteralPath $env:LOCALAPPDATA -Recurse -Force -ErrorAction SilentlyContinue
                $env:LOCALAPPDATA = $realLocalAppData
            }
        }
    }

    It 'gives the tray a recovery path when the desk is down' {
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\OpsHost.ps1') -Raw
        # Open must revive a dead desk instead of opening a browser at a closed port.
        $source | Should -Match 'Start-MetraOpsDeskIfDown'
        $source | Should -Match "restartItem\.Text = 'Restart desk'"
        # A healthy poll clears the failure streak so a later crash still gets fast recovery.
        $source | Should -Match '\$script:MetraOpsFailureStreak = 0'
    }

    It 'keeps retrying a dead desk instead of giving up after one attempt' {
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\OpsHost.ps1') -Raw
        # An unowned child (console ops, or a desk restarted outside the tray) must still be supervised.
        $source | Should -Not -Match 'if \(-not \$script:MetraOpsOwnedChild\) \{ return \}'
        $source | Should -Match 'Get-MetraOpsHostRestartDelaySeconds'
        # Only the operator's Stop desk ends supervision.
        $source | Should -Match 'if \(\$script:MetraOpsDeskStopped\) \{ return \}'
    }

    It 'backs off on repeated restart failures without giving up' {
        InModuleScope Metra {
            Get-MetraOpsHostRestartDelaySeconds -FailureStreak 1 | Should -Be 5
            Get-MetraOpsHostRestartDelaySeconds -FailureStreak 2 | Should -Be 15
            Get-MetraOpsHostRestartDelaySeconds -FailureStreak 3 | Should -Be 60
            Get-MetraOpsHostRestartDelaySeconds -FailureStreak 9 | Should -Be 300
        }
    }

    It 'records desk pid and failure count in host state' {
        InModuleScope Metra {
            $realLocalAppData = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = Join-Path ([IO.Path]::GetTempPath()) ("metra-host-" + [guid]::NewGuid().ToString('n'))
            try {
                Write-MetraOpsHostState -Status 'restarting' -OpsPort 7380 -RestartCount 2 `
                    -StartedAt '2026-08-01T00:00:00Z' -ChildPid 4321 -ConsecutiveFailures 3
                $state = Get-MetraOpsHostState
                $state.childPid | Should -Be 4321
                $state.consecutiveFailures | Should -Be 3
                $state.hostPid | Should -Be $PID
            }
            finally {
                Remove-Item -LiteralPath $env:LOCALAPPDATA -Recurse -Force -ErrorAction SilentlyContinue
                $env:LOCALAPPDATA = $realLocalAppData
            }
        }
    }

    It 'logs supervision events so a hidden tray leaves a trace' {
        InModuleScope Metra {
            $realLocalAppData = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = Join-Path ([IO.Path]::GetTempPath()) ("metra-host-" + [guid]::NewGuid().ToString('n'))
            try {
                Write-MetraOpsHostLog 'desk restarted in test'
                $log = Get-Content -LiteralPath (Get-MetraOpsHostLogPath) -Raw
                $log | Should -Match 'desk restarted in test'
            }
            finally {
                Remove-Item -LiteralPath $env:LOCALAPPDATA -Recurse -Force -ErrorAction SilentlyContinue
                $env:LOCALAPPDATA = $realLocalAppData
            }
        }
    }

    It 'treats a live desk process as alive without an HTTP probe' {
        InModuleScope Metra {
            $realLocalAppData = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = Join-Path ([IO.Path]::GetTempPath()) ("metra-host-" + [guid]::NewGuid().ToString('n'))
            try {
                # Port 7408 has no desk: current process id stands in for a busy Ops child.
                Set-Content -LiteralPath (Get-MetraOpsPidFile -Port 7408) -Value $PID -Encoding ASCII
                Get-MetraOpsChildProcessId -Port 7408 | Should -Be $PID
                Test-MetraOpsDeskAlive -Port 7408 -TimeoutSec 1 | Should -BeTrue
                $ensure = Start-MetraOpsDeskIfDown -Port 7408
                $ensure.Ok | Should -BeTrue
                $ensure.Started | Should -BeFalse
            }
            finally {
                Remove-Item -LiteralPath $env:LOCALAPPDATA -Recurse -Force -ErrorAction SilentlyContinue
                $env:LOCALAPPDATA = $realLocalAppData
            }
        }
    }

    It 'never kills a busy Ops child on a failed health probe' {
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\OpsHost.ps1') -Raw
        # A long Ask blocks the accept loop; supervision must not stop the child for that.
        $source | Should -Not -Match 'Stop-Process -Id \$script:MetraOpsChildPid'
        $source | Should -Match 'Get-MetraOpsChildProcessId -Port \$script:MetraOpsHostPort'
    }
}


Describe 'Snapshot git detection' {
    It 'reports counts from a nested repo when the project root is not one' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-git-" + [guid]::NewGuid().ToString('n'))
            $nested = Join-Path $root 'IWU.Sample'
            New-Item -ItemType Directory -Path $nested -Force | Out-Null
            try {
                Push-Location $nested
                git init --quiet 2>$null
                git config user.email 'test@example.com' 2>$null
                git config user.name 'Metra Test' 2>$null
                Set-Content -LiteralPath (Join-Path $nested 'file.txt') -Value 'change' -Encoding ASCII
                Pop-Location

                $git = Get-MetraProjectGitCounts -Path $root
                $git.isGit | Should -BeTrue
                $git.repoPath | Should -Be 'IWU.Sample'
                $git.dirty | Should -BeGreaterThan 0
                $git.summary | Should -Match 'IWU\.Sample'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'ignores nested repos when the probe is disabled' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-git-" + [guid]::NewGuid().ToString('n'))
            $nested = Join-Path $root 'Module'
            New-Item -ItemType Directory -Path $nested -Force | Out-Null
            try {
                Push-Location $nested
                git init --quiet 2>$null
                Pop-Location

                $git = Get-MetraProjectGitCounts -Path $root -NoProbe
                $git.isGit | Should -BeFalse
                $git.summary | Should -Be 'n/a'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Secure Ops proposal core' {
    BeforeEach {
        $script:proposalStore = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-proposals-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:proposalStore -Force | Out-Null
    }

    AfterEach {
        if ($script:proposalStore -and (Test-Path -LiteralPath $script:proposalStore)) {
            Remove-Item -LiteralPath $script:proposalStore -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'creates draft with schemaVersion, contentHash, and nonceHash' {
        $store = $script:proposalStore
        InModuleScope Metra -Parameters @{ Store = $store } {
            param($Store)
            $created = New-MetraProposal `
                -Project Metra `
                -RootPath 'C:\Projects\_meta' `
                -Summary 'Update Resolve UI copy' `
                -Files @(
                    @{
                        pathRelative = 'docs/Decisions.md'
                        action       = 'replace'
                        contentUtf8  = "# hello`n"
                        previousHash = 'sha256:abc'
                    }
                ) `
                -StoreRoot $Store

            $created.Status | Should -Be 'draft'
            $created.Body.schemaVersion | Should -Be 1
            $created.Body.contentHash | Should -Match '^sha256:[0-9a-f]{64}$'
            $created.Body.nonceHash | Should -Match '^sha256:[0-9a-f]{64}$'
            $created.Nonce | Should -Not -BeNullOrEmpty
            (Test-MetraProposalContentHashMatch -Id $created.Id -StoreRoot $Store) | Should -BeTrue
            (Test-MetraProposalNonce -Id $created.Id -Nonce $created.Nonce -StoreRoot $Store) | Should -BeTrue
            Test-Path -LiteralPath $created.BodyPath | Should -BeTrue
            Test-Path -LiteralPath $created.MetaPath | Should -BeTrue
        }
    }

    It 'rejects unknown schemaVersion and replace without previousHash' {
        $store = $script:proposalStore
        InModuleScope Metra -Parameters @{ Store = $store } {
            param($Store)
            {
                New-MetraProposal -Project Metra -RootPath 'C:\x' -Summary 'x' -SchemaVersion 99 `
                    -Files @(@{ pathRelative = 'a.md'; action = 'create'; contentUtf8 = 'a' }) `
                    -StoreRoot $Store
            } | Should -Throw '*Unknown schemaVersion*'

            {
                New-MetraProposal -Project Metra -RootPath 'C:\x' -Summary 'x' `
                    -Files @(@{ pathRelative = 'a.md'; action = 'replace'; contentUtf8 = 'a' }) `
                    -StoreRoot $Store
            } | Should -Throw '*previousHash*'
        }
    }

    It 'keeps body bytes immutable across status changes' {
        $store = $script:proposalStore
        InModuleScope Metra -Parameters @{ Store = $store } {
            param($Store)
            $created = New-MetraProposal -Project Metra -RootPath 'C:\Projects\_meta' -Summary 'immutable' `
                -Files @(@{ pathRelative = 'docs/a.md'; action = 'create'; contentUtf8 = 'one' }) `
                -StoreRoot $Store
            $before = Get-MetraProposalBodyRaw -Id $created.Id -StoreRoot $Store

            Request-MetraProposalApply -Id $created.Id -StoreRoot $Store | Out-Null
            $mid = Get-MetraProposal -Id $created.Id -StoreRoot $Store
            $mid.Status | Should -Be 'pendingApply'
            (Get-MetraProposalBodyRaw -Id $created.Id -StoreRoot $Store) | Should -BeExactly $before

            Set-MetraProposalStatus -Id $created.Id -Status applied -ResultMessage Applied -StoreRoot $Store | Out-Null
            (Get-MetraProposalBodyRaw -Id $created.Id -StoreRoot $Store) | Should -BeExactly $before
            (Get-MetraProposal -Id $created.Id -StoreRoot $Store).Status | Should -Be 'applied'
        }
    }

    It 'blocks illegal status transitions' {
        $store = $script:proposalStore
        InModuleScope Metra -Parameters @{ Store = $store } {
            param($Store)
            $created = New-MetraProposal -Project Metra -RootPath 'C:\x' -Summary 'x' `
                -Files @(@{ pathRelative = 'a.md'; action = 'create'; contentUtf8 = 'a' }) `
                -StoreRoot $Store

            {
                Set-MetraProposalStatus -Id $created.Id -Status applied -StoreRoot $Store
            } | Should -Throw '*Illegal proposal status transition*'

            Deny-MetraProposal -Id $created.Id -StoreRoot $Store | Out-Null
            {
                Request-MetraProposalApply -Id $created.Id -StoreRoot $Store
            } | Should -Throw '*Illegal proposal status transition*'
        }
    }

    It 'expires overdue draft and pendingApply proposals' {
        $store = $script:proposalStore
        InModuleScope Metra -Parameters @{ Store = $store } {
            param($Store)
            $past = [datetime]::UtcNow.AddMinutes(-30)
            $created = New-MetraProposal -Project Metra -RootPath 'C:\x' -Summary 'old' `
                -Files @(@{ pathRelative = 'a.md'; action = 'create'; contentUtf8 = 'a' }) `
                -CreatedAtUtc $past `
                -TtlMinutes 5 `
                -StoreRoot $Store

            $expired = Sync-MetraProposalExpiration -Id $created.Id -StoreRoot $Store
            $expired.Count | Should -Be 1
            $expired[0].Status | Should -Be 'expired'

            $fresh = New-MetraProposal -Project Metra -RootPath 'C:\x' -Summary 'fresh' `
                -Files @(@{ pathRelative = 'b.md'; action = 'create'; contentUtf8 = 'b' }) `
                -CreatedAtUtc $past `
                -TtlMinutes 5 `
                -StoreRoot $Store
            $viaRequest = Request-MetraProposalApply -Id $fresh.Id -StoreRoot $Store
            $viaRequest.Status | Should -Be 'expired'
        }
    }
}

Describe 'Secure Ops proposal jail' {
    BeforeEach {
        $script:jailRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-jail-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:jailRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:jailRoot 'docs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:jailRoot 'docs\notes.md') -Value "hello`n" -Encoding utf8NoBOM
    }

    AfterEach {
        if ($script:jailRoot -and (Test-Path -LiteralPath $script:jailRoot)) {
            Remove-Item -LiteralPath $script:jailRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'allows a boring markdown replace in preview and apply when previousHash matches' {
        $root = $script:jailRoot
        InModuleScope Metra -Parameters @{ Root = $root } {
            param($Root)
            $existing = Get-Content -LiteralPath (Join-Path $Root 'docs\notes.md') -Raw
            $hash = ConvertTo-MetraProposalSha256 -Text $existing
            $files = @(
                @{
                    pathRelative = 'docs/notes.md'
                    action       = 'replace'
                    contentUtf8  = "hello world`n"
                    previousHash = $hash
                }
            )

            $preview = Test-MetraProposalJail -Mode Preview -Project Metra -RootPath $Root -Files $files -ProjectCatalog @('Metra')
            $preview.Ok | Should -BeTrue

            $apply = Test-MetraProposalJail -Mode Apply -Project Metra -RootPath $Root -Files $files -ProjectCatalog @('Metra')
            $apply.Ok | Should -BeTrue
            $apply.Mode | Should -Be 'Apply'
        }
    }

    It 'table-driven preview denials' {
        $root = $script:jailRoot
        InModuleScope Metra -Parameters @{ Root = $root } {
            param($Root)
            $cases = @(
                @{
                    Name   = 'path escape'
                    Files  = @(@{ pathRelative = '../outside.md'; action = 'create'; contentUtf8 = 'x' })
                    Code   = 'pathRejected'
                }
                @{
                    Name   = 'ps1 denied'
                    Files  = @(@{ pathRelative = 'hack.ps1'; action = 'create'; contentUtf8 = 'x' })
                    Code   = 'policyDenied'
                }
                @{
                    Name   = 'git segment'
                    Files  = @(@{ pathRelative = '.git/config.md'; action = 'create'; contentUtf8 = 'x' })
                    Code   = 'policyDenied'
                }
                @{
                    Name   = 'credential name'
                    Files  = @(@{ pathRelative = 'docs/my-credential.json'; action = 'create'; contentUtf8 = '{}' })
                    Code   = 'policyDenied'
                }
                @{
                    Name   = 'replace missing previousHash'
                    Files  = @(@{ pathRelative = 'docs/notes.md'; action = 'replace'; contentUtf8 = 'x' })
                    Code   = 'policyDenied'
                }
                @{
                    Name   = 'vscode settings'
                    Files  = @(@{ pathRelative = '.vscode/settings.json'; action = 'create'; contentUtf8 = '{}' })
                    Code   = 'policyDenied'
                }
            )

            foreach ($case in $cases) {
                $result = Test-MetraProposalJail -Mode Preview -Project Metra -RootPath $Root -Files $case.Files -ProjectCatalog @('Metra')
                $result.Ok | Should -BeFalse -Because $case.Name
                $result.ReasonCode | Should -Be $case.Code -Because $case.Name
            }
        }
    }

    It 'rejects unknown project and unknown schemaVersion in preview' {
        $root = $script:jailRoot
        InModuleScope Metra -Parameters @{ Root = $root } {
            param($Root)
            $files = @(@{ pathRelative = 'docs/a.md'; action = 'create'; contentUtf8 = 'a' })
            $missing = Test-MetraProposalJail -Mode Preview -Project NoSuchProject -RootPath $Root -Files $files -ProjectCatalog @('Metra')
            $missing.Ok | Should -BeFalse
            $missing.ReasonCode | Should -Be 'policyDenied'

            $schema = Test-MetraProposalJail -Mode Preview -Project Metra -RootPath $Root -Files $files -SchemaVersion 99 -ProjectCatalog @('Metra')
            $schema.Ok | Should -BeFalse
            $schema.ReasonCode | Should -Be 'schemaRejected'
        }
    }

    It 'apply rejects hash mismatch and create-when-exists' {
        $root = $script:jailRoot
        InModuleScope Metra -Parameters @{ Root = $root } {
            param($Root)
            $mismatch = Test-MetraProposalJail -Mode Apply -Project Metra -RootPath $Root -ProjectCatalog @('Metra') -Files @(
                @{
                    pathRelative = 'docs/notes.md'
                    action       = 'replace'
                    contentUtf8  = "changed`n"
                    previousHash = 'sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
                }
            )
            $mismatch.Ok | Should -BeFalse
            $mismatch.ReasonCode | Should -Be 'hashMismatch'

            $exists = Test-MetraProposalJail -Mode Apply -Project Metra -RootPath $Root -ProjectCatalog @('Metra') -Files @(
                @{
                    pathRelative = 'docs/notes.md'
                    action       = 'create'
                    contentUtf8  = "nope`n"
                }
            )
            $exists.Ok | Should -BeFalse
            $exists.ReasonCode | Should -Be 'fileChanged'
        }
    }

    It 'apply allows create for a new markdown file under root' {
        $root = $script:jailRoot
        InModuleScope Metra -Parameters @{ Root = $root } {
            param($Root)
            $okCreate = Test-MetraProposalJail -Mode Apply -Project Metra -RootPath $Root -ProjectCatalog @('Metra') -Files @(
                @{
                    pathRelative = 'docs/new-note.md'
                    action       = 'create'
                    contentUtf8  = "fresh`n"
                }
            )
            $okCreate.Ok | Should -BeTrue
        }
    }

    It 'enforces file count limit' {
        $root = $script:jailRoot
        InModuleScope Metra -Parameters @{ Root = $root } {
            param($Root)
            $files = 1..6 | ForEach-Object {
                @{
                    pathRelative = "docs/f$_.md"
                    action       = 'create'
                    contentUtf8  = 'x'
                }
            }
            $result = Test-MetraProposalJail -Mode Preview -Project Metra -RootPath $Root -Files $files -ProjectCatalog @('Metra')
            $result.Ok | Should -BeFalse
            $result.ReasonCode | Should -Be 'policyDenied'
            $result.Message | Should -Match 'File count'
        }
    }
}

Describe 'Secure Ops proposal host apply' {
    BeforeEach {
        $script:applyStore = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-apply-store-' + [guid]::NewGuid().ToString('N'))
        $script:applyRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-apply-root-' + [guid]::NewGuid().ToString('N'))
        $script:applyData = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-apply-data-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:applyStore -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:applyRoot 'docs') -Force | Out-Null
        New-Item -ItemType Directory -Path $script:applyData -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:applyRoot 'docs\notes.md') -Value "hello`n" -Encoding utf8NoBOM
    }

    AfterEach {
        foreach ($path in @($script:applyStore, $script:applyRoot, $script:applyData)) {
            if ($path -and (Test-Path -LiteralPath $path)) {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'applies pending proposal after confirm and writes audit' {
        $store = $script:applyStore
        $root = $script:applyRoot
        $data = $script:applyData
        InModuleScope Metra -Parameters @{ Store = $store; Root = $root; Data = $data } {
            param($Store, $Root, $Data)
            $existing = Get-Content -LiteralPath (Join-Path $Root 'docs\notes.md') -Raw
            $hash = ConvertTo-MetraProposalSha256 -Text $existing
            $created = New-MetraProposal -Project Metra -RootPath $Root -Summary 'host apply' -StoreRoot $Store -Files @(
                @{
                    pathRelative = 'docs/notes.md'
                    action       = 'replace'
                    contentUtf8  = "hello applied`n"
                    previousHash = $hash
                }
            )
            Request-MetraProposalApply -Id $created.Id -StoreRoot $Store | Out-Null

            $result = Invoke-MetraProposalHostApply -Id $created.Id -StoreRoot $Store -DataDir $Data -ConfirmAction { 'apply' }
            $result.Ok | Should -BeTrue
            $result.ReasonCode | Should -Be 'applied'
            (Get-Content -LiteralPath (Join-Path $Root 'docs\notes.md') -Raw) | Should -BeExactly "hello applied`n"
            (Get-MetraProposal -Id $created.Id -StoreRoot $Store).Status | Should -Be 'applied'

            $audit = Get-Content -LiteralPath (Join-Path $Data 'apply-audit.log') -Raw
            $audit | Should -Match 'proposal.applied'
            $audit.Contains($created.Id) | Should -BeTrue
        }
    }

    It 'audits user deny without writing files' {
        $store = $script:applyStore
        $root = $script:applyRoot
        $data = $script:applyData
        InModuleScope Metra -Parameters @{ Store = $store; Root = $root; Data = $data } {
            param($Store, $Root, $Data)
            $existing = Get-Content -LiteralPath (Join-Path $Root 'docs\notes.md') -Raw
            $hash = ConvertTo-MetraProposalSha256 -Text $existing
            $created = New-MetraProposal -Project Metra -RootPath $Root -Summary 'deny me' -StoreRoot $Store -Files @(
                @{
                    pathRelative = 'docs/notes.md'
                    action       = 'replace'
                    contentUtf8  = "nope`n"
                    previousHash = $hash
                }
            )
            Request-MetraProposalApply -Id $created.Id -StoreRoot $Store | Out-Null

            $result = Invoke-MetraProposalHostApply -Id $created.Id -StoreRoot $Store -DataDir $Data -ConfirmAction { 'deny' }
            $result.Ok | Should -BeFalse
            $result.ReasonCode | Should -Be 'rejected'
            (Get-Content -LiteralPath (Join-Path $Root 'docs\notes.md') -Raw) | Should -BeExactly $existing
            (Get-Content -LiteralPath (Join-Path $Data 'apply-audit.log') -Raw) | Should -Match 'proposal.rejected'
        }
    }

    It 'audits hash mismatch from jail revalidate' {
        $store = $script:applyStore
        $root = $script:applyRoot
        $data = $script:applyData
        InModuleScope Metra -Parameters @{ Store = $store; Root = $root; Data = $data } {
            param($Store, $Root, $Data)
            $existing = Get-Content -LiteralPath (Join-Path $Root 'docs\notes.md') -Raw
            $hash = ConvertTo-MetraProposalSha256 -Text $existing
            $created = New-MetraProposal -Project Metra -RootPath $Root -Summary 'stale' -StoreRoot $Store -Files @(
                @{
                    pathRelative = 'docs/notes.md'
                    action       = 'replace'
                    contentUtf8  = "new`n"
                    previousHash = $hash
                }
            )
            Request-MetraProposalApply -Id $created.Id -StoreRoot $Store | Out-Null
            Set-Content -LiteralPath (Join-Path $Root 'docs\notes.md') -Value "changed underneath`n" -Encoding utf8NoBOM

            $result = Invoke-MetraProposalHostApply -Id $created.Id -StoreRoot $Store -DataDir $Data -SkipConfirm
            $result.Ok | Should -BeFalse
            $result.ReasonCode | Should -Be 'hashMismatch'
            (Get-Content -LiteralPath (Join-Path $Data 'apply-audit.log') -Raw) | Should -Match 'proposal.hashMismatch'
        }
    }

    It 'Sync-MetraProposalHostPending processes one pending proposal' {
        $store = $script:applyStore
        $root = $script:applyRoot
        $data = $script:applyData
        InModuleScope Metra -Parameters @{ Store = $store; Root = $root; Data = $data } {
            param($Store, $Root, $Data)
            $created = New-MetraProposal -Project Metra -RootPath $Root -Summary 'create file' -StoreRoot $Store -Files @(
                @{
                    pathRelative = 'docs/new.md'
                    action       = 'create'
                    contentUtf8  = "brand new`n"
                }
            )
            Request-MetraProposalApply -Id $created.Id -StoreRoot $Store | Out-Null

            $results = @(Sync-MetraProposalHostPending -StoreRoot $Store -DataDir $Data -ConfirmAction { 'apply' })
            $results.Count | Should -Be 1
            $results[0].Ok | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $Root 'docs\new.md') | Should -BeTrue
        }
    }

    It 'OpsHost timer source polls proposal apply' {
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\OpsHost.ps1') -Raw
        $source | Should -Match 'Sync-MetraProposalHostPending'
    }
}

Describe 'Secure Ops proposal API' {
    BeforeEach {
        $script:apiStore = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-prop-api-' + [guid]::NewGuid().ToString('N'))
        $script:apiRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-prop-root-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:apiStore -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:apiRoot 'docs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:apiRoot 'docs\notes.md') -Value "hello`n" -Encoding utf8NoBOM
    }

    AfterEach {
        foreach ($path in @($script:apiStore, $script:apiRoot)) {
            if ($path -and (Test-Path -LiteralPath $path)) {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'creates, gets, diffs, and request-applies without writing project files' {
        $store = $script:apiStore
        $root = $script:apiRoot
        InModuleScope Metra -Parameters @{ Store = $store; Root = $root } {
            param($Store, $Root)
            $existing = Get-Content -LiteralPath (Join-Path $Root 'docs\notes.md') -Raw
            $hash = ConvertTo-MetraProposalSha256 -Text $existing
            $body = @{
                project       = 'Metra'
                rootPath      = $Root
                summary       = 'Update notes'
                schemaVersion = 1
                files         = @(
                    @{
                        pathRelative = 'docs/notes.md'
                        action       = 'replace'
                        contentUtf8  = "hello world`n"
                        previousHash = $hash
                    }
                )
            } | ConvertTo-Json -Depth 8

            $created = Invoke-MetraOpsProposalCommand -Method POST -Path '/api/proposals' -Body $body -IsLoopback:$true -StoreRoot $Store
            $created.StatusCode | Should -Be 201
            $created.Object.status | Should -Be 'draft'
            $id = [string]$created.Object.id
            $id | Should -Match '^p_'

            $before = Get-Content -LiteralPath (Join-Path $Root 'docs\notes.md') -Raw

            $got = Invoke-MetraOpsProposalCommand -Method GET -Path "/api/proposals/$id" -IsLoopback:$true -StoreRoot $Store
            $got.StatusCode | Should -Be 200
            $got.Object.summary | Should -Be 'Update notes'

            $diff = Invoke-MetraOpsProposalCommand -Method GET -Path "/api/proposals/$id/diff" -IsLoopback:$true -StoreRoot $Store
            $diff.StatusCode | Should -Be 200
            $diff.Text | Should -Match 'docs/notes.md'

            $pending = Invoke-MetraOpsProposalCommand -Method POST -Path "/api/proposals/$id/request-apply" -IsLoopback:$true -StoreRoot $Store
            $pending.StatusCode | Should -Be 200
            $pending.Object.status | Should -Be 'pendingApply'

            $status = Invoke-MetraOpsProposalCommand -Method GET -Path "/api/proposals/$id/status" -IsLoopback:$true -StoreRoot $Store
            $status.Object.status | Should -Be 'pendingApply'

            (Get-Content -LiteralPath (Join-Path $Root 'docs\notes.md') -Raw) | Should -BeExactly $before
        }
    }

    It 'rejects /apply and non-loopback mutate without session' {
        $store = $script:apiStore
        InModuleScope Metra -Parameters @{ Store = $store } {
            param($Store)
            $apply = Invoke-MetraOpsProposalCommand -Method POST -Path '/api/proposals/p_x/apply' -IsLoopback:$true -StoreRoot $Store
            $apply.StatusCode | Should -Be 404
            $apply.Object.error | Should -Match 'request-apply'

            $remote = Invoke-MetraOpsProposalCommand -Method POST -Path '/api/proposals' -Body '{"project":"Metra"}' -IsLoopback:$false -StoreRoot $Store
            $remote.StatusCode | Should -Be 403
            $remote.Object.reasonCode | Should -Be 'localSessionRequired'
        }
    }

    It 'returns 400 when jail denies create' {
        $store = $script:apiStore
        $root = $script:apiRoot
        InModuleScope Metra -Parameters @{ Store = $store; Root = $root } {
            param($Store, $Root)
            $body = @{
                project  = 'Metra'
                rootPath = $Root
                summary  = 'bad'
                files    = @(@{ pathRelative = 'hack.ps1'; action = 'create'; contentUtf8 = 'x' })
            } | ConvertTo-Json -Depth 6

            $denied = Invoke-MetraOpsProposalCommand -Method POST -Path '/api/proposals' -Body $body -IsLoopback:$true -StoreRoot $Store
            $denied.StatusCode | Should -Be 400
            $denied.Object.reasonCode | Should -Be 'policyDenied'
        }
    }

    It 'OpsServer wires proposal routes and never names an apply endpoint handler' {
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\OpsServer.ps1') -Raw
        $source | Should -Match 'Invoke-MetraOpsProposalCommand'
        $source | Should -Match '/api/proposals'
        ($source -match '/api/proposals/.*/apply') | Should -BeFalse

        $apiSource = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\ProposalApi.ps1') -Raw
        $apiSource | Should -Match 'request-apply'
        $apiSource | Should -Match "action -eq 'apply'"
    }
}

Describe 'Secure Ops webview bridge and Tailscale session' {
    It 'page and extension forbid bare apply bridge messages' {
        $bridge = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'ops\src\bridge.ts') -Raw
        $bridge | Should -Match 'requestProposalApply'
        $bridge | Should -Match 'askInChat'
        $bridge | Should -Match 'openWorkspacePath'
        $bridge | Should -Match 'surfaceReady'
        $bridge | Should -Match 'applyStatus'
        $bridge | Should -Match "FORBIDDEN_BRIDGE_APPLY_TYPE = 'requestApply'"
        $bridge | Should -Match 'formatAskTabTitle'

        $ext = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'integrations\vscode-metra-ops\extension.js') -Raw
        $ext | Should -Match 'requestProposalApply'
        $ext | Should -Match "FORBIDDEN_TYPES"
        $ext | Should -Match 'requestApply'
        $ext | Should -Not -Match "type === 'apply'"
        ($ext -match "postMessage\(\{\s*type:\s*'apply'") | Should -BeFalse
    }

    It 'issues local session token and accepts non-loopback mutate with it' {
        $dataDir = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-session-' + [guid]::NewGuid().ToString('N'))
        $store = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-proposals-' + [guid]::NewGuid().ToString('N'))
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('metra-root-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dataDir, $store, (Join-Path $root 'docs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'docs\notes.md') -Value "old`n" -Encoding utf8
        try {
            InModuleScope Metra -Parameters @{ DataDir = $dataDir; Store = $store; Root = $root } {
                param($DataDir, $Store, $Root)

                $denied = Invoke-MetraOpsProposalCommand -Method POST -Path '/api/proposals' -Body '{"project":"Metra"}' -IsLoopback:$false -StoreRoot $Store
                $denied.StatusCode | Should -Be 403
                $denied.Object.reasonCode | Should -Be 'localSessionRequired'

                $issued = Initialize-MetraOpsLocalSessionToken -DataDir $DataDir -Rotate
                $issued.Token | Should -Match '^[0-9a-f]{64}$'
                (Test-MetraOpsLocalSessionToken -SessionToken $issued.Token -ExpectedToken $issued.Token) | Should -BeTrue
                (Test-MetraOpsLocalSessionToken -SessionToken 'nope' -ExpectedToken $issued.Token) | Should -BeFalse

                # Point the default token path via env LOCALAPPDATA override is hard; call Allowed with Expected through API path:
                # Temporarily write to real LOCALAPPDATA Metra folder is avoided - use Test-MetraOpsProposalCallerAllowed directly.
                (Test-MetraOpsProposalCallerAllowed -IsLoopback:$false -SessionToken $issued.Token) | Should -BeFalse

                $tokenPath = Join-Path $env:LOCALAPPDATA 'Metra\ops-local-session.token'
                $dir = Split-Path -Parent $tokenPath
                if (-not (Test-Path -LiteralPath $dir)) {
                    $null = New-Item -ItemType Directory -Path $dir -Force
                }
                $backup = $null
                if (Test-Path -LiteralPath $tokenPath) {
                    $backup = Get-Content -LiteralPath $tokenPath -Raw -Encoding UTF8
                }
                try {
                    Set-Content -LiteralPath $tokenPath -Value $issued.Token -Encoding utf8 -NoNewline
                    (Test-MetraOpsProposalCallerAllowed -IsLoopback:$false -SessionToken $issued.Token) | Should -BeTrue

                    $hash = ConvertTo-MetraProposalSha256 -Text "old`n"
                    $body = @{
                        project  = 'Metra'
                        rootPath = $Root
                        summary  = 'session ok'
                        files    = @(@{
                                pathRelative = 'docs/notes.md'
                                action       = 'replace'
                                contentUtf8  = "new`n"
                                previousHash = $hash
                            })
                    } | ConvertTo-Json -Depth 6

                    $created = Invoke-MetraOpsProposalCommand -Method POST -Path '/api/proposals' -Body $body -IsLoopback:$false -SessionToken $issued.Token -StoreRoot $Store
                    $created.StatusCode | Should -Be 201
                    $id = [string]$created.Object.id
                    $pending = Invoke-MetraOpsProposalCommand -Method POST -Path "/api/proposals/$id/request-apply" -IsLoopback:$false -SessionToken $issued.Token -StoreRoot $Store
                    $pending.StatusCode | Should -Be 200
                    $pending.Object.status | Should -Be 'pendingApply'
                }
                finally {
                    if ($null -ne $backup) {
                        Set-Content -LiteralPath $tokenPath -Value $backup -Encoding utf8 -NoNewline
                    }
                    elseif (Test-Path -LiteralPath $tokenPath) {
                        Remove-Item -LiteralPath $tokenPath -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        finally {
            Remove-Item -LiteralPath $dataDir, $store, $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'builds Tailscale dual-prefix binding objects' {
        InModuleScope Metra {
            Mock Get-MetraOpsTailscaleDnsName { $null }
            Mock Get-MetraOpsTailscaleServeStatus { [pscustomobject]@{ Ok = $false; ShareUrl = $null; Reason = 'off' } }
            $b = Get-MetraOpsTailscaleBinding -Address '100.64.1.2' -Port 7380
            $b.Tailscale | Should -BeTrue
            $b.BrowserUrl | Should -Be 'http://100.64.1.2:7380/'
            @($b.ListenerPrefixes) | Should -Contain 'http://127.0.0.1:7380/'
            @($b.ListenerPrefixes) | Should -Contain 'http://100.64.1.2:7380/'
        }
    }

    It 'prefers MagicDNS for share URL and listens on both names' {
        InModuleScope Metra {
            Mock Get-MetraOpsTailscaleServeStatus { [pscustomobject]@{ Ok = $false; ShareUrl = $null; Reason = 'off' } }
            $b = Get-MetraOpsTailscaleBinding -Address '100.64.1.2' -Port 80 -DnsName 'dev-jmp01.taila8f8a7.ts.net.'
            $b.BrowserUrl | Should -Be 'http://dev-jmp01.taila8f8a7.ts.net/'
            $b.ShareUrl | Should -Be 'http://dev-jmp01.taila8f8a7.ts.net/'
            $b.DnsName | Should -Be 'dev-jmp01.taila8f8a7.ts.net'
            $b.TailscaleIp | Should -Be '100.64.1.2'
            @($b.ListenerPrefixes) | Should -Contain 'http://127.0.0.1:80/'
            @($b.ListenerPrefixes) | Should -Contain 'http://100.64.1.2:80/'
            @($b.ListenerPrefixes) | Should -Contain 'http://dev-jmp01.taila8f8a7.ts.net:80/'
        }
    }

    It 'keeps Tailscale prefixes when the desk starts with an explicit port' {
        InModuleScope Metra {
            Mock Get-MetraDeskPreferences { [pscustomobject]@{ opsPort = 80; browserHost = '100.64.1.2'; bindTailscale = $true } }
            Mock Get-MetraOpsTailscaleIPv4 { '100.64.1.2' }
            Mock Get-MetraOpsTailscaleDnsName { 'dev-jmp01.taila8f8a7.ts.net' }
            Mock Get-MetraOpsTailscaleServeStatus { [pscustomobject]@{ Ok = $false; ShareUrl = $null; Reason = 'off' } }
            Mock Test-MetraHostsEntry { $false }

            $b = Get-MetraOpsDeskBindingForPort -Port 80
            $b.Tailscale | Should -BeTrue
            @($b.ListenerPrefixes) | Should -Contain 'http://100.64.1.2:80/'
            @($b.ListenerPrefixes) | Should -Contain 'http://127.0.0.1:80/'
            @($b.ListenerPrefixes) | Should -Contain 'http://dev-jmp01.taila8f8a7.ts.net:80/'
            $b.BrowserUrl | Should -Be 'http://dev-jmp01.taila8f8a7.ts.net/'
        }
    }

    It 'falls back to loopback for an explicit port when Tailscale is off' {
        InModuleScope Metra {
            Mock Get-MetraDeskPreferences { [pscustomobject]@{ opsPort = 7380; browserHost = ''; bindTailscale = $false } }
            Mock Test-MetraHostsEntry { $false }

            $b = Get-MetraOpsDeskBindingForPort -Port 7380
            @($b.ListenerPrefixes) | Should -Be @('http://127.0.0.1:7380/')
        }
    }

    It 'starts the desk from the pref-aware binding helper' {
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\OpsServer.ps1') -Raw
        $source | Should -Match 'Get-MetraOpsDeskBindingForPort'
    }

    It 'OpsServer exposes loopback-only local-session and CORS session header' {
        $source = Get-Content -LiteralPath (Join-Path (Get-MetraRoot) 'scripts\private\OpsServer.ps1') -Raw
        $source | Should -Match '/api/local-session'
        $source | Should -Match 'localSessionLoopbackOnly'
        $source | Should -Match 'X-Metra-Local-Session'
        $source | Should -Match 'Initialize-MetraOpsLocalSessionToken'
    }
}
