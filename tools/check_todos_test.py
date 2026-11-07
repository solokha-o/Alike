#!/usr/bin/env python3
"""Regression tests for tools/check_todos.py.

Run:
  python3 tools/check_todos_test.py
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_todos as check  # noqa: E402

# The markers are built from parts, so this file never holds a real marker.
todo = "TO" + "DO"
fixme = "FIX" + "ME"
hack = "HA" + "CK"
xxx = "X" + "XX"


def findings(name: str, text: str) -> list[tuple[int, str]]:
    return check.file_findings(PurePosixPath(name), text.encode("utf-8"))


class ScriptCommentTests(unittest.TestCase):
    def test_marker_without_link_is_a_finding(self) -> None:
        for marker in (todo, fixme, hack):
            with self.subTest(marker=marker):
                self.assertEqual(
                    findings("tools/a.py", f"x = 1\n# {marker}: remove this\n"),
                    [(2, f"{marker} without a card link")],
                )

    def test_marker_with_card_link_passes(self) -> None:
        for link in ("(#123)", "(https://github.com/solokha-o/Alike/issues/12)"):
            with self.subTest(link=link):
                self.assertEqual(findings("tools/a.sh", f"# {todo}{link}: remove this\n"), [])

    def test_malformed_link_is_a_finding(self) -> None:
        for link in ("(123)", "(#)", "(http://example.com)", " (#123)", "(PROJ-789)"):
            with self.subTest(link=link):
                self.assertEqual(len(findings("tools/a.rb", f"# {todo}{link}: remove this\n")), 1)

    def test_xxx_is_always_a_finding(self) -> None:
        self.assertEqual(findings("tools/a.py", f"# {xxx}(#1): what is this\n"), [(1, f"{xxx} marker")])

    def test_marker_outside_a_comment_is_ignored(self) -> None:
        self.assertEqual(findings("tools/a.py", f'NAME = "{todo}"\nprint("{xxx}")\n'), [])

    def test_lowercase_and_longer_words_are_ignored(self) -> None:
        self.assertEqual(findings("tools/a.py", f"# todo-management, {todo}s, {todo}_LIST\n"), [])

    def test_extensionless_script_with_shebang_is_checked(self) -> None:
        self.assertEqual(len(findings("tools/lint", f"#!/usr/bin/env bash\n# {hack}: x\n")), 1)

    def test_extensionless_file_without_shebang_is_ignored(self) -> None:
        self.assertEqual(findings("tools/package-categories", f"# {todo}: x\n"), [])

    def test_fastlane_files_are_ruby(self) -> None:
        self.assertEqual(len(findings("fastlane/Fastfile", f"# {fixme}: x\n")), 1)

    def test_markdown_is_not_checked(self) -> None:
        self.assertEqual(findings("Docs/a.md", f"# {todo}: x\n// {xxx}\n"), [])


class SwiftCommentTests(unittest.TestCase):
    def test_xxx_in_a_line_comment_is_a_finding(self) -> None:
        self.assertEqual(findings("Packages/Core/A.swift", f"let a = 1 // {xxx} why\n"), [(1, f"{xxx} marker")])

    def test_xxx_in_a_block_comment_is_a_finding(self) -> None:
        source = f"/*\n note\n {xxx} why\n*/\nlet a = 1\n"
        self.assertEqual(findings("Packages/Core/A.swift", source), [(3, f"{xxx} marker")])

    def test_xxx_after_a_closed_block_comment_is_ignored(self) -> None:
        self.assertEqual(findings("Packages/Core/A.swift", f'/* a */ let s = "{xxx}"\n'), [])

    def test_todo_without_link_is_left_to_swiftlint(self) -> None:
        self.assertEqual(findings("Packages/Core/A.swift", f"// {todo}: x\n// {fixme}: y\n"), [])

    def test_xxx_in_a_string_is_ignored(self) -> None:
        self.assertEqual(findings("Packages/Core/A.swift", f'let phone = "{xxx}-{xxx}"\n'), [])


class PathTests(unittest.TestCase):
    def test_vendored_and_build_paths_are_skipped(self) -> None:
        for path in (
            "Skills/External/swift-concurrency/scripts/a.py",
            "Packages/Settings/.build/checkouts/x/a.py",
            "build/reports/a.py",
        ):
            with self.subTest(path=path):
                self.assertFalse(check.is_candidate_path(PurePosixPath(path)))

    def test_first_party_paths_are_checked(self) -> None:
        for path in ("tools/lint", "Skills/Workflow/a/scripts/a.sh", "Alike/Alike/App.swift"):
            with self.subTest(path=path):
                self.assertTrue(check.is_candidate_path(PurePosixPath(path)))


if __name__ == "__main__":
    unittest.main()
