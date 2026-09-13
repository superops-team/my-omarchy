#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
INSTALLER = REPOSITORY / "scripts/install-my-omarchy.sh"
INSTALLERS = {
    "v0.3.1": {
        "bundle_version": "0.4.0",
        "asset": "MyOmarchy-0.3.1-arm64-unsigned.dmg",
        "sha256": "e66f4dcbc266e803efc610eac502c1e9297286a1b02f72d37d27e75e95143ed3",
    },
    "v0.4.0": {
        "bundle_version": "0.4.0",
        "asset": "MyOmarchy-0.4.0-arm64-unsigned.dmg",
        "sha256": "6f2972a1ce0d7c734e4330f67d7ad3f8f2c9b80c325898bd4c2f8c0f60ee7968",
    },
    "v0.5.0": {
        "bundle_version": "0.5.0",
        "asset": "MyOmarchy-0.5.0-arm64-unsigned.dmg",
        "sha256": "4bd2b39e66bcb7b952f5ea9d90ba85b48268f91295375c0b7257f451349801fa",
    },
}
RENDERER_SPEC = importlib.util.spec_from_file_location(
    "render_release_installers",
    REPOSITORY / "scripts/render-release-installers.py",
)
assert RENDERER_SPEC is not None and RENDERER_SPEC.loader is not None
renderer = importlib.util.module_from_spec(RENDERER_SPEC)
RENDERER_SPEC.loader.exec_module(renderer)


class InstallerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        system = subprocess.run(
            ["/usr/bin/uname", "-s"],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout.strip()
        if system != "Darwin":
            raise unittest.SkipTest("installer integration tests require macOS")

    def make_dmg(
        self,
        root: Path,
        *,
        bundle_identifier: str = "team.superops.myomarchy",
        bundle_version: str = "0.5.0",
        architecture: str = "arm64",
        break_signature: bool = False,
    ) -> Path:
        source = root / "source"
        app = source / "My Omarchy.app"
        executable = app / "Contents/MacOS/my-omarchy"
        executable.parent.mkdir(parents=True)
        with (app / "Contents/Info.plist").open("wb") as output:
            plistlib.dump(
                {
                    "CFBundleExecutable": "my-omarchy",
                    "CFBundleIdentifier": bundle_identifier,
                    "CFBundleName": "My Omarchy",
                    "CFBundlePackageType": "APPL",
                    "CFBundleShortVersionString": bundle_version,
                    "CFBundleVersion": "1",
                },
                output,
            )
        program = root / "main.c"
        program.write_text("int main(void) { return 0; }\n", encoding="ascii")
        subprocess.run(
            [
                "/usr/bin/xcrun",
                "clang",
                "-arch",
                architecture,
                str(program),
                "-o",
                str(executable),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        subprocess.run(
            ["/usr/bin/codesign", "--force", "--sign", "-", str(app)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        subprocess.run(
            ["/usr/bin/xattr", "-w", "com.apple.quarantine", "0081;test;installer", str(app)],
            check=True,
        )
        if break_signature:
            executable.write_bytes(executable.read_bytes() + b"broken")
        dmg = root / "fixture.dmg"
        subprocess.run(
            [
                "/usr/bin/hdiutil",
                "create",
                "-srcfolder",
                str(source),
                "-fs",
                "APFS",
                "-format",
                "UDZO",
                str(dmg),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        return dmg

    def run_installer(
        self, dmg: Path, install_root: Path, **overrides: str
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "MY_OMARCHY_INSTALLER_TEST_MODE": "1",
                "MY_OMARCHY_INSTALLER_TEST_DMG_PATH": str(dmg),
                "MY_OMARCHY_INSTALLER_TEST_DMG_SHA256": hashlib.sha256(
                    dmg.read_bytes()
                ).hexdigest(),
                "MY_OMARCHY_INSTALLER_TEST_INSTALL_ROOT": str(install_root),
                "MY_OMARCHY_INSTALLER_TEST_SYSTEM_NAME": "Darwin",
                "MY_OMARCHY_INSTALLER_TEST_ARCHITECTURE": "arm64",
                "MY_OMARCHY_INSTALLER_TEST_SYSTEM_VERSION": "15.0",
                "MY_OMARCHY_INSTALLER_TEST_SKIP_LAUNCH": "1",
            }
        )
        environment.update(overrides)
        return subprocess.run(
            ["/bin/bash", str(INSTALLER)],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=environment,
        )

    def test_each_existing_release_has_an_immutable_installer(self) -> None:
        for tag, expected in INSTALLERS.items():
            with self.subTest(tag=tag):
                path = (
                    REPOSITORY
                    / "scripts"
                    / "release-installers"
                    / tag
                    / "install-my-omarchy.sh"
                )
                source = path.read_text(encoding="utf-8")
                self.assertEqual(
                    renderer.render(tag, renderer.RELEASES[tag]), path.read_bytes()
                )
                self.assertIn(f"release_tag='{tag}'", source)
                self.assertIn(
                    f"bundle_version='{expected['bundle_version']}'", source
                )
                self.assertIn(f"dmg_asset='{expected['asset']}'", source)
                self.assertIn(f"dmg_sha256='{expected['sha256']}'", source)
                self.assertNotIn("/releases/latest/", source)
                self.assertNotIn("/raw/main/", source)
                syntax = subprocess.run(
                    ["/bin/bash", "-n", str(path)],
                    check=False,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                )
                self.assertEqual(0, syntax.returncode, syntax.stdout)

        current = REPOSITORY / "scripts/install-my-omarchy.sh"
        release = (
            REPOSITORY
            / "scripts/release-installers/v0.5.0/install-my-omarchy.sh"
        )
        self.assertEqual(current.read_bytes(), release.read_bytes())
        readme = (REPOSITORY / "README.md").read_text(encoding="utf-8")
        self.assertIn(
            "https://github.com/superops-team/my-omarchy/releases/download/"
            "v0.5.0/install-my-omarchy.sh",
            readme,
        )

    def test_installs_a_verified_app_without_touching_vm_data(self) -> None:
        with tempfile.TemporaryDirectory(prefix="my-omarchy installer " ) as temporary:
            root = Path(temporary)
            install_root = root / "Applications"
            install_root.mkdir()
            vm_data = root / "Application Support/My Omarchy/VM/v1/disk"
            vm_data.parent.mkdir(parents=True)
            vm_data.write_text("preserve me\n", encoding="utf-8")
            dmg = self.make_dmg(root)

            result = self.run_installer(dmg, install_root)

            self.assertEqual(0, result.returncode, result.stdout)
            installed = install_root / "My Omarchy.app"
            self.assertTrue(installed.is_dir())
            attributes = subprocess.run(
                ["/usr/bin/xattr", str(installed)],
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            ).stdout.splitlines()
            self.assertNotIn("com.apple.quarantine", attributes)
            self.assertEqual("preserve me\n", vm_data.read_text(encoding="utf-8"))
            self.assertIn("My Omarchy v0.5.0 is installed", result.stdout)

    def test_rejects_bad_checksum_and_running_vm_before_replacing_app(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            install_root = root / "Applications"
            old_app = install_root / "My Omarchy.app"
            old_app.mkdir(parents=True)
            marker = old_app / "old"
            marker.write_text("keep\n", encoding="utf-8")
            dmg = self.make_dmg(root)

            bad_checksum = self.run_installer(
                dmg,
                install_root,
                MY_OMARCHY_INSTALLER_TEST_DMG_SHA256="0" * 64,
            )
            self.assertNotEqual(0, bad_checksum.returncode)
            self.assertIn("checksum does not match", bad_checksum.stdout)
            self.assertTrue(marker.exists())

            running = self.run_installer(
                dmg, install_root, MY_OMARCHY_INSTALLER_TEST_VM_RUNNING="1"
            )
            self.assertNotEqual(0, running.returncode)
            self.assertIn("virtual machine is running", running.stdout)
            self.assertTrue(marker.exists())

    def test_rejects_wrong_app_identity_before_replacing_existing_app(self) -> None:
        cases = {
            "bundle identifier": {"bundle_identifier": "example.invalid"},
            "version": {"bundle_version": "9.9.9"},
            "arm64": {"architecture": "x86_64"},
            "code-signature": {"break_signature": True},
        }
        for expected_message, options in cases.items():
            with self.subTest(expected_message=expected_message), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                install_root = root / "Applications"
                old_app = install_root / "My Omarchy.app"
                old_app.mkdir(parents=True)
                marker = old_app / "old"
                marker.write_text("keep\n", encoding="utf-8")
                dmg = self.make_dmg(root, **options)

                result = self.run_installer(dmg, install_root)

                self.assertNotEqual(0, result.returncode, result.stdout)
                self.assertIn(expected_message, result.stdout)
                self.assertTrue(marker.exists())

    def test_restores_existing_app_when_install_fails_after_backup(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            install_root = root / "Applications"
            old_app = install_root / "My Omarchy.app"
            old_app.mkdir(parents=True)
            marker = old_app / "old"
            marker.write_text("keep\n", encoding="utf-8")
            dmg = self.make_dmg(root)

            result = self.run_installer(
                dmg,
                install_root,
                MY_OMARCHY_INSTALLER_TEST_FAIL_AFTER_BACKUP="1",
            )

            self.assertNotEqual(0, result.returncode)
            self.assertIn("simulated failure after backup", result.stdout)
            self.assertEqual("keep\n", marker.read_text(encoding="utf-8"))
            self.assertFalse(any(install_root.glob(".My Omarchy.*.app")))

    def test_removes_new_app_when_first_install_fails_after_move(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            install_root = root / "Applications"
            install_root.mkdir()
            dmg = self.make_dmg(root)

            result = self.run_installer(
                dmg,
                install_root,
                MY_OMARCHY_INSTALLER_TEST_FAIL_AFTER_INSTALL="1",
            )

            self.assertNotEqual(0, result.returncode)
            self.assertIn("simulated failure after install", result.stdout)
            self.assertFalse((install_root / "My Omarchy.app").exists())
            self.assertFalse(any(install_root.glob(".My Omarchy.*.app")))

    def test_rejects_a_symbolic_link_install_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            install_root = root / "Applications"
            install_root.mkdir()
            outside = root / "outside.app"
            outside.mkdir()
            target = install_root / "My Omarchy.app"
            target.symlink_to(outside, target_is_directory=True)
            dmg = self.make_dmg(root)

            result = self.run_installer(dmg, install_root)

            self.assertNotEqual(0, result.returncode)
            self.assertIn("symbolic link", result.stdout)
            self.assertTrue(target.is_symlink())
            self.assertTrue(outside.is_dir())


if __name__ == "__main__":
    unittest.main()
