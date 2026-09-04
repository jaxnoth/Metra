# Plan: Metra iOS companion app (umbrella)

**Status:** Approved with minor amendments (Bing 2026-08-29)  
**Date:** 2026-08-29  
**Product:** Native iOS **Metra** app for the operator (phone). Client of the operator’s **Metra Ops host** over Tailscale - not a separate cloud Metra.  
**Brand:** Metra. Scout is a **parked** idea (possible Attention 2.0), not an approved subsystem and not the app name (see [scout.plan.md](scout.plan.md)).  
**Replaces (long-term):** Ani / Grok personal-assistant continuity on phone  
**Related contracts (locked or provisional):**

| Contract | Doc | Status |
|----------|-----|--------|
| Presence face / transitions | [ios-presence-behavior.plan.md](ios-presence-behavior.plan.md) | Approved |
| Conversation Desk / Company / Deliver | [ios-conversation-policy.plan.md](ios-conversation-policy.plan.md) | Approved |
| Speak identity | [ios-voice-identity.plan.md](ios-voice-identity.plan.md) | Provisional - Siri Voice 4 |
| Brand iOS vs Ops | [Brand.md](Brand.md) | iOS face OK; Ops desk faceless |
| Client identity auth | [tailscale-identity-auth.plan.md](tailscale-identity-auth.plan.md) | Approved direction - implement pending |
| Parked reach / phases | Future-Development “Metra iOS app”; Cursor plan `metra_ios_no-mac_ce17481e` | Parked pending Mac / reach |

**Not this plan:** Implementing Xcode today; shipping sibling apps in the Metra MSI; girlfriend-mode companions.

**Bing (2026-08-29):** Approve with minor amendments. Product definition, scope, architecture, sequencing, and boundaries rated strong; risk moderate; few missing decisions. Amendments below are folded into this document (including second-pass fold-in).

---

## 1. Product shape

One app, **two modes** (operator sketch 2026-08-27):

| Mode | Job | Conversation policy lean |
|------|-----|---------------------------|
| **Vision** (default v1) | Unbounded Metra conversation - Ani replacement; Metra personality; Capture forks | Company / Deliver / personal support as policy dictates |
| **Bounded** (later) | Explicit portfolio Metra on phone - route + evidence | Desk / DeskStrict |

Hard rule: do **not** merge Vision freedom into Ops desk Chat, and do **not** force every Vision turn through portfolio routing.

The app identity is **Metra**. Scout is parked and is not part of the shipping app identity.

**Centering scar (Bing):** Phone is a client of Metra. Phone is not a second Metra.

**Presence:** nodes face on iOS only (`warm/attend` hub). Ops HTML stays route geometry, no face.

**Voice:** listen + speak; default **Siri Voice 4**; presence node overlay for speech/listen; Personal Voice opt-in later.

**Backend:** operator Metra Ops host (`/api/ask`, capture/journal, profile) via Tailscale. Client header e.g. `X-Metra-Client: ops-ios` + `mode=vision|bounded`.

**Layering scar (keep):** Presence and voice do not own policy. Policy does not own TTS voice catalog.

---

## 2. Architecture (layers)

```
UI (SwiftUI)
  ├── PresenceView          ← ios-presence-behavior
  ├── Chat / Voice session
  └── Mode + settings
        ↓
ConversationController      ← ios-conversation-policy
  (intent → policy → execution → retentionClass)
        ↓
   ┌────┴────┐
   ↓         ↓
LocalAssist  Ask / Capture client   ← Ops host JSON APIs
(on-device)   (portfolio / Desk truth)
        ↓
Speech (STT/TTS)            ← ios-voice-identity (Siri Voice 4)
        ↓
PresenceRenderer            ← SVG/SwiftUI layers + speech overlay
```

Presence and voice do not own policy. Policy does not own TTS voice catalog.

### 2.1 Session authority (Bing amendment)

| Owner | Authoritative for |
|-------|-------------------|
| **Ops host** | Conversation history (durable), `retentionClass`, `turnId`, profile state, policy evaluations for Ops-routed turns |
| **iOS client** | Presentation state, voice playback state, local draft capture, transient UI preferences, **in-memory ephemeral relational episode** (see §2.4) |

The phone may cache for UX; it is never source of truth for durable conversation, profile, or Ops policy. On reconnect, host state wins for anything Ops-owned. Ephemeral relational turns never become Metra durable history by default ([ios-conversation-policy.plan.md](ios-conversation-policy.plan.md) §3.6).

### 2.2 Offline mode (Bing amendment + relational carve-out)

When Tailscale / Ops is unreachable:

| Capability | Behavior |
|------------|----------|
| Capture / journal draft | Allowed - queue locally as pending |
| **Ops Ask** (portfolio / Desk / evidence) | Unavailable (fail closed; no fake Ops replies) |
| **Local relational** (`companionship`, `support_*` per policy) | Allowed via on-device LocalAssist when available; still ephemeral; intimacy ceiling still applies |
| Presence | Stay in warm / Attend (no invented moods) |
| Policy / profile (Ops) | Unchanged until host reconnects |

Screens must not invent divergent **Ops Ask** offline behavior. Relational offline is not “fake Ask” - it is the existing ephemeral / local-first path ([ios-conversation-policy.plan.md](ios-conversation-policy.plan.md) §3.6–§3.7).

### 2.3 Device auth (Bing amendment - Phase 1; Tailscale identity Decision 2026-08-29)

Even with Tailscale-only reach:

- **Identity:** Ops authorizes the phone via **Tailscale WhoIs** (login / node / tags) against a host allowlist. Do not paste a shared Ask key; do not derive a second “common secret” from Tailscale.
- **Device token:** On first Tailscale-proven pair, Ops **mints** a device capability token; store in **Keychain**; attach to Ops requests.
- Host may reject unknown identities and revoked / unknown device tokens.
- Same pairing model as Satellite profile sync target state - see [tailscale-identity-auth.plan.md](tailscale-identity-auth.plan.md).

Goal: revoke an old phone without redesigning auth or rediscovering a lost paste string. Not a public internet threat model for v1.

### 2.4 Local relational vs Ops Ask (operator 2026-08-29)

Not every Vision turn needs portfolio routing. Relational turns are still Metra-as-companion, not a second brain.

| Lane | Examples | Execution | Retention |
|------|----------|-----------|-----------|
| **Ops Ask** | Desk work, portfolio facts, tickets, Bounded evidence, Deliver that needs host tools | Ops `/api/ask` (online only) | `normal` (or policy default) |
| **Local relational** | Check-in, companionship, `support_*` personal support, warm Company with no Ops tools | On-device LocalAssist (Apple Intelligence / local model) when available | `ephemeral` - not Metra durable store |
| **Capture draft** | “Remember this for later” | Queue on phone; flush to Ops when online | Pending → host on sync |

**Rules:**

1. Intent classifier (conversation policy) chooses lane **before** calling Ops.
2. Local relational must not invent ticket/Ops facts or claim Host Apply succeeded.
3. Intimacy ceiling and refuse bands still apply on-device.
4. On reconnect, Ops history wins for durable threads; ephemeral relational episodes stay wiped per policy episode boundaries unless the user explicitly promotes a draft.
5. UI may label local-only turns lightly (“On device”) once - not every bubble.

This preserves: phone is a client of Metra; relational continuity does not require Tailscale.

---

## 3. Phased roadmap

### Phase 0 - Reach without native (optional, already sketched)

- Phone **Ops PWA** / Safari against Metra Ops over Tailscale.
- Prove ask + capture JSON from phone.
- No nodes face required.
- **Skip if** work Mac + Xcode is available and you prefer native-first.

### Phase 0.5 - Identity sync (was: Profile continuity)

- Ops profile export/import over Tailscale (`GET /api/profile/export` + Mac import).
- So phone and desk share operator prefs without Notion-as-truth.
- Renamed (Bing): phase is about identity continuity, not only prefs file shape.

### Phase 1 - Native shell (first real app bite)

**Done-when:**

- Xcode project (SwiftUI) on IWU work Mac (or approved Mac fallback).
- App talks to Ops host over Tailscale (ask + sessionId).
- **Device registration token** in Keychain; host rejects unknown devices.
- Shows **MARK → warm/attend** presence (static poses OK).
- Text Vision chat round-trip with Metra persona (unbounded) when online.
- Offline: Ops Ask unavailable; capture may queue; **Local relational allowed** if on-device path exists (stub OK if LocalAssist not wired yet - then say offline plainly for relational too).
- Settings stub: host URL, mode Vision, voice = Siri Voice 4 label.

**Out of Phase 1:** full nine-face animation, Bounded mode, Deliver polish, OCR / image upload / embeddings / capture inbox / reasoning views, ephemeral cloud routing matrix, App Store.

Resist expanding Phase 1 until it survives daily use (see Phase 1.5).

### Phase 1.5 - Mobile operator trial (Bing amendment)

**Between Phase 1 and Phase 2.** Goal: use the Phase 1 app yourself for about a week before voice.

Learn: Did you open it? When (driving, waiting rooms, airport, on-call)? Companion usage pattern matters more than tech polish.

No voice work until this trial produces notes (even short).

### Phase 2 - Voice listen / speak

- Hands-free listen while driving (parked ladder item).
- TTS via Siri Voice 4; STT → ask **or** LocalAssist per lane.
- Presence listen/speech overlays per presence Appendix A (can start with rest/mid/closed only).

### Phase 3 - Presence behavior controller

- Full mood/variant catalog + hub rules from presence plan.
- Cue wiring from conversation policy (non-normative presence map).

### Phase 4 - Conversation policy engine

- Desk / Company / Deliver / DeskStrict.
- Intimacy ceiling + `support_*` + retentionClass ephemeral path + **executionTarget** (`local` | `ops`).
- Per-turn re-eval, locks, silence caps, stale turnId.
- **First:** policy **telemetry only** (Bing) - log e.g. `{ "policy":"Company", "reason":"work-topic", "confidence":0.82, "executionTarget":"ops" }` and observe. Enforce after observation, not before.

### Phase 5 - Bounded mode + Capture depth

- Explicit Bounded UX.
- Capture / journal continuity; operational forks without killing Vision.

### Phase 6 - Hardening / distribution

- Backgrounding, incident DeskStrict, reduced motion.
- TestFlight; signing; Mac satellite distribution remains separate/parked.

---

## 4. Prerequisites (blockers)

| Need | Why | Status (2026-08-29) |
|------|-----|---------------------|
| **Mac with Xcode** (IWU work Mac) | Native iOS app | **Verified** on `iwu75208-mac` / `IWU75208-mac` (`100.101.163.18`). Operator paste: macOS **26.6.2** (25G83), Xcode **26.6** (17F113), Swift **6.3.3** arm64, `xcode-select` → `/Applications/Xcode.app/Contents/Developer`. Shell user `stephen.swan`; cwd showed existing `Metra` folder. |
| Jumpbox SSH to Mac | Optional remote verify / agent help | **Works** (2026-08-29): key auth `stephen.swan@100.101.163.18` from jumpbox (`id_ed25519` in Mac `authorized_keys`). Jumpbox `known_hosts` ACL fixed; Mac host key merged. **Tailscale SSH:** Mac has App Store / sandboxed Tailscale - `sudo tailscale set --ssh` reports SSH server does not run in sandboxed GUI builds. Need standalone Tailscale pkg for Tailscale SSH, or keep classic SSH. |
| Metra Ops host reachable on phone (Tailscale) | Ask/Capture APIs | Confirm when phone testing |
| Stable `/api/ask` (+ capture/journal as needed) | Already mostly shipped for Ops | Assumed available on Ops host |
| Operator Apple ID / signing for device runs | Device install | Operator-side |
| Device registration API on Ops | Phase 1 Keychain token | Design in Phase 1 spike - not shipped yet |

**Remote reach:** Tailscale peer online; classic SSH from jumpbox OK. **Tooling proof:** operator Terminal paste - Xcode/Swift ready.

Working jumpbox smoke test (key auth, no password):

```powershell
ssh stephen.swan@100.101.163.18 "hostname"
```

Password prompts mean the client is not offering the jumpbox `id_ed25519` (or that pubkey is missing from Mac `~/.ssh/authorized_keys`). Add the client pubkey, or SSH from the jumpbox.

**Tailscale SSH (optional):** uninstall/replace Mac App Store Tailscale with the [standalone macOS pkg](https://tailscale.com/download/mac), then `sudo tailscale set --ssh`. Classic SSH is enough for Phase 1.

No Mac → stay on Phase 0 PWA or pause native; do not pretend Windows Cursor can ship the `.ipa`.

---

## 5. What we already decided (do not reopen casually)

- Nine presence faces; Attend hub; Playful via wave; incident → Attend.
- Desk / Company / Deliver; DeskStrict; intimacy ceiling; ephemeral personal support.
- Siri Voice 4 provisional default.
- Vision ≠ desk Chat lane.
- Ani Notion bridge is transitional - not sprint truth.
- **Phone is a client of Metra. Phone is not a second Metra.**
- Presence and voice do not own policy; policy does not own TTS catalog.
- Ops host owns durable session/history/policy/profile; phone owns presentation/playback/drafts/UI prefs + ephemeral relational episode memory only.
- **Ops Ask vs Local relational:** portfolio/Desk truth → Ops; companionship / `support_*` → LocalAssist (ephemeral); do not force relational through portfolio routing.
- Tailscale-only for v1 (no public relay).
- Client auth = Tailscale identity (+ optional host-minted device token). No pasteable shared Ask/sync secret as the happy path.
- Native-first for Phase 1 (skip Phase 0 if Mac stays available).
- Min iOS **18+** (personal operator tool - support burden over install base).
- iOS code lives under `Metra/clients/ios` or a sibling `Metra-iOS` repo - not scattered through Ops host trees.

---

## 6. What is next (recommended order)

1. ~~Mac on Tailscale~~ / ~~Xcode proof~~ / ~~Bing umbrella review~~ - **done** (2026-08-29).
2. ~~Phase 1 spike plan~~ - [ios-phase1-spike.plan.md](ios-phase1-spike.plan.md).
3. ~~Phase 1 implement + smoke~~ - **done** (2026-08-29): simulator build + operator screenshots (Attend / Ask / Settings); live Ask OK.
4. **Phase 1.5 trial week** - daily use notes before voice (see spike plan). Optional: offline refusal smoke; Ensure stub token if Settings still shows `(none)`.
   - **UI scar (2026-08-29):** ~~next shell = single Metra home~~ **landed** - presence + chat; gear Settings; no Attend/Ask tabs. Face scales up for voice-only later. User chrome never says Ask.
5. Parallel (not blocking trial): Tailscale WhoIs / device mint ([tailscale-identity-auth.plan.md](tailscale-identity-auth.plan.md)).
6. After 1.5 notes: Phase 2 voice (only if trial says the shell is worth it) - presence grows in-pane for voice-only.

---

## 7. Non-goals (umbrella)

- No App Store launch in Phase 1–2.
- No embedding TicketTracker/Orion inside the iOS binary.
- No romance / sexual companion features.
- No Ops desk facial presence.
- No depending on Ani Notion as source of truth.
- No “wire” language implying the app already exists.
- No second brain on the phone (client only - LocalAssist is companion lane, not portfolio authority).

---

## 8. Open questions for operator

1. ~~Xcode on IWU Mac~~ - verified.
2. ~~Native-first vs PWA~~ - **native-first** (Bing + operator lean).
3. ~~Exact path~~ - **`Metra/clients/ios`** (Mac: `~/Developer/Metra/clients/ios`).
4. ~~Min iOS~~ - **18+**.
5. ~~Tailscale-only v1~~ - **yes**.
6. ~~Jumpbox known_hosts ACL~~ - done. Tailscale SSH optional via standalone pkg only.
7. ~~Bundle id~~ - **`app.metra.companion`**. Device registration mint stays stub until [tailscale-identity-auth.plan.md](tailscale-identity-auth.plan.md) ships.
8. ~~LocalAssist v1~~ - **defer stub** (offline unavailable message only).

---

## 9. Revision log

| Date | Change |
|------|--------|
| 2026-08-29 | Umbrella plan: unify parked iOS phases with presence, conversation policy, and Siri Voice 4; define next = Mac path + Phase 1 spike. |
| 2026-08-29 | Mac Tailscale reach confirmed (`iwu75208-mac`); SSH from jumpbox blocked. |
| 2026-08-29 | **Xcode verified** via operator paste: macOS 26.6.2, Xcode 26.6, Swift 6.3.3; Phase 1 tooling unblocked. |
| 2026-08-29 | Jumpbox classic SSH to Mac works (`stephen.swan@100.101.163.18`); dedicated `metra_known_hosts` because default known_hosts ACL denies write. |
| 2026-08-29 | Jumpbox `known_hosts` ACL fixed + Mac host key merged; plain `ssh` key auth OK. Tailscale SSH blocked on sandboxed/App Store Tailscale - classic SSH is the path. |
| 2026-08-29 | **Bing: Approve with minor amendments.** Folded: session authority, offline contract, Phase 1 device token, Phase 0.5 rename (Identity sync), Phase 1.5 operator trial, Phase 4 policy telemetry-first, open Qs (native-first, iOS 18+, Tailscale-only, clients/ios), centering scar “phone is not a second Metra.” Status → Approved with minor amendments. |
| 2026-08-29 | Client auth direction: Tailscale WhoIs + allowlist (+ optional host-minted device token). Linked `tailscale-identity-auth.plan.md` and Decision 2026-08-29. |
| 2026-08-29 | Bing second-pass fold-in (operator paste). Added §2.4 Local relational vs Ops Ask; offline carve-out for companionship/`support_*`; architecture shows LocalAssist beside Ops Ask. |
| 2026-08-29 | Phase 1 spike official: [ios-phase1-spike.plan.md](ios-phase1-spike.plan.md). Locked path/bundle/LocalAssist stub/always-Ops lane; live Ask contract verified. |
| 2026-08-29 | Phase 1 smoke passed (operator screenshots). Next = Phase 1.5 trial week before voice. |
| 2026-08-29 | Trial finding: Attend-as-tab useless. Next shell = Ask+presence single pane; face scales up for voice-only. |
| 2026-08-29 | User chrome: home is **Metra** (not Ask); no main tabs; Settings = gear mark only. |
| 2026-08-29 | Shell merge landed in clients/ios (Metra home + gear). |
| 2026-09-03 | Brand: iOS app stays **Metra**. Scout parked (not an approved subsystem; may become Attention 2.0) - [scout.plan.md](scout.plan.md). |
