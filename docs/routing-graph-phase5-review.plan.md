# Routing graph Phase 5 - Review

**Bite only.** Metra proposes routing edges from telemetry/candidates; operator affirms or rejects. No silent Observe→Apply, no embeddings, no concept/multi-hop.

Depends on: Phase 4 Persistence shipped. Master: [routing-graph-evolution.plan.md](routing-graph-evolution.plan.md).

**Bing verdict (accepted):** ship this bite after locking the policies below. Coding agents must not invent review behavior - everything below is contract.

## Outcome

Ambiguous telemetry aggregates into **deterministic edge proposals** under `%LOCALAPPDATA%\Metra\routing\proposals.json`. The operator reviews pending proposals via CLI, **affirms** (Apply to graph.json) or **rejects** (dismiss without graph write). Routine confident routes never auto-propose.

Roadmap principle: **misroutes ≫ routine confirms** - propose only when compound cue evidence disagrees with the ambiguous primary.

## Non-negotiable safety boundary

```text
events.jsonl ──read──> candidates ──read──> propose ──write──> proposals.json
                                              │
                         review / affirm / reject (read proposals.json)
                                              │
              affirm ──write──> graph.json     reject ──write──> proposals.json only
              (via Add-MetraRoutingAcceptedEdge only)
```

**Structural rules (extends P4):**

- Only `routing edges accept`, `routing edges affirm`, and `routing edges remove` may call durable graph mutation helpers.
- `propose` and `reject` may write `proposals.json` only - never `graph.json`.
- `candidates`, `routing events`, and telemetry readers have **no** code path into graph or proposal mutators.
- Manual `accept` remains valid without a proposal (operator knows best).

## Locked decisions (Bing)

### 1. Proposal trigger = ambiguous + compound misroute

Input: `Get-MetraRoutingEdgeCandidates -Last N` (ambiguous telemetry only).

For each candidate row with `Count >= MinCount` (default **2**):

1. Resolve **suggested target** from registry graph (`Get-MetraRoutingGraph`):
   - `cueClass ops` → Ops sibling for stem
   - `cueClass sql` → Sql sibling for stem
2. Skip when no registry family exists for stem + role.
3. Skip when `Primary` already equals suggested target (no misroute signal).
4. **Target** on the proposal = suggested sibling (not primary).

Rationale: ambiguous rows already carry `compound:ops|sql` in favored/matched tokens; when primary ≠ sibling, telemetry witnessed a close wrong winner.

Do **not** propose from `outcome=confident` or `outcome=home` in Phase 5.

### 2. De-duplication and suppression

Before adding a pending proposal:

- Skip if durable graph already has the same normalized **stem + cueClass** with **target** equal to suggested target.
- Skip if a **pending** proposal exists with the same stem + cueClass + target fingerprint.
- Skip if a **rejected** proposal exists with the same fingerprint (do not re-propose until operator clears rejections - Phase 5 has no `unreject`; manual `accept` still works).

Fingerprint = uppercase stem + lowercase cueClass + canonical registry target name.

### 3. Proposal id and schema v1

Path: `%LOCALAPPDATA%\Metra\routing\proposals.json` (path helper never creates file/dir).

Proposal id: `p_{STEM}_{cueClass}_{targetSlug}` (same target slug rules as accepted edge ids).

Minimum valid proposal:

| Field | Rule |
|-------|------|
| `id` | non-empty |
| `stem` | normalized uppercase |
| `cueClass` | `ops` \| `sql` |
| `target` | registry project name |
| `status` | `pending` \| `affirmed` \| `rejected` |
| `reason` | human string (may cite count + primary) |
| `evidence` | object with `count`, `primary`, `runnerUp`, `source=telemetry` |
| `proposedAtUtc` | parseable UTC |
| `resolvedAtUtc` | null when pending; ISO UTC when affirmed/rejected |
| `source` | `review` |

Root: `{ version: 1, proposals: [] }`.

### 4. Fail-soft reads; fail-loud writes

`Get-MetraRoutingProposals` returns empty v1 for missing/invalid JSON (same spirit as graph read - filter bad records, never rewrite on read).

`Save-MetraRoutingProposals`, `propose`, `affirm`, `reject`: validate then atomic write (temp sibling + replace). Throw on write failure.

### 5. Affirm = Apply via existing accept path

`affirm -Id <proposalId>`:

1. Load pending proposal by exact id.
2. Call `Add-MetraRoutingAcceptedEdge` (P4 replace semantics for stem+cueClass).
3. Mark proposal `status=affirmed`, set `resolvedAtUtc`, save proposals once.
4. Return edge + proposal.

Affirm on non-pending or missing id: throw / CLI error (no partial graph write).

### 6. Reject = dismiss only

`reject -Id <proposalId>`:

1. Load pending proposal.
2. Set `status=rejected`, `resolvedAtUtc`, optional note in `reason` suffix.
3. Save proposals.json only.

Never call graph mutators on reject.

### 7. Propose is idempotent refresh

`propose [-Last 200] [-MinCount 2]`:

- Re-read candidates; upsert **new** pending rows only (per de-duplication rules).
- Does not re-open rejected or affirmed proposals.
- Does not remove stale pending proposals automatically (operator rejects or affirms).
- Output: count added + table of new pending proposals.

## CLI

```text
.\metra.ps1 routing edges propose [-Last 200] [-MinCount 2]
.\metra.ps1 routing edges review [-Status pending|affirmed|rejected|all]
.\metra.ps1 routing edges affirm -Id p_IWUDATA_ops_iwudata_automation [-Note '…']
.\metra.ps1 routing edges reject -Id p_IWUDATA_ops_iwudata_automation [-Note '…']
```

Existing P4 commands unchanged: `list`, `candidates`, `accept`, `remove`.

## Done when

| Check | Expect |
|-------|--------|
| Pester matrix | Pass (propose / review / affirm / reject / safety boundary) |
| Ambiguous misroute fixture | `propose` creates pending row; primary ≠ target |
| MinCount | Count=1 skipped; Count=2 proposes |
| Affirm | graph.json edge + proposal affirmed |
| Reject | proposals.json only; graph untouched |
| Re-propose after reject | Same fingerprint skipped |
| Graph already correct | propose skips |
| candidates / events | Still never write graph or proposals |

## Out of scope

Concept/multi-hop (P6), similarity tie-break (P7), silent Observe→Apply, LLM proposal text, embedding signals, exporting telemetry, committing machine-local JSON, `unreject` / proposal expiry sweeps.
