from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


GUEST = Path(__file__).resolve().parents[1]
INSTALLER = GUEST / "scripts/install-touch-id-sudo.sh"
PAM_LINE = "auth\t\tsufficient\tpam_exec.so quiet seteuid stdout /usr/local/lib/my-omarchy/native-authentication-broker pam"


class TouchIDInstallerTests(unittest.TestCase):
    def test_live_installer_migrates_existing_state_and_refreshes_the_menu(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertIn("native-authentication-broker migrate", source)
        self.assertIn("/usr/bin/omarchy menu refresh", source)

    def test_stages_dormant_components_without_changing_sudo_pam(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root"
            (root / "usr/bin").mkdir(parents=True)
            (root / "usr/lib/security").mkdir(parents=True)
            (root / "etc/pam.d").mkdir(parents=True)
            (root / "usr/bin/python3").symlink_to(sys.executable)
            openssl = root / "usr/bin/openssl"
            shutil.copyfile("/usr/bin/openssl", openssl)
            openssl.chmod(0o755)
            (root / "usr/lib/security/pam_exec.so").write_bytes(b"fixture")
            sudo_policy = root / "etc/pam.d/sudo"
            original_policy = "#%PAM-1.0\nauth include system-auth\n"
            sudo_policy.write_text(original_policy, encoding="utf-8")

            result = subprocess.run(
                [
                    str(INSTALLER),
                    "--root",
                    str(root),
                    "--guest-dir",
                    str(GUEST),
                ],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(sudo_policy.read_text(encoding="utf-8"), original_policy)
            self.assertNotIn(PAM_LINE, sudo_policy.read_text(encoding="utf-8"))
            for relative in (
                "usr/local/bin/my-omarchy-touch-id",
                "usr/local/bin/my-omarchy-touch-id-test",
                "usr/local/lib/my-omarchy/native-authentication-broker",
                "usr/local/sbin/my-omarchy-touch-id-control",
                "usr/local/sbin/my-omarchy-touch-id-enroll",
            ):
                installed = root / relative
                self.assertTrue(installed.is_file(), relative)
                self.assertTrue(os.access(installed, os.X_OK), relative)


if __name__ == "__main__":
    unittest.main()
