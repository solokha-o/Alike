#!/usr/bin/env python3
"""Turn the raw device captures into App Store product screenshots.

Screenshots on the store are advertisements, not UI documentation. Each slide
sells one outcome, so the phone stays real and dense while the canvas around it
stays sparse: a dark background matching the app's own appearance, one headline,
one supporting line.

  in   `Docs/images/raw/<locale>/` — bare captures at 1320 x 2868, written by
       `tools/import_device_screenshots.py`
  out  `Docs/images/<locale>/`     — product renders at 1320 x 2868, picked up
       by `tools/prepare_app_store_upload_bundle.py`

Four background variants share one product concept — same palette, typography,
slides and copy — so they can be compared and one picked:

    build/tools-venv/bin/python tools/generate_app_store_product_screenshots.py --drafts
    open build/generated/product_screenshot_drafts/contact-sheet-all-variants.png

Then render the chosen one into the listing folder:

    build/tools-venv/bin/python tools/generate_app_store_product_screenshots.py --variant spotlight

Contact sheets land under `build/generated/` so the listing folder holds nothing
but uploadable PNGs.
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ModuleNotFoundError:  # pragma: no cover - setup guidance
    sys.exit(
        "Pillow is missing. Create the tools venv once:\n"
        "  python3 -m venv build/tools-venv && "
        "build/tools-venv/bin/pip install --upgrade pip Pillow\n"
        "then run this script with build/tools-venv/bin/python."
    )

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Docs" / "images" / "raw"
DEFAULT_OUTPUT_ROOT = ROOT / "Docs" / "images"
CONTACT_SHEET_ROOT = ROOT / "build" / "generated" / "product_screenshots"
DRAFT_ROOT = ROOT / "build" / "generated" / "product_screenshot_drafts"
MOCKUP_PATH = ROOT / "tools" / "assets" / "iphone-mockup.png"

CANVAS = (1320, 2868)
MOCKUP_SIZE = (1022, 2082)
PHONE_SCREEN_RECT = (52, 46, 970, 2036)
# Directory names under Docs/images/, which are the app's own language codes,
# not the App Store Connect ones. UPLOAD_SAFE_LOCALES in
# tools/prepare_app_store_upload_bundle.py maps es-419 onto App Store Connect's
# es-MX slot; nothing here needs to know that.
LOCALES = ("en-US", "uk", "de", "fr", "es", "es-419", "pt-BR")

# The app ships a dark UI, so the canvas is dark too: the phone melts into the
# background instead of floating on a light card.
THEME = {
    "top": (11, 11, 13),
    "bottom": (22, 24, 28),
    "fg": (255, 255, 255),
    "muted": (168, 176, 184),
    "accent": (90, 180, 204),  # the teal of the Start Scanning button
    "purple": (138, 107, 209),  # the mascot
    "green": (48, 209, 88),  # freed space
}

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
FALLBACK_FONT_PATH = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


@dataclass(frozen=True)
class Transform:
    x: int
    y: int
    width: int
    align: str = "left"
    headline_size: int = 112


@dataclass(frozen=True)
class DeviceTransform:
    x: int
    y: int
    width: int
    rotation: float

    @property
    def height(self) -> int:
        return round(self.width * MOCKUP_SIZE[1] / MOCKUP_SIZE[0])


@dataclass(frozen=True)
class SlideLayout:
    source: str
    caption: Transform
    subtitle: Transform
    subtitle_size: int
    device: DeviceTransform
    band: str

    @property
    def caption_at_top(self) -> bool:
        return self.caption.y < CANVAS[1] // 2

    @property
    def caption_zone(self) -> tuple[int, int]:
        """Vertical band that decorations must stay out of."""
        return (self.caption.y - 100, self.subtitle.y + 220)


# Two compositions alternate: caption on top with a large phone bleeding off the
# bottom edge, and caption at the bottom with a smaller, complete device above
# it. Neither shows the empty lower half of a capture.
def caption_top(align: str, headline_size: int = 112) -> Transform:
    return Transform(x=80, y=190, width=1160, align=align, headline_size=headline_size)


def subtitle_top(align: str) -> Transform:
    return Transform(x=80, y=648, width=1060, align=align)


def caption_bottom(align: str, headline_size: int = 104) -> Transform:
    return Transform(x=80, y=2118, width=1160, align=align, headline_size=headline_size)


def subtitle_bottom(align: str) -> Transform:
    return Transform(x=80, y=2536, width=1060, align=align)


SLIDES = (
    SlideLayout(
        source="01-scanner-idle.png",
        caption=caption_top("left"),
        subtitle=subtitle_top("left"),
        subtitle_size=44,
        device=DeviceTransform(x=100, y=900, width=1120, rotation=-3.0),
        band="accent",
    ),
    SlideLayout(
        source="03-cleanup-queue.png",
        caption=caption_bottom("right"),
        subtitle=subtitle_bottom("right"),
        subtitle_size=44,
        device=DeviceTransform(x=220, y=96, width=880, rotation=4.0),
        band="purple",
    ),
    SlideLayout(
        source="04-cluster-details.png",
        caption=caption_top("right", headline_size=106),
        subtitle=subtitle_top("right"),
        subtitle_size=44,
        device=DeviceTransform(x=100, y=900, width=1120, rotation=3.4),
        band="accent",
    ),
    SlideLayout(
        source="05-comparison-review.png",
        caption=caption_bottom("left"),
        subtitle=subtitle_bottom("left"),
        subtitle_size=44,
        device=DeviceTransform(x=220, y=96, width=880, rotation=-4.4),
        band="purple",
    ),
    SlideLayout(
        source="07-cleanup-progress.png",
        caption=caption_top("center"),
        subtitle=subtitle_top("center"),
        subtitle_size=44,
        device=DeviceTransform(x=100, y=920, width=1120, rotation=2.4),
        band="green",
    ),
)

# (label, headline, subtitle) per slide, in SLIDES order. Wording follows the
# listing copy generated by tools/prepare_app_store_upload_bundle.py.
COPY = {
    "en-US": [
        (
            "ON-DEVICE",
            "Find the photos\nthat look alike",
            "Alike scans your library with Apple Vision, entirely on your iPhone.",
        ),
        (
            "ONE QUEUE",
            "Every group,\nready to review",
            "Groups arrive with review badges, so you always know what is left.",
        ),
        (
            "BEST SHOT",
            "The keeper is\nalready picked",
            "Alike highlights the best frame in each group. You just confirm.",
        ),
        (
            "COMPARE",
            "Check before\nanything goes",
            "Review at full size. Nothing is deleted without your confirmation.",
        ),
        (
            "FREE SPACE",
            "Watch the gigabytes\ncome back",
            "Selected photos and estimated savings, tracked as you clean up.",
        ),
    ],
    "uk": [
        (
            "НА ПРИСТРОЇ",
            "Знайдіть схожі\nфотографії",
            "Alike сканує медіатеку через Apple Vision повністю на вашому iPhone.",
        ),
        (
            "ЧЕРГА",
            "Кожна група\nготова до перегляду",
            "Групи з позначками перегляду — завжди видно, що лишилось.",
        ),
        (
            "НАЙКРАЩИЙ ЗНІМОК",
            "Найкраще фото\nвже обрано",
            "Alike виділяє найвдаліший кадр у групі. Вам лишається підтвердити.",
        ),
        (
            "ПОРІВНЯННЯ",
            "Перевірте перед\nвидаленням",
            "Перегляд у повний розмір. Нічого не видаляється без підтвердження.",
        ),
        (
            "ВІЛЬНЕ МІСЦЕ",
            "Поверніть\nгігабайти",
            "«Обрано» й «Орієнтовна економія» — просто під час прибирання.",
        ),
    ],
    # The line break in each headline is chosen for that language, not carried
    # over from English: German and Portuguese break in different places than
    # "Find the photos / that look alike" does. fit_font_size() shrinks type
    # instead of failing, so an unread contact sheet hides an overlong headline
    # as small text rather than as an error.
    "de": [
        (
            "AUF DEM GERÄT",
            "Finde die Fotos,\ndie sich ähneln",
            "Alike durchsucht deine Mediathek mit Apple Vision, ganz auf dem iPhone.",
        ),
        (
            "EINE LISTE",
            "Jede Gruppe,\nbereit zur Prüfung",
            "Gruppen kommen mit Prüfstatus: du siehst immer, was noch offen ist.",
        ),
        (
            "BESTE AUFNAHME",
            "Die beste ist\nschon gewählt",
            "Alike hebt die beste Aufnahme jeder Gruppe hervor. Du bestätigst nur.",
        ),
        (
            "VERGLEICHEN",
            "Erst prüfen,\ndann aufräumen",
            "Ansicht in voller Größe. Nichts wird ohne deine Bestätigung gelöscht.",
        ),
        (
            "FREIER PLATZ",
            "Hol dir die\nGigabyte zurück",
            "Ausgewählt und geschätzte Ersparnis, während du aufräumst.",
        ),
    ],
    "fr": [
        (
            "SUR L’APPAREIL",
            "Trouvez les photos\nqui se ressemblent",
            "Alike analyse votre photothèque avec Apple Vision, sur votre iPhone.",
        ),
        (
            "UNE SEULE FILE",
            "Chaque groupe,\nprêt à examiner",
            "Les groupes arrivent avec des badges : vous voyez ce qui reste.",
        ),
        (
            "MEILLEURE PHOTO",
            "La photo à garder\nest déjà choisie",
            "Alike met en avant la meilleure de chaque groupe. Vous confirmez.",
        ),
        (
            "COMPARER",
            "Vérifiez avant\nde nettoyer",
            "Examen en plein écran. Rien n’est supprimé sans votre confirmation.",
        ),
        (
            "ESPACE LIBRE",
            "Récupérez\nvos gigaoctets",
            "Sélectionnées et économie estimée, suivies pendant le nettoyage.",
        ),
    ],
    # es and es-419 diverge where the app's own strings do: "cola" is the queue
    # in Spain and "fila" in Latin America, and es-419 keeps the simple past
    # where es-ES uses the present perfect.
    "es": [
        (
            "EN EL DISPOSITIVO",
            "Encuentra las fotos\nque se parecen",
            "Alike analiza tu fototeca con Apple Vision, todo en tu iPhone.",
        ),
        (
            "UNA SOLA COLA",
            "Cada grupo,\nlisto para revisar",
            "Los grupos llegan con indicadores: siempre sabes qué queda.",
        ),
        (
            "MEJOR TOMA",
            "La que conservas\nya está elegida",
            "Alike destaca la mejor toma de cada grupo. Tú solo confirmas.",
        ),
        (
            "COMPARAR",
            "Comprueba antes\nde limpiar",
            "Revisión a tamaño completo. Nada se elimina sin tu confirmación.",
        ),
        (
            "ESPACIO LIBRE",
            "Recupera los\ngigabytes",
            "Seleccionadas y ahorro estimado, mientras vas limpiando.",
        ),
    ],
    "es-419": [
        (
            "EN EL DISPOSITIVO",
            "Encuentra las fotos\nque se parecen",
            "Alike analiza tu fototeca con Apple Vision, todo en tu iPhone.",
        ),
        (
            "UNA SOLA FILA",
            "Cada grupo,\nlisto para revisar",
            "Los grupos llegan con indicadores: siempre sabes qué falta.",
        ),
        (
            "MEJOR TOMA",
            "La que conservas\nya está elegida",
            "Alike destaca la mejor toma de cada grupo. Tú solo confirmas.",
        ),
        (
            "COMPARAR",
            "Revisa antes\nde limpiar",
            "Revisión a tamaño completo. Nada se elimina sin tu confirmación.",
        ),
        (
            "ESPACIO LIBRE",
            "Recupera los\ngigabytes",
            "Seleccionadas y ahorro estimado, mientras vas limpiando.",
        ),
    ],
    "pt-BR": [
        (
            "NO DISPOSITIVO",
            "Encontre as fotos\nque se parecem",
            "O Alike analisa sua fototeca com Apple Vision, no seu iPhone.",
        ),
        (
            "UMA SÓ FILA",
            "Cada grupo,\npronto para revisar",
            "Os grupos chegam com selos: você sempre vê o que falta.",
        ),
        (
            "MELHOR FOTO",
            "A que fica\njá está escolhida",
            "O Alike destaca a melhor foto de cada grupo. Você só confirma.",
        ),
        (
            "COMPARAR",
            "Confira antes\nde limpar",
            "Revisão em tamanho real. Nada é apagado sem a sua confirmação.",
        ),
        (
            "ESPAÇO LIVRE",
            "Recupere os\ngigabytes",
            "Selecionadas e economia estimada, enquanto você limpa.",
        ),
    ],
}


@dataclass(frozen=True)
class Variant:
    """One background direction. Palette, type, slides and copy never change."""

    name: str
    description: str
    background: str
    label_style: str  # "pill" | "solid" | "rule"
    halo_alpha: int


VARIANTS = (
    Variant(
        name="glass-bands",
        description="Tilted translucent bands and outline rings; the busiest of the four.",
        background="bands",
        label_style="pill",
        halo_alpha=68,
    ),
    Variant(
        name="spotlight",
        description="One soft glow behind the device, everything else black; the quietest.",
        background="spotlight",
        label_style="pill",
        halo_alpha=104,
    ),
    Variant(
        name="blocks",
        description="A tinted block anchoring the caption half, phone crossing its edge.",
        background="blocks",
        label_style="solid",
        halo_alpha=60,
    ),
    Variant(
        name="stack",
        description="Dot grid plus offset photo cards — the 'similar photos' motif.",
        background="stack",
        label_style="rule",
        halo_alpha=76,
    ),
)
VARIANTS_BY_NAME = {variant.name: variant for variant in VARIANTS}
DEFAULT_VARIANT = "spotlight"  # the direction shipping on the listing


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--locales", default="all", help="Comma-separated locales, or 'all'.")
    parser.add_argument("--variant", default=DEFAULT_VARIANT, choices=[v.name for v in VARIANTS])
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_ROOT), help="Output root directory.")
    parser.add_argument(
        "--drafts",
        action="store_true",
        help=f"Render every variant into {DRAFT_ROOT.relative_to(ROOT)}/ for comparison instead of the listing.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Validate sources and layouts without writing PNGs.")
    return parser.parse_args()


def selected_locales(raw: str) -> list[str]:
    if raw == "all":
        return list(LOCALES)
    values = [item.strip() for item in raw.split(",") if item.strip()]
    unknown = sorted(set(values) - set(LOCALES))
    if unknown:
        raise SystemExit(f"Unsupported locales: {', '.join(unknown)}")
    return values


@lru_cache(maxsize=64)
def font(size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    """SF Pro at a named weight. SF is a variable font, so Bold is an instance."""
    try:
        face = ImageFont.truetype(FONT_PATH, size=size)
        face.set_variation_by_name(weight)
        return face
    except (OSError, AttributeError):
        return ImageFont.truetype(FALLBACK_FONT_PATH, size=size)


def new_layer() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    """Translucent drawing has to go through alpha_composite.

    ImageDraw writes the ink alpha straight into the target instead of blending
    it, so a 10%-alpha fill drawn directly on the canvas would come back fully
    opaque once the render is flattened to RGB.
    """
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    return layer, ImageDraw.Draw(layer)


def clear_of(zone: tuple[int, int], y: int, radius: int) -> bool:
    return y + radius < zone[0] or y - radius > zone[1]


def vertical_gradient(top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    column = Image.new("RGB", (1, CANVAS[1]))
    pixels = column.load()
    for y in range(CANVAS[1]):
        t = y / (CANVAS[1] - 1)
        pixels[0, y] = tuple(round(top[index] * (1 - t) + bottom[index] * t) for index in range(3))
    return column.resize(CANVAS, Image.Resampling.BILINEAR).convert("RGBA")


def radial_glow(center: tuple[int, int], radius: int, color: tuple[int, int, int], alpha: int) -> Image.Image:
    """A soft round falloff, built small and scaled up — cheap and smooth."""
    steps = 48
    small = Image.new("L", (steps * 2, steps * 2), 0)
    draw = ImageDraw.Draw(small)
    for step in range(steps, 0, -1):
        value = round(alpha * (1 - step / steps) ** 1.6)
        draw.ellipse((steps - step, steps - step, steps + step, steps + step), fill=value)
    canvas_mask = Image.new("L", CANVAS, 0)
    canvas_mask.paste(small.resize((radius * 2, radius * 2), Image.Resampling.BICUBIC), (center[0] - radius, center[1] - radius))
    glow = Image.new("RGBA", CANVAS, color + (255,))
    glow.putalpha(canvas_mask)
    return glow


def background_bands(canvas: Image.Image, slide_index: int, band: str, zone: tuple[int, int]) -> None:
    accent = THEME[band]
    for color, y, tilt, alpha in (
        (accent, 420 + slide_index * 40, -6, 34),
        (THEME["purple"], 1240 - slide_index * 30, 5, 26),
        (accent, 2180 + slide_index * 20, -4, 22),
    ):
        layer, draw = new_layer()
        points = [
            (-120, y + tilt * -14),
            (CANVAS[0] + 120, y + tilt * 22),
            (CANVAS[0] + 120, y + 240 + tilt * 22),
            (-120, y + 240 + tilt * -14),
        ]
        draw.polygon(points, fill=color + (alpha,))
        draw.line(points[:2], fill=color + (90,), width=3)
        canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(2)))

    layer, draw = new_layer()
    for x, y, radius, color in (
        (150 + slide_index * 60, 760, 104, accent),
        (1180, 1620, 82, THEME["purple"]),
        (240, 2420, 70, accent),
    ):
        if clear_of(zone, y, radius):
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=color + (58,), width=4)
    canvas.alpha_composite(layer)


def background_spotlight(canvas: Image.Image, slide_index: int, band: str, zone: tuple[int, int]) -> None:
    accent = THEME[band]
    device_center = 1900 if zone[0] > CANVAS[1] // 2 else 1020
    canvas.alpha_composite(radial_glow((660, device_center), 880, accent, 60))
    canvas.alpha_composite(radial_glow((980 - slide_index * 60, device_center - 620), 520, THEME["purple"], 34))

    layer, draw = new_layer()
    horizon = device_center + 660
    draw.line((0, horizon, CANVAS[0], horizon), fill=accent + (40,), width=2)
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(3)))


def background_blocks(canvas: Image.Image, slide_index: int, band: str, zone: tuple[int, int]) -> None:
    accent = THEME[band]
    caption_at_top = zone[0] < CANVAS[1] // 2
    block = (-80, -80, CANVAS[0] + 80, 1260) if caption_at_top else (-80, 1620, CANVAS[0] + 80, CANVAS[1] + 80)
    edge_y = block[3] if caption_at_top else block[1]

    layer, draw = new_layer()
    draw.rounded_rectangle(block, radius=96, fill=accent + (30,))
    draw.rounded_rectangle(
        (block[0] + 40, block[1] + 40, block[2] - 40, block[3] - 40), radius=72, outline=accent + (46,), width=3
    )
    draw.line((0, edge_y, CANVAS[0], edge_y), fill=accent + (170,), width=4)
    canvas.alpha_composite(layer)

    layer, draw = new_layer()
    offset = 120 + slide_index * 40
    draw.rounded_rectangle(
        (CANVAS[0] - 340, edge_y + (offset if caption_at_top else -offset - 260), CANVAS[0] + 80, edge_y + (offset + 260 if caption_at_top else -offset)),
        radius=56,
        fill=THEME["purple"] + (22,),
    )
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(1)))


def background_stack(canvas: Image.Image, slide_index: int, band: str, zone: tuple[int, int]) -> None:
    accent = THEME[band]
    layer, draw = new_layer()
    for y in range(60, CANVAS[1], 72):
        for x in range(60, CANVAS[0], 72):
            draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(255, 255, 255, 16))
    canvas.alpha_composite(layer)

    # Offset cards behind the device: three near-identical frames, which is the
    # thing the app is about.
    caption_at_top = zone[0] < CANVAS[1] // 2
    base_y = 1180 if caption_at_top else 380
    for dx, dy, alpha, angle in ((-290, -120, 26, -8.0), (-130, -50, 34, -4.0), (60, 20, 44, 0.0)):
        card, draw = new_layer()
        draw.rounded_rectangle(
            (330 + dx, base_y + dy, 330 + dx + 700, base_y + dy + 1180),
            radius=88,
            fill=accent + (alpha,),
            outline=accent + (alpha + 40,),
            width=3,
        )
        if angle:
            card = card.rotate(angle, resample=Image.Resampling.BICUBIC, center=(660, base_y + 590))
        canvas.alpha_composite(card)
    canvas.alpha_composite(radial_glow((660, base_y + 560), 700, THEME["purple"], 26))


BACKGROUNDS = {
    "bands": background_bands,
    "spotlight": background_spotlight,
    "blocks": background_blocks,
    "stack": background_stack,
}


@lru_cache(maxsize=len(SLIDES) * len(VARIANTS))
def base_canvas(slide_index: int, band: str, background: str, zone: tuple[int, int]) -> Image.Image:
    canvas = vertical_gradient(THEME["top"], THEME["bottom"])
    BACKGROUNDS[background](canvas, slide_index, band, zone)
    return canvas


def aligned_x(x: int, width: int, content_width: int, align: str) -> int:
    if align == "right":
        return x + width - content_width
    if align == "center":
        return x + (width - content_width) // 2
    return x


def text_width(draw: ImageDraw.ImageDraw, text: str, font_obj: ImageFont.FreeTypeFont) -> int:
    bbox = draw.textbbox((0, 0), text, font=font_obj)
    return bbox[2] - bbox[0]


def fit_text_lines(text: str, draw: ImageDraw.ImageDraw, font_obj: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    lines: list[str] = []
    for source_line in text.splitlines():
        words = source_line.split()
        if not words:
            lines.append("")
            continue
        current = ""
        for word in words:
            candidate = word if not current else f"{current} {word}"
            if text_width(draw, candidate, font_obj) <= max_width or not current:
                current = candidate
            else:
                lines.append(current)
                current = word
        if current:
            lines.append(current)
    return lines


def fit_font_size(
    text: str,
    draw: ImageDraw.ImageDraw,
    start_size: int,
    max_width: int,
    max_lines: int,
    weight: str,
    line_ratio: float,
    max_height: int | None = None,
    min_size: int = 44,
) -> int:
    """Shrink until the copy fits. Ukrainian headlines run longer than English."""
    size = start_size
    while size > min_size:
        font_obj = font(size, weight)
        lines = fit_text_lines(text, draw, font_obj, max_width)
        fits_height = max_height is None or len(lines) * int(size * line_ratio) <= max_height
        if (
            len(lines) <= max_lines
            and fits_height
            and all(text_width(draw, line, font_obj) <= max_width for line in lines)
        ):
            return size
        size -= 4
    return size


def draw_label(canvas: Image.Image, layout: SlideLayout, variant: Variant, label: str) -> None:
    accent = THEME[layout.band]
    caption = layout.caption
    label_font = font(30, "Bold")
    layer, draw = new_layer()

    if variant.label_style == "rule":
        rule_width = 96
        content_width = rule_width + 24 + text_width(draw, label, label_font)
        x = aligned_x(caption.x, caption.width, content_width, caption.align)
        draw.rounded_rectangle((x, caption.y - 4, x + rule_width, caption.y + 4), radius=4, fill=accent + (255,))
        draw.text((x + rule_width + 24, caption.y - 22), label, font=label_font, fill=accent + (255,))
        canvas.alpha_composite(layer)
        return

    pill_width = text_width(draw, label, label_font) + 76
    pill_x = aligned_x(caption.x, caption.width, pill_width, caption.align)
    pill_y = caption.y - 44
    box = (pill_x, pill_y, pill_x + pill_width, pill_y + 62)

    if variant.label_style == "solid":
        draw.rounded_rectangle(box, radius=31, fill=accent + (235,))
        text_fill = THEME["top"] + (255,)
        dot_fill = THEME["top"] + (255,)
    else:
        draw.rounded_rectangle(box, radius=31, fill=(255, 255, 255, 24), outline=accent + (170,), width=2)
        text_fill = THEME["fg"] + (255,)
        dot_fill = accent + (255,)

    dot_y = pill_y + 31
    draw.ellipse((pill_x + 24, dot_y - 8, pill_x + 40, dot_y + 8), fill=dot_fill)
    draw.text((pill_x + 54, pill_y + 15), label, font=label_font, fill=text_fill)
    canvas.alpha_composite(layer)


def draw_caption(canvas: Image.Image, layout: SlideLayout, variant: Variant, copy: tuple[str, str, str]) -> None:
    label, headline, subtitle = copy
    caption = layout.caption
    draw_label(canvas, layout, variant, label)

    layer, draw = new_layer()
    headline_y = caption.y + 72
    headline_size = fit_font_size(
        headline,
        draw,
        caption.headline_size,
        caption.width,
        3,
        "Bold",
        1.08,
        max_height=max(120, layout.subtitle.y - headline_y - 30),
        min_size=64,
    )
    headline_font = font(headline_size, "Bold")
    line_height = int(headline_size * 1.08)
    text_y = headline_y
    for line in fit_text_lines(headline, draw, headline_font, caption.width):
        line_width = text_width(draw, line, headline_font)
        draw.text(
            (aligned_x(caption.x, caption.width, line_width, caption.align), text_y),
            line,
            font=headline_font,
            fill=THEME["fg"] + (255,),
        )
        text_y += line_height

    subtitle_transform = layout.subtitle
    subtitle_size = fit_font_size(
        subtitle, draw, layout.subtitle_size, subtitle_transform.width, 2, "Medium", 1.3, min_size=34
    )
    subtitle_font = font(subtitle_size, "Medium")
    subtitle_y = subtitle_transform.y
    for line in fit_text_lines(subtitle, draw, subtitle_font, subtitle_transform.width):
        line_width = text_width(draw, line, subtitle_font)
        draw.text(
            (aligned_x(subtitle_transform.x, subtitle_transform.width, line_width, subtitle_transform.align), subtitle_y),
            line,
            font=subtitle_font,
            fill=THEME["muted"] + (255,),
        )
        subtitle_y += int(subtitle_size * 1.3)
    canvas.alpha_composite(layer)


def cover_crop(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Fill the screen rect without distorting; trim from the bottom, not the top."""
    src_w, src_h = image.size
    dst_w, dst_h = size
    scale = max(dst_w / src_w, dst_h / src_h)
    resized = image.resize((round(src_w * scale), round(src_h * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - dst_w) // 2
    return resized.crop((left, 0, left + dst_w, dst_h))


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def render_phone(screenshot_path: Path) -> Image.Image:
    mockup = Image.open(MOCKUP_PATH).convert("RGBA").resize(MOCKUP_SIZE, Image.Resampling.LANCZOS)
    screenshot = Image.open(screenshot_path).convert("RGBA")
    screen_w = PHONE_SCREEN_RECT[2] - PHONE_SCREEN_RECT[0]
    screen_h = PHONE_SCREEN_RECT[3] - PHONE_SCREEN_RECT[1]
    screen = cover_crop(screenshot, (screen_w, screen_h))
    screen.putalpha(rounded_mask((screen_w, screen_h), 126))

    phone = Image.new("RGBA", MOCKUP_SIZE, (0, 0, 0, 0))
    phone.alpha_composite(mockup, (0, 0))
    phone.alpha_composite(screen, (PHONE_SCREEN_RECT[0], PHONE_SCREEN_RECT[1]))
    return phone


def composite_clipped(canvas: Image.Image, layer: Image.Image, x: int, y: int) -> None:
    """alpha_composite refuses negative offsets, and slides run off the edges."""
    left, top = max(0, -x), max(0, -y)
    right = min(layer.width, CANVAS[0] - x)
    bottom = min(layer.height, CANVAS[1] - y)
    if left >= right or top >= bottom:
        return
    canvas.alpha_composite(layer.crop((left, top, right, bottom)), (x + left, y + top))


def paste_phone(canvas: Image.Image, layout: SlideLayout, variant: Variant, screenshot_path: Path) -> None:
    transform = layout.device
    phone = render_phone(screenshot_path).resize(
        (transform.width, transform.height), Image.Resampling.LANCZOS
    )
    x, y = transform.x, transform.y
    if transform.rotation:
        phone = phone.rotate(transform.rotation, resample=Image.Resampling.BICUBIC, expand=True)
        x -= (phone.width - transform.width) // 2
        y -= (phone.height - transform.height) // 2

    # A dark shadow is invisible on a dark canvas, so the phone gets an
    # accent-tinted halo instead: it separates the device from the background
    # and ties the slide to the band colour.
    padding = 140
    halo_alpha = Image.new("L", (phone.width + padding * 2, phone.height + padding * 2), 0)
    halo_alpha.paste(phone.getchannel("A"), (padding, padding))
    halo_alpha = halo_alpha.filter(ImageFilter.GaussianBlur(64)).point(
        lambda value: value * variant.halo_alpha // 255
    )
    halo = Image.new("RGBA", halo_alpha.size, THEME[layout.band] + (255,))
    halo.putalpha(halo_alpha)
    composite_clipped(canvas, halo, x - padding, y - padding + 24)
    composite_clipped(canvas, phone, x, y)


def render_slide(
    index: int, layout: SlideLayout, variant: Variant, copy: tuple[str, str, str], screenshot_path: Path
) -> Image.Image:
    canvas = base_canvas(index, layout.band, variant.background, layout.caption_zone).copy()
    draw_caption(canvas, layout, variant, copy)
    paste_phone(canvas, layout, variant, screenshot_path)
    return canvas.convert("RGB")


def validate_sources(locales: list[str]) -> None:
    if not MOCKUP_PATH.exists():
        raise SystemExit(f"Missing iPhone mockup: {MOCKUP_PATH}")
    if Image.open(MOCKUP_PATH).size != MOCKUP_SIZE:
        raise SystemExit(f"{MOCKUP_PATH} must be {MOCKUP_SIZE[0]}x{MOCKUP_SIZE[1]}")
    missing = []
    for locale in locales:
        if locale not in COPY or len(COPY[locale]) != len(SLIDES):
            raise SystemExit(f"Missing marketing copy for {len(SLIDES)} slides in {locale}")
        for slide in SLIDES:
            source = SOURCE_ROOT / locale / slide.source
            if not source.exists():
                missing.append(source)
    if missing:
        raise SystemExit("Missing source captures:\n" + "\n".join(str(path) for path in missing))


def render_locale(variant: Variant, locale: str, output_root: Path, quiet: bool = False) -> list[Path]:
    locale_output = output_root / locale
    locale_output.mkdir(parents=True, exist_ok=True)
    rendered: list[Path] = []
    for index, slide in enumerate(SLIDES):
        image = render_slide(index, slide, variant, COPY[locale][index], SOURCE_ROOT / locale / slide.source)
        assert image.size == CANVAS, f"{slide.source} rendered at {image.size}"
        target = locale_output / slide.source
        image.save(target, optimize=True)
        rendered.append(target)
        if not quiet:
            print(f"  {locale}  {target.name}")
    return rendered


def contact_sheet(rows: list[tuple[str, list[Path]]], output: Path, thumb_size: tuple[int, int] = (176, 382)) -> None:
    pad, label_w = 24, 190
    columns = max(len(files) for _, files in rows)
    sheet = Image.new(
        "RGB",
        (label_w + pad * (columns + 1) + thumb_size[0] * columns, pad + len(rows) * (thumb_size[1] + pad)),
        (18, 20, 24),
    )
    draw = ImageDraw.Draw(sheet)
    for row, (label, files) in enumerate(rows):
        y = pad + row * (thumb_size[1] + pad)
        draw.text((pad, y + 20), label, font=font(22, "Bold"), fill=(240, 244, 248))
        for col, path in enumerate(files):
            image = Image.open(path).convert("RGB").resize(thumb_size, Image.Resampling.LANCZOS)
            sheet.paste(image, (label_w + pad + col * (thumb_size[0] + pad), y))
    sheet.save(output)


def render_drafts(locales: list[str]) -> None:
    DRAFT_ROOT.mkdir(parents=True, exist_ok=True)
    comparison: list[tuple[str, list[Path]]] = []
    for variant in VARIANTS:
        print(f"{variant.name}: {variant.description}")
        variant_root = DRAFT_ROOT / variant.name
        rows: list[tuple[str, list[Path]]] = []
        for locale in locales:
            rendered = render_locale(variant, locale, variant_root, quiet=True)
            rows.append((locale, rendered))
        contact_sheet(rows, variant_root / "contact-sheet.png", thumb_size=(260, 566))
        comparison.append((variant.name, rows[0][1]))
    contact_sheet(comparison, DRAFT_ROOT / "contact-sheet-all-variants.png")
    print(f"\n{len(VARIANTS)} variants in {DRAFT_ROOT.relative_to(ROOT)}/")
    print(f"Compare: {(DRAFT_ROOT / 'contact-sheet-all-variants.png').relative_to(ROOT)}")


def main() -> None:
    args = parse_args()
    locales = selected_locales(args.locales)
    validate_sources(locales)

    if args.dry_run:
        print(f"ok: {len(SLIDES)} slides x {len(locales)} locales x {len(VARIANTS)} variants")
        return

    if args.drafts:
        render_drafts(locales)
        return

    variant = VARIANTS_BY_NAME[args.variant]
    output_root = Path(args.output)
    if not output_root.is_absolute():
        output_root = ROOT / output_root

    CONTACT_SHEET_ROOT.mkdir(parents=True, exist_ok=True)
    rows: list[tuple[str, list[Path]]] = []
    for locale in locales:
        rendered = render_locale(variant, locale, output_root)
        contact_sheet([(locale, rendered)], CONTACT_SHEET_ROOT / f"contact-sheet-{locale}.png", (260, 566))
        rows.append((locale, rendered))

    contact_sheet(rows, CONTACT_SHEET_ROOT / "contact-sheet-all-locales.png")
    total = sum(len(files) for _, files in rows)
    print(f"\n{total} product screenshots ({variant.name}) in {output_root.relative_to(ROOT)}/  at {CANVAS[0]}x{CANVAS[1]}")
    print(f"Contact sheets in {CONTACT_SHEET_ROOT.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
