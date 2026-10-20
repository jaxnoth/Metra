---
name: iOS voice identity (provisional)
status: approved
bingReviewed: true
approveForLoom: true
approveForLoomHash: 29561faa93e942c5e891ba6ab2f86171b071dd3189b4cbed4818f7aeef345974
externalReviewed: true
externalReviewHash: 29561faa93e942c5e891ba6ab2f86171b071dd3189b4cbed4818f7aeef345974
---

# Plan: iOS voice identity (provisional)

**Status:** Approved (Bing 2026-10-16; operator lock 2026-08-29). Identity decision only - no app wiring in this plan.

**Owner:** Metra iOS companion speak identity

**Related:** [ios-presence-behavior.plan.md](ios-presence-behavior.plan.md) Appendix A.0 (voice identity ≠ face), [ios-conversation-policy.plan.md](ios-conversation-policy.plan.md), Brand.md

**Not this plan:** Cloud neural TTS shortlist; Live Speech plumbing; app Settings UI; `AVSpeechSynthesizer` integration (separate Phase 2.1 implementation bite).

**Implementation handoff:** Phase 2.1 (tap-to-talk STT + speak replies) owns wiring. This plan stays the identity lock + Brand pointer.

---

## 1. Provisional default

| Role | Choice |
|------|--------|
| **Default Metra speak** | **Siri Voice 4** (operator preference after listen pass) |
| Lower-register alternate | Australian Siri Voice 4 (same character family, lower register) - optional, not required for v1 |
| Personal Voice | Future **opt-in only** when available - never silent default as Metra |

One Metra identity across Desk / Company / Deliver. Policy may nudge rate/energy; it must not switch to a different character voice.

Record device locale as shown in Settings when implementing (e.g. which regional Voice 4 pack is installed). Until then, “Siri Voice 4” is the operator-facing lock name.

---

## 2. Hard vetoes

Do not use as Metra default:

- Flirtatious / sensual TTS personas
- Childlike or cartoon voices
- Meme / novelty voices
- Silent default to the user’s Personal Voice (accessibility opt-in later is fine)

---

## 3. Eval pack (for re-check later)

Same four lines on any candidate:

1. **Desk:** “Ticket 4821 is waiting on DNS. Want me to pull the last check?”
2. **Company / support:** “Rough day. I’m here at the next desk if you want to talk it through.”
3. **Deliver:** “Here’s a short story.” + two or three sentences
4. **DeskStrict:** “Incident on the mail relay. Status first.”

Siri Voice 4 already preferred; re-run this pack if Apple renumbers voices or a new OS changes timbre.

---

## 4. Privacy note

System / on-device Siri and Spoken Content voices stay on-device for synthesis - good fit next to ephemeral personal-support routing. Cloud TTS remains a later, separate decision and must honor retentionClass.

---

## 5. Next (implementation bite - not this document)

Do **not** expand this identity plan into an AVSpeech project. A separate Phase 2.1 bite owns:

- Resolve Voice 4 to the concrete `AVSpeechSynthesisVoice` identifier for the installed locale.
- Settings: default Voice 4; optional AU Voice 4 register; optional Personal Voice when `isPersonalVoice` available.
- Brand stays the source of what Metra sounds like; this plan stays the identity pointer.

---

## 6. Decision record

**Decision (operator 2026-08-29):** Provisional default speak identity is **Siri Voice 4**. Australian Siri Voice 4 is a same-family lower register alternate. Personal Voice is deferred as explicit opt-in only. No app implementation in this bite.

**Bing (2026-10-16):** Approve with editorial cleanup (metadata lines). Do not expand into AVSpeech/Settings implementation here. Ownership: Brand owns character → this plan locks voice identity → later bite owns synthesizer wiring.

---

## 7. Revision log

| Date | Change |
|------|--------|
| 2026-10-16 | Bing approve; split Status/Owner/Related/Not-this-plan metadata lines; status → approved; explicit handoff to Phase 2.1 for wiring. |
| 2026-08-29 | Provisional lock: Siri Voice 4 default; AU Voice 4 alternate; Personal Voice opt-in later. |
