#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ $(uname -s) == Darwin ]] || fail 'macOS is required'
[[ $(uname -m) == arm64 ]] || fail 'an Apple Silicon Mac is required'
macos_version=$(sw_vers -productVersion)
macos_major=${macos_version%%.*}
[[ $macos_major =~ ^[0-9]+$ ]] || fail "could not determine the macOS version: $macos_version"
(( macos_major >= 15 )) || fail 'macOS 15 or newer is required'

for tool in curl docker pkg-config python3 swift swiftc xcrun; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
docker info >/dev/null 2>&1 || fail 'Docker is installed but not running'

if ! swift build \
  --package-path "$ROOT/macos" \
  --build-tests \
  --disable-sandbox >/dev/null 2>&1; then
  fail 'Swift package tests cannot build with the configured toolchain and dependencies'
fi

printf 'Toolchain ready: %s (%s)\n' "$macos_version" "$(uname -m)"
