#!/usr/bin/env python3
"""Regression tests for tools/check_package_graph.py.

Run:
  python3 tools/check_package_graph_test.py
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_package_graph as check  # noqa: E402

LOTTIE = "https://github.com/airbnb/lottie-spm.git"


def manifest(name, local=(), remote=(), products=None):
    dependencies = [f'.package(path: "../{dependency}")' for dependency in local]
    dependencies += [f'.package(url: "{url}", from: "1.0.0")' for url in remote]
    libraries = ", ".join(f'.library(name: "{product}", targets: ["{product}"])' for product in products or [name])
    return (
        "// swift-tools-version: 6.0\n"
        "import PackageDescription\n"
        f'let package = Package(name: "{name}",\n'
        f"    products: [{libraries}],\n"
        f"    dependencies: [{', '.join(dependencies)}],\n"
        f'    targets: [.target(name: "{name}"), .testTarget(name: "{name}Tests")]\n'
        ")\n"
    )


class Fixture:
    """A small repository: Core and DesignSystem (Foundation), Cleanup and Details (Feature)."""

    def __init__(self, root):
        self.root = Path(root)
        self.categories = {"Core": "Foundation", "DesignSystem": "Foundation", "Cleanup": "Feature", "Details": "Feature"}
        self.allowlist = [f"sdk DesignSystem {LOTTIE}  # ADR-0004 SDK rule."]
        self.package("Core")
        self.package("DesignSystem", local=["Core"], remote=[LOTTIE])
        self.package("Cleanup", local=["Core", "DesignSystem"])
        self.package("Details", local=["Core"])

    def package(self, name, local=(), remote=(), source="import Foundation\n"):
        directory = self.root / "Packages" / name
        (directory / "Sources" / name).mkdir(parents=True, exist_ok=True)
        (directory / "Package.swift").write_text(manifest(name, local, remote), encoding="utf-8")
        imports = "".join(f"import {dependency}\n" for dependency in local)
        (directory / "Sources" / name / f"{name}.swift").write_text(imports + source, encoding="utf-8")

    def run(self):
        tools = self.root / "tools"
        tools.mkdir(exist_ok=True)
        lines = [f"{name} {category}" for name, category in self.categories.items()]
        (tools / "package-categories").write_text("# comment\n" + "\n".join(lines) + "\n", encoding="utf-8")
        (tools / "package-graph.allowlist").write_text("\n".join(self.allowlist) + "\n", encoding="utf-8")
        return check.check(self.root)


class RepositoryTests(unittest.TestCase):
    def test_current_repository_graph_passes(self) -> None:
        errors, levels, notes = check.check(check.REPOSITORY_ROOT)
        self.assertEqual(errors, [])
        self.assertEqual(notes, [])
        # The precondition: the App edges were read from the project file.
        self.assertIn("Alike", levels)
        self.assertEqual(levels["Core"], 0)
        self.assertGreater(levels["Alike"], levels["Scanner"])


class FixtureTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.fixture = Fixture(directory.name)

    def assert_one_error(self, text) -> None:
        errors, _, _ = self.fixture.run()
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(text, errors[0])

    def test_fixture_passes_and_reports_levels(self) -> None:
        errors, levels, notes = self.fixture.run()
        self.assertEqual(errors, [])
        self.assertEqual(levels, {"Core": 0, "Details": 1, "DesignSystem": 1, "Cleanup": 2})
        self.assertEqual(len(notes), 1)  # No project file, so no App edges.

    def test_feature_to_feature_edge_fails(self) -> None:
        self.fixture.package("Cleanup", local=["Core", "DesignSystem", "Details"])
        self.assert_one_error("Cleanup (Feature) -> Details (Feature)")

    def test_foundation_to_feature_edge_fails(self) -> None:
        self.fixture.package("Core", local=["Details"])
        errors, _, _ = self.fixture.run()
        self.assertTrue(any("Core (Foundation) -> Details (Feature)" in error for error in errors), errors)

    def test_edge_to_a_tool_fails(self) -> None:
        self.fixture.categories["Calibration"] = "Tool"
        self.fixture.package("Calibration", local=["Core"])
        self.fixture.package("Details", local=["Core", "Calibration"])
        self.assert_one_error("Details (Feature) -> Calibration (Tool)")

    def test_allowlisted_edge_with_reason_passes(self) -> None:
        self.fixture.package("Cleanup", local=["Core", "DesignSystem", "Details"])
        self.fixture.allowlist.append("edge Cleanup Details  # ADR-0099 accepts it.")
        errors, _, _ = self.fixture.run()
        self.assertEqual(errors, [])

    def test_allowlist_line_without_reason_fails(self) -> None:
        self.fixture.allowlist.append("edge Cleanup Details")
        errors, _, _ = self.fixture.run()
        self.assertTrue(any("give the reason" in error for error in errors), errors)

    def test_unused_allowlist_line_fails(self) -> None:
        self.fixture.allowlist.append("edge Cleanup Details  # stale.")
        self.assert_one_error("no current dependency uses `edge Cleanup Details`")

    def test_package_without_category_fails(self) -> None:
        self.fixture.package("Extra", local=["Core"])
        self.assert_one_error("Packages/Extra: no line in tools/package-categories")

    def test_category_for_missing_package_fails(self) -> None:
        self.fixture.categories["Ghost"] = "Foundation"
        self.assert_one_error("Ghost has no Packages/Ghost/Package.swift")

    def test_cycle_fails(self) -> None:
        self.fixture.package("Core", local=["DesignSystem"])
        errors, levels, _ = self.fixture.run()
        self.assertIsNone(levels)
        self.assertIn("Cycle: Core -> DesignSystem -> Core.", errors)

    def test_undeclared_local_import_fails(self) -> None:
        self.fixture.package("Details", local=["Core"], source="@_exported import DesignSystem\n")
        self.assert_one_error("Packages/Details/Sources/Details/Details.swift:2: imports DesignSystem")

    def test_import_in_a_comment_or_of_a_system_module_passes(self) -> None:
        self.fixture.package("Details", local=["Core"], source="// import DesignSystem\nimport SwiftUI\n")
        errors, _, _ = self.fixture.run()
        self.assertEqual(errors, [])

    def test_lottie_outside_design_system_fails(self) -> None:
        self.fixture.package("Details", local=["Core"], remote=[LOTTIE])
        self.assert_one_error(f"Details -> {LOTTIE}")


class AppProductTests(unittest.TestCase):
    PROJECT = (
        "/* Begin PBXNativeTarget section */\n"
        "\t\tA1 /* Alike */ = {\n"
        "\t\t\tisa = PBXNativeTarget;\n"
        "\t\t\tpackageProductDependencies = (\n"
        "\t\t\t\tB1 /* Core */,\n"
        "\t\t\t\tB2 /* Cleanup */,\n"
        "\t\t\t);\n"
        "\t\t\tproductName = Alike;\n"
        "\t\t};\n"
        "/* End PBXNativeTarget section */\n"
        "\t\tB1 /* Core */ = {\n"
        "\t\t\tisa = XCSwiftPackageProductDependency;\n"
        "\t\t\tproductName = Core;\n"
        "\t\t};\n"
        "\t\tB2 /* Cleanup */ = {\n"
        "\t\t\tisa = XCSwiftPackageProductDependency;\n"
        "\t\t\tproductName = Cleanup;\n"
        "\t\t};\n"
    )

    def test_app_edges_come_from_the_project_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = Fixture(directory)
            fixture.categories["Alike"] = "App"
            project = fixture.root / check.PBXPROJ_FILE
            project.parent.mkdir(parents=True)
            project.write_text(self.PROJECT, encoding="utf-8")
            errors, levels, notes = fixture.run()
        self.assertEqual((errors, notes), ([], []))
        self.assertEqual(levels["Alike"], 3)


if __name__ == "__main__":
    unittest.main()
