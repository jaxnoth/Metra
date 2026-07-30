# Requires Pester 5+ (pwsh recommended).
# Run: pwsh -NoProfile -File .\tests\Invoke-MetraTests.ps1

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psm1') -Force
}

Describe 'Get-MetraRoutingTable' {
    It 'returns TicketTracker, Solarwinds, and Trivia rows from shared/local registry' {
        $rows = @(Get-MetraRoutingTable -Name @('TicketTracker', 'Solarwinds', 'Trivia'))
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

Describe 'Export-MetraContextPack' {
    It 'Path - with Quiet does not rewrite docs/context-pack.md' {
        $packPath = Join-Path (Get-MetraRoot) 'docs\context-pack.md'
        $before = if (Test-Path -LiteralPath $packPath) {
            (Get-Item -LiteralPath $packPath).LastWriteTimeUtc
        }
        else {
            $null
        }

        Start-Sleep -Milliseconds 50
        $result = Export-MetraContextPack -Query 'ticket' -Format markdown -Path '-' -Quiet |
            Select-Object -Last 1

        $result.Path | Should -Be '-'
        $result.Format | Should -Be 'markdown'

        if ($null -ne $before -and (Test-Path -LiteralPath $packPath)) {
            (Get-Item -LiteralPath $packPath).LastWriteTimeUtc | Should -Be $before
        }
    }
}

Describe 'Invoke-MetraSetup' {
    It 'Preview -Quiet returns structured result without seeding when config exists' {
        $preferred = Join-Path (Get-MetraRoot) 'metra.config.json'
        $legacy = Join-Path (Get-MetraRoot) 'meta.config.json'
        $hasConfig = (Test-Path -LiteralPath $preferred) -or (Test-Path -LiteralPath $legacy)
        $hasConfig | Should -BeTrue

        $result = Invoke-MetraSetup -Preview -Quiet
        $result.Preview | Should -BeTrue
        $result.WouldSeedConfig | Should -BeFalse
        $result.SeededConfig | Should -BeFalse
        $result.Workspace | Should -BeNullOrEmpty
        @($result.Roots).Count | Should -BeGreaterThan 0
    }

    It 'Preview with sample Profile does not throw and keeps WouldSeedConfig false when config exists' {
        $sample = Join-Path (Get-MetraRoot) 'profiles\sample'
        $result = Invoke-MetraSetup -Profile $sample -Preview -Quiet
        $result.Preview | Should -BeTrue
        $result.WouldSeedConfig | Should -BeFalse
        $result.Import | Should -Not -BeNullOrEmpty
        $result.Import.Preview | Should -BeTrue
    }
}

Describe 'Invoke-MetraVerify' {
    It 'returns structured PASS/WARN/FAIL with Ok when FailCount is 0' {
        $report = Invoke-MetraVerify
        $report.PassCount | Should -BeGreaterThan 0
        $report.FailCount | Should -BeGreaterOrEqual 0
        $report.Ok | Should -Be ($report.FailCount -eq 0)
        @($report.Results).Count | Should -Be ($report.PassCount + $report.WarnCount + $report.FailCount)
        ($report.Results | Where-Object Status -eq 'FAIL').Count | Should -Be $report.FailCount
    }

    It 'passes on this machine (no FAIL rows)' {
        $report = Invoke-MetraVerify
        $report.FailCount | Should -Be 0
        $report.Ok | Should -BeTrue
    }
}

