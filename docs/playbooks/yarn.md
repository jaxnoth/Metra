# Yarn intake playbook (A0–A4 + Phase B Atlas)

## Route here when

`yarn`, intake backlog, Capture→plan, Future-Dev scan, Atlas memory intake, pack freshness, plan approve / Loom handoff.

## Commands

```powershell
.\metra.ps1 yarn status
.\metra.ps1 yarn scan
.\metra.ps1 yarn backlog
.\metra.ps1 yarn daily
.\metra.ps1 yarn synthesize -BacklogId <id> -Confirm
.\metra.ps1 yarn synthesize -FromMemory <stableId> -Confirm
.\metra.ps1 yarn pack -BacklogId <id>
.\metra.ps1 yarn reconcile [-DryRun]
.\metra.ps1 yarn pending
.\metra.ps1 yarn plan approve -BacklogId <id> -Confirm
.\metra.ps1 yarn plan approve -Path <formal.plan.md> -Confirm
.\metra.ps1 plan-board status
.\metra.ps1 plan-board sync -DryRun
.\metra.ps1 plan-board sync
```

## Plan Board projection

Notion Plan Board is an **ops projection** only. Yarn backlog status and Loom verified `accepted` remain systems of record.

Copy `modules/Yarn/config/plan-board.example.json` to the Yarn root settings file (placeholders only in the example):

`%LOCALAPPDATA%\Metra\yarn\plan-board.settings.json`

That path is `Join-Path (Get-MetraYarnRoot) 'plan-board.settings.json'` (override with `METRA_YARN_ROOT` if set). Token: `METRA_NOTION_API_KEY`, else Atlas Notion `apiKey`. Missing Plan Board never blocks intake or approve.

`yarn scan` skips per-item Plan Board notifies. Full catch-up is `plan-board sync`, which rebuilds from Yarn backlog + plan-links + Loom queue plan paths + existing Plan Board cards (not event history alone).
| Event | Board update? |
|-------|---------------|
| Yarn status persisted: `idea` \| `ready` \| `pending-bing` \| `stale-pack` \| `approved` \| `parked` \| `rejected` | Yes (fail-open, once after persist; not during bulk `scan`) |
| Successful Loom handoff | Yes |
| Verified Loom `accepted` (after local commit verify) | Yes (Shipped) |
| `accepted-pending-commit` / other Loom hops | No |
| Failed Yarn mutation or failed handoff | No |

Resolver uses **explicit precedence** (not highest Stage). Manual Notion Board/Stage edits are non-authoritative and may be overwritten. `-Inventory` is unsupported in v1.

## Authority

- `scan` upserts/ranks only (Capture + Future-Dev + Atlas Plan/Roadmap/Parked)
- `daily` is read-only unless `-Reconcile`
- `reconcile` may template-synthesize Capture items, pack ready-enough plans, and retry Loom handoff (pending|failed). Atlas has no Capture-style auto-synth exception.
- `yarn synthesize -FromMemory <stableId> -Confirm` is the explicit Atlas draft path (`atlas sync pull` never synthesizes)
- `yarn plan approve -Confirm` is the sole human approval path (requires pending-bing + fresh pack)
- Yarn never writes Loom queue/journal files; Loom `Invoke-MetraLoomIngestApprovedPlan` owns ingest
- Plan review / Pending Bing live here — not in Loom daily §3
- Atlas providers return data only (local mirror); Yarn never promotes OCC/Decisions from Atlas
- Plan Board never Approves or enqueues; sync never writes Yarn/Loom status from Notion

## Phase B (Atlas)

- Post-sync cache = Atlas local mirror (`data/sync/objects` + stub), not a Yarn content cache
- Backlog fields: `atlasStableId`, `memoryLane=atlas`, `atlasKind` (Plan|Roadmap|Parked)
- Offline: empty Atlas set; Capture/Future-Dev continue; status/daily show `memoryLane=paused`

## Related

Loom owns queue execution after handoff (A4: one active lane per `projectKey`, atomic claim, `accepted-pending-commit` + local commit verify). Verified accept also notifies Plan Board (Shipped). See [loom.md](loom.md). Slice 7 Phase C AutoProgram leftovers are closed (naming/docs only; alias/migrate stay in the Loom playbook).
