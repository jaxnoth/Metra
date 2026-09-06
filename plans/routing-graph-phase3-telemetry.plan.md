---
name: Routing graph Phase 3 - Telemetry
overview: "Shipped contract - Observe-only routing events.jsonl witness (confident/ambiguous/home); no learning, no scorer changes, fail-open hot path."
status: Shipped
shippedAt: 2026-08-29
bingReviewed: true
phase: routing-graph-3
todos:
  - id: path-helpers
    content: Get-MetraRoutingTelemetryRoot / EventsPath (never create)
    status: completed
  - id: outcome
    content: Get-MetraRoutingTelemetryOutcome (confident|ambiguous|home)
    status: completed
  - id: append-read
    content: Add-MetraRoutingTelemetryEvent + Get-MetraRoutingTelemetryEvents + routing events CLI
    status: completed
  - id: wire-ambiguity
    content: Emit at end of Get-MetraRoutingAmbiguity (-SkipTelemetry)
    status: completed
  - id: pester-decision
    content: Pester Metra routing telemetry + Decisions.md Observe telemetry scar
    status: completed
---

# Routing graph Phase 3 - Telemetry

**Status: shipped** (code + Pester live; this file is the filled contract / residual ledger). Yarn/plan-board: YAML `status: Shipped` + all todos `completed`. Bing affirmed 2026-09-05 (`bingReviewed: true`).

**Bite only.** Observe routes / confident picks / ambiguity. No learning, durable graph file, Review suggest, or embeddings.

Depends on: Phase 2 Foundation shipped. Master: [routing-graph-evolution.plan.md](routing-graph-evolution.plan.md).

Scar: [Decisions.md](../docs/Decisions.md) 2026-08-29 Routing Observe telemetry is machine-local JSONL (no learning).

## Bing-affirmed commitments (2026-09-05)

1. **Witness, not teacher** - Routing influences telemetry; telemetry never influences routing. `Add-MetraRoutingTelemetryEvent` receives the completed ambiguity result and performs no scoring, token matching, thresholding, or route reconstruction. One definition of how routing works: the router decides; telemetry records.
2. **Fail-open product path** - Broken or unwritable telemetry must not break routing. Routing is the product; telemetry is supporting evidence.
3. **What did happen** - Outcomes (`confident` / `ambiguous` / `home`) are derived only from the completed result. Phase 3 never asks what should have happened. Rectangular JSON (nulls and empty arrays, not `0` or omitted fields) keeps later consumers boring and safe. Phase 5 proposals must read as "observations suggest…" not "we think this edge is useful."

Later-phase test: is this change altering routing behavior, or only observing it? Phase 3 answers: observe only.

## Outcome

Every live `routing` / `ctx` resolution can append one observation line under `%LOCALAPPDATA%\Metra\routing\events.jsonl` so later phases can count misroutes vs routine confidence **without changing the scorer**.

Central rule: `Add-MetraRoutingTelemetryEvent` receives the **completed** ambiguity result and performs **no** scoring, token matching, thresholding, or route reconstruction. Phase 3 is a **witness**.

## Problem this bite solves

Phase 2 proved compound cues. Phase 4/5 need evidence of confident vs ambiguous vs home outcomes before proposing durable edges. Telemetry is Observe-only so Review never confuses "we saw a route" with "we learned an edge."

## Architecture (Phase 3 slice)

```text
Get-MetraRoutingAmbiguity (or ctx path)
        │
        ├─ build RoutingResult (Primary, RunnerUp, IsAmbiguous, FavoredTokens, …)
        │
        ├─ Add-MetraRoutingTelemetryEvent   ← Phase 3 witness (unless -SkipTelemetry)
        │         │
        │         ▼
        │   %LOCALAPPDATA%\Metra\routing\events.jsonl
        │
        └─ return RoutingResult (unchanged)

Read path:  .\metra.ps1 routing events [-Last N]
            Get-MetraRoutingTelemetryEvents  (never creates sink)
```

## Architectural commitments

1. **Witness, not teacher** - Telemetry maps fields from the completed result only. It must not re-score or invent outcomes from the query text alone.
2. **Fail-open hot path** - Unwritable sink / append errors are swallowed; routing still returns.
3. **Privacy-first sink** - Machine-local JSONL; query capped; no silent export/aggregation.

## Locked contract

### 1. Path helpers (never create)

| Helper | Path |
|--------|------|
| `Get-MetraRoutingTelemetryRoot` | `%LOCALAPPDATA%\Metra\routing` |
| `Get-MetraRoutingTelemetryEventsPath` | `…\events.jsonl` |

Path getters never create directory or file. Only `Add-MetraRoutingTelemetryEvent` may create the routing directory when appending.

### 2. Outcome classification - `Get-MetraRoutingTelemetryOutcome`

Witness-only on the completed result:

| Condition | `outcome` |
|-----------|-----------|
| `IsAmbiguous = true` | `ambiguous` |
| Primary is home destination **and** primary score &lt; 2 | `home` |
| Else | `confident` |

Do **not** derive `outcome` solely from `IsAmbiguous`. Do not re-run the scorer.

### 3. Append - `Add-MetraRoutingTelemetryEvent`

| Rule | Detail |
|------|--------|
| Source | Soft-normalize to `routing` \| `ctx` \| `other` (unknown → `other`) |
| Query | Newlines → space; trim; max **512** chars; empty → `""` |
| Format | One compressed JSON line; UTF-8 append |
| Errors | Silent catch - never throw into routing hot path |
| Noise | No warning/verbose on the hot path by default |

### 4. Event schema

| Field | Notes |
|-------|-------|
| `tsUtc` | ISO UTC |
| `source` | `routing` / `ctx` / `other` |
| `query` | Single-line, max 512 |
| `outcome` | `confident` \| `ambiguous` \| `home` |
| `primary` | Project name or null |
| `primaryScore` | int |
| `runnerUp` | name or JSON **null** (never coerce absent to `0`) |
| `runnerUpScore` | int or JSON **null** |
| `isAmbiguous` | bool |
| `matchedTokens` | string[] from primary (else `[]`) |
| `favoredTokens` | when ambiguous; otherwise `[]` (rectangular) |

### 5. Wire-in

At end of `Get-MetraRoutingAmbiguity`: build result → emit telemetry → return.

- `-SkipTelemetry` skips append (tests / dry paths).
- `-Source` soft-normalized inside the helper.

### 6. Read CLI

`.\metra.ps1 routing events [-Last N]` - read-only tail (default 20). Never creates the sink. Malformed lines skipped or ignored safely.

`Get-MetraRoutingTelemetryEvents -Last N` - same rules for Pester / later candidates.

### 7. Privacy

- Query capped at 512 with newline normalization.
- No credentials or proposal payloads intentionally added.
- `%LOCALAPPDATA%` data stays untracked.
- Future export / aggregation needs a **separate** explicit design decision.

## Deliverables (shipped)

| Item | Location |
|------|----------|
| Path helpers | `Get-MetraRoutingTelemetryRoot`, `Get-MetraRoutingTelemetryEventsPath` |
| Outcome | `Get-MetraRoutingTelemetryOutcome` |
| Append | `Add-MetraRoutingTelemetryEvent` |
| Read | `Get-MetraRoutingTelemetryEvents`, `Show-MetraRoutingEventsCli` |
| Wire | End of `Get-MetraRoutingAmbiguity` |
| Decision | `docs/Decisions.md` 2026-08-29 Routing Observe telemetry |
| Pester | `tests/Metra.Tests.ps1` - `Describe 'Metra routing telemetry'` (+ compound event cases) |

## Done when (acceptance matrix)

| Check | Expect |
|-------|--------|
| Compound ops query | Automation + JSONL `outcome=confident` (or ambiguous if scores close) with `compound:ops` in matched/favored as applicable |
| Ask-once / close score | `outcome=ambiguous` + runner-up + favoredTokens |
| Weak query → home | `outcome=home`; runner-up null |
| Empty / multiline query | No throw; one valid single-line JSON event |
| Unwritable sink | Routing still returns |
| `routing events` missing file | Read-only, usable (empty / no create) |
| Path getters alone | Do not create root or file |
| Pester matrix | Pass under overridden `$env:LOCALAPPDATA` |
| Scorer | Unchanged vs Phase 2 fixtures |

## Verification commands

```powershell
.\metra.ps1 routing -Query "How did IWUDATA run today?"
.\metra.ps1 routing events -Last 5
Invoke-Pester -Path .\tests\Metra.Tests.ps1 -FullName '*telemetry*','*RoutingTelemetry*'
```

## Out of scope (later phases)

| Deferred | Owner |
|----------|--------|
| Durable `graph.json` / accepted edges | Phase 4 |
| Propose / affirm / reject from telemetry | Phase 5 |
| Concept / multi-hop | Phase 6 |
| Silent Observe→Apply | Hard off |
| Cue-weight / lexicon changes | Separate Decision |
| P4 fields on events "for later" | Hard off (no forward-leak) |
| Export / aggregation of events | Separate design Decision |

## Residual / follow-ups (not blockers for "Phase 3 shipped")

- Events accumulate without rotation - size hygiene is operator/local, not Phase 3 scope.
- `routing events candidates` / propose consume this sink in P4/P5; empty telemetry ⇒ no proposals (correct).
- Ask phone path should use the same ambiguity+telemetry wire when it goes through `Get-MetraRoutingAmbiguity` (verify Ask does not bypass).

## Operator notes

Phase 3 does not make routing smarter. It makes later Review possible. Destination still requires Phase 4/5 **and** operator-affirmed edges on top of this witness.
