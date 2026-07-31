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

