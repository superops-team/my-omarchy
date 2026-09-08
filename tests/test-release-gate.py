#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
PREFLIGHT = REPOSITORY / "scripts/release-preflight.py"
FIXTURE = REPOSITORY / "tests/fixtures/release-evidence/prerelease-pass.json"


class ReleaseGateTests(unittest.TestCase):
    def run_preflight(self, evidence: Path, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                str(PREFLIGHT),
                "--root",
                str(REPOSITORY),
                "--evidence",
                str(evidence),
                *extra,
            ],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

    def mutated_fixture(self, mutate) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / "release-evidence.json"
        document = json.loads(FIXTURE.read_text())
        mutate(document)
        path.write_text(json.dumps(document) + "\n")
        return path

    def test_valid_prerelease_evidence_passes_schema_and_identity(self) -> None:
        result = self.run_preflight(FIXTURE, "--skip-git-state")

        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn("release evidence verification passed", result.stdout)

    def test_makefile_exposes_release_evidence_verification(self) -> None:
        result = subprocess.run(
            [
                "make",
                "--no-print-directory",
                "verify-release-evidence",
                f"EVIDENCE={FIXTURE}",
                "RELEASE_PREFLIGHT_FLAGS=--skip-git-state",
            ],
            cwd=REPOSITORY,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn("release evidence verification passed", result.stdout)

    def test_rejects_wrong_repository_and_digest_shape(self) -> None:
        evidence = self.mutated_fixture(
            lambda document: (
                document.update({"repository": "other/project"}),
                document["artifact"].update({"sha256": "abc"}),
            )
        )

        result = self.run_preflight(evidence, "--skip-git-state")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("repository must be superops-team/my-omarchy", result.stdout)
        self.assertIn("artifact.sha256 must be a 64-character lowercase hex digest", result.stdout)

    def test_prerelease_requires_a_passing_device(self) -> None:
        evidence = self.mutated_fixture(
            lambda document: document["deviceQualification"].update({"devices": []})
        )

        result = self.run_preflight(evidence, "--skip-git-state")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("prerelease evidence requires at least one passing device", result.stdout)

    def test_stable_requires_two_devices_and_version_coverage(self) -> None:
        evidence = self.mutated_fixture(
            lambda document: document.update({"gateProfile": "stable"})
        )

        result = self.run_preflight(evidence, "--skip-git-state")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("stable evidence requires at least two passing devices", result.stdout)
        self.assertIn("stable evidence must cover minimum and latest macOS labels", result.stdout)

    def test_local_release_preflight_is_closed_by_default(self) -> None:
        result = subprocess.run(
            [str(PREFLIGHT), "--root", str(REPOSITORY)],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        self.assertNotEqual(0, result.returncode)
        self.assertIn("--evidence is required", result.stdout)


if __name__ == "__main__":
    unittest.main()
