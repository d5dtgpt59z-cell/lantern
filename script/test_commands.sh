#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
xcrun swiftc Helpers/CommandSupervisor.swift -o work/LanternCommand
python3 Tests/CommandSupervisorChecks.py work/LanternCommand
