---
metraMemory: procedural-architectural
patternSchemaVersion: 1
defaultContext: false
patternId: loom-queue-ingestion
owner: loom
cabinet: null
status: active
implemented: true
loadWhen:
  - loom triage
  - loom enqueue
  - formal-plan
  - Approved plan
ceiling:
  - Formal plans must be Approved before enqueue or Yarn ingest
  - Triage is dry-run by default; enqueue is explicit
  - Ineligible classifications fail closed (not merely lower priority)
relatedDecisions:
  - "2026-08-31 Completion is evidence; acceptance is authority"
  - "2026-08-31 Loom is the governed-execution product name"
relatedPlaybooks:
  - docs/playbooks/loom.md
supersedes: null
---

# Loom Queue Ingestion Pattern

## Intent

Governs how Approved formal plans and triage candidates become Loom queue items (`AP-*`).

## Actors

| Actor | Role |
|-------|------|
| Operator / Bing | Approve formal plan; explicit `enqueue` or Yarn handoff affirm |
| Loom hub | Eligibility, scoring, queue write, journal append |
| Yarn | May ingest Approved plans into Loom handoff (A3); never sets Approved |
| Model (triage) | Classification + rationale only; does not own queue state |

## Inputs / outputs

**In:** Formal plan path (Approved), or Capture/operator candidate with contract fields.

**Out:** Queue item under `%LOCALAPPDATA%\Metra\loom\queue\` plus one journal line; or ineligible reasons with no enqueue.

## Rules and ceilings

1. `source.type = formal-plan` requires plan status matching Approved (not Pending Bing).
2. Eligibility (`Test-MetraLoomEligibility`): reversibility `code`; not cross-root; not production-touch; not external side effect; routing confidence at or above minimum; non-empty `doneWhen` and `verifyCommands`.
3. Unsafe work is **ineligible**, not merely deprioritized.
4. Triage default is dry-run; mutation requires explicit enqueue (or Yarn ingest of an Approved plan).
5. Queue write updates the item file and appends journal; never rewrite prior journal lines.

## State or contract references

- `queue-item.schema.json`, `triage-candidate.schema.json`, `plan-record.schema.json`
- `Test-MetraLoomEligibility`, `Invoke-MetraLoomIngestApprovedPlan`, enqueue paths in `Domain.ps1`

## Flow

```text
Approved formal plan
  -> loom triage / plans show (read-only)
  -> explicit enqueue -FromPlan (or Yarn ingest)
  -> eligibility gate
  -> queued AP-* + journal append
```

## Human ritual

See [loom.md](../playbooks/loom.md): `loom triage`, `loom plans list`, `loom enqueue -FromPlan`.

## Anti-patterns

- Auto-enqueue from Pending Bing or Draft plans
- Treating triage score as a substitute for eligibility
- Letting the model write queue JSON or journal entries directly

## Evidence

- Contract: `modules/Loom/Contracts/v1/queue-item.schema.json`, `triage-candidate.schema.json`
- Code: `Test-MetraLoomEligibility`, `Add-MetraLoomQueueItem`, `Invoke-MetraLoomIngestApprovedPlan` in `modules/Loom/Private/Domain.ps1`
- Tests: `tests/Loom/Loom.Contracts.Tests.ps1`, triage/enqueue coverage in Loom suite
- Playbook: `docs/playbooks/loom.md`
- Decision scar: Completion vs acceptance (2026-08-31); Loom product name (2026-08-31)
- Shipped slice: Loom Slices 1-2 (+ Yarn Approved ingest when present)
