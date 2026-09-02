---
metraMemory: procedural-architectural
patternSchemaVersion: 1
defaultContext: false
patternId: loom-project-lane
owner: loom
cabinet: null
status: active
implemented: true
loadWhen:
  - loom run
  - loom loop
  - project lane
  - branch isolation
ceiling:
  - At most one active lane-holding item per projectKey
  - Slice 6 loop dequeues one eligible item and stops at completed
  - No unattended push, merge, or accepted
  - accepted-pending-commit holds the lane until local commit verify
relatedDecisions:
  - "2026-09-02 Loom Slice 6 unattended loop"
  - "2026-09-01 Loom Slice 5 daily gate"
relatedPlaybooks:
  - docs/playbooks/loom.md
supersedes: null
---

# Loom Project Lane Pattern

## Intent

Governs concurrency and isolation: one project lane at a time, isolated item branches, overnight loop bounds.

## Actors

| Actor | Role |
|-------|------|
| Loom lane | Atomic claim of next eligible item; tracks busy projectKeys |
| Runner | Clean tree, branch checkout, single implementer invocation |
| Loop (Slice 6) | One dequeue to `completed`; pause on Tier 1 engine faults |
| Operator | Supervised `loom run -Confirm`; morning daily gate |

## Inputs / outputs

**In:** Queued eligible items; optional `-UntilDailyGate`.

**Out:** Item on `loom/{project}/{date}/{id}` (or legacy `autoprogram/` prefix preserved); lane held through claim/implement/review/completed/`accepted-pending-commit` until local commit verify yields `accepted`.

## Rules and ceilings

1. Lane-holding statuses live in one helper (`Get-MetraLoomLaneHoldingStatuses`): `claimed`, `implementing`, `reviewing`, `completed`, `accepted-pending-commit`, plus `blocked` only when `blockedFrom` was active.
2. Claim skips projectKeys already busy; one active lane per `projectKey`. Canonical key is persisted `projectKey`.
3. Per-project gate: no new `run` or `enqueue` for project P while any lane-holding item for P exists.
4. Slice 6: one eligible `queued` item per invocation via shared atomic claim (total → effectiveImpact → createdAt → id); fail closed if classification missing; stop at `completed` (not `accepted`).
5. Forbidden unattended: push, merge, `daily approve`, auto-enqueue, multi-item dequeue.
6. Runner requires clean baseline; out-of-scope path edits rejected.

## State or contract references

- `modules/Loom/Private/Lane.ps1`, `Loop.ps1`, `Runner.ps1`
- Branch prefixes in playbook; `implementation-result.schema.json`

## Flow

```text
queued eligible items
  -> atomic claim next for free projectKey
  -> clean tree + item branch
  -> implement (+ optional chained review)
  -> completed (lane still held)
  -> daily ACCEPT -> accepted-pending-commit
  -> local commit verify -> accepted (lane free)
```

## Human ritual

[loom.md](../playbooks/loom.md) A4 lane, Slice 6 loop, and Slice 5 daily gate sections.

## Anti-patterns

- Parallel implementers on the same projectKey
- Overnight loop treating `completed` as merge authority
- Clearing `loopPaused` without addressing the Tier 1 engine fault
- Treating every historical `blocked` item as lane-holding without `blockedFrom`
- Falling back to registryName on every scheduler read instead of one-time normalize under lock

## Evidence

- Contract / code: `Lane.ps1` (`Get-MetraLoomLaneHoldingStatuses`, `Invoke-MetraLoomClaimNextEligible`); `Loop.ps1` (`Get-LoomEligibleQueuedItems`)
- Tests: `tests/Loom/Loom.A4.Lane.Tests.ps1`, `Loom.Loop.Tests.ps1`, `Loom.Runner.Tests.ps1`
- Playbook: `docs/playbooks/loom.md` (A4, Slice 6, branch prefixes, per-project gate)
- Decision scar: Loom Slice 6 (2026-09-02); Slice 5 daily gate (2026-09-01)
- Shipped slice: Loom Slices 3 and 6 + A4 lane ship
