#!/usr/bin/env python3
"""Regression tests for tools/check_no_xctest_imports.py.

Run:
  python3 tools/check_no_xctest_imports_test.py
"""
from __future__ import annotations

import sys
import time
import unittest
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_no_xctest_imports as check  # noqa: E402

TEST_FILE = PurePosixPath("Packages/Core/Tests/CoreTests/ATests.swift")


class ImportFormTests(unittest.TestCase):
    def test_real_imports_are_violations(self) -> None:
        for source in (
            "import XCTest\n",
            "  import XCTest\n",
            "@testable import XCTest\n",
            "@preconcurrency import XCTest\n",
            "import class XCTest.XCTestCase\n",
            "public import XCTest\n",
            "package import XCTest\n",
            "internal import XCTest\n",
            "fileprivate import XCTest\n",
            "private import XCTest\n",
            "@preconcurrency internal import XCTest\n",
            "import Foundation; import XCTest\n",
            'let s = "a"; import XCTest\n',
            "let u = 1 / 2; import XCTest\n",
            "/* note */ import XCTest\n",
            "public /* note */ import XCTest\n",
        ):
            with self.subTest(source=source):
                self.assertEqual(check.violation_line(TEST_FILE, source), 1)

    def test_text_that_is_not_code_is_not_a_violation(self) -> None:
        for source in (
            "// import XCTest\n",
            "/// import XCTest\n",
            "// note; import XCTest\n",
            "/*\nimport XCTest\n*/\nimport Testing\n",
            "/* outer /* inner */\nimport XCTest\n*/\nimport Testing\n",
            'let example = """\nimport XCTest\n"""\n',
            'let example = #"""\n"""\nimport XCTest\n"""#\n',
            'let s = "a; import XCTest"\n',
            'let s = "\\"; import XCTest"\n',
            'let s = #"\\"; import XCTest"#\n',
            "import XCTestDynamicOverlay\n",
        ):
            with self.subTest(source=source):
                self.assertIsNone(check.violation_line(TEST_FILE, source))

    def test_line_number_counts_lines_in_comments_and_strings(self) -> None:
        source = '/*\nnote\n*/\nlet s = """\ntext\n"""\nimport XCTest\n'
        self.assertEqual(check.violation_line(TEST_FILE, source), 7)

    def test_long_line_in_a_string_stays_fast(self) -> None:
        source = 'let a = """\n' + "A" * 1_000_000 + '\n"""\nimport XCTest\n'
        started = time.monotonic()
        self.assertEqual(check.violation_line(TEST_FILE, source), 4)
        self.assertLess(time.monotonic() - started, 5)

    def test_code_after_a_stray_quote_on_an_earlier_line_is_still_read(self) -> None:
        self.assertEqual(check.violation_line(TEST_FILE, 'let s = "open\nimport XCTest\n'), 2)


class ExceptionTests(unittest.TestCase):
    UI_FILE = PurePosixPath("Alike/AlikeUITests/ATests.swift")
    PERFORMANCE_FILE = PurePosixPath("Alike/AlikeTests/APerformanceTests.swift")

    def test_ui_test_needs_folder_and_use_in_code(self) -> None:
        use = "import XCTest\nlet app = XCUIApplication()\n"
        self.assertIsNone(check.violation_line(self.UI_FILE, use))
        self.assertEqual(check.violation_line(TEST_FILE, use), 1)
        for source in (
            "import XCTest\n",
            "import XCTest\n// XCUIApplication()\n",
            'import XCTest\nlet s = "XCUIApplication()"\n',
        ):
            with self.subTest(source=source):
                self.assertEqual(check.violation_line(self.UI_FILE, source), 1)

    def test_performance_test_needs_file_name_and_call_in_code(self) -> None:
        use = "import XCTest\nfunc t() { measure { } }\n"
        self.assertIsNone(check.violation_line(self.PERFORMANCE_FILE, use))
        self.assertEqual(check.violation_line(TEST_FILE, use), 1)
        for source in (
            "import XCTest\n",
            "import XCTest\n// measure(\n",
            'import XCTest\nlet s = "measure("\n',
        ):
            with self.subTest(source=source):
                self.assertEqual(check.violation_line(self.PERFORMANCE_FILE, source), 1)


if __name__ == "__main__":
    unittest.main()
