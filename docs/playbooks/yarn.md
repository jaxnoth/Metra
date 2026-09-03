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
```

## Authority

- `scan` upserts/ranks only (Capture + Future-Dev + Atlas Plan/Roadmap/Parked)
- `daily` is read-only unless `-Reconcile`
- `reconcile` may template-synthesize Capture items, pack ready-enough plans, and retry Loom handoff (pending|failed). Atlas has no Capture-style auto-synth exception.
- `yarn synthesize -FromMemory <stableId> -Confirm` is the explicit Atlas draft path (`atlas sync pull` never synthesizes)
- `yarn plan approve -Confirm` is the sole human approval path (requires pending-bing + fresh pack)
- Yarn never writes Loom queue/journal files; Loom `Invoke-MetraLoomIngestApprovedPlan` owns ingest
- Plan review / Pending Bing live here — not in Loom daily §3
- Atlas providers return data only (local mirror); Yarn never promotes OCC/Decisions from Atlas

## Phase B (Atlas)

- Post-sync cache = Atlas local mirror (`data/sync/objects` + stub), not a Yarn content cache
- Backlog fields: `atlasStableId`, `memoryLane=atlas`, `atlasKind` (Plan|Roadmap|Parked)
- Offline: empty Atlas set; Capture/Future-Dev continue; status/daily show `memoryLane=paused`

## Related

Loom owns queue execution after handoff (A4: one active lane per `projectKey`, atomic claim, `accepted-pending-commit` + local commit verify). See [loom.md](loom.md). Slice 7 Phase C AutoProgram leftovers are closed (naming/docs only; alias/migrate stay in the Loom playbook).
