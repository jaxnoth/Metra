# Requires Pester 5+ (pwsh recommended).
# Run: pwsh -NoProfile -File .\tests\Invoke-MetaTests.ps1

BeforeAll {
    $metaRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metaRoot 'scripts\Meta.psm1') -Force
}

Describe 'Get-MetaRoutingTable' {
    It 'returns TicketTracker, Solarwinds, and Trivia rows from shared/local registry' {
        $rows = @(Get-MetaRoutingTable -Name @('TicketTracker', 'Solarwinds', 'Trivia'))
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

Describe 'Import-MetaProfile' {
    It 'Preview -Quiet returns files and writes nothing' {
        $sample = Join-Path (Get-MetaRoot) 'profiles\sample'
        $result = Import-MetaProfile -Path $sample -Preview -Quiet
        $result.Preview | Should -BeTrue
        @($result.Files).Count | Should -BeGreaterThan 0
        $result.Files | Should -Contain 'meta.config.json'
    }

    It 'refuses overwrite without -Force when targets exist' {
        $sample = Join-Path (Get-MetaRoot) 'profiles\sample'
        # Live checkout already has local targets from sample/operator use.
        { Import-MetaProfile -Path $sample -Quiet } | Should -Throw '*Refusing to overwrite*'
    }
}

Describe 'Export-MetaContextPack' {
    It 'Path - with Quiet does not rewrite docs/context-pack.md' {
        $packPath = Join-Path (Get-MetaRoot) 'docs\context-pack.md'
        $before = if (Test-Path -LiteralPath $packPath) {
            (Get-Item -LiteralPath $packPath).LastWriteTimeUtc
        }
        else {
            $null
        }

        Start-Sleep -Milliseconds 50
        $result = Export-MetaContextPack -Query 'ticket' -Format markdown -Path '-' -Quiet |
            Select-Object -Last 1

        $result.Path | Should -Be '-'
        $result.Format | Should -Be 'markdown'

        if ($null -ne $before -and (Test-Path -LiteralPath $packPath)) {
            (Get-Item -LiteralPath $packPath).LastWriteTimeUtc | Should -Be $before
        }
    }
}

Describe 'Invoke-MetaVerify' {
    It 'returns structured PASS/WARN/FAIL with Ok when FailCount is 0' {
        $report = Invoke-MetaVerify
        $report.PassCount | Should -BeGreaterThan 0
        $report.FailCount | Should -BeGreaterOrEqual 0
        $report.Ok | Should -Be ($report.FailCount -eq 0)
        @($report.Results).Count | Should -Be ($report.PassCount + $report.WarnCount + $report.FailCount)
        ($report.Results | Where-Object Status -eq 'FAIL').Count | Should -Be $report.FailCount
    }

    It 'passes on this machine (no FAIL rows)' {
        $report = Invoke-MetaVerify
        $report.FailCount | Should -Be 0
        $report.Ok | Should -BeTrue
    }
}
