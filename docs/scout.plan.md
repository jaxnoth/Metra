# Plan: Metra Scout

**Status:** Approved direction - initial plan (2026-09-03)
**Date:** 2026-09-03
**Product:** Metra Scout - iOS application and always-on investigative subsystem
**Supersedes naming:** Metra iOS, Metra Mobile, Metra Companion (all retired)
**Related plans:**

| Plan | Doc | Status |
|------|-----|--------|
| iOS app umbrella (UI shape, presence, voice) | [ios-companion-app.plan.md](ios-companion-app.plan.md) | Approved - UI shape remains valid |
| iOS conversation policy | [ios-conversation-policy.plan.md](ios-conversation-policy.plan.md) | Approved - policy layer still applies |
| iOS presence behavior | [ios-presence-behavior.plan.md](ios-presence-behavior.plan.md) | Approved - presence transitions still valid |
| Vision Ask contract | [ios-vision-ask-contract.md](ios-vision-ask-contract.md) | Approved - Ask contract still valid |
| Tailscale identity auth | [tailscale-identity-auth.plan.md](tailscale-identity-auth.plan.md) | Approved direction |

**Decision Registry:** `docs/Decisions.md` (2026-09-03 Scout entries)

---

## 1. What Scout is

Scout is an **investigative capability**, not a chatbot, not a virtual personality, and not a peer application.

Scout exists to discover what deserves attention.

The iOS application named Metra Scout is the primary operator surface for Scout observations. The Scout subsystem also operates continuously in the background, independent of whether the iOS app is open.

Scout is not the Ani/Grok companion replacement. It is a distinct product identity built around investigation rather than conversation.

---

## 2. Architectural position

```
Metra
├── Atlas          (portfolio memory, document exchange)
├── TicketTracker  (ticket lifecycle, helpdesk ops)
├── Codex          (knowledge base, KB articles)
├── Loom           (plan execution, agentic coding)
├── Attention      (signal bus, detection layer)
└── Scout          (investigative subsystem, analyst layer)
```

Scout is a first-class subsystem. It is not a feature of another subsystem.

### Signal chain

```
Signal
  → Attention         (detects; routes signal to Scout)
  → Scout             (investigates; generates observations, hypotheses, recommendations)
  → Recommendation    (confidence-scored, evidence-based output)
  → Human Affirmation (required before any action)
```

Attention and Scout are intentionally separate layers. Attention detects; Scout investigates. This separation preserves independent replaceability: Attention can evolve its detection logic without changing Scout's investigative contract, and Scout can evolve its reasoning without changing how signals are detected.

---

## 3. Scout contract

### Primary mission

Discover what deserves attention.

### What Scout does

- Identify weak assumptions in prevailing theories or plans
- Generate alternate explanations for observed patterns
- Challenge architectural direction with evidence
- Review code changes for drift, risk, or missed implications
- Detect recurring patterns across tickets, commits, and observations
- Surface anomalies in system behavior or portfolio activity
- Identify missing evidence before decisions are made
- Suggest investigations the operator has not yet considered
- Generate new ideas from cross-domain signal
- Find contradictory signals across sources

### What Scout does not do

Scout may not:

- Approve any action
- Deploy to any environment
- Commit code
- Send communications on behalf of the operator
- Modify production systems
- Execute changes without explicit human affirmation

Human affirmation is required for all Scout outputs that affect the portfolio.

---

## 4. Notification model

Scout may proactively generate observations. Observations are:

- **Concise** - one to three sentences; lead with the signal
- **Evidence-based** - cite the source (ticket, commit, Attention card, pattern)
- **Confidence-scored** - low / medium / high; do not overstate certainty
- **Recommendation-oriented** - close with a suggested investigation or next step

Example observations:

> "Three Pentegra employees remain unexplained in the ticket evidence. Confidence: medium. Suggest reviewing the meeting prep notes for the remaining three names."

> "Recent commits suggest Atlas responsibility is drifting into Metra routing logic. Confidence: high. Recommend reviewing the routing decision boundary before the next release."

> "TicketTracker activity shows four DNSFilter exception requests in 30 days. Confidence: high. A solutions write-up may reduce repeat ticket handling time."

> "An alternate explanation exists for the payroll discrepancy: the Colleague feed timing change on 2026-08-15 predates the first report by two days. Confidence: medium."

Observations that do not meet evidence or confidence thresholds should be withheld or flagged as speculative rather than surfaced as authoritative.

---

## 5. Provider strategy

Scout is provider-agnostic. The provider is an implementation detail.

### Configuration

Scout uses a `scout.engine` configuration pin, following the same pattern as `ask.engine` and `inspect.*` pins.

```json
{
  "scout": {
    "engine": "claude",
    "fallback": "local"
  }
}
```

### Supported provider families (initial)

- Claude (Anthropic)
- GPT (OpenAI)
- Grok (xAI) - not required; not the primary
- Local models (Ollama)
- Future providers

### Engine independence

When implementation and Scout review use different model families, Scout findings are stronger. The engine independence principle from Inspect applies here: do not treat Scout observations as independent validation when the Metra Agent and Scout share the same model family.

---

## 6. iOS application: Metra Scout

The iOS application is renamed **Metra Scout**. The app is the primary operator-facing surface for Scout observations. It is a client of the operator's Metra Ops host over Tailscale.

### Prior UI contracts (still valid)

The presence behavior, conversation policy, and Vision Ask contracts from the prior iOS companion plans remain in effect for the UI layer. Scout changes the identity and mission framing of the app; it does not invalidate the SwiftUI architecture, Tailscale auth, or presence face design.

| Layer | Prior contract | Scout impact |
|-------|---------------|--------------|
| Presence face / transitions | `ios-presence-behavior.plan.md` | No change |
| Conversation Desk / Vision | `ios-conversation-policy.plan.md` | Vision mode reframed as Scout investigation surface |
| Voice identity | `ios-voice-identity.plan.md` | No change |
| Tailscale auth | `tailscale-identity-auth.plan.md` | No change |
| Backend | `/api/ask`, capture/journal, profile | Scout adds `/api/scout` investigation lane |

### Mode mapping (updated)

| Mode | Prior name | Scout framing |
|------|-----------|---------------|
| Vision | Companion chat / Ani replacement | Scout investigation surface - open-ended inquiry, observation capture, proactive Scout output |
| Bounded | Explicit portfolio Metra | Portfolio ops on phone - route + evidence (unchanged) |

### Eventual capabilities (not committed for v1)

- Meeting preparation summaries before calendar events
- Ticket observations before opening a ticket in iSupport
- Architecture review suggestions on recent commits
- Code review surfacing on active Loom executions
- Investigation tracking across sessions
- Idea generation from cross-portfolio signal
- Voice-first Scout interaction (drive-time use case)
- Proactive push notifications from background Scout activity

---

## 7. Background Scout subsystem

Scout also operates as a background subsystem independent of the iOS app. This is the "always-on" layer.

Background Scout is not yet implemented. The initial plan establishes the capability contract and the signal chain. Implementation follows in later phases.

Background Scout will:

- Consume Attention output on a configurable cadence
- Run investigations against the current portfolio state
- Queue observations for the operator (iOS push, Ops desk card, or both)
- Respect the authority ceiling at all times

Background Scout will not run in a continuous loop without a cadence gate. Observation volume must be controllable. The Attention volume handling decision (2026-08-11, `attentionVisibleCount`) applies here: Scout must not flood the operator with low-confidence observations.

---

## 8. Open questions (to resolve as Scout evolves)

| Question | Notes |
|----------|-------|
| Scout cadence gate | How often does background Scout run? Configurable interval? Event-triggered? |
| Observation store | Where do Scout observations live? Attention memory? A Scout-specific store? Atlas? |
| Confidence calibration | How are confidence scores derived and displayed? Manual tagging by the engine, or a calibration layer? |
| Investigation tracking | Can the operator follow up on a Scout observation across sessions? What persists? |
| Loom integration | Does Scout review active Loom executions? Does Loom trigger Scout? |
| Codex integration | Does Scout surface KB gaps from TicketTracker patterns? Does Scout draft KB articles? |
| Registry entry | Scout needs a `projects.json` entry and `AGENTS.md` when implementation begins |

---

## 9. Tagline candidates

"Find what deserves attention." - mission-accurate, calm

"See around corners." - more evocative, slightly informal

Both are candidates. No decision required now.

---

## 10. What this plan does not change

- Metra routing logic remains unchanged. Scout does not route; Metra routes.
- TicketTracker remains the ticket lifecycle system. Scout may surface ticket observations; it does not write tickets.
- Atlas remains the document exchange and portfolio memory layer. Scout may recommend Atlas puts; it does not perform them.
- Codex remains the KB system. Scout may surface KB gaps; it does not publish KB articles.
- Loom remains the plan execution layer. Scout may observe Loom runs; it does not trigger or modify them.
- Human affirmation is required before any Scout recommendation becomes an action.
