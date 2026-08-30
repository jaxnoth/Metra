# Metra Ops iOS client (Phase 1 spike)

SwiftUI shell: single **Metra** home (presence + chat); Settings via gear. Ops Ask API over Tailscale.

**Plan:** [docs/ios-phase1-spike.plan.md](../../docs/ios-phase1-spike.plan.md)

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

Operator enters Ops **HTTPS** MagicDNS/Serve URL (e.g. `https://jumpbox.emerald-banana.ts.net`). Stored in `@AppStorage`. Plain `http` is rejected before send (matches ATS).

## Trial reliability (Phase 1.5)

- Reachability: no `NWPathMonitor` preflight - `URLSession` is the authority; map connectivity `URLError`s to the offline result.
- Background: entering `.background` does **not** cancel an in-flight Ask (Cancel / New still do).
- Presence SVG under `docs/assets/` is reference only; the app ships the native SwiftUI face, not a bundled SVG.

## Preconditions

1. Phone on Tailscale, same tailnet as Ops.
2. Safari on phone loads Ops URL before debugging the app.

## Install on your iPhone (first trial)

1. Unlock **SwanMobile**, plug into the IWU Mac (or stay paired wirelessly), tap **Trust** if asked.
2. On the Mac, Xcode should be open on `MetraCompanion.xcodeproj` (or run `open ~/Developer/Metra/clients/ios/MetraCompanion.xcodeproj`).
3. **Xcode → Settings → Accounts** → add your Apple ID if missing → select the account → **Manage Certificates** → ensure a **Apple Development** cert exists (Personal Team is fine for a trial).
4. Select the **MetraCompanion** target → **Signing & Capabilities** → enable **Automatically manage signing** → Team **Stephen Swan (Personal Team)** (`DEVELOPMENT_TEAM` `642GT45K9V` in the pbxproj). Do not use the cert OU `5MXN892DDB` as the team id. Leave bundle id `app.metra.companion`.
5. Destination menu (toolbar): pick **SwanMobile** (not a simulator).
6. Press **Run** (▶) from Xcode on the Mac (GUI). Headless `xcodebuild` over SSH often fails codesign with `errSecInternalComponent` when the login keychain is locked. First time on phone: **Settings → General → VPN & Device Management** → trust the developer certificate, then Run again if needed.
7. If a portfolio sync cleared Team, re-select Personal Team in Signing (or confirm `DEVELOPMENT_TEAM = 642GT45K9V` in the pbxproj) before Run.
7. In the app gear: set Ops URL (same HTTPS MagicDNS that works in Safari on the phone, e.g. `https://jumpbox.emerald-banana.ts.net`). Ensure **Tailscale** is up on the phone.

Trial focus: open Metra daily, chat, note flakes - not Attend-as-a-tab.
