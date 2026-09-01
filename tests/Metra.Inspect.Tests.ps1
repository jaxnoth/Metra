# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Inspect.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Inspect file classification' {
    It 'classifies PowerShell as code' {
        InModuleScope Metra {
            Get-MetraInspectFileClass -RelativePath 'scripts/private/Inspect.ps1' | Should -Be 'code'
        }
    }

    It 'skips lockfiles and credentials' {
        InModuleScope Metra {
            Get-MetraInspectFileClass -RelativePath 'package-lock.json' | Should -Be 'skip'
            Get-MetraInspectFileClass -RelativePath 'credentials/config.json' | Should -Be 'skip'
        }
    }

    It 'skips root env dotfiles without stripping the leading dot' {
        InModuleScope Metra {
            Get-MetraInspectFileClass -RelativePath '.env' | Should -Be 'skip'
            Get-MetraInspectFileClass -RelativePath './.env' | Should -Be 'skip'
            Get-MetraInspectFileClass -RelativePath '.env.local' | Should -Be 'skip'
            Get-MetraInspectFileClass -RelativePath './.env.production' | Should -Be 'skip'
        }
    }

    It 'does not classify harmless root dotfiles as env secrets' {
        InModuleScope Metra {
            Get-MetraInspectFileClass -RelativePath '.gitignore' | Should -Be 'config'
            Get-MetraInspectFileClass -RelativePath './.editorconfig' | Should -Be 'config'
        }
    }

    It 'classifies markdown as docs' {
        InModuleScope Metra {
            Get-MetraInspectFileClass -RelativePath 'AGENTS.md' | Should -Be 'docs'
        }
    }
}

Describe 'Inspect scope reducer' {
    It 'prefers code over docs and skips lockfiles' {
        InModuleScope Metra {
            $files = @(
                [PSCustomObject]@{ path = 'package-lock.json'; content = 'x' }
                [PSCustomObject]@{ path = 'README.md'; content = 'docs' }
                [PSCustomObject]@{ path = 'src/App.ps1'; content = 'code here' }
            )
            $r = Reduce-MetraInspectDiffFiles -Files $files
            $r.SkippedFileCount | Should -Be 1
            ($r.Files | Where-Object { $_.path -eq 'src/App.ps1' }).Count | Should -Be 1
            ($r.Files | Where-Object { $_.class -eq 'docs' }).Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'Inspect findings JSON parse' {
    It 'parses a findings array' {
        InModuleScope Metra {
            $msg = '[{"severity":"High","confidence":"Low","category":"Security","file":"a.ps1","line":1,"finding":"x","recommendation":"y","evidence":"z"}]'
            $p = ConvertTo-MetraInspectFindings -Message $msg
            $p.Ok | Should -BeTrue
            $p.Findings.Count | Should -Be 1
            $p.Findings[0].severity | Should -Be 'High'
            $p.Findings[0].confidence | Should -Be 'Low'
        }
    }

    It 'parses fenced JSON wrapper object' {
        InModuleScope Metra {
            $msg = @'
```json
{"findings":[]}
```
'@
            $p = ConvertTo-MetraInspectFindings -Message $msg
            $p.Ok | Should -BeTrue
            $p.Findings.Count | Should -Be 0
        }
    }

    It 'fails closed on non-JSON' {
        InModuleScope Metra {
            $p = ConvertTo-MetraInspectFindings -Message 'not json at all'
            $p.Ok | Should -BeFalse
            $p.Excerpt | Should -Not -BeNullOrEmpty
        }
    }

    It 'non-integer line becomes null while Ok' {
        InModuleScope Metra {
            $msg = '[{"severity":"High","confidence":"Low","category":"Security","file":"a.ps1","line":"abc","finding":"x","recommendation":"y","evidence":"z"}]'
            $p = ConvertTo-MetraInspectFindings -Message $msg
            $p.Ok | Should -BeTrue
            $p.Findings.Count | Should -Be 1
            $p.Findings[0].line | Should -BeNullOrEmpty
        }
    }

    It 'clamps invalid severity confidence and category enums' {
        InModuleScope Metra {
            $msg = '[{"severity":"bogus","confidence":"Maybe","category":"Unknown","file":"a.ps1","line":null,"finding":"x","recommendation":"","evidence":""}]'
            $p = ConvertTo-MetraInspectFindings -Message $msg
            $p.Ok | Should -BeTrue
            $p.Findings[0].severity | Should -Be 'Info'
            $p.Findings[0].confidence | Should -Be 'Medium'
            $p.Findings[0].category | Should -Be 'Standards'
        }
    }

    It 'preserves Critical severity in findings JSON' {
        InModuleScope Metra {
            $msg = '[{"severity":"Critical","confidence":"Maybe","category":"Unknown","file":"a.ps1","line":null,"finding":"x","recommendation":"","evidence":""}]'
            $p = ConvertTo-MetraInspectFindings -Message $msg
            $p.Ok | Should -BeTrue
            $p.Findings[0].severity | Should -Be 'Critical'
        }
    }

    It 'extracts JSON object from leading prose' {
        InModuleScope Metra {
            $msg = @'
Here is my review output:
{"findings":[{"severity":"Low","confidence":"Medium","category":"Standards","file":"a.ps1","line":1,"finding":"x","recommendation":"y","evidence":"z"}]}
'@
            $p = ConvertTo-MetraInspectFindings -Message $msg
            $p.Ok | Should -BeTrue
            $p.Findings.Count | Should -Be 1
        }
    }

    It 'extracts fenced json block not at message start' {
        InModuleScope Metra {
            $msg = @'
Review complete:
```json
{"findings":[]}
```
'@
            $p = ConvertTo-MetraInspectFindings -Message $msg
            $p.Ok | Should -BeTrue
            $p.Findings.Count | Should -Be 0
        }
    }

    It 'flags plan-summary JSON as wrong shape with actionable error' {
        InModuleScope Metra {
            $msg = '{"overview":"AzDO integration","implementation_steps":[{"step_name":"Config"}]}'
            $p = ConvertTo-MetraInspectFindings -Message $msg
            $p.Ok | Should -BeFalse
            $p.ShapeMismatch | Should -BeTrue
            $p.Error | Should -Match 'wrong JSON shape'
            $p.Error | Should -Match 'overview'
        }
    }

    It 'does not flag valid findings wrapper as wrong shape' {
        InModuleScope Metra {
            $msg = '{"findings":[{"severity":"Low","confidence":"Medium","category":"Scope","file":"plan.md","line":1,"finding":"x","recommendation":"y","evidence":"z"}]}'
            $p = ConvertTo-MetraInspectFindings -Message $msg
            $p.Ok | Should -BeTrue
            $p.ShapeMismatch | Should -BeFalse
            $p.Findings.Count | Should -Be 1
        }
    }
}

Describe 'Inspect engine parse retry' {
    It 'retries once when engine returns plan-summary JSON then findings' {
        InModuleScope Metra {
            $script:AskCount = 0
            Mock Invoke-MetraAskEngine {
                $script:AskCount++
                if ($script:AskCount -eq 1) {
                    return [PSCustomObject]@{
                        ok      = $true
                        message = '{"overview":"summary","implementation_steps":[]}'
                        engine  = 'ollama'
                        model   = 'qwen2.5:14b'
                    }
                }
                return [PSCustomObject]@{
                    ok      = $true
                    message = '{"findings":[]}'
                    engine  = 'ollama'
                    model   = 'qwen2.5:14b'
                }
            }
            $r = Invoke-MetraInspectEngine -Prompt 'review plan' -Cwd 'C:\Projects\_meta'
            $r.Ok | Should -BeTrue
            $r.RetryAttempt | Should -Be 1
            $r.Findings.Count | Should -Be 0
            $script:AskCount | Should -Be 2
        }
    }
}

Describe 'Inspect report wrapper' {
    It 'builds schemaVersion 1 report with provenance' {
        InModuleScope Metra {
            $prov = [ordered]@{
                engine         = 'ollama'
                model          = 'test'
                inspectedAtUtc = '2026-08-12T00:00:00Z'
                inputHash      = 'abc'
                contextLimited = $false
            }
            $report = New-MetraInspectReport -Mode diff -Provenance $prov -Findings @()
            $report.schemaVersion | Should -Be 1
            $report.mode | Should -Be 'diff'
            $report.provenance.engine | Should -Be 'ollama'
            $report.findings.Count | Should -Be 0
        }
    }
}

Describe 'Inspect plan path resolution' {
    It 'list-only when no selector' {
        InModuleScope Metra {
            $r = Resolve-MetraInspectPlanPath
            $r.ListOnly | Should -BeTrue
            $r.Ok | Should -BeFalse
        }
    }

    It 'fails closed when multiple selectors' {
        InModuleScope Metra {
            $r = Resolve-MetraInspectPlanPath -Latest -Fragment 'metra'
            $r.Ok | Should -BeFalse
            $r.Error | Should -Match 'Only one plan selector'
        }
    }

    It 'fails closed on missing -Path' {
        InModuleScope Metra {
            $r = Resolve-MetraInspectPlanPath -Path 'C:\definitely\missing\nope.plan.md'
            $r.Ok | Should -BeFalse
            $r.Error | Should -Match 'not found'
        }
    }

    It 'resolves unique fragment against fixture plans' {
        InModuleScope Metra {
            $temp = Join-Path $env:TEMP ("metra-inspect-plans-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $temp -Force | Out-Null
            try {
                $a = Join-Path $temp 'alpha-unique-xyz.plan.md'
                $b = Join-Path $temp 'beta-other.plan.md'
                Set-Content -LiteralPath $a -Value '# a' -Encoding utf8
                Set-Content -LiteralPath $b -Value '# b' -Encoding utf8
                Mock Get-MetraInspectPlanRoots { @($temp) }
                $r = Resolve-MetraInspectPlanPath -Fragment 'unique-xyz'
                $r.Ok | Should -BeTrue
                $r.Path | Should -Be ([System.IO.Path]::GetFullPath($a))
            }
            finally {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'fails closed on ambiguous fragment' {
        InModuleScope Metra {
            $temp = Join-Path $env:TEMP ("metra-inspect-plans-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $temp -Force | Out-Null
            try {
                Set-Content -LiteralPath (Join-Path $temp 'metra-one.plan.md') -Value '#1' -Encoding utf8
                Set-Content -LiteralPath (Join-Path $temp 'metra-two.plan.md') -Value '#2' -Encoding utf8
                Mock Get-MetraInspectPlanRoots { @($temp) }
                $r = Resolve-MetraInspectPlanPath -Fragment 'metra'
                $r.Ok | Should -BeFalse
                $r.Matches.Count | Should -Be 2
            }
            finally {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'fails closed when -Path is outside plan roots' {
        InModuleScope Metra {
            $outside = Join-Path $env:TEMP ("metra-inspect-outside-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            try {
                $file = Join-Path $outside 'outside.plan.md'
                Set-Content -LiteralPath $file -Value '# outside' -Encoding utf8
                Mock Get-MetraInspectPlanRoots { @((Join-Path $env:TEMP 'metra-inspect-no-such-root')) }
                $r = Resolve-MetraInspectPlanPath -Path $file
                $r.Ok | Should -BeFalse
                $r.Error | Should -Match 'known plan root'
            }
            finally {
                Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'resolves -Path under a mocked plan root' {
        InModuleScope Metra {
            $temp = Join-Path $env:TEMP ("metra-inspect-plans-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $temp -Force | Out-Null
            try {
                $file = Join-Path $temp 'under-root.plan.md'
                Set-Content -LiteralPath $file -Value '# ok' -Encoding utf8
                Mock Get-MetraInspectPlanRoots { @($temp) }
                $r = Resolve-MetraInspectPlanPath -Path $file
                $r.Ok | Should -BeTrue
                $r.Path | Should -Be ([System.IO.Path]::GetFullPath($file))
            }
            finally {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'fails closed when -Path is not *.plan.md' {
        InModuleScope Metra {
            $temp = Join-Path $env:TEMP ("metra-inspect-plans-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $temp -Force | Out-Null
            try {
                $file = Join-Path $temp 'notes.md'
                Set-Content -LiteralPath $file -Value '# not a plan' -Encoding utf8
                Mock Get-MetraInspectPlanRoots { @($temp) }
                $r = Resolve-MetraInspectPlanPath -Path $file
                $r.Ok | Should -BeFalse
                $r.Error | Should -Match 'plan\.md'
            }
            finally {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Inspect project context' {
    It 'resolves Metra by -Name' {
        InModuleScope Metra {
            $c = Resolve-MetraInspectProjectContext -Name 'Metra' -Mode diff
            $c.Ok | Should -BeTrue
            $c.Project | Should -Be 'Metra'
            $c.ContextLimited | Should -BeFalse
        }
    }

    It 'plan mode continues context-limited without -Name or cwd project' {
        InModuleScope Metra {
            $c = Resolve-MetraInspectProjectContext -Mode plan -Cwd $env:TEMP
            $c.Ok | Should -BeTrue
            $c.ContextLimited | Should -BeTrue
            $c.Warning | Should -Match 'Project context not resolved'
        }
    }

    It 'diff mode fails without project root' {
        InModuleScope Metra {
            $c = Resolve-MetraInspectProjectContext -Mode diff -Cwd $env:TEMP
            $c.Ok | Should -BeFalse
            $c.Error | Should -Match 'resolve project'
        }
    }
}

Describe 'Inspect pack pointer honesty' {
    It 'warns when inputHash differs from pointer' {
        InModuleScope Metra {
            $state = Join-Path $env:TEMP ("metra-inspect-state-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $state -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $state }

            $slot = Join-Path $state 'Metra'
            New-Item -ItemType Directory -Path $slot -Force | Out-Null
            $report = [ordered]@{
                schemaVersion = 1
                mode          = 'diff'
                provenance    = [ordered]@{
                    engine         = 'ollama'
                    model          = 'test'
                    inspectedAtUtc = [datetime]::UtcNow.ToString('o')
                    project        = 'Metra'
                    root           = (Get-MetraRoot)
                    inputHash      = 'deadbeef'
                    assessedFiles  = @('x.ps1')
                    base           = ''
                }
                findings      = @()
            }
            $latest = Join-Path $slot 'latest.json'
            ($report | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $latest -Encoding utf8
            $pointer = [ordered]@{
                mode             = 'diff'
                latestReportPath = $latest
                project          = 'Metra'
                root             = (Get-MetraRoot)
                inputHash        = 'deadbeef'
                createdAtUtc     = [datetime]::UtcNow.ToString('o')
            }
            ($pointer | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $state 'last-diff.json') -Encoding utf8

            Mock Get-MetraInspectGitDiffFiles {
                [PSCustomObject]@{
                    Empty            = $false
                    Files            = @([PSCustomObject]@{ path = 'x.ps1'; content = 'new-content' })
                    GitHead          = 'abc'
                    RawDiff          = 'diff'
                    UntrackedCount   = 0
                    WorkingTreeDirty = $false
                    Warning          = $null
                    BaseMode         = 'working-tree'
                    Base             = ''
                }
            }
            Mock Reduce-MetraInspectDiffFiles {
                [PSCustomObject]@{
                    Files            = @([PSCustomObject]@{ path = 'x.ps1'; content = 'new-content'; class = 'code' })
                    FileCount        = 1
                    ReducedFileCount = 1
                    SkippedFileCount = 0
                    SkippedPaths     = @()
                    DocsCollapsed    = @()
                    Truncated        = $false
                    OmittedByFileCap = @()
                }
            }
            Mock ConvertTo-MetraInspectScrubbedDiffParts {
                @([PSCustomObject]@{ path = 'x.ps1'; content = 'new-content'; class = 'code' })
            }
            Mock Get-MetraInspectInputHash { 'freshhash' }
            Mock Set-Clipboard { }

            try {
                $pack = Invoke-MetraInspectPack -Mode diff
                $pack.Stale | Should -BeTrue
                $pack.Text | Should -Match 'assessed snapshot'
                $pack.Text | Should -Match 'new-content'
            }
            finally {
                Remove-Item -LiteralPath $state -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}


Describe 'Inspect pack plan disk scrub' {
    It 'throws when plan disk scrub refuses (no planBody persistence required)' {
        InModuleScope Metra {
            $state = Join-Path $env:TEMP ("metra-inspect-state-" + [guid]::NewGuid().ToString('n'))
            $planDir = Join-Path $env:TEMP ("metra-inspect-planfile-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $state -Force | Out-Null
            New-Item -ItemType Directory -Path $planDir -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $state }

            $planPath = Join-Path $planDir 'secret.plan.md'
            Set-Content -LiteralPath $planPath -Value 'plan body' -Encoding utf8

            $slot = Join-Path $state 'plan-Metra'
            New-Item -ItemType Directory -Path $slot -Force | Out-Null
            $report = [ordered]@{
                schemaVersion = 1
                mode          = 'plan'
                provenance    = [ordered]@{
                    engine         = 'ollama'
                    model          = 'test'
                    inspectedAtUtc = [datetime]::UtcNow.ToString('o')
                    project        = 'Metra'
                    planPath       = $planPath
                    inputHash      = 'deadbeef'
                }
                findings      = @()
            }
            $latest = Join-Path $slot 'latest.json'
            ($report | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $latest -Encoding utf8
            $pointer = [ordered]@{
                mode             = 'plan'
                latestReportPath = $latest
                project          = 'Metra'
                inputHash        = 'deadbeef'
                planPath         = $planPath
                createdAtUtc     = [datetime]::UtcNow.ToString('o')
            }
            ($pointer | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $state 'last-plan.json') -Encoding utf8

            Mock Get-MetraInspectPlanRoots { @($planDir) }
            Mock Get-MetraInspectScrubbedPlanText { throw 'Plan content refused by secrets scrub: mocked' }
            Mock Set-Clipboard { }

            try {
                { Invoke-MetraInspectPack -Mode plan } | Should -Throw '*refused by secrets scrub*'
            }
            finally {
                Remove-Item -LiteralPath $state -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}


Describe 'Inspect pack path confine' {
    It 'rejects latestReportPath outside state root' {
        InModuleScope Metra {
            $state = Join-Path $env:TEMP ("metra-inspect-state-" + [guid]::NewGuid().ToString('n'))
            $outside = Join-Path $env:TEMP ("metra-inspect-outside-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $state -Force | Out-Null
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $state }

            $evil = Join-Path $outside 'evil-latest.json'
            Set-Content -LiteralPath $evil -Value '{"schemaVersion":1,"mode":"diff","provenance":{},"findings":[]}' -Encoding utf8
            $pointer = [ordered]@{
                mode             = 'diff'
                latestReportPath = $evil
                project          = 'Metra'
                inputHash        = 'deadbeef'
                createdAtUtc     = [datetime]::UtcNow.ToString('o')
            }
            ($pointer | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $state 'last-diff.json') -Encoding utf8

            try {
                { Invoke-MetraInspectPack -Mode diff } | Should -Throw '*inspect state root*'
            }
            finally {
                Remove-Item -LiteralPath $state -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Inspect WhatIf honesty' {
    It 'diff WhatIf skips Invoke-MetraInspectEngine' {
        InModuleScope Metra {
            Mock Resolve-MetraInspectProjectContext {
                [PSCustomObject]@{
                    Ok             = $true
                    Project        = 'Metra'
                    Root           = (Get-MetraRoot)
                    ContextLimited = $false
                    Warning        = $null
                    Error          = $null
                }
            }
            Mock Get-MetraInspectGitDiffFiles {
                [PSCustomObject]@{
                    Empty            = $false
                    Files            = @([PSCustomObject]@{ path = 'a.ps1'; content = 'x' })
                    GitHead          = 'abc'
                    RawDiff          = 'diff'
                    UntrackedCount   = 0
                    WorkingTreeDirty = $false
                    Warning          = $null
                    BaseMode         = 'working-tree'
                    Base             = ''
                }
            }
            Mock Reduce-MetraInspectDiffFiles {
                [PSCustomObject]@{
                    Files            = @([PSCustomObject]@{ path = 'a.ps1'; content = 'x'; class = 'code' })
                    FileCount        = 1
                    ReducedFileCount = 1
                    SkippedFileCount = 0
                    SkippedPaths     = @()
                    DocsCollapsed    = @()
                    Truncated        = $false
                }
            }
            Mock Invoke-MetraInspectEngine { throw 'engine should not run under WhatIf' }

            $r = Invoke-MetraInspectDiff -Name Metra -WhatIf
            $r.WhatIf | Should -BeTrue
            $r.Mode | Should -Be 'diff'
            $r.FileCount | Should -Be 1
        }
    }

    It 'plan WhatIf skips Invoke-MetraInspectEngine' {
        InModuleScope Metra {
            $temp = Join-Path $env:TEMP ("metra-inspect-plans-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $temp -Force | Out-Null
            try {
                $plan = Join-Path $temp 'whatif.plan.md'
                Set-Content -LiteralPath $plan -Value '# plan' -Encoding utf8
                Mock Get-MetraInspectPlanRoots { @($temp) }
                Mock Resolve-MetraInspectProjectContext {
                    [PSCustomObject]@{
                        Ok             = $true
                        Project        = 'Metra'
                        Root           = (Get-MetraRoot)
                        ContextLimited = $false
                        Warning        = $null
                        Error          = $null
                    }
                }
                Mock Invoke-MetraInspectEngine { throw 'engine should not run under WhatIf' }
                Mock Get-MetraInspectScrubbedPlanText { throw 'scrub should not run under WhatIf' }

                $r = Invoke-MetraInspectPlan -Name Metra -Path $plan -WhatIf
                $r.WhatIf | Should -BeTrue
                $r.Mode | Should -Be 'plan'
                $r.PlanPath | Should -Be ([System.IO.Path]::GetFullPath($plan))
                }
            finally {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Inspect pack empty-diff stale' {
    It 'marks stale when current diff is empty' {
        InModuleScope Metra {
            $state = Join-Path $env:TEMP ("metra-inspect-state-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $state -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $state }

            $slot = Join-Path $state 'Metra'
            New-Item -ItemType Directory -Path $slot -Force | Out-Null
            $report = [ordered]@{
                schemaVersion = 1
                mode          = 'diff'
                provenance    = [ordered]@{
                    engine         = 'ollama'
                    model          = 'test'
                    inspectedAtUtc = [datetime]::UtcNow.ToString('o')
                    project        = 'Metra'
                    root           = (Get-MetraRoot)
                    inputHash      = 'deadbeef'
                    assessedFiles  = @('x.ps1')
                    base           = ''
                }
                findings      = @()
            }
            $latest = Join-Path $slot 'latest.json'
            ($report | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $latest -Encoding utf8
            $pointer = [ordered]@{
                mode             = 'diff'
                latestReportPath = $latest
                project          = 'Metra'
                root             = (Get-MetraRoot)
                inputHash        = 'deadbeef'
                createdAtUtc     = [datetime]::UtcNow.ToString('o')
            }
            ($pointer | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $state 'last-diff.json') -Encoding utf8

            Mock Get-MetraInspectGitDiffFiles {
                [PSCustomObject]@{
                    Empty            = $true
                    Files            = @()
                    GitHead          = 'abc'
                    RawDiff          = ''
                    UntrackedCount   = 0
                    WorkingTreeDirty = $false
                    Warning          = $null
                    BaseMode         = 'working-tree'
                    Base             = ''
                }
            }
            Mock Set-Clipboard { }

            try {
                $pack = Invoke-MetraInspectPack -Mode diff
                $pack.Stale | Should -BeTrue
                $pack.Text | Should -Match 'Working tree is now empty'
            }
            finally {
                Remove-Item -LiteralPath $state -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Inspect input hash' {
    It 'is stable for same parts' {
        InModuleScope Metra {
            $parts = @(
                [PSCustomObject]@{ path = 'a.ps1'; content = 'hello' }
            )
            $h1 = Get-MetraInspectInputHash -Parts $parts
            $h2 = Get-MetraInspectInputHash -Parts $parts
            $h1 | Should -Be $h2
            $h1.Length | Should -Be 64
        }
    }
}

Describe 'Inspect git base validation' {
    It 'rejects leading dash' {
        InModuleScope Metra {
            { Resolve-MetraInspectGitBase -Root (Get-MetraRoot) -Base '-evil' } | Should -Throw "*must not start*"
        }
    }

    It 'rejects path traversal segments' {
        InModuleScope Metra {
            { Resolve-MetraInspectGitBase -Root (Get-MetraRoot) -Base 'foo/..' } | Should -Throw '*path traversal*'
        }
    }

    It 'rejects whitespace-only' {
        InModuleScope Metra {
            { Resolve-MetraInspectGitBase -Root (Get-MetraRoot) -Base '   ' } | Should -Throw '*empty or whitespace*'
        }
    }

    It 'rejects unknown revision' {
        InModuleScope Metra {
            { Resolve-MetraInspectGitBase -Root (Get-MetraRoot) -Base 'this-rev-definitely-does-not-exist-zzzz' } | Should -Throw '*not a valid git revision*'
        }
    }
}

Describe 'Inspect untracked working-tree inclusion' {
    It 'includes untracked text files in a temp git repo' {
        InModuleScope Metra {
            $tmp = Join-Path $env:TEMP ("metra-inspect-git-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            try {
                Push-Location -LiteralPath $tmp
                try {
                    & git init 2>&1 | Out-Null
                    & git config user.email 'metra-inspect@example.com' 2>&1 | Out-Null
                    & git config user.name 'Metra Inspect' 2>&1 | Out-Null
                    Set-Content -LiteralPath (Join-Path $tmp 'tracked.txt') -Value 'tracked' -Encoding utf8
                    & git add tracked.txt 2>&1 | Out-Null
                    & git commit -m 'init' 2>&1 | Out-Null
                    Set-Content -LiteralPath (Join-Path $tmp 'new-feature.ps1') -Value 'Write-Host "hi"' -Encoding utf8
                }
                finally {
                    Pop-Location
                }

                $diff = Get-MetraInspectGitDiffFiles -Root $tmp
                $diff.Empty | Should -BeFalse
                $diff.UntrackedCount | Should -BeGreaterThan 0
                $diff.BaseMode | Should -Be 'working-tree'
                ($diff.Files | Where-Object { $_.path -eq 'new-feature.ps1' }).Count | Should -Be 1
                ($diff.Files | Where-Object { $_.path -eq 'new-feature.ps1' }).content | Should -Match 'UNTRACKED FILE'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Reduce keeps untracked-shaped code files' {
        InModuleScope Metra {
            $files = @(
                [PSCustomObject]@{ path = 'fresh.ps1'; content = "UNTRACKED FILE`nWrite-Host 1" }
            )
            $r = Reduce-MetraInspectDiffFiles -Files $files
            $r.ReducedFileCount | Should -Be 1
            $r.Files[0].class | Should -Be 'code'
        }
    }
}

Describe 'Inspect CLI Name arity' {
    It 'throws when -Name has more than one project' {
        InModuleScope Metra {
            { Show-MetraInspectCli -Name @('Metra', 'Trivia') } | Should -Throw '*single -Name*'
        }
    }
}

Describe 'Inspect provenance omits large bodies' {
    It 'New-MetraInspectReport keeps caller provenance without requiring assessedDiff/planBody' {
        InModuleScope Metra {
            $prov = [PSCustomObject]@{
                engine             = 'ollama'
                model              = 'test'
                inputHash          = 'abc'
                assessedFiles      = @('a.ps1')
                baseMode           = 'working-tree'
                untrackedFileCount = 1
                workingTreeDirty   = $false
            }
            $report = New-MetraInspectReport -Mode diff -Provenance $prov -Findings @()
            $report.provenance.assessedFiles | Should -Contain 'a.ps1'
            $report.provenance.PSObject.Properties.Name | Should -Not -Contain 'assessedDiff'
            $report.provenance.PSObject.Properties.Name | Should -Not -Contain 'planBody'
            $report.provenance.baseMode | Should -Be 'working-tree'
        }
    }
}

Describe 'Inspect pack-only' {
    It 'plan pack-only skips Invoke-MetraInspectEngine and marks Bing-only findings' {
        InModuleScope Metra {
            $state = Join-Path $env:TEMP ("metra-inspect-state-" + [guid]::NewGuid().ToString('n'))
            $planDir = Join-Path $env:TEMP ("metra-inspect-planfile-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $state -Force | Out-Null
            New-Item -ItemType Directory -Path $planDir -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $state }

            $planPath = Join-Path $planDir 'bing-only.plan.md'
            Set-Content -LiteralPath $planPath -Value '# Bing-only plan body' -Encoding utf8

            Mock Get-MetraInspectPlanRoots { @($planDir) }
            Mock Resolve-MetraInspectProjectContext {
                [PSCustomObject]@{
                    Ok             = $true
                    Project        = 'Metra'
                    Root           = (Get-MetraRoot)
                    ContextLimited = $false
                    Warning        = $null
                    Error          = $null
                }
            }
            Mock Invoke-MetraInspectEngine { throw 'engine should not run for pack-only' }
            Mock Set-Clipboard { }

            try {
                $pack = Invoke-MetraInspectPackOnly -Mode plan -Name Metra -Path $planPath
                $pack.Mode | Should -Be 'plan'
                $pack.Text | Should -Match 'Bing-only: no Ask engine run'
                $pack.Text | Should -Match 'none - Bing-only pack; no Ask engine run'
                $pack.Text | Should -Match 'Bing-only plan body'
                $pack.Text | Should -Match 'Assessed report: \(none - Bing-only pack\)'
            }
            finally {
                Remove-Item -LiteralPath $state -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'diff pack-only skips Invoke-MetraInspectEngine' {
        InModuleScope Metra {
            $state = Join-Path $env:TEMP ("metra-inspect-state-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $state -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $state }

            Mock Resolve-MetraInspectProjectContext {
                [PSCustomObject]@{
                    Ok             = $true
                    Project        = 'Metra'
                    Root           = (Get-MetraRoot)
                    ContextLimited = $false
                    Warning        = $null
                    Error          = $null
                }
            }
            Mock Get-MetraInspectGitDiffFiles {
                [PSCustomObject]@{
                    Empty            = $false
                    Files            = @([PSCustomObject]@{ path = 'a.ps1'; content = 'diff content' })
                    GitHead          = 'abc'
                    RawDiff          = 'diff'
                    UntrackedCount   = 0
                    WorkingTreeDirty = $false
                    Warning          = $null
                    BaseMode         = 'working-tree'
                    Base             = ''
                }
            }
            Mock Reduce-MetraInspectDiffFiles {
                [PSCustomObject]@{
                    Files            = @([PSCustomObject]@{ path = 'a.ps1'; content = 'diff content'; class = 'code' })
                    FileCount        = 1
                    ReducedFileCount = 1
                    SkippedFileCount = 0
                    SkippedPaths     = @()
                    DocsCollapsed    = @()
                    Truncated        = $false
                    OmittedByFileCap = @()
                }
            }
            Mock ConvertTo-MetraInspectScrubbedDiffParts {
                @([PSCustomObject]@{ path = 'a.ps1'; content = 'scrubbed'; class = 'code' })
            }
            Mock Invoke-MetraInspectEngine { throw 'engine should not run for pack-only' }
            Mock Set-Clipboard { }

            try {
                $pack = Invoke-MetraInspectPackOnly -Mode diff -Name Metra
                $pack.Mode | Should -Be 'diff'
                $pack.Text | Should -Match 'Bing-only: no Ask engine run'
                $pack.Text | Should -Match 'scrubbed'
                $pack.Text | Should -Match 'a.ps1'
                $pack.Text | Should -Match 'Pack profile: bing'
            }
            finally {
                Remove-Item -LiteralPath $state -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Inspect A2 desk pack' {
    It 'Test-MetraInspectRelativePathInA2DeskScope matches stub and playbooks only' {
        InModuleScope Metra {
            Test-MetraInspectRelativePathInA2DeskScope -RelativePath 'AGENTS.md' | Should -Be $true
            Test-MetraInspectRelativePathInA2DeskScope -RelativePath 'docs/playbooks/stuck-session-in-use.md' | Should -Be $true
            Test-MetraInspectRelativePathInA2DeskScope -RelativePath 'Colleague/Colleague.psm1' | Should -Be $false
            Test-MetraInspectRelativePathInA2DeskScope -RelativePath 'docs/Other.md' | Should -Be $false
        }
    }

    It 'agents pack-only skips Invoke-MetraInspectEngine and includes A2 audit summary' {
        InModuleScope Metra {
            $state = Join-Path $env:TEMP ("metra-inspect-state-" + [guid]::NewGuid().ToString('n'))
            $repo = Join-Path $env:TEMP ("metra-inspect-a2-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $state -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repo 'docs/playbooks') -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $state }

            Set-Content -LiteralPath (Join-Path $repo 'AGENTS.md') -Value ("# Stub`n" + ("line`n" * 4)) -Encoding utf8
            Set-Content -LiteralPath (Join-Path $repo 'docs/playbooks/sample.md') -Value '# Playbook' -Encoding utf8

            Mock Resolve-MetraInspectProjectContext {
                [PSCustomObject]@{
                    Ok             = $true
                    Project        = 'Sample'
                    Root           = $repo
                    ContextLimited = $false
                    Warning        = $null
                    Error          = $null
                }
            }
            Mock Get-MetraInspectGitDiffFiles {
                [PSCustomObject]@{
                    Empty            = $false
                    Files            = @([PSCustomObject]@{ path = 'scripts/noise.ps1'; content = 'diff noise' })
                    GitHead          = 'abc'
                    RawDiff          = 'diff'
                    UntrackedCount   = 0
                    WorkingTreeDirty = $false
                    Warning          = $null
                    BaseMode         = 'working-tree'
                    Base             = ''
                }
            }
            Mock Invoke-MetraInspectEngine { throw 'engine should not run for pack-only' }
            Mock Set-Clipboard { }

            try {
                $pack = Invoke-MetraInspectPackOnly -Mode agents -Name Sample
                $pack.Mode | Should -Be 'agents'
                $pack.Text | Should -Match 'Bing-only: no Ask engine run'
                $pack.Text | Should -Match 'review A2 desk split'
                $pack.Text | Should -Match '## A2 desk audit'
                $pack.Text | Should -Match 'AGENTS.md:'
                $pack.Text | Should -Match 'docs/playbooks/sample.md'
                $pack.Text | Should -Not -Match 'scripts/noise.ps1'
            }
            finally {
                Remove-Item -LiteralPath $state -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Inspect A2 AGENTS consumer' {
    It 'Get-MetraInspectAgentsPlaybookIndexPathsFromStub parses On-demand playbooks table links' {
        InModuleScope Metra {
            $stub = @'
# Pilot stub

## On-demand playbooks

| Trigger | Read |
| --- | --- |
| stuck session | [docs/playbooks/stuck-session-in-use.md](docs/playbooks/stuck-session-in-use.md) |
| wafm | [docs/playbooks/wafm.md](docs/playbooks/wafm.md) |
| stuck session dup | [docs/playbooks/stuck-session-in-use.md](docs/playbooks/stuck-session-in-use.md) |

## Token rules

- scoped grep only
'@
            $paths = @(Get-MetraInspectAgentsPlaybookIndexPathsFromStub -StubText $stub)
            $paths.Count | Should -Be 2
            $paths[0] | Should -Be 'docs/playbooks/stuck-session-in-use.md'
            $paths[1] | Should -Be 'docs/playbooks/wafm.md'
        }
    }

    It 'Resolve-MetraInspectAgentsPlaybookIndexRelativePath rejects .. traversal and accepts canonical paths' {
        InModuleScope Metra {
            Resolve-MetraInspectAgentsPlaybookIndexRelativePath -RawPath 'docs/playbooks/sample.md' |
                Should -Be 'docs/playbooks/sample.md'
            Resolve-MetraInspectAgentsPlaybookIndexRelativePath -RawPath 'docs/playbooks/../../AGENTS.md' |
                Should -Be $null
            Resolve-MetraInspectAgentsPlaybookIndexRelativePath -RawPath 'docs/playbooks/nested/sample.md' |
                Should -Be 'docs/playbooks/nested/sample.md'
        }
    }

    It 'Get-MetraInspectAgentsPlaybookIndexPathsFromStub ignores traversal links in the table' {
        InModuleScope Metra {
            $stub = @'
## On-demand playbooks

| Trigger | Read |
| --- | --- |
| escape | [docs/playbooks/../../AGENTS.md](docs/playbooks/../../AGENTS.md) |
| ok | [docs/playbooks/sample.md](docs/playbooks/sample.md) |
'@
            $paths = @(Get-MetraInspectAgentsPlaybookIndexPathsFromStub -StubText $stub)
            $paths.Count | Should -Be 1
            $paths[0] | Should -Be 'docs/playbooks/sample.md'
        }
    }

    It 'Get-MetraInspectAgentsText appends playbook path index without cabinet bodies' {
        InModuleScope Metra {
            $repo = Join-Path $env:TEMP ("metra-inspect-agents-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $repo 'docs/playbooks') -Force | Out-Null
            try {
                $stub = @'
# Stub

## On-demand playbooks

| Trigger | Read |
| --- | --- |
| sample | [docs/playbooks/sample.md](docs/playbooks/sample.md) |

## Token rules
'@
                Set-Content -LiteralPath (Join-Path $repo 'AGENTS.md') -Value $stub -Encoding utf8
                Set-Content -LiteralPath (Join-Path $repo 'docs/playbooks/sample.md') -Value 'CABINET_BODY_NOT_FOR_INSPECT' -Encoding utf8

                $text = Get-MetraInspectAgentsText -Root $repo
                $text | Should -Match 'On-demand playbooks'
                $text | Should -Match 'A2 on-demand playbook paths'
                $text | Should -Match '- docs/playbooks/sample.md'
                $text | Should -Not -Match 'CABINET_BODY_NOT_FOR_INSPECT'
            }
            finally {
                Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Get-MetraInspectAgentsText leaves legacy monolith AGENTS unchanged when no On-demand playbooks section' {
        InModuleScope Metra {
            $repo = Join-Path $env:TEMP ("metra-inspect-agents-legacy-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            try {
                Set-Content -LiteralPath (Join-Path $repo 'AGENTS.md') -Value "# Legacy`n`nLong procedural body stays attached.`n" -Encoding utf8
                $text = Get-MetraInspectAgentsText -Root $repo
                $text | Should -Match 'Long procedural body stays attached'
                $text | Should -Not -Match 'A2 on-demand playbook paths'
            }
            finally {
                Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Get-MetraInspectAgentsText README fallback does not append playbook index block' {
        InModuleScope Metra {
            $repo = Join-Path $env:TEMP ("metra-inspect-readme-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            try {
                $readme = @'
# README

## On-demand playbooks

| Trigger | Read |
| --- | --- |
| sample | [docs/playbooks/sample.md](docs/playbooks/sample.md) |
'@
                Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value $readme -Encoding utf8
                $text = Get-MetraInspectAgentsText -Root $repo
                $text | Should -Match 'On-demand playbooks'
                $text | Should -Not -Match 'A2 on-demand playbook paths'
            }
            finally {
                Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Inspect Bing pack profile' {
    It 'extracts Describe and It names for test catalog' {
        InModuleScope Metra {
            $root = Join-Path $env:TEMP ("metra-inspect-catalog-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'tests') -Force | Out-Null
            try {
                $testPath = Join-Path $root 'tests/Sample.Tests.ps1'
                @(
                    "Describe 'Outer block' {"
                    "    It 'does the thing' {"
                    '    }'
                    "    It 'inventory-path check' {"
                    '    }'
                    '}'
                ) | Set-Content -LiteralPath $testPath -Encoding utf8

                $catalog = Get-MetraInspectPesterTestCatalogText -Root $root -RelativePaths @('tests/Sample.Tests.ps1')
                $catalog | Should -Match 'Test catalog'
                $catalog | Should -Match "Describe 'Outer block'"
                $catalog | Should -Match "It 'does the thing'"
                $catalog | Should -Match "It 'inventory-path check'"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Build-MetraInspectPackDiffAppendix appends test catalog and manifest for bing profile' {
        InModuleScope Metra {
            $root = Join-Path $env:TEMP ("metra-inspect-bingpack-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'tests') -Force | Out-Null
            try {
                $testPath = Join-Path $root 'tests/Widget.Tests.ps1'
                Set-Content -LiteralPath $testPath -Value "Describe 'Widget' { It 'works' { } }" -Encoding utf8

                Mock ConvertTo-MetraInspectScrubbedDiffParts {
                    param($Files)
                    @($Files | ForEach-Object {
                            [PSCustomObject]@{ path = $_.path; content = $_.content; class = $_.class }
                        })
                }

                $appendix = Build-MetraInspectPackDiffAppendix -Root $root -Files @(
                    [PSCustomObject]@{ path = 'tests/Widget.Tests.ps1'; content = 'diff body' },
                    [PSCustomObject]@{ path = 'docs/Notes.md'; content = '# notes' }
                ) -Profile bing

                $appendix.Manifest | Should -Match 'Pack profile: bing'
                $appendix.Manifest | Should -Match 'MaxPackBodyChars=750000'
                $appendix.Manifest | Should -Match 'MaxFiles=64'
                $appendix.Manifest | Should -Match 'MaxBytesPerFile=96000'
                $appendix.TestCatalog | Should -Match 'tests/Widget.Tests.ps1'
                $appendix.TestCatalog | Should -Match "It 'works'"
                $appendix.FileList | Should -Contain 'docs/Notes.md'
                $appendix.Body | Should -Match 'docs/Notes.md'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'bing profile includes doc bodies; default inspect prompt still collapses docs' {
        InModuleScope Metra {
            $files = @(
                [PSCustomObject]@{ path = 'src/a.ps1'; content = 'code'; class = 'code' },
                [PSCustomObject]@{ path = 'docs/readme.md'; content = '# readme body'; class = 'docs' }
            )
            $bing = Reduce-MetraInspectDiffFiles -Files $files -MaxFiles 64 -MaxBytesPerFile 96000 -IncludeDocs
            $ask = Reduce-MetraInspectDiffFiles -Files $files
            @($bing.Files | ForEach-Object { $_.path }) | Should -Contain 'docs/readme.md'
            @($ask.Files | ForEach-Object { $_.path }) | Should -Not -Contain 'docs/readme.md'
            $ask.DocsCollapsed | Should -Contain 'docs/readme.md'
        }
    }
}

Describe 'Inspect review loop helpers' {
    It 'maps Info to Low tier for review counts' {
        InModuleScope Metra {
            $counts = Get-MetraInspectReviewSeverityCounts -Findings @(
                [PSCustomObject]@{ severity = 'High' },
                [PSCustomObject]@{ severity = 'Info' },
                [PSCustomObject]@{ severity = 'Low' }
            )
            $counts.High | Should -Be 1
            $counts.Low | Should -Be 2
        }
    }

    It 'Test-MetraInspectReviewGoalMet requires Critical=0 High=0 Medium<=2' {
        InModuleScope Metra {
            Test-MetraInspectReviewGoalMet -Counts ([PSCustomObject]@{ Critical = 0; High = 0; Medium = 2; Low = 5 }) | Should -BeTrue
            Test-MetraInspectReviewGoalMet -Counts ([PSCustomObject]@{ Critical = 0; High = 0; Medium = 3; Low = 0 }) | Should -BeFalse
            Test-MetraInspectReviewGoalMet -Counts ([PSCustomObject]@{ Critical = 0; High = 1; Medium = 0; Low = 0 }) | Should -BeFalse
        }
    }

    It 'Get-MetraInspectReviewGrade is informational only' {
        InModuleScope Metra {
            Get-MetraInspectReviewGrade -Counts ([PSCustomObject]@{ Critical = 0; High = 0; Medium = 2; Low = 0 }) | Should -Be 'A'
            Get-MetraInspectReviewGrade -Counts ([PSCustomObject]@{ Critical = 0; High = 0; Medium = 5; Low = 0 }) | Should -Be 'B'
            Get-MetraInspectReviewGrade -Counts ([PSCustomObject]@{ Critical = 0; High = 1; Medium = 0; Low = 0 }) | Should -Be 'C'
            Get-MetraInspectReviewGrade -Counts ([PSCustomObject]@{ Critical = 1; High = 0; Medium = 0; Low = 0 }) | Should -Be 'D'
        }
    }

    It 'Resolve-MetraInspectReviewTermination detects goal convergence and max loops' {
        InModuleScope Metra {
            $goalCounts = [PSCustomObject]@{ Critical = 0; High = 0; Medium = 2; Low = 1 }
            $r = Resolve-MetraInspectReviewTermination -LatestCounts $goalCounts -CompletedCycles 1 -MaxLoops 5
            $r.Complete | Should -BeTrue
            $r.TerminationReason | Should -Be 'Goal achieved'

            $flat = [PSCustomObject]@{ Critical = 0; High = 0; Medium = 3; Low = 0 }
            $r2 = Resolve-MetraInspectReviewTermination -LatestCounts $flat -CompletedCycles 2 -PreviousVerifyCounts $flat -MaxLoops 5
            $r2.Complete | Should -BeTrue
            $r2.TerminationReason | Should -Be 'Convergence detected'

            $r3 = Resolve-MetraInspectReviewTermination -LatestCounts ([PSCustomObject]@{ Critical = 0; High = 1; Medium = 2; Low = 0 }) -CompletedCycles 5 -MaxLoops 5
            $r3.Complete | Should -BeTrue
            $r3.TerminationReason | Should -Be 'Maximum loop count reached'
        }
    }

    It 'Test-MetraInspectReviewManifestRelativePath rejects traversal and rooted paths' {
        InModuleScope Metra {
            Test-MetraInspectReviewManifestRelativePath -RelativePath 'scripts/foo.ps1' | Should -BeTrue
            Test-MetraInspectReviewManifestRelativePath -RelativePath '.cursor/rules/x.mdc' | Should -BeTrue
            Test-MetraInspectReviewManifestRelativePath -RelativePath '..\outside.txt' | Should -BeFalse
            Test-MetraInspectReviewManifestRelativePath -RelativePath 'scripts\..\..\outside.txt' | Should -BeFalse
            Test-MetraInspectReviewManifestRelativePath -RelativePath 'C:\Windows\System32\cmd.exe' | Should -BeFalse
        }
    }

    It 'Assert-MetraInspectReviewBaselinePath confines persisted baselinePath to expected slot directory' {
        InModuleScope Metra {
            $stateRoot = Join-Path $env:TEMP ("metra-inspect-baseline-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $stateRoot }
            try {
                $expected = Get-MetraInspectReviewBaselineDirectory -SlotKey 'Metra' -RoundNum 1
                New-Item -ItemType Directory -Path $expected -Force | Out-Null
                { Assert-MetraInspectReviewBaselinePath -BaselinePath $expected -SlotKey 'Metra' -RoundNum 1 } | Should -Not -Throw

                $foreign = Join-Path $stateRoot 'Metra\baselines\r9'
                New-Item -ItemType Directory -Path $foreign -Force | Out-Null
                { Assert-MetraInspectReviewBaselinePath -BaselinePath $foreign -SlotKey 'Metra' -RoundNum 1 } | Should -Throw '*does not match expected*'

                $outside = Join-Path $env:TEMP 'metra-evil-baseline'
                New-Item -ItemType Directory -Path $outside -Force | Out-Null
                { Assert-MetraInspectReviewBaselinePath -BaselinePath $outside -SlotKey 'Metra' -RoundNum 1 } | Should -Throw '*outside inspect state root*'
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path $env:TEMP 'metra-evil-baseline') -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Assert-MetraInspectReviewLoopRootMatch rejects persisted root drift' {
        InModuleScope Metra {
            $root = (Get-MetraRoot)
            { Assert-MetraInspectReviewLoopRootMatch -PersistedRoot $root -CurrentRoot $root } | Should -Not -Throw
            { Assert-MetraInspectReviewLoopRootMatch -PersistedRoot 'C:\Old\Metra' -CurrentRoot $root } |
                Should -Throw '*root mismatch*'
        }
    }

    It 'Get-MetraInspectReviewLoopState fails closed on corrupt JSON' {
        InModuleScope Metra {
            $stateRoot = Join-Path $env:TEMP ("metra-inspect-state-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $stateRoot 'Metra') -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $stateRoot }
            $path = Get-MetraInspectReviewLoopStatePath -SlotKey 'Metra'
            Set-Content -LiteralPath $path -Value '{ not-json' -Encoding UTF8
            try {
                { Get-MetraInspectReviewLoopState -SlotKey 'Metra' } | Should -Throw '*Run inspect loop -Reset*'
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Resolve-MetraInspectReviewManifestPathPair throws on unsafe manifest entries' {
        InModuleScope Metra {
            $root = Join-Path $env:TEMP ("metra-manifest-" + [guid]::NewGuid().ToString('n'))
            $baseline = Join-Path $root 'baseline'
            New-Item -ItemType Directory -Path $baseline -Force | Out-Null
            try {
                { Resolve-MetraInspectReviewManifestPathPair -RelativePath '..\escape.txt' -ProjectRoot $root -ContainerRoot $baseline } |
                    Should -Throw '*unsafe manifest path*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Save-MetraInspectReviewGitBaseline warns when diff paths are omitted from manifest' {
        InModuleScope Metra {
            $root = Join-Path $env:TEMP ("metra-save-" + [guid]::NewGuid().ToString('n'))
            $stateRoot = Join-Path $root 'state'
            $project = Join-Path $root 'project'
            Mock Get-MetraInspectStateRoot { $stateRoot }
            New-Item -ItemType Directory -Path (Join-Path $project 'scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $project 'scripts\present.ps1') -Value 'present' -Encoding UTF8

            Mock Get-MetraInspectGitDiffFiles {
                [PSCustomObject]@{
                    GitHead = 'abc'
                    Files   = @(
                        [PSCustomObject]@{ path = 'scripts/present.ps1'; content = 'diff' }
                        [PSCustomObject]@{ path = 'scripts/deleted.ps1'; content = 'diff' }
                    )
                }
            }
            Mock Get-MetraInspectReviewWorkingTreeInputHash { 'hash' }

            try {
                $snap = Save-MetraInspectReviewGitBaseline -Confirm:$false -Root $project -SlotKey 'Metra' -RoundNum 3
                $snap.ManifestPathCount | Should -Be 1
                $snap.DiffPathCount | Should -Be 2
                $snap.OmittedPaths | Should -Contain 'scripts/deleted.ps1'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Invoke-MetraInspectReviewLoop prefers explicit -MaxLoops over persisted session' {
        InModuleScope Metra {
            $stateRoot = Join-Path $env:TEMP ("metra-maxloops-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $stateRoot }
            Mock Resolve-MetraInspectProjectContext {
                [PSCustomObject]@{
                    Ok      = $true
                    Project = 'Metra'
                    Root    = (Get-MetraRoot)
                    Error   = $null
                }
            }
            $persisted = [PSCustomObject]@{
                schemaVersion   = 1
                project         = 'Metra'
                root            = (Get-MetraRoot)
                inspectMode     = 'diff'
                maxLoops        = 5
                active          = $true
                phase           = $null
                runUntilGoal    = $false
                completedCycles = 0
                rounds          = @()
            }
            Write-MetraAtomicUtf8Text -Path (Join-Path $stateRoot 'review-loop.json') -Text ($persisted | ConvertTo-Json -Depth 6)

            try {
                $result = Invoke-MetraInspectReviewLoop -Name Metra -MaxLoops 8 -WhatIf
                $result.MaxLoops | Should -Be 8
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Restore-MetraInspectReviewGitBaseline leaves diff extras unchanged (manifest-only revert)' {
        InModuleScope Metra {
            $root = Join-Path $env:TEMP ("metra-restore-" + [guid]::NewGuid().ToString('n'))
            $stateRoot = Join-Path $root 'state'
            $project = Join-Path $root 'project'
            Mock Get-MetraInspectStateRoot { $stateRoot }
            $baseline = Get-MetraInspectReviewBaselineDirectory -SlotKey 'Metra' -RoundNum 1
            New-Item -ItemType Directory -Path $baseline -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $project 'scripts') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $baseline 'scripts') -Force | Out-Null
            $listed = Join-Path $project 'scripts\listed.ps1'
            $extra = Join-Path $project 'scripts\extra.ps1'
            Set-Content -LiteralPath $listed -Value 'listed v1' -Encoding UTF8
            Set-Content -LiteralPath $extra -Value 'extra new file' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $baseline 'scripts\listed.ps1') -Value 'listed baseline' -Encoding UTF8
            Write-MetraAtomicUtf8Text -Path (Join-Path $baseline 'manifest.json') -Text '["scripts/listed.ps1"]'

            Mock Get-MetraInspectGitDiffFiles {
                [PSCustomObject]@{
                    Files = @(
                        [PSCustomObject]@{ path = 'scripts/listed.ps1'; content = 'diff' }
                        [PSCustomObject]@{ path = 'scripts/extra.ps1'; content = 'diff' }
                    )
                }
            }

            try {
                Restore-MetraInspectReviewGitBaseline -Confirm:$false -Root $project -BaselinePath $baseline -SlotKey 'Metra' -RoundNum 1
                (Get-Content -LiteralPath $listed -Raw).Trim() | Should -Be 'listed baseline'
                Test-Path -LiteralPath $extra | Should -BeTrue
                (Get-Content -LiteralPath $extra -Raw).Trim() | Should -Be 'extra new file'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'finding fingerprints are stable across whitespace path separators and casing' {
        InModuleScope Metra {
            $base = @{
                File     = 'scripts/private/Inspect.ps1'
                Severity = 'High'
                Category = 'Correctness'
                Finding  = 'example finding text'
            }
            $fp1 = Get-MetraInspectFindingFingerprint @base
            $fp2 = Get-MetraInspectFindingFingerprint -File '  scripts\private\Inspect.ps1  ' -Severity 'High' -Category 'Correctness' -Finding "example`tfinding`r`ntext"
            $fp3 = Get-MetraInspectFindingFingerprint -File 'SCRIPTS/PRIVATE/Inspect.ps1' -Severity 'High' -Category 'Correctness' -Finding 'example finding text'
            $fp1 | Should -Be $fp2
            $fp1 | Should -Be $fp3
        }
    }

    It 'finding fingerprint changes with file severity or category; issueKey ignores severity' {
        InModuleScope Metra {
            $fpA = Get-MetraInspectFindingFingerprint -File 'a.ps1' -Severity 'High' -Category 'Correctness' -Finding 'msg'
            $fpB = Get-MetraInspectFindingFingerprint -File 'b.ps1' -Severity 'High' -Category 'Correctness' -Finding 'msg'
            $fpC = Get-MetraInspectFindingFingerprint -File 'a.ps1' -Severity 'Medium' -Category 'Correctness' -Finding 'msg'
            $fpD = Get-MetraInspectFindingFingerprint -File 'a.ps1' -Severity 'High' -Category 'Security' -Finding 'msg'
            $fpA | Should -Not -Be $fpB
            $fpA | Should -Not -Be $fpC
            $fpA | Should -Not -Be $fpD

            $keyHigh = Get-MetraInspectFindingIssueKey -File 'a.ps1' -Category 'Correctness' -Finding 'msg'
            $keyMed = Get-MetraInspectFindingIssueKey -File 'a.ps1' -Category 'Correctness' -Finding 'msg'
            $keyHigh | Should -Be $keyMed
            $keyHigh | Should -Not -Be (Get-MetraInspectFindingIssueKey -File 'a.ps1' -Category 'Security' -Finding 'msg')
        }
    }

    It 'finding message normalization truncates after 240 chars and tolerates null' {
        InModuleScope Metra {
            $long = ('x' * 300)
            $fp1 = Get-MetraInspectFindingFingerprint -File 'a.ps1' -Severity 'High' -Category 'C' -Finding $long
            $fp2 = Get-MetraInspectFindingFingerprint -File 'a.ps1' -Severity 'High' -Category 'C' -Finding (('x' * 240) + 'YYYY')
            $fp1 | Should -Be $fp2
            { Get-MetraInspectFindingFingerprint -File 'a.ps1' -Severity 'High' -Category 'C' -Finding $null } | Should -Not -Throw
            { Get-MetraInspectFindingIssueKey -File 'a.ps1' -Category 'C' -Finding $null } | Should -Not -Throw
        }
    }

    It 'Test-MetraInspectReviewRegressed ignores New High outside touch set' {
        InModuleScope Metra {
            $baseFinding = [PSCustomObject]@{
                file = 'scripts/touched.ps1'; severity = 'High'; category = 'Correctness'; finding = 'original'
            }
            $baseId = New-MetraInspectFindingIdentityRecord -Finding $baseFinding
            $pending = [PSCustomObject]@{
                findingFingerprintVersion = 1
                findingFingerprints       = @($baseId)
                critical                  = 0
                high                      = 1
                medium                    = 0
            }
            $current = @(
                $baseFinding
                [PSCustomObject]@{
                    file = 'scripts/other.ps1'; severity = 'High'; category = 'Correctness'; finding = 'brand new elsewhere'
                }
            )
            $r = Test-MetraInspectReviewRegressed -PendingBaseline $pending -CurrentFindings $current -TouchSet @('scripts/touched.ps1')
            $r.IncompatibleBaseline | Should -BeFalse
            $r.Regressed | Should -BeFalse
            $r.NewFindingCount | Should -Be 1
        }
    }

    It 'Test-MetraInspectReviewRegressed detects New High inside touch set' {
        InModuleScope Metra {
            $baseFinding = [PSCustomObject]@{
                file = 'scripts/touched.ps1'; severity = 'High'; category = 'Correctness'; finding = 'original'
            }
            $baseId = New-MetraInspectFindingIdentityRecord -Finding $baseFinding
            $pending = [PSCustomObject]@{
                findingFingerprintVersion = 1
                findingFingerprints       = @($baseId)
                critical                  = 0
                high                      = 1
                medium                    = 0
            }
            $current = @(
                $baseFinding
                [PSCustomObject]@{
                    file = 'scripts/touched.ps1'; severity = 'High'; category = 'Correctness'; finding = 'new in touch set'
                }
            )
            $r = Test-MetraInspectReviewRegressed -PendingBaseline $pending -CurrentFindings $current -TouchSet @('scripts/touched.ps1')
            $r.Regressed | Should -BeTrue
            $r.Reasons | Should -Contain 'TouchSetHighIncrease'
            $r.TouchHighBaseline | Should -Be 1
            $r.TouchHighCurrent | Should -Be 2
        }
    }

    It 'Test-MetraInspectReviewRegressed detects Critical increase outside touch set' {
        InModuleScope Metra {
            $baseFinding = [PSCustomObject]@{
                file = 'scripts/touched.ps1'; severity = 'High'; category = 'Correctness'; finding = 'original'
            }
            $baseId = New-MetraInspectFindingIdentityRecord -Finding $baseFinding
            $pending = [PSCustomObject]@{
                findingFingerprintVersion = 1
                findingFingerprints       = @($baseId)
                critical                  = 0
                high                      = 1
                medium                    = 0
            }
            $current = @(
                $baseFinding
                [PSCustomObject]@{
                    file = 'scripts/elsewhere.ps1'; severity = 'Critical'; category = 'Security'; finding = 'new critical'
                }
            )
            $r = Test-MetraInspectReviewRegressed -PendingBaseline $pending -CurrentFindings $current -TouchSet @('scripts/touched.ps1')
            $r.Regressed | Should -BeTrue
            $r.Reasons[0] | Should -Be 'CriticalIncrease'
        }
    }

    It 'Test-MetraInspectReviewRegressed detects affirmed issueKey still High' {
        InModuleScope Metra {
            $affirmed = [PSCustomObject]@{
                file = 'scripts/touched.ps1'; severity = 'High'; category = 'Correctness'; finding = 'must fix'
            }
            $affId = New-MetraInspectFindingIdentityRecord -Finding $affirmed
            $pending = [PSCustomObject]@{
                findingFingerprintVersion = 1
                findingFingerprints       = @($affId)
                critical                  = 0
                high                      = 1
                medium                    = 0
            }

            # Exact fingerprint remains High (counts unchanged) - still regresses via affirmed predicate.
            $rExact = Test-MetraInspectReviewRegressed `
                -PendingBaseline $pending `
                -CurrentFindings @($affirmed) `
                -TouchSet @('scripts/touched.ps1') `
                -AffirmedPackageFindings @($affId)
            $rExact.Regressed | Should -BeTrue
            $rExact.Reasons | Should -Be @('AffirmedFindingReappeared')
            $rExact.AffirmedReappearedCount | Should -Be 1

            # issueKey survives severity-bearing fingerprint change (High -> Critical).
            $elevated = [PSCustomObject]@{
                file = 'scripts/touched.ps1'; severity = 'Critical'; category = 'Correctness'; finding = 'must fix'
            }
            $elevId = New-MetraInspectFindingIdentityRecord -Finding $elevated
            $elevId.issueKey | Should -Be $affId.issueKey
            $elevId.fingerprint | Should -Not -Be $affId.fingerprint
            $rKey = Test-MetraInspectReviewRegressed `
                -PendingBaseline $pending `
                -CurrentFindings @($elevated) `
                -TouchSet @('scripts/touched.ps1') `
                -AffirmedPackageFindings @($affId)
            $rKey.Reasons | Should -Contain 'AffirmedFindingReappeared'
            $rKey.Reasons | Should -Contain 'CriticalIncrease'
        }
    }

    It 'Test-MetraInspectReviewRegressed accepts affirmed High downgraded to Medium without Medium population rise' {
        InModuleScope Metra {
            $affirmed = [PSCustomObject]@{
                file = 'scripts/touched.ps1'; severity = 'High'; category = 'Correctness'; finding = 'must fix'
            }
            $affId = New-MetraInspectFindingIdentityRecord -Finding $affirmed
            $pending = [PSCustomObject]@{
                findingFingerprintVersion = 1
                findingFingerprints       = @($affId)
                critical                  = 0
                high                      = 1
                medium                    = 0
            }
            $downgraded = [PSCustomObject]@{
                file = 'scripts/touched.ps1'; severity = 'Medium'; category = 'Correctness'; finding = 'must fix'
            }
            $r = Test-MetraInspectReviewRegressed `
                -PendingBaseline $pending `
                -CurrentFindings @($downgraded) `
                -TouchSet @('scripts/touched.ps1') `
                -AffirmedPackageFindings @($affId)
            # Demotion of the same issueKey does not count as TouchSetMediumIncrease.
            $r.Regressed | Should -BeFalse
            $r.TouchMediumCurrent | Should -Be 0
        }
    }

    It 'Test-MetraInspectReviewRegressed ignores New Medium inside touch set' {
        InModuleScope Metra {
            $base = [PSCustomObject]@{
                file = 'scripts/touched.ps1'; severity = 'Medium'; category = 'Correctness'; finding = 'old medium'
            }
            $baseId = New-MetraInspectFindingIdentityRecord -Finding $base
            $pending = [PSCustomObject]@{
                findingFingerprintVersion = 1
                findingFingerprints       = @($baseId)
                critical                  = 0
                high                      = 0
                medium                    = 1
            }
            $current = @(
                $base
                [PSCustomObject]@{
                    file = 'scripts/touched.ps1'; severity = 'Medium'; category = 'Correctness'; finding = 'brand new medium invent'
                }
            )
            $r = Test-MetraInspectReviewRegressed -PendingBaseline $pending -CurrentFindings $current -TouchSet @('scripts/touched.ps1')
            $r.Regressed | Should -BeFalse
            $r.Reasons | Should -BeNullOrEmpty
        }
    }

    It 'Test-MetraInspectReviewRegressed empty touch set falls back to baseline finding files only' {
        InModuleScope Metra {
            $baseFinding = [PSCustomObject]@{
                file = 'scripts/base-only.ps1'; severity = 'High'; category = 'Correctness'; finding = 'base'
            }
            $baseId = New-MetraInspectFindingIdentityRecord -Finding $baseFinding
            $pending = [PSCustomObject]@{
                findingFingerprintVersion = 1
                findingFingerprints       = @($baseId)
                critical                  = 0
                high                      = 1
                medium                    = 0
            }
            $touch = Get-MetraInspectReviewTouchSet -BaselineFindingFingerprints @($baseId) -PackageTargetFiles @() -CurrentDiffFiles @()
            $touch | Should -Contain 'scripts/base-only.ps1'
            $current = @(
                $baseFinding
                [PSCustomObject]@{
                    file = 'scripts/unrelated.ps1'; severity = 'High'; category = 'Correctness'; finding = 'noise'
                }
            )
            $r = Test-MetraInspectReviewRegressed -PendingBaseline $pending -CurrentFindings $current -TouchSet @()
            # empty TouchSet arg triggers fallback inside regressor via baseline fingerprints
            $r.Regressed | Should -BeFalse
            $r.TouchSet | Should -Contain 'scripts/base-only.ps1'
        }
    }

    It 'Get-MetraInspectReviewTouchSet uses content delta vs baseline not full dirty tree' {
        InModuleScope Metra {
            $root = Join-Path $env:TEMP ("metra-touch-" + [guid]::NewGuid().ToString('n'))
            $project = Join-Path $root 'project'
            $baseline = Join-Path $root 'baseline'
            New-Item -ItemType Directory -Path (Join-Path $project 'scripts') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $baseline 'scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $project 'scripts\touched.ps1') -Value 'changed' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $project 'scripts\untouched.ps1') -Value 'same' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $baseline 'scripts\touched.ps1') -Value 'original' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $baseline 'scripts\untouched.ps1') -Value 'same' -Encoding utf8
            try {
                $touch = Get-MetraInspectReviewTouchSet `
                    -ProjectRoot $project `
                    -BaselinePath $baseline `
                    -PackageTargetFiles @('scripts/touched.ps1') `
                    -BaselineManifest @('scripts/touched.ps1', 'scripts/untouched.ps1') `
                    -CurrentDiffFiles @(
                        [PSCustomObject]@{ path = 'scripts/touched.ps1' }
                        [PSCustomObject]@{ path = 'scripts/untouched.ps1' }
                        [PSCustomObject]@{ path = 'scripts/other.ps1' }
                    )
                $touch | Should -Contain 'scripts/touched.ps1'
                $touch | Should -Contain 'scripts/other.ps1'  # new vs manifest
                $touch | Should -Not -Contain 'scripts/untouched.ps1'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Test-MetraInspectReviewRegressed with no baseline finding files only Critical or affirmed can regress' {
        InModuleScope Metra {
            $pending = [PSCustomObject]@{
                findingFingerprintVersion = 1
                findingFingerprints       = @()
                critical                  = 0
                high                      = 0
                medium                    = 0
            }
            $current = @(
                [PSCustomObject]@{
                    file = 'scripts/anywhere.ps1'; severity = 'High'; category = 'Correctness'; finding = 'new high'
                }
            )
            $r = Test-MetraInspectReviewRegressed -PendingBaseline $pending -CurrentFindings $current -TouchSet @()
            $r.Regressed | Should -BeFalse
            $r.TouchSet.Count | Should -Be 0

            $rCrit = Test-MetraInspectReviewRegressed -PendingBaseline $pending -CurrentFindings @(
                [PSCustomObject]@{
                    file = 'scripts/anywhere.ps1'; severity = 'Critical'; category = 'Security'; finding = 'boom'
                }
            ) -TouchSet @()
            $rCrit.Regressed | Should -BeTrue
            $rCrit.Reasons | Should -Contain 'CriticalIncrease'
        }
    }

    It 'Test-MetraInspectReviewRegressed marks incompatible baseline for missing or unsupported version' {
        InModuleScope Metra {
            $legacy = [PSCustomObject]@{
                critical = 0
                high     = 1
                medium   = 0
            }
            $r = Test-MetraInspectReviewRegressed -PendingBaseline $legacy -CurrentFindings @() -TouchSet @()
            $r.IncompatibleBaseline | Should -BeTrue
            $r.Regressed | Should -BeFalse

            $v2 = [PSCustomObject]@{
                findingFingerprintVersion = 2
                findingFingerprints       = @()
                critical                  = 0
            }
            $r2 = Test-MetraInspectReviewRegressed -PendingBaseline $v2 -CurrentFindings @() -TouchSet @()
            $r2.IncompatibleBaseline | Should -BeTrue
        }
    }

    It 'Test-MetraInspectReviewRegressed Reasons follow locked precedence' {
        InModuleScope Metra {
            $affirmed = [PSCustomObject]@{
                file = 'scripts/touched.ps1'; severity = 'High'; category = 'Correctness'; finding = 'affirmed'
            }
            $lowBase = [PSCustomObject]@{
                file = 'scripts/touched.ps1'; severity = 'Low'; category = 'Correctness'; finding = 'will worsen'
            }
            $affId = New-MetraInspectFindingIdentityRecord -Finding $affirmed
            $lowId = New-MetraInspectFindingIdentityRecord -Finding $lowBase
            $pending = [PSCustomObject]@{
                findingFingerprintVersion = 1
                findingFingerprints       = @($affId, $lowId)
                critical                  = 0
                high                      = 1
                medium                    = 0
            }
            $current = @(
                $affirmed
                [PSCustomObject]@{
                    file = 'scripts/touched.ps1'; severity = 'High'; category = 'Correctness'; finding = 'extra high'
                }
                # Same issueKey as lowBase, raised to Medium - counts for TouchSetMediumIncrease (not New).
                [PSCustomObject]@{
                    file = 'scripts/touched.ps1'; severity = 'Medium'; category = 'Correctness'; finding = 'will worsen'
                }
                [PSCustomObject]@{
                    file = 'scripts/other.ps1'; severity = 'Critical'; category = 'Security'; finding = 'crit'
                }
            )
            $r = Test-MetraInspectReviewRegressed `
                -PendingBaseline $pending `
                -CurrentFindings $current `
                -TouchSet @('scripts/touched.ps1') `
                -AffirmedPackageFindings @($affId)
            $r.Reasons[0] | Should -Be 'CriticalIncrease'
            $r.Reasons[1] | Should -Be 'AffirmedFindingReappeared'
            $r.Reasons[2] | Should -Be 'TouchSetHighIncrease'
            $r.Reasons[3] | Should -Be 'TouchSetMediumIncrease'
        }
    }


    It 'Invoke-MetraInspectReviewLoop assess then verify reaches goal' {
        InModuleScope Metra {
            $stateRoot = Join-Path $env:TEMP ("metra-inspect-loop-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
            Mock Get-MetraInspectStateRoot { $stateRoot }
            Mock Resolve-MetraInspectProjectContext {
                [PSCustomObject]@{
                    Ok      = $true
                    Project = 'Metra'
                    Root    = (Get-MetraRoot)
                    Error   = $null
                }
            }

            Mock Get-MetraInspectReviewWorkingTreeInputHash { return 'after-fix-hash' }
            Mock Save-MetraInspectReviewGitBaseline {
                param($Root, $SlotKey, $RoundNum)
                $dir = Join-Path $stateRoot ("baselines/r{0}" -f $RoundNum)
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                [PSCustomObject]@{
                    Path      = $dir
                    GitHead   = 'abc'
                    InputHash = 'baseline-hash'
                    Manifest  = @('mock.txt')
                }
            }
            Mock Export-MetraInspectReviewFixQueue { Join-Path $stateRoot 'fix-queue.json' }

            $script:LoopCall = 0
            Mock Invoke-MetraInspectDiff {
                $script:LoopCall++
                $findings = if ($script:LoopCall -eq 1) {
                    @([PSCustomObject]@{ severity = 'High' }, [PSCustomObject]@{ severity = 'Medium' })
                }
                else {
                    @([PSCustomObject]@{ severity = 'Medium' })
                }
                [PSCustomObject]@{
                    findings   = $findings
                    provenance = [PSCustomObject]@{ reportPath = 'mock.json' }
                    Skipped    = $false
                }
            }

            try {
                $s1 = Invoke-MetraInspectReviewLoop -Name Metra -Reset
                $s1.active | Should -BeTrue
                $s1.phase | Should -Be 'AwaitingFix'
                $s1.LoopsUsed | Should -Be 1
                $s1.HighCount | Should -Be 1

                $s2 = Invoke-MetraInspectReviewLoop -Name Metra
                $s2.active | Should -BeFalse
                $s2.TerminationReason | Should -Be 'Goal achieved'
                $s2.FinalGrade | Should -Be 'A'
                $s2.LoopsUsed | Should -Be 1

                $historyPath = Join-Path $stateRoot 'review-loop-history.jsonl'
                Test-Path -LiteralPath $historyPath | Should -BeTrue
                $line = Get-Content -LiteralPath $historyPath -Tail 1
                $entry = $line | ConvertFrom-Json
                $entry.TerminationReason | Should -Be 'Goal achieved'
                $entry.FinalGrade | Should -Be 'A'
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Inspect engine selection' {
    It 'falls back to ask when inspect block is absent' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    engine             = 'ollama'
                    ollamaModel        = 'qwen2.5-coder:7b'
                    cursorModel        = 'composer-2.5'
                    cursorOptimizeFor  = 'cost'
                    enterpriseModel    = ''
                    llamacppModel      = ''
                }
            }
            Mock Get-MetraConfig { [PSCustomObject]@{ ask = [PSCustomObject]@{} } }
            $sel = Resolve-MetraInspectEngineSelection
            $sel.Engine | Should -Be 'ollama'
            $sel.RequestedModel | Should -Be 'qwen2.5-coder:7b'
            $sel.ConfigurationSource | Should -Be 'ask-fallback'
            $sel.FellBackToAsk | Should -BeTrue
        }
    }

    It 'uses inspect engine and cursor model when both set' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    engine             = 'ollama'
                    ollamaModel        = 'qwen2.5-coder:7b'
                    cursorModel        = 'composer-2.5'
                    cursorOptimizeFor  = 'cost'
                    enterpriseModel    = ''
                    llamacppModel      = ''
                }
            }
            Mock Get-MetraConfig {
                [PSCustomObject]@{
                    inspect = [PSCustomObject]@{
                        engine = 'cursor'
                        cursor = [PSCustomObject]@{ model = 'gemini-3.7-flash' }
                    }
                }
            }
            $sel = Resolve-MetraInspectEngineSelection
            $sel.Engine | Should -Be 'cursor'
            $sel.RequestedModel | Should -Be 'gemini-3.7-flash'
            $sel.ConfigurationSource | Should -Be 'inspect'
            $sel.FellBackToAsk | Should -BeFalse
        }
    }

    It 'mixed fallback: inspect.engine=cursor with ask.cursor.model when inspect.cursor.model omitted' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    engine             = 'ollama'
                    ollamaModel        = 'qwen2.5-coder:7b'
                    cursorModel        = 'composer-2.5'
                    cursorOptimizeFor  = 'cost'
                    enterpriseModel    = ''
                    llamacppModel      = ''
                }
            }
            Mock Get-MetraConfig {
                [PSCustomObject]@{
                    inspect = [PSCustomObject]@{
                        engine = 'cursor'
                    }
                }
            }
            $sel = Resolve-MetraInspectEngineSelection
            $sel.Engine | Should -Be 'cursor'
            $sel.RequestedModel | Should -Be 'composer-2.5'
            $sel.EngineSource | Should -Be 'inspect'
            $sel.ModelSource | Should -Be 'ask-fallback'
            $sel.FellBackToAsk | Should -BeTrue
            $sel.ConfigurationSource | Should -Be 'inspect'
        }
    }

    It 'ignores inspect.cursor.model when effective engine is ollama' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    engine             = 'ollama'
                    ollamaModel        = 'qwen2.5:7b'
                    cursorModel        = 'composer-2.5'
                    cursorOptimizeFor  = 'cost'
                    enterpriseModel    = ''
                    llamacppModel      = ''
                }
            }
            Mock Get-MetraConfig {
                [PSCustomObject]@{
                    inspect = [PSCustomObject]@{
                        cursor = [PSCustomObject]@{ model = 'gemini-3.7-flash' }
                    }
                }
            }
            $sel = Resolve-MetraInspectEngineSelection
            $sel.Engine | Should -Be 'ollama'
            $sel.RequestedModel | Should -Be 'qwen2.5:7b'
        }
    }

    It 'fails closed on unknown inspect.engine' {
        InModuleScope Metra {
            Mock Get-MetraAskSettings {
                [PSCustomObject]@{
                    engine             = 'ollama'
                    ollamaModel        = 'qwen2.5:7b'
                    cursorModel        = 'composer-2.5'
                    cursorOptimizeFor  = 'cost'
                    enterpriseModel    = ''
                    llamacppModel      = ''
                }
            }
            Mock Get-MetraConfig {
                [PSCustomObject]@{
                    inspect = [PSCustomObject]@{ engine = 'nope' }
                }
            }
            { Resolve-MetraInspectEngineSelection } | Should -Throw '*Unknown inspect.engine*'
        }
    }

    It 'does not synthesize resolvedModel in engineProvenance' {
        InModuleScope Metra {
            $sel = [PSCustomObject]@{
                Engine              = 'cursor'
                RequestedModel      = 'gemini-3.7-flash'
                ConfigurationSource = 'inspect'
                EngineSource        = 'inspect'
                ModelSource         = 'inspect'
            }
            $p = New-MetraInspectEngineProvenance -Selection $sel -ResolvedModel '' -CodingModel ''
            $p.requestedModel | Should -Be 'gemini-3.7-flash'
            [string]::IsNullOrWhiteSpace([string](Get-MetraProp -Object $p -Name 'resolvedModel' -Default '')) | Should -BeTrue
            $p.independence | Should -Be 'unknown'
        }
    }

    It 'classifies composer vs gemini as independent' {
        InModuleScope Metra {
            Resolve-MetraInspectIndependenceStatus -ReviewModel 'gemini-3.7-flash' -CodingModel 'composer-2.5' | Should -Be 'independent'
            Resolve-MetraInspectIndependenceStatus -ReviewModel 'qwen2.5:7b' -CodingModel 'qwen2.5-coder:7b' | Should -Be 'shared-family'
            Resolve-MetraInspectIndependenceStatus -ReviewModel 'gemini-3.7-flash' -CodingModel 'auto-smart/cost' | Should -Be 'unknown'
        }
    }
}

Describe 'Inspect fix dispatch queue hash' {
    It 'Assert-MetraInspectReviewFixQueueHashMatchesPackage throws when queue drifted' {
        InModuleScope Metra {
            $stateRoot = Join-Path $env:TEMP ("metra-fix-hash-" + [guid]::NewGuid().ToString('n'))
            $slotRoot = Join-Path $stateRoot 'Metra'
            New-Item -ItemType Directory -Path (Join-Path $slotRoot 'packages') -Force | Out-Null
            Mock Resolve-MetraInspectReviewSlotRoot {
                [PSCustomObject]@{ SlotRoot = $slotRoot; StateRoot = $stateRoot }
            }
            $queue = [PSCustomObject]@{
                round    = 1
                findings = @([PSCustomObject]@{
                        id = 'R1-F001'; severity = 'High'; file = 'a.ps1'; finding = 'x'; status = 'Affirmed'
                    })
            }
            $hash = Get-MetraInspectReviewFixQueueContentHash -Queue $queue
            $pkg = [PSCustomObject]@{ sourceQueueHash = $hash }
            Save-MetraInspectReviewFixQueue -SlotKey 'Metra' -Queue $queue -Confirm:$false
            { Assert-MetraInspectReviewFixQueueHashMatchesPackage -SlotKey 'Metra' -Package $pkg } | Should -Not -Throw

            $queue.findings[0].status = 'Deferred'
            Save-MetraInspectReviewFixQueue -SlotKey 'Metra' -Queue $queue -Confirm:$false
            { Assert-MetraInspectReviewFixQueueHashMatchesPackage -SlotKey 'Metra' -Package $pkg } | Should -Throw '*sourceQueueHash mismatch*'
        }
    }
}

Describe 'Inspect Bing gate slot scoping' {
    It 'reads inputHash from slot latest.json not the global last-diff pointer' {
        InModuleScope Metra {
            $stateRoot = Join-Path $env:TEMP ("metra-gate-" + [guid]::NewGuid().ToString('n'))
            Mock Get-MetraInspectStateRoot { $stateRoot }

            $metraSlot = Join-Path $stateRoot 'Metra'
            $otherSlot = Join-Path $stateRoot 'TicketTracker'
            New-Item -ItemType Directory -Path $metraSlot -Force | Out-Null
            New-Item -ItemType Directory -Path $otherSlot -Force | Out-Null

            $metraReport = [PSCustomObject]@{
                schemaVersion = 1
                mode          = 'diff'
                provenance    = [PSCustomObject]@{
                    project   = 'Metra'
                    inputHash = 'hash-metra-slot'
                }
                findings      = @()
            }
            $otherReport = [PSCustomObject]@{
                schemaVersion = 1
                mode          = 'diff'
                provenance    = [PSCustomObject]@{
                    project   = 'TicketTracker'
                    inputHash = 'hash-other-slot'
                }
                findings      = @()
            }
            ($metraReport | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $metraSlot 'latest.json') -Encoding UTF8
            ($otherReport | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $otherSlot 'latest.json') -Encoding UTF8

            $globalPointer = [ordered]@{
                mode             = 'diff'
                project          = 'TicketTracker'
                inputHash        = 'hash-other-slot'
                latestReportPath = (Join-Path $otherSlot 'latest.json')
            }
            ($globalPointer | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Join-Path $stateRoot 'last-diff.json') -Encoding UTF8

            try {
                $assess = Get-MetraInspectSlotDiffAssess -SlotKey 'Metra'
                $assess.inputHash | Should -Be 'hash-metra-slot'
                $assess.project | Should -Be 'Metra'
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'accepts case-insensitive slot project provenance' {
        InModuleScope Metra {
            $stateRoot = Join-Path $env:TEMP ("metra-gate-" + [guid]::NewGuid().ToString('n'))
            Mock Get-MetraInspectStateRoot { $stateRoot }
            $slot = Join-Path $stateRoot 'Metra'
            New-Item -ItemType Directory -Path $slot -Force | Out-Null
            $report = [PSCustomObject]@{
                schemaVersion = 1
                mode          = 'diff'
                provenance    = [PSCustomObject]@{ project = 'metra'; inputHash = 'hash-a' }
                findings      = @()
            }
            ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $slot 'latest.json') -Encoding UTF8
            try {
                { Get-MetraInspectSlotDiffAssess -SlotKey 'Metra' } | Should -Not -Throw
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Inspect Bing gate live hash invariant' {
    It 'allows commit when live assess and gate hashes match' {
        InModuleScope Metra {
            function Set-GateTestArtifacts {
                param([string]$StateRoot, [string]$SlotKey, [string]$AssessHash, [string]$GateHash = $null)
                $slot = Join-Path $StateRoot $SlotKey
                New-Item -ItemType Directory -Path $slot -Force | Out-Null
                $report = [PSCustomObject]@{
                    schemaVersion = 1; mode = 'diff'
                    provenance = [PSCustomObject]@{ project = $SlotKey; inputHash = $AssessHash }
                    findings = @()
                }
                ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $slot 'latest.json') -Encoding UTF8
                if ($null -ne $GateHash) {
                    $gate = [ordered]@{ schemaVersion = 1; project = $SlotKey; inputHash = $GateHash; affirmedAtUtc = '2026-08-31T00:00:00Z' }
                    ($gate | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Join-Path $slot 'bing-gate.json') -Encoding UTF8
                }
            }
            $stateRoot = Join-Path $env:TEMP ("metra-triad-" + [guid]::NewGuid().ToString('n'))
            Mock Get-MetraInspectStateRoot { $stateRoot }
            Set-GateTestArtifacts -StateRoot $stateRoot -SlotKey 'Metra' -AssessHash 'hash-a' -GateHash 'hash-a'
            try {
                $triad = Test-MetraInspectBingGateCommitAllowed -SlotKey 'Metra' -LiveInputHash 'hash-a'
                $triad.allowed | Should -BeTrue
                $triad.reason | Should -Be 'ok'
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'blocks when live hash differs from assessment' {
        InModuleScope Metra {
            function Set-GateTestArtifacts {
                param([string]$StateRoot, [string]$SlotKey, [string]$AssessHash, [string]$GateHash = $null)
                $slot = Join-Path $StateRoot $SlotKey
                New-Item -ItemType Directory -Path $slot -Force | Out-Null
                $report = [PSCustomObject]@{
                    schemaVersion = 1; mode = 'diff'
                    provenance = [PSCustomObject]@{ project = $SlotKey; inputHash = $AssessHash }
                    findings = @()
                }
                ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $slot 'latest.json') -Encoding UTF8
                if ($null -ne $GateHash) {
                    $gate = [ordered]@{ schemaVersion = 1; project = $SlotKey; inputHash = $GateHash; affirmedAtUtc = '2026-08-31T00:00:00Z' }
                    ($gate | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Join-Path $slot 'bing-gate.json') -Encoding UTF8
                }
            }
            $stateRoot = Join-Path $env:TEMP ("metra-triad-" + [guid]::NewGuid().ToString('n'))
            Mock Get-MetraInspectStateRoot { $stateRoot }
            Set-GateTestArtifacts -StateRoot $stateRoot -SlotKey 'Metra' -AssessHash 'hash-a' -GateHash 'hash-a'
            try {
                $triad = Test-MetraInspectBingGateCommitAllowed -SlotKey 'Metra' -LiveInputHash 'hash-b'
                $triad.allowed | Should -BeFalse
                $triad.reason | Should -Be 'live-assess-mismatch'
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'blocks when live hash differs from gate affirmation' {
        InModuleScope Metra {
            function Set-GateTestArtifacts {
                param([string]$StateRoot, [string]$SlotKey, [string]$AssessHash, [string]$GateHash = $null)
                $slot = Join-Path $StateRoot $SlotKey
                New-Item -ItemType Directory -Path $slot -Force | Out-Null
                $report = [PSCustomObject]@{
                    schemaVersion = 1; mode = 'diff'
                    provenance = [PSCustomObject]@{ project = $SlotKey; inputHash = $AssessHash }
                    findings = @()
                }
                ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $slot 'latest.json') -Encoding UTF8
                if ($null -ne $GateHash) {
                    $gate = [ordered]@{ schemaVersion = 1; project = $SlotKey; inputHash = $GateHash; affirmedAtUtc = '2026-08-31T00:00:00Z' }
                    ($gate | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Join-Path $slot 'bing-gate.json') -Encoding UTF8
                }
            }
            $stateRoot = Join-Path $env:TEMP ("metra-triad-" + [guid]::NewGuid().ToString('n'))
            Mock Get-MetraInspectStateRoot { $stateRoot }
            Set-GateTestArtifacts -StateRoot $stateRoot -SlotKey 'Metra' -AssessHash 'hash-b' -GateHash 'hash-a'
            try {
                $triad = Test-MetraInspectBingGateCommitAllowed -SlotKey 'Metra' -LiveInputHash 'hash-b'
                $triad.allowed | Should -BeFalse
                $triad.reason | Should -Be 'live-gate-mismatch'
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'blocks when assessment and gate hashes diverge' {
        InModuleScope Metra {
            function Set-GateTestArtifacts {
                param([string]$StateRoot, [string]$SlotKey, [string]$AssessHash, [string]$GateHash = $null)
                $slot = Join-Path $StateRoot $SlotKey
                New-Item -ItemType Directory -Path $slot -Force | Out-Null
                $report = [PSCustomObject]@{
                    schemaVersion = 1; mode = 'diff'
                    provenance = [PSCustomObject]@{ project = $SlotKey; inputHash = $AssessHash }
                    findings = @()
                }
                ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $slot 'latest.json') -Encoding UTF8
                if ($null -ne $GateHash) {
                    $gate = [ordered]@{ schemaVersion = 1; project = $SlotKey; inputHash = $GateHash; affirmedAtUtc = '2026-08-31T00:00:00Z' }
                    ($gate | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Join-Path $slot 'bing-gate.json') -Encoding UTF8
                }
            }
            $stateRoot = Join-Path $env:TEMP ("metra-triad-" + [guid]::NewGuid().ToString('n'))
            Mock Get-MetraInspectStateRoot { $stateRoot }
            Set-GateTestArtifacts -StateRoot $stateRoot -SlotKey 'Metra' -AssessHash 'hash-a' -GateHash 'hash-b'
            try {
                $triad = Test-MetraInspectBingGateCommitAllowed -SlotKey 'Metra' -LiveInputHash 'hash-a'
                $triad.allowed | Should -BeFalse
                $triad.reason | Should -Be 'live-gate-mismatch'
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'pre-commit blocks after post-affirmation working-tree drift' {
        InModuleScope Metra {
            function Set-GateTestArtifacts {
                param([string]$StateRoot, [string]$SlotKey, [string]$AssessHash, [string]$GateHash = $null)
                $slot = Join-Path $StateRoot $SlotKey
                New-Item -ItemType Directory -Path $slot -Force | Out-Null
                $report = [PSCustomObject]@{
                    schemaVersion = 1; mode = 'diff'
                    provenance = [PSCustomObject]@{ project = $SlotKey; inputHash = $AssessHash }
                    findings = @()
                }
                ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $slot 'latest.json') -Encoding UTF8
                if ($null -ne $GateHash) {
                    $gate = [ordered]@{ schemaVersion = 1; project = $SlotKey; inputHash = $GateHash; affirmedAtUtc = '2026-08-31T00:00:00Z' }
                    ($gate | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Join-Path $slot 'bing-gate.json') -Encoding UTF8
                }
            }
            $stateRoot = Join-Path $env:TEMP ("metra-pre-" + [guid]::NewGuid().ToString('n'))
            Mock Get-MetraInspectStateRoot { $stateRoot }
            Set-GateTestArtifacts -StateRoot $stateRoot -SlotKey 'Metra' -AssessHash 'hash-a' -GateHash 'hash-a'
            Mock Resolve-MetraInspectProjectContext {
                [PSCustomObject]@{ Ok = $true; Project = 'Metra'; Root = (Get-MetraRoot); Error = $null }
            }
            Mock Get-MetraInspectCurrentDiffInput {
                [PSCustomObject]@{ project = 'Metra'; root = (Get-MetraRoot); inputHash = 'hash-b'; empty = $false }
            }
            try {
                { Invoke-MetraInspectPreCommitHook -Name 'Metra' } | Should -Throw '*live-assess-mismatch*'
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'prepare-bing does not reuse completed session when live hash drifted' {
        InModuleScope Metra {
            Mock Resolve-MetraInspectProjectContext {
                [PSCustomObject]@{ Ok = $true; Project = 'Metra'; Root = (Get-MetraRoot); Error = $null }
            }
            Mock Get-MetraInspectReviewLoopState {
                [PSCustomObject]@{
                    active = $false; TerminationReason = 'Goal achieved'
                    CriticalCount = 0; HighCount = 0; MediumCount = 0; LowCount = 0
                }
            }
            Mock Get-MetraInspectCurrentDiffInput {
                [PSCustomObject]@{ project = 'Metra'; root = (Get-MetraRoot); inputHash = 'hash-b'; empty = $false }
            }
            Mock Get-MetraInspectSlotDiffAssess {
                [PSCustomObject]@{ slotKey = 'Metra'; inputHash = 'hash-a'; latestReportPath = 'x' }
            }
            Mock Invoke-MetraInspectReviewLoop {
                [PSCustomObject]@{
                    active = $false; TerminationReason = 'Goal achieved'
                    CriticalCount = 0; HighCount = 0; MediumCount = 2; LowCount = 1
                }
            }
            Mock Invoke-MetraInspectAutoPack {
                [PSCustomObject]@{ ok = $true; packPath = 'C:\pack.md' }
            }

            $result = Invoke-MetraInspectPrepareForBing -Name 'Metra'
            [bool](Get-MetraProp -Object $result -Name 'reusedSession' -Default $false) | Should -Be $false
            $result.project | Should -Be 'Metra'
        }
    }

    It 'gate affirm rejects when live hash differs from slot assessment' {
        InModuleScope Metra {
            function Set-GateTestArtifacts {
                param([string]$StateRoot, [string]$SlotKey, [string]$AssessHash, [string]$GateHash = $null)
                $slot = Join-Path $StateRoot $SlotKey
                New-Item -ItemType Directory -Path $slot -Force | Out-Null
                $report = [PSCustomObject]@{
                    schemaVersion = 1; mode = 'diff'
                    provenance = [PSCustomObject]@{ project = $SlotKey; inputHash = $AssessHash }
                    findings = @()
                }
                ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $slot 'latest.json') -Encoding UTF8
            }
            $stateRoot = Join-Path $env:TEMP ("metra-aff-" + [guid]::NewGuid().ToString('n'))
            Mock Get-MetraInspectStateRoot { $stateRoot }
            Set-GateTestArtifacts -StateRoot $stateRoot -SlotKey 'Metra' -AssessHash 'hash-a'
            Mock Resolve-MetraInspectProjectContext {
                [PSCustomObject]@{ Ok = $true; Project = 'Metra'; Root = (Get-MetraRoot); Error = $null }
            }
            Mock Get-MetraInspectCurrentDiffInput {
                [PSCustomObject]@{ project = 'Metra'; root = (Get-MetraRoot); inputHash = 'hash-b'; empty = $false }
            }
            try {
                { Set-MetraInspectBingGateAffirm -Name 'Metra' -Confirm:$false } |
                    Should -Throw '*Working tree changed since Inspect assessment*'
            }
            finally {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Inspect hooks install' {
    It 'throws for an invalid named project instead of installing against cwd' {
        InModuleScope Metra {
            Mock Resolve-MetraInspectProjectContext {
                [PSCustomObject]@{ Ok = $false; Project = $null; Root = $null; Error = "Unknown project 'Nope'." }
            }
            { Show-MetraInspectCli -Rest @('hooks', 'install') -Name @('Nope') } |
                Should -Throw "*Unknown project 'Nope'*"
        }
    }
}

Describe 'Inspect git config metra.root' {
    It 'returns the first trimmed metra.root value' {
        InModuleScope Metra {
            $repo = Join-Path $env:TEMP ("metra-cfg-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            Push-Location $repo
            try {
                git init 2>$null | Out-Null
                git config metra.root "  C:\Metra  " 2>$null | Out-Null
                git config --add metra.root 'C:\Other' 2>$null | Out-Null
                Get-MetraGitConfiguredMetraRoot -RepoRoot $repo | Should -Be 'C:\Metra'
            }
            finally {
                Pop-Location
                Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
