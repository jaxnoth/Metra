---
name: Routing graph Phase 5 - Review
overview: "Shipped contract - propose pending edges from ambiguous+compound misroutes into proposals.json; operator affirm→graph via Add-MetraRoutingAcceptedEdge or reject without graph write."
status: Shipped
shippedAt: 2026-08-31
bingReviewed: true
phase: routing-graph-5
todos:
  - id: proposals-io
    content: Get/Save proposals.json (fail-soft read, fail-loud atomic write, schema v1)
    status: completed
  - id: propose
    content: Update-MetraRoutingEdgeProposals from candidates (MinCount 2, misroute only)
    status: completed
  - id: affirm-reject
    content: Affirm via Add-MetraRoutingAcceptedEdge; reject proposals-only
    status: completed
  - id: suppression
    content: Skip pending/rejected fingerprint and matching durable edge
    status: completed
  - id: cli-pester
    content: routing edges propose/review/affirm/reject + Pester review + Decisions scar
    status: completed
---

# Routing graph Phase 5 - Review

**Status: shipped** (code + Pester live; this file is the filled contract / residual ledger). Yarn/plan-board: YAML `status: Shipped` + all todos `completed`. Bing affirmed 2026-09-06 (`bingReviewed: true`).

**Bite only.** Metra proposes routing edges from telemetry/candidates; operator affirms or rejects. No silent Observe→Apply, no embeddings, no concept/multi-hop.

Depends on: Phase 4 Persistence shipped. Master: [routing-graph-evolution.plan.md](routing-graph-evolution.plan.md).

Scar: [Decisions.md](../docs/Decisions.md) 2026-08-31 Routing graph Review proposes; operator affirms.

## Bing-affirmed commitments (2026-09-06)

1. **Propose is not Apply** - P5 grants authority to **proposing**, not to learning itself. Observe → propose → operator review → affirm → apply. The routing subsystem cannot modify itself; only the operator can. Affirm uses `Add-MetraRoutingAcceptedEdge` only - one memory path.
2. **Conservative misroute recommendations** - Propose only when ambiguous + compound cue + misroute (primary ≠ registry sibling) + MinCount + valid Ops|Sql family. Telemetry supplies evidence; `Get-MetraRoutingGraph` supplies structure. No free-form stem/cue/target invention; no popularity learning from confident traffic (**misroutes ≫ routine confirms**).
3. **Rejection is sticky** - Pending, rejected, and matching durable edges suppress re-propose. No nag loop. Manual `accept` remains valid. Still hard-off: auto-accept, auto-persist, auto-reweight, lexicon self-edit, autonomous graph creation.

Stack complete in **workflow** (Route → Observe → Candidate → Review → Affirm → Remember → Route better), not in capability (concepts / multi-hop / embeddings remain later).

## Outcome

Ambiguous telemetry aggregates into **deterministic edge proposals** under `%LOCALAPPDATA%\Metra\routing\proposals.json`. The operator reviews pending proposals via CLI, **affirms** (Apply to `graph.json`) or **rejects** (dismiss without graph write). Routine confident routes never auto-propose.

Roadmap principle: **misroutes ≫ routine confirms** - propose only when compound cue evidence disagrees with the ambiguous primary.

This is the **Learn loop** in Metra terms: Observe → Recommend → Approve/Reject → Apply. Learning proposes; the operator still owns Apply.

## Problem this bite solves

Phase 4 gave durable memory but every edge required a fully manual `accept`. Phase 5 turns ambiguous+compound scars in telemetry into **reviewable proposals** so the operator can affirm corrections without inventing stem/cue/target by hand - still never silent Apply.

## Architecture (Phase 5 slice)

```text
events.jsonl ──read──> candidates ──read──> propose ──write──> proposals.json
                                              │
                         review / affirm / reject (read proposals.json)
                                              │
              affirm ──write──> graph.json     reject ──write──> proposals.json only
              (via Add-MetraRoutingAcceptedEdge only)
```

Stack after P5:

```text
Think (P2) → Observe (P3) → Remember (P4) → Learn/Review (P5)
```

Concept / multi-hop remain Phase 6+.

## Architectural commitments

1. **Propose is not Apply** - `propose` and `reject` write `proposals.json` only. Only `accept`, `affirm`, and `remove` may call durable graph mutators.
2. **Observations suggest…** - Proposals cite ambiguous counts and wrong primary. They never claim "we think this edge is useful" as a scorer change until the operator affirms.
3. **Same memory path** - Affirm calls `Add-MetraRoutingAcceptedEdge` (P4 replace semantics). No second write shape for learned edges.

## Non-negotiable safety boundary

**Structural rules (extends P4):**

- Only `routing edges accept`, `routing edges affirm`, and `routing edges remove` may call durable graph mutation helpers.
- `propose` and `reject` may write `proposals.json` only - never `graph.json`.
- `candidates`, `routing events`, and telemetry readers have **no** code path into graph or proposal mutators.
- Manual `accept` remains valid without a proposal (operator knows best).

## Locked contract

### 1. Path helper (never creates)

| Helper | Path |
|--------|------|
| `Get-MetraRoutingProposalsPath` | `%LOCALAPPDATA%\Metra\routing\proposals.json` |

Path helper never creates directory or file. Save may create the routing directory when writing.

### 2. Proposal trigger = ambiguous + compound misroute

Input: `Get-MetraRoutingEdgeCandidates -Last N` (ambiguous telemetry only; P4 Observe).

For each candidate row with `Count >= MinCount` (default **2**):

1. Resolve **suggested target** from registry graph (`Get-MetraRoutingSuggestedTargetForStemCue` / `Get-MetraRoutingGraph`):
   - `cueClass ops` → Ops sibling for stem
   - `cueClass sql` → Sql sibling for stem
2. Skip when no registry family exists for stem + role.
3. Skip when `Primary` already equals suggested target (no misroute signal).
4. Canonicalize target via registry; **Target** on the proposal = suggested sibling (not primary).

Rationale: ambiguous rows already carry `compound:ops|sql` in favored/matched tokens; when primary ≠ sibling, telemetry witnessed a close wrong winner.

Do **not** propose from `outcome=confident` or `outcome=home` in Phase 5.

Default reason string shape: `ambiguous x{N}: compound:{cue} favored; primary was {Primary}`.

### 3. De-duplication and suppression

Before adding a pending proposal:

- Skip if durable graph already has the same normalized **stem + cueClass** with **target** equal to suggested (or canonical) target.
- Skip if a **pending** or **rejected** proposal exists with the same fingerprint.
- Affirmed fingerprints are suppressed via the durable-edge match (affirm already wrote `graph.json`).

Fingerprint = uppercase stem + lowercase cueClass + canonical registry target name.

Phase 5 has **no** `unreject`; manual `accept` still works after reject.

### 4. Proposal id and schema v1

Root: `{ "version": 1, "proposals": [ ... ] }`

Proposal id: `p_{STEM}_{cueClass}_{targetSlug}` via `Get-MetraRoutingProposalId` (same target slug rules as accepted edge ids; `p` + edge-id suffix).

| Field | Rule |
|-------|------|
| `id` | non-empty |
| `stem` | normalized uppercase |
| `cueClass` | `ops` \| `sql` |
| `target` | registry project name |
| `status` | `pending` \| `affirmed` \| `rejected` |
| `reason` | human string (may cite count + primary); present (may gain `| rejected: …` suffix) |
| `evidence` | object with `count`, `primary`, `runnerUp`, `source=telemetry` |
| `proposedAtUtc` | parseable UTC |
| `resolvedAtUtc` | JSON **null** when pending; ISO UTC when affirmed/rejected |
| `source` | `review` |

`Test-MetraRoutingProposalRecord` enforces pending ⇒ empty resolved; resolved statuses ⇒ parseable `resolvedAtUtc`.

### 5. Fail-soft reads; fail-loud writes

`Get-MetraRoutingProposals` returns empty v1 for missing/invalid JSON (filter bad records; **never rewrite on read**).

`Save-MetraRoutingProposals`, `propose`, `affirm`, `reject`: validate then atomic write (`proposals.json.tmp` + replace). Throw on write failure.

### 6. Propose is idempotent refresh

`Update-MetraRoutingEdgeProposals [-Last 200] [-MinCount 2]` / CLI `propose`:

- Re-read candidates; upsert **new** pending rows only (per de-duplication rules).
- Does not re-open rejected or affirmed proposals.
- Does not remove stale pending proposals automatically (operator rejects or affirms).
- If nothing added, does **not** create `proposals.json`.
- Output: `added` / `addedCount` (+ CLI table of new pending).

### 7. Affirm = Apply via existing accept path

`Invoke-MetraRoutingEdgeAffirm -Id <proposalId> [-Note]`:

1. Load pending proposal by exact id (missing / non-pending → throw; no partial graph write intended).
2. Call `Add-MetraRoutingAcceptedEdge` (P4 replace semantics for stem+cueClass).
3. Mark proposal `status=affirmed`, set `resolvedAtUtc`, save proposals once.
4. Return `{ proposal, edge }`.

### 8. Reject = dismiss only

`Invoke-MetraRoutingEdgeReject -Id <proposalId> [-Note]`:

1. Load pending proposal.
2. Set `status=rejected`, `resolvedAtUtc`; optional note appended as `| rejected: …` on `reason`.
3. Save `proposals.json` only.

Never call graph mutators on reject.

### 9. CLI

```text
.\metra.ps1 routing edges propose [-Last 200] [-MinCount 2]
.\metra.ps1 routing edges review [-Status pending|affirmed|rejected|all]
.\metra.ps1 routing edges affirm -Id p_IWUDATA_ops_iwudata_automation [-Note '…']
.\metra.ps1 routing edges reject -Id p_IWUDATA_ops_iwudata_automation [-Note '…']
```

Existing P4 commands unchanged: `list`, `candidates`, `accept`, `remove`.

## Deliverables (shipped)

| Item | Location |
|------|----------|
| Path / id / validate | `Get-MetraRoutingProposalsPath`, `Get-MetraRoutingProposalId`, `Test-MetraRoutingProposalRecord` |
| Load / save | `Get-MetraRoutingProposals`, `Save-MetraRoutingProposals` |
| Suggest / suppress | `Get-MetraRoutingSuggestedTargetForStemCue`, `Test-MetraRoutingProposalFingerprintExists`, `Test-MetraRoutingDurableEdgeMatches` |
| Propose | `Update-MetraRoutingEdgeProposals` |
| Affirm / reject | `Invoke-MetraRoutingEdgeAffirm`, `Invoke-MetraRoutingEdgeReject` |
| CLI | `Show-MetraRoutingEdgesCli` propose / review / affirm / reject |
| Decision | `docs/Decisions.md` 2026-08-31 Routing graph Review |
| Pester | `tests/Metra.Tests.ps1` - `Describe 'Metra routing review'` |

## Done when (acceptance matrix)

| Check | Expect |
|-------|--------|
| Ambiguous misroute ×2 | `propose` creates one pending; target = Ops/Sql sibling; primary ≠ target; graph untouched |
| MinCount | Count=1 skipped; no proposals file created |
| Affirm | `graph.json` edge + proposal `affirmed` + `resolvedAtUtc` |
| Reject | `proposals.json` only; graph file still absent/unchanged |
| Re-propose after reject | Same fingerprint skipped (`addedCount=0`) |
| Graph already correct | propose skips |
| candidates / events | Still never write graph or proposals |
| Pester `Metra routing review` | Pass under overridden `$env:LOCALAPPDATA` |

## Verification commands

```powershell
.\metra.ps1 routing edges candidates -Last 50
.\metra.ps1 routing edges propose -Last 200 -MinCount 2
.\metra.ps1 routing edges review -Status pending
.\metra.ps1 routing edges affirm -Id p_IWUDATA_ops_iwudata_automation -Note 'scar'
# or: .\metra.ps1 routing edges reject -Id … -Note 'not now'
.\metra.ps1 routing edges
Invoke-Pester -Path .\tests\Metra.Tests.ps1 -FullName '*routing review*'
```

## Out of scope (later / hard off)

| Deferred | Owner |
|----------|--------|
| Concept / multi-hop | Phase 6 |
| Similarity tie-break | Phase 7 (optional) |
| Silent Observe→Apply | Hard off |
| LLM proposal text / embeddings | Hard off |
| `unreject` / proposal expiry sweeps | Out of scope |
| Export / commit machine-local JSON | Hard off |
| Changing MinCount default without Decision | Operator + Decision |

## Residual / follow-ups (not blockers for "Phase 5 shipped")

- Affirm writes graph then proposals; a crash between those steps can leave an accepted edge with a still-pending proposal - re-affirm throws; operator can `review` / manual reconcile. Prefer small follow-up only if seen in ops.
- Empty telemetry ⇒ empty propose (correct). Destination still needs real affirms (or manual accept) so `graph.json` is not empty on HQ.
- Why-here edge display thinness noted in P4 residual still applies after affirm.

## Operator notes

Phase 5 closes Observe → Recommend → Approve → Apply without self-training. Typical scar path:

```powershell
.\metra.ps1 routing edges propose
.\metra.ps1 routing edges review -Status pending
.\metra.ps1 routing edges affirm -Id <id> -Note 'phone Ask IWUDATA ops'
```

Or skip propose and `accept` directly when the operator already knows the edge.
