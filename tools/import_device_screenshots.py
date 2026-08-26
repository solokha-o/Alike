#!/usr/bin/env python3
"""Turn native iPhone screenshots into the capture store every deck is built from.

Source captures are 1125 x 2436 (the 5.8" iPhone size).

  App Store  `Docs/images/raw/` holds the bare captures at exactly
             1320 x 2868. 1125 -> 1320 is a 1.17x upscale landing at
             1320 x 2858, so the remaining 10px is padded with black — the
             app's screens are black at the top and bottom edges, so the
             padding is invisible. `tools/generate_app_store_product_screenshots.py`
             turns these into the marketing renders in `Docs/images/<locale>/`
             that `tools/prepare_app_store_upload_bundle.py` uploads.

The landing page's frames are built from that raw store rather than from
`--source`, by `tools/build_site_screenshots.py`, so re-rendering the site does
not need the camera roll of a capture session from months ago.

Languages beyond en and uk come from an optional
`Docs/images/raw/capture-manifest.json`, which maps each locale's shot numbers
to the camera-roll filenames of that capture session:

    {
      "de": {"1": "IMG_4101.PNG", "3": "IMG_4102.PNG"},
      "fr": {"1": "IMG_4110.PNG", "3": "IMG_4111.PNG"}
    }

It merges over the table below, so a manifest naming only de leaves en and uk
untouched. Its locale keys must be the app's own source codes — `es-419`, not
App Store Connect's `es-MX` — and anything else is rejected rather than imported
into a directory the renderer never reads. Captures already at 1320 x 2868 — the iPhone 17 Pro Max simulator
produces that natively — need no conversion and can be dropped straight into
`Docs/images/raw/<locale>/`, skipping this script entirely.

Usage:
    python3 tools/import_device_screenshots.py --source ~/Downloads
    python3 tools/import_device_screenshots.py --source ~/Downloads --locales ar
"""
from __future__ import annotations

import argparse
import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path

SOURCE_SIZE = (1125, 2436)
APP_STORE_SIZE = (1320, 2868)

# shot number -> {lang: source filename}
# Shot numbers refer to the table in Docs/screenshot-shot-list.md.
SHOTS = {
    1:  {"name": "scanner-idle",       "en": "IMG_3237.PNG", "uk": "IMG_3246.PNG"},
    2:  {"name": "scanner-scanning",   "en": "IMG_3238.PNG", "uk": "IMG_3247.PNG"},
    3:  {"name": "cleanup-queue",      "en": "IMG_3239.PNG", "uk": "IMG_3248.PNG"},
    4:  {"name": "cluster-details",    "en": "IMG_3257.PNG", "uk": "IMG_3249.PNG"},
    5:  {"name": "comparison-review",  "en": "IMG_3256.PNG", "uk": "IMG_3250.PNG"},
    6:  {"name": "cleanup-confirm",    "en": "IMG_3241.PNG"},
    7:  {"name": "cleanup-progress",   "en": "IMG_3242.PNG", "uk": "IMG_3251.PNG"},
    8:  {"name": "screenshot-cleanup", "en": "IMG_3243.PNG"},
    13: {"name": "welcome-privacy",    "en": "IMG_3236.PNG", "uk": "IMG_3245.PNG"},
}

# Camera-roll filenames are not something a table in this file can predict for a
# capture session that has not happened yet, so the languages beyond en and uk
# come from an optional manifest instead of another hardcoded column. It is a
# locale -> {shot number: filename} map, and it merges into SHOTS rather than
# replacing it, so a manifest holding only de leaves en and uk exactly as they
# are. Absent manifest, this script behaves as it always did.
MANIFEST_NAME = "capture-manifest.json"

# The locale keys a manifest may use. These are the app's own source codes, the
# only ones tools/generate_app_store_product_screenshots.py iterates, so a key
# outside this set would import captures into a directory the renderer never
# reads: the import would succeed and the deck would silently ship without them.
# App Store Connect codes are the likely typo, hence the suggestions.
SUPPORTED_LOCALES = (
    "en", "uk", "de", "fr", "es", "es-419", "pt-BR", "it", "nl", "pl", "tr", "zh-Hant", "ar",
)
LOCALE_SUGGESTIONS = {
    "es-MX": "es-419",
    "en-US": "en",
    "pt": "pt-BR",
    "pt-PT": "pt-BR",
    # Traditional Chinese is the code nobody guesses right the first time: the
    # app spells it zh-Hant, iOS reports zh-Hant-TW, and the store calls the
    # locale zh-Hant too. zh-Hans is a different language and has no deck.
    "zh": "zh-Hant",
    "zh-TW": "zh-Hant",
    "zh-Hant-TW": "zh-Hant",
    # Arabic has one deck. The App Store locale is ar-SA, and a device set to any
    # Arabic region reports its own; all of them import into the same directory.
    "ar-SA": "ar",
    "ar-AE": "ar",
    "ar-EG": "ar",
    "it-IT": "it",
    "nl-NL": "nl",
    "pl-PL": "pl",
    "tr-TR": "tr",
}

# `en` is the only language whose directory name differs from its own code, for
# the same reason Docs/images/en-US/ is spelled that way: the App Store locale
# is en-US. Everything else — uk, de, fr, es, es-419, pt-BR, it, nl, pl, tr and
# zh-Hant — is verbatim.
LANGUAGE_DIRECTORIES = {"en": "en-US"}

def languages_of(spec: dict[str, str], only: set[str] | None = None) -> list[str]:
    """Every language key in a shot spec, in a stable order. "name" is not one."""
    languages = sorted(key for key in spec if key != "name")
    return [language for language in languages if only is None or language in only]


def confined_source_path(source: Path, filename: str, manifest_path: Path) -> Path:
    """Resolve one manifest filename inside --source, refusing anything that escapes it.

    Manifest entries are filenames a human types next to a locale, and they were
    fed straight to `source / name`. `/` makes that an absolute path, `../`
    walks out of the capture folder, and a symlink inside --source reaches
    anywhere the filesystem does — after which any PNG the walk lands on is
    copied into Docs/images/raw/ under a locale's name and, from there, into a
    published deck. The manifest is a local file, so this is a foot-gun rather
    than an attack, but the blast radius is committed image content.

    Only a plain relative name is accepted, and the resolved path has to stay
    under the resolved --source, which is what catches the symlink case that
    the string checks alone cannot see.
    """
    candidate = Path(filename)
    if candidate.is_absolute() or candidate.drive or candidate.anchor:
        raise SystemExit(f"{manifest_path}: {filename!r} is an absolute path; use a name inside --source")
    if ".." in candidate.parts:
        raise SystemExit(f"{manifest_path}: {filename!r} walks out of --source with '..'")

    root = source.resolve()
    resolved = (root / candidate).resolve()
    if resolved != root and root not in resolved.parents:
        raise SystemExit(
            f"{manifest_path}: {filename!r} resolves to {resolved}, outside --source {root} "
            f"(a symlink in the capture folder will do this)"
        )
    return resolved


def load_shots(manifest_path: Path) -> dict[int, dict[str, str]]:
    """SHOTS, with any capture manifest merged over it."""
    shots = {shot: dict(spec) for shot, spec in SHOTS.items()}
    if not manifest_path.exists():
        return shots

    manifest = json.loads(manifest_path.read_text())
    for locale, entries in manifest.items():
        if locale not in SUPPORTED_LOCALES:
            suggestion = LOCALE_SUGGESTIONS.get(locale)
            hint = f" Did you mean {suggestion}?" if suggestion else ""
            raise SystemExit(
                f"{manifest_path}: {locale} is not a source locale, so its captures would "
                f"never reach a deck.{hint} Supported locales are "
                f"{', '.join(SUPPORTED_LOCALES)}"
            )
        for shot_key, filename in entries.items():
            shot = int(shot_key)
            if shot not in shots:
                raise SystemExit(
                    f"{manifest_path}: shot {shot} for {locale} is not in the shot list; "
                    f"known shots are {', '.join(str(number) for number in sorted(shots))}"
                )
            shots[shot][locale] = filename
    return shots


def png_size(path: Path) -> tuple[int, int]:
    header = path.open("rb").read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", header[16:24])


def run(*args: str) -> None:
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", default="~/Downloads", help="folder holding the IMG_*.PNG captures")
    ap.add_argument("--repo", default=".", help="repository root")
    # A capture session covers one locale, and the camera roll it came from holds
    # that locale's shots only. Without this the run resolves every language in
    # SHOTS plus the manifest and stops on the ones whose files were imported
    # sessions ago and long since deleted — which made adding a thirteenth
    # language impossible through the tool that exists to add languages.
    ap.add_argument(
        "--locales",
        help="comma-separated source locales to import; default is every locale in the table",
    )
    args = ap.parse_args()

    only = None
    if args.locales:
        only = {code.strip() for code in args.locales.split(",") if code.strip()}
        unknown = sorted(only - set(SUPPORTED_LOCALES))
        if unknown:
            raise SystemExit(
                f"--locales: {', '.join(unknown)} is not a source locale. "
                f"Known: {', '.join(SUPPORTED_LOCALES)}"
            )

    source = Path(args.source).expanduser()
    repo = Path(args.repo).resolve()
    store_dir = repo / "Docs" / "images" / "raw"

    store_dir.mkdir(parents=True, exist_ok=True)

    shots = load_shots(store_dir / MANIFEST_NAME)

    # Resolve every manifest filename before anything is read or copied, so a
    # path that escapes --source stops the run rather than being caught halfway
    # through writing decks.
    manifest_path = store_dir / MANIFEST_NAME
    resolved_sources: dict[tuple[int, str], Path] = {}
    missing = []
    for shot, spec in shots.items():
        for lang in languages_of(spec, only):
            resolved = confined_source_path(source, spec[lang], manifest_path)
            resolved_sources[(shot, lang)] = resolved
            if not resolved.exists():
                missing.append(f"shot {shot} {lang}: {spec[lang]}")
    if missing:
        print("Missing source files:", *missing, sep="\n  ", file=sys.stderr)
        raise SystemExit(66)

    store_count = 0
    for shot in sorted(shots):
        spec = shots[shot]
        for lang in languages_of(spec, only):
            src = resolved_sources[(shot, lang)]
            size = png_size(src)
            if size != SOURCE_SIZE:
                print(f"  !! {src.name} is {size[0]}x{size[1]}, expected {SOURCE_SIZE[0]}x{SOURCE_SIZE[1]}")
                continue

            # App Store: numbered so the product generator (and in turn
            # `numbered_pngs()`) picks it up, per locale.
            locale_dir = LANGUAGE_DIRECTORIES.get(lang, lang)
            target = store_dir / locale_dir / f"{shot:02d}-{spec['name']}.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            tmp = target.with_suffix(".tmp.png")
            shutil.copy2(src, tmp)
            run("sips", "--resampleWidth", str(APP_STORE_SIZE[0]), str(tmp), "--out", str(tmp))
            run("sips", "-p", str(APP_STORE_SIZE[1]), str(APP_STORE_SIZE[0]),
                "--padColor", "000000", str(tmp), "--out", str(target))
            tmp.unlink()
            assert png_size(target) == APP_STORE_SIZE, f"{target} wrong size"
            store_count += 1

        print(f"  shot {shot:2d}  {spec['name']}")

    print(f"\nApp Store: {store_count} files in {store_dir.relative_to(repo)}/  at "
          f"{APP_STORE_SIZE[0]}x{APP_STORE_SIZE[1]}")
    print("Website:   run tools/build_site_screenshots.py --site-repo <path to alikeapp.github.io> "
          "to re-render the landing page's frames from these captures")


if __name__ == "__main__":
    main()
