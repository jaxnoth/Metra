# Metra Ops iOS client

SwiftUI shell: single **Metra** home (presence + chat); Settings via gear. Ops Ask API over Tailscale.

**Plans:** [ios-companion-app.plan.md](../../plans/ios-companion-app.plan.md) (umbrella), [ios-phase1-spike.plan.md](../../plans/ios-phase1-spike.plan.md), [ios-conversation-policy.plan.md](../../plans/ios-conversation-policy.plan.md)

## Install lanes (Phase 1.6)

| Lane | Status | Use when |
|------|--------|----------|
| **Weekly reinstall** (1.6a) | **Active interim** | Keep Personal Team install alive (~7-day expiry) via `build-mac01` |
| **Xcode Run** | Active | Feature work, debugger |
| **TestFlight** (1.6b) | **Parked** | After Apple Developer Program is paid (card required; Apple Pay does not cover Program fee) |

Honesty: weekly reinstall is a **Mac-tethered treadmill**, not durable off-network install. Prefer TestFlight when Program enrollment is possible again.

### Weekly reinstall (1.6a)

On **iwu75208-mac** (`100.101.163.18`, user `stephen.swan`) with GUI login and unlocked keychain:

```bash
cd ~/Developer/Metra/clients/ios
chmod +x scripts/Rebuild-MetraCompanion-Device.sh
./scripts/Rebuild-MetraCompanion-Device.sh --list-devices
# Optional: export METRA_IOS_UDID=<udid>
./scripts/Rebuild-MetraCompanion-Device.sh
```

SSH from HQ: `ssh stephen.swan@100.101.163.18`

Schedule (every 5 days = 432000 seconds):

```bash
cp scripts/com.metra.companion.weekly-reinstall.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.metra.companion.weekly-reinstall.plist
launchctl enable gui/$(id -u)/com.metra.companion.weekly-reinstall
launchctl kickstart -k gui/$(id -u)/com.metra.companion.weekly-reinstall
```

Logs: `~/Library/Logs/MetraCompanion/weekly-reinstall.log`

**Hard requirements**

- Phone paired when the job runs; unlock for DDI mount.
- Logged-in Mac GUI session - SSH-only codesign fails with `errSecInternalComponent`. Prefer `~/prove-metra` or Terminal on the Mac (HQ can launch via `osascript` → Terminal).
- Personal Team signing still configured on the target (`DEVELOPMENT_TEAM` in the Xcode project).
- **Wireless is not reliable auto-connect** (Xcode 26 dropped the "Connect via network" checkbox). Same Wi-Fi helps; device still goes `unavailable` asleep/locked/away. Prefer USB for weekly prove. If wireless is needed: Window → Devices and Simulators → Control-click SwanMobile → **Pair**, or **Connect via IP Address**. Keep phone unlocked / Auto-Lock Never during the install.
- SwanMobile hardware UDID: `00008130-0009142834F2001C` (set `METRA_IOS_UDID` if auto-detect picks wrong device). CoreDevice id differs (`777D10D4-…`) - rebuild script uses the hardware UDID.

Unload: `launchctl bootout gui/$(id -u)/com.metra.companion.weekly-reinstall`

### TestFlight (1.6b - parked)

When a payment card is available:

1. Enroll Individual at [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/) ($99/yr). Prefer **web** if the Developer app says enrollment is not available. Apple Pay / store credit do **not** pay for Program membership.
2. Xcode → paid team; Archive → App Store Connect → Internal Testing.
3. Install from TestFlight on the phone; smoke Ask over Tailscale.
4. Unload the weekly LaunchAgent.

Bump `CURRENT_PROJECT_VERSION` on every TestFlight upload. Keep `MARKETING_VERSION` at `0.1.x` until a deliberate cut.

## Voice (Phase 2.1)

- Toolbar waveform toggles **voice layout** (large face + mic).
- Tap mic → speak → tap again to stop → Vision Ask (`posture=Company`, max personality) → spoken reply (Siri Voice 4 / best female enhanced English voice).
- Settings: Speak replies (default on), Speak voice picker (**Metra / Voice 4** vs **System default**), Preview, resolved-voice note. Mic + speech recognition permission prompts required.
- System default ≈ Spoken Content / language voice (Apple does not expose the exact Siri & Search pick to apps).
- If Metra mode sounds male/robotic: install **Siri Voice 4** (enhanced) under iOS Settings → Accessibility → Spoken Content → Voices, then Preview.
- Rebuild on Mac after pull: `~/prove-metra` (GUI Terminal / unlocked keychain).

## Formal verify (do this before blaming the phone)

Non-UI failures (auth, Serve, Vision envelope, hung Ask worker, missing mic privacy keys) must fail on HQ / Mac gates first - not during phone UI smoke.

**Orchestrator (preferred):**

```powershell
# HQ: Reach only (fail-closed)
pwsh -File .\clients\ios\scripts\Invoke-MetraIosGate.ps1

# HQ: Reach, then SSH Mac sim smoke, then kick GUI device prove
pwsh -File .\clients\ios\scripts\Invoke-MetraIosGate.ps1 -SimSmoke -DeviceProve
```

| Gate | Where | Command / marker |
|------|--------|------------------|
| **Reach** (Serve + Vision Ask) | Jumpbox HQ | `Invoke-MetraIosReachVerify.ps1` → `VERIFY_OK` |
| **Sim smoke** (build/install/launch + privacy plist) | iwu75208-mac | `Invoke-MetraIosSimSmoke.sh` → `SIM_SMOKE_OK` |
| **Device prove** | iwu75208-mac GUI Terminal | `~/prove-metra` → `BUILD SUCCEEDED` + install finished |
| **UI smoke** (operator) | Phone | Unlock, Trust if needed, text Ask + optional mic |

Pester scars (HQ): Ops Ask sync worker (no hung BeginInvoke), Vision `cursor_*` ValidateSet round-trip, iOS gate scripts + mic/speech Info.plist keys - covered under `Ops Ask sidecar stability (reach)` in `tests/Metra.Tests.ps1`.

Reach must print `VERIFY_OK` before device testing. If you see `cursor_auth_error` / `ask-engine` FAIL:

```powershell
.\metra.ps1 ask key set <CURSOR_API_KEY>
# then re-run Invoke-MetraIosGate.ps1
```

Settings → Check Ops reach on the phone should match `/api/meta` (`degradedCode` shows Cursor auth failures).

## Defaults

| Item | Value |
|------|--------|
| Bundle id | `app.metra.companion` |
| Min iOS | 18.0 |
| Client header | `X-Metra-Client: ops-ios` |
| Device header | `X-Metra-Device: <Keychain stub>` |
| Ask | `POST /api/ask` (Vision + Company posture) |
| Lane | Always Ops when online; offline stub only |

## HQ vs this Mac

- Jumpbox remains Metra HQ (multi-root workspace, persona, Ops Host).
- Mac satellite **iwu75208-mac** (`100.101.163.18`, `stephen.swan`) is the Swift station / weekly reinstall (and later archive + TestFlight upload) station. (Older notes said `build-mac01` / `operator@100.64.1.10` - that peer is gone.)
- **Permanent Cursor Agent** runs on that Mac - prefer it for GUI Xcode / codesign prove and LaunchAgent load. HQ can SSH (`stephen.swan@100.101.163.18`) to land files; Agent on Mac should run rebuilds that need an unlocked login keychain.

## Open on Mac

```bash
open ~/Developer/Metra/clients/ios/MetraCompanion.xcodeproj
```

`MetraCompanion.xcodeproj` is checked in (XcodeGen optional). Simulator build verified 2026-08-29.

## Settings

Operator enters Ops **HTTPS** MagicDNS/Serve URL (e.g. `https://jumpbox.hq.example.ts.net`). Stored in `@AppStorage`. Plain `http` is rejected before send (matches ATS).

**Vision Ask:** always sends `contractVersion=1` / `mode=vision` so Ops hits the Vision identity stack (same Cursor persona packs when installed on HQ). `context.teachingWanted` is hardcoded `false` in v1 (no teaching UI). Vision Company still loads teaching-gentle when the pack file is present on HQ.

Error codes from Vision (`write_not_allowed`, `route_boundary_violation`, ...) surface as visible banners - never silent.

### Mac rebuild after HQ Vision stack changes

1. Pull / sync Metra on the Mac satellite checkout.
2. Open `MetraCompanion.xcodeproj` and Run to the paired iPhone, **or** run `./scripts/Rebuild-MetraCompanion-Device.sh`.
3. Confirm Ops URL still valid in Safari.
4. Smoke: casual chat should feel like Cursor Metra (humor when pack installed on jumpbox).

## Trial reliability (Phase 1.5)

- Reachability: no `NWPathMonitor` preflight - `URLSession` is the authority; map connectivity `URLError`s to the offline result.
- Background: entering `.background` does **not** cancel an in-flight Ask (Cancel / New still do). Ephemeral episodes end and `activeTurn` is cleared so a late HTTP completion cannot display (stale-route drop).
- Presence SVG under `docs/assets/` is reference only; the app ships the native SwiftUI face, not a bundled SVG.

## Conversation policy (Desk / Company / Deliver)

Normative plan: [plans/ios-conversation-policy.plan.md](../../plans/ios-conversation-policy.plan.md).

- Monotonic `turnId` + stale-route drop when a late reply no longer matches the active turn.
- `retentionClass` / `executionTarget` on the policy envelope are normative (not CE `retentionLane` posture aliases).
- Spark-or-quiet + seam/resume gates live under `Models/`; presence consumes policy events only (`PresenceCueMap`).
- LocalAssist relational path is not answering yet - Ops remains the online lane; honest offline / no-compliant-route messages come from the host.

## Preconditions

1. Phone on Tailscale, same tailnet as Ops.
2. Safari on phone loads Ops URL before debugging the app.

## Install on your iPhone (Xcode Run)

1. Unlock the paired iPhone, plug into the build Mac (or stay paired wirelessly), tap **Trust** if asked.
2. On the Mac, open `MetraCompanion.xcodeproj`.
3. **Xcode → Settings → Accounts** → Apple ID → Personal Team (until Program is paid).
4. Target **Signing & Capabilities** → Automatically manage signing → Team. Bundle id `app.metra.companion`.
5. Destination: paired iPhone. Press **Run** (▶) from GUI Xcode.
6. First time: **Settings → General → VPN & Device Management** → trust the developer certificate if prompted.
7. In the app gear: set Ops URL (HTTPS MagicDNS that works in Safari). Tailscale up on the phone.
