# Routing graph Phase 3 - Telemetry

**Bite only.** Observe routes / confident picks / ambiguity. No learning, durable graph file, Review suggest, or embeddings.

Depends on: Phase 2 Foundation shipped. Master: [routing-graph-evolution.plan.md](routing-graph-evolution.plan.md).

## Outcome

Every live `routing` / `ctx` resolution appends one observation line under `%LOCALAPPDATA%\Metra\routing\events.jsonl` so later phases can count misroutes vs routine confidence without changing the scorer.

Central rule: `Add-MetraRoutingTelemetryEvent` receives the **completed** ambiguity result and performs **no** scoring, token matching, thresholding, or route reconstruction. Phase 3 is a **witness**.

## Deliverables

- `Get-MetraRoutingTelemetryRoot` / `Get-MetraRoutingTelemetryEventsPath` - path only (never create)
- `Add-MetraRoutingTelemetryEvent` - only creator of the directory; one compressed JSON line; UTF-8 append; silent catch
- Wired at end of `Get-MetraRoutingAmbiguity`: build result → emit → return; `-SkipTelemetry`; `-Source` soft-normalized inside helper (`routing` | `ctx` | `other`)
- `.\metra.ps1 routing events [-Last N]` read-only tail (default 20; never create sink)
- Pester matrix under overridden `$env:LOCALAPPDATA`
- Privacy scar in Decisions (512-cap query; machine-local; no export without a later design)

## Event schema

| Field | Notes |
|-------|-------|
| `tsUtc` | ISO UTC |
| `source` | `routing` / `ctx` / `other` |
| `query` | Single-line, trim, max 512 chars; empty/whitespace → `""` |
| `outcome` | `confident` \| `ambiguous` \| `home` |
| `primary` | Project name |
| `primaryScore` | int |
| `runnerUp` | name or JSON null |
| `runnerUpScore` | int or JSON null (never coerce absent to `0`) |
| `isAmbiguous` | bool |
| `matchedTokens` | string[] from primary |
| `favoredTokens` | when ambiguous; otherwise `[]` (rectangular) |

## Outcome table

| Route result | `outcome` |
|--------------|-----------|
| Primary wins and `IsAmbiguous = false` (clears confident threshold) | `confident` |
| Close-score ask-once (`IsAmbiguous = true`) | `ambiguous` |
| No project clears home threshold (weak → Metra home) | `home` |

Do not derive `outcome` solely from `IsAmbiguous`.

## Sink contract

- Path getters never create directory or file.
- Only `Add-MetraRoutingTelemetryEvent` creates `%LOCALAPPDATA%\Metra\routing`.
- Readers never append and never create the sink.
- Hot path: no warning / verbose / error-stream noise from telemetry by default.

## Privacy

- Query capped at 512 chars with newline normalization.
- No credentials or proposal payloads intentionally added.
- `%LOCALAPPDATA%` data stays untracked.
- Future export / aggregation needs a separate explicit design decision.

## Done when

| Check | Expect |
|-------|--------|
| Compound ops query | Automation + JSONL `outcome=confident`, `compound:ops` |
| Ask-once / close score | `outcome=ambiguous` + runner-up + favoredTokens |
| Weak query | `outcome=home`; runner-up null |
| Empty / multiline query | No throw; one valid single-line JSON event |
| Unwritable sink | Routing still returns |
| `routing events` missing / malformed | Read-only, usable |
| Pester matrix | Pass |
| Scorer | Unchanged vs Phase 2 fixtures |

## Out of scope

Durable edges, Review suggest, concept/multi-hop, silent Observe→Apply, P4 fields, cue-weight changes, sanitizer beyond 512 + newlines.
