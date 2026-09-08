#!/usr/bin/env python3
"""Validate local My Omarchy release evidence and release preflight inputs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any


EXPECTED_REPOSITORY = "superops-team/my-omarchy"
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9.]+)?$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
CANDIDATE = re.compile(r"^my-omarchy-[0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9.]+)?-[0-9a-f]{7,40}$")


def error(message: str) -> None:
    print(f"release-preflight: {message}", file=sys.stderr)


def dotted_get(document: dict[str, Any], path: str) -> Any:
    value: Any = document
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            raise KeyError(path)
        value = value[part]
    return value


def require_string(document: dict[str, Any], path: str, errors: list[str]) -> str:
    try:
        value = dotted_get(document, path)
    except KeyError:
        errors.append(f"{path} is required")
        return ""
    if not isinstance(value, str) or not value:
        errors.append(f"{path} must be a non-empty string")
        return ""
    return value


def validate_evidence(document: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["release evidence must be a JSON object"]
    if document.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    if document.get("repository") != EXPECTED_REPOSITORY:
        errors.append("repository must be superops-team/my-omarchy")

    gate_profile = require_string(document, "gateProfile", errors)
    if gate_profile not in {"prerelease", "stable"}:
        errors.append("gateProfile must be prerelease or stable")
    version = require_string(document, "version", errors)
    tag = require_string(document, "tag", errors)
    candidate_id = require_string(document, "candidateId", errors)
    artifact_name = require_string(document, "artifact.name", errors)
    artifact_sha = require_string(document, "artifact.sha256", errors)
    commit = require_string(document, "commit", errors)
    build_number = require_string(document, "buildNumber", errors)

    if version and not SEMVER.fullmatch(version):
        errors.append("version must be semver")
    if version and tag != f"v{version}":
        errors.append("tag must be v<version>")
    if candidate_id and not CANDIDATE.fullmatch(candidate_id):
        errors.append("candidateId must be my-omarchy-<semver>-<short-sha>")
    if version and artifact_name != f"MyOmarchy-{version}-arm64.dmg":
        errors.append("artifact.name must be MyOmarchy-<version>-arm64.dmg")
    if artifact_sha and not SHA256.fullmatch(artifact_sha):
        errors.append("artifact.sha256 must be a 64-character lowercase hex digest")
    if commit and not COMMIT.fullmatch(commit):
        errors.append("commit must be a 40-character lowercase hex digest")
    if build_number and not re.fullmatch(r"[1-9][0-9]*", build_number):
        errors.append("buildNumber must be a positive decimal string")

    try:
        artifact_size = dotted_get(document, "artifact.size")
    except KeyError:
        errors.append("artifact.size is required")
    else:
        if not isinstance(artifact_size, int) or isinstance(artifact_size, bool) or artifact_size < 1:
            errors.append("artifact.size must be a positive integer")

    try:
        devices = dotted_get(document, "deviceQualification.devices")
    except KeyError:
        errors.append("deviceQualification.devices is required")
        devices = []
    if not isinstance(devices, list):
        errors.append("deviceQualification.devices must be an array")
        devices = []
    passing = [device for device in devices if isinstance(device, dict) and device.get("status") == "pass"]
    if gate_profile == "prerelease" and not passing:
        errors.append("prerelease evidence requires at least one passing device")
    if gate_profile == "stable":
        roles = {device.get("macOSRole") for device in passing if isinstance(device, dict)}
        if len(passing) < 2:
            errors.append("stable evidence requires at least two passing devices")
        if not {"minimum", "latest"} <= roles:
            errors.append("stable evidence must cover minimum and latest macOS labels")

    checks = document.get("checks")
    if not isinstance(checks, list) or not checks:
        errors.append("checks must contain at least one check")
    elif not any(isinstance(check, dict) and check.get("status") == "pass" for check in checks):
        errors.append("checks must contain at least one passing check")

    if not isinstance(document.get("knownLimitations"), list):
        errors.append("knownLimitations must be an array")
    require_string(document, "environment.macOS", errors)
    require_string(document, "environment.architecture", errors)
    if dotted_get(document, "environment") if isinstance(document.get("environment"), dict) else None:
        if document["environment"].get("architecture") != "arm64":
            errors.append("environment.architecture must be arm64")
    require_string(document, "environment.swift", errors)
    require_string(document, "environment.xcode", errors)
    require_string(document, "generatedAt", errors)
    require_string(document, "approvedBy", errors)
    return errors


def validate_git_state(root: Path, evidence: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    status = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if status.returncode != 0:
        return [status.stderr.strip() or "git status failed"]
    if status.stdout:
        errors.append("working tree must be clean")
    rev = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if rev.returncode == 0:
        current = rev.stdout.strip()
        if evidence.get("commit") != current:
            errors.append("evidence commit must match HEAD")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--skip-git-state", action="store_true")
    args = parser.parse_args()

    if args.evidence is None:
        error("--evidence is required")
        return 2
    try:
        document = json.loads(args.evidence.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        error(str(exc))
        return 2

    errors = validate_evidence(document)
    if not args.skip_git_state:
        errors.extend(validate_git_state(args.root.resolve(), document))
    if errors:
        for item in errors:
            error(item)
        return 1
    print("release evidence verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
