from pathlib import Path
import os
import subprocess
import tempfile
import unittest


COMMAND = Path(__file__).resolve().parents[1] / "native-overlay/usr/local/bin/my-omarchy-touch-id-test"


class TouchIDCommandTests(unittest.TestCase):
    def test_password_fallback_is_disabled_and_failure_is_propagated(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sudo = Path(directory) / "sudo"
            sudo.write_text(
                '#!/bin/sh\n'
                '[ "$1" = -k ] && exit 0\n'
                '[ "$1" = -A ] && [ "$2" = true ] && '
                '[ "$SUDO_ASKPASS" = /bin/false ] || exit 99\n'
                'exit "$CHECK_STATUS"\n'
            )
            sudo.chmod(0o755)
            for status in (0, 1):
                with self.subTest(status=status):
                    result = subprocess.run(
                        [str(COMMAND)],
                        env={**os.environ, "PATH": directory, "CHECK_STATUS": str(status)},
                        capture_output=True, text=True,
                    )
                    self.assertEqual(result.returncode, status)
                    if status:
                        self.assertIn("check failed", result.stderr)
                        self.assertEqual(result.stdout, "")
                    else:
                        self.assertIn("without a guest password", result.stdout)
