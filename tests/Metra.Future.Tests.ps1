# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Future.Tests.ps1"

BeforeAll {
    $script:MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:MetraRoot 'scripts\Metra.psd1') -Force
    $script:FutureStore = Join-Path $script:MetraRoot 'docs\future.local.yaml'
    $script:YamlHashAtStart = (Get-FileHash -LiteralPath $script:FutureStore -Algorithm SHA256).Hash
}

AfterAll {
    $yamlHashAtEnd = (Get-FileHash -LiteralPath $script:FutureStore -Algorithm SHA256).Hash
    if ($yamlHashAtEnd -ne $script:YamlHashAtStart) {
        throw 'docs/future.local.yaml changed during the Future test suite.'
    }
}

Describe 'Future portfolio store' {
    It 'holds 54 items and the two programs' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore } {
            param($Store)
            $fromYaml = ConvertFrom-MetraFutureYaml -Path $Store
            @($fromYaml.Items).Count | Should -Be 54
            @($fromYaml.Programs).Count | Should -Be 2
            $ios = @($fromYaml.Programs | Where-Object { $_.Id -eq 'ios-companion' })[0]
            $sprint = @($fromYaml.Programs | Where-Object { $_.Id -eq 'coworker-ticket-analysis' })[0]
            $ios.Status | Should -Be 'active'
            $sprint.Status | Should -Be 'expired'
            @($ios.Children) | Should -Be @('ios-bounded-face', 'human-ios-voice', 'ios-presence-voice-children', 'ios-ani-bridge-retire')
            @($sprint.Children) | Should -Be @('sprint-s2b', 'sprint-s1b', 'sprint-dry-runs', 'sprint-s7')
            foreach ($child in @($ios.Children + $sprint.Children)) {
                $item = @($fromYaml.Items | Where-Object { $_.Id -eq $child })[0]
                $item | Should -Not -BeNullOrEmpty
                if ($ios.Children -contains $child) {
                    $item.Program | Should -Be 'ios-companion'
                }
                else {
                    $item.Program | Should -Be 'coworker-ticket-analysis'
                }
            }
        }
    }

    It 'validates the seeded portfolio' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore } {
            param($Store)
            $portfolio = ConvertFrom-MetraFutureYaml -Path $Store
            $result = Test-MetraFutureModel -Portfolio $portfolio
            $result.Errors.Count | Should -Be 0
            @($portfolio.Items | Where-Object { $_.Status -eq 'now' }).Count | Should -Be 2
        }
    }

    It 'fails a duplicate id, a fourth now, a bad status, a missing child, and an unresolved plan ref' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore } {
            param($Store)
            function Copy-Portfolio {
                $fresh = ConvertFrom-MetraFutureYaml -Path $Store
                return $fresh
            }

            $dup = Copy-Portfolio
            $dup.Items[4].Id = $dup.Items[5].Id
            (Test-MetraFutureModel -Portfolio $dup).Errors -join "`n" | Should -Match 'DUPLICATE_ID'

            $now = Copy-Portfolio
            $added = 0
            foreach ($item in $now.Items) {
                if ($item.Status -ne 'now' -and $added -lt 2) {
                    $item.Status = 'now'
                    $added++
                }
            }
            (Test-MetraFutureModel -Portfolio $now).Errors -join "`n" | Should -Match 'NOW_LIMIT'

            $badItem = Copy-Portfolio
            $badItem.Items[0].Status = 'banana'
            (Test-MetraFutureModel -Portfolio $badItem).Errors -join "`n" | Should -Match 'BAD_ITEM_STATUS'

            $badProgram = Copy-Portfolio
            $badProgram.Programs[0].Status = 'now'
            (Test-MetraFutureModel -Portfolio $badProgram).Errors -join "`n" | Should -Match 'BAD_PROGRAM_STATUS'

            $missing = Copy-Portfolio
            [void]$missing.Programs[0].Children.Add('not-a-card')
            (Test-MetraFutureModel -Portfolio $missing).Errors -join "`n" | Should -Match 'MISSING_PROGRAM_CHILD'

            $two = Copy-Portfolio
            [void]$two.Programs[1].Children.Add('ios-bounded-face')
            (Test-MetraFutureModel -Portfolio $two).Errors -join "`n" | Should -Match 'MULTI_PROGRAM'

            $unresolved = Copy-Portfolio
            [void]$unresolved.Items[0].Plans.Add(@{ Ref = 'not-a-real-plan'; Role = 'related'; Source = 'repo' })
            (Test-MetraFutureModel -Portfolio $unresolved).Errors -join "`n" | Should -Match 'UNRESOLVED_PLAN_REF'

            $explicit = Copy-Portfolio
            [void]$explicit.Items[0].Plans.Add(@{ Ref = 'not-a-real-plan'; Role = 'related'; Source = 'missing' })
            (Test-MetraFutureModel -Portfolio $explicit).Errors.Count | Should -Be 0
        }
    }

    It 'reconciles with warnings, including the known stale and duplicate cases, and writes nothing' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore; Root = $script:MetraRoot } {
            param($Store, $Root)
            $beforeStore = (Get-FileHash -LiteralPath $Store -Algorithm SHA256).Hash
            $plan = Join-Path $Root 'plans\ios-conversation-policy.plan.md'
            $beforePlan = (Get-FileHash -LiteralPath $plan -Algorithm SHA256).Hash
            $portfolio = ConvertFrom-MetraFutureYaml -Path $Store
            $gate = Test-MetraFutureModel -Portfolio $portfolio
            $gate.Errors.Count | Should -Be 0
            $warnings = @(Get-MetraFutureReconcileWarnings -Portfolio $portfolio)
            $text = ($warnings | ForEach-Object { $_.Code + ' ' + $_.Message }) -join "`n"
            $text | Should -Match 'FUTURE_PLAN_COMPLETED ios-conversation-policy'
            $text | Should -Match 'DUPLICATE_WORK_RELATIONSHIP human-procedure-skills and agent-a4-skills'
            $text | Should -Match 'DUPLICATE_WORK_RELATIONSHIP agent-a1-prove and sprint-s7'
            $text | Should -Match 'PLAN_WITHOUT_DISPOSITION'
            $text | Should -Match 'FUTURE_PLAN_MISSING'
            (Get-FileHash -LiteralPath $Store -Algorithm SHA256).Hash | Should -Be $beforeStore
            (Get-FileHash -LiteralPath $plan -Algorithm SHA256).Hash | Should -Be $beforePlan
        }
    }

    It 'round-trips the emitted YAML subset and rejects newlines' {
        InModuleScope Metra {
            $samples = @(
                'Bing plan for allowlisted runners',
                "don't stop",
                'say "hi"',
                'C:\Projects\_meta\docs',
                'Status: now',
                '# not a comment',
                "caf$([char]0x00E9) $([char]0x03BB)",
                '',
                'a\b'
            )
            foreach ($sample in $samples) {
                $portfolio = @{
                    SchemaVersion = 1
                    Programs      = @()
                    Items         = @(
                        @{
                            Id       = 'round-trip'
                            Title    = $sample
                            Summary  = $sample
                            Status   = 'parked'
                            Audience = 'human'
                            Product  = 'Metra'
                            Tags     = @()
                            Program  = ''
                            Next     = $sample
                            Verify   = $sample
                            HardOffs = ''
                            Plans    = @()
                        }
                    )
                }
                $temp = Join-Path ([IO.Path]::GetTempPath()) ("metra-future-rt-" + [guid]::NewGuid().ToString('n') + '.yaml')
                try {
                    Export-MetraFuturePortfolioYaml -Portfolio $portfolio -Path $temp
                    $read = ConvertFrom-MetraFutureYaml -Path $temp
                    $item = $read.Items[0]
                    $item.Title | Should -Be $sample
                    $item.Summary | Should -Be $sample
                    $item.Next | Should -Be $sample
                    $item.Verify | Should -Be $sample
                }
                finally {
                    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
                }
            }
            { ConvertTo-MetraFutureYamlScalar "line`nbreak" } | Should -Throw
        }
    }

    It 'refuses reconcile when validate fails' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore } {
            param($Store)
            $portfolio = ConvertFrom-MetraFutureYaml -Path $Store
            $portfolio.Items[0].Status = 'banana'
            $temp = Join-Path ([IO.Path]::GetTempPath()) ("metra-future-" + [guid]::NewGuid().ToString('n') + '.yaml')
            try {
                Export-MetraFuturePortfolioYaml -Portfolio $portfolio -Path $temp
                $failed = $false
                $output = ''
                try {
                    $output = Invoke-MetraFutureCommand -Subcommand reconcile -Path $temp 2>&1 | Out-String
                }
                catch {
                    $failed = $true
                    $output = $_.Exception.Message
                }
                $failed | Should -BeTrue
                $output | Should -Match 'validate failed'
                $output | Should -Not -Match 'PLAN_WITHOUT_DISPOSITION'
            }
            finally {
                if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
            }
        }
    }

    It 'stores a summary on every item and does not store Home' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore } {
            param($Store)
            $yaml = ConvertFrom-MetraFutureYaml -Path $Store
            @($yaml.Items).Count | Should -Be 54
            foreach ($item in @($yaml.Items)) {
                $item.Summary | Should -Not -BeNullOrEmpty
            }
            $raw = [IO.File]::ReadAllText($Store)
            $raw | Should -Not -Match '(?m)^    home:'
        }
    }

    It 'renders projections once, then a second render and -Check are byte-identical' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore; Root = $script:MetraRoot } {
            param($Store, $Root)
            $parked = Join-Path $Root 'docs\Future-Parked.local.md'
            $index = Join-Path $Root 'docs\Future-Development.local.md'
            $canvas = Get-MetraFutureCanvasPath
            $yamlBefore = (Get-FileHash -LiteralPath $Store -Algorithm SHA256).Hash
            Invoke-MetraFutureCommand -Subcommand render -Path $Store
            $after = @{
                Parked = (Get-FileHash -LiteralPath $parked -Algorithm SHA256).Hash
                Index  = (Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash
                Canvas = (Get-FileHash -LiteralPath $canvas -Algorithm SHA256).Hash
            }
            (Get-FileHash -LiteralPath $Store -Algorithm SHA256).Hash | Should -Be $yamlBefore
            Invoke-MetraFutureCommand -Subcommand render -Path $Store
            (Get-FileHash -LiteralPath $parked -Algorithm SHA256).Hash | Should -Be $after.Parked
            (Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash | Should -Be $after.Index
            (Get-FileHash -LiteralPath $canvas -Algorithm SHA256).Hash | Should -Be $after.Canvas
            Invoke-MetraFutureCommand -Subcommand render -Path $Store -Check
            (Get-FileHash -LiteralPath $parked -Algorithm SHA256).Hash | Should -Be $after.Parked
            (Get-FileHash -LiteralPath $Store -Algorithm SHA256).Hash | Should -Be $yamlBefore

            $parkedText = [IO.File]::ReadAllText($parked)
            $indexText = [IO.File]::ReadAllText($index)
            $canvasText = [IO.File]::ReadAllText($canvas)
            $parkedText | Should -Not -Match '(?m)^\| Home \|'
            $parkedText | Should -Not -Match '(?m)^## Human ladder'
            $parkedText | Should -Not -Match '(?m)^## Agent lane'
            $parkedText | Should -Not -Match '(?m)^## Buckets / cold'
            $parkedText | Should -Not -Match '(?m)^## Explicitly last'
            $parkedText | Should -Match 'docs/future.local.yaml'
            $indexText | Should -Match 'ops-ask-live-tools'
            $indexText | Should -Match 'ios-bounded-face'
            $indexText | Should -Not -Match "What's left"
            $indexText | Should -Match 'future render'
            $start = $canvasText.IndexOf('// metra-future-data:start')
            $end = $canvasText.IndexOf('// metra-future-data:end')
            $start | Should -BeGreaterThan 0
            $end | Should -BeGreaterThan $start
            $outside = $canvasText.Substring(0, $start) + $canvasText.Substring($end + '// metra-future-data:end'.Length)
            $outside | Should -Not -Match 'const HUMAN'
            $outside | Should -Not -Match 'const AGENT'
            $outside | Should -Not -Match 'const CONSUMER'
            $outside | Should -Not -Match 'const CURSOR_ADJ'
            $outside | Should -Not -Match 'const SURVEYOR_OPEN'
            $outside | Should -Not -Match 'const FUTURE_MODEL'
            $outside | Should -Match 'FUTURE_MODEL.items'
        }
    }

    It 'projects reconcile warnings into Focus, Map, and Reconcile without a new ledger' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore; Root = $script:MetraRoot } {
            param($Store, $Root)
            $parked = Join-Path $Root 'docs\Future-Parked.local.md'
            $index = Join-Path $Root 'docs\Future-Development.local.md'
            $canvas = Get-MetraFutureCanvasPath
            $schema = Join-Path $Root 'docs\future\future-item.schema.json'
            Invoke-MetraFutureCommand -Subcommand render -Path $Store
            $before = (Get-FileHash -LiteralPath $canvas -Algorithm SHA256).Hash
            Invoke-MetraFutureCommand -Subcommand render -Path $Store
            (Get-FileHash -LiteralPath $canvas -Algorithm SHA256).Hash | Should -Be $before

            $portfolio = ConvertFrom-MetraFutureYaml -Path $Store
            $warnings = @(Get-MetraFutureReconcileWarnings -Portfolio $portfolio -MetraRoot $Root)
            $canvasText = [IO.File]::ReadAllText($canvas)
            $start = $canvasText.IndexOf('// metra-future-data:start')
            $end = $canvasText.IndexOf('// metra-future-data:end')
            $region = $canvasText.Substring($start, $end - $start)
            $found = @([regex]::Matches($region, '"code": "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
            $expected = @($warnings | ForEach-Object { $_.Code })
            $found.Count | Should -Be $expected.Count
            for ($i = 0; $i -lt $expected.Count; $i++) {
                $found[$i] | Should -Be $expected[$i]
            }
            $pos = $region.IndexOf('"warnings"')
            foreach ($warning in $warnings) {
                $needle = Format-MetraFutureJsString $warning.Message
                $at = $region.IndexOf($needle, $pos)
                $at | Should -BeGreaterThan $pos
                $pos = $at + $needle.Length
            }
            $region | Should -Not -Match 'subjectId'
            $region | Should -Not -Match 'subjectType'
            $schemaText = [IO.File]::ReadAllText($schema)
            $schemaText | Should -Not -Match 'subjectId'
            $schemaText | Should -Not -Match 'subjectType'
            [IO.File]::ReadAllText($parked) | Should -Not -Match 'PLAN_WITHOUT_DISPOSITION'
            [IO.File]::ReadAllText($index) | Should -Not -Match 'PLAN_WITHOUT_DISPOSITION'
            [IO.File]::ReadAllText($index) | Should -Not -Match "What's left"

            $now = @($portfolio.Items | Where-Object { $_.Status -eq 'now' } | ForEach-Object { $_.Id } | Sort-Object)
            @($now) | Should -Be @('ios-bounded-face', 'ops-ask-live-tools')
            $focusIds = @($portfolio.Items | Where-Object { $_.Status -in @('now', 'next') } | ForEach-Object { $_.Id })
            $parkedItem = @($portfolio.Items | Where-Object { $_.Status -eq 'parked' })[0]
            $focusIds | Should -Not -Contain $parkedItem.Id
            $fake = $parkedItem.Id + ' has no structured plan link.'
            $named = $false
            foreach ($id in $focusIds) {
                $pattern = '(?:^|[^A-Za-z0-9_-])' + [regex]::Escape($id) + '(?=$|[^A-Za-z0-9_-])'
                if ($fake -match $pattern) { $named = $true }
            }
            $named | Should -BeFalse
            $selfPattern = '(?:^|[^A-Za-z0-9_-])' + [regex]::Escape($parkedItem.Id) + '(?=$|[^A-Za-z0-9_-])'
            ($fake -match $selfPattern) | Should -BeTrue
            @($warnings | Where-Object { $_.Code -eq 'PLAN_WITHOUT_DISPOSITION' }).Count | Should -BeGreaterThan 0

            $canvasText | Should -Match 'Nothing in Now or Next\.'
            $canvasText | Should -Match 'No Future items match these filters\.'
            $canvasText | Should -Match 'No reconciliation findings\.'
            $canvasText | Should -Match "audience === 'human'"
            $canvasText | Should -Match 'item\.product'
            $canvasText | Should -Match 'item\.tags'
            $canvasText | Should -Not -Match 'const HUMAN'
            $canvasText | Should -Not -Match 'const AGENT'
            $canvasText | Should -Not -Match 'const CONSUMER'
            $canvasText | Should -Not -Match 'const CURSOR_ADJ'
            $canvasText | Should -Not -Match 'const SURVEYOR_OPEN'
            $canvasText | Should -Not -Match 'statusRowTone'
            $canvasText | Should -Not -Match 'type Status'
            $canvasText | Should -Not -Match 'type Lane'
            $canvasText | Should -Not -Match 'type Bite'
        }
    }

    It 'reports render drift when a projection file is missing' {
        InModuleScope Metra {
            $missing = Join-Path ([IO.Path]::GetTempPath()) ("metra-future-missing-" + [guid]::NewGuid().ToString('n') + '.md')
            if (Test-Path -LiteralPath $missing) { Remove-Item -LiteralPath $missing -Force }
            $err = ''
            try { Test-MetraFutureProjectionMatch -Path $missing -Text 'projection body' }
            catch { $err = $_.Exception.Message }
            $err | Should -Match 'future render drift'
            $err | Should -Not -Match 'Cannot find path'
        }
    }

    It 'treats an unrendered title edit as drift and refuses an invalid model before writing' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore; Root = $script:MetraRoot } {
            param($Store, $Root)
            $parked = Join-Path $Root 'docs\Future-Parked.local.md'
            $index = Join-Path $Root 'docs\Future-Development.local.md'
            $canvas = Get-MetraFutureCanvasPath
            $before = @{
                Parked = (Get-FileHash -LiteralPath $parked -Algorithm SHA256).Hash
                Index  = (Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash
                Canvas = (Get-FileHash -LiteralPath $canvas -Algorithm SHA256).Hash
            }
            $portfolio = ConvertFrom-MetraFutureYaml -Path $Store
            $portfolio.Items[0].Title = 'planted title mismatch'
            $temp = Join-Path ([IO.Path]::GetTempPath()) ("metra-future-render-" + [guid]::NewGuid().ToString('n') + '.yaml')
            $bad = Join-Path ([IO.Path]::GetTempPath()) ("metra-future-render-bad-" + [guid]::NewGuid().ToString('n') + '.yaml')
            try {
                Export-MetraFuturePortfolioYaml -Portfolio $portfolio -Path $temp
                $drifted = $false
                $driftText = ''
                try { Invoke-MetraFutureCommand -Subcommand render -Path $temp -Check }
                catch { $drifted = $true; $driftText = $_.Exception.Message }
                $drifted | Should -BeTrue
                $driftText | Should -Match 'drift'

                $broken = ConvertFrom-MetraFutureYaml -Path $Store
                $broken.Items[0].Status = 'banana'
                Export-MetraFuturePortfolioYaml -Portfolio $broken -Path $bad
                foreach ($useCheck in @($true, $false)) {
                    $failed = $false
                    $output = ''
                    try { Invoke-MetraFutureCommand -Subcommand render -Path $bad -Check:$useCheck }
                    catch { $failed = $true; $output = $_.Exception.Message }
                    $failed | Should -BeTrue
                    $output | Should -Match 'validate failed'
                }
            }
            finally {
                if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
                if (Test-Path -LiteralPath $bad) { Remove-Item -LiteralPath $bad -Force }
            }
            (Get-FileHash -LiteralPath $parked -Algorithm SHA256).Hash | Should -Be $before.Parked
            (Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash | Should -Be $before.Index
            (Get-FileHash -LiteralPath $canvas -Algorithm SHA256).Hash | Should -Be $before.Canvas
        }
    }

    It 'rejects a bad marker pair and a failed later commit without writing targets' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore; Root = $script:MetraRoot } {
            param($Store, $Root)
            $live = @(
                (Join-Path $Root 'docs\Future-Parked.local.md'),
                (Join-Path $Root 'docs\Future-Development.local.md'),
                (Get-MetraFutureCanvasPath)
            )
            $before = @{}
            foreach ($path in $live) { $before[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
            $portfolio = ConvertFrom-MetraFutureYaml -Path $Store
            $dir = Join-Path ([IO.Path]::GetTempPath()) ("metra-future-markers-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            $cases = @(
                "// metra-future-data:start`nconst A = 1`n// metra-future-data:end`n// metra-future-data:start`nconst B = 2`n// metra-future-data:end`n",
                "import { Text } from 'cursor/canvas';`n// metra-future-data:start`ntype Status = 'Parked'`n",
                "import { Text } from 'cursor/canvas';`n// metra-future-data:end`ntype Status = 'Parked'`n",
                "import { Text } from 'cursor/canvas';`n// metra-future-data:end`n// metra-future-data:start`ntype Status = 'Parked'`n"
            )
            try {
                foreach ($body in $cases) {
                    $canvas = Join-Path $dir 'bad.canvas.tsx'
                    [IO.File]::WriteAllText($canvas, $body)
                    $failed = $false
                    try {
                        New-MetraFutureProjectionBundle -Portfolio $portfolio -MetraRoot $Root -CanvasPath $canvas | Out-Null
                    }
                    catch { $failed = $true }
                    $failed | Should -BeTrue
                }
                $one = Join-Path $dir 'one.txt'
                $two = Join-Path $dir 'two.txt'
                $three = Join-Path $dir 'three.txt'
                [IO.File]::WriteAllText($one, 'one')
                [IO.File]::WriteAllText($two, 'two')
                [IO.File]::WriteAllText($three, 'three')
                $outputs = New-Object System.Collections.ArrayList
                [void]$outputs.Add(@{ Path = $one; Text = 'ONE' })
                [void]$outputs.Add(@{ Path = $two; Text = 'TWO' })
                [void]$outputs.Add(@{ Path = $three; Text = 'THREE' })
                $failedCommit = $false
                try {
                    Publish-MetraFutureOutputs -Outputs $outputs -BeforeEach {
                        param($index, $path)
                        if ($index -eq 1) { throw 'commit failed' }
                    }
                }
                catch { $failedCommit = $true }
                $failedCommit | Should -BeTrue
                [IO.File]::ReadAllText($one) | Should -Be 'one'
                [IO.File]::ReadAllText($two) | Should -Be 'two'
                [IO.File]::ReadAllText($three) | Should -Be 'three'
            }
            finally {
                if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
            }
            foreach ($path in $live) {
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $before[$path]
            }
        }
    }

    It 'does not write projections when render is WhatIf' {
        InModuleScope Metra -Parameters @{ Store = $script:FutureStore; Root = $script:MetraRoot } {
            param($Store, $Root)
            $parked = Join-Path $Root 'docs\Future-Parked.local.md'
            $before = (Get-FileHash -LiteralPath $parked -Algorithm SHA256).Hash
            Invoke-MetraFutureCommand -Subcommand render -Path $Store -WhatIf
            (Get-FileHash -LiteralPath $parked -Algorithm SHA256).Hash | Should -Be $before
        }
    }

    It 'does not keep the migration parsers or read Parked back into the model' {
        $sourcePath = Join-Path $script:MetraRoot 'scripts\private\Future.ps1'
        $source = [IO.File]::ReadAllText($sourcePath)
        $names = @(
            'Get-MetraFutureSectionTag',
            'Get-MetraFuturePlanLinksFromHome',
            'Get-MetraFuturePortfolioFromParked',
            'Get-MetraFutureMarkdownTables',
            'Get-MetraFutureParkedSurface',
            'Get-MetraFutureCanvasFutureCards',
            'Get-MetraFutureProjectionFindings',
            'Get-MetraFuturePlanKeySet',
            'Format-MetraFutureKeyList',
            'Add-MetraFutureFinding',
            'Get-MetraFutureGuardHashes',
            'Update-MetraFutureSummariesFromParked'
        )
        foreach ($name in $names) {
            $source.Contains($name) | Should -BeFalse
        }
        $source.Contains('SURVEYOR_OPEN') | Should -BeFalse
        $source.Contains('Prose Home cannot satisfy one.') | Should -BeTrue
        $source.Contains("ContainsKey('Home')") | Should -BeFalse
        $source.Contains("['Home']") | Should -BeFalse

        $defs = [regex]::Matches($source, '(?m)^function\s+\S+')
        $writesParked = $false
        for ($i = 0; $i -lt $defs.Count; $i++) {
            $start = $defs[$i].Index
            $end = if ($i + 1 -lt $defs.Count) { $defs[$i + 1].Index } else { $source.Length }
            $body = $source.Substring($start, $end - $start)
            if (-not $body.Contains('Future-Parked.local.md')) { continue }
            $writesParked = $true
            $body.Contains('ReadAllLines') | Should -BeFalse
            $body.Contains('ReadAllText') | Should -BeFalse
            $body.Contains('Get-Content') | Should -BeFalse
        }
        $writesParked | Should -BeTrue
    }
}
