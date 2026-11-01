#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ENGINE_VERSION="0.40.8"
ENGINE_SHA256="29fce20c736f62aa8885b1e83552c5fd8dcc63edc5ffc1b47f2de591a06cde44"
ENGINE_ARCHIVE="work/ollama-darwin-v${ENGINE_VERSION}.tgz"
ENGINE_VERSION_FILE="Vendor/Engine/.paige-runtime-version"
if [ -x Vendor/Engine/ollama ] && [ -x Vendor/Engine/llama-server ] &&
   [ -f "$ENGINE_VERSION_FILE" ] && [ "$(cat "$ENGINE_VERSION_FILE")" = "$ENGINE_VERSION" ]; then
    exit 0
fi

mkdir -p work Vendor
if ! printf '%s  %s\n' "$ENGINE_SHA256" "$ENGINE_ARCHIVE" | shasum -a 256 -c - >/dev/null 2>&1; then
    curl -fL --retry 3 "https://github.com/ollama/ollama/releases/download/v${ENGINE_VERSION}/ollama-darwin.tgz" -o "${ENGINE_ARCHIVE}.partial"
    printf '%s  %s\n' "$ENGINE_SHA256" "${ENGINE_ARCHIVE}.partial" | shasum -a 256 -c -
    mv "${ENGINE_ARCHIVE}.partial" "$ENGINE_ARCHIVE"
fi

# Validate a complete, fresh payload before touching an existing runtime. In
# particular, new releases require llama-server alongside the Ollama executable.
runtime_stage=$(mktemp -d "$PWD/work/engine-v${ENGINE_VERSION}.XXXXXX")
trap 'if [ -n "$runtime_stage" ]; then rm -rf "$runtime_stage"; fi' EXIT
tar -xzf "$ENGINE_ARCHIVE" -C "$runtime_stage"
test -x "$runtime_stage/ollama"
test -x "$runtime_stage/llama-server"
printf '%s\n' "$ENGINE_VERSION" > "$runtime_stage/.paige-runtime-version"

# Replace the directory rather than overlaying it, so obsolete libraries cannot
# remain in a future app bundle. Keep the previous payload for rollback.
runtime_backup=""
if [ -e Vendor/Engine ]; then
    mkdir -p work/engine-backups
    runtime_backup=$(mktemp -d "$PWD/work/engine-backups/previous.XXXXXX")
    mv Vendor/Engine "$runtime_backup/Engine"
fi
if ! mv "$runtime_stage" Vendor/Engine; then
    if [ -n "$runtime_backup" ]; then mv "$runtime_backup/Engine" Vendor/Engine; fi
    exit 1
fi
runtime_stage=""
if [ -n "$runtime_backup" ]; then printf 'Previous engine retained at %s\n' "$runtime_backup/Engine"; fi
