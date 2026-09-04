# Plan: Scout (parked)

**Status:** Parked (2026-09-03)
**Date:** 2026-09-03
**Not approved as:** a separate Metra subsystem
**Related:** [ios-companion-app.plan.md](ios-companion-app.plan.md) (Metra iOS brand), Attention (existing signal / recommendation layer)

**Decision Registry:** `docs/Decisions.md` (2026-09-03 Scout park)

---

## Disposition

Scout is **not** approved as a first-class Metra subsystem.

Desired investigative behaviors were identified, but no clear ownership boundary differentiates Scout from **Attention**. Granting Scout peer status next to Atlas, Codex, Loom, and Attention would invent a sibling whose mission still overlaps Attention + recommendations.

**Likely future path:** Scout ideas may fold into **Attention 2.0** rather than become a separate product. Revisit only if a concrete workflow needs dedicated investigative reasoning beyond Attention recommendations.

Earlier same-day drafts that formalized Scout as an approved subsystem (or renamed the iOS app) are superseded by the park decision.

---

## Settled (not Scout)

- iOS application name and brand remain **Metra**.
- Phone is a client of Metra, not a second Metra.
- Secretary / coworker framing applies to Metra on the phone, not to a Scout product.

---

## Desired attributes (parked notes)

Keep these as candidate behaviors for a later Attention evolution or a future subsystem proof:

- Alternate / competing explanations
- Contradiction detection
- Assumption challenges
- Investigative or deliberately adversarial reasoning

Example of a *possible* distinct behavior (not approved, not implemented):

> Attention: "Pentegra discrepancy detected."
> Investigative step: "The current explanation is probably incomplete. Here are three competing explanations."

If that step never needs a separate owner, it belongs in Attention.

---

## Open question (reopen trigger)

Do the attributes above belong in **Attention**, or do they justify a dedicated subsystem after a concrete workflow appears?

Revisit when:

- A named workflow requires competing explanations or assumption challenges that Attention recommendations cannot cover, **or**
- Attention is explicitly redesigned as Attention 2.0 and absorbs these notes.

---

## Explicit non-goals while parked

- No Scout registry project / `AGENTS.md`
- No `scout.engine` pin as a shipping contract
- No Loom / Yarn enqueue for Scout implementation
- No iOS app rename to Scout or Metra Scout
- No claim that Scout is already Attention's peer

---

## Historical note

This file previously carried an "Approved direction" Scout subsystem architecture (signal chain, provider strategy, async delivery). That content is withdrawn from active architecture. Source discussion and Bing park guidance live in chat / Decision Registry; do not treat older Scout hierarchy diagrams as current.
