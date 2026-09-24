---
name: Ops Ask Conflict Parent
overview: Parent umbrella for active unbuilt Ops/Ask/desk plans - inventory conflict surfaces, lock build sequence (stability before fix_batch offload), and keep sibling lanes from colliding on OpsServer/Ask without merging plans. Bing approve-with-minor-amendments 2026-09-21 folded below.
todos:
  - id: affirm-parent
    content: Surveyor Pack/Approve this parent; index stem ops-desk-ask-sequencing authority cursor (Bing Conditional Affirm folded 2026-09-21)
    status: pending
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
    content: "When Track A + integration done and no active child modifies Ops Ask concurrency / askBusy /api/meta / Ensure - mark parent Parked/Complete and archive"
    status: pending
isProject: false
relatedPlans:
  - ops_ask_sidecar_stability_79118c68.plan.md
  - ops_ask_fix_batch_a72e390d.plan.md
  - attention_2.0_forward_cb1ee20e.plan.md
---

# Ops Desk / Ask sequencing (parent)

**Stem:** `ops-desk-ask-sequencing`
**Role:** Parent umbrella (same pattern as [`attention_2.0_forward_cb1ee20e.plan.md`](attention_2.0_forward_cb1ee20e.plan.md)) - organize and sequence children; do **not** merge child bodies.
**Home:** Metra (Yarn / Plan Board Subproject **OpsDesk** + **Ask**). **Not** a TicketTracker iSupport ticket - portfolio plan conflict is Yarn/Plan Board territory.
**Status:** Approved with minor amendments (Bing 2026-09-21) - amendments A/B/C folded below. Surveyor Approve / Yarn index still pending operator.

## Bing review (2026-09-21)

**Verdict:** Approve with minor amendments. Parent stays portfolio coordination; children keep implementation authority. Amendments A (override authority), B (retirement), C (future-child relatedPlans) folded into this document.

Boundaries checked and kept: parent owns sequencing; children own implementation; Attention parent stays separate; TicketTracker not absorbed; OpsDesk/Ask remain portfolio categories.

---

## Why this parent exists

~30 Cursor leaves still have `pending` todos. Two unbuilt plans both rewrite [`OpsServer.ps1`](scripts/private/OpsServer.ps1) Ask behavior:

- [`ops_ask_sidecar_stability_79118c68.plan.md`](ops_ask_sidecar_stability_79118c68.plan.md) - remote reach / false offline
- [`ops_ask_fix_batch_a72e390d.plan.md`](ops_ask_fix_batch_a72e390d.plan.md) - DEV-JMP01 CPU; Ask off accept-loop

Without a parent, Loom/Surveyor can Approve either in either order and collide. Yarn `clusterHint` alone does **not** create parent epics (inventory metadata only).

---

## Snapshot - active unbuilt (pending todos > 0)

Broad portfolio (~30 leaves). **Conflict-relevant cluster only** below. Other pending work (Jitterbit, TT mining, Orion, installer, routing soak, Atlas, Scout parked, etc.) stays outside this parent unless it edits `OpsServer` Ask paths.

### Track A - Ops/Ask conflict lane (serialize)

| Child | Pending | Owns | Conflict |
|-------|---------|------|----------|
| **ops_ask_sidecar_stability** | 7 | Phone timeout, Ask `/health` poll, Serve+meta, error taxonomy, Ops Scheduled Task | Accept-loop Ensure; `/api/meta` shape; iOS errors |
| **ops_ask_fix_batch** | 6 | Attention Project/Reconcile; SemaphoreSlim + Ask worker offload; cost caps | Accept-loop rewrite; 409 `askBusy`; named mutex Ensure |
| sidecar_complete_fix | 0 (shipped) | Lease, health gate, Ensure recycle | Foundation only - cite; ignore obsolete SDK 1.0.30 todo (live pin **1.0.26**) |
| metra_ops_host / ops_desk_coherence | 0 (shipped) | Tray Host→Ops→Ask; desk UX | Cite ownership chain |

**Locked sequence**

1. Ship **sidecar stability** under current sync Ask (poll + iOS timeout + Serve meta + Task).
2. Ship **fix_batch** P0a → P0b → P1… (offload + gate).
3. Tiny integration follow-through: iOS map `askBusy`; route poll Ensure through fix_batch named mutex.

Do **not** merge these two plans. Do **not** implement async Ask worker inside stability.

### Track B - Vision / iOS (parallel OK if they avoid OpsServer accept-loop)

| Child | Pending | Note |
|-------|---------|------|
| vision_cursor_identity_stack | 6 | Vision identity loader - touch VisionAsk, not accept-loop offload |
| ios_conversation_policy_wire | 1 | Residual policy wire |
| ios_phase_1_spike | 5 | Spike leftovers; HTTPS/Tailscale client |
| metra_ios_no-mac | 9 | Work Mac / reach program - may assume stable Serve; **depends on** stability Serve visibility |

**Rule:** iOS/Vision children may ship in parallel with Track A **except** they must not change Ops accept-loop concurrency, Ask single-flight, or `/api/meta` schema without citing this parent. Prefer consuming stability's meta/error contracts once shipped.

### Track C - Ops desk Attention UI (aware of fix_batch P0a)

| Child | Pending | Note |
|-------|---------|------|
| ops_itsm_ui_mining | 7 | Attention card UX - may call desk payload; must use Project vs Reconcile once fix_batch P0a lands |
| attention_2.0_forward | 4 | Separate **Attention** parent - TicketWatch/Scout; cross-link only |
| ticket_watch_* (affirm/bus; desk shipped) | 3+ | Sensors; Host poll later - do not steal Ops Ask lifecycle |

**Rule:** Attention UI work can proceed, but any `Get-MetraDeskPayload` / reconcile change waits for or follows fix_batch **P0a** boundary.

### Outside this parent (no Ops Ask conflict)

Examples with pending todos that do **not** need this sequence gate: `tt_itsm_pattern_mining`, `orion_alert_desk`, `jitterbit_upgrade_policy`, `plan_index_per_project`, `github_public_audience_revision`, `inspect_runtime_verification` (parked stub), `Scout` (parked), routing graph soak, Atlas commit sessions, capability routing inertia (routing product - cite if it changes Ask engine bind).

---

## Parent duties

1. Keep Track A sequence visible on Plan Board (Subproject OpsDesk/Ask).
2. **Future-child gate (Amendment C):** Any **new** plan that modifies OpsServer Ask lifecycle, Ask concurrency, Ask Busy semantics (`askBusy` / 409), `/api/meta` schema, or Ask Ensure behavior must list `relatedPlans` citing this parent (stem `ops-desk-ask-sequencing` or leaf `ops_ask_conflict_parent_6578644c.plan.md`) **before** Surveyor/Yarn Approve. Existing Track A children must cite this parent the same way.
3. After either Track A child ships, mark the integration follow-through todo here (or cancel if folded into the open child).
4. Do not invent a second Metra project or TicketTracker ticket for this.

---

## Override authority (Amendment A)

Track A sequence is the default gate for Loom / Surveyor / Yarn Approve of downstream Ask work.

**Any override of the Track A sequence must be recorded in this parent plan by the operator before approval of downstream work.**

Required override record (edit this parent body):

- Date (UTC)
- What is being approved out of order (e.g. fix_batch P0b before stability reach bites)
- Why (one short paragraph)
- Operator identity (Stephen / display name)

Until that note exists here, tools must treat out-of-order Approve of fix_batch P0b (or any third plan that changes Ask concurrency / Ensure / `/api/meta` ahead of stability) as **blocked**. Do not invent a second override channel (chat-only, Loom receipt alone, or child-plan footnote).

---

## Yarn / Surveyor gate (after affirm)

- Cursor leaf under `%USERPROFILE%\.cursor\plans\` (`authority: cursor`).
- Upsert index stem `ops-desk-ask-sequencing`.
- Optionally Capture → Yarn idea titled "Ops Desk / Ask sequencing parent" linking both children.
- Point [`ops_ask_sidecar_stability`](ops_ask_sidecar_stability_79118c68.plan.md) and [`ops_ask_fix_batch`](ops_ask_fix_batch_a72e390d.plan.md) at this parent in their Related sections.

---

## Done when (coordination success)

- Both Track A children cite this parent and the locked sequence.
- Operator can open one plan and see what else is live on Ops/Ask without hunting 30 leaves.
- Override authority (Amendment A) is the only path around Track A order.

---

## Retire parent when (Amendment B)

Park / Complete this parent (Surveyor archive / Yarn park) when **all** of the following are true:

1. `ops_ask_sidecar_stability` shipped (or cancelled with operator note here)
2. `ops_ask_fix_batch` shipped (or cancelled with operator note here)
3. Integration follow-through completed **or** explicitly cancelled on this parent
4. No **active** child (pending todos) modifies Ops Ask concurrency, Ask Busy semantics, `/api/meta` schema, or Ask Ensure behavior

Retirement is the archival trigger for Surveyor/Yarn - not an automatic Loom action. After retire, a future plan that reopens those surfaces must either revive this parent or create a new sequencing parent and re-lock order.
