#!/usr/bin/env python3
"""Turn native iPhone screenshots into the two renditions the project needs.

Source captures are 1125 x 2436 (the 5.8" iPhone size). Two consumers:

  App Store  `Docs/images/raw/` holds the bare captures at exactly
             1320 x 2868. 1125 -> 1320 is a 1.17x upscale landing at
             1320 x 2858, so the remaining 10px is padded with black — the
             app's screens are black at the top and bottom edges, so the
             padding is invisible. `tools/generate_app_store_product_screenshots.py`
             turns these into the marketing renders in `Docs/images/<locale>/`
             that `tools/prepare_app_store_upload_bundle.py` uploads.

  Website    `assets/img/screens/` in the alikeapp/alikeapp.github.io repository
             renders in ~260px frames, so a 520px wide copy covers 2x with room
             to spare and keeps the page light. Skipped when that checkout is
             not next to this one.

Languages beyond en and uk come from an optional
`Docs/images/raw/capture-manifest.json`, which maps each locale's shot numbers
to the camera-roll filenames of that capture session:

    {
      "de": {"1": "IMG_4101.PNG", "3": "IMG_4102.PNG"},
      "fr": {"1": "IMG_4110.PNG", "3": "IMG_4111.PNG"}
    }

It merges over the table below, so a manifest naming only de leaves en and uk
untouched. Captures already at 1320 x 2868 — the iPhone 17 Pro Max simulator
produces that natively — need no conversion and can be dropped straight into
`Docs/images/raw/<locale>/`, skipping this script entirely.

Usage:
    python3 tools/import_device_screenshots.py --source ~/Downloads
    python3 tools/import_device_screenshots.py --source ~/Downloads \
        --site-repo ../alikeapp.github.io
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
SITE_WIDTH = 520

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

# `en` is the only language whose directory name differs from its own code, for
# the same reason Docs/images/en-US/ is spelled that way: the App Store locale
# is en-US. Everything else — uk, de, fr, es, es-419, pt-BR — is verbatim.
LANGUAGE_DIRECTORIES = {"en": "en-US"}

# Which shots the landing page shows, matching _data/screens.yml in the site repo.
SITE_SHOTS = [1, 3, 4, 5, 7]


def languages_of(spec: dict[str, str]) -> list[str]:
    """Every language key in a shot spec, in a stable order. "name" is not one."""
    return sorted(key for key in spec if key != "name")


def load_shots(manifest_path: Path) -> dict[int, dict[str, str]]:
    """SHOTS, with any capture manifest merged over it."""
    shots = {shot: dict(spec) for shot, spec in SHOTS.items()}
    if not manifest_path.exists():
        return shots

    manifest = json.loads(manifest_path.read_text())
    for locale, entries in manifest.items():
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
    ap.add_argument(
        "--site-repo",
        default="../alikeapp.github.io",
        help="checkout of alikeapp/alikeapp.github.io; website renders are skipped when it is absent",
    )
    args = ap.parse_args()

    source = Path(args.source).expanduser()
    repo = Path(args.repo).resolve()
    store_dir = repo / "Docs" / "images" / "raw"

    # The site lives in its own repository now, so its image directory is not
    # ours to create — an unconditional mkdir would quietly produce a dead
    # folder here and the renders would never reach the published page. Write
    # only into a checkout that already exists, and say so when there isn't one.
    site_root = Path(args.site_repo).expanduser()
    site_dir = (site_root / "assets" / "img" / "screens").resolve() if site_root.is_dir() else None

    store_dir.mkdir(parents=True, exist_ok=True)
    if site_dir is not None:
        site_dir.mkdir(parents=True, exist_ok=True)

    shots = load_shots(store_dir / MANIFEST_NAME)

    missing = []
    for shot, spec in shots.items():
        for lang in languages_of(spec):
            if not (source / spec[lang]).exists():
                missing.append(f"shot {shot} {lang}: {spec[lang]}")
    if missing:
        print("Missing source files:", *missing, sep="\n  ", file=sys.stderr)
        raise SystemExit(66)

    store_count = site_count = 0
    for shot in sorted(shots):
        spec = shots[shot]
        for lang in languages_of(spec):
            src = source / spec[lang]
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

            # Website: only the shots the page actually frames, English only —
            # the site swaps language by text, not by screenshot.
            if site_dir is not None and shot in SITE_SHOTS and lang == "en":
                site_target = site_dir / f"{spec['name']}.png"
                shutil.copy2(src, site_target)
                run("sips", "--resampleWidth", str(SITE_WIDTH), str(site_target), "--out", str(site_target))
                site_count += 1

        print(f"  shot {shot:2d}  {spec['name']}")

    print(f"\nApp Store: {store_count} files in {store_dir.relative_to(repo)}/  at "
          f"{APP_STORE_SIZE[0]}x{APP_STORE_SIZE[1]}")
    if site_dir is None:
        print(f"Website:   skipped — no checkout at {args.site_repo}; "
              f"pass --site-repo <path to alikeapp.github.io> to render the page images")
    else:
        print(f"Website:   {site_count} files in {site_dir}/  at {SITE_WIDTH}px wide")


if __name__ == "__main__":
    main()
