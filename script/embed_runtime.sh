#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?App bundle path required}"
./script/prepare_engine.sh
mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
# Only runtime assets: no installed app configuration or user data.
ditto Vendor/Engine "$APP/Contents/Frameworks/Engine"
xcrun swiftc -O -target arm64-apple-macos15.0 Helpers/CommandSupervisor.swift -o "$APP/Contents/Helpers/LanternCommand"
xcrun swiftc -O -target arm64-apple-macos15.0 Helpers/EngineSupervisor.swift -o "$APP/Contents/Helpers/LanternEngine"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ -z "$IDENTITY" ]; then IDENTITY=-; fi
while IFS= read -r -d '' file; do
  if /usr/bin/file -b "$file" | /usr/bin/grep -q 'Mach-O'; then
    codesign --force --sign "$IDENTITY" --options runtime "$file"
  fi
done < <(find "$APP/Contents/Frameworks/Engine" -type f -print0)
codesign --force --sign "$IDENTITY" --options runtime "$APP/Contents/Helpers/LanternCommand"

codesign --force --sign "$IDENTITY" --options runtime "$APP/Contents/Helpers/LanternEngine"
