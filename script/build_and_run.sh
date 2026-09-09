#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
pkill -x Lantern 2>/dev/null || true
swift build -c release
APP="$(pwd)/dist/Lantern.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Lantern "$APP/Contents/MacOS/Lantern"
if [ -d Resources/Pip-frames ]; then ditto Resources/Pip-frames "$APP/Contents/Resources/Pip-frames"; fi
cp Resources/run_command.py "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/Lantern.icns ]; then cp Resources/Lantern.icns "$APP/Contents/Resources/"; fi
codesign --force --sign - "$APP"
case "$MODE" in
  --build) ;;
  --debug) lldb -- "$APP/Contents/MacOS/Lantern" ;;
  --logs) open -n "$APP"; log stream --info --predicate 'process == "Lantern"' ;;
  --telemetry) open -n "$APP"; log stream --info --predicate 'subsystem == "com.builtbymagnus.lantern"' ;;
  --verify) open -n "$APP"; sleep 1; pgrep -x Lantern ;;
  *) open -n "$APP" ;;
esac
