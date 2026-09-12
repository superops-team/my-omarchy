#!/usr/bin/env python3

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class VenusSourcePinTests(unittest.TestCase):
    def test_virglrenderer_uses_immutable_commit_archive(self) -> None:
        sources = json.loads((ROOT / "venus-sources.json").read_text())
        virglrenderer = sources["virglrenderer"]

        commit = "ca50e008863837e094747a69974dde3ae148aeaa"
        self.assertIn(f"/archive/{commit}/", virglrenderer["url"])
        self.assertNotIn("ref_type=tags", virglrenderer["url"])
        self.assertEqual(
            "e7c512469a207444103ead88a8992a7077173e21771623845d4567f8128b5dc1",
            virglrenderer["sha256"],
        )


if __name__ == "__main__":
    unittest.main()
