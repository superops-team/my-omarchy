#!/usr/bin/env python3

"""Require the native screensaver override to stay narrowly scoped."""

from __future__ import annotations

import argparse
from pathlib import Path


UPSTREAM_CURSOR_RESTORE = (
    "  hyprctl eval 'hl.config({ cursor = { invisible = false } })' &>/dev/null "
    "|| hyprctl keyword cursor:invisible false &>/dev/null || true"
)
NATIVE_CURSOR_RESTORE = (
    "  /usr/local/bin/omarchy-native-cursor-restore 2>/dev/null || true"
)
UPSTREAM_FRAME_RATE = "    --frame-rate 120 --canvas-width 0 --canvas-height 0 --reuse-canvas --anchor-canvas c --anchor-text c\\"
NATIVE_FRAME_RATE = "    --frame-rate \"$frame_rate\" --canvas-width 0 --canvas-height 0 --reuse-canvas --anchor-canvas c --anchor-text c\\"
NATIVE_RATE_GUARD = """frame_rate=${MY_OMARCHY_SCREENSAVER_FRAME_RATE:-15}
if [[ ! $frame_rate =~ ^[1-9][0-9]*$ || $frame_rate -gt 60 ]]; then
  frame_rate=15
fi
"""
NATIVE_DYNAMIC_GUARD = """if [[ ${MY_OMARCHY_DYNAMIC_SCREENSAVER:-0} != 1 ]]; then
  exit_screensaver
fi
"""


def read(path: Path, label: str) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise SystemExit(f"verify-screensaver-override: cannot read {label}: {error}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--override", required=True, type=Path)
    args = parser.parse_args()

    upstream = read(args.source, "pinned upstream screensaver")
    native = read(args.override, "native screensaver override")
    if upstream.count(UPSTREAM_CURSOR_RESTORE) != 1:
        raise SystemExit(
            "verify-screensaver-override: pinned upstream cursor cleanup changed; "
            "review the native override"
        )
    if upstream.count(UPSTREAM_FRAME_RATE) != 1:
        raise SystemExit(
            "verify-screensaver-override: pinned upstream frame-rate line changed; "
            "review the native override"
        )
    expected = upstream.replace(UPSTREAM_CURSOR_RESTORE, NATIVE_CURSOR_RESTORE)
    expected = expected.replace(UPSTREAM_FRAME_RATE, NATIVE_FRAME_RATE)
    expected = expected.replace(
        "\nprintf '\\033]11;rgb:00/00/00\\007'  # Set background color to black\n",
        "\n" + NATIVE_DYNAMIC_GUARD + "\nprintf '\\033]11;rgb:00/00/00\\007'  # Set background color to black\n",
    )
    expected = expected.replace("\nwhile true; do\n", "\n" + NATIVE_RATE_GUARD + "\nwhile true; do\n")
    if native != expected:
        raise SystemExit(
            "verify-screensaver-override: native screensaver must differ from pinned "
            "upstream only at cursor restoration, default idle suppression, "
            "and VM-safe frame-rate limiting"
        )


if __name__ == "__main__":
    main()
