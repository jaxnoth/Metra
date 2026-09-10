# Plan-index schema, stem fixtures, seed, resolve.
#Requires -Modules Pester
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Yarn.PlanIndex.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'modules\Yarn\Yarn.psd1') -Force
    $script:FixtureStem = Join-Path $PSScriptRoot 'fixtures\plan-index\stem-cases.yaml'
}

Describe 'Yarn plan-index stem fixtures' {
    It 'normalizes stems per shared fixtures' {
        $raw = Get-Content -LiteralPath $script:FixtureStem -Raw
        $cases = [regex]::Matches($raw, '(?ms)- leaf:\s*(.*?)\r?\n\s*stem:\s*(.*?)\r?\n')
        $cases.Count | Should -BeGreaterThan 3
        foreach ($c in $cases) {
            $leafRaw = $c.Groups[1].Value.Trim()
            $stemRaw = $c.Groups[2].Value.Trim()
            $leaf = if ($leafRaw -eq '""') { '' } else { $leafRaw.Trim('"') }
            $stem = if ($stemRaw -eq '""') { '' } else { $stemRaw.Trim('"') }
            (Get-YarnPlanBoardInventoryNormalizeStem -Text $leaf) | Should -Be $stem
        }
    }
}

Describe 'Yarn plan-index read/write/resolve' {
    It 'creates cursor entry, preserves repo authority, rejects traversal, resolves correctly' {
        InModuleScope Yarn {
            $temp = Join-Path ([IO.Path]::GetTempPath()) ('metra-plan-index-' + [guid]::NewGuid().ToString('n'))
            $plansDir = Join-Path $temp 'plans'
            $cursorDir = Join-Path $temp 'cursor-plans'
            try {
                New-Item -ItemType Directory -Path $plansDir, $cursorDir -Force | Out-Null
                $script:YarnCursorPlansDirOverride = $cursorDir

                $r = Set-MetraPlanIndexEntry -PlansDir $plansDir -Project 'Metra' `
                    -Stem 'demo-plan' -CursorLeaf 'demo_plan_abcd1234.plan.md' -Authority cursor -RepoPath $null
                $r.outcome | Should -Be 'created'
                $doc = Read-MetraPlanIndex -PlansDir $plansDir
                $doc.schemaVersion | Should -Be 1
                $doc.plans.Count | Should -Be 1
                $doc.plans[0].authority | Should -Be 'cursor'
                $doc.plans[0].stem | Should -Be 'demo-plan'

                Set-MetraPlanIndexEntry -PlansDir $plansDir -Project 'Metra' `
                    -Stem 'scar-plan' -CursorLeaf $null -Authority repo -RepoPath 'scar-plan.plan.md' | Out-Null
                'scar content' | Set-Content -LiteralPath (Join-Path $plansDir 'scar-plan.plan.md') -Encoding utf8

                $working = Resolve-MetraPlanWorkingPath -PlansDir $plansDir -Stem 'scar-plan' -CursorPlansDir $cursorDir
                $working.status | Should -Be 'Missing'
                $working.note | Should -Be 'repo-only-scar'
                $path = Resolve-MetraPlanPath -PlansDir $plansDir -Stem 'scar-plan' -CursorPlansDir $cursorDir
                $path.status | Should -Be 'Resolved'
                $path.authority | Should -Be 'repo'

                Set-MetraPlanIndexEntry -PlansDir $plansDir -Project 'Metra' `
                    -Stem 'scar-plan' -CursorLeaf 'scar_plan_ffffffff.plan.md' -Authority repo -RepoPath 'scar-plan.plan.md' | Out-Null
                $doc = Read-MetraPlanIndex -PlansDir $plansDir
                $e = @($doc.plans) | Where-Object { $_.stem -eq 'scar-plan' } | Select-Object -First 1
                $e.authority | Should -Be 'repo'
                $e.cursorLeaf | Should -Be 'scar_plan_ffffffff.plan.md'

                {
                    Set-MetraPlanIndexEntry -PlansDir $plansDir -Project 'Metra' `
                        -Stem 'bad' -CursorLeaf '..\evil.plan.md' -Authority cursor
                } | Should -Throw

                $src = Join-Path $cursorDir 'shim_plan_aabbccdd.plan.md'
                "---`nname: shim`n---`n" | Set-Content -LiteralPath $src -Encoding utf8
                $before = @(Get-ChildItem -LiteralPath $plansDir -Filter '*.plan.md' -File).Count
                $out = Copy-YarnFormalPlanToProjectPlans -SourcePath $src -ProjectKey 'Metra' -MetraRoot $temp
                $out | Should -Be ([System.IO.Path]::GetFullPath($src))
                @(Get-ChildItem -LiteralPath $plansDir -Filter '*.plan.md' -File).Count | Should -Be $before
                $doc2 = Read-MetraPlanIndex -PlansDir $plansDir
                $shim = @($doc2.plans) | Where-Object { $_.stem -eq 'shim-plan' } | Select-Object -First 1
                $shim.authority | Should -Be 'cursor'
                $shim.cursorLeaf | Should -Be 'shim_plan_aabbccdd.plan.md'

                # AmbiguousSelected: newest leaf is persisted so later reads use exact-leaf.
                $older = Join-Path $cursorDir 'ambi_plan_11111111.plan.md'
                $newer = Join-Path $cursorDir 'ambi_plan_22222222.plan.md'
                "---`nname: old`n---`n" | Set-Content -LiteralPath $older -Encoding utf8
                Start-Sleep -Milliseconds 20
                "---`nname: new`n---`n" | Set-Content -LiteralPath $newer -Encoding utf8
                Set-MetraPlanIndexEntry -PlansDir $plansDir -Project 'Metra' `
                    -Stem 'ambi-plan' -CursorLeaf $null -Authority cursor -RepoPath $null | Out-Null
                $w = Resolve-MetraPlanWorkingPath -PlansDir $plansDir -Stem 'ambi-plan' -CursorPlansDir $cursorDir
                $w.status | Should -Be 'AmbiguousSelected'
                $w.leaf | Should -Be 'ambi_plan_22222222.plan.md'
                $doc3 = Read-MetraPlanIndex -PlansDir $plansDir
                $ambi = @($doc3.plans) | Where-Object { $_.stem -eq 'ambi-plan' } | Select-Object -First 1
                $ambi.cursorLeaf | Should -Be 'ambi_plan_22222222.plan.md'
                $w2 = Resolve-MetraPlanWorkingPath -PlansDir $plansDir -Stem 'ambi-plan' -CursorPlansDir $cursorDir
                $w2.status | Should -Be 'Resolved'
                $w2.leaf | Should -Be 'ambi_plan_22222222.plan.md'
            }
            finally {
                $script:YarnCursorPlansDirOverride = $null
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
