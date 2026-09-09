#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-$(pwd)/dist/Lantern.app}"
[ -d "$APP" ] || { echo 'Build Lantern first.'; exit 1; }
codesign --verify --deep --strict "$APP"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/lantern-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Lantern.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p dist
hdiutil create -volname Lantern -srcfolder "$STAGING" -ov -format UDZO dist/Lantern.dmg
