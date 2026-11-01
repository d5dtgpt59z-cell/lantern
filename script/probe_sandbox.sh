#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROBE="$PWD/work/LanternSandboxProbe.app"
mkdir -p "$PROBE/Contents/MacOS" "$PROBE/Contents/Helpers" "$PROBE/Contents/Frameworks" "$PROBE/Contents/Resources"
cat > "$PROBE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.builtbymagnus.lantern.sandboxprobe</string><key>CFBundleName</key><string>Lantern Sandbox Probe</string><key>CFBundleExecutable</key><string>LanternSandboxProbe</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>LSUIElement</key><true/><key>LSMinimumSystemVersion</key><string>15.0</string></dict></plist>
PLIST
printf 'public synthetic test fixture\n' > work/sandbox-outside-canary.txt
printf '%s\n' "$PWD/work/sandbox-outside-canary.txt" > "$PROBE/Contents/Resources/canary-path.txt"
xcrun swiftc -O -target arm64-apple-macos15.0 Tests/SandboxProbe/main.swift -o "$PROBE/Contents/MacOS/LanternSandboxProbe"
xcrun swiftc -O -target arm64-apple-macos15.0 Helpers/CommandSupervisor.swift -o "$PROBE/Contents/Helpers/LanternCommand"
xcrun swiftc -O -target arm64-apple-macos15.0 Helpers/EngineSupervisor.swift -o "$PROBE/Contents/Helpers/LanternEngine"
if [ ! -f "$PROBE/Contents/Frameworks/Engine/ollama" ]; then ditto Vendor/Engine "$PROBE/Contents/Frameworks/Engine"; fi
while IFS= read -r -d '' binary; do
    kind=$(/usr/bin/file -b "$binary")
    if [[ "$kind" == *Mach-O* ]]; then
        if [[ "$kind" == *executable* ]]; then
            codesign --force --sign - --entitlements Tests/SandboxProbe/helper.entitlements "$binary"
        else codesign --force --sign - "$binary"; fi
    fi
done < <(find "$PROBE/Contents/Frameworks/Engine" "$PROBE/Contents/Helpers" -type f -print0)
codesign --force --sign - --entitlements Tests/SandboxProbe/app.entitlements "$PROBE"
codesign --verify --deep --strict "$PROBE"
open -n --stdout "$PWD/work/sandbox-stdout.txt" --stderr "$PWD/work/sandbox-stderr.txt" "$PROBE" --args "$@"
