#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
pkill -x Lantern 2>/dev/null || true
./script/prepare_engine.sh
swift build -c release
APP="$(pwd)/dist/Lantern.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Lantern "$APP/Contents/MacOS/Lantern"
ditto Resources/Pip-frames "$APP/Contents/Resources/Pip-frames"
ditto Resources/ThirdParty "$APP/Contents/Resources/ThirdParty"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Lantern.icns "$APP/Contents/Resources/"
./script/embed_runtime.sh "$APP"
codesign --force --sign - --options runtime "$APP"
case "$MODE" in
  --build) ;;
  --debug) lldb -- "$APP/Contents/MacOS/Lantern" ;;
  --logs) open -n "$APP"; log stream --info --predicate 'process == "Lantern"' ;;
  --telemetry) open -n "$APP"; log stream --info --predicate 'subsystem == "com.builtbymagnus.lantern"' ;;
  --verify) open -n "$APP"; sleep 1; pgrep -x Lantern ;;
  *) open -n "$APP" ;;
esac
