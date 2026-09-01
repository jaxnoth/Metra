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
```

## Slice 4 review (completed vs accepted)

| Rule | Detail |
|------|--------|
| Transition owner | `Invoke-MetraLoomReview` only - adapters return evidence |
| Live execution | `-Confirm` required on `run` and `review` |
| Commit order | When `completionCommitPolicy` is `required` (default), commit before `completed` |
| Exits from `reviewing` | `completed`, `implementing`, `blocked` only |
| Recovery | `loom review -Confirm` resumes idempotently from `review.json` in run dir |

Verify commands in contracts use structured entries (`executable`, `arguments`, `workingDirectory`, `timeoutSeconds`), not bare shell strings.

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
