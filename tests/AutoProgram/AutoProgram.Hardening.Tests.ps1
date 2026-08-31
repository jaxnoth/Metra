# Bing hardening: fail-closed adapters, contract enforcement, path/state/contention guards.
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Metra, AutoProgram -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\AutoProgram\AutoProgram.psd1') -Force
}

Describe 'AutoProgram adapter fail-closed (isolation)' {
    It 'does not grant routing confidence from title heuristics when routing adapter unavailable' {
        InModuleScope AutoProgram {
            Test-AutoProgramRoutingAdapterAvailable | Should -BeFalse
            $metraRoot = Get-AutoProgramHostRoot
            $outside = Join-Path ([IO.Path]::GetTempPath()) ('ap-route-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            try {
                $planPath = Join-Path $outside 'metra-title.plan.md'
                $proj = Resolve-MetraAutoprogramPlanProject -Path $planPath -MetraRoot $metraRoot `
                    -Title 'Metra boundary work' -Overview 'metra routing test'
                [double]$proj.routingConfidence | Should -Be 0.0
                $proj.routingEvidence | Should -Be 'unresolved'
            }
            finally {
                Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'returns adapter-unavailable routing context without eligibility' {
        $ctx = Get-AutoProgramRoutingContext -Request @{
            schemaVersion = 1
            query         = 'Metra inspect'
            planPath      = ''
        }
        $ctx.routingEvidence | Should -Be 'adapter-unavailable'
        $ctx.eligible | Should -BeFalse
        [double]$ctx.routingConfidence | Should -Be 0.0
    }

    It 'reports capture adapter availability in triage result' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-cap-' + [guid]::NewGuid().ToString('n'))
            try {
                $result = Invoke-MetraAutoprogramTriage -Root $root -MetraRoot (Get-AutoProgramHostRoot)
                $result.PSObject.Properties.Name | Should -Contain 'captureAdapterAvailable'
                $result.captureAdapterAvailable | Should -BeFalse
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'AutoProgram contract enforcement' {
    It 'accepts valid queue-item and rejects invalid id pattern' {
        InModuleScope AutoProgram {
            $valid = [PSCustomObject]@{
                schemaVersion = 1
                id            = 'AP-20260831-0001'
                summary       = 'ok'
                status        = 'queued'
                createdAt     = (Get-Date).ToString('o')
                updatedAt     = (Get-Date).ToString('o')
            }
            { Test-AutoProgramContract -Schema 'queue-item' -Object $valid } | Should -Not -Throw

            $invalid = [PSCustomObject]@{
                schemaVersion = 1
                id            = 'AP-bad-id'
                summary       = 'bad'
                status        = 'queued'
                createdAt     = (Get-Date).ToString('o')
                updatedAt     = (Get-Date).ToString('o')
            }
            { Test-AutoProgramContract -Schema 'queue-item' -Object $invalid } | Should -Throw '*Contract validation failed*'
        }
    }

    It 'rejects candidate writes missing required fields' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-cand-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraAutoprogramLayout -Root $root
                $bad = [PSCustomObject]@{ id = 'CAND-20260831-0001'; summary = 'x' }
                { Save-MetraAutoprogramCandidate -Root $root -Candidate $bad } | Should -Throw '*Contract validation failed*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects routing-context.result objects with extra properties' {
        $extra = [PSCustomObject]@{
            schemaVersion     = 1
            registryName      = ''
            root              = ''
            routingConfidence = 0.0
            routingEvidence   = 'unresolved'
            minimumConfidence = 0.85
            eligible          = $false
            surprise          = 'nope'
        }
        { Test-AutoProgramContract -Schema 'routing-context.result' -Object $extra } | Should -Throw '*disallowed property*'
    }
}

Describe 'AutoProgram path escape guards' {
    It 'rejects traversal and UNC-like ids' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-path-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraAutoprogramLayout -Root $root
                foreach ($bad in @('..\evil', '..\/evil', '\\server\share\evil')) {
                    { Resolve-MetraAutoprogramItemPath -Root $root -Id $bad -Subfolder 'queue' } |
                        Should -Throw '*Invalid*' -Because "id '$bad' must be rejected"
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'AutoProgram corrupt state recovery' {
    It 'throws predictably when state.json is invalid JSON' {
        InModuleScope AutoProgram {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-state-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraAutoprogramLayout -Root $root
                Write-AutoProgramAtomicUtf8Text -Path (Join-Path $root 'state.json') -Text '{ not json'
                { Get-MetraAutoprogramState -Root $root } | Should -Throw '*state unreadable*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'AutoProgram concurrent queue id allocation' {
    It 'issues unique queue ids under mutex contention' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('ap-conc-' + [guid]::NewGuid().ToString('n'))
        $modulePath = Join-Path $script:RepoRoot 'modules\AutoProgram\AutoProgram.psd1'
        Import-Module $modulePath -Force
        try {
            Initialize-MetraAutoprogramLayout -Root $root
            $ids = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            $pool = [runspacefactory]::CreateRunspacePool(1, 6)
            $pool.Open()
            $blocks = @()
            1..6 | ForEach-Object {
                $ps = [powershell]::Create().AddScript({
                    param($RootPath, $ModPath)
                    Import-Module $ModPath -Force
                    New-MetraAutoprogramQueueId -Root $RootPath
                }).AddArgument($root).AddArgument($modulePath)
                $ps.RunspacePool = $pool
                $blocks += [PSCustomObject]@{ Ps = $ps; Handle = $ps.BeginInvoke() }
            }
            foreach ($b in $blocks) {
                $ids.Add([string]$b.Ps.EndInvoke($b.Handle))
                $b.Ps.Dispose()
            }
            $pool.Close()
            $pool.Dispose()
            @($ids | Select-Object -Unique).Count | Should -Be 6
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'AutoProgram module export integrity' {
    It 'psd1 FunctionsToExport matches psm1 export list' {
        $psd1 = Join-Path $script:RepoRoot 'modules\AutoProgram\AutoProgram.psd1'
        $psm1 = Join-Path $script:RepoRoot 'modules\AutoProgram\AutoProgram.psm1'
        $manifest = Import-PowerShellDataFile -Path $psd1
        $psmText = Get-Content -LiteralPath $psm1 -Raw
        $match = [regex]::Match($psmText, '\$export\s*=\s*@\((?<body>[^)]*)\)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $match.Success | Should -BeTrue
        $fromPsm1 = [regex]::Matches($match.Groups['body'].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
        $fromPsd1 = @($manifest.FunctionsToExport | Sort-Object)
        $fromPsm1Sorted = @($fromPsm1 | Sort-Object)
        $fromPsd1 | Should -BeExactly $fromPsm1Sorted
    }

    It 'every exported command resolves after import' {
        $manifest = Import-PowerShellDataFile -Path (Join-Path $script:RepoRoot 'modules\AutoProgram\AutoProgram.psd1')
        foreach ($name in @($manifest.FunctionsToExport)) {
            Get-Command $name -Module AutoProgram -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    It 're-import does not multiply AutoProgram module instances' {
        Import-Module (Join-Path $script:RepoRoot 'modules\AutoProgram\AutoProgram.psd1') -Force
        @(Get-Module AutoProgram).Count | Should -Be 1
    }
}
