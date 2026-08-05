# Requires Pester 5+ (pwsh recommended).
# Run: pwsh -NoProfile -File .\tests\Invoke-MetraTests.ps1

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Route metadata audit' {
    BeforeEach {
        InModuleScope Metra {
            Mock Get-MetraRoutingStopWords {
                return [System.Collections.Generic.HashSet[string]]::new(
                    [string[]]@('the', 'and', 'or'),
                    [StringComparer]::OrdinalIgnoreCase
                )
            }

            Mock Get-MetraProjectRegistry {
                return [pscustomobject]@{
                    projects = @(
                        [pscustomobject]@{
                            name        = 'empty-purpose'
                            purpose     = '   '
                            triggers    = @('valid')
                            optional    = $false
                            whenMissing = $null
                            source      = 'synthetic'
                        },
                        [pscustomobject]@{
                            name        = 'empty-triggers'
                            purpose     = 'Has purpose'
                            triggers    = @()
                            optional    = $false
                            whenMissing = $null
                            source      = 'synthetic'
                        },
                        [pscustomobject]@{
                            name        = 'blank-triggers'
                            purpose     = 'Has purpose'
                            triggers    = @('', '   ')
                            optional    = $false
                            whenMissing = $null
                            source      = 'synthetic'
                        },
                        [pscustomobject]@{
                            name        = 'optional-no-whenmissing'
                            purpose     = 'Has purpose'
                            triggers    = @('optional route')
                            optional    = $true
                            whenMissing = ' '
                            source      = 'synthetic'
                        },
                        [pscustomobject]@{
                            name        = 'stop-word-trigger'
                            purpose     = 'Has purpose'
                            triggers    = @('the')
                            optional    = $false
                            whenMissing = $null
                            source      = 'synthetic'
                        },
                        [pscustomobject]@{
                            name        = 'single-char-trigger'
                            purpose     = 'Has purpose'
                            triggers    = @('x')
                            optional    = $false
                            whenMissing = $null
                            source      = 'synthetic'
                        },
                        [pscustomobject]@{
                            name        = 'healthy-route'
                            purpose     = 'Healthy purpose'
                            triggers    = @('ops desk', 'healthy route')
                            optional    = $true
                            whenMissing = 'Clone the sibling project.'
                            source      = 'synthetic'
                        }
                    )
                }
            }
        }
    }

    It 'reports empty purpose' {
        InModuleScope Metra {
            $issues = @(Get-MetraRouteMetadataIssues)
            $issues.Issue | Should -Contain 'EmptyPurpose'
        }
    }

    It 'reports empty triggers' {
        InModuleScope Metra {
            $issues = @(Get-MetraRouteMetadataIssues)
            $issues.Issue | Should -Contain 'EmptyTriggers'
            @($issues | Where-Object { $_.Route -eq 'blank-triggers' -and $_.Issue -eq 'EmptyTriggers' }).Count |
                Should -Be 1
        }
    }

    It 'reports optional route missing whenMissing guidance' {
        InModuleScope Metra {
            $issues = @(Get-MetraRouteMetadataIssues)
            $issues.Issue | Should -Contain 'OptionalRouteMissingWhenMissing'
        }
    }

    It 'reports stop-word trigger' {
        InModuleScope Metra {
            $issues = @(Get-MetraRouteMetadataIssues)
            $issues.Issue | Should -Contain 'StopWordTrigger'
        }
    }

    It 'reports single-character trigger' {
        InModuleScope Metra {
            $issues = @(Get-MetraRouteMetadataIssues)
            $issues.Issue | Should -Contain 'SingleCharacterTrigger'
        }
    }

    It 'does not flag healthy multi-word triggers as stop words' {
        InModuleScope Metra {
            $issues = @(Get-MetraRouteMetadataIssues)
            @($issues | Where-Object { $_.Route -eq 'healthy-route' }).Count | Should -Be 0
        }
    }

    It 'does not report metadata findings as drift' {
        InModuleScope Metra {
            $result = Test-MetraProjectContext -MetadataOnly -Quiet
            $result.DriftCount | Should -Be 0
            $result.MetadataOnly | Should -BeTrue
            @($result.MetadataFindings).Count | Should -BeGreaterThan 0
            $result.MetadataCount | Should -Be @($result.MetadataFindings).Count
        }
    }

    It 'MetadataOnly with DriftOnly still exits success for metadata advisories' {
        InModuleScope Metra {
            $global:LASTEXITCODE = 99
            $null = Test-MetraProjectContext -MetadataOnly -DriftOnly -Quiet
            $global:LASTEXITCODE | Should -Be 0
        }
    }
}
