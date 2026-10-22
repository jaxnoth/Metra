# A Cursor plan outside the Metra checkout must route through the real Metra adapter.
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Loom\Loom.PlanRouting.Tests.ps1"
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Metra, Loom, Yarn -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'scripts\Metra.psd1') -Force
}

AfterAll {
    Get-Module Metra, Loom, Yarn -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'Loom formal plan routing' {
    It 'resolves a cursor plan for a registered non-Metra project to that project checkout' {
        $projects = @(
            Get-MetraProjects |
                Where-Object {
                    $_.Name -ne 'Metra' -and
                    $_.Name -notmatch '(?i)\bmetra\b' -and
                    -not [string]::IsNullOrWhiteSpace([string]$_.Path) -and
                    (Test-Path -LiteralPath $_.Path -PathType Container)
                } |
                Sort-Object Name
        )
        $picked = $null
        foreach ($p in $projects) {
            $title = ('{0} routing test' -f $p.Name)
            $overview = ('{0}: routing test for Loom enqueue.' -f $p.Name)
            $query = ('{0} {1}' -f $title, $overview).Trim()
            $amb = Get-MetraRoutingAmbiguity -Query $query -SkipTelemetry
            $primary = $amb.Primary
            if ($primary -and [string]$primary.Name -eq $p.Name -and [int]$primary.Score -ge 2) {
                $picked = [PSCustomObject]@{
                    Project  = $p
                    Title    = $title
                    Overview = $overview
                }
                break
            }
        }
        if (-not $picked) {
            foreach ($p in $projects) {
                $title = [string]$p.Name
                $overview = [string]$p.Name
                $query = ('{0} {1}' -f $title, $overview).Trim()
                $amb = Get-MetraRoutingAmbiguity -Query $query -SkipTelemetry
                $primary = $amb.Primary
                if ($primary -and [string]$primary.Name -eq $p.Name -and [int]$primary.Score -ge 2) {
                    $picked = [PSCustomObject]@{
                        Project  = $p
                        Title    = $title
                        Overview = $overview
                    }
                    break
                }
            }
        }
        if (-not $picked) { throw 'No present non-Metra registry project wins its own name query.' }

        $expectedRoot = [System.IO.Path]::GetFullPath([string]$picked.Project.Path)
        $plansDir = Join-Path $env:USERPROFILE '.cursor\plans'
        New-Item -ItemType Directory -Path $plansDir -Force | Out-Null
        $planPath = Join-Path $plansDir ('loom-routing-' + [guid]::NewGuid().ToString('n') + '.plan.md')
        $loomRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('loom-route-' + [guid]::NewGuid().ToString('n'))
        $previousLoomRoot = $env:METRA_LOOM_ROOT
        $body = @"
---
name: $($picked.Title)
overview: "$($picked.Overview)"
status: Approved
todos:
  - id: t1
    content: "$($picked.Project.Name): no-op routing test."
    status: pending
---

# Implement

Edit tests/ only.

- Tests must pass.

Invoke-Pester -Path tests
"@
        $metraCli = Join-Path $script:RepoRoot 'metra.ps1'
        try {
            [System.IO.File]::WriteAllText($planPath, $body, [System.Text.UTF8Encoding]::new($false))
            $env:METRA_LOOM_ROOT = $loomRoot
            & $metraCli loom enqueue -FromPlan -Path $planPath | Out-Null
            $queueDir = Join-Path $loomRoot 'queue'
            $queueFiles = @(Get-ChildItem -LiteralPath $queueDir -Filter 'AP-*.json' -File -ErrorAction SilentlyContinue)
            $queueFiles.Count | Should -Be 1
            $item = Get-Content -LiteralPath $queueFiles[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            [string]$item.project.routingEvidence | Should -Be 'routing-ambiguity-primary'
            [string]$item.project.registryName | Should -Be $picked.Project.Name
            [string]$item.project.root | Should -Be $expectedRoot
            ([double]$item.project.routingConfidence -ge 0.85) | Should -BeTrue
            [string]$item.project.root | Should -Not -Be ([string]$picked.Project.Root)

            & $metraCli loom run -Id ([string]$item.id) -DryRun | Out-Null
            $impl = @(Get-ChildItem -LiteralPath $loomRoot -Recurse -Filter 'implementation.json' -File -ErrorAction SilentlyContinue)
            $impl.Count | Should -BeGreaterThan 0
            $implText = [System.IO.File]::ReadAllText($impl[0].FullName)
            $implText | Should -Match 'dry-run'
        }
        finally {
            if ($null -eq $previousLoomRoot) {
                Remove-Item Env:METRA_LOOM_ROOT -ErrorAction SilentlyContinue
            }
            else {
                $env:METRA_LOOM_ROOT = $previousLoomRoot
            }
            Remove-Item -LiteralPath $planPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $loomRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
