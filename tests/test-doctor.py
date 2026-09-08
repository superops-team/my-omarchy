#!/usr/bin/env python3

from __future__ import annotations

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import textwrap
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
DOCTOR = REPOSITORY / "scripts/doctor.sh"


class DoctorTests(unittest.TestCase):
    def run_doctor(self, *, swift_status: int = 0) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary_directory = root / "bin"
            binary_directory.mkdir()
            calls = root / "calls"

            commands = {
                "uname": textwrap.dedent(
                    """
                    case "${1:-}" in
                      -s) printf '%s\n' "${DOCTOR_TEST_UNAME:-Darwin}" ;;
                      -m) printf '%s\n' "${DOCTOR_TEST_ARCH:-arm64}" ;;
                      *) exit 64 ;;
                    esac
                    """
                ).strip(),
                "sw_vers": "printf '%s\n' \"${DOCTOR_TEST_MACOS:-15.6}\"",
                "docker": "printf '%s\\n' 'Docker version 28.0.0'",
                "swift": textwrap.dedent(
                    """
                    printf '%s\n' "$*" >>"$DOCTOR_TEST_CALLS"
                    exit "${DOCTOR_TEST_SWIFT_STATUS:-0}"
                    """
                ).strip(),
                "swiftc": "exit 0",
                "xcrun": "exit 0",
                "curl": "exit 0",
                "pkg-config": "exit 0",
                "python3": "exit 0",
            }
            for name, body in commands.items():
                path = binary_directory / name
                path.write_text(f"#!/bin/bash\nset -eu\n{body}\n")
                path.chmod(path.stat().st_mode | stat.S_IXUSR)

            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{binary_directory}:/usr/bin:/bin",
                    "DOCTOR_TEST_CALLS": str(calls),
                    "DOCTOR_TEST_SWIFT_STATUS": str(swift_status),
                }
            )
            result = subprocess.run(
                [str(DOCTOR)],
                cwd=REPOSITORY,
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            result.swift_calls = calls.read_text() if calls.exists() else ""  # type: ignore[attr-defined]
            return result

    def test_reports_unbuildable_swift_test_package(self) -> None:
        result = self.run_doctor(swift_status=1)

        self.assertNotEqual(0, result.returncode)
        self.assertIn("Swift package tests cannot build", result.stdout)
        self.assertIn("--build-tests", result.swift_calls)  # type: ignore[attr-defined]
        self.assertIn("--disable-sandbox", result.swift_calls)  # type: ignore[attr-defined]

    def test_accepts_toolchain_that_builds_swift_test_package(self) -> None:
        result = self.run_doctor()

        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn("Toolchain ready: 15.6", result.stdout)
        self.assertIn("--package-path", result.swift_calls)  # type: ignore[attr-defined]
        self.assertIn("--build-tests", result.swift_calls)  # type: ignore[attr-defined]


if __name__ == "__main__":
    unittest.main()
