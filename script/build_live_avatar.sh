#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIVE="$ROOT/Resources/LiveAvatar"
BUILD="$ROOT/.build/live-avatar/dependencies"
mkdir -p "$BUILD"
cp "$LIVE/package.json" "$LIVE/package-lock.json" "$BUILD/"
if [ ! -x "$BUILD/node_modules/.bin/esbuild" ] || ! cmp -s "$LIVE/package-lock.json" "$BUILD/installed-lock.json"; then
  npm ci --prefix "$BUILD" --no-audit --no-fund --ignore-scripts
  cp "$LIVE/package-lock.json" "$BUILD/installed-lock.json"
fi
NODE_PATH="$BUILD/node_modules" "$BUILD/node_modules/.bin/esbuild" "$LIVE/src/main.js" --bundle --platform=browser --target=safari18 --format=iife --minify --legal-comments=eof --outfile="$LIVE/avatar.js"
node --test "$LIVE/src/bridge-core.test.js"
