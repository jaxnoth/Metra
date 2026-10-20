#!/bin/zsh
# Simulator smoke: build, install, launch MetraCompanion. Does not claim Ask works
# (HQ Invoke-MetraIosReachVerify.ps1 owns reach). Run on iwu75208-mac.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$IOS_ROOT/MetraCompanion.xcodeproj"
SCHEME="MetraCompanion"
BUNDLE_ID="app.metra.companion"
DERIVED="${METRA_IOS_SIM_DERIVED:-$HOME/Library/Developer/MetraCompanion/DerivedData-sim-smoke}"
DEVICE_NAME="${METRA_IOS_SIM_DEVICE:-iPhone 17}"
LOG_DIR="${METRA_IOS_LOG_DIR:-$HOME/Library/Logs/MetraCompanion}"
LOG_FILE="$LOG_DIR/sim-smoke.log"

mkdir -p "$LOG_DIR" "$DERIVED"

log() {
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S %z')] $*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

log "=== sim smoke start device=$DEVICE_NAME ==="

# Boot simulator if needed (BSD awk - no GNU match() capture array).
UDID="$(xcrun simctl list devices available | grep "$DEVICE_NAME (" | grep -v unavailable | head -1 | sed -n 's/.*(\([A-F0-9-]\{36\}\)).*/\1/p')"
[[ -n "$UDID" ]] || die "Simulator not found: $DEVICE_NAME"

STATE="$(xcrun simctl list devices | grep "$UDID" | grep -o 'Booted\|Shutdown' | head -1 || true)"
if [[ "$STATE" != "Booted" ]]; then
  log "booting $DEVICE_NAME ($UDID)"
  xcrun simctl boot "$UDID" || true
  open -a Simulator || true
  sleep 3
fi

log "xcodebuild (iphonesimulator) ..."
BUILD_LOG="$LOG_DIR/sim-smoke-xcodebuild.log"
set +e
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" \
  build \
  CODE_SIGN_STYLE=Automatic \
  >"$BUILD_LOG" 2>&1
XC_CODE=$?
set -e
tail -n 40 "$BUILD_LOG" | tee -a "$LOG_FILE"
cat "$BUILD_LOG" >>"$LOG_FILE"
if [[ $XC_CODE -ne 0 ]] || ! grep -q 'BUILD SUCCEEDED' "$BUILD_LOG"; then
  die "xcodebuild failed (exit=$XC_CODE). See $BUILD_LOG"
fi
log "xcodebuild ok"

APP="$DERIVED/Build/Products/Debug-iphonesimulator/MetraCompanion.app"
[[ -d "$APP" ]] || die "App missing at $APP"

# Privacy keys must be present (mic kill scar).
plutil -extract NSMicrophoneUsageDescription raw "$APP/Info.plist" >/dev/null 2>&1 \
  || die "NSMicrophoneUsageDescription missing from built Info.plist"
plutil -extract NSSpeechRecognitionUsageDescription raw "$APP/Info.plist" >/dev/null 2>&1 \
  || die "NSSpeechRecognitionUsageDescription missing from built Info.plist"
log "Info.plist privacy keys ok"

log "install + launch"
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" || die "launch failed"

log "=== sim smoke ok ==="
print -r -- "SIM_SMOKE_OK udid=$UDID app=$APP"
