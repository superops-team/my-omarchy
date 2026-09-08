#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
CONTRACT_PATH = REPOSITORY / "config/product-identity.json"
SCHEMA_PATH = REPOSITORY / "config/product-identity.schema.json"
ALLOWLIST_PATH = REPOSITORY / "config/legacy-identity-allowlist.json"
SCANNER = REPOSITORY / "scripts/verify-product-identity.py"
CONTRACT_VALIDATOR = REPOSITORY / "scripts/verify-product-contract.py"


class ProductIdentityContractTests(unittest.TestCase):
    def run_contract_validator(self, mutate) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            contract = json.loads(CONTRACT_PATH.read_text())
            mutate(contract)
            contract_path = root / "product-identity.json"
            contract_path.write_text(json.dumps(contract) + "\n")
            return subprocess.run(
                [
                    str(CONTRACT_VALIDATOR),
                    "--contract",
                    str(contract_path),
                    "--schema",
                    str(SCHEMA_PATH),
                ],
                cwd=REPOSITORY,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )

    def test_contract_contains_the_approved_my_omarchy_identity(self) -> None:
        contract = json.loads(CONTRACT_PATH.read_text())

        self.assertEqual(1, contract["schemaVersion"])
        self.assertEqual(
            {
                "displayName": "My Omarchy",
                "slug": "my-omarchy",
                "compactName": "MyOmarchy",
            },
            contract["product"],
        )
        self.assertEqual("superops-team", contract["repository"]["owner"])
        self.assertEqual("my-omarchy", contract["repository"]["name"])
        self.assertEqual(
            "https://github.com/superops-team/my-omarchy",
            contract["repository"]["url"],
        )
        self.assertEqual(
            f'{contract["repository"]["url"]}/releases',
            contract["repository"]["releasesUrl"],
        )
        self.assertEqual(
            f'{contract["repository"]["url"]}/issues',
            contract["repository"]["issuesUrl"],
        )
        self.assertEqual("team.superops.myomarchy", contract["macos"]["bundleIdentifier"])
        self.assertEqual("My Omarchy.app", contract["macos"]["appBundleName"])
        self.assertEqual("my-omarchy", contract["macos"]["executableName"])
        self.assertEqual("MyOmarchy", contract["macos"]["moduleName"])
        self.assertEqual("My Omarchy", contract["macos"]["bundledQemuExecutableName"])
        self.assertEqual("My Omarchy/VM/v1", contract["storage"]["applicationSupportRelativePath"])
        self.assertEqual("my-omarchy", contract["storage"]["productIdentity"])
        self.assertEqual("myomarchy.", contract["guest"]["kernelParameterPrefix"])
        self.assertEqual("my-omarchy-", contract["guest"]["packagePrefix"])
        self.assertEqual("team.superops.myomarchy.", contract["runtime"]["virtioPortPrefix"])
        self.assertEqual("MyOmarchy-<semver>-arm64.dmg", contract["release"]["dmgPattern"])

    def test_schema_closes_every_object_to_unreviewed_fields(self) -> None:
        schema = json.loads(SCHEMA_PATH.read_text())

        objects = [schema]
        objects.extend(schema["properties"][name] for name in schema["required"] if name != "schemaVersion")
        for object_schema in objects:
            self.assertFalse(object_schema["additionalProperties"])
            self.assertEqual(
                set(object_schema["properties"]),
                set(object_schema["required"]),
            )

    def test_standard_library_validator_rejects_missing_and_extra_fields(self) -> None:
        missing = self.run_contract_validator(lambda document: document["product"].pop("slug"))
        extra = self.run_contract_validator(lambda document: document["product"].update({"alias": "other"}))

        self.assertNotEqual(0, missing.returncode)
        self.assertIn("missing required field product.slug", missing.stdout)
        self.assertNotEqual(0, extra.returncode)
        self.assertIn("unreviewed field product.alias", extra.stdout)

    def test_standard_library_validator_rejects_identity_drift(self) -> None:
        result = self.run_contract_validator(
            lambda document: document["repository"].update(
                {"issuesUrl": document["repository"]["url"] + "/wrong"}
            )
        )

        self.assertNotEqual(0, result.returncode)
        self.assertIn("repository.issuesUrl must equal the approved value", result.stdout)

    def test_makefile_exposes_the_baseline_identity_gate(self) -> None:
        result = subprocess.run(
            ["make", "--no-print-directory", "verify-identity"],
            cwd=REPOSITORY,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )

        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn("product identity baseline verification passed", result.stdout)

    def test_phase_1b_brand_entries_are_cleared_from_the_allowlist(self) -> None:
        allowlist = json.loads(ALLOWLIST_PATH.read_text())

        self.assertEqual(
            [],
            [
                entry
                for entry in allowlist["entries"]
                if entry["ownerPhase"] == "1B"
            ],
        )


class LegacyIdentityScannerTests(unittest.TestCase):
    def run_scanner(
        self, files: dict[str, str], allowlist: list[dict[str, object]], mode: str
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative, contents in files.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents)
            config = root / "config"
            config.mkdir(exist_ok=True)
            allowlist_path = config / "legacy-identity-allowlist.json"
            allowlist_path.write_text(
                json.dumps({"schemaVersion": 1, "entries": allowlist}) + "\n"
            )
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            return subprocess.run(
                [
                    str(SCANNER),
                    "--root",
                    str(root),
                    "--allowlist",
                    str(allowlist_path),
                    "--mode",
                    mode,
                ],
                cwd=REPOSITORY,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )

    def test_unregistered_legacy_identity_fails_both_modes(self) -> None:
        files = {"app.txt": "Try Omarchy\n"}

        for mode in ("baseline", "release"):
            result = self.run_scanner(files, [], mode)
            self.assertNotEqual(0, result.returncode)
            self.assertIn("unallowlisted legacy identity", result.stdout)
            self.assertIn("legacy-display-name", result.stdout)

    def test_legacy_identity_in_tracked_path_is_scanned(self) -> None:
        result = self.run_scanner({"Sources/OmarchyVMHelper/main.swift": "clean\n"}, [], "baseline")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("Sources/OmarchyVMHelper/main.swift", result.stdout)
        self.assertIn("legacy-swift-module", result.stdout)

    def test_current_my_omarchy_runtime_names_are_not_legacy_matches(self) -> None:
        result = self.run_scanner(
            {"build.sh": "tmp=/private/tmp/my-omarchy-qemu-gpu-runtime.123\n"},
            [],
            "release",
        )

        self.assertEqual(0, result.returncode, result.stdout)

    def test_exact_baseline_entry_passes_only_baseline(self) -> None:
        entry = {
            "path": "app.txt",
            "pattern": "legacy-display-name",
            "expectedCount": 1,
            "category": "host-identity",
            "ownerPhase": "1C",
            "reason": "Existing host branding awaiting Phase 1C.",
        }

        baseline = self.run_scanner({"app.txt": "Try Omarchy\n"}, [entry], "baseline")
        release = self.run_scanner({"app.txt": "Try Omarchy\n"}, [entry], "release")

        self.assertEqual(0, baseline.returncode, baseline.stdout)
        self.assertNotEqual(0, release.returncode)
        self.assertIn("not permitted in release mode", release.stdout)
        self.assertIn("release blockers by ownerPhase: 1C=1 entry/1 occurrence", release.stdout)

    def test_release_accepts_only_precise_historical_reference(self) -> None:
        entry = {
            "path": "THIRD_PARTY_NOTICES.md",
            "pattern": "legacy-display-name",
            "expectedCount": 1,
            "category": "historical-attribution",
            "ownerPhase": "permanent",
            "reason": "Required historical attribution.",
        }

        result = self.run_scanner(
            {"THIRD_PARTY_NOTICES.md": "Derived from Try Omarchy.\n"},
            [entry],
            "release",
        )

        self.assertEqual(0, result.returncode, result.stdout)

    def test_count_drift_and_stale_entries_fail(self) -> None:
        entry = {
            "path": "app.txt",
            "pattern": "legacy-display-name",
            "expectedCount": 2,
            "category": "host-identity",
            "ownerPhase": "1C",
            "reason": "Existing host branding awaiting Phase 1C.",
        }

        drift = self.run_scanner({"app.txt": "Try Omarchy\n"}, [entry], "baseline")
        stale = self.run_scanner({"app.txt": "My Omarchy\n"}, [entry], "baseline")

        self.assertNotEqual(0, drift.returncode)
        self.assertIn("expected 2 occurrence(s), found 1", drift.stdout)
        self.assertNotEqual(0, stale.returncode)
        self.assertIn("expected 2 occurrence(s), found 0", stale.stdout)

    def test_allowlist_rejects_glob_paths_and_missing_ownership(self) -> None:
        invalid = {
            "path": "docs/*",
            "pattern": "legacy-display-name",
            "expectedCount": 1,
            "category": "host-identity",
            "ownerPhase": "",
            "reason": "",
        }

        result = self.run_scanner({"docs/readme.md": "Try Omarchy\n"}, [invalid], "baseline")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("allowlist entry is invalid", result.stdout)

    def test_allowlist_rejects_unknown_category_and_owner_phase(self) -> None:
        invalid = {
            "path": "app.txt",
            "pattern": "legacy-display-name",
            "expectedCount": 1,
            "category": "miscellaneous",
            "ownerPhase": "later",
            "reason": "Not a governed migration entry.",
        }

        result = self.run_scanner({"app.txt": "Try Omarchy\n"}, [invalid], "baseline")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("allowlist entry is invalid", result.stdout)


if __name__ == "__main__":
    unittest.main()
