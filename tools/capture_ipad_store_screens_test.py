#!/usr/bin/env python3
"""Tests for the argument checks of capture_ipad_store_screens.py: no
combination may save one screen under the name of another."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import capture_ipad_store_screens as capture  # noqa: E402


class ArgumentErrorTests(unittest.TestCase):
    def test_launched_captures_of_all_locales_are_safe(self) -> None:
        self.assertIsNone(capture.argument_error(list(capture.LOCALES), None, False))

    def test_one_launched_screen_is_safe(self) -> None:
        self.assertIsNone(capture.argument_error(["uk"], "03-cleanup-queue", False))

    def test_manual_screen_with_one_locale_is_safe(self) -> None:
        self.assertIsNone(capture.argument_error(["uk"], "07-cleanup-progress", True))

    def test_no_launch_needs_one_screen(self) -> None:
        self.assertIn("--only", capture.argument_error(["uk"], None, True))

    def test_no_launch_needs_one_locale(self) -> None:
        self.assertIn("--locales", capture.argument_error(["uk", "de"], "07-cleanup-progress", True))

    def test_manual_screen_needs_no_launch(self) -> None:
        self.assertIn("--no-launch", capture.argument_error(["uk"], "07-cleanup-progress", False))

    def test_unknown_locale_and_screen_are_refused(self) -> None:
        self.assertIn("Unknown locales", capture.argument_error(["xx"], None, False))
        self.assertIn("Unknown screen", capture.argument_error(["uk"], "09-nothing", False))


if __name__ == "__main__":
    unittest.main()
