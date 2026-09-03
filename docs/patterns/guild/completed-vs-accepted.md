---
metraMemory: procedural-architectural
patternSchemaVersion: 1
defaultContext: false
patternId: guild-completed-vs-accepted
owner: loom
cabinet: guild
status: active
implemented: true
loadWhen:
  - completed vs accepted
  - daily approve
  - ACCEPT
  - daily gate
ceiling:
  - Machine completed is evidence; operator acceptance is authority
  - Only daily approve may exit completed toward accepted-pending-commit
  - accepted requires local commit verification evidence
  - No harness may treat its own judgment as operator approval
relatedDecisions:
  - "2026-08-31 Completion is evidence; acceptance is authority"
  - "2026-09-01 Loom Slice 5 daily gate"
relatedPlaybooks:
  - docs/playbooks/loom.md
supersedes: null
---

# Guild Completed vs Accepted Pattern

## Intent

Governs the hard split between machine `completed` and operator `accepted` across Loom (and related write surfaces named in the scar).

## Actors

| Actor | Role |
|-------|------|
| Loom review | May set `completed` when contract met |
| `Invoke-MetraLoomDailyApprove` / accept+verify | Sole owner of exits from `completed` |
| Operator + Bing | Pack-diff review, ACCEPT / RETRY / BLOCK directives |
| Atlas promote (Slice 8) | Requires acceptance before promotable candidates; tracked file stays authoritative |

## Inputs / outputs

**In:** Items in `completed`; daily plan directives; pack-diff manifest bound to completion evidence.

**Out:** `accepted-pending-commit` then `accepted` (optional local merge after verified), retry, or block; acceptance records; never silent self-accept.

## Rules and ceilings

1. Completion without acceptance is forbidden for Loom queue items (and other surfaces listed in the 2026-08-31 scar).
2. Slice 5 / A4: only daily approve helpers transition out of `completed` (to `accepted-pending-commit`, retry, or block).
3. Approve validates the full directive batch before any mutation (atomic batch).
4. ACCEPT requires pack-diff evidence matching `completedCommit` and `completionCycleId`.
5. Manual test checklist must be satisfied (or explicit override) before ACCEPT when required.
6. Local commit verification is observe-only (root/branch/HEAD SHA). Failure stays `accepted-pending-commit` with honest `lastError`.
7. Optional `-Merge` is local only after verified `accepted`; no push in Slice 5.

## State or contract references

- `acceptance-record.schema.json`, `pack-diff-manifest.schema.json`
- `modules/Loom/Private/Daily.ps1`, `Lane.ps1` (`Invoke-MetraLoomAcceptWithLocalCommitVerify`)

## Flow

```text
completed (machine evidence)
  -> loom daily + pack-diff (Bing)
  -> daily approve ACCEPT
  -> accepted-pending-commit (lane busy)
  -> local commit verify
  -> accepted | stay pending with failed verify
  -> optional local merge (no push)
```

## Human ritual

[loom.md](../playbooks/loom.md) A4 acceptance and Slice 5 daily gate; morning `loom daily` then `daily approve -Confirm`.

## Anti-patterns

- Equating inspect-clean or `completed` with merge/push authority
- Partial batch apply when one directive fails
- Promoting Patterns or plans from `completed` without acceptance (Slice 8)
- Silently creating/amending commits to satisfy verification

## Evidence

- Contract: `modules/Loom/Contracts/v1/acceptance-record.schema.json`, `pack-diff-manifest.schema.json`
- Code: `Invoke-MetraLoomDailyApprove` in `Daily.ps1`; `Invoke-MetraLoomAcceptWithLocalCommitVerify` in `Lane.ps1`
- Tests: `tests/Loom/Loom.Daily.Tests.ps1`, `Loom.A4.Lane.Tests.ps1`
- Playbook: `docs/playbooks/loom.md` (A4, Slice 5)
- Decision scar: Completion is evidence; acceptance is authority (2026-08-31); Slice 5 daily gate (2026-09-01)
- Shipped slice: Loom Slices 4-5 + A4
