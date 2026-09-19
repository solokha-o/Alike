#!/usr/bin/env python3
"""Render the Custom Product Page screenshot sets for Apple Ads (ASA #9).

A Custom Product Page is a second App Store listing shown only to people who
tapped a specific ad, so each set answers one search intent and nothing else.
Three sets, three intents:

  cpp-duplicates  "duplicate photos"   hero: a group of near-identical frames
  cpp-storage     "space on my phone"  hero: what Smart Cleanup can reclaim
  cpp-bestshot    "best shot"          hero: the keeper already picked

  in   `Docs/images/raw/<locale>/` — the same bare captures the listing uses
  out  `build/generated/custom_product_pages/<set>/<locale>/`

Nothing here writes into `Docs/images/`: these renders are uploaded to App Store
Connect by hand, not through the listing bundle.

    build/tools-venv/bin/python tools/generate_custom_product_pages.py --drafts
    open build/generated/custom_product_pages/contact-sheet-all-sets.png

Sources are limited to the seven captures that exist in every locale, so a set
renders identically in en-US, it, nl and pl. The extra en-US-only captures
(02, 06, 08, 13) are deliberately unused.
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from generate_app_store_product_screenshots import (  # noqa: E402
    CANVAS,
    DeviceTransform,
    SlideLayout,
    SOURCE_ROOT,
    VARIANTS_BY_NAME,
    caption_bottom,
    caption_top,
    contact_sheet,
    render_slide,
    subtitle_bottom,
    subtitle_top,
)

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = ROOT / "build" / "generated" / "custom_product_pages"

# The listing ships "spotlight"; a CPP that looked like a different app would
# read as a different product, so the sets stay on it.
VARIANT = VARIANTS_BY_NAME["spotlight"]

# Captures present in en-US, it, nl and pl alike.
SHARED_SOURCES = frozenset(
    {
        "01-scanner-idle.png",
        "03-cleanup-queue.png",
        "04-cluster-details.png",
        "05-comparison-review.png",
        "07-cleanup-progress.png",
        "14-best-shot-enhanced.png",
        "15-widgets-home.png",
    }
)

# The two compositions the listing alternates, reused so a CPP sits beside the
# default page without looking foreign.
HERO = SlideLayout(
    source="",
    caption=caption_top("left"),
    subtitle=subtitle_top("left"),
    subtitle_size=44,
    device=DeviceTransform(x=100, y=900, width=1120, rotation=-3.0),
    band="accent",
)
SECOND = SlideLayout(
    source="",
    caption=caption_bottom("right"),
    subtitle=subtitle_bottom("right"),
    subtitle_size=44,
    device=DeviceTransform(x=220, y=96, width=880, rotation=4.0),
    band="purple",
)
THIRD = SlideLayout(
    source="",
    caption=caption_top("right", headline_size=106),
    subtitle=subtitle_top("right"),
    subtitle_size=44,
    device=DeviceTransform(x=100, y=900, width=1120, rotation=3.4),
    band="green",
)
COMPOSITIONS = (HERO, SECOND, THIRD)


@dataclass(frozen=True)
class PageSet:
    name: str
    intent: str
    sources: tuple[str, ...]
    copy: dict[str, tuple[tuple[str, str, str], ...]]


SETS = (
    PageSet(
        name="cpp-duplicates",
        intent="duplicate photos",
        sources=("04-cluster-details.png", "03-cleanup-queue.png", "05-comparison-review.png"),
        copy={
            "en-US": (
                (
                    "GROUPED FOR YOU",
                    "Four shots.\nOne keeper.",
                    "Alike finds the near-identical frames and groups them, so duplicates stop hiding one scroll apart.",
                ),
                (
                    "ONE QUEUE",
                    "Every group,\nready to review",
                    "Groups arrive with review badges, so you always know what is left.",
                ),
                (
                    "COMPARE",
                    "Check before\nanything goes",
                    "Review at full size. Nothing is deleted without your confirmation.",
                ),
            ),
            "it": (
                (
                    "RAGGRUPPATE",
                    "Quattro scatti.\nUno da tenere.",
                    "Alike trova i fotogrammi quasi identici e li raggruppa: i doppioni non si nascondono più a uno scroll di distanza.",
                ),
                (
                    "UNA SOLA CODA",
                    "Ogni gruppo,\npronto da controllare",
                    "I gruppi arrivano con gli indicatori: vedi sempre cosa manca.",
                ),
                (
                    "CONFRONTA",
                    "Controlla prima\ndi eliminare",
                    "Revisione a dimensione piena. Niente sparisce senza conferma.",
                ),
            ),
            "nl": (
                (
                    "GEGROEPEERD",
                    "Vier opnames.\nÉén blijver.",
                    "Alike vindt de bijna identieke opnames en groepeert ze, zodat dubbele foto's zich niet meer verstoppen.",
                ),
                (
                    "ÉÉN WACHTRIJ",
                    "Elke groep,\nklaar om te bekijken",
                    "Groepen komen met statuslabels: je ziet altijd wat er nog ligt.",
                ),
                (
                    "VERGELIJK",
                    "Kijk eerst,\nruim daarna op",
                    "Bekijk op volle grootte. Niets verdwijnt zonder je bevestiging.",
                ),
            ),
            "pl": (
                (
                    "POGRUPOWANE",
                    "Cztery ujęcia.\nJedno zostaje.",
                    "Alike znajduje niemal identyczne kadry i łączy je w grupy — duplikaty przestają ukrywać się w bibliotece.",
                ),
                (
                    "JEDNA KOLEJKA",
                    "Każda grupa\ngotowa do przeglądu",
                    "Grupy mają znaczniki przeglądu — zawsze wiesz, co zostało.",
                ),
                (
                    "PORÓWNAJ",
                    "Sprawdź, zanim\ncokolwiek zniknie",
                    "Podgląd w pełnym rozmiarze. Nic nie znika bez potwierdzenia.",
                ),
            ),
        },
    ),
    PageSet(
        name="cpp-storage",
        intent="space on my phone",
        sources=("03-cleanup-queue.png", "07-cleanup-progress.png", "04-cluster-details.png"),
        copy={
            "en-US": (
                (
                    "SMART CLEANUP",
                    "Screenshots and\nblurs, already found",
                    "Alike totals what each pile can give back before you delete a single photo.",
                ),
                (
                    "AS YOU GO",
                    "The number moves\nwhile you clean",
                    "Selected photos and estimated savings, counted in real time.",
                ),
                (
                    "NOTHING GUESSED",
                    "See the size\nbefore it goes",
                    "Every group shows what keeping three of four actually costs you.",
                ),
            ),
            "it": (
                (
                    "PULIZIA SMART",
                    "Screenshot e foto\nmosse, già trovati",
                    "Alike calcola quanto può restituire ogni gruppo prima che tu elimini una sola foto.",
                ),
                (
                    "MENTRE PULISCI",
                    "Il numero cresce\nmentre fai pulizia",
                    "Foto selezionate e risparmio stimato, contati in tempo reale.",
                ),
                (
                    "NIENTE A CASO",
                    "Vedi la dimensione\nprima di eliminare",
                    "Ogni gruppo mostra quanto costa davvero tenere tre foto su quattro.",
                ),
            ),
            "nl": (
                (
                    "SLIM OPRUIMEN",
                    "Schermafbeeldingen\nen wazige foto's",
                    "Alike telt op wat elke stapel kan teruggeven, voordat je één foto verwijdert.",
                ),
                (
                    "TIJDENS HET OPRUIMEN",
                    "Het getal loopt op\nterwijl je opruimt",
                    "Geselecteerde foto's en geschatte besparing, in real time geteld.",
                ),
                (
                    "NIETS GEGOKT",
                    "Zie de grootte\nvoordat het weg is",
                    "Elke groep laat zien wat drie van de vier bewaren echt kost.",
                ),
            ),
            "pl": (
                (
                    "INTELIGENTNE PORZĄDKI",
                    "Zrzuty ekranu\ni rozmyte zdjęcia",
                    "Alike podlicza, ile może oddać każda grupa, zanim usuniesz choć jedno zdjęcie.",
                ),
                (
                    "NA BIEŻĄCO",
                    "Licznik rośnie\npodczas porządków",
                    "Wybrane zdjęcia i szacowana oszczędność, liczone na bieżąco.",
                ),
                (
                    "NIC NA OKO",
                    "Zobacz rozmiar,\nzanim zniknie",
                    "Każda grupa pokazuje, ile naprawdę kosztuje zostawienie trzech zdjęć z czterech.",
                ),
            ),
        },
    ),
    PageSet(
        name="cpp-bestshot",
        intent="best shot",
        sources=("04-cluster-details.png", "14-best-shot-enhanced.png", "05-comparison-review.png"),
        copy={
            "en-US": (
                (
                    "BEST SHOT",
                    "The keeper is\nalready picked",
                    "Alike marks the sharpest, best-exposed frame in each burst. You just confirm.",
                ),
                (
                    "AND BETTER",
                    "Improve the keeper,\nkeep the original",
                    "One tap makes the best shot better. One tap puts it back — the original never leaves your library.",
                ),
                (
                    "YOUR CALL",
                    "Disagree in\none tap",
                    "Review at full size and pick a different keeper whenever Alike gets it wrong.",
                ),
            ),
            "it": (
                (
                    "SCATTO MIGLIORE",
                    "La foto da tenere\nè già scelta",
                    "Alike segna il fotogramma più nitido e meglio esposto di ogni raffica. A te la conferma.",
                ),
                (
                    "E ANCHE MEGLIO",
                    "Migliora lo scatto,\ntieni l’originale",
                    "Un tocco migliora lo scatto migliore. Un altro lo riporta com’era — l’originale non lascia mai la tua libreria.",
                ),
                (
                    "DECIDI TU",
                    "Cambi idea\ncon un tocco",
                    "Guarda a dimensione piena e scegli un altro scatto quando Alike sbaglia.",
                ),
            ),
            "nl": (
                (
                    "BESTE OPNAME",
                    "De blijver is\nal gekozen",
                    "Alike markeert de scherpste, best belichte opname uit elke reeks. Jij bevestigt alleen.",
                ),
                (
                    "EN BETER",
                    "Maak de blijver beter,\nhoud het origineel",
                    "Eén tik maakt de beste opname beter. Eén tik zet hem terug — het origineel blijft in je bibliotheek.",
                ),
                (
                    "JOUW KEUZE",
                    "Niet eens?\nEén tik.",
                    "Bekijk op volle grootte en kies een andere blijver wanneer Alike het mis heeft.",
                ),
            ),
            "pl": (
                (
                    "NAJLEPSZE UJĘCIE",
                    "Zdjęcie do zostawienia\njest już wybrane",
                    "Alike zaznacza najostrzejszy, najlepiej naświetlony kadr z serii. Ty tylko potwierdzasz.",
                ),
                (
                    "I JESZCZE LEPIEJ",
                    "Popraw ujęcie,\nzachowaj oryginał",
                    "Jedno dotknięcie poprawia najlepsze ujęcie. Drugie przywraca oryginał — nigdy nie znika on z biblioteki.",
                ),
                (
                    "TWÓJ WYBÓR",
                    "Nie zgadzasz się?\nJedno dotknięcie.",
                    "Obejrzyj w pełnym rozmiarze i wybierz inne ujęcie, gdy Alike się pomyli.",
                ),
            ),
        },
    ),
)
SETS_BY_NAME = {page_set.name: page_set for page_set in SETS}


def validate() -> None:
    for page_set in SETS:
        assert len(page_set.sources) == len(COMPOSITIONS), f"{page_set.name}: 3 slides expected"
        for source in page_set.sources:
            assert source in SHARED_SOURCES, f"{page_set.name}: {source} is not in every locale"
        for locale, copy in page_set.copy.items():
            assert len(copy) == len(page_set.sources), f"{page_set.name}/{locale}: copy count"


def render_set(page_set: PageSet, locale: str, quiet: bool = False) -> list[Path]:
    output = OUTPUT_ROOT / page_set.name / locale
    output.mkdir(parents=True, exist_ok=True)
    rendered: list[Path] = []
    for index, (source, composition) in enumerate(zip(page_set.sources, COMPOSITIONS)):
        layout = SlideLayout(
            source=source,
            caption=composition.caption,
            subtitle=composition.subtitle,
            subtitle_size=composition.subtitle_size,
            device=composition.device,
            band=composition.band,
        )
        image = render_slide(
            index, layout, VARIANT, page_set.copy[locale][index], SOURCE_ROOT / locale / source, locale
        )
        assert image.size == CANVAS, f"{source} rendered at {image.size}"
        target = output / f"{index + 1:02d}-{source}"
        image.save(target, optimize=True)
        rendered.append(target)
        if not quiet:
            print(f"  {page_set.name}  {locale}  {target.name}")
    return rendered


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--locales", default="en-US", help="Comma-separated locales.")
    parser.add_argument("--sets", default="all", help="Comma-separated set names, or 'all'.")
    parser.add_argument("--drafts", action="store_true", help="Also write a contact sheet across all sets.")
    parser.add_argument("--dry-run", action="store_true", help="Validate sources and copy without writing PNGs.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    validate()
    chosen = SETS if args.sets == "all" else tuple(SETS_BY_NAME[name] for name in args.sets.split(","))
    locales = tuple(locale.strip() for locale in args.locales.split(","))

    if args.dry_run:
        missing = [
            str((SOURCE_ROOT / locale / source).relative_to(ROOT))
            for page_set in chosen
            for locale in locales
            for source in page_set.sources
            if not (SOURCE_ROOT / locale / source).exists()
        ]
        if missing:
            sys.exit("missing captures:\n  " + "\n  ".join(missing))
        print(f"ok: {len(chosen)} sets x 3 slides x {len(locales)} locales")
        return

    rows: list[tuple[str, list[Path]]] = []
    total = 0
    for page_set in chosen:
        print(f"{page_set.name}: {page_set.intent}")
        for locale in locales:
            if locale not in page_set.copy:
                sys.exit(f"{page_set.name}: no copy for locale {locale}")
            rendered = render_set(page_set, locale, quiet=args.drafts)
            total += len(rendered)
            if args.drafts:
                rows.append((f"{page_set.name} {locale}", rendered))

    if args.drafts and rows:
        sheet = OUTPUT_ROOT / "contact-sheet-all-sets.png"
        contact_sheet(rows, sheet, thumb_size=(260, 566))
        print(f"\nCompare: {sheet.relative_to(ROOT)}")
    print(f"{total} screenshots in {OUTPUT_ROOT.relative_to(ROOT)}/  at {CANVAS[0]}x{CANVAS[1]}")


if __name__ == "__main__":
    main()
