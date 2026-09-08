#!/usr/bin/env python3
"""Reject unreviewed legacy product identities in tracked text files."""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


PATTERNS = {
    "legacy-display-name": re.compile(r"Try Omarchy"),
    "legacy-compact-name": re.compile(r"TryOmarchy"),
    "legacy-repository": re.compile(r"(?:https://github\.com/)?themartiano/try-omarchy"),
    "legacy-bundle-prefix": re.compile(r"dev\.tryomarchy(?:\.[A-Za-z0-9_-]+)*"),
    "legacy-kernel-prefix": re.compile(r"(?<![A-Za-z0-9.])tryomarchy\.[A-Za-z0-9_.-]+"),
    "legacy-slug": re.compile(r"(?<![A-Za-z0-9])try-omarchy(?:-[A-Za-z0-9_.-]+)?"),
    "legacy-swift-module": re.compile(r"OmarchyVMHelper(?:Tests)?"),
    "legacy-host-executable": re.compile(r"omarchy-vm-helper"),
    "legacy-runtime-name": re.compile(r"omarchy-(?:qemu|dmg)(?:-[A-Za-z0-9_.?*-]+)?"),
}

ENTRY_FIELDS = {"path", "pattern", "expectedCount", "category", "ownerPhase", "reason"}
RELEASE_CATEGORIES = {"historical-attribution", "verification-fixture"}
CATEGORIES = {
    "brand",
    "repository",
    "host-identity",
    "host-storage",
    "guest-abi",
    "build-resource",
    "historical-attribution",
    "verification-fixture",
}
OWNER_PHASES = {"1A", "1B", "1C", "1D", "permanent"}
GLOB_CHARACTERS = set("*?[")


def fail(message: str) -> None:
    print(f"product-identity: {message}", file=sys.stderr)


def tracked_files(root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(result.stderr.decode(errors="replace").strip() or "git ls-files failed")
    return [item.decode() for item in result.stdout.split(b"\0") if item]


def validate_entry(entry: object, root: Path) -> str | None:
    if not isinstance(entry, dict) or set(entry) != ENTRY_FIELDS:
        return "allowlist entry is invalid: fields must match the schema"
    path = entry["path"]
    pattern = entry["pattern"]
    count = entry["expectedCount"]
    if not isinstance(path, str) or not path or any(char in path for char in GLOB_CHARACTERS):
        return "allowlist entry is invalid: path must be exact and cannot contain globs"
    logical = PurePosixPath(path)
    if logical.is_absolute() or ".." in logical.parts or logical.as_posix() != path:
        return "allowlist entry is invalid: path must be a normalized repository-relative path"
    if pattern not in PATTERNS:
        return f"allowlist entry is invalid: unknown pattern {pattern!r}"
    if not isinstance(count, int) or isinstance(count, bool) or count < 1:
        return "allowlist entry is invalid: expectedCount must be a positive integer"
    for field in ("category", "ownerPhase", "reason"):
        if not isinstance(entry[field], str) or not entry[field].strip():
            return f"allowlist entry is invalid: {field} is required"
    if entry["category"] not in CATEGORIES:
        return f"allowlist entry is invalid: unknown category {entry['category']!r}"
    if entry["ownerPhase"] not in OWNER_PHASES:
        return f"allowlist entry is invalid: unknown ownerPhase {entry['ownerPhase']!r}"
    if not (root / path).is_file():
        return f"allowlist entry is invalid: path is not a tracked file: {path}"
    return None


def read_text(path: Path) -> str | None:
    payload = path.read_bytes()
    if b"\0" in payload:
        return None
    try:
        return payload.decode("utf-8")
    except UnicodeDecodeError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--allowlist", type=Path)
    parser.add_argument("--mode", choices=("baseline", "release"), default="baseline")
    args = parser.parse_args()

    root = args.root.resolve()
    allowlist_path = (args.allowlist or root / "config/legacy-identity-allowlist.json").resolve()
    try:
        document = json.loads(allowlist_path.read_text())
        if set(document) != {"schemaVersion", "entries"} or document["schemaVersion"] != 1:
            raise ValueError("allowlist root must contain schemaVersion 1 and entries")
        entries = document["entries"]
        if not isinstance(entries, list):
            raise ValueError("allowlist entries must be an array")
        tracked = tracked_files(root)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        fail(str(error))
        return 2

    errors: list[str] = []
    allowed: dict[tuple[str, str], dict[str, object]] = {}
    for entry in entries:
        error = validate_entry(entry, root)
        if error:
            errors.append(error)
            continue
        key = (str(entry["path"]), str(entry["pattern"]))
        if key in allowed:
            errors.append(f"allowlist entry is invalid: duplicate {key[0]} {key[1]}")
            continue
        allowed[key] = entry

    observed: Counter[tuple[str, str]] = Counter()
    release_blocker_entries: Counter[str] = Counter()
    release_blocker_occurrences: Counter[str] = Counter()
    excluded = set()
    try:
        excluded.add(allowlist_path.relative_to(root).as_posix())
    except ValueError:
        pass
    scanner_path = Path(__file__).resolve()
    try:
        excluded.add(scanner_path.relative_to(root).as_posix())
    except ValueError:
        pass

    for relative in tracked:
        if relative in excluded:
            continue
        text = read_text(root / relative)
        for pattern_name, pattern in PATTERNS.items():
            count = len(pattern.findall(relative))
            if text is not None:
                count += len(pattern.findall(text))
            if count:
                observed[(relative, pattern_name)] = count

    for key, count in sorted(observed.items()):
        entry = allowed.get(key)
        if entry is None:
            errors.append(
                f"unallowlisted legacy identity: {key[0]} pattern={key[1]} count={count}"
            )
            continue
        expected = int(entry["expectedCount"])
        if count != expected:
            errors.append(
                f"allowlist count drift: {key[0]} pattern={key[1]} expected {expected} occurrence(s), found {count}"
            )
        if args.mode == "release" and entry["category"] not in RELEASE_CATEGORIES:
            owner_phase = str(entry["ownerPhase"])
            release_blocker_entries[owner_phase] += 1
            release_blocker_occurrences[owner_phase] += count
            errors.append(
                f"legacy identity not permitted in release mode: {key[0]} pattern={key[1]} ownerPhase={entry['ownerPhase']}"
            )

    for key, entry in sorted(allowed.items()):
        if key not in observed:
            errors.append(
                f"stale allowlist entry: {key[0]} pattern={key[1]} expected {entry['expectedCount']} occurrence(s), found 0"
            )

    if errors:
        for error in errors:
            fail(error)
        if release_blocker_entries:
            summary = ", ".join(
                f"{phase}={release_blocker_entries[phase]} "
                f"{'entry' if release_blocker_entries[phase] == 1 else 'entries'}/"
                f"{release_blocker_occurrences[phase]} "
                f"{'occurrence' if release_blocker_occurrences[phase] == 1 else 'occurrences'}"
                for phase in sorted(release_blocker_entries)
            )
            fail(f"release blockers by ownerPhase: {summary}")
        return 1

    print(f"product identity {args.mode} verification passed ({sum(observed.values())} legacy occurrence(s) reviewed)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
