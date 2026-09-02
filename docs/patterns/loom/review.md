---
metraMemory: procedural-architectural
patternSchemaVersion: 1
defaultContext: false
patternId: loom-review
owner: loom
cabinet: null
status: active
implemented: true
loadWhen:
  - loom review
  - inspecting
  - verify
  - completed
ceiling:
  - Only Invoke-MetraLoomReview exits reviewing to completed, implementing, or blocked
  - Inspect goal and authoritative verify both required for completed
  - completed is not accepted
relatedDecisions:
  - "2026-09-01 Loom Slice 4 review and completion"
  - "2026-08-31 Completion is evidence; acceptance is authority"
relatedPlaybooks:
  - docs/playbooks/loom.md
  - docs/playbooks/inspect-loop.md
supersedes: null
---

# Loom Review Pattern

## Intent

Governs machine review after implementation: inspect + verify + scope, then `completed` (evidence), never operator acceptance.

## Actors

| Actor | Role |
|-------|------|
| `Invoke-MetraLoomReview` | Sole transition owner out of `reviewing` |
| Inspect adapter | Contract-shaped findings; no queue authority |
| Verify adapter | Authoritative `verifyCommands` |
| Implementer | Bounded retry when verdict is retry / regression revert |
| Operator | Acceptance only via daily gate (separate Pattern) |

## Inputs / outputs

**In:** Item in `reviewing` with run directory evidence.

**Out:** `completed` (optional branch commit first), `implementing` (retry), or `blocked`; `review.json` / inspect / verify artifacts under the run dir.

## Rules and ceilings

1. Live `run` / `review` require `-Confirm`.
2. Exits from `reviewing`: `completed`, `implementing`, or `blocked` only.
3. Completion requires inspect goal, passed verify, done-when satisfaction, and in-scope paths (hub policy; adapters return evidence only).
4. When `completionCommitPolicy` is `required`, commit on the item branch before `completed` (no push).
5. Inspect packs use per-project slots so parallel items do not overwrite Bing packs.
6. Recovery: `loom review -Confirm` resumes idempotently from `review.json`.

## State or contract references

- `review-result.schema.json`, `inspect-result.schema.json`, `verify-result.schema.json`
- `modules/Loom/Private/Review.ps1`

## Flow

```text
implementing -> reviewing
  -> inspect assess + verify
  -> retry (implementing) | blocked | completed (+ commit)
  -> (acceptance is daily gate, not this Pattern)
```

## Human ritual

[loom.md](../playbooks/loom.md) Slice 4; [inspect-loop.md](../playbooks/inspect-loop.md) for Metra inspect.

## Anti-patterns

- Marking `accepted` from review
- Skipping verify because inspect looks clean
- Agent reading Bing pack bodies as fix input (use fix-queue / latest)

## Evidence

- Contract: `modules/Loom/Contracts/v1/review-result.schema.json`, inspect/verify schemas
- Code: `modules/Loom/Private/Review.ps1`
- Tests: `tests/Loom/Loom.Review.Tests.ps1`, `Loom.InspectAdapter.Tests.ps1`, `Loom.VerifyAdapter.Tests.ps1`
- Playbook: `docs/playbooks/loom.md`, `docs/playbooks/inspect-loop.md`
- Decision scar: Slice 4 review (2026-09-01); Completion vs acceptance (2026-08-31); Inspect context economy (2026-09-01)
- Shipped slice: Loom Slice 4
