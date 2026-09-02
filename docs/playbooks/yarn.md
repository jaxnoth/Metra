# Yarn intake playbook (A0–A2)

## Route here when

`yarn`, intake backlog, Capture→plan, Future-Dev scan, pack freshness for plans.

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
```

## Authority (A0–A2)

- `scan` upserts/ranks only
- `daily` is read-only unless `-Reconcile`
- `reconcile` may template-synthesize Capture items and pack ready-enough plans
- Approval / Loom handoff not available (`yarn plan approve` throws until A3)

## Related

Loom owns queue execution after A3 handoff. Atlas intake is Phase B.
