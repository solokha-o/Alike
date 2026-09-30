#!/usr/bin/env python3
"""Regression tests for the search-field rules in tools/prepare_app_store_upload_bundle.py.

Run:
  python3 tools/prepare_app_store_upload_bundle_test.py
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_app_store_upload_bundle as bundle  # noqa: E402

NAME = "Alike: Similar Photo Cleaner"


class SearchFieldTests(unittest.TestCase):
    def errors(self, subtitle: str, keywords: str, name: str = NAME) -> list[str]:
        return bundle.search_field_errors("xx", name, subtitle, keywords)

    def test_clean_fields_pass(self) -> None:
        self.assertEqual(self.errors("Duplicate & Storage Cleanup", "delete,space,clean,up"), [])

    def test_name_over_thirty_characters_fails(self) -> None:
        self.assertTrue(any("name is 31" in error for error in self.errors("Tidy", "delete", name="A" * 31)))

    def test_name_length_counts_characters_not_bytes(self) -> None:
        # 30 Cyrillic characters are 60 UTF-8 bytes.
        self.assertEqual(self.errors("Tidy", "delete", name="Я" * 30), [])

    def test_duplicate_keyword_fails(self) -> None:
        self.assertTrue(any("more than once" in error for error in self.errors("Tidy", "delete,space,Delete")))

    def test_space_after_comma_fails(self) -> None:
        self.assertTrue(any("space-padded" in error for error in self.errors("Tidy", "delete, space")))

    def test_keyword_repeating_name_fails(self) -> None:
        self.assertTrue(any("repeats the name" in error for error in self.errors("Tidy", "delete,photos")))

    def test_keyword_repeating_subtitle_fails(self) -> None:
        self.assertTrue(any("repeats the subtitle" in error for error in self.errors("Doppelte Fotos löschen", "bilder,LÖSCHEN")))

    def test_subtitle_repeating_name_fails(self) -> None:
        self.assertTrue(any("subtitle repeats 'photos'" in error for error in self.errors("Find and clear similar photos", "delete")))

    def test_han_keyword_inside_unspaced_subtitle_fails(self) -> None:
        self.assertTrue(any("repeats the subtitle" in error for error in self.errors("一鍵清理重複照片", "相似,清理")))

    def test_es_mx_keyword_shared_with_en_us_fails(self) -> None:
        self.assertEqual(
            bundle.cross_indexed_keyword_errors({"en-US": "delete,space", "es-MX": "borrar,space"}),
            ["es-MX keyword 'space' repeats en-US"],
        )

    def test_shipped_metadata_passes(self) -> None:
        self.assertEqual(bundle.validate_source_search_fields(), [])

    def test_shipped_fields_fit_their_limits(self) -> None:
        for locale, values in bundle.METADATA.items():
            with self.subTest(locale=locale):
                self.assertLessEqual(len(values["subtitle"]), bundle.APP_SUBTITLE_MAX_LENGTH)
                self.assertLessEqual(len(values["keywords"]), bundle.APP_KEYWORDS_MAX_LENGTH)
                self.assertLessEqual(len(values["promotional_text"]), bundle.APP_PROMOTIONAL_TEXT_MAX_LENGTH)


if __name__ == "__main__":
    unittest.main()
