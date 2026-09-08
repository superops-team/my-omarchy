#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
CONTRACT_PATH = REPOSITORY / "config/product-identity.json"
SCHEMA_PATH = REPOSITORY / "config/product-identity.schema.json"


class ProductIdentityContractTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
