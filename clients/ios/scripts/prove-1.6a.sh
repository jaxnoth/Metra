#!/bin/zsh
# Device prove (build + install + LaunchAgent). Prefer GUI Terminal / unlocked keychain.
# Alias: ~/prove-metra -> this script on iwu75208-mac.
# Resolve symlinks so ~/prove-metra still finds clients/ios (scar 2026-10-17).
set -euo pipefail
SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$IOS_ROOT"
export METRA_IOS_UDID="${METRA_IOS_UDID:-00008130-0009142834F2001C}"
chmod +x scripts/Rebuild-MetraCompanion-Device.sh scripts/Invoke-MetraIosSimSmoke.sh 2>/dev/null || true
./scripts/Rebuild-MetraCompanion-Device.sh
echo "PROVE_BUILD_OK"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/MetraCompanion"
REBUILD_SH="$IOS_ROOT/scripts/Rebuild-MetraCompanion-Device.sh"
DEST_PLIST="$HOME/Library/LaunchAgents/com.metra.companion.weekly-reinstall.plist"
[[ -f "$REBUILD_SH" ]] || { echo "ERROR: missing $REBUILD_SH"; exit 1; }
# Render LaunchAgent from this checkout (do not copy the checked-in host-specific example plist).
cat > "$DEST_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.metra.companion.weekly-reinstall</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>${REBUILD_SH}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${IOS_ROOT}</string>
  <key>StartInterval</key>
  <integer>432000</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/MetraCompanion/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/MetraCompanion/launchd.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin</string>
  </dict>
</dict>
</plist>
EOF
UID_NUM="$(id -u)"
launchctl bootout "gui/${UID_NUM}/com.metra.companion.weekly-reinstall" 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "$DEST_PLIST" 2>/dev/null || true
launchctl enable "gui/${UID_NUM}/com.metra.companion.weekly-reinstall" 2>/dev/null || true
echo "PROVE_LAUNCHAGENT_OK"
