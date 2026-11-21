#!/usr/bin/env python3
"""Turn the raw iPad captures into 13-inch App Store product screenshots.

  in   `Docs/images/ipad/raw/<locale>/` — captures from
       `tools/capture_ipad_store_screens.py`
  out  `Docs/images/ipad/store/<locale>/` — product renders at 2048 x 2732, the
       13-inch iPad size App Store Connect accepts

The iPad deck reuses the iPhone generator: the same palette, fonts, copy and
right-to-left handling, so a copy change lands on both decks. Only the canvas,
the layouts, the background and the device frame are its own. The frame is
drawn here, so no mockup asset or licence is needed.

The deck is 4 slides, the iPhone slides the fake library can show on a
simulator: scan, queue, the review with a decision half made, and the cleanup
in progress. Best Shot on its own, the enhanced photo and the widgets need a
real library or a Home Screen, so they stay iPhone-only.

    build/tools-venv/bin/python tools/generate_ipad_store_screenshots.py
    build/tools-venv/bin/python tools/generate_ipad_store_screenshots.py --locales en-US,uk
"""
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "tools" / "generate_app_store_product_screenshots.py"
SOURCE_ROOT = ROOT / "Docs" / "images" / "ipad" / "raw"
OUTPUT_ROOT = ROOT / "Docs" / "images" / "ipad" / "store"
CONTACT_SHEET_ROOT = ROOT / "build" / "generated" / "ipad_product_screenshots"

CANVAS = (2048, 2732)
# The drawn device: a 1560 x 2080 screen (the 3:4 of a 13-inch iPad) inside a
# 40 px bezel.
SCREEN_SIZE = (1560, 2080)
BEZEL = 40
FRAME_SIZE = (SCREEN_SIZE[0] + BEZEL * 2, SCREEN_SIZE[1] + BEZEL * 2)
SCREEN_RADIUS = 64
FRAME_RADIUS = SCREEN_RADIUS + BEZEL

# iPhone slide index (position in the generator's SLIDES and COPY) for each
# iPad capture.
DECK = (
    ("01-scanner-idle.png", 0),
    ("03-cleanup-queue.png", 1),
    ("05-comparison-review.png", 3),
    ("07-cleanup-progress.png", 4),
)

# The iPhone copy names the device once, in slide 1. Most languages take "iPad"
# in the same slot; Turkish needs its own suffix (vowel harmony), so the longer
# match goes first.
DEVICE_NAME_REPLACEMENTS = (
    ("iPhone'unda", "iPad'inde"),
    ("iPhone", "iPad"),
)


def load_generator():
    spec = importlib.util.spec_from_file_location("app_store_screenshots", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolve their module through sys.modules while the class body runs.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


gen = load_generator()


def ipad_copy(text: str) -> str:
    for old, new in DEVICE_NAME_REPLACEMENTS:
        text = text.replace(old, new)
    return text


def caption_top(align: str) -> "gen.Transform":
    return gen.Transform(x=140, y=230, width=1768, align=align, headline_size=150)


def subtitle_top(align: str) -> "gen.Transform":
    return gen.Transform(x=140, y=720, width=1768, align=align)


def caption_bottom(align: str) -> "gen.Transform":
    return gen.Transform(x=140, y=1990, width=1768, align=align, headline_size=140)


def subtitle_bottom(align: str) -> "gen.Transform":
    return gen.Transform(x=140, y=2450, width=1768, align=align)


# The iPhone deck's rhythm: caption on top with a large device bleeding off the
# bottom, then caption at the bottom with a whole, smaller device above it.
SLIDES = (
    gen.SlideLayout(
        source="01-scanner-idle.png",
        caption=caption_top("left"),
        subtitle=subtitle_top("left"),
        subtitle_size=58,
        device=gen.DeviceTransform(x=244, y=1000, width=1560, rotation=-2.0),
        band="accent",
    ),
    gen.SlideLayout(
        source="03-cleanup-queue.png",
        caption=caption_bottom("right"),
        subtitle=subtitle_bottom("right"),
        subtitle_size=58,
        device=gen.DeviceTransform(x=404, y=110, width=1240, rotation=2.6),
        band="purple",
    ),
    gen.SlideLayout(
        source="05-comparison-review.png",
        caption=caption_top("right"),
        subtitle=subtitle_top("right"),
        subtitle_size=58,
        device=gen.DeviceTransform(x=244, y=1000, width=1560, rotation=2.2),
        band="accent",
    ),
    gen.SlideLayout(
        source="07-cleanup-progress.png",
        caption=caption_bottom("left"),
        subtitle=subtitle_bottom("left"),
        subtitle_size=58,
        device=gen.DeviceTransform(x=404, y=110, width=1240, rotation=-2.6),
        band="green",
    ),
)


def background_spotlight(canvas: Image.Image, slide_index: int, band: str, zone: tuple[int, int]) -> None:
    """The iPhone spotlight, placed by proportion instead of iPhone pixels."""
    width, height = CANVAS
    accent = gen.THEME[band]
    caption_at_top = zone[0] < height // 2
    device_center = round(height * 0.68) if caption_at_top else round(height * 0.34)
    canvas.alpha_composite(gen.radial_glow((width // 2, device_center), 1300, accent, 60))
    canvas.alpha_composite(
        gen.radial_glow((round(width * 0.72) - slide_index * 90, device_center - 940), 780, gen.THEME["purple"], 34)
    )


def render_ipad(screenshot_path: Path) -> Image.Image:
    """A dark bezel around the capture, its corners rounded like the device."""
    frame = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)
    draw.rounded_rectangle((0, 0, FRAME_SIZE[0] - 1, FRAME_SIZE[1] - 1), radius=FRAME_RADIUS, fill=(20, 21, 24, 255))
    # A thin light edge, so the bezel reads against the dark canvas.
    draw.rounded_rectangle(
        (2, 2, FRAME_SIZE[0] - 3, FRAME_SIZE[1] - 3), radius=FRAME_RADIUS - 2, outline=(78, 82, 90, 255), width=3
    )
    screenshot = Image.open(screenshot_path).convert("RGBA")
    screen = gen.cover_crop(screenshot, SCREEN_SIZE)
    screen.putalpha(gen.rounded_mask(SCREEN_SIZE, SCREEN_RADIUS))
    frame.alpha_composite(screen, (BEZEL, BEZEL))
    return frame


def configure(source_root: Path = SOURCE_ROOT) -> None:
    """Points the iPhone generator at the iPad canvas, deck and frame."""
    gen.CANVAS = CANVAS
    gen.MOCKUP_SIZE = FRAME_SIZE
    gen.SOURCE_ROOT = source_root
    gen.SLIDES = SLIDES
    gen.render_phone = render_ipad
    gen.BACKGROUNDS["spotlight"] = background_spotlight
    gen.base_canvas.cache_clear()
    gen.COPY = {
        locale: [tuple(ipad_copy(part) for part in rows[index]) for _, index in DECK]
        for locale, rows in gen.COPY.items()
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--locales", default="all", help="Comma-separated locales, or 'all'.")
    parser.add_argument("--source", type=Path, default=SOURCE_ROOT, help="Raw captures root.")
    parser.add_argument("--output", type=Path, default=OUTPUT_ROOT, help="Output root.")
    args = parser.parse_args()
    source_root, output_root = args.source.resolve(), args.output.resolve()

    configure(source_root)
    locales = gen.selected_locales(args.locales)
    missing = [
        str(gen.raw_source(locale, slide.source))
        for locale in locales
        for slide in SLIDES
        if not gen.raw_source(locale, slide.source).exists()
    ]
    if missing:
        raise SystemExit("Missing captures:\n  " + "\n  ".join(missing))
    for locale in locales:
        gen.validate_glyph_coverage(locale)

    variant = gen.VARIANTS_BY_NAME["spotlight"]
    CONTACT_SHEET_ROOT.mkdir(parents=True, exist_ok=True)
    rows: list[tuple[str, list[Path]]] = []
    for locale in locales:
        rendered = gen.render_locale(variant, locale, output_root)
        rows.append((locale, rendered))
    gen.contact_sheet(rows, CONTACT_SHEET_ROOT / "contact-sheet-all-locales.png", thumb_size=(300, 400))
    gen.contact_sheet(rows[:1], CONTACT_SHEET_ROOT / "contact-sheet-160px.png", thumb_size=(160, 213))
    total = sum(len(files) for _, files in rows)
    print(f"\n{total} iPad screenshots in {output_root}/ at {CANVAS[0]}x{CANVAS[1]}")
    print(f"Contact sheets in {CONTACT_SHEET_ROOT.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
