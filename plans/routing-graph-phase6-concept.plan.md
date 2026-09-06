---
name: Routing graph Phase 6 - Concept / multi-hop
overview: "WAKE when Review/telemetry shows concept gaps beyond Ops|Sql (not curiosity). Then fill this stub to P2-P5 contract depth, Bing, and implement. Do not start from Idea nag. Board: Backlog."
status: Deferred
phase: routing-graph-6
wakeWhen: "Concept gaps appear in ambiguous routing telemetry / Review after P5 is in real use - not Ops|Sql family coverage alone."
doNotStartUntil: "Wake criteria above; operator promotes this plan out of Deferred."
bingReviewed: false
todos:
  - id: wake-evidence
    content: Confirm wake from telemetry/Review concept gaps (operator)
    status: pending
  - id: fill-contract
    content: Fill this plan to Phase 2-5 contract depth (architecture, schema, acceptance)
    status: pending
  - id: bing-affirm
    content: Bing-review filled contract; set bingReviewed true
    status: pending
  - id: implement
    content: Implement concept/multi-hop per filled contract (separate ship bite)
    status: pending
---

# Routing graph Phase 6 - Concept / multi-hop

**Status: Deferred (Backlog wake stub).** Not an implement bite yet. Master index (Parked when affirmed): [routing-graph-evolution.plan.md](routing-graph-evolution.plan.md).

## Wake criteria (required)

Author and implement **only when**:

1. Phase 5 Review is in real use (propose/affirm happening for real scars), and
2. Telemetry / operator scars show **concept gaps** that Ops|Sql compound + accepted edges cannot express (concept→product, bounded cross-stem), and
3. Operator explicitly promotes this plan out of Deferred.

**Do not start** because the roadmap looks incomplete, Notion Idea feels idle, or Phase 7 curiosity fires early.

## Outcome (when filled later)

Concept→product and bounded cross-stem paths on the deterministic scorer - still explainable, still no embedding-as-map, still no silent Observe→Apply.

## Hard offs until filled + Bing

- Implementing concept scoring from this stub as-is
- Loom ingest / `yarn plan approve` while `status: Deferred`
- Phase 7 similarity work before P6 proves need

## Next after wake

1. Fill this file to the same contract depth as Phases 2–5.
2. `inspect pack-only plan` + Bing; set `bingReviewed: true`.
3. Implement as a normal Metra ship bite (inspect prepare-bing).
4. Only then consider Phase 7 (optional similarity tie-break).

## Out of scope here

Full schema, lexicons, Pester matrix - belong in the filled contract after wake, not in this stub.
