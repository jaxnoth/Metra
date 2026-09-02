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
                $script:YarnHostRootOverride = $hostRoot
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
                (Get-Content -LiteralPath $synth.planPath -Raw) | Should -Match 'Pending Bing Review'
                (Get-Content -LiteralPath $synth.planPath -Raw) | Should -Not -Match '(?m)^status:\s*Approved'

                $after = @(Get-MetraYarnBacklog -Root $root) | Where-Object { $_.id -eq $item.id } | Select-Object -First 1
                $after.readyEnough | Should -BeTrue

                $pack = Invoke-MetraYarnPack -Root $root -MetraRoot $hostRoot -BacklogId $item.id
                $pack.outcome | Should -Be 'packed'
                $pack.freshCheck.fresh | Should -BeTrue

                { Invoke-YarnCommand -Subcommand plan -ArgsRest @('approve', '-Confirm') -Root $root } | Should -Throw
            }
            finally {
                $script:YarnHostRootOverride = $null
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
            $docs = Join-Path $root "docs"
            try {
                Initialize-MetraYarnLayout -Root $root
                New-Item -ItemType Directory -Path $docs -Force | Out-Null
                $planPath = Join-Path $docs "approve-me.plan.md"
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
                $failed = Invoke-MetraYarnPlanApprove -Root $root -BacklogId $item.id -Confirm
                $failed.outcome | Should -Be "approved-handoff-failed"
                $link = @(Get-YarnPlanLinks -Root $root) | Where-Object { $_.backlogId -eq $item.id } | Select-Object -First 1
                $link.planStatus | Should -Be "Approved"
                $link.approval.approvalRevision | Should -Be $planHash
                $link.approval.planContentHash | Should -Be $planHash
                $link.loomHandoff.state | Should -Be "failed"
                (Get-Content -LiteralPath $planPath -Raw) | Should -Match "status:\s*Approved"

                $script:YarnLoomIngestOverride = {
                    param($req)
                    [PSCustomObject]@{
                        outcome = "enqueued"; queueItemId = "AP-20260902-0001"
                        approvalId = $req.ApprovalId; approvalRevision = $req.ApprovalRevision
                    }
                }
                $retry = Invoke-MetraYarnReconcile -Root $root
                $retry.actions | Where-Object { $_.outcome -eq "approved-enqueued" } | Should -Not -BeNullOrEmpty
                $link2 = @(Get-YarnPlanLinks -Root $root) | Where-Object { $_.backlogId -eq $item.id } | Select-Object -First 1
                $link2.loomHandoff.state | Should -Be "succeeded"
                $link2.loomHandoff.queueItemId | Should -Be "AP-20260902-0001"

                # second approve same revision stays one logical handoff success
                $again = Invoke-MetraYarnPlanApprove -Root $root -BacklogId $item.id -Confirm
                $again.outcome | Should -BeIn @("approved-enqueued", "handoff-already-succeeded")
            }
            finally {
                $script:YarnLoomIngestOverride = $null
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
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
