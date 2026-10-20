#!/bin/zsh
# Rebuild MetraCompanion (Debug) and install to a paired iPhone.
# Phase 1.6a interim: beat Personal Team ~7-day expiry until TestFlight is available.
#
# Run on the Mac build station with a logged-in GUI session (unlocked login keychain).
# SSH-only codesign often fails with errSecInternalComponent.
#
# Usage:
#   ./Rebuild-MetraCompanion-Device.sh
#   METRA_IOS_UDID=<udid> ./Rebuild-MetraCompanion-Device.sh
#   ./Rebuild-MetraCompanion-Device.sh --list-devices
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$IOS_ROOT/MetraCompanion.xcodeproj"
SCHEME="MetraCompanion"
BUNDLE_ID="app.metra.companion"
DERIVED="${METRA_IOS_DERIVED:-$HOME/Library/Developer/MetraCompanion/DerivedData-weekly}"
LOG_DIR="${METRA_IOS_LOG_DIR:-$HOME/Library/Logs/MetraCompanion}"
LOG_FILE="$LOG_DIR/weekly-reinstall.log"
CONFIG="${METRA_IOS_CONFIG:-Debug}"

mkdir -p "$LOG_DIR" "$DERIVED"

log() {
  local line="[$(date '+%Y-%m-%d %H:%M:%S %z')] $*"
  print -r -- "$line" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

list_devices() {
  xcrun devicectl list devices 2>/dev/null || xcrun xctrace list devices 2>/dev/null || true
}

if [[ "${1:-}" == "--list-devices" ]]; then
  list_devices
  exit 0
fi

[[ -d "$PROJECT" ]] || die "Xcode project not found: $PROJECT"

log "=== MetraCompanion weekly rebuild start ==="
log "project=$PROJECT config=$CONFIG derived=$DERIVED"

# Prefer an explicitly configured UDID; otherwise pick the first available iPhone that is connected.
UDID="${METRA_IOS_UDID:-}"
if [[ -z "$UDID" ]]; then
  # Private scratch JSON via mktemp (never a fixed world-writable path - symlink / stale-file risk).
  TMP_JSON="$(mktemp -t metra-devices)"
  trap 'rm -f "$TMP_JSON"' EXIT
  # devicectl JSON is the stable path on modern Xcode.
  if xcrun devicectl list devices --json-output "$TMP_JSON" >/dev/null 2>&1; then
    UDID="$(
      METRA_DEVICES_JSON="$TMP_JSON" /usr/bin/python3 - <<'PY'
import json
import os
path = os.environ.get("METRA_DEVICES_JSON", "")
if not path:
    raise SystemExit(0)
try:
    data = json.load(open(path))
except Exception:
    raise SystemExit(0)
# Shape varies by Xcode; search for hardware properties with iPhone + identifier.
candidates = []
def walk(obj):
    if isinstance(obj, dict):
        conn = str(obj.get("connectionProperties", obj.get("hardwareProperties", {})))
        name = str(obj.get("deviceProperties", obj.get("name", "")))
        ident = (
            obj.get("identifier")
            or obj.get("udid")
            or (obj.get("hardwareProperties") or {}).get("udid")
            or (obj.get("hardwareProperties") or {}).get("ecid")
        )
        product = str(
            (obj.get("hardwareProperties") or {}).get("productType")
            or obj.get("productType")
            or ""
        )
        text = " ".join([str(ident), name, product, conn]).lower()
        if ident and ("iphone" in text or product.startswith("iPhone")):
            # Prefer connected / available
            state = str(obj.get("connectionProperties", {})).lower()
            score = 0
            if "connected" in state or "available" in state:
                score = 1
            candidates.append((score, str(ident)))
        for v in obj.values():
            walk(v)
    elif isinstance(obj, list):
        for i in obj:
            walk(i)
walk(data)
candidates.sort(reverse=True)
print(candidates[0][1] if candidates else "")
PY
    )"
  fi
fi

[[ -n "$UDID" ]] || die "No iPhone UDID. Pair the phone, or set METRA_IOS_UDID. Try: $0 --list-devices"

log "udid=$UDID"

# Destination: concrete device id (more reliable than 'generic/platform=iOS' for install path).
DEST="id=$UDID"

log "xcodebuild clean build ..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "$DEST" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  build \
  2>&1 | tee -a "$LOG_FILE"

APP_PATH="$(
  find "$DERIVED/Build/Products/$CONFIG-iphoneos" -maxdepth 1 -name '*.app' -print 2>/dev/null | head -n 1
)"
[[ -n "$APP_PATH" && -d "$APP_PATH" ]] || die "Built .app not found under $DERIVED/Build/Products/$CONFIG-iphoneos"

log "installing $APP_PATH -> $UDID"
xcrun devicectl device install app --device "$UDID" "$APP_PATH" 2>&1 | tee -a "$LOG_FILE"

log "install finished (bundle $BUNDLE_ID). Unlock phone and launch Metra if needed."
log "=== MetraCompanion weekly rebuild ok ==="
exit 0
