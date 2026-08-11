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
