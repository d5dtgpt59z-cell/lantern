#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/AutomationProbe.app/Contents/MacOS
PROBE="$PWD/work/AutomationProbe.app"
cat > "$PROBE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.builtbymagnus.lantern.automationprobe</string><key>CFBundleExecutable</key><string>Probe</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -parse-as-library -O -target arm64-apple-macos15.0 Tests/Automation/Probe.swift Sources/Models/Attachment.swift Sources/Models/ToolCall.swift Sources/Services/BrowserDriver.swift Sources/Services/InternetDriver.swift Sources/Services/ComputerDriver.swift Sources/Services/AutomationTools.swift -o "$PROBE/Contents/MacOS/Probe"
codesign --force --sign - "$PROBE"
python3 Tests/Automation/server.py > work/automation-server.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
open -n -W "$PROBE" --args "$PWD/work"
cat work/automation-results.txt
rg -q '^DONE$' work/automation-results.txt
