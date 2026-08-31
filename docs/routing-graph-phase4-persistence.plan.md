# Routing graph Phase 4 - Persistence

**Bite only.** Durable graph + operator-accepted edges. No Review propose UI, no silent Observe→Apply, no embeddings, no cue-weight redesign.

Depends on: Phase 3 Telemetry shipped. Master: [routing-graph-evolution.plan.md](routing-graph-evolution.plan.md).

**Bing verdict (accepted):** ship this bite after locking the policies below. Coding agents must not invent persistence behavior - everything below is contract.

## Outcome

Operator-accepted routing edges persist under `%LOCALAPPDATA%\Metra\routing\graph.json`, reload into the scorer with explainable `edge:<id>` evidence, and survive restarts - without turning P3 Observe into Apply.

Roadmap principle: **misroutes ≫ routine confirms** - accept corrections; do not persist every confident event.

## Non-negotiable safety boundary

```text
events.jsonl ──read──> candidates
                         │
                         │ operator reviews
                         ▼
CLI accept/remove ──write──> graph.json ──read──> graph builder ──> scorer
```

**Structural rule:** Only the `routing edges accept` and `routing edges remove` command handlers may call durable graph mutation helpers (`Save-MetraRoutingDurableGraph`, `Add-MetraRoutingAcceptedEdge`, `Remove-MetraRoutingAcceptedEdge`). Candidate generation and telemetry readers must have **no** code path into those mutators.

## Locked decisions (Bing)

### 1. Duplicate stem + cueClass = replace

A new acceptance for an existing **normalized** stem + cueClass **replaces** the prior edge (does not reject).

- Normalize stem → uppercase.
- Normalize cueClass → lowercase (`ops` | `sql`).
- Derive ID from normalized stem, cueClass, **and full normalized target** (opaque to callers).
- Remove any existing edge with the same normalized stem + cueClass.
- Add the replacement edge; save **once**; return the resulting edge.

### 2. Fail-soft reads; fail-loud writes

`Get-MetraRoutingDurableGraph` returns `@{ version = 1; edges = @() }` for missing/empty/invalid JSON/unsupported root/missing edges/non-array edges/unsupported version.

Partially valid files: accept valid v1 root; **filter** invalid edge records; return remaining valid edges; **never rewrite** the graph merely because invalid entries were skipped.

`Save-MetraRoutingDurableGraph` / accept / remove: validate then atomic write (temp sibling + replace). **Throw / non-success to CLI** on write failure.

### 3. Scorer idempotency via MatchedTokens

Machine token: `edge:<id>` (display: `Accepted edge: STEM + cue → Target`).

Before applying each matching edge:

```powershell
if (@($Project.MatchedTokens) -contains "edge:$($Edge.id)") { continue }
```

Then: ensure target row exists (P2 sibling-insert schema); add exactly **+4**; add exactly one `edge:<id>` token; preserve row property schema and collection types.

### 4. Multiple matching edges

Uniqueness is stem + cueClass only. A query may match multiple stems and/or both ops and sql. **Each distinct accepted edge may apply once** per scoring pass.

### 5. Call order

```text
Update-MetraScoredRoutingWithCompoundCues
Update-MetraScoredRoutingWithAcceptedEdges
```

Explanation precedence: `edge:*` then `compound:*` then weaker evidence. Leave compound evidence in place alongside edge tokens.

### 6. Telemetry -Tail

`Get-Content -LiteralPath $Path -Tail $Last` - last **physical** lines, not "last N valid JSON". Missing file → no events; skip malformed; never create sink.

## Schema v1

Path: `%LOCALAPPDATA%\Metra\routing\graph.json` (path helper never creates file/dir).

Minimum valid edge: non-empty `id`, `stem`, `target`; `cueClass` in `ops|sql`; parseable UTC `acceptedAtUtc`; `source` = `operator`; `note` string (may be empty).

## CLI

```text
.\metra.ps1 routing edges
.\metra.ps1 routing edges candidates [-Last 200]
.\metra.ps1 routing edges accept -Stem … -CueClass ops|sql -Target … [-Note '…']
.\metra.ps1 routing edges remove -Id …
```

## Done when

| Check | Expect |
|-------|--------|
| Pester matrix | Pass (persistence / scorer / candidates / CLI) |
| Restart reload | Accepted edge survives; scorer applies after reload |
| events cannot mutate graph | candidates + telemetry readers never write graph.json |
| `-Tail` | Reader uses physical tail, not full-file slice |

## Out of scope

Phase 5 Review Affirm, silent Observe→Apply, embeddings, concept/multi-hop, committing graph.json, exporting telemetry.
