#!/usr/bin/env python3
"""Regression tests for tools/symbolicate_crash_payload.py.

Run:
  python3 tools/symbolicate_crash_payload_test.py
"""
from __future__ import annotations

import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import symbolicate_crash_payload as symbolicate  # noqa: E402

DWARF = "Alike.app.dSYM/Contents/Resources/DWARF/Alike"


class DsymIndexZipTests(unittest.TestCase):
    def test_same_named_zips_keep_each_build_symbols(self) -> None:
        with tempfile.TemporaryDirectory() as workspace:
            roots = []
            for build in ("1", "2"):
                root = Path(workspace) / f"build-{build}"
                root.mkdir()
                with zipfile.ZipFile(root / "dSYMs.zip", "w") as archive:
                    archive.writestr(DWARF, build)
                roots.append(root)

            def fake_run(*command: str) -> str:
                # `dwarfdump --uuid <bundle>`: the UUID is the build number the DWARF holds.
                if command[:3] != ("xcrun", "dwarfdump", "--uuid"):
                    return ""
                dwarf = Path(command[3]) / "Contents/Resources/DWARF/Alike"
                build = dwarf.read_text()
                return f"UUID: {build * 8}-0000-0000-0000-000000000000 (arm64) {dwarf}\n"

            index = symbolicate.DsymIndex(roots)
            with mock.patch.object(symbolicate, "run", fake_run):
                index.scan()

            contents = {uuid[0]: path.read_text() for uuid, path in index.by_uuid.items()}
            self.assertEqual(contents, {"1": "1", "2": "2"})


if __name__ == "__main__":
    unittest.main()
