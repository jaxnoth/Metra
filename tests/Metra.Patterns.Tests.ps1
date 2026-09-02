# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Patterns.Tests.ps1"

BeforeAll {
    $script:MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    . (Join-Path $script:MetraRoot 'scripts\private\Patterns.ps1')
}

Describe 'Pattern path containment' {
    It 'rejects absolute and escape paths from index' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-pat-' + [guid]::NewGuid().ToString('n'))
        try {
            $pat = Join-Path $root 'docs\patterns'
            [void][System.IO.Directory]::CreateDirectory($pat)
            $escapeRel = '..\..\..\Windows\System32\drivers\etc\hosts'
            @(
                'escape-pat: ' + $escapeRel
                'abs-pat: C:\Temp\evil.md'
            ) | Set-Content -LiteralPath (Join-Path $pat 'index.yaml') -Encoding utf8

            $r1 = Resolve-MetraPatternPath -MetraRoot $root -PatternId 'escape-pat'
            $r1.ok | Should -BeFalse
            $r1.errors | Should -Contain 'path-escapes-patterns-root'

            $r2 = Resolve-MetraPatternPath -MetraRoot $root -PatternId 'abs-pat'
            $r2.ok | Should -BeFalse
            $r2.errors | Should -Contain 'absolute-path-in-index'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects patternId that looks like a path' {
        $r = Resolve-MetraPatternPath -MetraRoot $script:MetraRoot -PatternId '../loom/review.md'
        $r.ok | Should -BeFalse
        $r.errors | Should -Contain 'patternId-must-not-be-path'
    }

    It 'resolves real loom-review within docs/patterns' {
        $r = Resolve-MetraPatternPath -MetraRoot $script:MetraRoot -PatternId 'loom-review'
        $r.ok | Should -BeTrue
        Test-MetraPatternPathWithinPatternsRoot -Path $r.path -MetraRoot $script:MetraRoot | Should -BeTrue
    }
}

Describe 'Pattern front matter validation' {
    It 'rejects unknown owner and legacy product field' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-pat-' + [guid]::NewGuid().ToString('n'))
        try {
            $dir = Join-Path $root 'docs\patterns\loom'
            [void][System.IO.Directory]::CreateDirectory($dir)
            'bad: loom/bad.md' | Set-Content -LiteralPath (Join-Path $root 'docs\patterns\index.yaml') -Encoding utf8
            $body = @"
---
patternSchemaVersion: 1
defaultContext: false
patternId: bad
owner: not-a-product
product: loom
cabinet: guild
status: stub
implemented: false
---
# Bad
"@
            [System.IO.File]::WriteAllText((Join-Path $dir 'bad.md'), $body, [System.Text.UTF8Encoding]::new($false))
            $p = Read-MetraPatternFile -MetraRoot $root -PatternId 'bad'
            $p.ok | Should -BeFalse
            $p.errors | Should -Contain 'unknown-owner'
            $p.errors | Should -Contain 'legacy-field-product'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails package on duplicate patternId in index' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-pat-' + [guid]::NewGuid().ToString('n'))
        try {
            $dir = Join-Path $root 'docs\patterns\loom'
            [void][System.IO.Directory]::CreateDirectory($dir)
            @(
                'dup: loom/a.md'
                'DUP: loom/b.md'
            ) | Set-Content -LiteralPath (Join-Path $root 'docs\patterns\index.yaml') -Encoding utf8
            $pkg = Get-MetraPatternsForPackage -MetraRoot $root -PatternIds @('dup')
            $pkg.ok | Should -BeFalse
            $pkg.errors | Should -Contain 'duplicate-patternId-in-index'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'warns and continues on missing cite' {
        $pkg = Get-MetraPatternsForPackage -MetraRoot $script:MetraRoot -PatternIds @('does-not-exist-xyz')
        $pkg.ok | Should -BeTrue
        $pkg.patterns.Count | Should -Be 0
        ($pkg.warnings -join ' ') | Should -Match 'pattern-unresolved'
    }
}

Describe 'Yarn deterministic matcher' {
    It 'prefers loadWhen over owner fill and treats cabinet uniformly' {
        $hits = @(Find-MetraPatternsMatching -MetraRoot $script:MetraRoot -Owner 'loom' -MatchText 'please run loom review now' -MaxCount 8)
        $hits.Count | Should -BeGreaterThan 0
        $hits[0].patternId | Should -Be 'loom-review'
        $hits[0].reason | Should -Match 'loadWhen'

        $guild = @(Find-MetraPatternsMatching -MetraRoot $script:MetraRoot -Cabinet 'guild' -MaxCount 8)
        $guild.Count | Should -BeGreaterOrEqual 2
        @($guild | Where-Object { $_.cabinet -eq 'guild' }).Count | Should -Be $guild.Count
    }

    It 'parses patterns list from plan front matter' {
        $text = @"
---
name: x
patterns:
  - loom-review
  - guild-agent-interaction
---
body
"@
        $ids = @(Get-MetraPlanPatternIds -PlanText $text)
        $ids | Should -Contain 'loom-review'
        $ids | Should -Contain 'guild-agent-interaction'
    }
}

Describe 'Required catalog gaps' {
    It 'reports gap for missing required id without inventing a body' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-pat-' + [guid]::NewGuid().ToString('n'))
        try {
            $pat = Join-Path $root 'docs\patterns'
            [void][System.IO.Directory]::CreateDirectory($pat)
            '{}' | Set-Content -LiteralPath (Join-Path $pat 'index.yaml') -Encoding utf8
            @"
loom:
  - loom-review
"@ | Set-Content -LiteralPath (Join-Path $pat 'required.yaml') -Encoding utf8
            $gaps = @(Get-MetraPatternGaps -MetraRoot $root -Owner 'loom')
            $gaps.Count | Should -Be 1
            $gaps[0].suggestedPatternId | Should -Be 'loom-review'
            $gaps[0].status | Should -Be 'candidate'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
