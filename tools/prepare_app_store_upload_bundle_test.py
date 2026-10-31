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

    def test_regional_keyword_shared_with_cross_indexed_locale_fails(self) -> None:
        self.assertEqual(
            bundle.cross_indexed_keyword_errors(
                {"en-CA": "delete,space", "fr-CA": "supprimer,space", "en-AU": "tidy", "en-GB": "TIDY"}
            ),
            ["fr-CA keyword 'space' repeats en-CA", "en-GB keyword 'tidy' repeats en-AU"],
        )

    def test_european_keyword_shared_with_en_gb_fails(self) -> None:
        self.assertEqual(
            bundle.cross_indexed_keyword_errors({"it": "spazio,up", "nl-NL": "opslag", "pl": "miejsce", "en-GB": "free,up"}),
            ["en-GB keyword 'up' repeats it"],
        )

    def test_pt_pt_has_its_own_deck_and_copy(self) -> None:
        mapping = next(m for m in bundle.UPLOAD_SAFE_LOCALES if m.apple == "pt-PT")
        self.assertEqual(mapping.source, "pt-PT")
        self.assertNotEqual(bundle.METADATA["pt-PT"]["description"], bundle.METADATA["pt-BR"]["description"])
        self.assertNotEqual(bundle.METADATA["pt-PT"]["keywords"], bundle.METADATA["pt-BR"]["keywords"])

    def test_regional_listings_have_their_own_keywords(self) -> None:
        source_listing = {"en-US": "en-US", "fr": "fr-FR"}
        for mapping in bundle.UPLOAD_SAFE_LOCALES:
            source = source_listing.get(mapping.source)
            if source is None or source == mapping.apple:
                continue
            with self.subTest(locale=mapping.apple):
                self.assertNotEqual(bundle.METADATA[mapping.apple]["keywords"], bundle.METADATA[source]["keywords"])
                self.assertEqual(bundle.METADATA[mapping.apple]["subtitle"], bundle.METADATA[source]["subtitle"])

    def test_british_listings_use_british_spelling(self) -> None:
        for locale in ("en-GB", "en-AU"):
            for field in ("description", "promotional_text", "release_notes"):
                with self.subTest(locale=locale, field=field):
                    text = bundle.METADATA[locale][field]
                    for american, _ in bundle.BRITISH_SPELLING:
                        self.assertNotIn(american, text)

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
