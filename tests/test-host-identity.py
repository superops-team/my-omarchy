#!/usr/bin/env python3

from __future__ import annotations

import json
import plistlib
from pathlib import Path
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
CONTRACT = json.loads((REPOSITORY / "config/product-identity.json").read_text())


class HostIdentityTests(unittest.TestCase):
    def test_info_plist_matches_my_omarchy_contract(self) -> None:
        info = plistlib.loads((REPOSITORY / "macos/Info.plist").read_bytes())
        macos = CONTRACT["macos"]

        self.assertEqual("My Omarchy", info["CFBundleDisplayName"])
        self.assertEqual("My Omarchy", info["CFBundleName"])
        self.assertEqual(macos["executableName"], info["CFBundleExecutable"])
        self.assertEqual(macos["bundleIdentifier"], info["CFBundleIdentifier"])
        self.assertEqual("MyOmarchy.icns", info["CFBundleIconFile"])
        self.assertFalse(info.get("LSUIElement", False))
        for key in (
            "NSDesktopFolderUsageDescription",
            "NSDocumentsFolderUsageDescription",
            "NSDownloadsFolderUsageDescription",
            "NSCameraUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSRemovableVolumesUsageDescription",
        ):
            self.assertIn("My Omarchy", info[key])
            predecessor_name = "Try " + "Omarchy"
            self.assertNotIn(predecessor_name, info[key])

    def test_swift_package_uses_my_omarchy_module_and_executable(self) -> None:
        package = (REPOSITORY / "macos/Package.swift").read_text()

        self.assertIn('name: "MyOmarchy"', package)
        self.assertIn('.executable(name: "my-omarchy", targets: ["MyOmarchy"])', package)
        self.assertIn('.executableTarget(', package)
        self.assertIn('name: "MyOmarchy"', package)
        self.assertIn('resources: [.process("Resources")]', package)
        self.assertIn('url: "https://github.com/swiftlang/swift-testing.git"', package)
        self.assertIn('.product(name: "Testing", package: "swift-testing")', package)
        predecessor_module = "OmarchyVM" + "Helper"
        predecessor_executable = "omarchy-vm" + "-helper"
        self.assertNotIn(predecessor_module, package)
        self.assertNotIn(predecessor_executable, package)

    def test_build_entrypoints_use_my_omarchy_host_outputs(self) -> None:
        makefile = (REPOSITORY / "Makefile").read_text()
        build_app = (REPOSITORY / "macos/build-app.sh").read_text()

        self.assertIn("$(DIST)/app.noindex/My Omarchy.app", makefile)
        self.assertIn("$(DIST)/MyOmarchy.dmg", makefile)
        self.assertIn("'My Omarchy — native macOS build commands'", makefile)
        predecessor_heading = "Try " + "Omarchy — native macOS build commands"
        self.assertNotIn(predecessor_heading, makefile)
        self.assertIn('helper="$macos_dir/.build/release/my-omarchy"', build_app)
        self.assertIn('app="$repo_dir/dist/app.noindex/My Omarchy.app"', build_app)
        self.assertIn('bundled_qemu="$contents/Resources/runtime/bin/My Omarchy"', build_app)
        self.assertIn('generated_icon="$macos_dir/.build/MyOmarchy.icns"', build_app)
        self.assertIn('install -m 0755 "$helper" "$contents/MacOS/my-omarchy"', build_app)
        self.assertIn('install -m 0644 "$generated_icon" "$contents/Resources/MyOmarchy.icns"', build_app)
        self.assertIn('ditto "$resource_bundle" "$contents/Resources/MyOmarchy_MyOmarchy.bundle"', build_app)
        self.assertIn('--identifier team.superops.myomarchy', build_app)
        predecessor_bundle_id = "dev." + "try" + "omarchy.native"
        self.assertNotIn(predecessor_bundle_id, build_app)


if __name__ == "__main__":
    unittest.main()
