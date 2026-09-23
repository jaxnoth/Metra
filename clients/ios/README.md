# Metra Ops iOS client (Phase 1 spike)

SwiftUI shell: single **Metra** home (presence + chat); Settings via gear. Ops Ask API over Tailscale.

**Plan:** [plans/ios-phase1-spike.plan.md](../../plans/ios-phase1-spike.plan.md)

## Defaults

| Item | Value |
|------|--------|
| Bundle id | `app.metra.companion` |
| Min iOS | 18.0 |
| Client header | `X-Metra-Client: ops-ios` |
| Device header | `X-Metra-Device: <Keychain stub>` |
| Ask | `POST /api/ask` |
| Lane | Always Ops when online; offline stub only |

## HQ vs this Mac

- Jumpbox remains Metra HQ (multi-root workspace, persona, Ops Host).
- This Mac is a Swift station / Metra satellite only.

## Open on Mac

```bash
open ~/Developer/Metra/clients/ios/MetraCompanion.xcodeproj
```

`MetraCompanion.xcodeproj` is checked in (XcodeGen optional). Simulator build verified 2026-08-29.

## Settings

Operator enters Ops **HTTPS** MagicDNS/Serve URL (e.g. `https://jumpbox.hq.example.ts.net`). Stored in `@AppStorage`. Plain `http` is rejected before send (matches ATS).

**Vision Ask:** always sends `contractVersion=1` / `mode=vision` so Ops hits the Vision identity stack (same Cursor persona packs when installed on HQ). `context.teachingWanted` is hardcoded `false` in v1 (no teaching UI). Vision Company still loads teaching-gentle when the pack file is present on HQ.

Error codes from Vision (`write_not_allowed`, `route_boundary_violation`, …) surface as visible banners - never silent.

### Mac rebuild after HQ Vision stack changes

1. Pull / sync Metra on the Mac satellite checkout.
2. Open `MetraCompanion.xcodeproj` and Run to the paired iPhone.
3. Confirm Ops URL still valid in Safari.
4. Smoke: casual chat should feel like Cursor Metra (humor when pack installed on jumpbox).

## Trial reliability (Phase 1.5)

- Reachability: no `NWPathMonitor` preflight - `URLSession` is the authority; map connectivity `URLError`s to the offline result.
- Background: entering `.background` does **not** cancel an in-flight Ask (Cancel / New still do).
- Presence SVG under `docs/assets/` is reference only; the app ships the native SwiftUI face, not a bundled SVG.

## Preconditions

1. Phone on Tailscale, same tailnet as Ops.
2. Safari on phone loads Ops URL before debugging the app.

## Install on your iPhone (first trial)

1. Unlock the paired iPhone, plug into the build Mac (or stay paired wirelessly), tap **Trust** if asked.
2. On the Mac, Xcode should be open on `MetraCompanion.xcodeproj` (or run `open ~/Developer/Metra/clients/ios/MetraCompanion.xcodeproj`).
3. **Xcode → Settings → Accounts** → add your Apple ID if missing → select the account → **Manage Certificates** → ensure a **Apple Development** cert exists (Personal Team is fine for a trial).
4. Select the **MetraCompanion** target → **Signing & Capabilities** → enable **Automatically manage signing** → Team **Personal Team** (set `DEVELOPMENT_TEAM` in the pbxproj to your team id). Leave bundle id `app.metra.companion`.
5. Destination menu (toolbar): pick the paired iPhone (not a simulator).
6. Press **Run** (▶) from Xcode on the Mac (GUI). Headless `xcodebuild` over SSH often fails codesign with `errSecInternalComponent` when the login keychain is locked. First time on phone: **Settings → General → VPN & Device Management** → trust the developer certificate, then Run again if needed.
7. If a portfolio sync cleared Team, re-select Personal Team in Signing before Run.
8. In the app gear: set Ops URL (same HTTPS MagicDNS that works in Safari on the phone, e.g. `https://jumpbox.hq.example.ts.net`). Ensure **Tailscale** is up on the phone.

Trial focus: open Metra daily, chat, note flakes - not Attend-as-a-tab.
