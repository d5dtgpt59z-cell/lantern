#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-$(pwd)/dist/PAIGE.app}"
[ -d "$APP" ] || { echo 'Build PAIGE first.'; exit 1; }
codesign --verify --deep --strict "$APP"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/lantern-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/PAIGE.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p dist
hdiutil create -volname PAIGE -srcfolder "$STAGING" -ov -format UDZO dist/PAIGE.dmg
