#!/bin/bash

set -euo pipefail

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

probe_directory=$(mktemp -d "${TMPDIR:-/tmp}/my-omarchy-doctor.XXXXXX")
trap 'rm -rf -- "$probe_directory"' EXIT
module_cache="$probe_directory/module-cache"
mkdir -p "$module_cache"
printf '%s\n' 'import Testing' '' '@Test func probe() {}' >"$probe_directory/testing-probe.swift"
if ! MACOSX_DEPLOYMENT_TARGET=15.0 swiftc \
  -module-cache-path "$module_cache" \
  -typecheck "$probe_directory/testing-probe.swift" >/dev/null 2>&1; then
  fail 'Swift toolchain cannot compile the Testing module'
fi

printf 'Toolchain ready: %s (%s)\n' "$macos_version" "$(uname -m)"
