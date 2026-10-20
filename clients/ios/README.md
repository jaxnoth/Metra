# Metra Ops iOS client

SwiftUI shell: single **Metra** home (presence + chat); Settings via gear. Ops Ask API over Tailscale.

**Plans:** [ios-companion-app.plan.md](../../plans/ios-companion-app.plan.md) (umbrella), [ios-phase1-spike.plan.md](../../plans/ios-phase1-spike.plan.md), [ios-conversation-policy.plan.md](../../plans/ios-conversation-policy.plan.md)

Operator station facts (Mac hostname, Tailscale address, phone UDID, Apple Team ID) stay in gitignored local notes - copy [docs/station.local.example.md](docs/station.local.example.md) to `docs/station.local.md` and fill in. Gate URLs/SSH: `%LOCALAPPDATA%\Metra\ios-gate.local.json` from [scripts/ios-gate.local.example.json](scripts/ios-gate.local.example.json).

## Install lanes (Phase 1.6)

| Lane | Status | Use when |
|------|--------|----------|
| **Weekly reinstall** (1.6a) | **Active interim** | Keep Personal Team install alive (~7-day expiry) via Mac rebuild job |
| **Xcode Run** | Active | Feature work, debugger |
| **TestFlight** (1.6b) | **Parked** | After Apple Developer Program is paid (card required; Apple Pay does not cover Program fee) |

Honesty: weekly reinstall is a **Mac-tethered treadmill**, not durable off-network install. Prefer TestFlight when Program enrollment is possible again.

### Weekly reinstall (1.6a)

On the **Mac build station** (GUI login, unlocked keychain):

```bash
cd ~/Developer/Metra/clients/ios   # or your checkout path
chmod +x scripts/Rebuild-MetraCompanion-Device.sh
./scripts/Rebuild-MetraCompanion-Device.sh --list-devices
# Optional: export METRA_IOS_UDID=<hardware-udid>
./scripts/Rebuild-MetraCompanion-Device.sh
```

Prefer `~/prove-metra` (symlink to `scripts/prove-1.6a.sh`) so the LaunchAgent is rendered from this checkout.

Schedule: `prove-1.6a.sh` installs a checkout-local LaunchAgent (every 5 days = 432000 seconds). Do not copy the checked-in example plist blindly - it uses placeholders.

Logs: `~/Library/Logs/MetraCompanion/weekly-reinstall.log`

**Hard requirements**

- Phone paired when the job runs; unlock for DDI mount.
- Logged-in Mac GUI session - SSH-only codesign fails with `errSecInternalComponent`.
- Personal Team signing configured locally (`DEVELOPMENT_TEAM` via Xcode or gitignored `Config/Local.xcconfig` - never commit a real Team ID).
- Prefer USB for weekly prove. Wireless pairing is flaky when the phone sleeps.
- Set `METRA_IOS_UDID` when auto-detect picks the wrong device.

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
- Speech recognition defaults to **on-device**. Settings → Allow cloud speech recognition is opt-in only (Apple cloud STT).
- Settings: Speak replies (default on), Speak voice picker (**Metra / Voice 4** vs **System default**), Preview, resolved-voice note. Mic + speech recognition permission prompts required.
- Rebuild on Mac after pull: `~/prove-metra` (GUI Terminal / unlocked keychain).

## Formal verify (do this before blaming the phone)

Non-UI failures (auth, Serve, Vision envelope, hung Ask worker, missing mic privacy keys) must fail on HQ / Mac gates first - not during phone UI smoke.

**Orchestrator (preferred):**

```powershell
# HQ: Reach only (fail-closed). Ops URL from ios-gate.local.json or -OpsBaseUrl.
pwsh -File .\clients\ios\scripts\Invoke-MetraIosGate.ps1

# HQ: Reach, then SSH Mac sim smoke, then kick GUI device prove
# Requires MacSsh in ios-gate.local.json; SSH uses StrictHostKeyChecking=yes.
pwsh -File .\clients\ios\scripts\Invoke-MetraIosGate.ps1 -SimSmoke -DeviceProve
```

| Gate | Where | Command / marker |
|------|--------|------------------|
| **Reach** (Serve + Vision Ask) | Jumpbox HQ | `Invoke-MetraIosReachVerify.ps1` → `VERIFY_OK` |
| **Sim smoke** (build/install/launch + privacy plist) | Mac build station | `Invoke-MetraIosSimSmoke.sh` → `SIM_SMOKE_OK` |
| **Device prove** | Mac GUI Terminal | `~/prove-metra` → `BUILD SUCCEEDED` + install finished |
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
| Device header | `X-Metra-Device: <Keychain stub or host-minted>` |
| Ask | `POST /api/ask` (Vision + Company posture) |
| Lane | Always Ops when online; offline stub only |

## HQ vs Mac satellite

- Jumpbox remains Metra HQ (multi-root workspace, persona, Ops Host).
- A Mac satellite with Xcode is the Swift / weekly-reinstall station. Put concrete host and SSH identity only in local notes / `ios-gate.local.json`.
- Prefer a Cursor Agent session on that Mac for GUI codesign prove. HQ may SSH for file land only after host keys are verified (`StrictHostKeyChecking=yes`).

## Open on Mac

```bash
open ~/Developer/Metra/clients/ios/MetraCompanion.xcodeproj
```

`MetraCompanion.xcodeproj` is checked in (XcodeGen optional). Simulator build verified 2026-08-29.

## Settings

Operator enters Ops **HTTPS** MagicDNS/Serve URL (e.g. `https://hq.example.ts.net`). Stored in `@AppStorage`. Plain `http` is rejected before send (matches ATS).

**Device identity:** Pair with Ops stores a host-minted token in Keychain. Settings shows only a masked suffix - never the full bearer.

**Vision Ask:** always sends `contractVersion=1` / `mode=vision` so Ops hits the Vision identity stack (same Cursor persona packs when installed on HQ). `context.teachingWanted` is hardcoded `false` in v1 (no teaching UI). Vision Company still loads teaching-gentle when the pack file is present on HQ.

Error codes from Vision (`write_not_allowed`, `route_boundary_violation`, ...) surface as visible banners - never silent.

### Mac rebuild after HQ Vision stack changes

1. Pull / sync Metra on the Mac satellite checkout.
2. Open `MetraCompanion.xcodeproj` and Run to the paired iPhone, **or** run `./scripts/Rebuild-MetraCompanion-Device.sh`.
3. Confirm Settings → Check Ops reach, then a short Vision Ask.
