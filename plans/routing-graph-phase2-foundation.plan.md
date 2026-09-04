# Routing graph Phase 2 - Foundation

**Bite only.** No telemetry, persistence, learning, Review UI, concept scoring, or embeddings.

Depends on: Tailscale identity/auth scar shipped (2026-08-29). Master roadmap: [routing-graph-evolution.plan.md](routing-graph-evolution.plan.md).

## Outcome

`How did IWUDATA run today?` → **IWUDATA-Automation** with explainable compound evidence, without relying only on local phrase triggers.

## Deliverables

- `Get-MetraRoutingGraph` - registry → builder → stem/Ops|Sql families (mutual related, fail-closed roles; concepts harvested not scored)
- `Get-MetraCompoundRoutingCueHits` - Ops vs Sql cue classes on raw query (boundary-safe)
- `Update-MetraScoredRoutingWithCompoundCues` - +4 once per family; tags `compound:ops` / `compound:sql`; SQL wins when both classes present; idempotent; schema-preserving sibling insert
- Wired into `Get-MetraScoredRoutingProjects` after haystack, before sort
- Why-here surfaces `Compound cue: product+ops|product+sql`; FavoredTokens prefer `compound:*`
- Pester `*compound*` / `*RoutingGraph*`

## Done when

| Query | Expect |
|-------|--------|
| How did IWUDATA run today? | Automation + `compound:ops` |
| iwudata sql deploy | SQL + `compound:sql` |
| iwudata | no `compound:*` (no invented certainty) |
| iwudata job deploy | SQL (mixed-cue precedence) |
| Synthetic SQL 4 vs Automation 2 | Automation 6 after apply; second invoke unchanged |

## Out of scope

Telemetry, graph file, Review suggest, multi-hop, embeddings.
