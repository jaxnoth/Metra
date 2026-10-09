---
name: Ops Ask Conflict Parent
overview: Parent umbrella for Ops/Ask/desk sequencing - lock Track A build order (stability before fix_batch offload), keep sibling lanes from colliding on OpsServer/Ask, and retire when the conflict lane is clear. Bing approve-with-minor-amendments 2026-09-21 folded below.
todos:
  - id: affirm-parent
    content: Surveyor Pack/Approve this parent; index stem ops-desk-ask-sequencing authority cursor (Bing Conditional Affirm folded 2026-09-21)
    status: completed
  - id: link-children
    content: Add relatedPlans cite on ops_ask_sidecar_stability + ops_ask_fix_batch pointing at this parent + locked sequence
    status: completed
  - id: yarn-idea
    content: "Optional: Yarn Capture/idea for Ops Desk Ask sequencing parent (Plan Board Subproject OpsDesk)"
    status: pending
  - id: integration-followthrough
    content: "After both Track A ships: iOS askBusy mapping + poll Ensure via named mutex (or cancel if folded into a child)"
    status: pending
  - id: retire-parent
    content: When Track A + integration done and no active child modifies Ops Ask concurrency / askBusy /api/meta / Ensure - mark parent Parked/Complete and archive
    status: pending
isProject: false
externalReviewHash: 224a09ceef27e4443f0017a8d9fbca1c360323c3ac3fc6e31d795639cbd231e4
approveForLoom: true
approveForLoomHash: 224a09ceef27e4443f0017a8d9fbca1c360323c3ac3fc6e31d795639cbd231e4
externalReviewed: true
loomAcceptedAt: "2026-10-08T20:52:57.8964670Z"
loomHandoffId: yh-61ec5675fbbe4ea467e208ce9db2bf41
status: Approved
---

# Ops Desk / Ask sequencing (parent)

**Stem:** `ops-desk-ask-sequencing`
**Role:** Parent umbrella (same pattern as [`attention_2.0_forward_cb1ee20e.plan.md`](attention_2.0_forward_cb1ee20e.plan.md)) - organize and sequence children; do **not** merge child bodies.
**Home:** Metra (Yarn / Plan Board Subproject **OpsDesk** + **Ask**). Not a TicketTracker ticket.
**Status:** Bing Approve with minor amendments (2026-09-21). Surveyor Approve recorded (content-bound marks). Index stem `ops-desk-ask-sequencing` already `authority: cursor`.

## Goal

One place to see **what ships next** on Ops/Ask without hunting ~30 Cursor leaves. Two children both rewrite [`OpsServer.ps1`](scripts/private/OpsServer.ps1) Ask behavior - without this parent, Loom/Surveyor can Approve them in either order and collide.

| Child leaf | Job |
|------------|-----|
| [`ops_ask_sidecar_stability_79118c68.plan.md`](ops_ask_sidecar_stability_79118c68.plan.md) | Remote reach / false offline |
| [`ops_ask_fix_batch_a72e390d.plan.md`](ops_ask_fix_batch_a72e390d.plan.md) | DEV-JMP01 CPU; Ask off accept-loop |

## Design

```mermaid
flowchart TB
  parent[Ops Desk / Ask sequencing parent]
  parent --> order[Order of execution]
  order --> step1[1 Sidecar stability]
  order --> step2[2 fix_batch]
  order --> step3[3 Integration follow-through]
  step1 --> stability[ops_ask_sidecar_stability]
  step2 --> fixbatch[ops_ask_fix_batch]
  step3 --> integrate[integration-followthrough]
  parent --> parallel[Parallel tracks B and C]
  parallel --> trackB[Track B Vision / iOS]
  parallel --> trackC[Track C Attention UI]
```

## Order of execution

Serialize Track A. Do **not** merge the two Ask children. Do **not** put async Ask worker work inside stability.

| Step | Plan / bite | Status | Pending | What it owns | Conflict surface |
|------|-------------|--------|---------|--------------|------------------|
| 0 | Foundation: `sidecar_complete_fix`, `metra_ops_host` / `ops_desk_coherence` | Shipped | 0 | Lease, health gate, Ensure recycle; tray Host→Ops→Ask | Cite only |
| **1** | [`ops_ask_sidecar_stability`](ops_ask_sidecar_stability_79118c68.plan.md) | **Todos complete** - affirm/index if still needed | 0 | Phone timeout, Ask `/health` poll, Serve+meta, error taxonomy, Ops Scheduled Task | Accept-loop Ensure; `/api/meta` shape; iOS errors |
| **2a** | [`ops_ask_fix_batch`](ops_ask_fix_batch_a72e390d.plan.md) **P0a** | **Next implement** | 6 total | Attention Project vs Reconcile; migrate `Get-MetraDeskPayload` callers | Desk payload / reconcile boundary |
| **2b** | same leaf **P0b** | Blocked until 2a (and step 1) | (same) | SemaphoreSlim `askBusy` 409; Ask worker off accept-loop | Accept-loop rewrite; named mutex Ensure |
| **2c** | same leaf **P1 → P2 → verify** | After 2b | (same) | Cost caps, caches, inspect | Telemetry must not share Ask gate |
| **3** | Parent todo `integration-followthrough` | After step 2 ships | 1 | iOS map `askBusy`; route poll Ensure through fix_batch named mutex | May cancel if folded into open child |
| 4 | Parent todo `retire-parent` | After 1–3 clear | 1 | Park/Complete this parent | See Retire parent when |

**Current next bite:** step **2a** (fix_batch P0a).

### Hard gates

| Gate | Rule |
|------|------|
| Default order | Step 1 → 2a → 2b → 2c → 3 → 4 |
| Override | Only via [Override authority](#override-authority-amendment-a) note on **this** parent (date, what, why, operator). Chat / Loom receipt / child footnote do not count. |
| Future children | Any new plan that touches Ask lifecycle, concurrency, `askBusy`/409, `/api/meta`, or Ensure must `relatedPlans` cite this parent **before** Approve (Amendment C). |
| Merge ban | Do not merge stability + fix_batch into one plan. |

---

## Track A - Ops/Ask conflict lane (serialize)

Same children as the execution table; ownership detail for desk scan.

| Child | Status | Pending | Owns | Conflict |
|-------|--------|---------|------|----------|
| **ops_ask_sidecar_stability** | Todos complete | 0 | Phone timeout, Ask `/health` poll, Serve+meta, error taxonomy, Ops Scheduled Task | Accept-loop Ensure; `/api/meta` shape; iOS errors |
| **ops_ask_fix_batch** | Unbuilt | 6 | Attention Project/Reconcile; SemaphoreSlim + Ask worker offload; cost caps | Accept-loop rewrite; 409 `askBusy`; named mutex Ensure |
| sidecar_complete_fix | Shipped | 0 | Lease, health gate, Ensure recycle | Foundation only - cite; live SDK pin **1.0.26** (ignore obsolete 1.0.30 todo) |
| metra_ops_host / ops_desk_coherence | Shipped | 0 | Tray Host→Ops→Ask; desk UX | Cite ownership chain |

## Track B - Vision / iOS (parallel OK)

May ship beside Track A **unless** they change Ops accept-loop concurrency, Ask single-flight, or `/api/meta` without citing this parent. Prefer consuming stability meta/error contracts.

| Child | Pending | Note | Wait on Track A? |
|-------|---------|------|------------------|
| vision_cursor_identity_stack | 6 | Vision identity loader - VisionAsk, not accept-loop offload | No |
| ios_conversation_policy_wire | 1 | Residual policy wire | No |
| ios_phase_1_spike | 5 | Spike leftovers; HTTPS/Tailscale client | Prefer stable Serve (step 1) |
| metra_ios_no-mac | 9 | Work Mac / reach program | Depends on step 1 Serve visibility |

## Track C - Ops desk Attention UI

| Child | Pending | Note | Wait on Track A? |
|-------|---------|------|------------------|
| ops_itsm_ui_mining | 7 | Attention card UX / desk payload | Yes for Project vs Reconcile - after **2a** |
| attention_2.0_forward | 4 | Separate **Attention** parent - cross-link only | No (different umbrella) |
| ticket_watch_* (affirm/bus; desk shipped) | 3+ | Sensors; Host poll later | Do not steal Ops Ask lifecycle |

## Outside this parent

No sequence gate unless the work edits `OpsServer` Ask paths: e.g. `tt_itsm_pattern_mining`, `orion_alert_desk`, `jitterbit_upgrade_policy`, `plan_index_per_project`, `github_public_audience_revision`, `inspect_runtime_verification` (parked), Scout (parked), routing soak, Atlas commit sessions. Capability routing - cite here only if it changes Ask engine bind.

---

## Parent duties

| # | Duty |
|---|------|
| 1 | Keep Track A order visible on Plan Board (OpsDesk / Ask). |
| 2 | Enforce future-child `relatedPlans` cite (Amendment C) before Approve. |
| 3 | After Track A children ship, complete or cancel `integration-followthrough`. |
| 4 | Do not invent a second Metra project or TicketTracker ticket for this. |

### Parent todos (this leaf)

| Todo | Status | When |
|------|--------|------|
| `affirm-parent` | completed | Surveyor Pack/Approve + index stem `ops-desk-ask-sequencing` |
| `link-children` | completed | Both Track A children cite this parent |
| `yarn-idea` | pending | Optional Capture / Plan Board idea |
| `integration-followthrough` | pending | Execution step 3 |
| `retire-parent` | pending | Execution step 4 |

## Override authority (Amendment A)

Track A order is the default gate for Loom / Surveyor / Yarn Approve of downstream Ask work.

**Any override must be recorded in this parent before approving out-of-order work.**

| Field | Required |
|-------|----------|
| Date (UTC) | yes |
| What is approved out of order | yes (e.g. fix_batch P0b before stability) |
| Why | one short paragraph |
| Operator | Stephen / display name |

### Override log

| Date (UTC) | What | Why | Operator |
|------------|------|-----|----------|
| *(none)* | | | |

Until a row exists here, out-of-order Approve of fix_batch P0b (or any third plan that changes Ask concurrency / Ensure / `/api/meta` ahead of stability) is **blocked**.

## Bing review (2026-09-21)

**Verdict:** Approve with minor amendments. Parent = portfolio coordination; children = implementation. Amendments A (override), B (retirement), C (future-child relatedPlans) folded above. Boundaries kept: Attention parent separate; TicketTracker not absorbed; OpsDesk/Ask stay portfolio categories.

## Yarn / Surveyor gate (after affirm)

| Action | Detail |
|--------|--------|
| Authority | Cursor leaf under `%USERPROFILE%\.cursor\plans\` |
| Index | Upsert stem `ops-desk-ask-sequencing` |
| Optional | Yarn idea "Ops Desk / Ask sequencing parent" linking both children |
| Children | Already point here in Related sections |

## Done when (coordination)

| Check | State |
|-------|-------|
| Both Track A children cite this parent + locked sequence | Done (`link-children`) |
| One plan shows what else is live on Ops/Ask | This leaf |
| Only Amendment A overrides Track A order | Active |

## Retire parent when (Amendment B)

Park / Complete (Surveyor archive / Yarn park) when **all** are true:

| # | Condition |
|---|-----------|
| 1 | `ops_ask_sidecar_stability` shipped (or cancelled with note here) |
| 2 | `ops_ask_fix_batch` shipped (or cancelled with note here) |
| 3 | Integration follow-through completed **or** cancelled on this parent |
| 4 | No active child (pending todos) modifies Ask concurrency, `askBusy`, `/api/meta`, or Ensure |

Retirement is archival - not an automatic Loom action. A later plan that reopens those surfaces must revive this parent or create a new sequencing parent and re-lock order.
