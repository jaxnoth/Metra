# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Audit.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Audit README trigger extraction' {
    It 'caps README text before regex extraction' {
        InModuleScope Metra {
            $pad = 'aaaa ' * 50000
            $late = 'uniquelatetokenxyz'
            $early = 'uniqueearlytokenxyz'
            $text = "$early $pad $late"
            $text.Length | Should -BeGreaterThan 200000
            $hints = @(Get-MetraAuditSuggestedTriggersFromText -Text $text -MaxChars 200000)
            $hints | Should -Contain 'uniqueearlytokenxyz'
            $hints | Should -Not -Contain 'uniquelatetokenxyz'
        }
    }

    It 'returns empty for blank README text' {
        InModuleScope Metra {
            @(Get-MetraAuditSuggestedTriggersFromText -Text '') | Should -HaveCount 0
            @(Get-MetraAuditSuggestedTriggersFromText -Text $null) | Should -HaveCount 0
        }
    }
}

Describe 'Audit drift metric split' {
    It 'counts DriftProjects once when one project has multiple drift findings' {
        InModuleScope Metra {
            $script:auditFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("metra-audit-" + [guid]::NewGuid().ToString('n'))
            $script:auditFixtureWork = Join-Path $script:auditFixtureRoot 'Work'
            $script:auditFixtureProj = Join-Path $script:auditFixtureWork 'MultiDrift'
            New-Item -ItemType Directory -Path $script:auditFixtureProj -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:auditFixtureProj 'node_modules') -Force | Out-Null
            try {
                Mock Get-MetraRoots {
                    return @(
                        [pscustomobject]@{
                            Name   = 'work'
                            Path   = $script:auditFixtureWork
                            Audit  = 'full'
                            Exists = $true
                        }
                    )
                }
                Mock Get-MetraProjectRegistry {
                    return [pscustomobject]@{
                        projects = @(
                            [pscustomobject]@{
                                name           = 'MultiDrift'
                                entry          = 'AGENTS.md'
                                excludePaths   = @('node_modules')
                                preferredPaths = @('AGENTS.md')
                                optional       = $false
                                source         = 'synthetic'
                            }
                        )
                    }
                }
                Mock Resolve-MetraProjectSet {
                    return @(
                        [pscustomobject]@{
                            Name = 'MultiDrift'
                            Path = $script:auditFixtureProj
                            Root = 'work'
                        }
                    )
                }
                Mock Get-MetraRegistryProject {
                    param($Registry, $Name)
                    return @($Registry.projects | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
                }
                Mock Get-MetraRouteMetadataIssues { @() }

                $result = Invoke-MetraProjectContextAudit -Quiet | Select-Object -Last 1
                $result.DriftProjects | Should -Be 1
                $result.DriftFindings | Should -BeGreaterThan 1
                $result.DriftCount | Should -Be $result.DriftFindings
                @($result.Reports | Where-Object { $_.Drift }).Count | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $script:auditFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Variable -Name auditFixtureRoot, auditFixtureWork, auditFixtureProj -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }

    It 'counts registry-missing as DriftProjects and DriftFindings' {
        InModuleScope Metra {
            Mock Get-MetraRoots { @() }
            Mock Resolve-MetraProjectSet { @() }
            Mock Get-MetraRouteMetadataIssues { @() }
            Mock Get-MetraProjectRegistry {
                return [pscustomobject]@{
                    projects = @(
                        [pscustomobject]@{
                            name     = 'GhostProject'
                            optional = $false
                            source   = 'synthetic'
                        }
                    )
                }
            }

            $result = Invoke-MetraProjectContextAudit -Quiet | Select-Object -Last 1
            $result.DriftProjects | Should -Be 1
            $result.DriftFindings | Should -Be 1
            $result.DriftCount | Should -Be 1
        }
    }

    It 'does not count optional registry-missing as drift' {
        InModuleScope Metra {
            Mock Get-MetraRoots { @() }
            Mock Resolve-MetraProjectSet { @() }
            Mock Get-MetraRouteMetadataIssues { @() }
            Mock Get-MetraProjectRegistry {
                return [pscustomobject]@{
                    projects = @(
                        [pscustomobject]@{
                            name        = 'OptionalGhost'
                            optional    = $true
                            whenMissing = 'Install when needed.'
                            source      = 'synthetic'
                        }
                    )
                }
            }

            $result = Invoke-MetraProjectContextAudit -Quiet | Select-Object -Last 1
            $result.DriftProjects | Should -Be 0
            $result.DriftFindings | Should -Be 0
        }
    }
}

Describe 'Audit AGENTS line budget' {
    It 'returns OK when AGENTS.md is under budget' {
        InModuleScope Metra {
            $dir = Join-Path ([IO.Path]::GetTempPath()) ("metra-agents-ok-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            @('line1','line2','line3') | Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') -Encoding utf8
            try {
                $audit = Get-MetraAgentsLineAuditForPath -AgentsPath (Join-Path $dir 'AGENTS.md') -Budget 100
                $audit.Status | Should -Be 'OK'
                $audit.LineCount | Should -Be 3
            }
            finally {
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'returns WARN when AGENTS.md exceeds budget' {
        InModuleScope Metra {
            $dir = Join-Path ([IO.Path]::GetTempPath()) ("metra-agents-warn-" + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            1..120 | ForEach-Object { "line $_" } | Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') -Encoding utf8
            try {
                $audit = Get-MetraAgentsLineAuditForPath -AgentsPath (Join-Path $dir 'AGENTS.md') -Budget 100
                $audit.Status | Should -Be 'WARN'
                $audit.LineCount | Should -Be 120
            }
            finally {
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'honors metra.config.json audit.agentsLineBudget' {
        InModuleScope Metra {
            Mock Get-MetraConfig {
                return [pscustomobject]@{
                    audit = [pscustomobject]@{ agentsLineBudget = 50 }
                }
            }
            Get-MetraAgentsLineBudget | Should -Be 50
        }
    }

    It 'does not count docs/playbooks toward AGENTS budget' {
        InModuleScope Metra {
            $dir = Join-Path ([IO.Path]::GetTempPath()) ("metra-playbook-" + [guid]::NewGuid().ToString('n'))
            $playDir = Join-Path $dir 'docs\playbooks'
            New-Item -ItemType Directory -Path $playDir -Force | Out-Null
            1..200 | ForEach-Object { "playbook line $_" } | Set-Content -LiteralPath (Join-Path $playDir 'big.md') -Encoding utf8
            1..10 | ForEach-Object { "stub line $_" } | Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') -Encoding utf8
            try {
                $audit = Get-MetraAgentsLineAuditForPath -AgentsPath (Join-Path $dir 'AGENTS.md') -Budget 100
                $audit.Status | Should -Be 'OK'
                $audit.LineCount | Should -Be 10
            }
            finally {
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Context Footprint Estimate ignores alwaysApply false rules' {
        InModuleScope Metra {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-footprint-" + [guid]::NewGuid().ToString('n'))
            $proj = Join-Path $root 'SampleProj'
            $rulesDir = Join-Path $proj '.cursor\rules'
            New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
            @(
                '---'
                'alwaysApply: false'
                '---'
                'requestable only'
            ) | Set-Content -LiteralPath (Join-Path $rulesDir 'requestable.mdc') -Encoding utf8
            'stub' | Set-Content -LiteralPath (Join-Path $proj 'AGENTS.md') -Encoding utf8
            try {
                Mock Get-MetraRoot { return $root }
                $estimate = Get-MetraContextFootprintEstimate -Projects @(
                    [pscustomobject]@{ Name = 'SampleProj'; Path = $proj; Root = 'work' }
                )
                $estimate.AlwaysApplyRulesLines | Should -Be 0
                $estimate.MountedAgentsLines | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'includes AGENTS WARN rows in DriftOnly output' {
        InModuleScope Metra {
            $script:auditFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("metra-agents-drift-" + [guid]::NewGuid().ToString('n'))
            $script:auditFixtureWork = Join-Path $script:auditFixtureRoot 'Work'
            $script:auditFixtureProj = Join-Path $script:auditFixtureWork 'FatAgents'
            New-Item -ItemType Directory -Path $script:auditFixtureProj -Force | Out-Null
            1..120 | ForEach-Object { "line $_" } | Set-Content -LiteralPath (Join-Path $script:auditFixtureProj 'AGENTS.md') -Encoding utf8
            'readme' | Set-Content -LiteralPath (Join-Path $script:auditFixtureProj 'README.md') -Encoding utf8
            '.git' | Set-Content -LiteralPath (Join-Path $script:auditFixtureProj '.cursorignore') -Encoding utf8
            try {
                Mock Get-MetraRoots {
                    return @([pscustomobject]@{ Name = 'work'; Path = $script:auditFixtureWork; Audit = 'full'; Exists = $true })
                }
                Mock Get-MetraProjectRegistry {
                    return [pscustomobject]@{
                        projects = @(
                            [pscustomobject]@{
                                name           = 'FatAgents'
                                entry          = 'AGENTS.md'
                                excludePaths   = @()
                                preferredPaths = @('AGENTS.md')
                                optional       = $false
                                source         = 'synthetic'
                            }
                        )
                    }
                }
                Mock Resolve-MetraProjectSet {
                    return @([pscustomobject]@{ Name = 'FatAgents'; Path = $script:auditFixtureProj; Root = 'work' })
                }
                Mock Get-MetraRegistryProject {
                    param($Registry, $Name)
                    return @($Registry.projects | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
                }
                Mock Get-MetraRouteMetadataIssues { @() }

                $result = Invoke-MetraProjectContextAudit -DriftOnly -Quiet | Select-Object -Last 1
                $result.Reports[0].AgentsLineStatus | Should -Be 'WARN'
                $result.ContextFootprintEstimate.MountedAgentsLines | Should -Be 120
            }
            finally {
                Remove-Item -LiteralPath $script:auditFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
