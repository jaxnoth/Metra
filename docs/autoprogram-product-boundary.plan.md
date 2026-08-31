---
name: AutoProgram product boundary
overview: "Product-boundary correction: AutoProgram as a first-class governed-execution domain, Metra-hosted with extractable module boundary. Pause feature work until M0–M2 complete. Do not move into Forge."
status: Approved with amendments (Bing 2026-08-31)
phase: boundary-correction
bingReviewed: true
m0Completed: 2026-08-31
m1Completed: 2026-08-31
todos:
  - id: m0-baseline
    content: "M0 — Baseline reconcile, freeze, git track separation, canonical status matrix, focused pack"
    status: completed
  - id: m0.5-commit
    content: "M0.5 — Commit Phase A baseline only; tag boundary-correction-start (rollback anchor before M2)"
    status: completed
  - id: m1-adr
    content: "M1 — Product ADR, dependency-direction ADR, completion-vs-acceptance scar, extraction triggers"
    status: completed
  - id: m2-module
    content: "M2 — AutoProgram module layout, adapters, contracts, isolation/extraction-readiness tests, façade"
    status: pending
  - id: gate-resume
    content: "Gate — M0 + M0.5 + M1 + M2 partial (isolation tests green) before Slice 3 branch runner"
    status: pending
  - id: m2-naming-review
    content: "Post-M2 — Execute Loom rename track (decision recorded 2026-08-31); separate from module extraction"
    status: pending
atlasStableId: null
synthesizedAt: null
relatedPlans:
  - path: C:\Users\admin.sswan\.cursor\plans\metra_auto-programming_loop_0e30e91c.plan.md
    role: execution-roadmap
  - path: C:\Projects\_meta\docs\routing-graph-phase5-review.plan.md
    role: separate-track
---

# AutoProgram product boundary correction

**Status:** Approved with amendments (Bing 2026-08-31)  
**Date:** 2026-08-31  
**Type:** Product / architecture (not a file cleanup)  
**Gate:** No AutoProgram **feature** work (Slice 3+) until **M0, M0.5, M1, and M2 partial** (module shell + adapter boundary + isolation tests) are complete. Full M2 before unattended or Slice 4+.

---

## 1. Executive decision

**Decision:** AutoProgram is a **first-class governed-execution domain**. It does **not** move into Forge. It remains **Metra-hosted temporarily** with an **explicit, extractable module boundary**.

**Portfolio product definitions (durable):**

| Product | Job |
|---------|-----|
| **Atlas** | Remembers — portfolio knowledge bus, StableIds, promoted knowledge |
| **Metra** | Coordinates — routing, context, decisions, operational surfaces, human authority |
| **Forge** | Generates — structured definitions → regenerable declarative artifacts |
| **Loom** (working name **AutoProgram** through M2) | Executes — Approved formal plans → governed queue → isolated mutation → review → operator acceptance |

**Why not Forge:** Forge’s authority model is **definition → disposable generated output**. AutoProgram’s authority model is **mutable execution state** (queue, journal, branches, review evidence, acceptance records). Merging them reduces Forge coherence without reducing Metra coupling.

**Why not sibling repo yet:** Extraction is premature until module contracts and adapter tests exist. Metra may host the CLI façade; AutoProgram must **own implementation internals**.

**Operator entry (stable):** `.\metra.ps1 autoprogram …` — unchanged through M0–M2.

---

## 2. Reconciled current-state inventory

Evidence gathered 2026-08-31 from repository inspection (not plan text alone).

### 2.1 Git and commit state

| Evidence | Finding |
|----------|---------|
| Branch | `main`, **ahead 2** of `origin/main` |
| Recent commits | `be87d8c` routing edges; `f6b6d7b` portfolio memory path — **not AutoProgram** |
| AutoProgram implementation | **`scripts/private/Autoprogram.ps1`** — **untracked** (not committed) |
| AutoProgram tests | **`tests/Metra.Autoprogram.Tests.ps1`** — **untracked** |
| Metra wiring | `metra.ps1`, `scripts/Metra.psd1`, `scripts/Metra.psm1` — **modified**, uncommitted |
| Mixed modified tracks (same working tree) | Routing (`Routing.ps1` +518 lines), Ask (`AskEngine.ps1`, `AskLane.ps1`, Cursor engine), Ops/Inspect, `Metra.Tests.ps1` |
| Separate track (untracked plan) | `docs/routing-graph-phase5-review.plan.md` |

**Uncertainty:** Whether the two commits ahead of origin include any AutoProgram work — **no**; they are routing/memory/Ask sidecar commits per `git log`.

### 2.2 Implementation inventory (AutoProgram)

| Artifact | Lines / size | Shipped to git? | Notes |
|----------|--------------|-----------------|-------|
| `scripts/private/Autoprogram.ps1` | ~1,087 lines | **No** (untracked) | Phase A scope only |
| `tests/Metra.Autoprogram.Tests.ps1` | ~300 lines | **No** (untracked) | **13/13 passing** (2026-08-31 run) |
| Storage default | `%LOCALAPPDATA%\Metra\autoprogram\` | Runtime | queue, journal, candidates, daily, locks |
| Formal roadmap plan | `.cursor/plans/metra_auto-programming_loop_0e30e91c.plan.md` | Cursor plan root | Slices 1–2 marked completed; Slice 3 pending |

### 2.3 Commands implemented (Phase A)

| Command | Implemented | Tested |
|---------|-------------|--------|
| `autoprogram status` | Yes | Indirect |
| `autoprogram show -Id` | Yes | Indirect |
| `autoprogram block -Id` | Yes | Yes |
| `autoprogram enqueue -CandidateId` | Yes | Yes |
| `autoprogram enqueue -FromPlan` | Yes | Yes |
| `autoprogram triage` | Yes | Yes (dry-run) |
| `autoprogram plans list/show/pending` | Yes | Yes (indexer) |
| `autoprogram daily` | Yes (stub) | Yes |

### 2.4 Not implemented (roadmap slices)

| Capability | Evidence |
|------------|----------|
| Branch runner (Slice 3) | No `runs/` orchestration, no clean-tree check, no implementer invocation |
| Review / inspect adapter (Slice 4) | No `completed` transition, no inspect loop wiring |
| Daily approve / pack-diff gate (Slice 5) | Stub intake only; no `daily approve` |
| Unattended `-UntilDailyGate` (Slice 6) | Not present |
| Plan synthesize (Slice 7) | Not present |
| Knowledge promotion (Slice 8) | Not present |

### 2.5 Direct Metra coupling (today — boundary violation for M2)

AutoProgram.ps1 calls Metra module internals directly (non-contract):

| Called symbol | Owner | M2 target |
|---------------|-------|-----------|
| `Get-MetraCaptureLedger` | Metra/Capture | `Invoke-AutoProgramCaptureAdapter` |
| `Get-MetraRoutingAmbiguity` | Metra/Routing | `Invoke-AutoProgramRoutingAdapter` |
| `Get-MetraInspectPlanRoots` | Metra/Inspect | `Invoke-AutoProgramPlanRootsAdapter` |
| `Write-MetraAtomicUtf8Text`, `Invoke-MetraWithNamedMutex`, `Get-MetraUtf8NoBomEncoding`, `Get-MetraProp`, `Get-MetraRoot` | Metra/Snapshot/Core | Shared util via narrow `AutoProgram.Storage` or duplicated thin helpers inside module |

**No** calls to Decision Registry, Atlas API, or Capture mutation — **good**, preserve in M2.

---

## 3. Canonical phase / slice status matrix

Reconciles **conversational “Phase 3”**, **formal plan slices**, **git**, and **tests**.

| Label | Meaning | Planned | Implemented | Tested | Git committed | Bing accepted |
|-------|---------|---------|-------------|--------|---------------|---------------|
| **Phase A** (plan) | Slices 1–2 only | Yes | **Yes** (untracked) | **13 Pester** | **No** | Architecture yes; merge **no** (mixed diff) |
| **Slice 1** State | Queue, journal, lock, enqueue, block | Yes | Yes | Yes | No | Partial (truncated pack) |
| **Slice 2** Triage | Plans index, dry-run, scoring, `-FromPlan` | Yes | Yes | Yes | No | Partial |
| **Slice 3** Branch runner | Clean tree, run dir, implementer | Yes | **No** | No | No | N/A |
| **Slice 4–8** | Per roadmap | Yes | No | No | No | N/A |
| **Conversational “Phase 3”** (operator) | Unclear — possibly “third initiative phase” or mixed diff review | — | **Misaligned** with Slice 3 | — | — | **Approve with changes**, not merge |
| **Routing Phase 5 review** | Separate Metra maturity track | Yes | **Partial** (in working tree) | `Metra.Tests.ps1` delta | Partial (1 commit) | Separate plan |
| **Ask/Cursor resilience** | Separate Metra maturity track | — | **Partial** (working tree) | `Metra.AskLane.Tests.ps1` | Partial | Separate from AutoProgram |
| **Boundary correction M0–M2** | This plan | Yes | **No** | No | No | Pending |

### Phase 3 / Slice 3 finding (canonical)

**Operator statement “Phase 3 is complete” is not supported by repository evidence for AutoProgram Slice 3 (branch runner).**

| Interpretation | Verdict |
|----------------|---------|
| Formal plan **Slice 3** (branch runner) | **Not implemented** — plan correctly shows `pending` |
| Formal plan **Phase A** (Slices 1–2) | **Implemented locally**, **not committed**, **13 tests pass** |
| Bing **“Phase 3 diff”** review | Refers to a **mixed working-tree changeset** (AutoProgram + Routing + Ask + Cursor + Ops), **not** completion of branch runner |
| Recommended canonical language | **“Phase A baseline complete (Slices 1–2, uncommitted); Slice 3 not started; boundary correction required before resume.”** |

This plan **supersedes** ambiguous “Phase 3 complete” wording until operator explicitly redefines phase numbers in the roadmap plan frontmatter.

---

## 4. Product responsibility matrix

| Concern | Atlas | Metra | Forge | AutoProgram |
|---------|-------|-------|-------|-------------|
| Portfolio memory / StableIds | **Owns** | Routes | — | Reads (future) |
| Registry / `ctx` / routing | — | **Owns** | — | Consumes |
| Capture inbox | — | **Owns** | — | Read-only intake |
| Decision Registry / Decisions.md | — | **Owns** | — | **Must not write** |
| Ask / Ops / Mobile surfaces | — | **Owns** | — | Consumes (health/blockers) |
| Inspect / verify engines | — | **Owns** | — | Orchestrates (Slice 4+) |
| Formal `.plan.md` (Approved) | Mirror optional | Indexes paths | Doc templates only | **Consumes** |
| Queue / journal / run state | Never | Host path | Never | **Owns authority** |
| Git branches / mutations | Never | Never | Deploy assets only | **Owns** (Slice 3+) |
| Machine `completed` | — | — | — | **Owns** |
| Operator `accepted` | — | **Human authority** | — | Records only |
| Brand/site generation | — | Routes | **Owns** | — |
| Notion runtime | — | — | — | **Never** |

---

## 5. Data and authority ownership matrix

| Data | Authority | Storage | Mutators |
|------|-----------|---------|----------|
| Queue item snapshot `AP-*.json` | AutoProgram | `%LOCALAPPDATA%\Metra\autoprogram\queue\` | AutoProgram state commands only |
| Journal `YYYY-MM-DD.jsonl` | AutoProgram | `…/journal\` | Append-only via AutoProgram |
| Candidate `CAND-*.json` | AutoProgram | `…/candidates\` | Triage only; never copied to queue folder |
| Run artifacts `runs/…` | AutoProgram | `…/runs\` | Runner (Slice 3+) |
| Daily intake `.md` | Collaboration doc | `…/daily\` | AutoProgram generates; **not executable** |
| Daily plan `.md` | Operator directives | `…/daily\` | Operator; parsed by approve (Slice 5) |
| Formal plan files | Operator + Bing | Project docs / `.cursor/plans` | **Not AutoProgram** |
| Capture ledger | Metra | `docs/ops-capture.local.json` | Capture CLI only |
| Routing graph | Metra | `%LOCALAPPDATA%\Metra\routing\` | Routing CLI only |
| Inspect reports | Metra | `%LOCALAPPDATA%\Metra\inspect\` | Inspect CLI only |

**Invariants (enforce in M2 tests):**

- `CAND-*` IDs never appear under `queue/`.
- `AP-*` IDs never appear under `candidates/`.
- `daily/*-intake.md` is never parsed for execution directives.

---

## 6. Dependency-direction rules

**ADR status (Bing 2026-08-31):** These rules are the highest-value architectural statement in this document. M1 promotes them to a durable [`Decisions.md`](Decisions.md) entry alongside the completion-vs-acceptance scar. Code must follow **AutoProgram → Adapters → Metra public surfaces** — never AutoProgram → `scripts/private/*.ps1`.

```text
Allowed:
  Operator → metra.ps1 autoprogram → AutoProgram module
  AutoProgram → Metra.Adapters (narrow) → Metra public surfaces
  AutoProgram → local storage (queue/journal/runs)

Forbidden:
  AutoProgram → scripts/private/Routing.ps1 (direct)
  AutoProgram → scripts/private/Capture.ps1 mutation paths
  AutoProgram → Decision Registry / Decisions.md / Atlas put
  AutoProgram → Forge module
  Forge → AutoProgram queue
  Atlas → AutoProgram enqueue
  Plan synthesize → queue (without Approved + explicit enqueue)
  Machine completed → accepted (without operator gate)
```

**Fail closed:** Any adapter contract validation failure aborts the command; no silent fallback.

---

## 7. Proposed module / file structure (M2 target)

Metra checkout (`C:\Projects\_meta`):

```text
modules/
  AutoProgram/
    AutoProgram.psd1              # Module manifest; versioned
    README.md                     # Domain boundary (short)
    Public/
      Invoke-AutoProgramCommand.ps1
    Private/
      State/                      # queue, journal, lock, transitions
      Triage/                     # scoring, eligibility, candidates
      Plans/                      # formal plan indexer (read-only)
      Daily/                      # intake stub; approve later
      Storage/                    # atomic IO wrappers (may wrap Metra util)
    Adapters/
      Metra.Capture.Adapter.ps1
      Metra.Routing.Adapter.ps1
      Metra.Plans.Adapter.ps1
      Metra.Inspect.Adapter.ps1   # stub until Slice 4
      Metra.Verify.Adapter.ps1    # stub until Slice 4
    Contracts/
      v1/
        routing-context.request.schema.json
        routing-context.result.schema.json
        plan-record.schema.json
        triage-candidate.schema.json
        queue-item.schema.json
        journal-entry.schema.json
        inspect-request.schema.json
        inspect-result.schema.json
        verify-request.schema.json
        verify-result.schema.json
        acceptance-record.schema.json
        blocker-report.schema.json

scripts/
  private/
    Autoprogram.ps1               # DEPRECATED shim → Import-Module + delegate (one release)
  Metra.psm1                      # dot-sources adapter registration only

metra.ps1                         # autoprogram → Invoke-AutoProgramCommand (façade)

tests/
  Metra.Autoprogram.Tests.ps1     # integration via metra.ps1 façade
  AutoProgram/                    # unit + contract tests (new)
    AutoProgram.Boundary.Tests.ps1
    AutoProgram.Contracts.Tests.ps1
    AutoProgram.ExtractionReadiness.Tests.ps1
```

**What moves in M2:** Body of current `Autoprogram.ps1` → `modules/AutoProgram/Private/**` (split by concern).  
**What stays Metra-owned:** Routing, Capture, Inspect, Verify, Ops, registry, `metra.ps1` dispatch.  
**What does not move:** Nothing to Forge.

---

## 8. Interface and contract definitions

Version **v1** JSON schemas under `Contracts/v1/`. PowerShell adapters serialize/deserialize; schemas are source of truth for future sibling-repo extraction.

### 8.1 Routing and context

**Request** (`routing-context.request.schema.json`):

```json
{
  "schemaVersion": 1,
  "query": "Metra autoprogram harness",
  "planPath": "C:\\Projects\\_meta\\docs\\example.plan.md"
}
```

**Result** (`routing-context.result.schema.json`):

```json
{
  "schemaVersion": 1,
  "registryName": "Metra",
  "root": "C:\\Projects\\_meta",
  "routingConfidence": 0.99,
  "routingEvidence": "plan-path-under-metra-root",
  "minimumConfidence": 0.85,
  "eligible": true
}
```

Adapter: `Get-AutoProgramRoutingContext -Request <path or object>` — **only** Metra routing entry point AutoProgram may use.

### 8.2 Plan intake (read-only)

**Plan record** (`plan-record.schema.json`): path, name, overview, `status` (enum), `bingReviewed`, `approved`, todos[], verifyCommands[], doneWhen[].

Frontmatter authority (M2 implementation — roadmap hardening):

```yaml
status: approved          # canonical
bingReviewed: true
```

Body `**Status:**` line becomes presentation-only when frontmatter present.

### 8.3 Inspect (Slice 4 — stub in M2)

**Request:** project name, base ref, plan path, allowed paths.  
**Result:** goalMet, severity counts, report path, engine model, stale flag.

M2: adapter returns `not-implemented` unless `-WhatIf`; contract tests validate shape only.

### 8.4 Verify (Slice 4 — stub in M2)

**Request:** verifyCommands[], project root.  
**Result:** passed, failedCommand, exitCode, log excerpt path.

### 8.5 Operator approval and acceptance

**Acceptance record** (`acceptance-record.schema.json`): itemId, operator, acceptedAt, packDiffPath, manualTestComplete — **written only by operator gate** (Slice 5); M2 defines schema + validation only.

### 8.6 Health and blocker reporting

**Blocker report** (`blocker-report.schema.json`): tier (`stop` | `auto-recover` | `daily-gate`), class, message, recoveryAttempts[].

---

## 9. Backward-compatibility requirements

| Surface | Requirement |
|---------|-------------|
| CLI | `.\metra.ps1 autoprogram <subcommand>` unchanged through M2 |
| Storage path | `%LOCALAPPDATA%\Metra\autoprogram\` unchanged unless migration tool provided |
| IDs | `AP-YYYYMMDD-####`, `CAND-YYYYMMDD-####` unchanged |
| Journal format | JSONL append-only lines unchanged |
| Queue item schema | `schemaVersion: 1` — additive fields only in v1.x |
| Phase A transitions | Active subset remains `@new→queued`, `queued→blocked` until Slice 3+ enables more |
| Export surface | `Invoke-MetraAutoprogramCommand` remains as compatibility alias → `Invoke-AutoProgramCommand` |

---

## 10. Test strategy

### 10.1 Existing (baseline)

`tests/Metra.Autoprogram.Tests.ps1` — **13 tests**, Phase A behavior, path/id guards.

### 10.2 M0 tests

- Git track hygiene script or Pester: fails if AutoProgram + Routing + Ask change in same staged set without `TRACK:` trailer (optional lightweight check).

### 10.3 M1 tests

- Documentation tests: Decisions.md contains ADR id; product definitions string match.

### 10.4 M2 tests (required)

| Suite | Purpose |
|-------|---------|
| `AutoProgram.Boundary.Tests.ps1` | No dot-source of `scripts/private/Routing.ps1` etc.; module loads in isolation |
| `AutoProgram.Contracts.Tests.ps1` | JSON schema validation for v1 contracts |
| `AutoProgram.ExtractionReadiness.Tests.ps1` | Façade delegation; storage paths; ID invariants; full status enum; **isolation gate** (below) |
| `Metra.Autoprogram.Tests.ps1` | Regression — all 13+ tests pass via `metra.ps1` path |

### 10.5 Extraction readiness gate (Bing amendment)

Measurable criterion — not diagram-only:

```text
Import-Module modules/AutoProgram/AutoProgram.psd1   # NOT Metra.psm1
Invoke-Pester -Path tests/AutoProgram/                # contract, state, transition, storage

PASS = extractable boundary proven
FAIL = still coupled to Metra implementation
```

M2 partial acceptance requires this gate **green** for: contract validation, state/journal writes, transition enforcement, storage/ID guards. Integration tests via `Metra.psm1` remain required separately but do not satisfy the isolation gate alone.

**Bing findings mapped to M2 tests:**

| Finding | Test |
|---------|------|
| Full status map | `Get-AutoProgramStatusCatalog` returns all lifecycle states; Phase A activates subset |
| Frontmatter approval | Plan with `status: approved` vs body-only |
| Path normalization | `AP-…/`, `AP-…\`, `AP-….json`, `..` rejected |
| Empty contract on enqueue | Rejects missing doneWhen/verifyCommands |
| Intake not executable | Daily stub has no directive parser |

---

## 11. Implementation slices (M0–M2)

### M0 — Baseline and freeze

**Scope:**

1. **Freeze** AutoProgram feature work (Slices 3–8, synthesis, unattended).
2. Publish **canonical status matrix** (Section 3) into roadmap plan frontmatter note.
3. **Commit track separation** (minimum):
   - **Track A:** AutoProgram Phase A (`Autoprogram.ps1`, tests, metra wiring)
   - **Track B:** Routing Phase 5 review
   - **Track C:** Ask/Cursor resilience
   - **Track D:** Ops/Inspect incidental
4. Generate **focused inspect pack** (`Autoprogram.ps1` + tests only) for Bing.
5. Reconcile operator phase vocabulary in chat → **Phase A baseline**, not Slice 3.

**Acceptance criteria:**

- [x] Canonical matrix agreed by operator (no “Slice 3 complete” without branch runner code) — 2026-08-31
- [x] Track separation documented — [autoprogram-m0-tracks.md](autoprogram-m0-tracks.md); Track A ready for M0.5 (zero Routing hunks)
- [x] `Invoke-Pester tests/Metra.Autoprogram.Tests.ps1` — **13/13 pass** (M0 run)
- [x] Focused packs: `%LOCALAPPDATA%\Metra\inspect\pack-plan.md` (roadmap) + `autoprogram-phase-a-pack.md` (Track A only)

**Rollback:** Revert commits per track; untracked AP files remain in working tree.

---

### M0.5 — Commit Phase A baseline (rollback anchor)

**Scope (Bing amendment — before M2 module extraction):**

1. Commit **Track A only**: `Autoprogram.ps1`, `Metra.Autoprogram.Tests.ps1`, `metra.ps1` / `Metra.psd1` / `Metra.psm1` wiring — **zero** Routing/Ask/Ops hunks in the same commit.
2. Message: `feat(autoprogram): Phase A baseline (Slices 1–2 state + triage)`.
3. Tag: `boundary-correction-start` (annotated tag optional; lightweight tag OK).
4. Confirm 13/13 Pester green on committed tree.

**Why:** Today’s state — implemented, tested, **uncommitted** — is where refactors get messy. M0.5 is the rollback anchor before M2 moves files.

**Acceptance criteria:**

- [x] Single commit contains only AutoProgram Phase A artifacts — `7d90ebe` (2026-08-31)
- [x] Tag `boundary-correction-start` points at that commit
- [x] Pester green on clean checkout of that commit — **13/13**
- [x] Mixed tracks (Routing, Ask, Cursor) remain uncommitted or on separate commits

**Rollback:** `git revert` the baseline commit; tag deleted or marked superseded.

---

### M1 — Product and authority boundary (ADR)

**Scope:**

1. Add ADR to [`docs/Decisions.md`](Decisions.md): **AutoProgram governed-execution domain** (four-product model, Forge exclusion, extraction triggers).
2. Add ADR: **Dependency direction** — AutoProgram → Adapters → Metra; forbidden direct private imports (Section 6 verbatim policy).
3. Add portfolio scar: **Completion is evidence. Acceptance is authority.** — applies to AutoProgram, TicketWatch, Atlas promotion, future agentic surfaces; machine `completed` ≠ operator `accepted`.
4. Update [`docs/portfolio-memory-path.md`](portfolio-memory-path.md) one-line cheat sheet (optional cross-link).
5. Update roadmap plan [`.cursor/plans/metra_auto-programming_loop_0e30e91c.plan.md`](../../Users/admin.sswan/.cursor/plans/metra_auto-programming_loop_0e30e91c.plan.md): link boundary plan; clarify Phase A vs Slice 3.
6. Document **non-goals:** move to Forge; sibling repo now; autonomous accept/merge/push; Notion queue backend.
7. Document **extraction triggers** (Section 15).

**Acceptance criteria:**

- [x] Decisions.md: Loom domain ADR + dependency-direction ADR + completion-vs-acceptance scar + Loom naming (2026-08-31)
- [x] Product definitions match Section 1 in domain ADR (Loom executes; AutoProgram working name through M2)
- [x] Roadmap plan links boundary plan, tracks, non-goals, extraction triggers
- [x] Decision 1 accepted: Phase A committed; Slice 3 not started
- [x] `portfolio-memory-path.md` cross-link added

**Rollback:** Revert Decisions.md ADR entry; plans remain draft.

---

### M2 — Enforceable module and contract boundary

**M2 partial (minimum before Slice 3):** Module manifest, adapter layer, v1 contracts, isolation/extraction-readiness tests green **without** `Import-Module Metra.psm1`. Domain code moved enough to prove boundary; shim façade delegates.

**M2 complete (before Slice 4+ / unattended):** Full Private/ split, all adapters wired, regression suite, focused Bing pack clean.

**Scope:**

1. Create `modules/AutoProgram/` layout (Section 7).
2. Move implementation from `scripts/private/Autoprogram.ps1` into module Private/ — **no behavior change** intended.
3. Add `Adapters/` — Metra-facing only; remove direct `Get-MetraRoutingAmbiguity` calls from domain code.
4. Add `Contracts/v1/*.schema.json` + validation tests.
5. Implement `Get-AutoProgramStatusCatalog` (full enum) vs `Get-AutoProgramActiveTransitions` (Phase A subset).
6. Implement frontmatter `status:` / `bingReviewed:` parsing (body fallback).
7. Thin `Invoke-MetraAutoprogramCommand` → delegates to `Invoke-AutoProgramCommand`.
8. Keep `metra.ps1 autoprogram` as façade.

**Acceptance criteria:**

- [ ] `Import-Module modules/AutoProgram/AutoProgram.psd1` loads without Metra private dot-sources
- [ ] Boundary Pester suite passes (no forbidden imports)
- [ ] Contract Pester suite passes
- [ ] `Metra.Autoprogram.Tests.ps1` ≥13 pass unchanged behavior
- [ ] **Isolation gate:** `Import-Module AutoProgram.psd1` + `tests/AutoProgram/` pass **without** Metra.psm1
- [ ] Extraction-readiness tests pass (Section 10.5)
- [ ] `scripts/private/Autoprogram.ps1` is shim only (≤30 lines) or deleted with deprecation note
- [ ] Focused Bing pack of module + tests clean
- [ ] **M2 partial** checked before Slice 3; **M2 complete** checked before Slice 4+
- [ ] **Naming review** scheduled (Section 17) — decision recorded; no rename required to pass M2

**Rollback:** Restore monolithic `Autoprogram.ps1`; remove module folder; keep adapter interfaces documented for retry.

---

## 12. Rollback strategy (all slices)

| Slice | Rollback |
|-------|----------|
| M0 | Reset staged commits per track; keep local AP files |
| M0.5 | Revert baseline commit or reset tag; return to untracked if needed |
| M1 | Revert Decisions.md + plan links |
| M2 | Revert to `boundary-correction-start` tag; tests prove Phase A still passes |

**Data rollback:** Queue/journal under `%LOCALAPPDATA%\Metra\autoprogram\` is forward-compatible; no migration required for M2 if schemas unchanged.

---

## 13. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| “Bounded product” stays diagram-only | M2 required before resume; boundary Pester |
| Premature sibling repo | Explicit triggers; module first |
| Phase vocabulary drift | Canonical matrix in two plans + ADR |
| Mixed diffs recur | M0 track-separated commits; pack-only review |
| Adapter sprawl | v1 contracts frozen; one adapter file per Metra concern |
| Forge scope creep | ADR non-goals; Forge README unchanged |
| Over-extraction breaks CLI | Façade + compatibility alias through M2+ |

---

## 14. Risks of immediate boundary work

| Risk | Mitigation |
|------|------------|
| Migration churn without feature value | M2 is refactor-only; no Slice 3 code |
| Test breakage | 13-test baseline must stay green |
| Dual maintenance shim + module | Time-box shim to one release |

---

## 15. Objective criteria for future sibling-repository extraction

Extract `C:\Projects\AutoProgram\` when **any two** are true:

1. Non-Metra consumer needs governed execution (e.g. standalone agent host).
2. Module + tests exceed **~3,000 LOC** or **4+ adapter contracts** with stable v1 schemas.
3. Release cadence must diverge (execution vs Metra 0.1.x ops releases).
4. Second machine runs queue worker without full portfolio registry checkout.
5. Operator explicitly opts in after M2 boundary proven for **≥30 days** and Slice 5 daily gate shipped.
6. **Isolation gate passes** (Section 10.5): AutoProgram module tests green without importing `Metra.psm1`.

Until then: **Metra-hosted module**, not separate repo.

---

## 16. Explicit resume gate

**AutoProgram feature development (Slice 3 branch runner and beyond) MUST NOT resume until:**

1. **M0** complete (freeze, track separation, focused pack).
2. **M0.5** complete (Phase A baseline committed; tag `boundary-correction-start`).
3. **M1** complete (Decisions.md ADRs including dependency direction + completion vs acceptance).
4. **M2 partial** complete (module + adapters + **isolation gate** green — Section 10.5).
5. This plan **Approved** (Bing 2026-08-31 — done).
6. Operator explicitly authorizes Slice 3 in chat or ticket.

**Slice 4+ / unattended:** requires **M2 complete** in addition to the above.

**Permitted before Slice 3 gate:** M0–M2 implementation, Pester, focused packs, ADR docs, git track separation.

**Not permitted before gate:** Branch runner, implementer agent, inspect adapter execution, daily approve, unattended loop, plan synthesize, Atlas promotion automation.

---

## Non-goals

- Moving AutoProgram into Forge
- Creating sibling git repository in M0–M2
- Changing storage root without migration plan
- Merging mixed AutoProgram + Routing + Ask commits
- Autonomous merge, push, ticket post, OCC promote, Decision Registry writes
- Notion as queue or runtime authority
- Resuming Slice 3 automatically after drafting this plan

---

## Operator decisions still required

| # | Decision | Options |
|---|----------|---------|
| 1 | Accept canonical finding: **Slice 3 not complete**; Phase A baseline only | **Accepted** (Bing + operator M0 2026-08-31) |
| 2 | Approve M0 → M0.5 → M1 → M2 partial before Slice 3 | **Accepted** (operator execute M0 2026-08-31) |
| 3 | Minimum routing confidence `0.85` — defer to config until pre-Phase C? | Defer (recommended) / promote to settings now |
| 4 | Module path `modules/AutoProgram/` vs `scripts/Autoprogram/` | Recommend `modules/AutoProgram/` |
| 5 | After M2 gate: authorize Slice 3 branch runner | Explicit operator go |
| 6 | Product name | **Loom** chosen (operator 2026-08-31); **AutoProgram** working name through M2; rename track at M2 (Section 17) |

---

## Related artifacts

| Artifact | Role |
|----------|------|
| [metra_auto-programming_loop plan](file:///C:/Users/admin.sswan/.cursor/plans/metra_auto-programming_loop_0e30e91c.plan.md) | Execution roadmap (Slices 1–8) |
| [routing-graph-phase5-review.plan.md](routing-graph-phase5-review.plan.md) | Separate Metra track — not AutoProgram |
| [portfolio-memory-path.md](portfolio-memory-path.md) | Atlas / Metra memory layers |

---

## Bing review (2026-08-31)

**Verdict:** Approved with minor refinements.

**Accepted amendments folded into this revision:**

- **M0.5** — commit Phase A baseline; tag `boundary-correction-start` before M2 extraction.
- **Isolation gate** — AutoProgram tests pass without `Import-Module Metra.psm1` (Section 10.5).
- **ADR promotion** — dependency-direction rules (Section 6) + **Completion is evidence. Acceptance is authority.** (M1).
- **Resume gate** — M0 + M0.5 + M1 + **M2 partial** before Slice 3; not full M2 alone as sole blocker for M0.

**Bing assessment:** AutoProgram is important enough to deserve a **boundary before a repository**. Forge argument accepted. Immediate risk is mixed review surface (AP + Routing + Ask + Ops + Cursor), not product identity.

**Naming:** **Loom** chosen as product name (operator 2026-08-31; Bing favored Loom over Assembly). Do **not** block M0–M2 on rename. Keep **AutoProgram** (module, CLI, `AP-*`/`CAND-*` IDs, plans, tests) as working name through M2; execute rename on a separate track after M2 isolation gate (Section 17). Rejected: **Foundry** (Forge confusion), **Conductor** (overlaps Metra), **Assembly** (runner-up).

---

## 17. Product naming

**Chosen product name:** **Loom** (operator 2026-08-31).

**Portfolio line:** Atlas remembers · Metra coordinates · Forge generates · **Loom** executes.

**Working name through M2:** **AutoProgram** — stable for IDs (`AP-*`, `CAND-*`), Pester, plans, `metra.ps1 autoprogram`, module path `modules/AutoProgram/`. No CLI, commit, or ID-prefix rename during M0–M2.

**Why execution is deferred:** Architecture and boundaries are expensive to change; identifier migration is cheap *after* the module boundary is proven. Stopping M0–M2 for rename would fix the wrong problem first.

**Why Loom:** The domain is governed delivery (queue, review, acceptance), not “automatic programming.” Loom weaves plans, context, implementation, review, and approval into outcomes; it reads as a **product** next to Atlas / Metra / Forge. **Assembly** was runner-up (literal pipeline fit; weaker portfolio identity and .NET “assembly” confusion).

| Candidate | Outcome |
|-----------|---------|
| **Loom** | **Chosen** — portfolio-style; role over technique |
| **Assembly** | Runner-up |
| **AutoProgram** | Working name through M2; legacy alias candidate post-rename |
| **Conductor** | Rejected — overlaps Metra “coordinates” |
| **Foundry** | Rejected — too close to Forge |

**M2 rename track (after isolation gate green — separate from module extraction commit):**

1. Module/product docs adopt **Loom**; optional `metra.ps1 loom` façade with `autoprogram` deprecated alias period.
2. ID prefix policy: **`AP-*` / `CAND-*` may stay** for backward compatibility (journal paths unchanged unless migrated).
3. Decisions.md and registry updated when rename lands (scar entry added 2026-08-31 for name choice).

**Non-goals now:** Renaming CLI, retagging commits, or changing queue ID format during M0–M2.

---

## Next steps (post-M1)

1. ~~**M0**~~ — Complete 2026-08-31.
2. ~~**M0.5**~~ — Complete 2026-08-31 (`7d90ebe`, tag `boundary-correction-start`).
3. ~~**M1**~~ — Complete 2026-08-31 (ADRs, plans, portfolio-memory-path).
4. **M2 partial** — module + adapters + isolation gate.
5. Operator gate → resume **Slice 3** (branch runner).

**Recommended next slice:** **M2 partial**.
