#!/usr/bin/env python3
"""Render the App Store creative assets: Product Page Header and Search Results.

Creative assets are not screenshots. They live in the App Store Connect Asset
Library and are placed per version localization (iOS 27+ product pages):

  header  PRODUCT_PAGE_HEADER_ASSET       3840 x 1646 PNG, 21:9, no alpha
  search  APP_STORE_SEARCH_RESULTS_ASSET  3:2, 1920x1280 … 3840x2560, no alpha

  in   `Docs/images/creative-assets/v7-{header,search}-plate.png` — art plates
       with no text and no hero (variant 7, paper style)
       `Packages/DesignSystem/DesignSource/WelcomeHero/AlikeWelcomeHero-source.png`
  out  `build/generated/creative_assets/{header,search}/<copy>.png`
       `build/generated/creative_assets/manifest.json` — App Store locale ->
       files, read by `fastlane ios creative_assets_upload`
       `preview-*.png`, `thumb-*.png` — contact sheets

Plates are cropped and downscaled, never upscaled or repainted. The hero is the
app's own PNG under a uniform downscale only. Every render is checked for size,
alpha, glyph coverage, contrast and margins before it reaches the manifest.

    build/tools-venv/bin/python tools/generate_app_store_creative_assets.py
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Docs" / "images" / "creative-assets"
HERO_PATH = ROOT / "Packages/DesignSystem/DesignSource/WelcomeHero/AlikeWelcomeHero-source.png"
OUTPUT_ROOT = ROOT / "build" / "generated" / "creative_assets"
TEXT = (245, 245, 247)
MIN_CONTRAST = 12.0

# App Store locale -> copy key. The regional English listings reuse en-US and
# fr-CA reuses fr-FR, as the listing text does. Keys must match
# DELIVER_ACCEPTED_LOCALES in prepare_app_store_upload_bundle.py.
APP_STORE_LOCALES = {
    "en-US": "en", "en-GB": "en", "en-CA": "en", "en-AU": "en",
    "uk": "uk", "de-DE": "de", "fr-FR": "fr", "fr-CA": "fr",
    "es-ES": "es", "es-MX": "es-MX", "pt-BR": "pt-BR", "pt-PT": "pt-PT",
    "it": "it", "nl-NL": "nl", "pl": "pl", "tr": "tr",
    "zh-Hant": "zh-Hant", "ar-SA": "ar",
}

# (header, search). Header may run three lines; search must read at thumbnail
# size. "\n" is a deliberate break; a line that still does not fit wraps. The
# register follows each locale's promotional text (pt-PT "tu", fr "vous").
# No numbers, prices, or claims of automatic deletion.
COPY = {
    "en": ("Find similar photos\nand choose which\nones to keep.", "Find similar photos"),
    "uk": ("Знайдіть схожі фото\nй оберіть, які\nзалишити.", "Знайдіть схожі фото"),
    "de": ("Finde ähnliche Fotos\nund wähle, welche\nbleiben.", "Ähnliche Fotos finden"),
    "fr": ("Trouvez les photos\nsimilaires et gardez\ncelles qui comptent.", "Trouvez les photos similaires"),
    "es": ("Encuentra fotos\nparecidas y elige\ncuáles conservar.", "Encuentra fotos parecidas"),
    "es-MX": ("Encuentra fotos\nsimilares y elige\ncuáles conservar.", "Encuentra fotos similares"),
    "pt-BR": ("Encontre fotos\nparecidas e escolha\nquais manter.", "Encontre fotos parecidas"),
    "pt-PT": ("Encontra fotos\nparecidas e escolhe\nquais manter.", "Encontra fotos semelhantes"),
    "it": ("Trova le foto simili\ne scegli quali\ntenere.", "Trova le foto simili"),
    "nl": ("Vind foto's die\nop elkaar lijken en\nkies welke je houdt.", "Vind vergelijkbare foto's"),
    "pl": ("Znajdź podobne\nzdjęcia i wybierz,\nktóre zostawić.", "Znajdź podobne zdjęcia"),
    "tr": ("Benzer fotoğrafları\nbul, saklayacaklarını\nseç.", "Benzer fotoğrafları bul"),
    "zh-Hant": ("找出相似照片，\n選出你想保留的\n那幾張。", "找出相似照片"),
    "ar": ("اعثر على الصور\nالمتشابهة واختر\nما تحتفظ به.", "اعثر على الصور المتشابهة"),
}
RTL_COPY = frozenset({"ar"})

# Geometry, in plate pixels. The plates' paper arcs end in a hard vertical cut a
# little before the right edge; the crop ends inside the arcs so they bleed off
# the canvas instead. Both crops keep the exact aspect ratio of the target.
#
# iPhone scales the header to the banner height and shows only the centre,
# about x 372…3468 of 3840 (measured on 1.7.2, 2026-11-11); iPad and Mac show
# the full width. All text and the hero stay inside `safe`; the paper frame is
# decoration and may run past it. The header crop is 1:1, which puts the frame
# as far right as the plate allows.
HEADER_IPHONE_CROP = (372, 3468)
PLACEMENTS = {
    "header": {
        "plate": "v7-header-plate.png", "crop": (0, 41, 3840, 1687), "size": (3840, 1646),
        "frame_left": 2698, "frame_base": 1586, "hero_height": 900, "safe": (560, 3280),
        "text": {"x": 560, "cy": 823, "start": 150, "min": 120, "max_lines": 3, "gap": 70},
    },
    "search": {
        "plate": "v7-search-plate.png", "crop": (0, 96, 3696, 2560), "size": (3600, 2400),
        "frame_left": 1915, "frame_base": 2446, "hero_height": 1000,
        "text": {"x": 240, "cy": 380, "start": 240, "min": 140, "max_lines": 2, "gap": 0},
    },
}


def gen():
    """The listing generator owns the fonts and Arabic shaping; reuse it."""
    sys.path.insert(0, str(ROOT / "tools"))
    import generate_app_store_product_screenshots as module

    return module


def family_for(key: str):
    g = gen()
    return {"zh-Hant": g.HEITI_TC, "ar": g.SF_ARABIC}.get(key, g.SF_PRO)


def load_plate(spec: dict):
    from PIL import Image

    source = Image.open(SOURCE_ROOT / spec["plate"]).convert("RGB")
    box = source.crop(spec["crop"])
    width, height = spec["size"]
    if abs(box.width / box.height - width / height) > 0.002:
        raise SystemExit(f"{spec['plate']}: crop {box.size} is not {width}:{height}")
    if box.width < width or box.height < height:
        raise SystemExit(f"{spec['plate']}: crop {box.size} would upscale to {spec['size']}")
    return box.resize(spec["size"], Image.LANCZOS)


def load_hero(height: int):
    from PIL import Image

    hero = Image.open(HERO_PATH).convert("RGBA")
    hero = hero.crop(hero.getchannel("A").getbbox())
    if height > hero.height:
        raise SystemExit(f"hero would upscale from {hero.height} to {height}")
    return hero.resize((round(hero.width * height / hero.height), height), Image.LANCZOS)


def ink(face, character: str) -> bytes:
    from PIL import Image, ImageDraw

    image = Image.new("L", (face.size * 2, face.size * 2), 0)
    ImageDraw.Draw(image).text((face.size // 2, face.size // 4), character, font=face, fill=255)
    return image.tobytes()


def missing_glyphs(text: str, key: str) -> list[str]:
    """A character is missing when it draws nothing or draws .notdef."""
    g = gen()
    family = family_for(key)
    missing = []
    for character in sorted(set(text)):
        if character.isspace():
            continue
        face_family = g.SF_PRO if family == g.SF_ARABIC and not g.is_arabic(character) else family
        face = g.font(120, "Bold", face_family)
        drawn = ink(face, character)
        if not any(drawn) or drawn == ink(face, "￿"):
            missing.append(character)
    return missing


def draw_headline(canvas, text: str, key: str, x: int, width: int, cy: int, align: str, start: int, minimum: int, max_lines: int) -> dict:
    from PIL import Image, ImageDraw

    g = gen()
    family = family_for(key)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    size = start
    while True:
        face = g.font(size, "Bold", family)
        lines = g.fit_text_lines(text, draw, face, width, family, size, "Bold")
        widths = [g.text_width(draw, line, face, family, size, "Bold") for line in lines]
        if len(lines) <= max_lines and max(widths) <= width:
            break
        if size - 4 < minimum:
            raise SystemExit(f"{key}: {text!r} does not fit at {minimum}px; rebreak it by hand")
        size -= 4
    step = int(size * 1.1)
    ascent, descent = face.getmetrics()
    y = cy - (step * (len(lines) - 1) + ascent + descent) // 2
    for line, line_width in zip(lines, widths):
        offset = {"center": (width - line_width) // 2, "right": width - line_width}.get(align, 0)
        g.draw_line(draw, (x + offset, y), line, face, TEXT + (255,), family, size, "Bold")
        y += step
    canvas.alpha_composite(layer)
    return {"size": size, "lines": lines, "bbox": layer.getchannel("A").getbbox()}


def relative_luminance(rgb) -> float:
    def channel(value: int) -> float:
        value /= 255
        return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4

    r, g, b = rgb[:3]
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(foreground, background) -> float:
    return (relative_luminance(foreground) + 0.05) / (relative_luminance(background) + 0.05)


def safe_area_problems(boxes: dict, safe: tuple[int, int]) -> list[str]:
    """Boxes (left, top, right, bottom) that leave the column range `safe`."""
    safe_left, safe_right = safe
    return [
        f"{name} {box} outside the iPhone safe area x {safe_left}…{safe_right}"
        for name, box in boxes.items()
        if box[0] < safe_left or box[2] > safe_right
    ]


def render(placement: str, key: str) -> tuple[Path, dict]:
    spec = PLACEMENTS[placement]
    width, height = spec["size"]
    scale = width / (spec["crop"][2] - spec["crop"][0])
    canvas = load_plate(spec).convert("RGBA")
    hero = load_hero(spec["hero_height"])
    frame_left = round(spec["frame_left"] * scale)
    frame_base = round((spec["frame_base"] - spec["crop"][1]) * scale)
    hero_x = frame_left + 40 - hero.width
    hero_y = frame_base - hero.height
    canvas.alpha_composite(hero, (hero_x, hero_y))

    text = spec["text"]
    headline = COPY[key][0 if placement == "header" else 1]
    if placement == "header":
        box_width = hero_x - text["x"] - text["gap"]
        align = "right" if key in RTL_COPY else "left"
    else:
        box_width = width - 2 * text["x"]
        align = "center"
    report = draw_headline(canvas, headline, key, text["x"], box_width, text["cy"], align, text["start"], text["min"], text["max_lines"])

    flat = canvas.convert("RGB")
    left, top, right, bottom = report["bbox"]
    background = flat.crop((max(0, left - 40), top, max(1, left - 5), bottom)).resize((1, 1)).getpixel((0, 0))
    report["contrast"] = round(contrast(TEXT, background), 1)
    report["missing_glyphs"] = missing_glyphs(headline, key)
    problems = []
    if report["missing_glyphs"]:
        problems.append(f"missing glyphs {report['missing_glyphs']}")
    if report["contrast"] < MIN_CONTRAST:
        problems.append(f"contrast {report['contrast']}")
    if left < 150 or top < 60 or right > width - 150 or bottom > height - 60:
        problems.append(f"text box {report['bbox']} too close to the edge")
    if "safe" in spec:
        hero_box = hero.getchannel("A").getbbox()
        report["hero_bbox"] = (hero_x + hero_box[0], hero_y + hero_box[1], hero_x + hero_box[2], hero_y + hero_box[3])
        problems += safe_area_problems({"text box": report["bbox"], "hero": report["hero_bbox"]}, spec["safe"])
    if problems:
        raise SystemExit(f"{placement}/{key}: " + "; ".join(problems))

    path = OUTPUT_ROOT / placement / f"{key}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    flat.save(path, optimize=True)
    return path, report


def sheet(placement: str, paths: list[Path], tile_width: int, name: str, labels: bool, crop_x: tuple[int, int] | None = None) -> None:
    """Contact sheet. `crop_x` shows only that column range, as iPhone does."""
    from PIL import Image, ImageDraw

    width, height = PLACEMENTS[placement]["size"]
    if crop_x:
        width = crop_x[1] - crop_x[0]
    tile_height = round(tile_width * height / width)
    columns = 3 if placement == "header" else 4
    rows = (len(paths) + columns - 1) // columns
    label = 40 if labels else 0
    canvas = Image.new("RGB", (columns * (tile_width + 20) + 20, rows * (tile_height + label + 20) + 20), (240, 240, 240))
    draw = ImageDraw.Draw(canvas)
    for index, path in enumerate(paths):
        x = 20 + (index % columns) * (tile_width + 20)
        y = 20 + (index // columns) * (tile_height + label + 20)
        if labels:
            draw.text((x, y + 10), path.stem, fill=(0, 0, 0))
        image = Image.open(path)
        if crop_x:
            image = image.crop((crop_x[0], 0, crop_x[1], image.height))
        canvas.paste(image.resize((tile_width, tile_height), Image.LANCZOS), (x, y + label))
    canvas.save(OUTPUT_ROOT / name)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    reports: dict[str, dict] = {}
    files: dict[str, dict[str, Path]] = {}
    for placement in PLACEMENTS:
        for key in COPY:
            path, report = render(placement, key)
            files.setdefault(key, {})[placement] = path
            reports[f"{placement}/{key}"] = report
            print(f"{placement:6} {key:7} {report['size']}px {len(report['lines'])} lines, contrast {report['contrast']}")
        paths = [files[key][placement] for key in COPY]
        sheet(placement, paths, 900 if placement == "header" else 600, f"preview-{placement}.png", True)
        sheet(placement, paths, 600 if placement == "header" else 320, f"thumb-{placement}.png", False)
        if placement == "header":
            sheet(placement, paths, 900, "preview-header-iphone.png", True, HEADER_IPHONE_CROP)

    manifest = {
        locale: {
            placement: {
                "path": str(files[key][placement].relative_to(ROOT)),
                "sha256": sha256(files[key][placement]),
                "copy": key,
            }
            for placement in PLACEMENTS
        }
        for locale, key in APP_STORE_LOCALES.items()
    }
    (OUTPUT_ROOT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (OUTPUT_ROOT / "qa-report.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2, default=list) + "\n")
    print(f"Manifest: {(OUTPUT_ROOT / 'manifest.json').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
