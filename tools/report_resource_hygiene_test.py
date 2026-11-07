#!/usr/bin/env python3
"""Regression tests for tools/report_resource_hygiene.py.

Run:
  python3 tools/report_resource_hygiene_test.py
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
import report_resource_hygiene as report  # noqa: E402

CATALOG = PurePosixPath("Packages/Scanner/Sources/Scanner/Resources/Localizable.xcstrings")
TRANSLATED = {"stringUnit": {"state": "translated", "value": "x"}}


def corpus(production: str = "", tests: str = "") -> report.Corpus:
    return report.Corpus(production, tests, report.dynamic_patterns(production))


class KeyClassificationTests(unittest.TestCase):
    def test_literal_reference_is_used(self) -> None:
        source = 'static var a: String { L10n.string("scanner.main.title") }\n'
        self.assertEqual(report.classify_key(CATALOG, "scanner.main.title", {}, corpus(source))[0], "used")

    def test_key_without_reference_is_unused(self) -> None:
        self.assertEqual(report.classify_key(CATALOG, "scanner.main.gone", {}, corpus("let a = 1\n"))[0], "unused")

    def test_stale_state_wins(self) -> None:
        entry = {"extractionState": "stale"}
        source = '"scanner.main.title"'
        self.assertEqual(report.classify_key(CATALOG, "scanner.main.title", entry, corpus(source))[0], "stale")

    def test_interpolated_literal_needs_manual_check(self) -> None:
        source = 'let text = String(localized: "core.level.\\(level.rawValue)", bundle: .module)\n'
        self.assertEqual(report.classify_key(CATALOG, "core.level.high", {}, corpus(source))[0], "manual")
        self.assertEqual(report.classify_key(CATALOG, "core.other.high", {}, corpus(source))[0], "unused")

    def test_interpolation_with_nested_quotes_and_parentheses(self) -> None:
        source = 'let a = String(localized: "row.\\(f(x, "y")).title")\n'
        self.assertEqual(report.classify_key(CATALOG, "row.3.title", {}, corpus(source))[0], "manual")

    def test_concatenated_prefix_needs_manual_check(self) -> None:
        source = 'let key = "settings.section." + name\n'
        self.assertEqual(report.classify_key(CATALOG, "settings.section.about", {}, corpus(source))[0], "manual")

    def test_format_key_needs_manual_check(self) -> None:
        for key in ("%lld photos", "Hello %@", "%1$d of %2$d"):
            with self.subTest(key=key):
                self.assertEqual(report.classify_key(CATALOG, key, {}, corpus())[0], "manual")

    def test_widget_catalog_needs_manual_check(self) -> None:
        catalog = PurePosixPath("Packages/WidgetSupport/Sources/WidgetSupport/Resources/Localizable.xcstrings")
        self.assertEqual(report.classify_key(catalog, "widget.title", {}, corpus())[0], "manual")

    def test_info_plist_catalog(self) -> None:
        catalog = PurePosixPath("Alike/Alike/InfoPlist.xcstrings")
        plist = "<key>NSPhotoLibraryUsageDescription</key>\n"
        self.assertEqual(report.classify_key(catalog, "NSPhotoLibraryUsageDescription", {}, corpus(plist))[0], "used")
        setting = "INFOPLIST_KEY_CFBundleDisplayName = Alike;\n"
        self.assertEqual(report.classify_key(catalog, "CFBundleDisplayName", {}, corpus(setting))[0], "used")
        self.assertEqual(report.classify_key(catalog, "CFBundleName", {}, corpus())[0], "manual")

    def test_key_named_only_in_tests_needs_manual_check(self) -> None:
        result = report.classify_key(CATALOG, "scanner.main.title", {}, corpus(tests='"scanner.main.title"'))
        self.assertEqual(result[0], "manual")


class TranslationTests(unittest.TestCase):
    def test_absent_and_untranslated_locales_are_missing(self) -> None:
        entry = {"localizations": {"en": TRANSLATED, "de": {"stringUnit": {"state": "new", "value": "x"}}}}
        self.assertEqual(report.missing_locales(entry, {"en", "de", "uk"}), ["de (state new)", "uk (absent)"])

    def test_plural_variations_are_read(self) -> None:
        plural = {"variations": {"plural": {"one": TRANSLATED, "other": {"stringUnit": {"state": "needs_review"}}}}}
        entry = {"localizations": {"en": TRANSLATED, "uk": plural}}
        self.assertEqual(report.missing_locales(entry, {"en", "uk"}), ["uk (state needs_review)"])

    def test_should_translate_false_is_skipped(self) -> None:
        self.assertEqual(report.missing_locales({"shouldTranslate": False}, {"en", "uk"}), [])

    def test_catalog_locales_come_from_all_keys(self) -> None:
        data = {
            "sourceLanguage": "en",
            "strings": {"a": {"localizations": {"en": TRANSLATED, "uk": TRANSLATED}}, "b": {"localizations": {"en": TRANSLATED}}},
        }
        result = report.catalog_findings(CATALOG, data, corpus('"a" "b"'))
        self.assertEqual(result["missingTranslations"], [{"key": "b", "locales": ["uk (absent)"]}])
        self.assertEqual(result["unused"], [])


class AssetTests(unittest.TestCase):
    def test_literal_and_generated_symbol_references(self) -> None:
        self.assertEqual(report.classify_asset("HeroImage", "imageset", corpus('Image("HeroImage")'))[0], "used")
        self.assertEqual(report.classify_asset("WidgetAccent", "colorset", corpus(".fill(Color.widgetAccent)"))[0], "used")
        self.assertEqual(report.classify_asset("BrandColor", "colorset", corpus(".tint(.brand)"))[0], "used")

    def test_build_setting_reference(self) -> None:
        setting = "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"
        self.assertEqual(report.classify_asset("AppIcon", "appiconset", corpus(setting))[0], "used")

    def test_unreferenced_asset_is_unused(self) -> None:
        self.assertEqual(report.classify_asset("OldBanner", "imageset", corpus("let a = 1"))[0], "unused")

    def test_unreferenced_app_icon_needs_manual_check(self) -> None:
        self.assertEqual(report.classify_asset("AppIconDark", "appiconset", corpus())[0], "manual")

    def test_asset_sets_are_found_inside_catalogs_only(self) -> None:
        paths = [
            PurePosixPath("Alike/Alike/Assets.xcassets/Old.imageset/Contents.json"),
            PurePosixPath("Alike/Alike/Assets.xcassets/Old.imageset/old.png"),
            PurePosixPath("Docs/Loose.imageset/Contents.json"),
        ]
        findings = report.asset_findings(paths, corpus())
        self.assertEqual([finding["asset"] for finding in findings], ["Alike/Alike/Assets.xcassets/Old.imageset"])


class PathTests(unittest.TestCase):
    def test_test_paths(self) -> None:
        self.assertTrue(report.is_test_path(PurePosixPath("Packages/Core/Tests/CoreTests/A.swift")))
        self.assertTrue(report.is_test_path(PurePosixPath("Alike/AlikeTests/A.swift")))
        self.assertFalse(report.is_test_path(PurePosixPath("Packages/Core/Sources/Core/A.swift")))


if __name__ == "__main__":
    unittest.main()
