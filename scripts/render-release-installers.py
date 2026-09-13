#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "scripts/install-my-omarchy.sh.in"
CURRENT = ROOT / "scripts/install-my-omarchy.sh"
RELEASE_ROOT = ROOT / "scripts/release-installers"
RELEASES = {
    "v0.3.1": {
        "bundle_version": "0.4.0",
        "dmg_asset": "MyOmarchy-0.3.1-arm64-unsigned.dmg",
        "dmg_sha256": "e66f4dcbc266e803efc610eac502c1e9297286a1b02f72d37d27e75e95143ed3",
    },
    "v0.4.0": {
        "bundle_version": "0.4.0",
        "dmg_asset": "MyOmarchy-0.4.0-arm64-unsigned.dmg",
        "dmg_sha256": "6f2972a1ce0d7c734e4330f67d7ad3f8f2c9b80c325898bd4c2f8c0f60ee7968",
    },
    "v0.5.0": {
        "bundle_version": "0.5.0",
        "dmg_asset": "MyOmarchy-0.5.0-arm64-unsigned.dmg",
        "dmg_sha256": "4bd2b39e66bcb7b952f5ea9d90ba85b48268f91295375c0b7257f451349801fa",
    },
}


def render(tag: str, config: dict[str, str]) -> bytes:
    source = TEMPLATE.read_text(encoding="utf-8")
    replacements = {
        "@RELEASE_TAG@": tag,
        "@BUNDLE_VERSION@": config["bundle_version"],
        "@DMG_ASSET@": config["dmg_asset"],
        "@DMG_SHA256@": config["dmg_sha256"],
    }
    for marker, value in replacements.items():
        source = source.replace(marker, value)
    if "@" in "".join(line for line in source.splitlines()[:12]):
        raise RuntimeError(f"unresolved installer marker for {tag}")
    return source.encode("utf-8")


def main() -> None:
    for tag, config in RELEASES.items():
        destination = RELEASE_ROOT / tag / "install-my-omarchy.sh"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(render(tag, config))
        destination.chmod(0o755)
    CURRENT.write_bytes((RELEASE_ROOT / "v0.5.0/install-my-omarchy.sh").read_bytes())
    CURRENT.chmod(0o755)


if __name__ == "__main__":
    main()
