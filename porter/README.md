# Porter

Metra **Porter** transports Metra-product continuity between the desk and the Cursor Project. Named for carrying packs - not for portfolio routing, Inspect, or ship authority.

**Decision sentence:** Porter remains a transport product. DESK-HANDOFF workflow state may live inside the porter pack, but Porter is not the authority for implementation lifecycle, ship status, or Bing decisions. Automation (Pulse observing handoff state) may advance work through evidence generation to `ready-for-bing`. Human authority is required only for gates that represent judgment, risk acceptance, or durable shipment.

## Plan shelf (locked target)

| Surface | Role |
|---------|------|
| Agent Store `docs/plans/<stem>.plan.md` | Project-visible shelf (drafts pre-Approve; Approved mirror after write-back) |
| `%USERPROFILE%\.cursor\plans\<leaf>.plan.md` | Surveyor Approve only |
| `porter/plans/*` | **Interim** shuttle / pin - not long-term SoT |
| Porter | Desk writer + transport; soft-fail; no auto-commit / affirm |

Conflict **B+A:** pre-Approve Project may write Agent Store drafts; post-Approve Porter owns overwrite of that stem. Skip only when ledger source hash, current Approved desk hash, and destination content hash all match.

### Agent Store write-back

Pulse / `porter refresh` after packing:

1. Resolve `%LOCALAPPDATA%\Metra\porter\cursor-project.local.json` (`projectId` + `projectKey` required).
2. `projectKey` must be `Metra` (case-insensitive) or write-back is skipped (soft-fail). Never write to an arbitrary store.
3. For each in-scope **Approved** desk leaf: write byte-identical body to Agent Store `files/docs/plans/<hyphen-stem>.plan.md` unless ledger hash, source hash, and destination hash already agree. Destination drift after Approve is rewritten even when the desk leaf is unchanged.
4. Non-Approved desk leaves never clobber Agent Store drafts.

Seed config (one-time):

```powershell
Copy-Item .\porter\cursor-project.local.example.json "$env:LOCALAPPDATA\Metra\porter\cursor-project.local.json"
# Edit projectId to the Metra Cursor Project id (placeholder only: REPLACE-WITH-METRA-CURSOR-PROJECT-ID)
```

## Authority (short)

| Product | Owns | Does not own |
|---------|------|--------------|
| **Porter** | Continuity transport; interim pack mirrors; Agent Store Approved write-back; handoff **state storage** | Plan SoT; Surveyor Approve; Bing affirm; ship |
| **Handoff** (concept) | `awaiting-prepare-bing` / `ready-for-bing` / `cleared` / `stale` | Transport of plan bodies; Inspect engines |
| **Pulse / Schedule** | Observes handoff; invokes prepare-bing; runs Porter refresh (incl. write-back) | Authorizing ship |
| **Inspect** | Evidence generation | Ship decision |
| **Operator** | Bing affirm, reject, durable ship judgment | Being the prepare-bing glue |

**Scar:** Never hand-edit `porter/plans/*`. Prefer Agent Store shelf for Project-visible Approved bodies once write-back is seeded.

## Layout

| Path | Role | Git |
|------|------|-----|
| `README.md` | This file | Tracked |
| `scope.json` | Metra-product-only stem filter | Tracked |
| `cursor-project.local.example.json` | projectId + projectKey=Metra shape | Tracked |
| `OPEN-PLANS.md` | Index of in-scope Metra-product plans | Tracked (interim shuttle) |
| `plans/*.plan.md` | Interim byte-identical mirrors | Tracked (interim) |
| `manifest.json` | Freshness stamp | Gitignored |
| `handoff.json` / `DESK-HANDOFF.md` | Handoff machine state | Gitignored |

Machine-private (never git): `%LOCALAPPDATA%\Metra\porter\cursor-project.local.json`, `writeback-ledger.json`.

## Commands

```powershell
cd C:\Projects\_meta
.\metra.ps1 porter refresh          # pack + Agent Store write-back (when configured)
.\metra.ps1 porter refresh -WhatIf  # dry-run counters
.\metra.ps1 porter publish
.\metra.ps1 porter handoff set -Stem <stem>
.\metra.ps1 porter prep
```

## Pulse contract

`MetraYarnLoomPulse`: Scout-only loom → Porter refresh (pack + write-back) → Inspect prep when handoff awaiting. Soft-fail. No auto-commit. No Bing affirm.

## Related

- `docs/Cursor-Project-Metra-Charter.md`
- `docs/playbooks/project-lane.md`
- `docs/Decisions.md`
- `scripts/Invoke-MetraPorter.ps1`, `scripts/Invoke-MetraPorterCli.ps1`
