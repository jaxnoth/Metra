# Agentic maturity model

Shared reference for scoring **workflows** (not people, not models). Use it when designing current behavior, planning future development, or judging whether an agentic design is complete relative to its target.

This is a **workflow governance** model. It asks how complete the system around the LLM is (routing, context, isolation, validation, write authority) - not how autonomous the model sounds.

**Completeness** here means: the workflow reliably reaches its **declared target level** with the evidence and gates that level requires. Higher is not always better. Maxing every workflow to L6 is usually wrong.

Related: [Decisions.md](Decisions.md) (portfolio policy), [Context-Routing.md](Context-Routing.md) (route-first harness), [Integrations.md](Integrations.md) (engines and MCP), gitignored `Future-Development.local.md` (parking lot).

---

## Levels

| Level | Name | Definition | Capability or control |
|-------|------|------------|------------------------|
| **L1** | Basic | Prompt in, answer out. No tools, no routing policy, no retry contract. | Capability |
| **L2** | Router | Triage cost/latency/difficulty (strong model for hard, cheap for easy) **or** institutional route to one project/home before work. | Capability |
| **L3** | Tool calling | Real tools (CLI, MCP, APIs) with grounded results. Answers cite evidence from tools, not invent. | Capability |
| **L4** | Multi-agent | A manager (or orchestrator) delegates to specialists and merges results under an explicit merge policy. | Capability |
| **L5** | Autonomous check | Generate, self-check against a validator, retry until valid or fail closed with a clear stop. | Control loop |
| **L6** | Loop engineering | LLM + harness + orchestration are one workflow. The agent owns the loop: plan, call model, use tools, reflect - and only returns when the goal criteria are met (or a hard stop fires). | Control loop |

### Capability vs control (do not collapse)

| Capability (L1-L4) | Control loop (L5-L6) |
|--------------------|----------------------|
| Router / institutional route | Validator |
| Tool calling | Retry loop |
| Specialists / delegation | Goal loop + stop conditions |

Tool calling, multi-agent fan-out, long context, and deep reasoning are **not** autonomy. Without validators, retry bounds, and fail-closed stops, do not grant L5/L6.

### Reading the ladder

- **L1-L4** are capability layers. You can have tools (L3) without a good router (L2).
- **L5-L6** are control loops. Long context or many tools does not make a workflow L5/L6.
- **Institutional routing** (Metra `routing` / sticky primary / ticket-ops vs investigate) counts as **L2** even when model choice is fixed - the "router" is the portfolio map, not only a model picker. Perfect work in the wrong repo is still a failure.
- **Durable writes** (tickets, commits, prod mutations) stay operator-gated unless a workflow explicitly documents unsupervised authority. Loop maturity does not override the professional sink or Propose-Confirm-Apply. An L6 workflow may still declare Ceiling L3 for writes.

---

## Scoring rules

Score the **workflow**, end-to-end, as operators actually run it.

| Field | Meaning |
|-------|---------|
| **Current** | Highest level the workflow **reliably** achieves today (not the best happy path once). |
| **Target** | Intended level for this workflow. Declare it; do not assume L6. |
| **Gap** | Missing evidence or behavior between Current and Target (ordered, concrete). |
| **Completeness** | `complete` when Current >= Target **and** every required gate for Target is present; else `incomplete`. |
| **Ceiling** | Optional hard stop below L6 (governance, answer-only desk, human approval). |
| **Ceiling reason** | Why the ceiling exists: `policy` / `safety` / `compliance` / `cost` / `technical` / `none`. Future operators should not guess. |
| **Evidence quality** | How strong the tool/grounding signal is for Current (see below). Does not create L3a/L3b levels. |
| **On hard stop** | For Target L5/L6: what failed, where evidence lives, next operator action. Required for fail-closed to be operational. |

### Evidence quality (annotation, not a new level)

L3 requires grounded results. Tool **available** is not the same as tool **trusted**. Annotate Evidence quality on the scorecard:

| Quality | Meaning | Example |
|---------|---------|---------|
| **weak** | Single signal, stale cache, or unverified claim from one API | One status bit says "healthy" |
| **adequate** | Named live tool result used in the answer; honest when absent | `brief`, one `Get-*-Health`, catalog filter |
| **authoritative** | Multiple independent signals or a machine validator agree | PE process + libcurl + TranDb counts; `verify` PASS |

Do not invent L3a/L3b. Raise quality inside L3 (or as an L5 validator) instead of minting sub-levels.

### Required gates by level

A workflow may **claim** a level only when all gates for that level (and below) hold.

| Level | Must have |
|-------|-----------|
| L1 | Single-turn Q&A path; no false claim of tools or live systems. |
| L2 | Explicit route or model/cost triage **before** deep work; wrong-home is treated as failure. |
| L3 | Named tools; tool results used in the answer; honesty when a tool/server is absent. |
| L4 | Specialist roles + merge/conflict policy; no unbounded fan-out. |
| L5 | Machine-checkable success criteria; retry bound; **fail closed** (stop + report failure - do not shrug and return success). |
| L6 | Documented loop (plan -> act -> reflect); stop conditions; harness owns policy (route, root isolation, write gates); returns only when goal criteria met or hard stop; **recovery path** on hard stop (below). |

### Fail-closed and recovery (L5/L6)

Without fail-closed behavior, do not grant L5. Generate -> validate -> shrug -> return anyway is not L5.

When a hard stop fires (retry exhausted, validator fail, missing Live evidence, ceiling hit), the workflow should surface:

1. **What failed** - criterion or gate that did not pass
2. **Where evidence is** - command output, log path, ticket note, checklist phase
3. **Next operator action** - one concrete move (confirm Clear, open Host apply, ask for mnemonic, re-run phase B)

### Forms of loops (by exit)

Control loops are often taught by how they **start**. Score them by how they **stop**. This vocabulary subtypes L5/L6 exits - it does **not** add levels.

**Rule:** pick the loop by its exit, not its trigger. Starting on a timer when you meant "until the check passes" is the common mix-up (`/loop` vs `/goal` style).

| Form | Closes on | What it is | Metra-shaped example |
|------|-----------|------------|----------------------|
| **Turn-based** | The operator | One cycle (read/edit/test/hand back); waits for the next human prompt | Default Cursor chat; sticky primary; you review the diff |
| **Goal-based** | A judge / check | After each cycle, a validator says yes/no; retry until done or fail closed | L5: `verify` PASS, tests green, health + TranDb after Clear; done-when checklist |
| **Time-based** | The clock | Wake, work, sleep until the next schedule; exit is elapsed time, not evidence | Cursor `/loop`; Ops snapshot refresh cadence - **watch**, do not claim "finished" |
| **Proactive** | Nothing (re-arms) | External event fires work while unattended; may spawn specialists, then wait for the next event | Thin event bus / unattended CI-fix ideas - **high ceiling**; refuse unsupervised prod writes |

How this maps to maturity:

- Turn-based alone is normal operator chat - often L3 capability with a human ceiling, not L5.
- Goal-based is the default shape for claiming **L5** (judge = machine-checkable criteria).
- Time-based is a trigger/schedule pattern - useful for polling; do not grant L5 because a timer fired.
- Proactive is closest to unattended L6 theater risk - require explicit Ceiling reason (`safety` / `policy`) and durable-write gates; Metra Future-Development keeps thin event bus cold until allowlisted.

Starting a loop is easy. Teaching the stop is the product scar - same reason On hard stop and fail-closed exist.

### Anti-patterns (do not inflate the score)

- Calling it L6 because the chat was long or the agent "thought hard."
- Calling it L4 because two tools ran in one turn (that is still L3).
- Calling it L5 because a human skimmed the output (human review is a ceiling, not a validator).
- Claiming live Orion/iSupport/MCP when the binding is absent.
- Unsupervised ticket `post` / prod change dressed as "autonomous completion."
- Treating "tool returned 200" as authoritative when the playbook needs independent signals.
- Calling it goal-based (L5) when the exit was only a timer (time-based) or "I looked at it" (turn-based human skim).
- Calling proactive unattended loops "complete" without a write ceiling and allowlisted actions.

---

## Scorecard template

Copy per workflow (project playbook, Future-Development bite, or plan):

```markdown
### Workflow: <name>

| Field | Value |
|-------|-------|
| Current | L? |
| Target | L? |
| Ceiling | L? or none |
| Ceiling reason | policy / safety / compliance / cost / technical / none |
| Completeness | complete / incomplete |
| Evidence quality | weak / adequate / authoritative |
| Evidence (current) | <commands, docs, tests, runbook steps> |
| On hard stop | what failed; where evidence; next operator action (L5/L6 targets) |
| Loop form (optional) | turn-based / goal-based / time-based / proactive - pick by exit |
| Gaps to target | 1. ... 2. ... |
| Next bite | <one concrete change> |
```

Agents assessing completeness should fill this card (or equivalent) before declaring a design "done." Prefer gap lists over percentages. Do not invent a portfolio-wide maturity percentage for the Ops board.

---

## Portfolio scorecard register

Filled **2026-08-06**. Loop-form annotations added same day (TikTok glean). Revisit when a workflow's tools, gates, or ceiling change. Summary first; detail below. Not an Ops health feed.

| Workflow | Current | Target | Completeness | Ceiling | Ceiling reason |
|----------|---------|--------|--------------|---------|----------------|
| Plain chat Q&A (no repo) | L1 | L1 | complete | none | none |
| Metra Ops Ask (answer-only) | L3 | L3 | complete | L3 | policy |
| Metra route-first coding session | L3 | L6 | incomplete | L3 (writes) | policy |
| Cursor Task subagents | L4 | L4 | complete | merge-to-primary | policy |
| `metra.ps1 verify` / Pester | L5 | L5 | complete | gate-only | technical |
| TicketTracker ticket-ops | L3 | L3 | complete | L3 | policy |
| Metra ticket watch intake | L3 | L3 | complete | L3 (writes) | policy |
| Ticket + one technical investigate | L3 | L5 | incomplete | L3 (writes) | policy |
| Jitterbit stuck-ops | L3 | L5 | incomplete | L3 (Clear/PE) | safety |
| Jitterbit agent go-live | L3 | L5 | incomplete | phase-stop | safety |
| Colleague stuck session / in-use | L3 | L5 | incomplete | L3 (Live kill) | safety |

### Workflow: Plain chat Q&A (no repo)

| Field | Value |
|-------|-------|
| Current | L1 |
| Target | L1 |
| Ceiling | none |
| Ceiling reason | none |
| Completeness | complete |
| Evidence quality | weak (no tools by design) |
| Loop form | turn-based |
| Evidence (current) | Single-turn answer path; no portfolio tools required |
| On hard stop | n/a at L1 |
| Gaps to target | none |
| Next bite | none - leave as L1 |

### Workflow: Metra Ops Ask (answer-only)

| Field | Value |
|-------|-------|
| Current | L3 |
| Target | L3 |
| Ceiling | L3 - HTML Ops is answer-only; Host owns Propose-Confirm-Apply disk writes |
| Ceiling reason | policy |
| Completeness | complete |
| Evidence quality | adequate (routing + home retrieval; not multi-signal health) |
| Loop form | turn-based |
| Evidence (current) | Route-first Ask engine (`engines/cursor`, Decisions 2026-08-01); Classify/routing before answer; desk retrieves from existing homes; honesty when engine/bindings absent; no browser apply |
| On hard stop | Engine/bindings absent: say so; do not invent live systems; next: open Cursor or CLI for builds |
| Gaps to target | none for L3. Optional hardening (not a level gap): Ask secrets scrub (Future-Development parked) |
| Next bite | Ask polish / Ollama when activated - stay at Target L3 unless answer-only ceiling moves |

### Workflow: Metra route-first coding session

| Field | Value |
|-------|-------|
| Current | L3 |
| Target | L6 |
| Ceiling | L3 for tickets/commits/prod mutations unless operator asks; Host apply for Ops proposals |
| Ceiling reason | policy |
| Completeness | incomplete |
| Evidence quality | adequate (CLI/MCP when used); authoritative when `verify`/tests gate the session |
| Loop form | turn-based today; target goal-based (judge = done-when + verify/tests) |
| Evidence (current) | Always-on routing + root isolation + professional sink; Cursor agent plan/tool/reflect in practice; project CLI/MCP when bound. Peak sessions reach L5/L6 when `verify`/tests/`done-when` are used - not the reliable floor |
| On hard stop | State which done-when failed; cite test/`verify` output or file path; next: fix or ask operator - do not claim complete |
| Gaps to target | 1. Default machine-checkable done-when per task type (not only operator skim). 2. Retry bound + fail-closed when checks fail. 3. Treat mid-loop clarifying questions as hard stops, not silent incomplete returns. 4. Standard recovery triplet on every hard stop |
| Next bite | For coding bites: state done-when + run `.\metra.ps1 verify` (or project tests) before declaring complete |

### Workflow: Cursor Task subagents

| Field | Value |
|-------|-------|
| Current | L4 |
| Target | L4 |
| Ceiling | Merge results back to sticky primary; no unbounded fan-out |
| Ceiling reason | policy |
| Completeness | complete |
| Evidence quality | adequate (specialist tool results merged by parent) |
| Evidence (current) | Task tool specialists (explore, shell, bugbot, security-review, etc.); parent merges; Metra sticky-primary / one technical hop policy |
| On hard stop | Specialist failed or empty: parent reports gap; stay on primary; next: retry one specialist or operator path - no parallel multi-repo sprawl |
| Gaps to target | none when merge-back is followed |
| Next bite | none - refuse parallel multi-repo explore without evidence |

### Workflow: `metra.ps1 verify` / Pester smoke

| Field | Value |
|-------|-------|
| Current | L5 |
| Target | L5 |
| Ceiling | Validator/gate only - does not own a full operator goal loop by itself |
| Ceiling reason | technical |
| Completeness | complete |
| Evidence quality | authoritative (PASS/WARN/FAIL fixtures) |
| Loop form | goal-based (judge = verify/Pester) |
| Evidence (current) | `.\metra.ps1 verify` PASS/WARN/FAIL against Routing-Scenarios; `tests/Invoke-MetraTests.ps1` / Pester; used as fail-closed smoke |
| On hard stop | FAIL/WARN named; output in console or test results path; next: fix fixture/registry drift then re-run verify |
| Gaps to target | none as a gate. Pair with L6 coding sessions as the check step |
| Next bite | none required; wire into coding-session done-when (see route-first coding card) |

### Workflow: TicketTracker ticket-ops

**Purpose:** Operator-driven ticket brief, note, recommend, and related iSupport actions. Separate from Metra ticket watch intake - do not merge scorecards.

| Field | Value |
|-------|-------|
| Current | L3 |
| Target | L3 |
| Ceiling | L3 - `post` / `recommend` / `resolve` only when operator requests; `note` is local-only |
| Ceiling reason | policy |
| Completeness | complete |
| Evidence quality | adequate (`brief`/SQL-backed fields); stretch to authoritative with post-then-rebrief |
| Loop form | turn-based (operator requests durable writes) |
| Evidence (current) | `brief` / `similar` / `search` / `chats`; sticky TicketTracker primary; `post`/`recommend`/`resolve` with structured plain text; solutions index; Metra AI Recommendation rule |
| On hard stop | Sync/tool failure: say local vs iSupport state; next: retry `sync`/`brief` or operator posts in UI - never invent work history |
| Gaps to target | none for L3. Stretch (not required): L5 = post then re-`brief` confirms work history / resolution fields |
| Next bite | none for Target L3; optional post-then-brief check when hardening a specific ticket path |

### Workflow: Metra ticket watch intake

**Purpose:** Convert TicketTracker changes into operator-visible Attention observations and optional local draft recommendations. Sensor-to-Attention - not unsupervised ticket mutation.

| Field | Value |
|-------|-------|
| Current | L3 |
| Target | L3 (named TicketTracker tools + Attention upsert; honesty when TT absent) - intake capability only |
| Ceiling | L3 for iSupport `recommend`/`post`/`resolve`; implement forever outside watch |
| Ceiling reason | policy |
| Completeness | complete |
| Evidence quality | adequate (live sync/list/updates via TicketTracker module; fail-soft when TT missing) |
| Loop form | turn-based via `.\metra.ps1 watch tickets`; time-based when full Snapshot covers `ticket` (exit = scan cadence, not "work finished"). Later Host poll: time-based. Thin event bus: proactive - keep cold until allowlisted |
| Evidence (current) | Attention kind `ticket`; `Invoke-MetraTicketWatchScan` / `.\metra.ps1 watch tickets`; Snapshot full-scan fail-soft ingest; sticky dismiss on id+Updated+Status; no iSupport writes from watch |
| On hard stop | TT unavailable / sync fail: Snapshot continues with warning; CLI reports skip; next: fix TT path or retry `watch tickets` - do not invent tickets |
| Gaps to target | none for Target L3 intake. Stretch (not required): goal-based L5 draft validator; Phase 2 affirm-to-recommend |
| Next bite | Phase 2 affirm UX calling TicketTracker `recommend` (separate bite); keep Host poll / Mail / Orion later |

Do not call this L4 (no specialist merge). Do not grant L5 because Snapshot or Host poll woke up. Stretch goal-based L5 only with a machine-checkable draft validator.

### Workflow: Ticket thread + one technical investigate hop

| Field | Value |
|-------|-------|
| Current | L3 |
| Target | L5 |
| Ceiling | L3 for iSupport durable writes; warehouse/Datamart read-only for agents |
| Ceiling reason | policy |
| Completeness | incomplete |
| Evidence quality | adequate (one technical CLI surface); authoritative when playbook multi-signal checks run |
| Evidence (current) | Ticket-ops vs investigate classification; one technical project via registry; return outcomes to TicketTracker; Colleague/Jitterbit/Solarwinds playbooks as tool surfaces |
| On hard stop | Investigate criterion unmet; cite session/health/command output (or ticket `note`); next: return to TicketTracker with fail-closed handoff - do not `post` success |
| Gaps to target | 1. Explicit investigate done-when (evidence checklist) before leaving the technical project. 2. Retry/re-query bound when session/health checks flake. 3. Fail-closed handoff text when Live evidence cannot be obtained. 4. Recovery triplet on every hard stop |
| Next bite | Per playbook: add a short "done-when" block (e.g. Colleague: session list + process filter empty or stack reviewed) |

### Workflow: Jitterbit stuck-ops

| Field | Value |
|-------|-------|
| Current | L3 |
| Target | L5 |
| Ceiling | Operator confirm before `Clear-JitterbitTranDbStuckOperation` (non-WhatIf); do not automate PE restart |
| Ceiling reason | safety |
| Completeness | incomplete |
| Evidence quality | adequate today; authoritative when health + TranDb agree after action |
| Loop form | turn-based today; target goal-based (judge = health + TranDb after Clear) |
| Evidence (current) | Playbook in `IWU.Jitterbit/README.md` + project `AGENTS.md`: `Find-JitterbitStuckOperation` -> `Get-JitterbitAgentHealth` -> `Stop-JitterbitOperation` -> TranDb get/clear with `-WhatIf`; CredSSP via CredentialHelper |
| On hard stop | PE down or counts not improved; cite health/TranDb tables; next: operator fixes PE or confirms Clear - never soft-cancel live work blindly |
| Gaps to target | 1. Machine-checkable success (health + TranDb counts after clear). 2. Ordered retry when Harmony list/health flakes, with bound. 3. Fail-closed when PE down - partially documented, not agent-enforced. 4. Document recovery triplet as done-when |
| Next bite | After Clear: re-run `Get-JitterbitAgentHealth` + TranDb preview; document pass criteria in README as done-when |

### Workflow: Jitterbit agent go-live

| Field | Value |
|-------|-------|
| Current | L3 |
| Target | L5 |
| Ceiling | Fail any phase = stop; human owns go-live sign-off |
| Ceiling reason | safety |
| Completeness | incomplete |
| Evidence quality | adequate (checklist + smoke); authoritative when phase matrix is stamped from script |
| Evidence (current) | `Agent/Docs/Agent-Go-Live-Checklist.md` phased gates; `Agent/bin/Test-JitterbitAgentInstall.ps1` for Phases A-E host facts; health module for day-two spot-check |
| On hard stop | Named phase failed; smoke/checklist Actual column; next: fix that phase and re-run from failure - no skip-ahead to traffic |
| Gaps to target | 1. Single orchestrated run that executes smoke + records pass/fail per phase. 2. Retry bound only inside a phase, not skip-ahead. 3. Fail-closed artifact (which phase failed) before traffic |
| Next bite | Extend smoke script output to a phase pass matrix the checklist can stamp |

### Workflow: Colleague stuck session / in-use

| Field | Value |
|-------|-------|
| Current | L3 |
| Target | L5 |
| Ceiling | Confirm before Live `Stop-ColleagueSession` / control-record clear; never kill datatel phantoms |
| Ceiling reason | safety |
| Completeness | incomplete |
| Evidence quality | adequate (`Get-ColleagueSession -FullName`); authoritative when session + process filter agree |
| Loop form | turn-based today; target goal-based (judge = session gone or lock owner named) |
| Evidence (current) | Colleague `AGENTS.md` triage: `brief` then `Get-ColleagueSession -FullName`, optional `Get-ColleagueUdtProcess`, classify old vs fresh vs none; module cmdlets over ad-hoc telnet |
| On hard stop | No killable session or unknown lock file; cite session/process output; next: ask operator which control record to clear - fail closed, do not invent a generic clear |
| Gaps to target | 1. Done-when checklist (session gone or lock owner named). 2. Bound retry when `Show-ColleagueCallStack` / telnet flakes. 3. Fail-closed ask to operator when no clear-in-use helper exists for the mnemonic |
| Next bite | Add done-when bullets to the stuck-process section in Colleague `AGENTS.md` |

---

## How agents use this (completeness metric)

When modeling **current** or **future** development for a workflow:

1. **Name the workflow** (one sentence; one primary project when portfolio work).
2. **Score Current** using the gates table - cite evidence and Evidence quality.
3. **Declare Target**, Ceiling, and Ceiling reason.
4. **List Gaps** as level deltas and missing gates - not vibes.
5. For Target L5/L6, fill **On hard stop** (what / where / next) and name the **loop form by exit** (turn / goal / time / proactive).
6. **Verdict:** `complete` only if Current meets Target with gates satisfied; otherwise `incomplete` and name the next bite.
7. **Refuse L6 theater:** if durable writes or prod actions lack an operator (or Host) gate the workflow documents, do not mark complete at L5/L6. Refuse proactive loops for systems of record without an explicit allowlist.

Planning / Future-Development bites should state Target level in the bite notes when the work is agentic. Implementation PRs and ticket write-ups stay in the professional sink - cite level only when it helps the operator (for example "stuck-ops runbook is L3 today; target L5 with TranDb clear + health check").

---

## Relationship to Metra temperament

- **Route before execute** is L2 institutional routing - non-negotiable for portfolio work.
- **Visibility, not vanity scores** - maturity cards are design artifacts; do not add a maturity percentage strip to Ops health.
- **Professional sink** - tickets/commits never speak as Metra; maturity labels in chat are fine, in iSupport rarely needed.
- **Operator stays in charge** - L6 means the harness owns the loop until goal criteria; it does not mean unsupervised mutation of systems of record.
- **System surrounds the model** - routing, context, root isolation, validation, and write authority are harness concerns; the LLM is one component inside the workflow.
- **Pick loops by exit** - turn / goal / time / proactive; do not confuse a timer with a judge.

---

## Change control

- Portfolio-wide level definitions live in this file.
- Portfolio scorecard register (above) is the shared snapshot; refresh the dated summary when Current/Target/Completeness changes.
- Project playbooks may deep-link here or keep a one-line Current/Target - do not fork a second ladder.
- Per-bite plans and Future-Development notes may attach a mini scorecard for work in flight.
- Policy scars about adopting or changing the ladder go in [Decisions.md](Decisions.md).
- 2026-08-06 Bing review scars folded here: evidence quality annotation, ceiling reason, hard-stop recovery triplet; no L3a/L3b sub-levels; no Ops percentage theater.
- 2026-08-06 loop-forms-by-exit vocabulary folded under L5/L6 (turn / goal / time / proactive); not new levels.
