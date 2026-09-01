# Boundary: Loom must not import Metra private scripts.
BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Metra -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    $script:RepoRoot = $repoRoot
    Import-Module (Join-Path $repoRoot 'modules\Loom\Loom.psd1') -Force
    $script:ApRoot = Join-Path $repoRoot 'modules\Loom'
}

Describe 'Loom boundary' {
    It 'domain and adapters do not reference scripts/private paths' {
        $hits = @()
        foreach ($f in @(Get-ChildItem -LiteralPath $script:ApRoot -Recurse -Include *.ps1, *.psm1 -File)) {
            $text = Get-Content -LiteralPath $f.FullName -Raw
            if ($text -match 'scripts[/\\]private[/\\](Routing|Capture|Inspect|Snapshot)\.ps1') {
                $hits += $f.FullName
            }
            if ($text -match '(?m)^\s*\.\s+.*scripts[/\\]private') {
                $hits += $f.FullName
            }
        }
        $hits | Should -BeNullOrEmpty
    }

    It 'does not call Get-MetraRoutingAmbiguity / Get-MetraCaptureLedger directly from Domain' {
        $domain = Join-Path $script:ApRoot 'Private\Domain.ps1'
        $text = Get-Content -LiteralPath $domain -Raw
        $text | Should -Not -Match 'Get-MetraRoutingAmbiguity'
        $text | Should -Not -Match 'Get-MetraCaptureLedger'
        $text | Should -Not -Match 'Get-MetraInspectPlanRoots'
        $text | Should -Not -Match 'Write-MetraAtomicUtf8Text'
        $text | Should -Match 'Get-LoomRoutingAmbiguity'
        $text | Should -Match 'Get-LoomCaptureLedger'
    }

    It 'shim Loom.ps1 is thin' {
        $shim = Join-Path $script:RepoRoot 'scripts\private\Loom.ps1'
        $lines = @(Get-Content -LiteralPath $shim)
        $lines.Count | Should -BeLessThan 40
        ($lines -join "`n") | Should -Match 'Import-Module'
        ($lines -join "`n") | Should -Match 'Invoke-LoomCommand'
    }
}
