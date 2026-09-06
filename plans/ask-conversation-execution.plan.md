---
name: Ask Conversation Execution
overview: "Replace AskLane regex template/ops-status fork with Conversation Execution (secrets preflight → intent → policy → depth → engine → voice) for Bounded Ops/phone Ask. Bing Conditional Affirm 2026-09-06 closed into locked contract."
status: Approved with amendments (Bing baseline review 2026-09-06)
bingReviewed: true
implementationHold: baseline-separation-required
phase: ask-conversation-execution
relatedPlans:
  - plans/ios-conversation-policy.plan.md
  - plans/ios-presence-behavior.plan.md
todos:
  - id: preflight-voice-contracts
    content: Secrets preflight + filled voice envelope on every return path (incl. refuse)
    status: pending
  - id: ask-conversation-pure
    content: "AskConversation.ps1 pure functions - intent, policy hierarchy, knobs, depth budget"
    status: pending
  - id: evidence-depth
    content: Extend AskEvidence depth ceiling (capability+health, route_summary, full)
    status: pending
  - id: engine-result-overlay
    content: Typed engine result + reason codes; policy-aware buildPrompt
    status: pending
  - id: rewire-desk-ask
    content: Rewire Get-MetraDeskAskResult behind flag; demote AskLane to telemetry
    status: pending
  - id: api-clients-voice
    content: Ops + iOS render voice.display; normalize voice in both flag modes
    status: pending
  - id: tests-eval-docs
    content: Boundary/output/policy/migration Pester + Decisions scar + Ask eval
    status: pending
---

# Ask Conversation Execution

**Status: Approved with amendments** (Conditional Affirm + baseline review 2026-09-06 folded below). Implement behind `ask.conversationExecution.enabled` only after the working-tree baseline is separated/committed. Not shipped.

**Bite:** Server-side Conversation Execution for **Bounded Ops / phone Ask** only. Normative posture: [ios-conversation-policy.plan.md](ios-conversation-policy.plan.md). Presence/TTS separate ([ios-presence-behavior.plan.md](ios-presence-behavior.plan.md)).

**Verified current (2026-09-06):** `AskConversation.ps1` absent. `Get-MetraDeskAskResult` still early-returns via `Resolve-MetraAskLane` → chat templates / `New-MetraAskOpsStatusResult`.

**Implementation hold (Bing baseline review 2026-09-06):** Do not start code from a mixed pack of host/Loom/routing-plan + Ask-plan docs. Ship OpsHost/Profile/Routing/Snapshot (+ Loom hyphen scrub if kept) and routing ledger plans as separate baselines first; then begin Ask bite 1 (preflight + voice envelope).

## Bing-affirmed amendments (2026-09-06)

Conditional Affirm closed by locking these five gaps into the contract:

1. Secrets preflight **before** intent, policy, evidence, telemetry, journal, engine.
2. `status_query` needs live health (or explicit inability to verify) - not capability inventory alone for affirmative "running well."
3. Server-side policy trust hierarchy - clients cannot weaken gates / DeskStrict.
4. Typed engine failure classes + deterministic fallback (always filled voice; never empty; never false completion).
5. Voice formatter preserves refusal, uncertainty, OperatorConfirm, and not-completed across spoken/display/durable.

Baseline review locked two more contract edits: trusted-client policy authority (not header-as-auth), and source-owned health freshness.

## Outcome

Phone and Ops Ask answer check-ins and status asks in **plain English**, use **intent-gated evidence depth** for work turns, and **always** return a filled **`voice`** (`spoken` / `display` / `durable`) with `message = voice.display` - without leaking secrets, inventing health, letting client policy bypass authority, or breaking Vision / TicketTracker ownership.

## Problem (still live)

```text
prompt → handoff → Resolve-MetraAskLane (regex)
              ├─ chat → templates (robotic; no engine)
              ├─ ops status → New-MetraAskOpsStatusResult
              └─ routed + adequate → full pack → AGENTS.md essay risk
```

## Target architecture

```text
raw prompt
  → Normalize-MetraAskInput
  → secrets disposition (refuse | scrubbed | unchanged)
  → Resolve-MetraAskIntent
  → Resolve-MetraConversationPolicy (server trust hierarchy)
  → other deterministic gates (authority, Vision isolation path)
  → Resolve-MetraAskEvidenceDepth (ceiling)
  → New-MetraAskEvidencePack -Depth …
  → Invoke-MetraAskConversationEngine → typed result
  → Format-MetraAskVoiceFromEngine (all paths)
  → /api/ask  message=display  voice=*  + telemetry
  → Resolve-MetraAskLane -.-> lane/reason badges only
```

## Architectural commitments

1. **Intent is evidence; policy is posture** - not equal to Desk/Company/Deliver by themselves.
2. **Hard gates stay deterministic and ordered** - Secrets first; then authority / incident / Vision isolation. Low intent confidence never suppresses those gates.
3. **Secretary, not train station** - Plain English first; intent chooses evidence depth.
4. **Persona overlays stay in rules** - AskConversation supplies knobs only; no kernel re-host.
5. **Routing graph is orthogonal** - where vs how.
6. **Capture is not a free write** - may recognize/phrase capture intent; does **not** create/modify durable artifacts unless an existing authorized capture contract owns the action.

## Locked contract

### 0. Secrets preflight (before intent)

Secrets detection, refusal, and scrubbing occur **before** intent classification, policy resolution, evidence construction, telemetry, journaling, or engine invocation. Downstream components receive only the approved sanitized prompt and **must not retain the raw prompt**.

Refuse returns a **filled voice** (example shape):

| Field | Content |
|-------|---------|
| `message` / `voice.spoken` / `voice.display` | Short refuse (no secret text) |
| `voice.durable` | Disposition only (e.g. secrets boundary) - **never** the detected secret |

### 1. Module `scripts/private/AskConversation.ps1`

| Function | Role |
|----------|------|
| `Resolve-MetraAskIntent` | Intent classes + confidence/source; local deterministic; no raw-prompt persist |
| `Resolve-MetraConversationPolicy` | Applies **trust hierarchy** below |
| `Get-MetraConversationPolicyKnobs` | warmth/humor/clarifications/silence/plainEnglish/retentionClass |
| `Resolve-MetraAskEvidenceDepth` | Depth **ceiling** (may return less; never more) |
| `New-MetraConversationPrompt` | Policy overlay + objective |
| `Invoke-MetraAskConversationEngine` | Returns typed envelope (Succeeded, ReasonCode, Text, …) |
| `Format-MetraAskVoiceFromEngine` | Always filled scrubbed voice; semantic preservation |

Intent confidence may increase clarification or constrain depth; it **must not** suppress secrets, authority, incident, or Vision isolation.

Authority defense in depth: pre-engine deterministic scan → intent → post-engine completion-language validation (no false "done").

### 2. Evidence depth budget (ceiling)

| Depth | May contain |
|-------|-------------|
| `none` | Prompt + policy overlay only |
| `capability_only` | Capability manifest + **permitted current health summary when available** (`runtimeHealthSnapshot`, `degradedComponents`, `observationTimestamp`, `healthSource`, plus any source freshness fields the health owner publishes) |
| `route_summary` | Selected route, confidence, bounded product/owner summary - no full artifact dump |
| `full` | Existing Ask evidence pack under current limits |

**Health freshness (source-owned):** A health source owns its freshness contract. Conversation Execution may make an affirmative current-health statement only when the source marks the observation current, or when the observation remains inside that source's configured freshness window. Missing freshness metadata is treated as unverifiable for affirmative current-health claims. Do **not** hard-code a universal timeout inside `AskConversation.ps1`.

### 3. Check-in vs status_query

| Input | Intent | Evidence | Required behavior |
|-------|--------|----------|-------------------|
| How are today Metra? | check_in | Capability; health optional | Brief check-in; no infrastructure essay |
| Are you running well? | status_query | Runtime health **required for affirmative claim** | Report known health **or** state inability to verify |
| Is TicketTracker working? | work/status component | Component health or route_summary | Do not generalize overall Metra health |
| What can you do? | capability | Static capability manifest | No full pack |

Rules:

- Social check-in may answer conversationally from capability awareness.
- Status questions must use current health evidence if available.
- If no current health signal: say cannot verify - do **not** infer "running well" from HTTP 200 / Ask success.
- Affirmative current-health claims also require source-owned freshness (current mark or inside the source freshness window); missing freshness metadata → unverifiable.
- Successful `/api/ask` proves only that the immediate request path responded.

### 4. Policy trust hierarchy

```text
Deterministic server gates
  > active incident / DeskStrict
  > server-configured endpoint policy
  > server-established trusted-client context (auth or validated loopback)
  > accepted policy override (allow-list; trusted context only)
  > header / body client claims (descriptive / telemetry)
  > clientHint (advisory)
  > intent-derived Auto
```

Practical identity hierarchy for this bounded bite:

```text
server-established client identity
  > validated loopback endpoint classification
  > header client claim (X-Metra-Client)
  > body client hint
```

Only the first two authorize a policy override. Header and body values may drive compatibility or telemetry, not authority.

Rules:

- `clientHint` is advisory.
- Unknown clients cannot select policy directly.
- Requested policy may make behavior **stricter**, never relax a hard gate.
- DeskStrict cannot be downgraded by payload.
- Deliver changes response objective, not authority.
- Policy overrides are accepted only from a **server-established trusted-client context**. `X-Metra-Client` and body `client` are descriptive claims unless validated by an existing authentication or loopback trust boundary.
- Header/body mismatch rejects the override and records `policy_override_client_mismatch`; it does **not** choose either claim as authenticated identity.
- Rejected overrides → telemetry reason (not silent accept).

Fixtures: incident+Company→DeskStrict; authority_write+Deliver→OperatorConfirm; unknown+Company→Auto/default; trusted iOS greeting→Company only if allow-listed; header/body mismatch→override rejected + mismatch reason.

### 5. Incident provenance

DeskStrict / incident activates only from **trusted** sources: server runtime state, explicit trusted request context, existing incident detector, or operator-selected mode. Natural language alone ("what would you do in an incident?") does **not** activate operational incident state.

### 6. Engine result + fallback

Typed envelope (shape):

```powershell
[pscustomobject]@{ Succeeded = $true; ReasonCode = 'ok'; Text = $engineText; Raw = $optionalDiagnostic }
```

Reason classes (minimum): `engine_disabled`, `engine_not_configured`, `engine_unreachable`, `engine_timeout`, `engine_invalid_response`, `engine_empty_response`, `engine_context_rejected`, `evidence_pack_failed`, `policy_overlay_failed`.

Fallback locks:

- Never empty `message`; always complete `voice`.
- Never claim requested work completed.
- Preserve authority and secret dispositions.
- Templates only after recorded execution failure **or** feature flag false.
- Do not silently downgrade a work answer into generic chat.
- No raw engine errors in spoken/display; bounded diagnostic in durable + telemetry.
- Distinguish known deterministic route evidence from unavailable generated explanation.

### 7. Voice normalization

Invariants on **every** return path (success, refuse, fallback, flag false):

- `message == voice.display`
- `spoken`, `display`, `durable` all non-empty and scrubbed
- Preserve gate disposition, uncertainty, completion state
- `spoken`: no Markdown / routing furniture
- Formatting may shorten; **must not** remove refusal, uncertainty, OperatorConfirm, source limitation, or not-completed
- `durable`: sanitized journal-canonical disposition + useful result - **not** raw engine, hidden reasoning, full prompt, or evidence pack

### 8. Rewire `Get-MetraDeskAskResult`

Behind `ask.conversationExecution.enabled`:

1. Secrets preflight → intent → policy (hierarchy) → other gates.
2. Stop chat-template / ops-status as **primary** when flag true.
3. Depth-bounded pack → engine → voice normalize.
4. AskLane → legacy lane/reason mapping only.
5. Flag **false**: prior execution branch; **still** normalize result into filled voice (`message = voice.display`).

### 9. Clients + telemetry

- Ops/iOS prefer `voice.display`; tolerate legacy message-only during migration.
- Telemetry: `policy`, `reasonCode`, `policySource`, `retentionClass`, `intentClass`, engine `ReasonCode`, override accept/reject codes.

### 10. Rollout

- Flag default **true** only after boundary/output/policy/migration fixtures pass.
- Ops restart after deploy; inspect `prepare-bing` after meaningful batch.

## Implementation sequence (Bing)

1. Preflight + voice result contracts  
2. Intent/policy/knobs/depth as pure functions + heavy Pester  
3. Evidence-pack depth without changing default caller  
4. Engine overlay + typed execution result  
5. Rewire behind flag  
6. Demote AskLane to migration metadata  
7. Normalize every return through voice formatter  
8. Ops + iOS clients  
9. Telemetry + Decisions + docs  
10. Focused Pester → existing AskLane/evidence → HTTP smoke → prepare-bing  

## Done when (acceptance)

| Check | Expect |
|-------|--------|
| Secrets before intent | Refuse/scrub; filled voice; durable has disposition only |
| Check-in | Plain; no AGENTS essay |
| Status affirmative | Health evidence or inability-to-verify |
| Policy override untrusted | Ignored/stricter; telemetry reason |
| DeskStrict | Cannot weaken via payload |
| Engine failure | ReasonCode + filled voice; no false completion |
| Voice | message==display; semantic preservation fixtures |
| Flag false | Old branch + voice schema still filled |
| Vision / TT assess | Isolation / ownership unchanged |
| Capture intent | Phrase only unless authorized capture contract fires |

## Required test matrix (additions)

**Boundary:** secret in greeting; secret in authority; secret-like false positive; indirect authority; NL "incident" without trusted signal; trusted incident + humorous prompt; Vision to `/api/ask`; TT assess through Bounded Ask; capture with no write owner.

**Output:** empty/whitespace/malformed engine; Markdown in spoken; false completion; missing spoken/durable; truncation would drop OperatorConfirm; secret in engine output; message≠display.

**Policy:** Auto per intent; trusted/untrusted override; DeskStrict cannot weaken; Deliver≠authority bypass; Company retention; Deliver maxClarifications=0; Desk ≤1 follow-up; incident disables humor/warmth.

**Migration:** lane/reason populated but not primary; flag false/true branches; engine-down keeps lane without pretending it answered; clients render both shapes.

## Deliverables

| Item | Location |
|------|----------|
| NEW | `scripts/private/AskConversation.ps1` |
| NEW | `tests/Metra.AskConversation.Tests.ps1` |
| Rewire | `Snapshot.ps1`, `AskEvidence.ps1`, `AskLane.ps1` |
| Sidecar | `engines/cursor/server.mjs` |
| Clients | `ops/src/App.tsx`, iOS `OpsAskClient.swift` |
| Docs | This plan; Decisions at ship; Ask eval |

## Out of scope

Vision/LocalAssist relational lane; Company silence push from Ops; dual live models; TT assess graph rewrite; auto Host writes; routing-graph P6+; re-hosting persona kernels in AskConversation.

## Operator notes

Architecture affirmed; Conditional Affirm gaps plus baseline-review edits (trusted-client override authority; source-owned health freshness) are locked. Hold code until host/routing baseline commits land. Then implement behind the flag using the sequence above (bite 1 = preflight + voice envelope only). Cursor twin: sync from this file after edits.
