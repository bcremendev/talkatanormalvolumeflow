#!/bin/bash
# Downloads prebuilt whisper.cpp (xcframework) and Ollama into vendor/. Idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."
WHISPER_VER="${WHISPER_VER:-v1.9.2}"
OLLAMA_VER="${OLLAMA_VER:-v0.33.3}"
mkdir -p vendor

if [[ ! -d vendor/build-apple/whisper.xcframework ]]; then
  echo "▸ downloading whisper.cpp $WHISPER_VER xcframework"
  curl -fL --progress-bar -o vendor/whisper-xcframework.zip \
    "https://github.com/ggml-org/whisper.cpp/releases/download/$WHISPER_VER/whisper-$WHISPER_VER-xcframework.zip"
  (cd vendor && unzip -qo whisper-xcframework.zip)
fi

if [[ -z "${SKIP_OLLAMA:-}" && ! -x vendor/ollama/ollama ]]; then
  echo "▸ downloading Ollama $OLLAMA_VER"
  curl -fL --progress-bar -o vendor/ollama-darwin.tgz \
    "https://github.com/ollama/ollama/releases/download/$OLLAMA_VER/ollama-darwin.tgz"
  mkdir -p vendor/ollama && tar -xzf vendor/ollama-darwin.tgz -C vendor/ollama
fi
echo "▸ dependencies ready"
