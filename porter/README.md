# Porter

Metra **Porter** transports Metra-product continuity files for the Cursor Project (plan snapshots, freshness, scope). Named for carrying the pack to cloud / Project shared context - not for portfolio routing.

Cursor Project "shared context" has no documented external write API. Porter owns the pack Metra controls:

1. Lives in the Metra git checkout under `porter/` (cloud clone can read it once on the remote, or the Project coordinator pins these paths into Product shared context).
2. Is refreshed by `scripts/Invoke-MetraPorter.ps1` (manual now; Yarn schedule pulse sibling later).
3. Does **not** auto-commit. Porter updates the working tree and `%LOCALAPPDATA%\Metra\porter\` only.

## Layout

| Path | Role |
|------|------|
| `README.md` | This file (tracked) |
| `scope.json` | Metra-product-only stem filter (tracked) |
| `manifest.json` | Freshness stamp (generated, gitignored) |
| `OPEN-PLANS.md` | Index of **in-scope** Metra-product plans (generated, gitignored) |
| `plans/` | Snapshots of Cursor-local plan bodies for in-scope stems only (generated, gitignored) |
| `manifest.example.json` | Shape reference (tracked) |

Porter is **deny-by-default**: a stem must match an include prefix in `scope.json`. Portfolio plans that merely live in Metra's affiliation index (Orion, TicketWatch, ITSM mining, etc.) are skipped. Edit `scope.json` when a new Metra-product stem family appears.

## Already visible without Porter snapshots

Cloud Agents with the Metra repo already see:

- `docs/Cursor-Project-Metra-Charter.md`
- `docs/Cursor-Project-Metra-Voice.md`
- `plans/*.plan.md` with `authority: repo` (when in Porter scope)
- `AGENTS.md`, playbooks, base persona rules

Porter exists for what the clone **does not** have: Cursor working plan bodies under the user profile, plus a single freshness manifest.

## Bootstrap (operator)

1. Create the Metra Cursor Project (Agents Window → Projects → New Project → Metra GitHub workspace).
2. Paste the coordinator brief from `docs/Cursor-Project-Metra-Charter.md`.
3. Ask the coordinator to treat `porter/` as the Metra pack and pin Charter + Voice + this folder into Project shared context.
4. Run Porter locally:

```powershell
cd C:\Projects\_meta
pwsh -File .\scripts\Invoke-MetraPorter.ps1
```

5. When you want cloud clones to see new plan snapshots without waiting for Product shared-context sync, commit+push generated files **only if** you intentionally un-ignore them. Default: generated files stay gitignored; Product shared context or a local-agent hop is the no-commit path.

## Pulse contract

Attached to **`MetraYarnLoomPulse`** (same 15-minute task as Scout): after Scout-only loom loop, Pulse runs `scripts/Invoke-MetraPorter.ps1`. No separate scheduled task. No auto-commit. Porter soft-fails so Scout canary exit codes stay authoritative.

Manual:

```powershell
pwsh -File .\scripts\Invoke-MetraPorter.ps1
.\metra.ps1 yarn schedule pulse run
```
