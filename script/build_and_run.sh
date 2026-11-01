#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
pkill -x Lantern 2>/dev/null || true
./script/prepare_engine.sh
./script/build_live_avatar.sh
swift build -c release
APP="$(pwd)/dist/PAIGE.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Lantern "$APP/Contents/MacOS/Lantern"
strip -S "$APP/Contents/MacOS/Lantern"
ditto Resources/ThirdParty "$APP/Contents/Resources/ThirdParty"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/PAIGE-mark.png "$APP/Contents/Resources/"
cp Resources/PAIGE-background.png "$APP/Contents/Resources/"
cp Resources/PAIGE.icns "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/LiveAvatar"
cp Resources/LiveAvatar/index.html Resources/LiveAvatar/avatar.js Resources/LiveAvatar/THIRD-PARTY-NOTICES.txt "$APP/Contents/Resources/LiveAvatar/"
IDENTITY="${PAIGE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then IDENTITY=-; fi
export EXPANDED_CODE_SIGN_IDENTITY="$IDENTITY"
./script/embed_runtime.sh "$APP"
codesign --force --sign "$IDENTITY" --options runtime --timestamp=none --entitlements Resources/Live.entitlements "$APP"
codesign --verify --deep --strict "$APP"
case "$MODE" in
  --build|--build-only) ;;
  --install)
    if [ -d /Applications/PAIGE.app ]; then
      BACKUP="$PWD/work/app-backups/PAIGE-before-live-$(date +%Y%m%d-%H%M%S).app"
      mkdir -p "$(dirname "$BACKUP")"
      mv /Applications/PAIGE.app "$BACKUP"
      printf 'Previous PAIGE retained at %s\n' "$BACKUP"
    fi
    if ! ditto "$APP" /Applications/PAIGE.app; then
      if [ -n "${BACKUP:-}" ]; then ditto "$BACKUP" /Applications/PAIGE.app; fi
      exit 1
    fi
    open -n /Applications/PAIGE.app
    ;;
  --debug) lldb -- "$APP/Contents/MacOS/Lantern" ;;
  --logs) open -n "$APP"; log stream --info --predicate 'process == "Lantern"' ;;
  --telemetry) open -n "$APP"; log stream --info --predicate 'subsystem == "com.builtbymagnus.lantern"' ;;
  --verify) open -n "$APP"; sleep 1; pgrep -x Lantern ;;
  *) open -n "$APP" ;;
esac
