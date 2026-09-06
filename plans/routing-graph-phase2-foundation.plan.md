---
name: Routing graph Phase 2 - Foundation
overview: "Shipped contract - in-memory Ops|Sql family graph + compound cue boost (+4) so product+ops intent prefers Automation without replacing haystack keywords."
status: Shipped
shippedAt: 2026-08-29
bingReviewed: true
phase: routing-graph-2
todos:
  - id: graph-builder
    content: Get-MetraRoutingGraph stem/Ops/Sql families from registry
    status: completed
  - id: compound-cues
    content: Ops|Sql cue lexicon + Update-MetraScoredRoutingWithCompoundCues (+4)
    status: completed
  - id: why-here
    content: Surface Compound cue why-here / FavoredTokens for compound tags
    status: completed
  - id: pester
    content: Pester compound/RoutingGraph acceptance matrix
    status: completed
  - id: decision-scar
    content: Decisions.md compound intent + Decision Registry d9b91b622c7
    status: completed
---

# Routing graph Phase 2 - Foundation

**Status: shipped** (code + Pester live; this file is the filled contract / residual ledger). Yarn/plan-board: YAML `status: Shipped` + all todos `completed` (propose Park as completed-unmarked).

**Bite only.** No telemetry, persistence, learning, Review UI, concept scoring, or embeddings.

Depends on: Tailscale identity/auth scar shipped (2026-08-29). Master roadmap: [routing-graph-evolution.plan.md](routing-graph-evolution.plan.md).

Scar: [Decisions.md](../docs/Decisions.md) 2026-08-29 compound intent; Decision Registry `d9b91b622c7`.

## Outcome

`How did IWUDATA run today?` → **IWUDATA-Automation** with explainable compound evidence (`compound:ops`), without relying only on local phrase triggers that monopolize bare `iwudata`.

Bare product token alone must **not** invent a compound tag. SQL keeps deploy/source ownership when the query is sql-class.

## Problem this bite solves

Phone Ask (2026-08-29) answered "How did IWUDATA run today?" from **IWUDATA-SQL** and honestly said it had no run status - wrong stop. Haystack keywords alone let SQL own the shared product token. Phase 2 adds a **registry-derived Ops|Sql family graph** plus **compound cue boosts** so product+ops intent prefers Automation.

## Architecture (Phase 2 slice)

```text
projects.json / projects.local.json
        │
        ▼
Get-MetraRoutingGraph          (in-memory families: Stem, Ops, Sql, Concepts*)
        │
        ▼
Get-MetraScoredRoutingProjects
   1. haystack score (name + triggers + purpose)
   2. Update-MetraScoredRoutingWithCompoundCues   ← Phase 2
   3. (later phases) accepted edges
   4. sort (compound:sql before compound:ops on ties)
        │
        ▼
Why-here: "Compound cue: product+ops|product+sql"
```

\*Concepts are harvested onto the family object; **not scored** in Phase 2.

## Locked contract

### 1. Graph builder - `Get-MetraRoutingGraph`

| Rule | Detail |
|------|--------|
| Input | Registry projects (optional `-Registry` for tests) |
| Stem | Name before final `-` segment (`IWUDATA-Automation` → `IWUDATA`); skip names with no usable stem |
| Role | Fail-closed `Ops` or `Sql` from name/purpose/triggers via `Resolve-MetraRoutingGraphRole`; ambiguous → omit from graph |
| Family | Same stem; **mutual** `related`; one Ops + one Sql member; no same-role pairs |
| Output | List of families: `Stem`, `Roles`, `Members.Ops`, `Members.Sql`, `Concepts` (capped), registry-derived `Edges` (weight 4, source `registry`) |
| Persistence | **None** in Phase 2 - rebuild from registry every call |

Ops role evidence (examples): automation, etl, load, job(s), run in name/purpose/triggers.
Sql role evidence: sql, procedure, deploy, script; or name matching `(^|-)sql($|-)`.

### 2. Compound cue lexicon - `Get-MetraCompoundRoutingCueHits`

Class hits from the **raw query** (not stop-word filtered tokens), using boundary-safe `Test-MetraRoutingQueryHasTerm`.

| Class | Lexicon (exact terms) |
|-------|------------------------|
| Ops | `run`, `ran`, `job`, `status`, `failed`, `failure`, `today`, `morning`, `load`, `etl`, `start-automation` |
| Sql | `sql`, `procedure`, `deploy`, `script` |

Multiple words in one class = one class election, not multiple boosts.

### 3. Apply - `Update-MetraScoredRoutingWithCompoundCues`

| Rule | Detail |
|------|--------|
| When | At least one Ops or Sql cue hit **and** a graph family whose stem appears in the query/haystack path used by apply |
| Boost | **+4 once per family** |
| Tag | `compound:ops` or `compound:sql` on `MatchedTokens` |
| Mixed cues | **SQL wins** - tag `compound:sql` only; do not also tag ops |
| Sibling missing | Insert sibling scored row via `New-MetraCompoundScoredRoutingRow` (live schema); do not invent projects |
| Idempotent | Second apply leaves scores/tags unchanged |
| Bare product | No cue hits → no `compound:*` |

### 4. Wire-in order

Inside `Get-MetraScoredRoutingProjects`, after haystack scoring, **before** sort:

1. `Update-MetraScoredRoutingWithCompoundCues`
2. (Phase 4+) `Update-MetraScoredRoutingWithAcceptedEdges`
3. Sort: Score desc; then prefer `compound:sql` over `compound:ops` on equal scores; then Name

### 5. Why-here / FavoredTokens

- Surface human line: `Compound cue: product+ops` or `product+sql` when a compound tag is present.
- FavoredTokens prefer `compound:*` so telemetry and later Review see the cue class.

### 6. Registry hygiene (companion to Phase 2, not graph code)

- No sibling may monopolize a bare shared product token when the other owns ops/sql meaning (scar: remove bare `iwudata` from SQL triggers; Automation may keep phrase triggers like `iwudata run`).
- Phrase trigger bonus must use **word boundaries** (2026-09-05 scar: `checkin` must not match `checking`). That fix lives in haystack phrase matching; Phase 2 compound terms already used boundary-safe term tests.

## Deliverables (shipped)

| Item | Location |
|------|----------|
| Graph builder | `Get-MetraRoutingGraph` - `scripts/private/Routing.ps1` |
| Role / stem helpers | `Resolve-MetraRoutingGraphRole`, `Get-MetraRoutingStemFromName` |
| Cue hits | `Get-MetraCompoundRoutingCueHits` |
| Apply | `Update-MetraScoredRoutingWithCompoundCues`, `New-MetraCompoundScoredRoutingRow` |
| Scorer wire | `Get-MetraScoredRoutingProjects` |
| Why-here compound line | routing ambiguity / Why-here path in `Routing.ps1` |
| Decision | `docs/Decisions.md` 2026-08-29 Compound intent |
| Decision Registry | `d9b91b622c7` |
| Pester | `tests/Metra.Tests.ps1` - `*compound*` / `*RoutingGraph*` |

## Done when (acceptance matrix)

| Query | Expect |
|-------|--------|
| How did IWUDATA run today? | Primary **IWUDATA-Automation**; `MatchedTokens` contains `compound:ops` |
| iwudata sql deploy | Primary **IWUDATA-SQL**; `compound:sql` |
| iwudata | No `compound:*` (no invented certainty) |
| iwudata job deploy | **SQL** wins mixed-cue precedence (`compound:sql`) |
| Synthetic SQL score 4 vs Automation 2 + ops cue | Automation reaches 6 after apply; second invoke unchanged (idempotent) |
| IWUDATA family in graph | Mutual related Ops+Sql members present when registry configured |

## Verification commands

```powershell
.\metra.ps1 routing -Query "How did IWUDATA run today?"
.\metra.ps1 routing -Query "iwudata sql deploy"
.\metra.ps1 routing -Query "iwudata"
Invoke-Pester -Path .\tests\Metra.Tests.ps1 -FullName '*compound*','*RoutingGraph*'
```

## Out of scope (later phases)

| Deferred | Owner phase |
|----------|-------------|
| `events.jsonl` Observe telemetry | 3 |
| Durable `graph.json` / accepted edges | 4 |
| Propose / affirm / reject from telemetry | 5 |
| Concept scoring / multi-hop | 6 |
| Similarity / embeddings as map | Hard off (optional P7 tie-break only) |
| Expanding Ops/Sql lexicons without a Decision | Operator change + Decision if behavioral |

## Residual / follow-ups (not blockers for "Phase 2 shipped")

- Families only form when registry `related` is **mutual** and roles resolve - incomplete related topology = no compound boost for that stem.
- Lexicon is closed; new ops verbs (e.g. `watch`, `cooldown`) need an explicit lexicon Decision before adding.
- Phase 2 does not populate accepted edges - empty `graph.json` is expected until P4/P5 operator work.
- Trigger substring false positives (BuildingCheckin / phone "checking in") are haystack hygiene; keep boundary matching when editing phrase bonuses.

## Operator notes

Phase 2 is the **in-memory foundation** under the desired stack. It does not replace keyword haystack; it corrects compound product+intent when an Ops|Sql family exists. Filling durable edges is Phase 4/5 work on top of this builder.
