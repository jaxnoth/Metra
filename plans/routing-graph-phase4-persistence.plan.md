---
name: Routing graph Phase 4 - Persistence
overview: "Shipped contract - durable operator-accepted edges in graph.json; apply +4 with edge:id after compound cues; candidates Observe-only; no silent Observe→Apply."
status: Shipped
shippedAt: 2026-08-30
bingReviewed: true
phase: routing-graph-4
todos:
  - id: durable-io
    content: Get/Save durable graph.json (fail-soft read, fail-loud atomic write)
    status: completed
  - id: accept-remove
    content: Add/Remove accepted edges; stem+cueClass replace; registry target required
    status: completed
  - id: scorer-apply
    content: Update-MetraScoredRoutingWithAcceptedEdges after compound (+4, edge:id idempotent)
    status: completed
  - id: candidates
    content: Get-MetraRoutingEdgeCandidates from ambiguous telemetry only (never writes graph)
    status: completed
  - id: cli-pester
    content: routing edges list/candidates/accept/remove + Pester persistence + Decisions scar
    status: completed
---

# Routing graph Phase 4 - Persistence

**Status: shipped** (code + Pester live; this file is the filled contract / residual ledger). Yarn/plan-board: YAML `status: Shipped` + all todos `completed`. Bing affirmed 2026-09-06 (`bingReviewed: true`).

**Bite only.** Durable graph + operator-accepted edges. No Review propose/affirm UI (Phase 5), no silent Observe→Apply, no embeddings, no cue-weight redesign.

Depends on: Phase 3 Telemetry shipped. Master: [routing-graph-evolution.plan.md](routing-graph-evolution.plan.md).

Scar: [Decisions.md](../docs/Decisions.md) 2026-08-30 Durable routing edges are operator-applied only.

## Bing-affirmed commitments (2026-09-06)

1. **Remember, not Learn** - Phase 4 is Think + Observe + Remember. Durable edges are **operator-applied only**. Telemetry and candidates never write `graph.json`. Human decision sits between candidate and accepted edge - observe → candidate → human → memory. Learning (propose/affirm/reject) stays Phase 5.
2. **Narrow memory, additive evidence** - An edge is `stem + cueClass → target` (same compound-intent vocabulary as P2), not query→target or a parallel router. Accepted edges use the same **+4** magnitude as compound cues (strong evidence, not opaque override). Keep both `edge:*` and `compound:*` on the scored row so the reasoning chain stays visible.
3. **Misroutes feed memory; confident does not** - Candidates come from **ambiguous + compound** events only. Call order stays haystack → compound → accepted edges → sort so operator scars extend Phase 2 rather than fight it. Empty `graph.json` with working CLI is machinery without scars - destination still needs operator accepts.

Later-phase test: is this changing routing via operator-approved memory, or sneaking Observe→Apply? Phase 4 answers: memory only after human Apply.

## Outcome

Operator-accepted routing edges persist under `%LOCALAPPDATA%\Metra\routing\graph.json`, reload into the scorer with explainable `edge:<id>` evidence, and survive restarts - without turning P3 Observe into Apply.

Roadmap principle: **misroutes ≫ routine confirms** - accept corrections; do not persist every confident event.

Empty `graph.json` (or missing file) with working accept CLI is **machinery without memory** - destination still needs operator-accepted edges (at least IWUDATA ops → Automation).

The real outcome is not the file itself: **a single operator correction survives process restarts and becomes reusable routing evidence.**

## Problem this bite solves

Phase 2/3 can route and witness. Without durable accepted edges, every restart forgets operator corrections and Review has nowhere to Apply. Phase 4 is the **memory file + apply path** only - still no automatic learning.

## Architecture (Phase 4 slice)

```text
events.jsonl ──read──> Get-MetraRoutingEdgeCandidates   (Observe-only)
                              │
                              │ operator reviews (CLI / later Phase 5)
                              ▼
routing edges accept|remove ──write──> graph.json
                              │
                              ▼
Get-MetraRoutingDurableGraph (fail-soft)
                              │
                              ▼
Get-MetraScoredRoutingProjects
   1. haystack
   2. Update-MetraScoredRoutingWithCompoundCues     ← Phase 2
   3. Update-MetraScoredRoutingWithAcceptedEdges    ← Phase 4
   4. sort
```

**Structural rule:** Only the `routing edges accept` and `routing edges remove` command handlers (and Phase 5 `affirm`, which calls the same mutator) may call durable graph mutation helpers (`Save-MetraRoutingDurableGraph`, `Add-MetraRoutingAcceptedEdge`, `Remove-MetraRoutingAcceptedEdge`). Candidate generation and telemetry readers must have **no** code path into those mutators.

## Architectural commitments

1. **Memory, not teacher** - Persistence stores what the operator applied. Telemetry and candidates never write `graph.json`.
2. **Fail-soft reads; fail-loud writes** - Broken graph must not crash routing (empty edges). Failed accept/remove must surface to the CLI.
3. **misroutes ≫ routine confirms** - Do not auto-accept confident events. Manual accept (and later affirm) only.

## Locked contract

### 1. Path helper (never creates)

| Helper | Path |
|--------|------|
| `Get-MetraRoutingDurableGraphPath` | `%LOCALAPPDATA%\Metra\routing\graph.json` |

Path helper never creates directory or file. `Save-MetraRoutingDurableGraph` may create the routing directory when writing.

### 2. Schema v1

Root: `{ "version": 1, "edges": [ ... ] }`

| Field | Rule |
|-------|------|
| `id` | non-empty; derived `e_{STEM}_{cue}_{targetSlug}` |
| `stem` | normalized **uppercase** |
| `cueClass` | `ops` \| `sql` (lowercase) |
| `target` | canonical registry project **name** |
| `acceptedAtUtc` | parseable UTC |
| `source` | must be `operator` |
| `note` | string present (may be empty `""`) |

`Test-MetraRoutingAcceptedEdgeRecord` enforces the minimum. Invalid edges are filtered on read; rejected on write.

### 3. Duplicate stem + cueClass = replace

A new acceptance for an existing **normalized** stem + cueClass **replaces** the prior edge (does not reject).

- Normalize stem → uppercase; cueClass → lowercase (`ops` \| `sql`).
- Derive ID from normalized stem, cueClass, **and full normalized target** (`Get-MetraRoutingAcceptedEdgeId`) - opaque to callers.
- Target must resolve via `Get-MetraRegistryProject` (unknown target throws).
- Remove any existing edge with the same normalized stem + cueClass.
- Add the replacement; save **once**; return the resulting edge (may include transient `replaced` for CLI).

### 4. Fail-soft reads; fail-loud writes

`Get-MetraRoutingDurableGraph` returns `@{ version = 1; edges = @() }` for missing/empty/invalid JSON/unsupported version/missing edges/non-array edges.

Partially valid files: accept valid v1 root; **filter** invalid edge records; return remaining valid edges; **never rewrite** the graph merely because invalid entries were skipped.

`Save-MetraRoutingDurableGraph` / accept / remove: validate then atomic write (temp sibling `graph.json.tmp` + `Move-Item -Force`). **Throw / non-success to CLI** on write failure.

`Remove-MetraRoutingAcceptedEdge`: exact id match; missing id → `{ removed = false }` with **no** rewrite.

### 5. Scorer apply - `Update-MetraScoredRoutingWithAcceptedEdges`

Runs **after** compound cues. For each durable edge:

| Gate | Rule |
|------|------|
| Stem in query | `Test-MetraRoutingQueryHasTerm` on edge stem |
| Cue class | Ops edge requires Ops cue hits; Sql edge requires Sql cue hits (same Phase 2 lexicon) |
| Idempotency | Skip if `MatchedTokens` already contains `edge:<id>` |

Then:

- If target row exists: **+4** once; add exactly one `edge:<id>` token; preserve row schema/collection types.
- If missing: insert via `New-MetraCompoundScoredRoutingRow` (score 4, token `edge:<id>`) when registry + on-disk project exist; else skip.

Display / Why-here intent: `Accepted edge: STEM + cue → Target` (machine token remains `edge:<id>`).

### 6. Multiple matching edges

Uniqueness is stem + cueClass only. A query may match multiple stems and/or both ops and sql. **Each distinct accepted edge may apply once** per scoring pass.

### 7. Call order and evidence precedence

```text
Update-MetraScoredRoutingWithCompoundCues
Update-MetraScoredRoutingWithAcceptedEdges
```

Explanation precedence: `edge:*` then `compound:*` then weaker evidence. Leave compound evidence in place alongside edge tokens (do not strip `compound:*` when an edge applies).

### 8. Candidates - Observe-only

`Get-MetraRoutingEdgeCandidates [-Last N]` (default 200):

- Reads telemetry via `Get-MetraRoutingTelemetryEvents -Last N` (physical `-Tail` lines; never creates sink).
- Keeps **`outcome=ambiguous` only**.
- Requires `compound:ops` or `compound:sql` in favoredTokens (else matchedTokens); sql wins if both.
- Stem from primary name, else runner-up.
- Aggregates counts keyed by stem + cueClass + primary + runnerUp.
- **Never** writes `graph.json` or `proposals.json`.

### 9. CLI (Phase 4 surface)

```text
.\metra.ps1 routing edges                 # list accepted (default)
.\metra.ps1 routing edges candidates [-Last 200]
.\metra.ps1 routing edges accept -Stem … -CueClass ops|sql -Target … [-Note '…']
.\metra.ps1 routing edges remove -Id …
```

Phase 5 adds `propose` / `review` / `affirm` / `reject` on the same CLI entry - out of scope for this bite's **done** criteria, but live on the same handler after P5 ships.

## Deliverables (shipped)

| Item | Location |
|------|----------|
| Path | `Get-MetraRoutingDurableGraphPath` |
| Id / validate | `Get-MetraRoutingAcceptedEdgeId`, `Test-MetraRoutingAcceptedEdgeRecord` |
| Load / save | `Get-MetraRoutingDurableGraph`, `Save-MetraRoutingDurableGraph` |
| Mutate | `Add-MetraRoutingAcceptedEdge`, `Remove-MetraRoutingAcceptedEdge` |
| Scorer | `Update-MetraScoredRoutingWithAcceptedEdges` wired in `Get-MetraScoredRoutingProjects` |
| Candidates | `Get-MetraRoutingEdgeCandidates` |
| CLI | `Show-MetraRoutingEdgesCli` (list / candidates / accept / remove) |
| Decision | `docs/Decisions.md` 2026-08-30 Durable routing edges |
| Pester | `tests/Metra.Tests.ps1` - `Describe 'Metra routing persistence'` |

## Done when (acceptance matrix)

| Check | Expect |
|-------|--------|
| Missing / corrupt graph.json | Empty v1; routing still scores |
| Accept known target | File created; edge reloads after restart |
| Accept same stem+cue, new target | Prior edge replaced; one edge remains |
| Accept unknown target | Throws; graph unchanged |
| Remove missing id | `removed=false`; no rewrite |
| Scorer + ops cue + IWUDATA stem | Target +4 once; `edge:<id>` present; second apply unchanged |
| Compound + edge | Both `compound:*` and `edge:*` retained |
| Candidates | Ambiguous+compound only; never creates/writes graph.json |
| Telemetry `-Tail` | Physical last N lines; skip malformed; never create sink |
| Pester `Metra routing persistence` | Pass under overridden `$env:LOCALAPPDATA` |

## Verification commands

```powershell
.\metra.ps1 routing edges accept -Stem IWUDATA -CueClass ops -Target IWUDATA-Automation -Note 'scar'
.\metra.ps1 routing edges
.\metra.ps1 routing -Query "How did IWUDATA run today?"
.\metra.ps1 routing edges candidates -Last 50
.\metra.ps1 routing edges remove -Id e_IWUDATA_ops_iwudata_automation
Invoke-Pester -Path .\tests\Metra.Tests.ps1 -FullName '*routing persistence*'
```

## Out of scope (later / hard off)

| Deferred | Owner |
|----------|--------|
| `propose` / `affirm` / `reject` / `proposals.json` | Phase 5 |
| Silent Observe→Apply | Hard off |
| Concept / multi-hop | Phase 6 |
| Embeddings as map | Hard off (optional P7) |
| Committing `graph.json` to git | Hard off (machine-local) |
| Export / aggregation of events | Separate Decision |
| Cue lexicon or +4 weight changes | Separate Decision |

## Residual / follow-ups (not blockers for "Phase 4 shipped")

- **Empty graph on this machine is expected until accept/affirm** - code-complete ≠ destination.
- Why-here CLI currently surfaces compound cue lines strongly; edge token display may be thinner than the locked precedence intent - improve display without changing apply rules if operators miss `edge:*` evidence.
- Phase 5 affirm must call `Add-MetraRoutingAcceptedEdge` only (same replace semantics) - never a second write path.
- Candidates feed Phase 5; empty telemetry ⇒ empty candidates (correct).

## Operator notes

Phase 4 is **Think + Observe + Memory file**. Learning loop is still Phase 5. Seed the first real scar when ready:

```powershell
.\metra.ps1 routing edges accept -Stem IWUDATA -CueClass ops -Target IWUDATA-Automation -Note 'phone Ask misroute scar'
```
