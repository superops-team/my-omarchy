#!/bin/bash

set -euo pipefail

repository='superops-team/my-omarchy'
api_url="https://api.github.com/repos/$repository/releases?per_page=20"
test_mode=${MY_OMARCHY_LATEST_INSTALLER_TEST_MODE:-0}
[[ $test_mode == 0 || $test_mode == 1 ]] || {
  printf '%s\n' 'install-latest-my-omarchy: invalid test mode' >&2
  exit 1
}

fail() {
  printf 'install-latest-my-omarchy: %s\n' "$*" >&2
  exit 1
}

for tool in /usr/bin/curl /usr/bin/mktemp /usr/bin/plutil /bin/bash /bin/cp /bin/rm; do
  [[ -x $tool ]] || fail "required macOS tool is unavailable: $tool"
done

temporary_directory=$(/usr/bin/mktemp -d /private/tmp/my-omarchy-latest-installer.XXXXXX)
releases_json="$temporary_directory/releases.json"
version_installer="$temporary_directory/install-my-omarchy.sh"
cleanup() {
  result=$?
  trap - EXIT HUP INT TERM
  /bin/rm -rf -- "$temporary_directory"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ $test_mode == 1 ]]; then
  [[ -n ${MY_OMARCHY_LATEST_INSTALLER_TEST_API_PATH:-} ]] ||
    fail 'test mode requires an API fixture path'
  [[ -n ${MY_OMARCHY_LATEST_INSTALLER_TEST_ASSET_DIRECTORY:-} ]] ||
    fail 'test mode requires an asset fixture directory'
  /bin/cp -- "$MY_OMARCHY_LATEST_INSTALLER_TEST_API_PATH" "$releases_json"
else
  /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' \
    --tlsv1.2 --retry 3 \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    --output "$releases_json" "$api_url"
fi

release_index=
release_tag=
release_is_prerelease=false
for ((index = 0; index < 20; index++)); do
  draft=$(/usr/bin/plutil -extract "$index.draft" raw "$releases_json" 2>/dev/null || true)
  [[ -n $draft ]] || break
  [[ $draft == false ]] || continue
  release_index=$index
  release_tag=$(/usr/bin/plutil -extract "$index.tag_name" raw "$releases_json" 2>/dev/null || true)
  release_is_prerelease=$(/usr/bin/plutil -extract "$index.prerelease" raw "$releases_json" 2>/dev/null || true)
  break
done

[[ -n $release_index ]] || fail 'GitHub returned no public My Omarchy release'
[[ $release_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]] ||
  fail 'latest public release does not use a valid semantic version tag'
[[ $release_is_prerelease == true || $release_is_prerelease == false ]] ||
  fail 'latest public release has invalid prerelease metadata'

installer_url=
for ((asset_index = 0; asset_index < 50; asset_index++)); do
  asset_name=$(/usr/bin/plutil -extract \
    "$release_index.assets.$asset_index.name" raw "$releases_json" 2>/dev/null || true)
  [[ -n $asset_name ]] || break
  if [[ $asset_name == install-my-omarchy.sh ]]; then
    installer_url=$(/usr/bin/plutil -extract \
      "$release_index.assets.$asset_index.browser_download_url" raw \
      "$releases_json" 2>/dev/null || true)
    break
  fi
done

[[ -n $installer_url ]] ||
  fail "latest public release $release_tag does not publish install-my-omarchy.sh"
expected_url="https://github.com/$repository/releases/download/$release_tag/install-my-omarchy.sh"
[[ $installer_url == "$expected_url" ]] ||
  fail 'latest installer asset has an unexpected or non-HTTPS download URL'

if [[ $release_is_prerelease == true ]]; then
  printf '==> Latest public release: %s (prerelease)\n' "$release_tag"
else
  printf '==> Latest public release: %s\n' "$release_tag"
fi

if [[ $test_mode == 1 ]]; then
  fixture="$MY_OMARCHY_LATEST_INSTALLER_TEST_ASSET_DIRECTORY/$release_tag.sh"
  [[ -f $fixture && ! -L $fixture ]] || fail 'latest installer fixture is missing or unsafe'
  /bin/cp -- "$fixture" "$version_installer"
else
  /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' \
    --tlsv1.2 --retry 3 --output "$version_installer" "$installer_url"
fi

[[ -s $version_installer && ! -L $version_installer ]] ||
  fail 'downloaded release installer is empty or unsafe'
/bin/bash "$version_installer"
