#!/usr/bin/env bash
# Export a debug APK and install + launch it on the connected Android device.
#   tools/deploy-android.sh          # export, install, launch
#   tools/deploy-android.sh --logs   # ...then follow Godot's log output
set -euo pipefail
cd "$(dirname "$0")/.."
PKG=com.networkburger.loadsagolf
GODOT="${GODOT:-godot}"
ADB="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb"

"$ADB" get-state >/dev/null 2>&1 || { echo "No device: connect the tablet (USB debugging on) and check '$ADB devices'." >&2; exit 1; }
mkdir -p build
"$GODOT" --headless --export-debug "Android" build/loadsagolf-debug.apk 2>&1 | grep -E "ERROR|DONE" || true
"$ADB" install -r build/loadsagolf-debug.apk
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Launched $PKG on $("$ADB" shell getprop ro.product.model | tr -d '\r')"
if [[ "${1:-}" == "--logs" ]]; then
  "$ADB" logcat -c
  "$ADB" logcat -s godot:V
fi
