#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
xcrun swiftc -O -target arm64-apple-macos15.0 Helpers/ImageSupervisor.swift -o work/LanternImageChecks
python3 Tests/ImageSupervisorChecks.py work/LanternImageChecks
