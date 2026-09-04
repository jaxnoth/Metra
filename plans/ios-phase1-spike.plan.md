# Metra iOS Phase 1 spike (official)

**Status:** Phase 1 spike **smoke-passed** (2026-08-29); next = Phase 1.5 trial week  
**Parent:** [ios-companion-app.plan.md](ios-companion-app.plan.md)  
**Parallel (not a blocker):** [tailscale-identity-auth.plan.md](tailscale-identity-auth.plan.md)  
**Build machine:** IWU Mac `IWU75208-mac` (`100.101.163.18`) - Xcode 26.6 / Swift 6.3.3 verified  
**Code home:** `clients/ios` (bundle `app.metra.companion`, min iOS 18)

## Locked defaults

| Item | Choice |
|------|--------|
| Mode | Vision only |
| Auth | Ask-class Tailscale + Keychain stub `X-Metra-Device` (WhoIs mint later) |
| LocalAssist | Offline stub message only - never fake Ask |
| Lane | **Always Ops when online; offline → unavailable stub** (no heuristics) |
| Settings | `@AppStorage` for Ops URL, Vision mode, voice label |
| Transport | `AskClient` + `OpsAskClient` |
| Models | `Session` + `Message` with `sessionId` |

## Verified Ops Ask contract (2026-08-29 jumpbox)

| Field | Value |
|-------|--------|
| Method / path | `POST /api/ask` |
| Base URL (lab) | Operator Settings - e.g. `https://jumpbox.emerald-banana.ts.net` |
| Headers | `Content-Type: application/json; charset=utf-8`, `X-Metra-Client: ops-ios`, `X-Metra-Device: <stub>` |
| Body | `{ "prompt", "sessionId"?, "client": "ops-ios", "clientHint": "phone" }` |
| Response (key fields) | `message`, `sessionId`, `answered`, plus entry/handoff/engine metadata |

Loopback smoke on HQ returned HTTP 200 with `sessionId` and assistant `message`.

## Preconditions

1. Phone on Tailscale, same tailnet as Ops.
2. Safari on phone loads Ops URL (TLS) before app debug.
3. If Tailscale/Safari fails, fix network before SwiftUI.

## Done-when

See parent umbrella Phase 1 + Bing amendments. Proves: reach Ops, hold device token, render Attend, send Ask.

## Implementation status (2026-08-29)

| Item | Status |
|------|--------|
| `clients/ios` SwiftUI project (`app.metra.companion`) | Landed; synced to `~/Developer/Metra/clients/ios` |
| Attend / Ask / Settings (`@AppStorage`) | Landed |
| `AskClient` + `OpsAskClient` + Keychain stub | Landed |
| `xcodebuild` iOS Simulator | **BUILD SUCCEEDED** |
| Live `POST /api/ask` contract (HQ loopback) | Verified 200 + `sessionId`/`message` |
| Operator screenshots (Attend / Ask / Settings) | **Smoke passed** - Ask round-trip with Ops URL set; empty-URL banner correct before Settings |
| Offline Tailscale-off refusal | Optional leftover (operator) |
| Device token Settings preview | Optional leftover - tap Ensure stub token if still `(none)` |

Open on Mac: `open ~/Developer/Metra/clients/ios/MetraCompanion.xcodeproj`

## Phase 1.5 - trial week (next)

Use the Phase 1 app for about a week **before** voice work. Capture short notes:

- Did you open it? When (desk, waiting, driving-adjacent, on-call)?
- Ask quality over Tailscale - any TLS / reach flakes?
- Anything that blocked daily use (Settings friction, banner noise, Attend useless)?

**Out of 1.5:** STT/TTS, nine-face animation, WhoIs mint (parallel track), Bounded mode.

### Trial finding (2026-08-29 operator)

Separate **Attend** tab feels useless as a destination. Naming the home **Ask** is also wrong - the user is talking to **Metra**. **UI direction (lock for next shell bite):**

- **Default home = Metra** - one pane (presence + chat). No Attend tab, no Ask tab, no tab bar for the main surface.
- Face reacts to what you type or the turn (listening / speaking / warm attend).
- **Settings = gear mark only** (toolbar / corner), not a labeled Settings tab.
- When **voice-only** arrives (Phase 2+): presence may **grow** (larger face, less chrome) - still the same Metra pane.
- Internal/API language may still say Ops Ask / `AskClient`; user-facing chrome never says Ask.

Do not spend trial energy “using” Attend alone. Note open / chat patterns; face work follows this layout.

### Shell merge (2026-08-29)

**Done in tree:** single **Metra** home (RootTabView) = presence chrome + chat; Settings via gear only. No Attend/Ask tabs. Face mood: attend / listening / speaking from send state.

### Real face (2026-08-29)

**Done:** Starfish placeholder replaced with native SwiftUI nodes face (`MetraPresenceFaceView`) from `docs/assets/metra-presence-face.svg` **warm/attend**. Soft blink/lean when Reduce Motion is off. Nine-face controller still later.

## Revision log

| Date | Change |
|------|--------|
| 2026-08-29 | Official spike from Cursor plan; Bing amendments folded; Ask contract verified on live Ops. |
| 2026-08-29 | Phase 1 sources + xcodeproj landed; simulator build succeeded on IWU Mac. |
| 2026-08-29 | Operator smoke screenshots reviewed - Phase 1 **passed**; next = Phase 1.5 trial week. |
| 2026-08-29 | Trial finding: merge Attend into Ask pane (reactive presence); enlarge for voice-only later. Drop Attend-as-destination tab. |
| 2026-08-29 | User chrome: home is **Metra** (not Ask); no main-surface tabs; Settings = gear mark only. |
| 2026-08-29 | Shell merge landed: Metra home + gear Settings; tabs removed. |
| 2026-08-29 | Real nodes face (warm/attend) in PresenceChrome; synced + simulator build OK. |
