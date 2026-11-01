#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
IMAGE_CHECK_BINARY="$PWD/work/paige-image-checks"
IMAGE_CHECK_SOURCES=()
while IFS= read -r source; do
  IMAGE_CHECK_SOURCES+=("$source")
done < <(rg --files Sources -g '*.swift' -g '!LanternApp.swift' | sort)
xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 Tests/ImageChecks.swift "${IMAGE_CHECK_SOURCES[@]}" -o "$IMAGE_CHECK_BINARY"
"$IMAGE_CHECK_BINARY"
