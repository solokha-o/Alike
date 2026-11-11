#!/usr/bin/env python3
"""Offline checks for the creative-asset copy and locale map.

Runs under the system python3 (no Pillow): it only reads the tables.

    python3 tools/generate_app_store_creative_assets_test.py
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_app_store_creative_assets as creative  # noqa: E402
from prepare_app_store_upload_bundle import DELIVER_ACCEPTED_LOCALES  # noqa: E402


class CreativeAssetCopyTest(unittest.TestCase):
    def test_every_listing_locale_has_copy(self) -> None:
        self.assertEqual(set(creative.APP_STORE_LOCALES), set(DELIVER_ACCEPTED_LOCALES))
        for locale, key in creative.APP_STORE_LOCALES.items():
            self.assertIn(key, creative.COPY, locale)

    def test_no_unused_copy(self) -> None:
        self.assertEqual(set(creative.COPY), set(creative.APP_STORE_LOCALES.values()))

    def test_search_is_shorter_than_header(self) -> None:
        for key, (header, search) in creative.COPY.items():
            self.assertNotIn("\n", search, key)
            self.assertLess(len(search), len(header.replace("\n", " ")), key)
            self.assertLessEqual(header.count("\n") + 1, creative.PLACEMENTS["header"]["text"]["max_lines"], key)

    def test_no_numbers_prices_or_deletion_claims(self) -> None:
        forbidden = re.compile(r"[0-9%$€£¥]|delet|lösch|supprim|elimin|apag|usuń|видал|sil\b|刪除|حذف", re.IGNORECASE)
        for key, pair in creative.COPY.items():
            for text in pair:
                self.assertIsNone(forbidden.search(text), f"{key}: {text!r}")

    def test_placements_match_app_store_specs(self) -> None:
        self.assertEqual(creative.PLACEMENTS["header"]["size"], (3840, 1646))
        width, height = creative.PLACEMENTS["search"]["size"]
        self.assertEqual(width * 2, height * 3)
        self.assertTrue(1920 <= width <= 3840)

    def test_header_text_and_hero_stay_inside_the_iphone_crop(self) -> None:
        spec = creative.PLACEMENTS["header"]
        crop_left, crop_right = creative.HEADER_IPHONE_CROP
        safe_left, safe_right = spec["safe"]
        self.assertGreaterEqual(safe_left - crop_left, 150)
        self.assertGreaterEqual(crop_right - safe_right, 150)
        self.assertGreaterEqual(spec["text"]["x"], safe_left)
        scale = spec["size"][0] / (spec["crop"][2] - spec["crop"][0])
        hero_right = round(spec["frame_left"] * scale) + 40
        self.assertLessEqual(hero_right, safe_right)

    def test_crops_keep_the_ratio_and_only_downscale(self) -> None:
        for name, spec in creative.PLACEMENTS.items():
            left, top, right, bottom = spec["crop"]
            width, height = spec["size"]
            self.assertAlmostEqual((right - left) / (bottom - top), width / height, places=2, msg=name)
            self.assertGreaterEqual(right - left, width, name)


if __name__ == "__main__":
    unittest.main()
