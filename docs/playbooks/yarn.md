# Yarn intake playbook (A0–A4)

## Route here when

`yarn`, intake backlog, Capture→plan, Future-Dev scan, pack freshness, plan approve / Loom handoff.

## Commands

```powershell
.\metra.ps1 yarn status
.\metra.ps1 yarn scan
.\metra.ps1 yarn backlog
.\metra.ps1 yarn daily
.\metra.ps1 yarn synthesize -BacklogId <id> -Confirm
.\metra.ps1 yarn pack -BacklogId <id>
.\metra.ps1 yarn reconcile [-DryRun]
.\metra.ps1 yarn pending
.\metra.ps1 yarn plan approve -BacklogId <id> -Confirm
.\metra.ps1 yarn plan approve -Path <formal.plan.md> -Confirm
```

## Authority

- `scan` upserts/ranks only
- `daily` is read-only unless `-Reconcile`
- `reconcile` may template-synthesize Capture items, pack ready-enough plans, and retry Loom handoff (pending|failed)
- `yarn plan approve -Confirm` is the sole human approval path (requires pending-bing + fresh pack)
- Yarn never writes Loom queue/journal files; Loom `Invoke-MetraLoomIngestApprovedPlan` owns ingest
- Plan review / Pending Bing live here — not in Loom daily §3

## Related

Loom owns queue execution after handoff (A4: one active lane per `projectKey`, atomic claim, `accepted-pending-commit` + local commit verify). See [loom.md](loom.md). Atlas intake is Phase B (post-A4 Bing stop).
