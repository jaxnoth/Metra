---
name: Ask routing graph evolution (master roadmap)
overview: "P2-P5 program complete (contracts + seeded IWUDATA ops edge). Architecture index only - not a Loom bite. Future work: Backlog wake stub routing-graph-phase6-concept.plan.md."
status: Shipped
shippedAt: 2026-09-06
bingReviewed: true
phase: routing-graph-program
todos:
  - id: p2-p5-contracts
    content: Fill and Bing-affirm Phases 2-5 shipped contracts
    status: completed
  - id: seed-iwudata-edge
    content: Operator-accept IWUDATA ops to Automation (d9b91b622c7)
    status: completed
  - id: p6-wake-stub
    content: Deferred P6 stub on Backlog (wake when concept gaps)
    status: completed
---

# Ask routing graph evolution (master roadmap)

**Status: P2–P5 program complete** (2026-09-06). This file is the architecture index for the finished Think→Observe→Remember→Review loop. **Not a Loom implementer plan.**

Future gated work lives on the Backlog wake stub: [routing-graph-phase6-concept.plan.md](routing-graph-phase6-concept.plan.md) (Phase 7 stays unauthored until P6 proves need).

Scar: [Decisions.md](../docs/Decisions.md) 2026-08-29 compound intent; Decision Registry `d9b91b622c7`.

## Destination (what "done" means)

Not "registry instead of keywords." Desired end state for **this program (P2–P5)**:

```text
Registry (purpose / triggers / related)
  → Graph builder (Ops|Sql families; later concepts)
  → Deterministic scorer (haystack + compound + accepted edges)
  → Ambiguity / ask-once
  → Why-here (stem · cue · edge id · Decision Registry)
  → Observe telemetry → Review proposes → operator affirm → graph.json
```

**P2–P5 arrived when:**

- Phases **2–5** are filled contracts **and** shipped behavior matches those contracts.
- `%LOCALAPPDATA%\Metra\routing\graph.json` holds **operator-accepted** edges for known compound scars (at least IWUDATA ops → Automation), not an empty file with unused CLI.
- Haystack keywords remain the base map; compound + edges correct product+intent without LLM/embedding as the router.
- Decision Registry explains why; TicketTracker `solutions/` keywords stay the product-name lane for tickets (not `projects.json` trigger dumping).

**Empty `graph.json` with P2–P5 code present is not destination** - machinery without affirmed edges still feels keyword-primary. (Seeded 2026-09-06: IWUDATA+ops → IWUDATA-Automation.)

Concept / multi-hop / similarity are **out of this program’s ship bar** - see Phase 6 wake stub.

## Invariants (all phases)

- Deterministic scorer remains the execution engine; learning **proposes** edges (Observe → Recommend → Approve → Apply).
- Explainable Why-here (stem / role / cue / edge id) - not opaque similarity.
- No LLM router, no embedding-primary map, no parallel "smart" router beside `Get-MetraScoredRoutingProjects`.
- Auth / identity work is a **separate** risk domain - ship and scar that before expanding routing phases when both are in flight.

## Pipeline

```text
Registry (+ optional graph file later)
  → Graph Builder → Get-MetraRoutingGraph
  → Scorer (haystack + graph edge apply)
  → Ambiguity / ask-once
  → Why-here
  → telemetry → Review suggest → durable edges
```

## How phases compose

| Layer | Job |
|-------|-----|
| **2 Foundation** | In-memory Ops\|Sql families + compound cue boost (+4); IWUDATA run → Automation |
| **3 Telemetry** | Observe-only `events.jsonl`; no learning |
| **4 Persistence** | Durable accepted edges in `graph.json`; apply on score path |
| **5 Review** | Propose from ambiguous+compound misroutes; affirm/reject; never silent Apply |
| **6 Concept / multi-hop** | [Wake stub](routing-graph-phase6-concept.plan.md) - fill only after concept gaps in telemetry |
| **7 Similarity** | Optional tie-break only; never the map; do not author until P6 proves need |

Operator work is part of arrival: `routing edges accept` / `propose` + `affirm` for real scars. Code-complete without affirmations does not fill the graph.

## Phases

| Phase | Plan file | Plan status | Done means |
|-------|-----------|-------------|------------|
| **2 Foundation** | [routing-graph-phase2-foundation.plan.md](routing-graph-phase2-foundation.plan.md) | **Shipped** (Bing affirmed) | Stem+Ops/Sql+compound cue; IWUDATA run routes correctly |
| **3 Telemetry** | [routing-graph-phase3-telemetry.plan.md](routing-graph-phase3-telemetry.plan.md) | **Shipped** (Bing affirmed) | Observe routes/confirms/ambiguity; **no learning** |
| **4 Persistence** | [routing-graph-phase4-persistence.plan.md](routing-graph-phase4-persistence.plan.md) | **Shipped** (Bing affirmed) | Durable graph + operator-accepted edges; misroutes ≫ routine confirms |
| **5 Review** | [routing-graph-phase5-review.plan.md](routing-graph-phase5-review.plan.md) | **Shipped** (Bing affirmed) | Metra proposes from telemetry; operator affirms/rejects; no silent Observe→Apply |
| **6 Concept / multi-hop** | [routing-graph-phase6-concept.plan.md](routing-graph-phase6-concept.plan.md) | **Deferred** (Backlog wake stub) | Concept→product and bounded cross-stem paths |
| **7 Similarity tie-break** | unauthored until P6 proves need | Unauthored | Tie-breaker only |

## Non-goals (this roadmap)

- Retiring registry `triggers` / purpose haystack as the base scorer
- Making Decision Registry the match engine (it stays Why-here / scar memory)
- Moving TicketTracker solutions product keywords into `projects.json` triggers
- Trigger false-positive hygiene as a phase deliverable (e.g. `checkin`⊂`checking`) - fix in scorer/registry when found; not a graph phase
- Silent auto-Apply of learned edges; vector search as the route map

## Hard offs until criteria

- Future architecture leaking into the current phase (telemetry fields "for P4", etc.)
- Silent Observe→Apply for learned edges
- Vector search as the route map
- Starting Phase 6 from roadmap incompleteness or Idea curiosity (use the wake stub)

## Next

1. Soak P5: live Ask/routing → `propose` / `affirm` when ambiguous misroutes appear.
2. Yarn plan-board: **Park** this master + Phases 2–5; keep Phase 6 stub on **Backlog**.
3. Author Phase 6 contract only when [wake criteria](routing-graph-phase6-concept.plan.md) fire.
