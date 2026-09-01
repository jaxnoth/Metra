# Loom / Metra — git track separation (Track G)

**Date:** 2026-08-31 (Loom rename shipped)  
**Purpose:** Keep Loom rename commits reviewable. **Do not merge mixed diffs.**

Product name: **Loom**. Module: `modules/Loom/`. CLI: `.\metra.ps1 loom`.

---

## Track G — Loom rename (shipped)

| Path | Role |
|------|------|
| `modules/Loom/` | Loom module (Domain, Storage, Runner, Migrate, Adapters) |
| `scripts/private/Loom.ps1` | Metra shim |
| `tests/Loom/*.Tests.ps1` | Module tests |
| `tests/Metra.Loom.Tests.ps1` | Façade + CLI tests |
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
