#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -x Vendor/Engine/ollama ]; then exit 0; fi
mkdir -p work Vendor/Engine
curl -fL --retry 3 https://github.com/ollama/ollama/releases/download/v0.22.0/ollama-darwin.tgz -o work/ollama-darwin.tgz
printf '%s  %s\n' f8ed626b3d1833333d213f18d38bdfc7c836af4864399a54d35f9c2bc51da6b4 work/ollama-darwin.tgz | shasum -a 256 -c -
tar -xzf work/ollama-darwin.tgz -C Vendor/Engine
