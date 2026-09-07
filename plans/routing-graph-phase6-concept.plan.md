---
name: Routing graph Phase 6 - Concept / multi-hop
overview: "Bing-affirmed contract for concept→product and bounded cross-stem. Operator promoted Gate B build 2026-09-07 - implement in parent session after P5 soak. No embedding map; no silent Apply."
status: BingAffirmedBuildPromoted
phase: routing-graph-6
wakeWhen: "Operator promote-for-build (2026-09-07) authorizes Gate B implement; P5 soak still runs first for evidence."
doNotStartUntil: "Parent Gate B execute; bingReviewed true; build promoted."
bingReviewed: true
bingReviewedAt: 2026-09-07
buildPromotedAt: 2026-09-07
parent: tt_assess_sprint_bites_a69b2410.plan.md
todos:
  - id: bing-contract
    content: Bing-affirm this filled contract (set bingReviewed true) - Gate A
    status: completed
  - id: wake-evidence
    content: Operator promote-for-build recorded; run P5 soak before P6 code for evidence (not a hard block)
    status: completed
  - id: implement-concepts
    content: Implement concept lexicon + scorer hooks per contract in Gate B
    status: completed
  - id: implement-multihop
    content: Implement bounded cross-stem edge apply + Why-here + Pester in Gate B
    status: completed
  - id: prepare-bing-code
    content: inspect prepare-bing -Name Metra after code ship
    status: pending
---

# Routing graph Phase 6 - Concept / multi-hop

**Status: Bing-affirmed + build promoted (2026-09-07).** Master: [routing-graph-evolution.plan.md](routing-graph-evolution.plan.md).

**Bing (2026-09-07):** Approved — deterministic evolution not embedding routing; concept assist not sole authority; depth≤2 + cycle detection. Folded: multi-hop MinCount in Acceptance.

**Operator promote (2026-09-07):** Authorize **Gate B implement** of this contract as part of the parent full-set session. Intent: ship P6 now so the portfolio does not park concept/multi-hop for a later return. P5 soak ([`metra_routing_graph_p5_soak.plan.md`](C:\Users\admin.sswan\.cursor\plans\metra_routing_graph_p5_soak.plan.md)) still runs **before** P6 code for evidence; soak zero-candidate does **not** cancel P6 build.

Depends on: Phase 5 Review shipped; contract Bing-affirmed; parent Gate B execute. Seed scar: Decision Registry `d9b91b622c7`.

## Implement authorization (promoted)

| Was (wake triad) | Now (this package) |
| ---------------- | ------------------ |
| Wait for concept-gap telemetry + promote | Operator **promote-for-build** satisfies implement authorization |
| Defer P6 if soak incomplete | Soak still required as WP6 evidence; **P6 code proceeds** after soak attempt |
| Idea nag / Phase 7 curiosity | Still hard-off |

Phase 7 remains unauthored. No embedding-primary router. No silent Apply.

## Outcome (when implemented)

Deterministic scorer can:

1. Map **concept tokens** (e.g. “payroll run”, “print queue”) to registry stems / projects without replacing haystack.
2. Apply **bounded multi-hop** accepted edges (stem A cue → intermediate → target) with explainable Why-here (concept id + edge id).
3. Still: Observe → propose → operator affirm → `graph.json`; never silent Apply; never embedding-as-map.

## Problem this bite solves

Ops|Sql families fix product+ops/sql intent. Some Ask scars are **concept-shaped** (capability language) or need a **one-hop bridge** across stems that P5’s single stem+cueClass edge cannot express. Phase 6 adds those without inventing an LLM router.

## Architecture

```text
Registry + graph.json (P4) + proposals (P5)
        │
        ▼
Get-MetraRoutingGraph
  + Concepts family (lexicon → stem/project hints)
        │
        ▼
Get-MetraScoredRoutingProjects
  1. haystack
  2. compound Ops|Sql (P2)
  3. accepted edges (P4) including optional multi-hop expand (depth ≤ 2)
  4. concept cue boost (bounded +N; never sole winner without haystack/edge support)
        │
        ▼
Why-here: concept:<id> · edge:<id> · compound:<ops|sql>
        │
        ▼
Telemetry (P3) → Review propose (P5) may suggest concept or multi-hop edges
  operator affirm only
```

### Locked contract

#### 1. Concept lexicon (deterministic)

- Machine-local or repo-owned lexicon file under Metra routing config (not OCC). Shape: `{ version, concepts: [ { id, tokens[], stem?, preferProject?, notes } ] }`.
- Match is token overlap on Ask/query; emit favored token `concept:<id>`.
- Boost magnitude capped (propose **+3** default, ≤ compound +4); cannot invent a project absent from registry.
- Missing lexicon file = soft-fail empty concepts (scorer unchanged).

#### 2. Bounded multi-hop

- Accepted edge schema gains optional `via` / hop list **or** chain resolution at score time: depth **≤ 2** (one intermediate).
- Cycle detection required; reject affirm that would cycle.
- Why-here lists each edge id in the path.
- P5 propose may suggest multi-hop only when telemetry shows repeated wrong primary across related stems (MinCount ≥ 2); still operator affirm.

#### 3. Propose is not Apply (extends P5)

- Concept/multi-hop proposals write `proposals.json` only until affirm.
- Affirm uses same durable mutator path as P4/P5 (`Add-MetraRoutingAcceptedEdge` or documented successor that preserves replace semantics).
- No auto-accept; rejection sticky by fingerprint (extend fingerprint to include concept id or hop target).

#### 4. Fail-soft / fail-loud

- Lexicon/graph read: fail-soft.
- Affirm/reject/save: fail-loud atomic write.

#### 5. Pester matrix (implement)

| Case | Expect |
| ---- | ------ |
| Concept token + matching stem | Prefer correct project; Why-here includes concept id |
| Concept alone, no registry support | No invented project; haystack wins or ask-once |
| Multi-hop depth 2 | Target via intermediate; Why-here lists edges |
| Cycle edge affirm | Rejected / throw; graph unchanged |
| Missing lexicon | Soft-fail; P2–P5 behavior intact |

## Acceptance (Bing on contract; code later)

| Check | Rule |
| ----- | ---- |
| Explainable | Every concept/multi-hop route has Why-here ids |
| Concept assist | Concept boost never sole winner without haystack/edge support |
| Multi-hop propose | Documented telemetry meeting configured MinCount (≥2 default) for repeated wrong primary across related stems |
| Multi-hop depth | Depth ≤ 2; cycle detection; path in Why-here |
| No embedding map | Similarity Phase 7 still unauthored |
| Wake / promote | Code ship authorized by operator promote-for-build (2026-09-07); still after parent Gate B execute |
| Bing | This file `bingReviewed: true` before any P6 code |

## Hard offs

- LLM / embedding-primary router
- Silent Observe→Apply
- Unbounded graph walk
- Moving TicketTracker solutions keywords into `projects.json`
- Phase 7 before P6 proves need in production soak (P6 code is promoted; Phase 7 is not)
- Skipping P5 soak entirely in Gate B (still run soak first for evidence)

## Gate A vs Gate B

| Gate | Action |
| ---- | ------ |
| A | Bing-affirm **this contract** — **done** |
| B | P5 soak then **implement** P6 + `inspect prepare-bing -Name Metra` (build promoted; do not defer) |

## Non-goals

Retiring haystack; Decision Registry as match engine; auto-Apply; vector search as the map.
