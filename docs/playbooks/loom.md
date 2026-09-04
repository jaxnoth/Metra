# Loom operator playbook

Governed execution harness (queue, journal, triage, branch runner). Metra hosts the CLI; Loom owns runtime state.

## Terminology

| Term | Meaning |
|------|---------|
| **Loom** | Governed execution product/module |
| **Metra** | Host and operator surface |
| **Atlas** | Portfolio memory (plans context via cache) |
| **Forge** | Generation/build (unrelated to Loom queue) |
| **AP-\*** | Work-item identity namespace - not a product-name abbreviation |
| **CAND-\*** | Triage candidate identity namespace |

## Commands

```powershell
.\metra.ps1 loom status
.\metra.ps1 loom triage
.\metra.ps1 loom plans list
.\metra.ps1 loom enqueue -FromPlan -Path <plan.md>
.\metra.ps1 loom run -Id <AP-...> -DryRun
.\metra.ps1 loom run -Id <AP-...> -Confirm          # implement + auto-chain review (Slice 4)
.\metra.ps1 loom run -Id <AP-...> -Confirm -NoChainReview   # implement only; stop at reviewing
.\metra.ps1 loom review -Id <AP-...>               # dry-run assess (no engines)
.\metra.ps1 loom review -Id <AP-...> -Confirm      # live inspect + verify + commit + completed
.\metra.ps1 loom daily                             # intake (sections 1-3) + prior-day pack-diff
.\metra.ps1 loom daily pack-diff                   # pack-diff manifest only
.\metra.ps1 loom daily approve -PlanPath .\daily\2026-09-01-plan.md   # preview (no writes)
.\metra.ps1 loom daily approve -PlanPath ... -Confirm                 # apply batch
.\metra.ps1 loom daily approve -PlanPath ... -Confirm -Merge          # accept + local merge (no push)
.\metra.ps1 loom loop -UntilDailyGate -DryRun                       # preview one eligible dequeue (Slice 6)
.\metra.ps1 loom loop -UntilDailyGate -Confirm                      # one item overnight to completed (not accepted)
.\metra.ps1 loom pattern score                                      # Slice 8 promote candidates
.\metra.ps1 loom pattern promote -Path <one-pattern.md> -Preview
.\metra.ps1 loom pattern promote -Path <one-pattern.md> -Confirm    # Atlas put (add -Publish to push)
```

## A4 per-project lane and acceptance

| Rule | Detail |
|------|--------|
| Canonical identity | Queue items persist top-level `projectKey`. Legacy resolves once from `yarnHandoff.projectKey` then `project.registryName` under the claim/migration lock. |
| Lane-holding | At most one active item per `projectKey`: `claimed`, `implementing`, `reviewing`, `completed`, `accepted-pending-commit`, or `blocked` with `blockedFrom` from an active state |
| Atomic claim | `run` and `loop` share claim helpers under the `loom_queue` namespace lock: reload → busy lanes → select → `queued`→`claimed` → persist and journal → unlock |
| Selection | Among free lanes: `scores.total` desc → `effectiveImpact` desc → `createdAt` asc → `id` asc |
| Acceptance | `completed` → `accepted-pending-commit` (human ACCEPT; lane busy) → `accepted` after observe-only local commit verification. No commit/push/merge in verify. Verified `accepted` fail-open notifies Yarn Plan Board (Shipped); `accepted-pending-commit` does not. |
| Ritual split | Triage no longer promotes Capture→candidate. Daily §3 points plan review at Yarn. Manual `loom enqueue -FromPlan` remains break-glass for Approved plans only. Allowed roots include `%USERPROFILE%\.cursor\plans`, `<project>\plans` (Yarn handoff copies), and legacy `<project>\docs`. |

## Slice 6 loop (unattended to daily gate)

| Rule | Detail |
|------|--------|
| Scope | **One** eligible `queued` item per invocation; stops at `completed` |
| Selection | Atomic claim among free `projectKey` lanes (see A4) |
| Policy | Fail closed: missing `classification` rejects; code-only; routing >= 0.85; verify commands present |
| Pause | Tier 1 engine faults set `loopPaused`, `pausedAtUtc`, `pauseReason` in `state.json` |
| Pause enforcement | Subsequent `loom loop` emits reason + age; **no dequeue** while paused |
| Supervised path | `loom run -Id <AP-...> -Confirm` (same claim authority) |
| Forbidden | No push, merge, `daily approve`, auto-enqueue, multi-item dequeue |

Clear pause (v1): edit `%LOCALAPPDATA%\Metra\loom\state.json` (`loopPaused: false`). Slice 6b may add `loom loop resume`.

Morning handoff unchanged: `loom daily` → pack-diff review → `daily approve -Confirm`.

## Slice 8 Pattern promote (Atlas publication)

| Rule | Detail |
|------|--------|
| Commands | `loom pattern score`; `loom pattern promote -Path <md> -Preview\|-Confirm` optional `-Publish` |
| Gate | Item must be **accepted**; path under `docs/patterns/`; path in accepted commit range; hash matches accepted revision; not already promoted at same hash |
| Authority | Tracked Pattern file stays authoritative; Atlas holds discoverability copy only |
| Ledger | `{loomRoot}/patterns/promotions.json` + journal `pattern-promote` |
| Pattern | [guild-knowledge-promotion](../patterns/guild/knowledge-promotion.md) |

## Slice 4 review (completed vs accepted)

| Rule | Detail |
|------|--------|
| Transition owner | `Invoke-MetraLoomReview` only - adapters return evidence |
| Live execution | `-Confirm` required on `run` and `review` |
| Commit order | When `completionCommitPolicy` is `required` (default), commit before `completed` |
| Exits from `reviewing` | `completed`, `implementing`, `blocked` only |
| Recovery | `loom review -Confirm` resumes idempotently from `review.json` in run dir |

Verify commands in contracts use structured entries (`executable`, `arguments`, `workingDirectory`, `timeoutSeconds`), not bare shell strings.

## Slice 5 daily gate (operator acceptance)

| Rule | Detail |
|------|--------|
| Transition owner | `Invoke-MetraLoomDailyApprove` / accept+verify helpers only may exit `completed` |
| Preview | Without `-Confirm`: validate + preview; no queue, journal, acceptance-record, or git writes |
| Batch atomicity | Any invalid directive or gate failure blocks the entire batch (zero mutations) |
| Per-project gate | No new `run` or `enqueue` for project `P` while any lane-holding item for `P` exists (through `accepted-pending-commit`) |
| Evidence binding | ACCEPT requires pack-diff manifest entry matching `completedCommit` and `completionCycleId` |
| Manual test | `MANUAL-TEST-DONE` directive required when `manualTestClass` is not `none`; override via `-OverrideManualTest -OverrideReason` |
| Merge | Optional `-Merge` after **verified** `accepted` only (local `git merge`, no push). Verify failures stay `accepted-pending-commit`. |

Directive grammar (full line, checked checkbox):

```text
- [x] ACCEPT AP-YYYYMMDD-NNNN
- [x] MANUAL-TEST-DONE AP-YYYYMMDD-NNNN
- [x] RETRY AP-YYYYMMDD-NNNN
- [x] BLOCK AP-YYYYMMDD-NNNN
```

Pack-diff output: `{loomRoot}/daily/{ReviewDate}-pack-diff/` (manifest + per-project summaries). Full inspect packs copied to `{loomRoot}/daily/{ReviewDate}-bing/{projectKey}/`.

## Storage migration

When upgrading from AutoProgram storage layout:

```powershell
.\metra.ps1 loom migrate              # dry-run (no writes)
.\metra.ps1 loom migrate -WhatIf
.\metra.ps1 loom migrate -Apply -Confirm
```

- Copy-first; source `Metra\autoprogram\` preserved
- Does **not** rewrite `execution.branch` in queue JSON
- Refuses when mutation mutex is held

## Branch prefixes

| When | Prefix |
|------|--------|
| New enqueue | `loom/{project}/{date}/{id}` |
| Existing in-flight items | `autoprogram/...` preserved in JSON |
| Runner checkout | Accepts both `loom/` and `autoprogram/` |

## Deprecated CLI

`.\metra.ps1 autoprogram` remains as a temporary alias (deprecation warning). Use `loom`.

## Related

- [loom-product-boundary.plan.md](../loom-product-boundary.plan.md)
- [inspect-loop.md](inspect-loop.md) (Metra inspect gate for commits)
- [yarn.md](yarn.md) (intake + Plan Board v2 projection: `plan-board sync` and Bing `plan-board inventory`)
