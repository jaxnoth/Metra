# Loom / Metra - git track separation (Track G)

**Date:** 2026-08-31 (Loom rename shipped)  
**Purpose:** Keep Loom rename commits reviewable. **Do not merge mixed diffs.**

Product name: **Loom**. Module: `modules/Loom/`. CLI: `.\metra.ps1 loom`.

---

## Track G - Loom rename (shipped)

| Path | Role |
|------|------|
| `modules/Loom/` | Loom module (Domain, Storage, Runner, Migrate, Adapters) |
| `scripts/private/Loom.ps1` | Metra shim |
| `tests/Loom/*.Tests.ps1` | Module tests |
| `tests/Metra.Loom.Tests.ps1` | Facade + CLI tests |
| `metra.ps1` | `loom` primary; `autoprogram` deprecated alias |
| `docs/playbooks/loom.md` | Operator playbook |

**Removed:** `modules/AutoProgram/`, `scripts/private/Autoprogram.ps1`

---

## Operator CLI

```powershell
.\metra.ps1 loom status
.\metra.ps1 loom migrate -Apply -Confirm   # production desk migration
.\metra.ps1 autoprogram status             # deprecated alias (warns)
```

See [loom-product-boundary.plan.md](loom-product-boundary.plan.md).

---

## Track H — Slice 4 review and completion (shipped 2026-09-01)

| Path | Role |
|------|------|
| `modules/Loom/Private/Review.ps1` | Review orchestrator, identity, counters, commit transaction |
| `modules/Loom/Adapters/Metra.Adapters.ps1` | Inspect + verify adapters (evidence only) |
| `modules/Loom/Contracts/` | `review-result`, `inspect-result`, `verify-result` schemas |
| `tests/Loom/Loom.Review.Tests.ps1` | Orchestrator, dry-run, completion path |
| `docs/playbooks/loom.md` | Operator commands (`review`, `-NoChainReview`) |

**Inspect pack isolation (Track I):** per-slot `inspect/<Project>/pack-diff.md` and `pack-plan.md` - prerequisite for parallel Bing lanes during Slice 4 gate.
