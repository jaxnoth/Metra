# Porter

Metra **Porter** transports Metra-product continuity files for the Cursor Project (plan snapshots, freshness, scope, and handoff **state storage**). Named for carrying the pack to cloud / Project shared context - not for portfolio routing, and not for Inspect or ship authority.

**Decision sentence:** Porter remains a transport product. DESK-HANDOFF workflow state may live inside the porter pack, but Porter is not the authority for implementation lifecycle, ship status, or Bing decisions. Automation (Pulse observing handoff state) may advance work through evidence generation to `ready-for-bing`. Human authority is required only for gates that represent judgment, risk acceptance, or durable shipment.

## Authority (short)

| Product | Owns | Does not own |
|---------|------|--------------|
| **Porter** | Continuity transport; byte-identical plan mirrors; **storage** of handoff state files | Running Inspect; Bing affirm; ship; implementation lifecycle authority |
| **Handoff** (concept) | Workflow states `awaiting-prepare-bing` / `ready-for-bing` / `cleared` / `stale` | Transport of plan bodies; Inspect engines |
| **Pulse / Schedule** | Observes handoff; **invokes** `inspect prepare-bing` (soft-fail) | Authorizing ship |
| **Inspect** | Evidence generation (prepare-bing / pack) | Ship decision |
| **Operator** | Bing affirm, reject, durable ship judgment | Being the prepare-bing glue |

**Scar:** Porter mirrors are transport artifacts and **must remain byte-identical** to their source Approved leaf. Never edit `porter/plans/*` by hand.

## Layout

| Path | Role | Git |
|------|------|-----|
| `README.md` | This file | Tracked |
| `scope.json` | Metra-product-only stem filter | Tracked |
| `OPEN-PLANS.md` | Index of in-scope Metra-product plans | **Tracked** (commit after refresh when Project should see updates) |
| `plans/*.plan.md` | Byte-identical mirrors of Approved leaves | **Tracked** (same) |
| `plans/README.md` | Mirror folder note | Tracked |
| `manifest.json` | Freshness stamp | Gitignored |
| `handoff.json` | Machine handoff state | Gitignored |
| `DESK-HANDOFF.md` | Human-readable handoff table (generated) | Gitignored |
| `manifest.example.json` | Shape reference | Tracked |

Porter is **deny-by-default**: a stem must match an include prefix in `scope.json`.

## Sources

1. **`plans/index.yaml`** - in-scope index rows (repo or cursor authority). Index wins for metadata when a stem exists there.
2. **Cursor discovery** - `%USERPROFILE%\.cursor\plans\*.plan.md` whose normalized stem is not already in the index, matches `scope.json`, and passes the **Approved-only** gate (`status: Approved` or `approveForLoom: true`).

## Commands

```powershell
cd C:\Projects\_meta
.\metra.ps1 porter refresh          # Invoke-MetraPorter.ps1 (mirrors + OPEN-PLANS)
.\metra.ps1 porter publish          # git add tracked pack files (no auto-commit)
.\metra.ps1 porter handoff set -Stem <stem> [-Path <cursorLeaf>] [-Note '...']
.\metra.ps1 porter handoff show
.\metra.ps1 porter handoff clear -Stem <stem>
.\metra.ps1 porter handoff stale -Stem <stem>
.\metra.ps1 porter prep             # Pulse also runs this: observe awaiting -> prepare-bing
```

`handoff set` freezes Project coding for that stem (`awaiting-prepare-bing`). Pulse after Porter calls `porter prep`, which may invoke Inspect and advance to `ready-for-bing`. Never affirms Bing.

## Pulse contract

Attached to **`MetraYarnLoomPulse`**: after Scout-only loom loop → Porter refresh → Inspect prep (if any handoff row is `awaiting-prepare-bing`). Soft-fail both Porter and prep so Scout exit codes stay authoritative. No Pulse auto-commit. No Bing affirm.

## Path: Approve → Porter → Project → Handoff → Pulse → Bing

1. Surveyor Approve on Cursor leaf.
2. Porter refresh (manual or Pulse).
3. Optional: `porter publish` + commit so cloud clones see mirrors.
4. Project implements (Context sync from Porter on start - see `docs/playbooks/project-lane.md`).
5. Code-complete: `porter handoff set -Stem ...` (freeze).
6. Pulse `porter prep` → Inspect prepare-bing → `ready-for-bing`.
7. Operator Bing affirm → commit/ship.

## Related

- `docs/Cursor-Project-Metra-Charter.md`
- `docs/playbooks/project-lane.md`
- `docs/Decisions.md` (Porter / Handoff / Inspect entries)
- `scripts/Invoke-MetraPorter.ps1`, `scripts/Invoke-MetraPorterCli.ps1`
- `modules/Yarn/Private/Schedule.ps1`
