# Ask routing graph evolution (master roadmap)

Architecture roadmap only. **Implementation stays one phase plan at a time.** Do not treat this file as a mega-PR checklist.

Scar: [Decisions.md](Decisions.md) 2026-08-29 compound intent; Decision Registry `d9b91b622c7`.

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
  → (later) telemetry → Review suggest → durable edges
```

## Phases

| Phase | Plan file | Done means |
|-------|-----------|------------|
| **2 Foundation** | [routing-graph-phase2-foundation.plan.md](routing-graph-phase2-foundation.plan.md) | Stem+Ops/Sql+compound cue; IWUDATA run routes correctly |
| **3 Telemetry** | [routing-graph-phase3-telemetry.plan.md](routing-graph-phase3-telemetry.plan.md) | Observe routes/confirms/ambiguity; **no learning** |
| **4 Persistence** | create when P3 ships | Durable graph + accepted edges; misroutes ≫ routine confirms. Carry-forward: JSONL reader should use `-Tail` / streaming (P3 full-file read is OK only at low volume). |
| **5 Review** | create when P4 ships | Metra proposes; operator accepts/rejects (highest long-term ROI) |
| **6 Concept / multi-hop** | create when P5 ships | Concept→product and bounded cross-stem paths |
| **7 Similarity tie-break** | **optional; do not author until P4–P6 prove need** | Tie-breaker only |

## Hard offs until criteria

- Future architecture leaking into the current phase (telemetry fields "for P4", etc.)
- Silent Observe→Apply for learned edges
- Vector search as the route map
