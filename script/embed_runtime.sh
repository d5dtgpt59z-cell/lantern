#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?App bundle path required}"
./script/prepare_engine.sh
mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
# Only runtime assets: no installed app configuration or user data.
ditto Vendor/Engine "$APP/Contents/Frameworks/Engine"
# Frameworks is a code directory: keep the release's text notices in Resources.
mkdir -p "$APP/Contents/Resources/ThirdParty"
for notice in "$APP/Contents/Frameworks/Engine/"*LICENSE* "$APP/Contents/Frameworks/Engine/"*NOTICE*; do
  if [ -f "$notice" ]; then
    cp "$notice" "$APP/Contents/Resources/ThirdParty/$(basename "$notice")"
    rm "$notice"
  fi
done
rm -f "$APP/Contents/Frameworks/Engine/.paige-runtime-version"
xcrun swiftc -O -target arm64-apple-macos15.0 Helpers/CommandSupervisor.swift -o "$APP/Contents/Helpers/LanternCommand"
xcrun swiftc -O -target arm64-apple-macos15.0 Helpers/EngineSupervisor.swift -o "$APP/Contents/Helpers/LanternEngine"
xcrun swiftc -O -target arm64-apple-macos15.0 Helpers/ImageSupervisor.swift -o "$APP/Contents/Helpers/LanternImage"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ -z "$IDENTITY" ]; then IDENTITY=-; fi
while IFS= read -r -d '' file; do
  if /usr/bin/file -b "$file" | /usr/bin/grep -q 'Mach-O'; then
    codesign --force --sign "$IDENTITY" --options runtime "$file"
  fi
done < <(find "$APP/Contents/Frameworks/Engine" -type f -print0)
codesign --force --sign "$IDENTITY" --options runtime "$APP/Contents/Helpers/LanternCommand"

codesign --force --sign "$IDENTITY" --options runtime "$APP/Contents/Helpers/LanternEngine"

codesign --force --sign "$IDENTITY" --options runtime "$APP/Contents/Helpers/LanternImage"
