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
        self.assertIn("AlikeTests", levels)
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


def project(targets):
    """Return a project.pbxproj text with {target: [product]} native targets."""
    identifiers = {}
    lines = ["/* Begin PBXNativeTarget section */"]
    for index, (target, products) in enumerate(targets.items()):
        lines += [f"\t\tT{index} /* {target} */ = {{", "\t\t\tisa = PBXNativeTarget;", "\t\t\tpackageProductDependencies = ("]
        for product in products:
            identifiers.setdefault(product, f"P{len(identifiers)}")
            lines.append(f"\t\t\t\t{identifiers[product]} /* {product} */,")
        lines += ["\t\t\t);", f"\t\t\tproductName = {target};", "\t\t};"]
    lines.append("/* End PBXNativeTarget section */")
    for product, identifier in identifiers.items():
        lines += [
            f"\t\t{identifier} /* {product} */ = {{",
            "\t\t\tisa = XCSwiftPackageProductDependency;",
            f"\t\t\tproductName = {product};",
            "\t\t};",
        ]
    return "\n".join(lines) + "\n"


# The forbidden cells of the ADR-0004 matrix between package categories, written
# out here and not read from check.MATRIX, so that a wrong MATRIX fails a test.
FORBIDDEN = [
    ("Feature", "Feature"),
    ("Feature", "Tool"),
    ("Foundation", "Feature"),
    ("Foundation", "Tool"),
    ("Utility", "Feature"),
    ("Utility", "Foundation"),
    ("Utility", "Tool"),
    ("Tool", "Feature"),
    ("Tool", "Tool"),
]
PERMITTED = [
    ("Feature", "Foundation"),
    ("Feature", "Utility"),
    ("Foundation", "Foundation"),
    ("Foundation", "Utility"),
    ("Utility", "Utility"),
    ("Tool", "Foundation"),
    ("Tool", "Utility"),
]


class MatrixTests(unittest.TestCase):
    def run_edge(self, source_category, target_category):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Fixture(directory)
            fixture.categories.update({"Source": source_category, "Target": target_category})
            fixture.package("Target")
            fixture.package("Source", local=["Target"])
            errors, _, _ = fixture.run()
        return errors

    def test_each_forbidden_cell_fails(self) -> None:
        for source_category, target_category in FORBIDDEN:
            with self.subTest(source=source_category, target=target_category):
                errors = self.run_edge(source_category, target_category)
                expected = f"Source ({source_category}) -> Target ({target_category})"
                self.assertEqual(len(errors), 1, errors)
                self.assertIn(expected, errors[0])

    def test_each_permitted_cell_passes(self) -> None:
        for source_category, target_category in PERMITTED:
            with self.subTest(source=source_category, target=target_category):
                self.assertEqual(self.run_edge(source_category, target_category), [])


class AppProductTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.fixture = Fixture(directory.name)
        self.fixture.categories["Alike"] = "App"

    def run_project(self, targets):
        path = self.fixture.root / check.PBXPROJ_FILE
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(project(targets), encoding="utf-8")
        return self.fixture.run()

    def test_app_edges_come_from_the_project_file(self) -> None:
        errors, levels, notes = self.run_project({"Alike": ["Core", "Cleanup"]})
        self.assertEqual((errors, notes), ([], []))
        self.assertEqual(levels["Alike"], 3)

    def test_app_to_tool_fails(self) -> None:
        self.fixture.categories["Calibration"] = "Tool"
        self.fixture.package("Calibration", local=["Core"])
        errors, _, _ = self.run_project({"Alike": ["Core", "Calibration"]})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("Alike (App) -> Calibration (Tool)", errors[0])

    def test_target_with_products_and_no_category_fails(self) -> None:
        errors, _, _ = self.run_project({"Alike": ["Core"], "AlikeShare": ["Core"]})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("target AlikeShare links package products and has no line", errors[0])

    def test_target_without_products_needs_no_category(self) -> None:
        errors, _, _ = self.run_project({"Alike": ["Core"], "AlikeUITests": []})
        self.assertEqual(errors, [])

    def test_second_app_target_is_checked_too(self) -> None:
        self.fixture.categories["AlikeTests"] = "App"
        self.fixture.categories["Calibration"] = "Tool"
        self.fixture.package("Calibration", local=["Core"])
        errors, _, _ = self.run_project({"Alike": ["Core"], "AlikeTests": ["Calibration"]})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("AlikeTests (App) -> Calibration (Tool)", errors[0])

    def test_app_category_without_target_fails(self) -> None:
        self.fixture.categories["AlikeWidgets"] = "App"
        errors, _, _ = self.run_project({"Alike": ["Core"]})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("App AlikeWidgets is not a target", errors[0])

    def test_unknown_product_fails(self) -> None:
        errors, _, _ = self.run_project({"Alike": ["Core", "Missing"]})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("Alike uses product Missing, which no local package declares", errors[0])


class ParsingTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.fixture = Fixture(directory.name)

    def write(self, relative, text) -> None:
        path = self.fixture.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def errors(self):
        errors, _, _ = self.fixture.run()
        return errors

    def test_commented_edge_in_package_swift_is_ignored(self) -> None:
        manifest_path = self.fixture.root / "Packages/Details/Package.swift"
        text = manifest_path.read_text(encoding="utf-8").replace(
            '.package(path: "../Core")',
            '.package(path: "../Core"), // .package(path: "../Cleanup"),\n/* .package(path: "../Cleanup") */',
        )
        manifest_path.write_text(text, encoding="utf-8")
        self.assertEqual(self.errors(), [])

    def test_unsupported_dependency_forms_fail(self) -> None:
        for form in ('.package(path: "../../Packages/Cleanup")', '.package(id: "airbnb.lottie", from: "4.6.1")'):
            with self.subTest(form=form):
                self.fixture.package("Details", local=["Core"])
                manifest_path = self.fixture.root / "Packages/Details/Package.swift"
                text = manifest_path.read_text(encoding="utf-8").replace(
                    '.package(path: "../Core")', f'.package(path: "../Core"), {form}'
                )
                manifest_path.write_text(text, encoding="utf-8")
                errors = self.errors()
                self.assertEqual(len(errors), 1, errors)
                self.assertIn(f"Packages/Details/Package.swift: cannot check `{form}", errors[0])

    def test_undeclared_import_in_tests_folder_fails(self) -> None:
        self.write("Packages/Details/Tests/DetailsTests/ATests.swift", "@testable import Cleanup\n")
        errors = self.errors()
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("Packages/Details/Tests/DetailsTests/ATests.swift:1: imports Cleanup", errors[0])

    def test_test_target_name_is_not_a_local_module(self) -> None:
        # DetailsTests is the test target of Details, not a module that Cleanup can import.
        self.write("Packages/Cleanup/Tests/CleanupTests/ATests.swift", "import DetailsTests\n")
        self.assertEqual(self.errors(), [])

    def test_build_folder_is_skipped(self) -> None:
        self.write("Packages/Details/Tests/.build/checkouts/x/Sources/X.swift", "import Cleanup\n")
        self.assertEqual(self.errors(), [])

    def test_duplicate_category_line_fails(self) -> None:
        tools = self.fixture.root / "tools"
        self.fixture.run()
        text = (tools / "package-categories").read_text(encoding="utf-8") + "Core Feature\n"
        (tools / "package-categories").write_text(text, encoding="utf-8")
        errors, _, _ = check.check(self.fixture.root)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("Core has a second category line", errors[0])

    def test_duplicate_allowlist_line_fails(self) -> None:
        self.fixture.allowlist.append(f"sdk DesignSystem {LOTTIE}  # again.")
        errors = self.errors()
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("duplicate of line 1", errors[0])

    def test_import_debt_line_covers_only_its_file(self) -> None:
        self.fixture.package("Details", local=["Core"], source="@_exported import Cleanup\n")
        self.fixture.allowlist.append(
            "import Packages/Details/Sources/Details/Details.swift Cleanup  # debt card."
        )
        self.assertEqual(self.errors(), [])
        self.write("Packages/Details/Sources/Details/New.swift", "import Cleanup\n")
        errors = self.errors()
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("Packages/Details/Sources/Details/New.swift:1: imports Cleanup", errors[0])


if __name__ == "__main__":
    unittest.main()
