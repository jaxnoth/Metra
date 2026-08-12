# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Azdo.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'AzDO name normalization' {
    It 'collapses case, spaces, hyphens, underscores' {
        InModuleScope Metra {
            Normalize-MetraAzdoName -Name 'Colleague Migration' | Should -Be 'colleaguemigration'
            Normalize-MetraAzdoName -Name 'Colleague-Migration' | Should -Be 'colleaguemigration'
            Normalize-MetraAzdoName -Name 'COLLEAGUE_MIGRATION' | Should -Be 'colleaguemigration'
        }
    }
}

Describe 'AzDO wildcard match' {
    It 'matches idea repo patterns' {
        InModuleScope Metra {
            Test-MetraAzdoWildcardMatch -Pattern '*Experience*' -Value 'IWU.Experience.Portal' | Should -BeTrue
            Test-MetraAzdoWildcardMatch -Pattern '*Ethos*' -Value 'EthosIntegration' | Should -BeTrue
            Test-MetraAzdoWildcardMatch -Pattern '*Ethos*' -Value 'Colleague' | Should -BeFalse
        }
    }
}

Describe 'AzDO gap buckets' {
    It 'classifies registry, disk, and AzDO repos' {
        InModuleScope Metra {
            $mappings = @(
                [PSCustomObject]@{
                    RegistryName   = 'Colleague'
                    NormalizedName = 'colleague'
                    AzdoProject    = 'PowerShell'
                    AzdoRepo       = 'Colleague'
                    RemoteUrl      = ''
                    CheckoutPath   = 'C:\Projects\Colleague'
                    OnDisk         = $true
                },
                [PSCustomObject]@{
                    RegistryName   = 'MissingLocal'
                    NormalizedName = 'missinglocal'
                    AzdoProject    = ''
                    AzdoRepo       = 'MissingLocal'
                    RemoteUrl      = ''
                    CheckoutPath   = $null
                    OnDisk         = $false
                },
                [PSCustomObject]@{
                    RegistryName   = 'LocalOnly'
                    NormalizedName = 'localonly'
                    AzdoProject    = ''
                    AzdoRepo       = ''
                    RemoteUrl      = ''
                    CheckoutPath   = 'C:\Projects\LocalOnly'
                    OnDisk         = $true
                }
            )

            $repos = @(
                [PSCustomObject]@{
                    id             = '1'
                    name           = 'Colleague'
                    project        = [PSCustomObject]@{ name = 'PowerShell' }
                    defaultBranch  = 'refs/heads/main'
                },
                [PSCustomObject]@{
                    id             = '2'
                    name           = 'MissingLocal'
                    project        = [PSCustomObject]@{ name = 'PowerShell' }
                    defaultBranch  = 'refs/heads/main'
                },
                [PSCustomObject]@{
                    id             = '3'
                    name           = 'AzdoOnly'
                    project        = [PSCustomObject]@{ name = 'PowerShell' }
                    defaultBranch  = 'refs/heads/main'
                }
            )

            $gaps = Compare-MetraAzdoGaps -RegistryMappings $mappings -Repos $repos -ListLimit 10
            $gaps.MatchedPresentCount | Should -BeGreaterThan 0
            $gaps.InRegistryMissingCheckoutCount | Should -Be 1
            $gaps.InAzdoNotInRegistryCount | Should -Be 1
        }
    }
}

Describe 'AzDO retrieval caps' {
    It 'truncates file content over maxFileChars' {
        InModuleScope Metra {
            $long = 'x' * 500
            $out = Invoke-MetraAzdoTruncateText -Text $long -MaxChars 100
            $out.Length | Should -BeLessOrEqual 100
            $out | Should -Match 'truncated by maxFileChars cap'
        }
    }
}

Describe 'AzDO ambiguity guard' {
    It 'flags multiple plausible repo matches without explicit repo' {
        InModuleScope Metra {
            $repos = @(
                [PSCustomObject]@{ id = '1'; name = 'Colleague'; project = [PSCustomObject]@{ name = 'PowerShell' } },
                [PSCustomObject]@{ id = '2'; name = 'Colleague-Migration'; project = [PSCustomObject]@{ name = 'PowerShell' } },
                [PSCustomObject]@{ id = '3'; name = 'ColleagueReports'; project = [PSCustomObject]@{ name = 'PowerShell' } }
            )
            Test-MetraAzdoAmbiguousRepoMatch -QueryName 'Colleague' -Repos $repos | Should -BeTrue
            Test-MetraAzdoAmbiguousRepoMatch -QueryName 'Colleague' -Repos $repos -ExplicitRepo 'Colleague' | Should -BeFalse
        }
    }
}

Describe 'Ask AzDO remote gating' {
    It 'uses remote when checkout missing' {
        InModuleScope Metra {
            Mock Get-MetraAskRouteCwd { return 'C:\Missing' }
            Mock Get-MetraProjects { return @() }
            $gate = Test-MetraAskAzdoRemoteGating -Prompt 'How does Colleague WAGC work?' -Where 'Colleague'
            $gate.UseRemote | Should -BeTrue
            $gate.Reason | Should -Be 'missing_checkout'
        }
    }

    It 'stays local without remote flag or keywords when checkout exists' {
        InModuleScope Metra {
            Mock Get-MetraAskRouteCwd { return $TestDrive }
            Mock Get-MetraProjects { return @([PSCustomObject]@{ Name = 'Colleague'; Path = $TestDrive }) }
            New-Item -ItemType File -Path (Join-Path $TestDrive 'AGENTS.md') -Force | Out-Null
            $gate = Test-MetraAskAzdoRemoteGating -Prompt 'How does Colleague WAGC work?' -Where 'Colleague'
            $gate.UseRemote | Should -BeFalse
        }
    }

    It 'allows remote on keyword even with local checkout' {
        InModuleScope Metra {
            Mock Get-MetraAskRouteCwd { return $TestDrive }
            Mock Get-MetraProjects { return @([PSCustomObject]@{ Name = 'Colleague'; Path = $TestDrive }) }
            New-Item -ItemType File -Path (Join-Path $TestDrive 'AGENTS.md') -Force | Out-Null
            $gate = Test-MetraAskAzdoRemoteGating -Prompt 'What is latest in azure devops for Colleague?' -Where 'Colleague'
            $gate.UseRemote | Should -BeTrue
            $gate.Reason | Should -Be 'prompt_keyword'
        }
    }
}

Describe 'AzDO PAT precedence' {
    It 'prefers Process over User and Machine' {
        InModuleScope Metra {
            $r = Resolve-MetraAzdoPatPrecedence -ProcessPat 'from-process' -UserPat 'from-user' -MachinePat 'from-machine'
            $r.Pat | Should -Be 'from-process'
            $r.Scope | Should -Be 'Process'
        }
    }

    It 'prefers User when Process is absent' {
        InModuleScope Metra {
            $r = Resolve-MetraAzdoPatPrecedence -ProcessPat '' -UserPat 'from-user' -MachinePat 'from-machine'
            $r.Pat | Should -Be 'from-user'
            $r.Scope | Should -Be 'User'
        }
    }

    It 'prefers Machine when Process and User are absent' {
        InModuleScope Metra {
            $r = Resolve-MetraAzdoPatPrecedence -ProcessPat '' -UserPat '' -MachinePat 'from-machine'
            $r.Pat | Should -Be 'from-machine'
            $r.Scope | Should -Be 'Machine'
        }
    }

    It 'treats blank PAT strings as absent and falls through to the next scope' {
        InModuleScope Metra {
            $r = Resolve-MetraAzdoPatPrecedence -ProcessPat '   ' -UserPat 'from-user' -MachinePat 'from-machine'
            $r.Pat | Should -Be 'from-user'
            $r.Scope | Should -Be 'User'
            Resolve-MetraAzdoPatPrecedence -ProcessPat '' -UserPat '  ' -MachinePat '' | Should -BeNullOrEmpty
        }
    }

    It 'uses local JSON only when all env scopes are absent' {
        InModuleScope Metra {
            Mock Get-MetraAzdoPatFromEnvironment { return $null }
            $cfgPath = Join-Path $TestDrive 'azdo.local.json'
            (@{ pat = 'file-pat'; organization = 'indwes' } | ConvertTo-Json) | Set-Content -LiteralPath $cfgPath -Encoding UTF8
            Mock Get-MetraAzdoConfigPath { return $cfgPath }
            Get-MetraAzdoPat | Should -Be 'file-pat'
        }
    }

    It 'prefers environment PAT over local JSON file' {
        InModuleScope Metra {
            Mock Get-MetraAzdoPatFromEnvironment {
                return [PSCustomObject]@{ Pat = 'env-pat'; Scope = 'User' }
            }
            $cfgPath = Join-Path $TestDrive 'azdo.local.json'
            (@{ pat = 'file-pat'; organization = 'indwes' } | ConvertTo-Json) | Set-Content -LiteralPath $cfgPath -Encoding UTF8
            Mock Get-MetraAzdoConfigPath { return $cfgPath }
            Get-MetraAzdoPat | Should -Be 'env-pat'
        }
    }

    It 'warms process env from Get-MetraAzdoPatFromEnvironment' {
        InModuleScope Metra {
            Remove-Item Env:METRA_AZDO_PAT -ErrorAction SilentlyContinue
            Mock Resolve-MetraAzdoPatPrecedence {
                return [PSCustomObject]@{ Pat = 'scoped-pat'; Scope = 'User' }
            }
            $r = Get-MetraAzdoPatFromEnvironment
            $r.Pat | Should -Be 'scoped-pat'
            $env:METRA_AZDO_PAT | Should -Be 'scoped-pat'
        }
    }
}

Describe 'AzDO exact target names' {
    It 'rejects wildcard project and repo tokens' {
        InModuleScope Metra {
            { Test-MetraAzdoExactTargetName -Name 'Power*' -Kind 'Project' } | Should -Throw '*wildcards*'
            { Test-MetraAzdoExactTargetName -Name 'Colleague?' -Kind 'Repository' } | Should -Throw '*wildcards*'
            { Resolve-MetraAzdoRepository -Project 'PowerShell' -Repo '*Colleague*' -Inventory @() } | Should -Throw '*wildcards*'
        }
    }
}

Describe 'AzDO direct repo resolve' {
    It 'falls back to REST when repo is outside bounded inventory' {
        InModuleScope Metra {
            $inventory = @(
                [PSCustomObject]@{
                    id            = '1'
                    name          = 'Other'
                    project       = [PSCustomObject]@{ name = 'PowerShell' }
                    defaultBranch = 'refs/heads/main'
                }
            )
            Mock Invoke-MetraAzdoRest {
                return [PSCustomObject]@{
                    id            = '99'
                    name          = 'valence-sdk-dotnet'
                    project       = [PSCustomObject]@{ name = 'SharePoint' }
                    defaultBranch = 'refs/heads/main'
                }
            }
            $repo = Resolve-MetraAzdoRepository -Project 'SharePoint' -Repo 'valence-sdk-dotnet' -Inventory $inventory
            $repo.name | Should -Be 'valence-sdk-dotnet'
            Should -Invoke Invoke-MetraAzdoRest -Times 1 -Exactly
        }
    }

    It 'invokes identity validation on inventory match before return' {
        InModuleScope Metra {
            $inventory = @(
                [PSCustomObject]@{
                    id            = '1'
                    name          = 'Colleague'
                    project       = [PSCustomObject]@{ name = 'PowerShell' }
                    defaultBranch = 'refs/heads/main'
                }
            )
            Mock Test-MetraAzdoResolvedRepoIdentity { return $true }

            $repo = Resolve-MetraAzdoRepository -Project 'PowerShell' -Repo 'Colleague' -Inventory $inventory
            $repo.name | Should -Be 'Colleague'
            Should -Invoke Test-MetraAzdoResolvedRepoIdentity -Times 1 -Exactly -ParameterFilter {
                $ExpectedProject -eq 'PowerShell' -and $ExpectedRepo -eq 'Colleague'
            }
        }
    }

    It 'fail-closes when REST returns a mismatched repository identity' {
        InModuleScope Metra {
            Mock Invoke-MetraAzdoRest {
                return [PSCustomObject]@{
                    id            = '99'
                    name          = 'WrongRepo'
                    project       = [PSCustomObject]@{ name = 'WrongProject' }
                    defaultBranch = 'refs/heads/main'
                }
            }
            { Resolve-MetraAzdoRepository -Project 'SharePoint' -Repo 'valence-sdk-dotnet' -Inventory @() } |
                Should -Throw '*identity mismatch*'
        }
    }
}

Describe 'AzDO status without PAT' {
    It 'reports not ready when unauthenticated' {
        InModuleScope Metra {
            Mock Get-MetraAzdoPat { return $null }
            $s = Get-MetraAzdoStatus
            $s.authenticated | Should -BeFalse
            $s.ready | Should -BeFalse
        }
    }
}

Describe 'Ask AzDO evidence enforcement' {
    It 'fail-closes on ambiguity before any code search' {
        InModuleScope Metra {
            Mock Test-MetraAzdoAuthenticated { return $true }
            Mock Invoke-MetraAzdoRest { return [PSCustomObject]@{ value = @() } }
            Mock Get-MetraProjectRegistry {
                return [PSCustomObject]@{
                    projects = @([PSCustomObject]@{
                            name        = 'AmbiguousTest'
                            azdoProject = 'PowerShell'
                            azdoRepo    = ''
                            remoteUrl   = ''
                        })
                }
            }
            Mock Test-MetraAzdoAmbiguousRepoMatch { return $true }
            Mock Search-MetraAzdoCode { throw 'org-wide search should not run' }

            $ev = Get-MetraAskAzdoEvidence -Prompt 'How does routing work?' -Where 'AmbiguousTest'
            $ev.ok | Should -BeFalse
            $ev.ambiguous | Should -BeTrue
            $ev.error | Should -Match 'Ambiguous'
            @($ev.items).Count | Should -Be 0
            Should -Invoke Search-MetraAzdoCode -Times 0 -Exactly
            Should -Invoke Test-MetraAzdoAmbiguousRepoMatch -Times 1 -Exactly
        }
    }

    It 'searches only inside the resolved repo after routing' {
        InModuleScope Metra {
            Mock Test-MetraAzdoAuthenticated { return $true }
            Mock Invoke-MetraAzdoRest { return [PSCustomObject]@{ value = @() } }
            Mock Get-MetraProjectRegistry {
                return [PSCustomObject]@{
                    projects = @([PSCustomObject]@{
                            name        = 'ScopedSearchTest'
                            azdoProject = 'PowerShell'
                            azdoRepo    = 'ScopedSearchTest'
                            remoteUrl   = ''
                        })
                }
            }
            $repo = [PSCustomObject]@{
                id            = '42'
                name          = 'ScopedSearchTest'
                project       = [PSCustomObject]@{ name = 'PowerShell' }
                defaultBranch = 'refs/heads/main'
            }
            Mock Test-MetraAzdoAmbiguousRepoMatch { return $false }
            Mock Find-MetraAzdoPlausibleRepos { return @($repo) }
            Mock Get-MetraAzdoFileContent {
                param($Project, $Repo, $Path)
                if ($Path -eq 'src/example.ps1') {
                    return [PSCustomObject]@{ content = 'function Example { }' }
                }
                return [PSCustomObject]@{ content = '' }
            }
            Mock Search-MetraAzdoCode {
                param($Query, $Projects, $Repositories)
                return [PSCustomObject]@{
                    searchUsed = $true
                    hitCount   = 1
                    hits       = @([PSCustomObject]@{
                            path       = '/src/example.ps1'
                            project    = 'PowerShell'
                            repository = 'ScopedSearchTest'
                        })
                }
            }

            $ev = Get-MetraAskAzdoEvidence -Prompt 'Example function routing' -Where 'ScopedSearchTest'
            $ev.ok | Should -BeTrue
            Should -Invoke Search-MetraAzdoCode -Times 1 -Exactly -ParameterFilter {
                $Projects -contains 'PowerShell' -and $Repositories -contains 'ScopedSearchTest'
            }
            Should -Invoke Get-MetraAzdoFileContent -Times 1 -Exactly -ParameterFilter {
                $Purpose -eq 'Ask' -and $Path -eq 'src/example.ps1'
            }
            $ev.items.Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'AzDO Ask retrieval caps' {
    It 'uses maxAskFileChars for Purpose Ask file reads' {
        InModuleScope Metra {
            Mock Get-MetraAzdoConfig {
                return [PSCustomObject]@{
                    maxFileChars    = 120000
                    maxAskFileChars = 500
                }
            }
            Mock Resolve-MetraAzdoRepository {
                return [PSCustomObject]@{
                    id            = '1'
                    name          = 'Colleague'
                    project       = [PSCustomObject]@{ name = 'PowerShell' }
                    defaultBranch = 'refs/heads/main'
                }
            }
            Mock Invoke-MetraAzdoRest {
                return [PSCustomObject]@{ content = ('x' * 1000); size = 1000 }
            }

            $file = Get-MetraAzdoFileContent -Project PowerShell -Repo Colleague -Path README.md -Purpose Ask
            $file.maxFileChars | Should -Be 500
            $file.truncated | Should -BeTrue
            $file.content.Length | Should -BeLessOrEqual 500
        }
    }
}

Describe 'AzDO repo-scoped search' {
    It 'passes project and repository filters to code search API' {
        InModuleScope Metra {
            Mock Get-MetraAzdoConfig {
                return [PSCustomObject]@{ organization = 'indwes'; maxSearchHits = 5 }
            }
            Mock Invoke-MetraAzdoRest {
                param($Method, $Path, $Body)
                return [PSCustomObject]@{ results = @() }
            }

            Search-MetraAzdoCode -Query 'WAGC' -Projects @('PowerShell') -Repositories @('Colleague') | Out-Null

            Should -Invoke Invoke-MetraAzdoRest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Post' -and $Path -eq '_apis/search/codesearchresults' `
                    -and $Body.filters.Project -contains 'PowerShell' `
                    -and $Body.filters.Repository -contains 'Colleague'
            }
        }
    }
}

Describe 'AzDO CLI item path parameters' {
    It 'maps -ItemPath, -RepoPath, and -File to the repo item path (not metra.ps1 filesystem -Path)' {
        InModuleScope Metra {
            $fromItem = ConvertFrom-MetraAzdoCliArgs -ArgsRest @('-Project', 'PowerShell', '-Repo', 'Colleague', '-ItemPath', 'README.md')
            $fromRepo = ConvertFrom-MetraAzdoCliArgs -ArgsRest @('-Project', 'PowerShell', '-Repo', 'Colleague', '-RepoPath', 'AGENTS.md')
            $fromFile = ConvertFrom-MetraAzdoCliArgs -ArgsRest @('-Project', 'PowerShell', '-Repo', 'Colleague', '-File', 'docs/setup.md')
            $fromPath = ConvertFrom-MetraAzdoCliArgs -ArgsRest @('-Project', 'PowerShell', '-Repo', 'Colleague', '-Path', 'src/module.ps1')

            $fromItem.Path | Should -Be 'README.md'
            $fromRepo.Path | Should -Be 'AGENTS.md'
            $fromFile.Path | Should -Be 'docs/setup.md'
            $fromPath.Path | Should -Be 'src/module.ps1'
        }
    }

    It 'get subcommand requires -ItemPath family params and uses operator file caps' {
        InModuleScope Metra {
            Mock Test-MetraAzdoAuthenticated { return $true }
            Mock Get-MetraAzdoFileContent {
                param($Purpose)
                return [PSCustomObject]@{ content = 'ok'; purpose = $Purpose; maxFileChars = 120000 }
            }

            Invoke-MetraAzdoCommand -Subcommand get -ArgsRest @(
                '-Project', 'PowerShell', '-Repo', 'Colleague', '-ItemPath', 'README.md'
            ) | Out-Null

            Should -Invoke Get-MetraAzdoFileContent -Times 1 -Exactly -ParameterFilter {
                $Project -eq 'PowerShell' -and $Repo -eq 'Colleague' -and $Path -eq 'README.md'
            }
        }
    }
}
