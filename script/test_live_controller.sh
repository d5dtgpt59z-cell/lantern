#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
LIVE_CONTROLLER_CHECK_BINARY="$PWD/work/paige-live-controller-checks"
xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 \
  Sources/Services/LiveController.swift Tests/LiveControllerChecks.swift \
  -o "$LIVE_CONTROLLER_CHECK_BINARY"
"$LIVE_CONTROLLER_CHECK_BINARY"
