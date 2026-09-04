# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.Yarn.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'modules\Yarn\Yarn.psd1') -Force
}

Describe 'Yarn A0 storage and hashes' {
    It 'initializes layout and fails closed on bad JSON' {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraYarnLayout -Root $root
                Test-Path -LiteralPath (Join-Path $root 'backlog.json') | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $root 'plan-links.json') | Should -BeTrue
                Get-YarnSchemaVersion | Should -Be 1
                Get-YarnHandoffContractVersion | Should -Be 1
                Set-Content -LiteralPath (Join-Path $root 'backlog.json') -Value '{bad' -NoNewline
                { Get-MetraYarnBacklog -Root $root } | Should -Throw
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'computes stable source and pack hashes and freshness' {
        InModuleScope Yarn {
            $t1 = "hello`r`nworld "
            $t2 = "hello`nworld"
            (Get-YarnSourceHash -NormalizedSourceText $t1) | Should -Be (Get-YarnSourceHash -NormalizedSourceText $t2)
            $plan = "---`nname: x`n---`nbody"
            $h = Get-YarnPlanContentHash -PlanText $plan
            $p = Get-YarnPackInputHash -PlanText $plan
            $fresh = Test-YarnPackFreshness -PlanText $plan -RecordedPlanContentHash $h -RecordedPackInputHash $p -RecordedPackContractVersion (Get-YarnPackContractVersion) -LastPackSucceeded $true
            $fresh.fresh | Should -BeTrue
            $stale = Test-YarnPackFreshness -PlanText ($plan + "`nedit") -RecordedPlanContentHash $h -RecordedPackInputHash $p -RecordedPackContractVersion (Get-YarnPackContractVersion) -LastPackSucceeded $true
            $stale.fresh | Should -BeFalse
            $stale.reason | Should -Be 'plan-content-changed'
        }
    }

    It 'preserves backlog id and firstSeenAt on upsert' {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraYarnLayout -Root $root
                $a = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title = 'Alpha'; primarySourceKey = 'capture:c1'; sources = @('capture:c1')
                        projectKey = 'Metra'; sourceText = 'Alpha'
                    })
                $id = $a.id
                $first = $a.firstSeenAt
                Start-Sleep -Milliseconds 20
                $b = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title = 'Alpha2'; primarySourceKey = 'capture:c1'; sources = @('capture:c1')
                        projectKey = 'Metra'; sourceText = 'Alpha2'
                    })
                $b.id | Should -Be $id
                [string]$b.firstSeenAt | Should -Be ([string]$first)
                $b.title | Should -Be 'Alpha2'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Yarn A1 rank and scan' {
    It 'ranks with explainable components and stable sort' {
        InModuleScope Yarn {
            $r = Measure-YarnRank -Item ([PSCustomObject]@{
                    title = 'T'; projectKey = 'Metra'; operatorPriority = 0.2
                    urgency = 0.1; strategicAlignment = 0.1
                    dependenciesResolved = $true
                })
            $r.rubricVersion | Should -Be 'yarn-rank-v1'
            $r.rankReasons | Should -Contain 'objectivePresent'
            $r.rankReasons | Should -Contain 'projectCriticality'
            $r.readyEnough | Should -BeFalse
            $items = @(
                [PSCustomObject]@{ id = 'YARN-B'; total = 0.5; effectiveImpact = 0.4; firstSeenAt = '2026-01-02' }
                [PSCustomObject]@{ id = 'YARN-A'; total = 0.5; effectiveImpact = 0.4; firstSeenAt = '2026-01-01' }
                [PSCustomObject]@{ id = 'YARN-C'; total = 0.9; effectiveImpact = 0.2; firstSeenAt = '2026-01-03' }
            )
            $sorted = Sort-YarnBacklogItems -Items $items
            $sorted[0].id | Should -Be 'YARN-C'
            $sorted[1].id | Should -Be 'YARN-A'
        }
    }

    It 'scan upserts Capture override without Loom writes' {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-' + [guid]::NewGuid().ToString('n'))
            $docs = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-docs-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $docs -Force | Out-Null
                $script:YarnHostRootOverride = $docs
                $script:YarnCaptureOverride = {
                    param($req)
                    @([PSCustomObject]@{
                            id      = 'cap-1'
                            summary = 'Wire intake smoke'
                            status  = 'candidate'
                            tags    = @()
                        })
                }
                $script:YarnAtlasOverride = { @() }
                # Empty Future-Dev (no ### headings)
                Set-Content -LiteralPath (Join-Path $docs 'Future-Development.local.md') -Value "# Future`n" -Encoding utf8
                # Read-YarnFutureDevIdeas expects docs under MetraRoot\docs\
                $docsDir = Join-Path $docs 'docs'
                New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
                Move-Item -LiteralPath (Join-Path $docs 'Future-Development.local.md') -Destination (Join-Path $docsDir 'Future-Development.local.md') -Force

                $scan = Invoke-MetraYarnScan -Root $root -MetraRoot $docs
                $scan.captureCount | Should -Be 1
                $items = @(Get-MetraYarnBacklog -Root $root)
                $items.Count | Should -BeGreaterOrEqual 1
                $items[0].primarySourceKey | Should -Be 'capture:cap-1'
                Test-YarnLoomQueueWriteForbidden | Should -BeTrue
            }
            finally {
                $script:YarnHostRootOverride = $null
                $script:YarnCaptureOverride = $null
                $script:YarnAtlasOverride = $null
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $docs -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'daily is read-only by default' {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraYarnLayout -Root $root
                $d = Get-MetraYarnDaily -Root $root
                $d.outcome | Should -Be 'daily-readonly'
                $d.approvalAvailable | Should -BeTrue
                $d.outcome | Should -Be 'daily-readonly'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Yarn A2 synthesize pack reconcile' {
    It 'template synthesizes Pending Bing Review and packs' {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-' + [guid]::NewGuid().ToString('n'))
            $hostRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-host-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path (Join-Path $hostRoot 'docs') -Force | Out-Null
                $cursorPlans = Join-Path $hostRoot 'cursor-plans'
                New-Item -ItemType Directory -Path $cursorPlans -Force | Out-Null
                $script:YarnHostRootOverride = $hostRoot
                $script:YarnCursorPlansDirOverride = $cursorPlans
                $script:YarnPackOverride = {
                    param($req)
                    $packDir = Join-Path $env:LOCALAPPDATA 'Metra\inspect\Metra'
                    [void][System.IO.Directory]::CreateDirectory($packDir)
                    $packPath = Join-Path $packDir 'pack-plan.md'
                    Write-YarnAtomicUtf8Text -Path $packPath -Text "# stub pack`n"
                    [PSCustomObject]@{ ok = $true; packPath = $packPath; stub = $true }
                }
                Initialize-MetraYarnLayout -Root $root
                $item = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title = 'Synth Demo'; primarySourceKey = 'capture:demo1'
                        sources = @('capture:demo1'); sourceKind = 'capture'; captureId = 'demo1'
                        projectKey = 'Metra'; sourceText = 'Synth Demo body'; sourceHash = (Get-YarnSourceHash -NormalizedSourceText 'Synth Demo body')
                    })
                { Invoke-MetraYarnSynthesize -Root $root -MetraRoot $hostRoot -BacklogId $item.id -UseAgent -Confirm } | Should -Throw
                $synth = Invoke-MetraYarnSynthesize -Root $root -MetraRoot $hostRoot -BacklogId $item.id -Confirm
                $synth.outcome | Should -Be 'synthesized'
                $synth.status | Should -Be 'Pending Bing Review'
                Test-Path -LiteralPath $synth.planPath | Should -BeTrue
                ([System.IO.Path]::GetFullPath($synth.planPath)).StartsWith(
                    [System.IO.Path]::GetFullPath($cursorPlans),
                    [System.StringComparison]::OrdinalIgnoreCase
                ) | Should -BeTrue
                (Get-Content -LiteralPath $synth.planPath -Raw) | Should -Match 'Pending Bing Review'
                (Get-Content -LiteralPath $synth.planPath -Raw) | Should -Not -Match '(?m)^status:\s*Approved'
                (Get-Content -LiteralPath $synth.planPath -Raw) | Should -Match '(?m)^patterns:'
                (Get-Content -LiteralPath $synth.planPath -Raw) | Should -Match '## Pattern gaps'

                $after = @(Get-MetraYarnBacklog -Root $root) | Where-Object { $_.id -eq $item.id } | Select-Object -First 1
                $after.readyEnough | Should -BeTrue

                $pack = Invoke-MetraYarnPack -Root $root -MetraRoot $hostRoot -BacklogId $item.id
                $pack.outcome | Should -Be 'packed'
                $pack.freshCheck.fresh | Should -BeTrue

                { Invoke-YarnCommand -Subcommand plan -ArgsRest @('approve', '-Confirm') -Root $root } | Should -Throw
            }
            finally {
                $script:YarnHostRootOverride = $null
                $script:YarnCursorPlansDirOverride = $null
                $script:YarnPackOverride = $null
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hostRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'reconcile dry-run would-synthesize Capture without writing plan' {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraYarnLayout -Root $root
                $null = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title = 'Cap Only'; primarySourceKey = 'capture:c2'; sources = @('capture:c2')
                        sourceKind = 'capture'; projectKey = 'Metra'; sourceText = 'Cap Only'
                    })
                $rec = Invoke-MetraYarnReconcile -Root $root -DryRun
                $rec.outcome | Should -Be 'reconcile-dry-run'
                @($rec.actions | Where-Object { $_.action -eq 'would-synthesize' }).Count | Should -BeGreaterOrEqual 1
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Yarn Bing punch-list (schema, health, Future-Dev)' {
    It 'rejects backlog documents missing required fields' {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraYarnLayout -Root $root
                $bad = @{
                    schemaVersion = 1
                    items         = @(
                        @{ id = 'YARN-1'; title = 'x' }
                    )
                }
                Write-YarnAtomicUtf8Text -Path (Join-Path $root 'backlog.json') -Text (($bad | ConvertTo-Json -Depth 6) + "`n")
                { Get-MetraYarnBacklog -Root $root } | Should -Throw
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'sets health=ok on new intake items' {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-' + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraYarnLayout -Root $root
                $row = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title = 'Health Default'; primarySourceKey = 'capture:h1'
                        sources = @('capture:h1'); projectKey = 'Metra'; sourceText = 'Health Default'
                    })
                $row.health | Should -Be 'ok'
                $loaded = @(Get-MetraYarnBacklog -Root $root) | Where-Object { $_.id -eq $row.id } | Select-Object -First 1
                $loaded.health | Should -Be 'ok'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'degrades gracefully on malformed Future-Dev markdown' {
        InModuleScope Yarn {
            $hostRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-fd-' + [guid]::NewGuid().ToString('n'))
            try {
                $docs = Join-Path $hostRoot 'docs'
                New-Item -ItemType Directory -Path $docs -Force | Out-Null
                $path = Join-Path $docs 'Future-Development.local.md'

                Set-Content -LiteralPath $path -Value "# Future`n## Only H2`n* bullet`n" -Encoding utf8
                @(Read-YarnFutureDevIdeas -MetraRoot $hostRoot).Count | Should -Be 0

                Set-Content -LiteralPath $path -Value '' -Encoding utf8
                @(Read-YarnFutureDevIdeas -MetraRoot $hostRoot).Count | Should -Be 0

                Set-Content -LiteralPath $path -Value @"
### Contents
### Hi
### Real Idea Alpha
### Real Idea Alpha
### Real idea alpha
### Another Solid Idea
"@ -Encoding utf8
                $ideas = @(Read-YarnFutureDevIdeas -MetraRoot $hostRoot)
                $ideas.Count | Should -Be 2
                $ideas[0].primarySourceKey | Should -Be 'future-dev:real-idea-alpha'
                $ideas[0].health | Should -Be 'ok'
                $ideas[1].primarySourceKey | Should -Be 'future-dev:another-solid-idea'
            }
            finally {
                Remove-Item -LiteralPath $hostRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Yarn A3 approve and handoff" {
    It "refuses approve without Confirm and blocks ready status" {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-yarn-a3-" + [guid]::NewGuid().ToString("n"))
            try {
                Initialize-MetraYarnLayout -Root $root
                { Invoke-MetraYarnPlanApprove -Root $root -BacklogId "x" } | Should -Throw "*Confirm*"
                $item = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title = "Ready Only"; primarySourceKey = "capture:r1"; sources = @("capture:r1")
                        projectKey = "Metra"; sourceText = "Ready Only"; status = "ready"; health = "ok"
                    })
                Sync-YarnPlanLink -Root $root -Link ([PSCustomObject]@{
                        backlogId = $item.id; formalPlanPath = "C:\missing.md"; planStatus = "Draft"
                        handoffContractVersion = 1; planContentHash = "h"; packInputHash = "p"
                        packContractVersion = (Get-YarnPackContractVersion); packSucceeded = $true
                    })
                { Invoke-MetraYarnPlanApprove -Root $root -BacklogId $item.id -Confirm } | Should -Throw "*pending-bing*"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It "approves pending-bing, transfers contract fields, retries after Loom failure" {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-yarn-a3-" + [guid]::NewGuid().ToString("n"))
            $hostRoot = Join-Path ([IO.Path]::GetTempPath()) ("metra-yarn-a3-host-" + [guid]::NewGuid().ToString("n"))
            $cursorDir = Join-Path $hostRoot 'cursor-plans'
            try {
                Initialize-MetraYarnLayout -Root $root
                New-Item -ItemType Directory -Path $cursorDir -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $hostRoot 'plans') -Force | Out-Null
                $script:YarnHostRootOverride = $hostRoot
                $planPath = Join-Path $cursorDir "approve-me.plan.md"
                $planBody = @"
---
name: Approve Me
overview: "fixture"
status: Pending Bing Review
bingReviewed: false
---

# Approve Me
"@
                Write-YarnAtomicUtf8Text -Path $planPath -Text $planBody
                $planHash = Get-YarnPlanContentHash -PlanText $planBody
                $packHash = Get-YarnPackInputHash -PlanText $planBody
                $item = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title = "Approve Me"; primarySourceKey = "capture:a3"; sources = @("capture:a3")
                        projectKey = "Metra"; sourceText = "Approve Me"; status = "pending-bing"; health = "ok"
                        formalPlanPath = $planPath; total = 3; effectiveImpact = 1; completionReady = 1
                        rubricVersion = "yarn-rank-v1"; rankReasons = @("objectivePresent")
                    })
                # Force pending-bing after rank may flip ready
                $all = @(Get-MetraYarnBacklog -Root $root)
                $map = ConvertTo-YarnPropertyMap -Object ($all | Where-Object { $_.id -eq $item.id } | Select-Object -First 1)
                $map["status"] = "pending-bing"
                $map["formalPlanPath"] = $planPath
                $map["total"] = 3; $map["effectiveImpact"] = 1; $map["completionReady"] = 1
                $map["rubricVersion"] = "yarn-rank-v1"; $map["rankReasons"] = @("objectivePresent")
                Save-MetraYarnBacklogItems -Root $root -Items @(($all | Where-Object { $_.id -ne $item.id }) + @((New-YarnPsObject -Map $map)))
                Sync-YarnPlanLink -Root $root -Link ([PSCustomObject]@{
                        backlogId = $item.id; formalPlanPath = $planPath; planStatus = "Pending Bing Review"
                        handoffContractVersion = 1; planContentHash = $planHash; packInputHash = $packHash
                        packContractVersion = (Get-YarnPackContractVersion); packSucceeded = $true
                    })

                $script:YarnLoomIngestOverride = {
                    param($req)
                    throw "loom down"
                }
                $failed = Invoke-MetraYarnPlanApprove -Root $root -MetraRoot $hostRoot -BacklogId $item.id -Confirm
                $failed.outcome | Should -Be "approved-handoff-failed"
                $expectedRepo = [System.IO.Path]::GetFullPath((Join-Path $hostRoot 'plans\approve-me.plan.md'))
                $failed.planPath | Should -Be $expectedRepo
                Test-Path -LiteralPath $expectedRepo | Should -BeTrue
                $link = @(Get-YarnPlanLinks -Root $root) | Where-Object { $_.backlogId -eq $item.id } | Select-Object -First 1
                $link.planStatus | Should -Be "Approved"
                $link.formalPlanPath | Should -Be $expectedRepo
                $link.approval.approvalRevision | Should -Be $planHash
                $link.approval.planContentHash | Should -Be $planHash
                $link.loomHandoff.state | Should -Be "failed"
                (Get-Content -LiteralPath $expectedRepo -Raw) | Should -Match "status:\s*Approved"

                $script:YarnLoomIngestOverride = {
                    param($req)
                    [PSCustomObject]@{
                        outcome = "enqueued"; queueItemId = "AP-20260902-0001"
                        approvalId = $req.ApprovalId; approvalRevision = $req.ApprovalRevision
                    }
                }
                $retry = Invoke-MetraYarnReconcile -Root $root -MetraRoot $hostRoot
                $retry.actions | Where-Object { $_.outcome -eq "approved-enqueued" } | Should -Not -BeNullOrEmpty
                $link2 = @(Get-YarnPlanLinks -Root $root) | Where-Object { $_.backlogId -eq $item.id } | Select-Object -First 1
                $link2.loomHandoff.state | Should -Be "succeeded"
                $link2.loomHandoff.queueItemId | Should -Be "AP-20260902-0001"
                $link2.formalPlanPath | Should -Be $expectedRepo

                # second approve same revision stays one logical handoff success
                $again = Invoke-MetraYarnPlanApprove -Root $root -MetraRoot $hostRoot -BacklogId $item.id -Confirm
                $again.outcome | Should -BeIn @("approved-enqueued", "handoff-already-succeeded")
            }
            finally {
                $script:YarnLoomIngestOverride = $null
                $script:YarnHostRootOverride = $null
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hostRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It "blocks stale pack on approve" {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ("metra-yarn-a3-" + [guid]::NewGuid().ToString("n"))
            $docs = Join-Path $root "docs"
            try {
                Initialize-MetraYarnLayout -Root $root
                New-Item -ItemType Directory -Path $docs -Force | Out-Null
                $planPath = Join-Path $docs "stale.plan.md"
                Write-YarnAtomicUtf8Text -Path $planPath -Text "---`nname: Stale`nstatus: Pending Bing Review`nbingReviewed: false`n---`n# Stale`n"
                $item = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title = "Stale"; primarySourceKey = "capture:stale"; sources = @("capture:stale")
                        projectKey = "Metra"; sourceText = "Stale"; status = "pending-bing"; health = "ok"
                        formalPlanPath = $planPath
                    })
                $all = @(Get-MetraYarnBacklog -Root $root)
                $map = ConvertTo-YarnPropertyMap -Object ($all | Where-Object { $_.id -eq $item.id } | Select-Object -First 1)
                $map["status"] = "pending-bing"; $map["formalPlanPath"] = $planPath
                Save-MetraYarnBacklogItems -Root $root -Items @(($all | Where-Object { $_.id -ne $item.id }) + @((New-YarnPsObject -Map $map)))
                Sync-YarnPlanLink -Root $root -Link ([PSCustomObject]@{
                        backlogId = $item.id; formalPlanPath = $planPath; planStatus = "Pending Bing Review"
                        handoffContractVersion = 1; planContentHash = "old"; packInputHash = "old"
                        packContractVersion = (Get-YarnPackContractVersion); packSucceeded = $true
                    })
                { Invoke-MetraYarnPlanApprove -Root $root -BacklogId $item.id -Confirm } | Should -Throw "*Pack not fresh*"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Yarn Pattern match (P3)' {
    It 'emits patterns cites for loom owner when MatchText hits loadWhen' {
        InModuleScope Yarn {
            $hostRoot = Get-YarnHostRoot
            $item = [PSCustomObject]@{
                title            = 'Need loom review wiring'
                primarySourceKey = 'capture:pat1'
                captureId        = 'pat1'
                projectKey       = 'loom'
                sourceText       = 'Please run loom review after inspect'
            }
            $text = New-YarnFormalPlanText -BacklogItem $item -MetraRoot $hostRoot
            $ids = @(Get-MetraPlanPatternIds -PlanText $text)
            $ids | Should -Contain 'loom-review'
            $text | Should -Match '## Pattern gaps'
            $text | Should -Not -Match '(?m)^product:'
        }
    }
}

Describe 'Yarn Phase B Atlas intake' {
    It 'scan upserts atlas fields, skips Session, pauses offline, and FromMemory requires Confirm' {
        InModuleScope Yarn {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-' + [guid]::NewGuid().ToString('n'))
            $hostRoot = Join-Path ([IO.Path]::GetTempPath()) ('metra-yarn-host-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path (Join-Path $hostRoot 'docs') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $hostRoot 'docs\Future-Development.local.md') -Value "# Future`n" -Encoding utf8
                $script:YarnHostRootOverride = $hostRoot
                $script:YarnCaptureOverride = { @() }
                $script:YarnAtlasOverride = {
                    param($req)
                    @(
                        [PSCustomObject]@{
                            stableId   = 'plan:phase-b-demo'
                            title      = 'Phase B Demo Plan'
                            kind       = 'Plan'
                            projectKey = 'Metra'
                            sourceText = 'Atlas plan body for intake'
                        }
                        [PSCustomObject]@{
                            stableId   = 'session:skip-me'
                            title      = 'Session noise'
                            kind       = 'Session'
                            projectKey = 'Metra'
                            sourceText = 'should skip'
                        }
                        [PSCustomObject]@{
                            stableId   = 'parked:phase-b-park'
                            title      = 'Parked Idea'
                            kind       = 'Parked'
                            projectKey = 'Metra'
                            sourceText = 'parked body'
                        }
                    )
                }

                $scan = Invoke-MetraYarnScan -Root $root -MetraRoot $hostRoot
                $scan.memoryLane | Should -Be 'ok'
                $scan.atlasCount | Should -Be 2
                $items = @(Get-MetraYarnBacklog -Root $root)
                $planItem = $items | Where-Object { $_.atlasStableId -eq 'plan:phase-b-demo' } | Select-Object -First 1
                $planItem | Should -Not -BeNullOrEmpty
                $planItem.primarySourceKey | Should -Be 'atlas:plan:phase-b-demo'
                $planItem.memoryLane | Should -Be 'atlas'
                $planItem.atlasKind | Should -Be 'Plan'
                $planItem.strategicAlignment | Should -Be 0.15
                $planItem.rankReasons -join ',' | Should -Match 'atlasKind=Plan'
                @($items | Where-Object { $_.atlasStableId -eq 'session:skip-me' }).Count | Should -Be 0
                $park = $items | Where-Object { $_.atlasKind -eq 'Parked' } | Select-Object -First 1
                $park.strategicAlignment | Should -Be 0.10

                # Sibling skip: plan-link with atlasStableId blocks re-emit
                Sync-YarnPlanLink -Root $root -Link ([PSCustomObject]@{
                        backlogId              = [string]$planItem.id
                        formalPlanPath         = (Join-Path $hostRoot 'docs\already.plan.md')
                        planStatus             = 'Pending Bing Review'
                        handoffContractVersion = 1
                        atlasStableId          = 'plan:phase-b-demo'
                    })
                Write-YarnAtomicUtf8Text -Path (Join-Path $hostRoot 'docs\already.plan.md') -Text "# already`n"
                $scan2 = Invoke-MetraYarnScan -Root $root -MetraRoot $hostRoot
                $scan2.atlasCount | Should -Be 1

                # Offline pause: adapter throws
                $script:YarnAtlasOverride = { throw 'atlas down' }
                $scan3 = Invoke-MetraYarnScan -Root $root -MetraRoot $hostRoot
                $scan3.memoryLane | Should -Be 'paused'
                $scan3.atlasCount | Should -Be 0
                $status = Get-MetraYarnStatus -Root $root
                $status.memoryLane | Should -Be 'paused'
                $status.phase | Should -Be 'B'
                Test-YarnLoomQueueWriteForbidden | Should -BeTrue

                $script:YarnAtlasOverride = {
                    @([PSCustomObject]@{
                            stableId   = 'plan:from-mem'
                            title      = 'From Memory Plan'
                            kind       = 'Plan'
                            projectKey = 'Metra'
                            sourceText = 'from memory body'
                        })
                }
                { Invoke-MetraYarnSynthesize -Root $root -MetraRoot $hostRoot -FromMemory 'plan:from-mem' } | Should -Throw
                $beforeCount = @(Get-MetraYarnBacklog -Root $root).Count
                $beforeLinks = @(Get-YarnPlanLinks -Root $root).Count
                $dry = Invoke-MetraYarnSynthesize -Root $root -MetraRoot $hostRoot -FromMemory 'plan:from-mem' -DryRun
                $dry.outcome | Should -Be 'dry-run'
                $dry.backlogId | Should -Be 'YARN-DRYRUN'
                @(Get-MetraYarnBacklog -Root $root).Count | Should -Be $beforeCount
                @(Get-YarnPlanLinks -Root $root).Count | Should -Be $beforeLinks
                @(Get-MetraYarnBacklog -Root $root | Where-Object { $_.atlasStableId -eq 'plan:from-mem' }).Count | Should -Be 0
                $synth = Invoke-MetraYarnSynthesize -Root $root -MetraRoot $hostRoot -FromMemory 'plan:from-mem' -Confirm
                $synth.outcome | Should -Be 'synthesized'
                (Get-Content -LiteralPath $synth.planPath -Raw) | Should -Match 'atlasStableId:\s*plan:from-mem'
                $link = @(Get-YarnPlanLinks -Root $root) | Where-Object { $_.backlogId -eq $synth.backlogId } | Select-Object -First 1
                $link.atlasStableId | Should -Be 'plan:from-mem'
                $link.atlasKind | Should -Be 'Plan'
                $link.memoryLane | Should -Be 'atlas'
            }
            finally {
                $script:YarnHostRootOverride = $null
                $script:YarnCaptureOverride = $null
                $script:YarnAtlasOverride = $null
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $hostRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Yarn Plan Board projection' {
    It 'resolves explicit precedence (not Stage max)' {
        InModuleScope Yarn {
            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus 'idea' -VerifiedLoomAccepted:$true
            $p.Stage | Should -Be 6
            $p.Board | Should -Be 'Shipped'
            $p.signal | Should -Be 'verified-loom-accepted'

            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus 'rejected' -HasActiveLoomQueue:$true
            $p.Stage | Should -Be 8
            $p.Board | Should -Be 'Drop'

            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus 'parked' -HandoffSucceeded:$true
            $p.Stage | Should -Be 7
            $p.Board | Should -Be 'Parked'

            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus 'approved' -HandoffSucceeded:$true
            $p.Stage | Should -Be 5
            $p.signal | Should -Be 'loom-handoff'

            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus '' -HasActiveLoomQueue:$true
            $p.Stage | Should -Be 5

            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus 'approved'
            $p.Stage | Should -Be 5
            $p.signal | Should -Be 'yarn-approved'

            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus 'pending-bing'
            $p.Stage | Should -Be 4
            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus 'stale-pack'
            $p.Stage | Should -Be 4

            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus 'idea' -HasFormalPlan:$true
            $p.Stage | Should -Be 3
            $p.Board | Should -Be 'Idea'
            $p = Resolve-YarnPlanBoardProjection -CursorPlan '' -YarnStatus 'idea' -HasFormalPlan:$false
            $p.Stage | Should -Be 2
            $p.Board | Should -Be 'Backlog'
            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus 'ready' -HasFormalPlan:$true
            $p.Stage | Should -Be 3

            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus '' -ExistingPlanBoardCard:$true
            $p.Stage | Should -Be 1
            $p.Board | Should -Be 'Inbox'

            $p = Resolve-YarnPlanBoardProjection -CursorPlan 'a.plan.md' -YarnStatus ''
            $p.action | Should -Be 'skip'
            $p.signal | Should -Be 'no-authoritative-signal'
        }
    }

    It 'preserves existing side-tab Board and heals Stage; unknown Board goes Inbox without signal' {
        InModuleScope Yarn {
            $p = Resolve-YarnPlanBoardProjection -YarnStatus '' -ExistingPlanBoardCard:$true -ExistingBoard 'Backlog'
            $p.Board | Should -Be 'Backlog'
            $p.Stage | Should -Be 2
            $p.signal | Should -Be 'existing-side-tab-preserve'

            $p = Resolve-YarnPlanBoardProjection -YarnStatus '' -ExistingPlanBoardCard:$true -ExistingBoard 'Drop'
            $p.Board | Should -Be 'Drop'
            $p.Stage | Should -Be 8

            $p = Resolve-YarnPlanBoardProjection -YarnStatus '' -ExistingPlanBoardCard:$true -ExistingBoard 'Inbox'
            $p.Board | Should -Be 'Inbox'
            $p.Stage | Should -Be 1

            $p = Resolve-YarnPlanBoardProjection -YarnStatus 'idea' -HasFormalPlan:$true -ExistingPlanBoardCard:$true -ExistingBoard 'Mystery'
            $p.Board | Should -Be 'Idea'
            $p.Stage | Should -Be 3

            $p = Resolve-YarnPlanBoardProjection -YarnStatus '' -ExistingPlanBoardCard:$true -ExistingBoard 'Mystery'
            $p.Board | Should -Be 'Inbox'
            $p.Stage | Should -Be 1

            $healed = Resolve-YarnPlanBoardHealProjection -Projection ([PSCustomObject]@{
                    action = 'project'; CursorPlan = 'x.plan.md'; YarnId = 'Y1'; Stage = 2; Board = 'Idea'; Title = 'x'; signal = 'legacy'
                })
            $healed.Stage | Should -Be 3
            $healed.Board | Should -Be 'Idea'
        }
    }

    It 'maps Project select, Description/PlanPath, and counts plan todos for Pending/Done' {
        InModuleScope Yarn {
            (Resolve-YarnPlanBoardProjectSelect -ProjectKey 'TicketTracker') | Should -Be 'TicketTracker'
            (Resolve-YarnPlanBoardProjectSelect -ProjectKey 'Finance') | Should -Be 'Other'
            (Resolve-YarnPlanBoardProjectSelect -ProjectKey '' -CursorPlan 'metra_ios_no-mac_.plan.md' -Title 'Metra iOS') | Should -Be 'Metra'
            (Resolve-YarnPlanBoardProjectSelect -ProjectKey '' -Title 'Sprint coworker' -CursorPlan 'tickettracker_sprint.plan.md') | Should -Be 'TicketTracker'
            (Resolve-YarnPlanBoardProjectSelect -ProjectKey '' -Title 'Sprint coworker' -CursorPlan 'sprint_coworker.plan.md') | Should -Be 'Metra'

            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('pb-todos-' + [guid]::NewGuid().ToString('n') + '.plan.md')
            try {
                @(
                    '---'
                    'name: Todo Sample'
                    'overview: Short blurb for the board card'
                    'todos:'
                    '  - id: a'
                    '    content: one'
                    '    status: completed'
                    '  - id: b'
                    '    content: two'
                    '    status: pending'
                    '  - id: c'
                    '    content: three'
                    '    status: cancelled'
                    '  - id: d'
                    '    content: four'
                    '    status: pending'
                    '---'
                    '# body'
                ) | Set-Content -LiteralPath $tmp -Encoding utf8
                $c = Get-YarnPlanBoardPlanTodoCounts -Path $tmp
                $c.HasTodos | Should -BeTrue
                $c.Done | Should -Be 1
                $c.Pending | Should -Be 2
                $c.PlanName | Should -Be 'Todo Sample'
                $c.Overview | Should -Be 'Short blurb for the board card'
                (Get-YarnPlanBoardShortDescription -Text $c.Overview) | Should -Be 'Short blurb for the board card'
                $fullPath = [System.IO.Path]::GetFullPath($tmp)
                $props = New-YarnPlanBoardNotionProperties -Projection ([PSCustomObject]@{
                        Title = 'Todo Sample'; Board = 'Idea'; Stage = 3; CursorPlan = 'todo.plan.md'
                        YarnId = ''; Project = 'Metra'; Pending = 2; Done = 1
                        Description = (Get-YarnPlanBoardShortDescription -Text $c.Overview)
                        PlanPath = $fullPath
                    })
                $props.Project.select.name | Should -Be 'Metra'
                $props.Pending.number | Should -Be 2
                $props.Done.number | Should -Be 1
                $props.Description.rich_text[0].text.content | Should -Be 'Short blurb for the board card'
                $props.PlanPath.rich_text[0].text.content | Should -Be $fullPath
                (Resolve-YarnPlanBoardSubprojectSelect -ClusterHint 'Ask' -Project 'Metra') | Should -Be 'Ask'
                (Resolve-YarnPlanBoardSubprojectSelect -Title 'Ask engine polish' -CursorPlan 'ask_engine.plan.md' -Project 'Metra') | Should -Be 'Ask'
                $props2 = New-YarnPlanBoardNotionProperties -Projection ([PSCustomObject]@{
                        Title = 'Ask'; Board = 'Idea'; Stage = 3; CursorPlan = 'a.plan.md'
                        Project = 'Metra'; Subproject = 'Ask'
                    })
                $props2.Subproject.select.name | Should -Be 'Ask'

                $plansDir = Join-Path $env:USERPROFILE '.cursor\plans'
                $fxLeaf = 'pb_fuzzy_resolve_aabbccdd.plan.md'
                $fxPath = Join-Path $plansDir $fxLeaf
                $createdFx = $false
                try {
                    if (-not (Test-Path -LiteralPath $plansDir)) {
                        New-Item -ItemType Directory -Path $plansDir -Force | Out-Null
                    }
                    if (-not (Test-Path -LiteralPath $fxPath)) {
                        @(
                            '---'
                            'name: Fuzzy Resolve Fixture'
                            'overview: Fuzzy path fill'
                            'todos:'
                            '  - id: a'
                            '    content: x'
                            '    status: pending'
                            '---'
                        ) | Set-Content -LiteralPath $fxPath -Encoding utf8
                        $createdFx = $true
                    }
                    $fuzzy = Resolve-YarnPlanBoardPlanFilePath -CursorPlan 'pb_fuzzy_resolve_' -MetraRoot ''
                    $fuzzy | Should -Be ([System.IO.Path]::GetFullPath($fxPath))
                }
                finally {
                    if ($createdFx) { Remove-Item -LiteralPath $fxPath -Force -ErrorAction SilentlyContinue }
                }
            }
            finally {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'matches dual identity: Yarn-only card gains CursorPlan; split conflict modifies neither' {
        InModuleScope Yarn {
            $yarnOnly = [PSCustomObject]@{ pageId = 'page-y'; CursorPlan = ''; YarnId = 'Y-1'; Board = 'Backlog'; Stage = 2 }
            $m = Resolve-YarnPlanBoardCardMatch -CursorPlan 'new.plan.md' -YarnId 'Y-1' -ExistingCards @($yarnOnly) `
                -DatabaseId 'db' -ApiKey 'k'
            $m.status | Should -Be 'matched'
            $m.reason | Should -Be 'yarn-id'
            $m.populateCursorPlan | Should -BeTrue
            $m.card.pageId | Should -Be 'page-y'

            $cardA = [PSCustomObject]@{ pageId = 'page-a'; CursorPlan = 'a.plan.md'; YarnId = 'Y-A'; Board = 'Idea'; Stage = 3 }
            $cardB = [PSCustomObject]@{ pageId = 'page-b'; CursorPlan = 'b.plan.md'; YarnId = 'Y-B'; Board = 'Backlog'; Stage = 2 }
            $split = Resolve-YarnPlanBoardCardMatch -CursorPlan 'a.plan.md' -YarnId 'Y-B' -ExistingCards @($cardA, $cardB) `
                -DatabaseId 'db' -ApiKey 'k'
            $split.status | Should -Be 'conflict'
            $split.reason | Should -Be 'split-identity'

            $dups = Resolve-YarnPlanBoardCardMatch -CursorPlan 'a.plan.md' -YarnId '' -ExistingCards @(
                $cardA, [PSCustomObject]@{ pageId = 'page-a2'; CursorPlan = 'a.plan.md'; YarnId = 'Y-Z'; Board = 'Idea'; Stage = 3 }
            ) -DatabaseId 'db' -ApiKey 'k'
            $dups.status | Should -Be 'matched'
            $dups.reason | Should -Be 'cursor-plan-stem-preferred'
            $dups.conflictCards.Count | Should -Be 1

            $stub = [PSCustomObject]@{ pageId = 'page-stub'; CursorPlan = 'ask_conversation_execution_'; YarnId = ''; Board = 'Active'; Stage = 4 }
            $full = [PSCustomObject]@{ pageId = 'page-full'; CursorPlan = 'ask_conversation_execution_27fc070b.plan.md'; YarnId = ''; Board = 'Idea'; Stage = 3 }
            Test-YarnPlanBoardCursorPlanMatch -Left $stub.CursorPlan -Right $full.CursorPlan | Should -BeTrue
            $stem = Resolve-YarnPlanBoardCardMatch -CursorPlan $full.CursorPlan -YarnId '' -ExistingCards @($stub, $full) `
                -DatabaseId 'db' -ApiKey 'k'
            $stem.status | Should -Be 'matched'
            $stem.card.pageId | Should -Be 'page-stub'
            $stem.populateCursorPlan | Should -BeTrue
        }
    }

    It 'matches CursorPlan case-insensitively by filename' {
        InModuleScope Yarn {
            Test-YarnPlanBoardCursorPlanMatch -Left 'C:\x\Foo.plan.md' -Right 'foo.plan.md' | Should -BeTrue
            (Get-YarnPlanBoardCursorPlanName -PathOrName 'C:\plans\Demo.plan.md') | Should -Be 'Demo.plan.md'
        }
    }

    It 'notifies once after Set-YarnBacklogItemStatus; zero when SkipPlanBoard; fail-open without Notion' {
        InModuleScope Yarn {
            $root = Join-Path $env:TEMP ("yarn-pb-" + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraYarnLayout -Root $root
                $created = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title            = 'PB Test'
                        status           = 'idea'
                        formalPlanPath   = 'pb-test.plan.md'
                        projectKey       = 'Metra'
                        primarySourceKey = 'capture:pb1'
                        sources          = @('capture:pb1')
                        sourceText       = 'PB Test'
                    })
                $bid = [string]$created.id
                $script:pbCalls = New-Object System.Collections.Generic.List[object]
                $script:YarnPlanBoardOverride = {
                    param($req)
                    $script:pbCalls.Add($req)
                    if ($req.Operation -eq 'upsert') {
                        return [PSCustomObject]@{ outcome = 'created'; pageId = 'page-1'; projection = $req.Projection }
                    }
                    if ($req.Operation -eq 'status') {
                        return [PSCustomObject]@{ access = 'accessible'; detail = 'override' }
                    }
                    if ($req.Operation -eq 'rest') {
                        return [PSCustomObject]@{ results = @(); has_more = $false }
                    }
                    return $null
                }
                $env:METRA_NOTION_API_KEY = 'test-token-not-real'
                Write-YarnAtomicUtf8Text -Path (Join-Path $root 'plan-board.settings.json') -Text (@{
                        DatabaseId     = 'db-test'
                        DataSourceId   = 'ds-test'
                        HttpTimeoutSec = 5
                    } | ConvertTo-Json)

                $updated = Set-YarnBacklogItemStatus -Root $root -BacklogId $bid -Status 'ready'
                $updated.status | Should -Be 'ready'
                $upsertCalls = @($script:pbCalls | Where-Object { $_.Operation -eq 'upsert' })
                $upsertCalls.Count | Should -Be 1
                [int]$upsertCalls[0].Projection.Stage | Should -Be 3

                $script:pbCalls = New-Object System.Collections.Generic.List[object]
                [void](Set-YarnBacklogItemStatus -Root $root -BacklogId $bid -Status 'parked' -SkipPlanBoard)
                $script:pbCalls.Count | Should -Be 0
                $parked = @(Get-MetraYarnBacklog -Root $root | Where-Object { [string]$_.id -eq $bid }) | Select-Object -First 1
                [string]$parked.status | Should -Be 'parked'

                $script:pbCalls = New-Object System.Collections.Generic.List[object]
                # Empty DatabaseId in local settings (no example fallback) => unconfigured even if Atlas token exists.
                Write-YarnAtomicUtf8Text -Path (Join-Path $root 'plan-board.settings.json') -Text (@{
                        DatabaseId     = ''
                        DataSourceId   = ''
                        HttpTimeoutSec = 5
                    } | ConvertTo-Json)
                Remove-Item Env:METRA_NOTION_API_KEY -ErrorAction SilentlyContinue
                { Set-YarnBacklogItemStatus -Root $root -BacklogId $bid -Status 'rejected' } | Should -Not -Throw
                $script:pbCalls.Count | Should -Be 0
                $rej = @(Get-MetraYarnBacklog -Root $root | Where-Object { [string]$_.id -eq $bid }) | Select-Object -First 1
                [string]$rej.status | Should -Be 'rejected'
            }
            finally {
                $script:YarnPlanBoardOverride = $null
                $script:pbCalls = $null
                Remove-Item Env:METRA_NOTION_API_KEY -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'sync DryRun writes zero Notion mutations; status does not mutate; -Inventory rejected' {
        InModuleScope Yarn {
            $root = Join-Path $env:TEMP ("yarn-pb-sync-" + [guid]::NewGuid().ToString('n'))
            $script:pbWrites = 0
            try {
                Initialize-MetraYarnLayout -Root $root
                [void](Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                            title            = 'Sync Test'
                            status           = 'pending-bing'
                            formalPlanPath   = 'sync-test.plan.md'
                            projectKey       = 'Metra'
                            primarySourceKey = 'capture:pb2'
                            sources          = @('capture:pb2')
                            sourceText       = 'Sync Test'
                        }))
                $script:YarnPlanBoardOverride = {
                    param($req)
                    if ($req.Operation -eq 'upsert') {
                        if (-not $req.DryRun) { $script:pbWrites++ }
                        return [PSCustomObject]@{
                            outcome    = $(if ($req.DryRun) { 'would-create' } else { 'created' })
                            projection = $req.Projection
                        }
                    }
                    if ($req.Operation -eq 'rest') {
                        if ($req.Method -eq 'Get') {
                            return [PSCustomObject]@{ id = 'db-test'; object = 'database' }
                        }
                        return [PSCustomObject]@{ results = @(); has_more = $false }
                    }
                    if ($req.Operation -eq 'status') {
                        return [PSCustomObject]@{ access = 'accessible'; detail = 'override' }
                    }
                    return $null
                }
                $env:METRA_NOTION_API_KEY = 'test-token-not-real'
                Write-YarnAtomicUtf8Text -Path (Join-Path $root 'plan-board.settings.json') -Text (@{
                        DatabaseId = 'db-test'; DataSourceId = 'ds-test'; HttpTimeoutSec = 5
                    } | ConvertTo-Json)

                $dry = Invoke-MetraYarnPlanBoardSync -Root $root -DryRun
                $dry.DryRun | Should -BeTrue
                $dry.Created | Should -BeGreaterThan 0
                $script:pbWrites | Should -Be 0

                $st = Get-MetraYarnPlanBoardStatus -Root $root
                $st.configured | Should -BeTrue
                $st.access | Should -Be 'accessible'
                $script:pbWrites | Should -Be 0

                { Invoke-YarnPlanBoardCommand -ArgsRest @('sync', '-Inventory') -Root $root } | Should -Throw -ExpectedMessage '*inventory*'
            }
            finally {
                $script:YarnPlanBoardOverride = $null
                $script:pbWrites = 0
                Remove-Item Env:METRA_NOTION_API_KEY -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'fail-open notify swallows upsert errors and never rethrows' {
        InModuleScope Yarn {
            $root = Join-Path $env:TEMP ("yarn-pb-fail-" + [guid]::NewGuid().ToString('n'))
            try {
                Initialize-MetraYarnLayout -Root $root
                $created = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title            = 'Fail Test'
                        status           = 'approved'
                        formalPlanPath   = 'fail-test.plan.md'
                        projectKey       = 'Metra'
                        primarySourceKey = 'capture:pb3'
                        sources          = @('capture:pb3')
                        sourceText       = 'Fail Test'
                    })
                $script:YarnPlanBoardOverride = {
                    param($req)
                    if ($req.Operation -eq 'upsert') { throw 'notion down bearer SECRETTOKEN' }
                    if ($req.Operation -eq 'rest') { return [PSCustomObject]@{ results = @(); has_more = $false } }
                    return $null
                }
                $env:METRA_NOTION_API_KEY = 'test-token-not-real'
                Write-YarnAtomicUtf8Text -Path (Join-Path $root 'plan-board.settings.json') -Text (@{ DatabaseId = 'db-test' } | ConvertTo-Json)
                { Invoke-YarnPlanBoardNotifyFailOpen -Root $root -BacklogId ([string]$created.id) -CursorPlan 'fail-test.plan.md' -Reason 'yarn-status:approved' } | Should -Not -Throw
                $state = Get-YarnPlanBoardSyncState -Root $root
                $state.lastError | Should -Not -BeNullOrEmpty
                [string]$state.lastError.message | Should -Not -Match 'SECRETTOKEN'
                [string]$state.lastError.cursorPlan | Should -Be 'fail-test.plan.md'
            }
            finally {
                $script:YarnPlanBoardOverride = $null
                Remove-Item Env:METRA_NOTION_API_KEY -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'does not treat loomHandoff without state=succeeded as handoff success' {
        InModuleScope Yarn {
            $ctx = Build-YarnPlanBoardSignalContext -Root (Join-Path $env:TEMP 'yarn-pb-empty') -CursorPlan 'x.plan.md' `
                -PlanLink ([PSCustomObject]@{
                    backlogId      = 'Y1'
                    formalPlanPath = 'x.plan.md'
                    loomHandoff    = [PSCustomObject]@{ state = 'failed'; lastError = 'boom' }
                }) -ExistingPlanBoardCard:$false
            $ctx.HandoffSucceeded | Should -BeFalse

            $ctxOk = Build-YarnPlanBoardSignalContext -Root (Join-Path $env:TEMP 'yarn-pb-empty') -CursorPlan 'x.plan.md' `
                -PlanLink ([PSCustomObject]@{
                    backlogId      = 'Y1'
                    formalPlanPath = 'x.plan.md'
                    loomHandoff    = [PSCustomObject]@{ state = 'succeeded'; queueItemId = 'AP-1' }
                }) -ExistingPlanBoardCard:$false
            $ctxOk.HandoffSucceeded | Should -BeTrue
        }
    }

    It 'full sync examines SkipPlanBoard backlog items; duplicate CursorPlan fails that item; second sync is idempotent' {
        InModuleScope Yarn {
            $root = Join-Path $env:TEMP ("yarn-pb-idemp-" + [guid]::NewGuid().ToString('n'))
            $script:pbWrites = 0
            $script:pbCards = New-Object System.Collections.Generic.List[object]
            try {
                Initialize-MetraYarnLayout -Root $root
                [void](Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                            title            = 'Scan-like Idea'
                            status           = 'idea'
                            formalPlanPath   = 'scan-idea.plan.md'
                            projectKey       = 'Metra'
                            primarySourceKey = 'capture:scan1'
                            sources          = @('capture:scan1')
                            sourceText       = 'from scan'
                        }) -SkipPlanBoard)

                $script:YarnPlanBoardOverride = {
                    param($req)
                    if ($req.Operation -eq 'upsert') {
                        if (-not $req.DryRun) {
                            $name = [string]$req.Projection.CursorPlan
                            $existing = @($script:pbCards | Where-Object { $_.CursorPlan -eq $name })
                            if ($existing.Count -gt 1) { throw "Duplicate Plan Board cards for CursorPlan='$name' (count=$($existing.Count))" }
                            if ($existing.Count -eq 1) {
                                $c = $existing[0]
                                $sameBoard = [string]::Equals([string]$c.Board, [string]$req.Projection.Board, [StringComparison]::OrdinalIgnoreCase)
                                $sameStage = ([int]$c.Stage -eq [int]$req.Projection.Stage)
                                $needYarnId = (-not [string]::IsNullOrWhiteSpace([string]$req.Projection.YarnId)) -and
                                    (-not [string]::Equals([string]$c.YarnId, [string]$req.Projection.YarnId, [StringComparison]::OrdinalIgnoreCase))
                                if ($sameBoard -and $sameStage -and -not $needYarnId) {
                                    return [PSCustomObject]@{ outcome = 'unchanged'; pageId = $c.pageId; projection = $req.Projection }
                                }
                                $script:pbWrites++
                                $c.Board = [string]$req.Projection.Board
                                $c.Stage = [int]$req.Projection.Stage
                                $c.YarnId = [string]$req.Projection.YarnId
                                return [PSCustomObject]@{ outcome = 'updated'; pageId = $c.pageId; projection = $req.Projection }
                            }
                            $script:pbWrites++
                            $pageId = 'page-' + $script:pbWrites
                            $script:pbCards.Add([PSCustomObject]@{
                                    pageId     = $pageId
                                    CursorPlan = $name
                                    Board      = [string]$req.Projection.Board
                                    Stage      = [int]$req.Projection.Stage
                                    YarnId     = [string]$req.Projection.YarnId
                                })
                            return [PSCustomObject]@{ outcome = 'created'; pageId = $pageId; projection = $req.Projection }
                        }
                        return [PSCustomObject]@{ outcome = 'would-create'; projection = $req.Projection }
                    }
                    if ($req.Operation -eq 'rest') {
                        # Emulate Find/AllCards from in-memory store
                        $results = @()
                        foreach ($c in $script:pbCards) {
                            $results += [PSCustomObject]@{
                                id         = $c.pageId
                                properties = @{
                                    Name       = @{ title = @(@{ plain_text = $c.CursorPlan }) }
                                    CursorPlan = @{ rich_text = @(@{ plain_text = $c.CursorPlan }) }
                                    YarnId     = @{ rich_text = @() }
                                    Board      = @{ select = @{ name = $c.Board } }
                                    Stage      = @{ number = $c.Stage }
                                }
                            }
                        }
                        return [PSCustomObject]@{ results = $results; has_more = $false }
                    }
                    if ($req.Operation -eq 'status') {
                        return [PSCustomObject]@{ access = 'accessible'; detail = 'override' }
                    }
                    return $null
                }
                $env:METRA_NOTION_API_KEY = 'test-token-not-real'
                Write-YarnAtomicUtf8Text -Path (Join-Path $root 'plan-board.settings.json') -Text (@{ DatabaseId = 'db-test' } | ConvertTo-Json)

                $s1 = Invoke-MetraYarnPlanBoardSync -Root $root
                $s1.Examined | Should -BeGreaterThan 0
                @($s1.Actions | Where-Object { $_.CursorPlan -eq 'scan-idea.plan.md' }).Count | Should -Be 1
                (@($s1.Actions | Where-Object { $_.CursorPlan -eq 'scan-idea.plan.md' })[0]).signal | Should -Be 'yarn-idea'
                $s1.Created | Should -BeGreaterThan 0

                $s2 = Invoke-MetraYarnPlanBoardSync -Root $root
                $s3 = Invoke-MetraYarnPlanBoardSync -Root $root
                # After convergence, further syncs must not write
                $s3.Updated | Should -Be 0
                $s3.Created | Should -Be 0
                $s3.Unchanged | Should -BeGreaterThan 0
                $writesAfterSecond = $script:pbWrites
                $s4 = Invoke-MetraYarnPlanBoardSync -Root $root
                $script:pbWrites | Should -Be $writesAfterSecond
                $s4.Updated | Should -Be 0
                $s4.Created | Should -Be 0

                # Duplicate identity: two cards same CursorPlan => item fails, others continue
                $script:pbCards.Add([PSCustomObject]@{
                        pageId     = 'page-dup'
                        CursorPlan = 'scan-idea.plan.md'
                        Board      = 'Idea'
                        Stage      = 2
                        YarnId     = ''
                    })
                $sDup = Invoke-MetraYarnPlanBoardSync -Root $root
                $sDup.identityConflicts | Should -BeGreaterThan 0
                @($sDup.Actions | Where-Object { $_.CursorPlan -eq 'scan-idea.plan.md' -and $_.outcome -eq 'identity-conflict' }).Count | Should -Be 1
            }
            finally {
                $script:YarnPlanBoardOverride = $null
                $script:pbWrites = 0
                $script:pbCards = $null
                Remove-Item Env:METRA_NOTION_API_KEY -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'inventory classifiers: noise, parked beats noise, echo, hash twin, clusterHint' {
        InModuleScope Yarn {
            # Stem normalize strips plan suffix and trailing 8-hex
            (Get-YarnPlanBoardInventoryNormalizeStem -Text 'commit_then_knowledge_coverage_2b8f30d2.plan.md') |
                Should -Be 'commit-then-knowledge-coverage'
            (Get-YarnPlanBoardInventoryNormalizeStem -Text 'Commit Then Knowledge Coverage') |
                Should -Be 'commit-then-knowledge-coverage'

            # Fixture / index / test-card propose drop
            $fx = Get-YarnPlanBoardInventoryHeuristic -Title 'calibrate_a13_benign_20260825.plan.md' -SourceType 'cursor-plan' -HasFormalPlan:$true
            $fx.proposedDecision | Should -Be 'drop'
            $fx.reasonCodes | Should -Contain 'fixture'
            $fx.isNoise | Should -BeTrue

            $ix = Get-YarnPlanBoardInventoryHeuristic -Title 'Open Cursor plans (created, not fully done)' -SourceType 'yarn' -YarnStatus 'idea' -HasFormalPlan:$false
            $ix.proposedDecision | Should -Be 'drop'
            $ix.reasonCodes | Should -Contain 'index-heading'
            $ix.isNoise | Should -BeTrue

            # Legitimate titles that share words with Future-Dev headings must not drop
            $legLadder = Get-YarnPlanBoardInventoryHeuristic -Title 'Voice Ladder' -SourceType 'yarn' -YarnStatus 'idea' -HasFormalPlan:$false
            $legLadder.proposedDecision | Should -Not -Be 'drop'
            $legLadder.reasonCodes | Should -Not -Contain 'index-heading'
            $legVerify = Get-YarnPlanBoardInventoryHeuristic -Title 'Verify Who Service Owns X' -SourceType 'yarn' -YarnStatus 'idea' -HasFormalPlan:$false
            $legVerify.proposedDecision | Should -Not -Be 'drop'
            $legVerify.reasonCodes | Should -Not -Contain 'index-heading'
            (Get-YarnPlanBoardInventoryNoiseKind -Title 'Ladder' -HasFormalPlan:$false -SourceType 'yarn') |
                Should -Be 'index-heading'
            (Get-YarnPlanBoardInventoryEchoKey -Text 'routing-phase4-2026-09-01') |
                Should -Be (Get-YarnPlanBoardInventoryEchoKey -Text 'routing-phase4-2026-09-02')
            (Get-YarnPlanBoardInventoryEchoKey -Text 'routing-phase4') |
                Should -Not -Be (Get-YarnPlanBoardInventoryEchoKey -Text 'routing-phase5')

            $tc = Get-YarnPlanBoardInventoryHeuristic -Title 'Fail Test' -SourceType 'notion' -ExistingBoard 'Inbox'
            $tc.proposedDecision | Should -Be 'drop'
            $tc.reasonCodes | Should -Contain 'test-card'

            # Parked status beats noise
            $park = Get-YarnPlanBoardInventoryHeuristic -Title 'Fail Test' -SourceType 'yarn' -YarnStatus 'parked' -HasFormalPlan:$false
            $park.proposedDecision | Should -Be 'park'
            $park.proposedDecision | Should -Not -Be 'drop'
            $park.reasonCodes | Should -Contain 'park-language'

            $tmp = Join-Path $env:TEMP ('yarn-pb-cls-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                $oldPath = Join-Path $tmp 'commit_then_knowledge_coverage_aaaaaaaa.plan.md'
                $newPath = Join-Path $tmp 'commit_then_knowledge_coverage_bbbbbbbb.plan.md'
                Set-Content -LiteralPath $oldPath -Value '# old' -Encoding utf8
                Start-Sleep -Milliseconds 50
                Set-Content -LiteralPath $newPath -Value '# new' -Encoding utf8

                $twinOld = [PSCustomObject]@{
                    rowId = 'cursor-plan:commit_then_knowledge_coverage_aaaaaaaa.plan.md'
                    proposedDecision = 'keep'; decision = 'review'; proposedBoard = 'Idea'; proposedStage = 3
                    cursorPlan = 'commit_then_knowledge_coverage_aaaaaaaa.plan.md'
                    yarnId = $null; notionPageId = $null; sourceType = 'cursor-plan'; sourcePath = $oldPath
                    reasonCodes = @('formal-plan'); evidence = @(); title = 'commit_then_knowledge_coverage_aaaaaaaa.plan.md'
                    isNoise = $false; echoOf = $null; supersededBy = $null; clusterHint = $null
                }
                $twinNew = [PSCustomObject]@{
                    rowId = 'cursor-plan:commit_then_knowledge_coverage_bbbbbbbb.plan.md'
                    proposedDecision = 'keep'; decision = 'review'; proposedBoard = 'Idea'; proposedStage = 3
                    cursorPlan = 'commit_then_knowledge_coverage_bbbbbbbb.plan.md'
                    yarnId = $null; notionPageId = $null; sourceType = 'cursor-plan'; sourcePath = $newPath
                    reasonCodes = @('formal-plan'); evidence = @(); title = 'commit_then_knowledge_coverage_bbbbbbbb.plan.md'
                    isNoise = $false; echoOf = $null; supersededBy = $null; clusterHint = $null
                }

                # Noise yarn shares stem with a real cursor-plan; noise must not win echo
                $noiseYarn = [PSCustomObject]@{
                    rowId = 'yarn:open-cursor'
                    proposedDecision = 'drop'; decision = 'review'; proposedBoard = 'Drop'; proposedStage = 8
                    cursorPlan = 'consumer_ready_ask_activation.plan.md'
                    yarnId = 'YARN-NOISE'; notionPageId = $null; sourceType = 'yarn'; sourcePath = $null
                    reasonCodes = @('index-heading'); evidence = @('status:idea')
                    title = 'Open Cursor plans'
                    isNoise = $true; echoOf = $null; supersededBy = $null; clusterHint = $null
                }
                $realPlan = [PSCustomObject]@{
                    rowId = 'cursor-plan:consumer_ready_ask_activation.plan.md'
                    proposedDecision = 'keep'; decision = 'review'; proposedBoard = 'Idea'; proposedStage = 3
                    cursorPlan = 'consumer_ready_ask_activation.plan.md'
                    yarnId = $null; notionPageId = $null; sourceType = 'cursor-plan'; sourcePath = (Join-Path $tmp 'consumer_ready_ask_activation.plan.md')
                    reasonCodes = @('formal-plan'); evidence = @()
                    title = 'consumer_ready_ask_activation.plan.md'
                    isNoise = $false; echoOf = $null; supersededBy = $null; clusterHint = $null
                }
                Set-Content -LiteralPath $realPlan.sourcePath -Value '# ask' -Encoding utf8

                # Echo: meta-doc loses to cursor-plan; reasonCodes append
                $metaEcho = [PSCustomObject]@{
                    rowId = 'meta-doc:consumer_ready_ask_activation.plan.md'
                    proposedDecision = 'keep'; decision = 'review'; proposedBoard = 'Backlog'; proposedStage = 2
                    cursorPlan = 'consumer_ready_ask_activation.plan.md'
                    yarnId = $null; notionPageId = $null; sourceType = 'meta-doc'; sourcePath = $null
                    reasonCodes = @('discovered-plan-doc', 'meta-plan-doc'); evidence = @()
                    title = 'consumer_ready_ask_activation.plan.md'
                    isNoise = $false; echoOf = $null; supersededBy = $null; clusterHint = $null
                }

                $done = @(Complete-YarnPlanBoardInventoryRows -Rows @($twinOld, $twinNew, $noiseYarn, $realPlan, $metaEcho))
                $twinLoser = @($done | Where-Object { $_.rowId -eq $twinOld.rowId }) | Select-Object -First 1
                $twinWinner = @($done | Where-Object { $_.rowId -eq $twinNew.rowId }) | Select-Object -First 1
                $twinLoser.proposedDecision | Should -Be 'drop'
                $twinLoser.reasonCodes | Should -Contain 'formal-plan'
                $twinLoser.reasonCodes | Should -Contain 'hash-twin-superseded'
                $twinLoser.supersededBy | Should -Be $twinWinner.rowId
                $twinWinner.proposedDecision | Should -Be 'keep'

                $noiseDone = @($done | Where-Object { $_.rowId -eq $noiseYarn.rowId }) | Select-Object -First 1
                $planDone = @($done | Where-Object { $_.rowId -eq $realPlan.rowId }) | Select-Object -First 1
                $metaDone = @($done | Where-Object { $_.rowId -eq $metaEcho.rowId }) | Select-Object -First 1
                $planDone.proposedDecision | Should -Be 'keep'
                $noiseDone.echoOf | Should -Be $planDone.rowId
                $noiseDone.proposedDecision | Should -Be 'drop'
                # Noise must not be echo winner (plan stays keep; noise has echoOf pointing at plan)
                $planDone.echoOf | Should -BeNullOrEmpty
                $metaDone.proposedDecision | Should -Be 'drop'
                $metaDone.echoOf | Should -Be $planDone.rowId
                $metaDone.reasonCodes | Should -Contain 'discovered-plan-doc'
                $metaDone.reasonCodes | Should -Contain 'echo-duplicate'

                $planDone.clusterHint | Should -Be 'Ask'
                $twinWinner.clusterHint | Should -Not -BeNullOrEmpty

                # Wrapped module-scrap; shipped leftover parks (docs), index Shipped archive still drops
                $scrap = Get-YarnPlanBoardInventoryHeuristic -Title 'Ask recommend (`AskRecommend.ps1`)' -SourceType 'yarn' -YarnStatus 'idea' -HasFormalPlan:$false
                $scrap.proposedDecision | Should -Be 'drop'
                $scrap.reasonCodes | Should -Contain 'module-scrap'
                $shipPark = Get-YarnPlanBoardInventoryHeuristic -Title 'installer_smartscreen_signing_shipped.plan.md' -SourceType 'cursor-plan' -HasFormalPlan:$true
                $shipPark.proposedDecision | Should -Be 'park'
                $shipPark.reasonCodes | Should -Contain 'shipped-archive'
                $shipIdx = Get-YarnPlanBoardInventoryHeuristic -Title 'Shipped (archive)' -SourceType 'yarn' -YarnStatus 'idea' -HasFormalPlan:$false
                $shipIdx.proposedDecision | Should -Be 'drop'
                $shipIdx.reasonCodes | Should -Contain 'index-heading'

                (Get-YarnPlanBoardInventoryEchoKey -Text 'sprint_coworker_ticket_analysis_20260910.plan.md') |
                    Should -Be (Get-YarnPlanBoardInventoryEchoKey -Text 'sprint-coworker-ticket-analysis-2026-09.plan.md')

                $cursorSprint = [PSCustomObject]@{
                    rowId = 'cursor-plan:sprint_coworker_ticket_analysis_20260910.plan.md'
                    proposedDecision = 'keep'; decision = 'review'; proposedBoard = 'Idea'; proposedStage = 3
                    cursorPlan = 'sprint_coworker_ticket_analysis_20260910.plan.md'
                    yarnId = $null; notionPageId = $null; sourceType = 'cursor-plan'; sourcePath = $null
                    reasonCodes = @('formal-plan'); evidence = @()
                    title = 'sprint_coworker_ticket_analysis_20260910.plan.md'
                    isNoise = $false; echoOf = $null; supersededBy = $null; clusterHint = $null
                }
                $metaSprint = [PSCustomObject]@{
                    rowId = 'meta-doc:sprint-coworker-ticket-analysis-2026-09.plan.md'
                    proposedDecision = 'keep'; decision = 'review'; proposedBoard = 'Backlog'; proposedStage = 2
                    cursorPlan = 'sprint-coworker-ticket-analysis-2026-09.plan.md'
                    yarnId = $null; notionPageId = $null; sourceType = 'meta-doc'; sourcePath = $null
                    reasonCodes = @('discovered-plan-doc', 'meta-plan-doc'); evidence = @()
                    title = 'sprint-coworker-ticket-analysis-2026-09.plan.md'
                    isNoise = $false; echoOf = $null; supersededBy = $null; clusterHint = $null
                }
                $loose = @(Complete-YarnPlanBoardInventoryRows -Rows @($cursorSprint, $metaSprint))
                $metaLoose = @($loose | Where-Object { $_.rowId -eq $metaSprint.rowId }) | Select-Object -First 1
                $curLoose = @($loose | Where-Object { $_.rowId -eq $cursorSprint.rowId }) | Select-Object -First 1
                $curLoose.proposedDecision | Should -Be 'keep'
                $metaLoose.proposedDecision | Should -Be 'drop'
                $metaLoose.echoOf | Should -Be $curLoose.rowId
                $metaLoose.reasonCodes | Should -Contain 'echo-duplicate'

                $notionKeep = [PSCustomObject]@{
                    rowId = 'notion:page-sprint'
                    proposedDecision = 'review'; decision = 'review'; proposedBoard = 'Idea'; proposedStage = 3
                    cursorPlan = 'sprint_coworker_ticket_analysis_20260910.plan.md'
                    yarnId = $null; notionPageId = 'page-sprint'; sourceType = 'notion'; sourcePath = $null
                    reasonCodes = @('unsure'); evidence = @()
                    title = 'Sprint coworker ticket analysis 2026-09-10'
                    isNoise = $false; echoOf = $null; supersededBy = $null; clusterHint = $null
                }
                $boardEcho = @(Complete-YarnPlanBoardInventoryRows -Rows @($cursorSprint, $notionKeep))
                $nKeep = @($boardEcho | Where-Object { $_.rowId -eq $notionKeep.rowId }) | Select-Object -First 1
                $nKeep.proposedDecision | Should -Not -Be 'drop'
                $nKeep.reasonCodes | Should -Contain 'echo-board-keep'
                $nKeep.echoOf | Should -Be $cursorSprint.rowId

                $md = Format-YarnPlanBoardInventoryMarkdown -InventoryId 'x' -GeneratedAt 't' -Rows @($cursorSprint, $notionKeep)
                $md | Should -Match 'Review this markdown'
                $md | Should -Match 'AffirmCluster'

                $noiseDrop = [PSCustomObject]@{
                    decision = 'review'; proposedDecision = 'drop'; reasonCodes = @('test-card')
                    notionPageId = 'p1'; clusterHint = 'Other'
                }
                (Get-YarnPlanBoardInventoryApplyDecision -Row $noiseDrop -Affirm 'drop,park') | Should -Be 'drop'
                $echoBoard = [PSCustomObject]@{
                    decision = 'review'; proposedDecision = 'drop'; reasonCodes = @('echo-board-keep')
                    notionPageId = 'p2'; clusterHint = 'Ask'
                }
                (Get-YarnPlanBoardInventoryApplyDecision -Row $echoBoard -Affirm 'drop,park') | Should -Be 'review'
                $askKeep = [PSCustomObject]@{
                    decision = 'review'; proposedDecision = 'keep'; reasonCodes = @('formal-plan')
                    notionPageId = $null; clusterHint = 'Ask'
                }
                (Get-YarnPlanBoardInventoryApplyDecision -Row $askKeep -Affirm 'drop,park') | Should -Be 'review'
                (Get-YarnPlanBoardInventoryApplyDecision -Row $askKeep -Affirm 'keep,park') | Should -Be 'keep'
                (Get-YarnPlanBoardInventoryApplyDecision -Row $askKeep -Affirm 'keep park') | Should -Be 'keep'
                $parkRow = [PSCustomObject]@{
                    decision = 'review'; proposedDecision = 'park'; reasonCodes = @('completed-unmarked')
                    notionPageId = $null; clusterHint = 'LoomYarn'
                }
                (Get-YarnPlanBoardInventoryApplyDecision -Row $parkRow -Affirm 'keep,park') | Should -Be 'park'
                (Get-YarnPlanBoardInventoryApplyDecision -Row $askKeep -AffirmCluster 'Ask') | Should -Be 'keep'
                (Get-YarnPlanBoardInventoryApplyDecision -Row $askKeep -AffirmCluster 'Ask' -As 'park') | Should -Be 'park'

                $doneSlice = [PSCustomObject]@{
                    rowId = 'cursor-plan:ask_activation_closeout_1f6a514c.plan.md'
                    proposedDecision = 'keep'; decision = 'review'; proposedBoard = 'Idea'; proposedStage = 3
                    cursorPlan = 'ask_activation_closeout_1f6a514c.plan.md'
                    yarnId = $null; notionPageId = $null; sourceType = 'cursor-plan'; sourcePath = $null
                    reasonCodes = @('formal-plan'); evidence = @()
                    title = 'ask_engine_polish_b9dd3dc1.plan.md'
                    isNoise = $false; echoOf = $null; supersededBy = $null; clusterHint = $null
                    blurb = 'Ask engine polish - DONE 2026-08-08'
                }
                $doneOut = @(Complete-YarnPlanBoardInventoryRows -Rows @($doneSlice)) | Select-Object -First 1
                $doneOut.proposedDecision | Should -Be 'park'
                $doneOut.reasonCodes | Should -Contain 'completed-unmarked'
                $doneOut.reasonCodes | Should -Contain 'formal-plan'

                $sliceDir = Join-Path $tmp 'slice-complete'
                New-Item -ItemType Directory -Path $sliceDir | Out-Null
                $slicePath = Join-Path $sliceDir 'loom_slice_4.plan.md'
                @(
                    '---'
                    'name: Loom Slice 4'
                    'todos:'
                    '  - id: a'
                    '    content: work'
                    '    status: completed'
                    '---'
                    '# Loom Slice 4'
                ) | Set-Content -LiteralPath $slicePath -Encoding utf8
                (Test-YarnPlanBoardInventoryPlanFileComplete -Path $slicePath) | Should -BeTrue
                $sliceRow = [PSCustomObject]@{
                    rowId = 'cursor-plan:loom_slice_4.plan.md'
                    proposedDecision = 'keep'; decision = 'review'; proposedBoard = 'Idea'; proposedStage = 3
                    cursorPlan = 'loom_slice_4.plan.md'
                    yarnId = $null; notionPageId = $null; sourceType = 'cursor-plan'; sourcePath = $slicePath
                    reasonCodes = @('formal-plan'); evidence = @()
                    title = 'loom_slice_4.plan.md'
                    isNoise = $false; echoOf = $null; supersededBy = $null; clusterHint = $null
                }
                $sliceOut = @(Complete-YarnPlanBoardInventoryRows -Rows @($sliceRow)) | Select-Object -First 1
                $sliceOut.proposedDecision | Should -Be 'park'
                $sliceOut.reasonCodes | Should -Contain 'completed-unmarked'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'inventory pack is versioned; apply skips review, rejects unknown schema, requires Confirm, and skips stale keep after approve' {
        InModuleScope Yarn {
            $root = Join-Path $env:TEMP ("yarn-pb-inv-" + [guid]::NewGuid().ToString('n'))
            $script:pbWrites = 0
            try {
                Initialize-MetraYarnLayout -Root $root
                $created = Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                        title            = 'No Plan Idea'
                        status           = 'idea'
                        formalPlanPath   = ''
                        projectKey       = 'Metra'
                        primarySourceKey = 'capture:inv1'
                        sources          = @('capture:inv1')
                        sourceText       = 'No Plan Idea'
                    }) -SkipPlanBoard
                $bid = [string]$created.id
                $env:METRA_NOTION_API_KEY = 'test-token-not-real'
                Write-YarnAtomicUtf8Text -Path (Join-Path $root 'plan-board.settings.json') -Text (@{ DatabaseId = 'db-test' } | ConvertTo-Json)
                $script:YarnPlanBoardOverride = {
                    param($req)
                    if ($req.Operation -eq 'upsert') {
                        if (-not $req.DryRun) { $script:pbWrites++ }
                        return [PSCustomObject]@{ outcome = 'created'; pageId = 'page-inv'; projection = $req.Projection }
                    }
                    if ($req.Operation -eq 'rest') {
                        return [PSCustomObject]@{ results = @(); has_more = $false }
                    }
                    return $null
                }

                $inv = Invoke-MetraYarnPlanBoardInventory -Root $root
                $inv.schemaVersion | Should -Be 2
                Test-Path -LiteralPath $inv.jsonPath | Should -BeTrue
                $pack = Get-Content -LiteralPath $inv.jsonPath -Raw | ConvertFrom-Json
                $pack.schemaVersion | Should -Be 2
                $yarnRow = @($pack.rows | Where-Object { $_.yarnId -eq $bid }) | Select-Object -First 1
                $yarnRow | Should -Not -BeNullOrEmpty
                $yarnRow.proposedDecision | Should -Not -BeNullOrEmpty
                $yarnRow.decision | Should -Be 'review'

                { Invoke-MetraYarnPlanBoardInventoryApply -Root $root } | Should -Throw -ExpectedMessage '*Confirm*'
                $script:pbWrites | Should -Be 0

                $applyReview = Invoke-MetraYarnPlanBoardInventoryApply -Root $root -Confirm
                $applyReview.skippedReview | Should -BeGreaterThan 0
                $applyReview.applied | Should -Be 0
                $script:pbWrites | Should -Be 0

                $badPath = Join-Path $root 'plan-board-inventory.json'
                $bad = @{ schemaVersion = 99; generatedAt = (Get-Date).ToUniversalTime().ToString('o'); inventoryId = 'x'; roots = @(); rows = @() }
                Write-YarnAtomicUtf8Text -Path $badPath -Text (($bad | ConvertTo-Json -Depth 6) + "`n")
                { Invoke-MetraYarnPlanBoardInventoryApply -Root $root -Confirm } | Should -Throw -ExpectedMessage '*schemaVersion*'

                $keepRow = [PSCustomObject]@{
                    rowId            = "yarn:$bid"
                    proposedDecision = 'keep'
                    decision         = 'keep'
                    proposedBoard    = 'Backlog'
                    proposedStage    = 2
                    decisionReason   = $null
                    cursorPlan       = $null
                    yarnId           = $bid
                    notionPageId     = $null
                    sourceType       = 'yarn'
                    sourcePath       = $null
                    reasonCodes      = @()
                    evidence         = @()
                    title            = 'No Plan Idea'
                }
                $stalePack = @{
                    schemaVersion = 2
                    generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
                    inventoryId   = 'stale-test'
                    roots         = @()
                    rows          = @($keepRow)
                }
                Write-YarnAtomicUtf8Text -Path $badPath -Text (($stalePack | ConvertTo-Json -Depth 8) + "`n")
                [void](Set-YarnBacklogItemStatus -Root $root -BacklogId $bid -Status 'approved' -SkipPlanBoard)
                $stale = Invoke-MetraYarnPlanBoardInventoryApply -Root $root -Confirm
                $stale.skippedStale | Should -BeGreaterThan 0
                $stale.applied | Should -Be 0

                $malformed = [PSCustomObject]@{
                    rowId            = 'keep-bad'
                    proposedDecision = 'keep'
                    decision         = 'keep'
                    proposedBoard    = 'Backlog'
                    proposedStage    = 8
                    cursorPlan       = $null
                    yarnId           = $bid
                    notionPageId     = $null
                    sourceType       = 'yarn'
                    title            = 'x'
                }
                # approved item: live Loom/5 supersedes malformed keep
                Write-YarnAtomicUtf8Text -Path $badPath -Text ((@{
                            schemaVersion = 2
                            generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
                            inventoryId   = 'malform'
                            roots         = @()
                            rows          = @($malformed)
                        } | ConvertTo-Json -Depth 8) + "`n")
                $mf = Invoke-MetraYarnPlanBoardInventoryApply -Root $root -Confirm
                ($mf.skippedStale + $mf.failed + $mf.Failed) | Should -BeGreaterThan 0

                $dropNoId = [PSCustomObject]@{
                    rowId            = 'drop-noid'
                    proposedDecision = 'drop'
                    decision         = 'drop'
                    proposedBoard    = 'Drop'
                    proposedStage    = 8
                    cursorPlan       = 'ghost.plan.md'
                    yarnId           = $null
                    notionPageId     = $null
                    sourceType       = 'cursor-plan'
                    title            = 'ghost'
                }
                Write-YarnAtomicUtf8Text -Path $badPath -Text ((@{
                            schemaVersion = 2
                            generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
                            inventoryId   = 'drop'
                            roots         = @()
                            rows          = @($dropNoId)
                        } | ConvertTo-Json -Depth 8) + "`n")
                $dr = Invoke-MetraYarnPlanBoardInventoryApply -Root $root -Confirm
                $dr.failed | Should -BeGreaterThan 0
                @($dr.Actions | Where-Object { $_.error -eq 'drop-requires-stable-identity' }).Count | Should -Be 1
            }
            finally {
                $script:YarnPlanBoardOverride = $null
                $script:pbWrites = 0
                Remove-Item Env:METRA_NOTION_API_KEY -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'continues after one upsert failure and reports partial success fields' {
        InModuleScope Yarn {
            $root = Join-Path $env:TEMP ("yarn-pb-partial-" + [guid]::NewGuid().ToString('n'))
            $script:upsertN = 0
            try {
                Initialize-MetraYarnLayout -Root $root
                [void](Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                            title = 'A'; status = 'idea'; formalPlanPath = 'a.plan.md'; projectKey = 'Metra'
                            primarySourceKey = 'capture:a'; sources = @('capture:a'); sourceText = 'A'
                        }) -SkipPlanBoard)
                [void](Sync-YarnBacklogItem -Root $root -Incoming ([PSCustomObject]@{
                            title = 'B'; status = 'idea'; formalPlanPath = 'b.plan.md'; projectKey = 'Metra'
                            primarySourceKey = 'capture:b'; sources = @('capture:b'); sourceText = 'B'
                        }) -SkipPlanBoard)
                $script:YarnPlanBoardOverride = {
                    param($req)
                    if ($req.Operation -eq 'upsert') {
                        $script:upsertN++
                        if ($script:upsertN -eq 1) { throw 'notion one-item fail' }
                        return [PSCustomObject]@{ outcome = 'created'; pageId = "p-$($script:upsertN)"; projection = $req.Projection }
                    }
                    if ($req.Operation -eq 'rest') {
                        return [PSCustomObject]@{ results = @(); has_more = $false }
                    }
                    return $null
                }
                $env:METRA_NOTION_API_KEY = 'test-token-not-real'
                Write-YarnAtomicUtf8Text -Path (Join-Path $root 'plan-board.settings.json') -Text (@{ DatabaseId = 'db-test' } | ConvertTo-Json)
                $s = Invoke-MetraYarnPlanBoardSync -Root $root
                $s.failed | Should -BeGreaterThan 0
                $s.applied | Should -BeGreaterThan 0
                $s.scanned | Should -BeGreaterThan 0
            }
            finally {
                $script:YarnPlanBoardOverride = $null
                $script:upsertN = 0
                Remove-Item Env:METRA_NOTION_API_KEY -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
