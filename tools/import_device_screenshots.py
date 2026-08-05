#!/usr/bin/env python3
"""Turn native iPhone screenshots into the two renditions the project needs.

Source captures are 1125 x 2436 (the 5.8" iPhone size). Two consumers:

  App Store  `Docs/images/` must be exactly 1320 x 2868, which
             `tools/prepare_app_store_upload_bundle.py` enforces. 1125 -> 1320
             is a 1.17x upscale landing at 1320 x 2858, so the remaining 10px
             is padded with black — the app's screens are black at the top and
             bottom edges, so the padding is invisible.

  Website    `site/assets/img/screens/` renders in ~260px frames, so a 520px
             wide copy covers 2x with room to spare and keeps the page light.

Usage:
    python3 tools/import_device_screenshots.py --source ~/Downloads
"""
from __future__ import annotations

import argparse
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
    4:  {"name": "cluster-details",    "en": "IMG_3240.PNG", "uk": "IMG_3249.PNG"},
    5:  {"name": "comparison-review",  "en": "IMG_3244.PNG", "uk": "IMG_3250.PNG"},
    6:  {"name": "cleanup-confirm",    "en": "IMG_3241.PNG"},
    7:  {"name": "cleanup-progress",   "en": "IMG_3242.PNG", "uk": "IMG_3251.PNG"},
    8:  {"name": "screenshot-cleanup", "en": "IMG_3243.PNG"},
    13: {"name": "welcome-privacy",    "en": "IMG_3236.PNG", "uk": "IMG_3245.PNG"},
}

# Which shots the landing page shows, matching site/_data/screens.yml.
SITE_SHOTS = [1, 3, 4, 5, 7]


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
    args = ap.parse_args()

    source = Path(args.source).expanduser()
    repo = Path(args.repo).resolve()
    store_dir = repo / "Docs" / "images"
    site_dir = repo / "site" / "assets" / "img" / "screens"

    store_dir.mkdir(parents=True, exist_ok=True)
    site_dir.mkdir(parents=True, exist_ok=True)

    missing = []
    for shot, spec in SHOTS.items():
        for lang in ("en", "uk"):
            if lang in spec and not (source / spec[lang]).exists():
                missing.append(f"shot {shot} {lang}: {spec[lang]}")
    if missing:
        print("Missing source files:", *missing, sep="\n  ", file=sys.stderr)
        raise SystemExit(66)

    store_count = site_count = 0
    for shot in sorted(SHOTS):
        spec = SHOTS[shot]
        for lang in ("en", "uk"):
            if lang not in spec:
                continue
            src = source / spec[lang]
            size = png_size(src)
            if size != SOURCE_SIZE:
                print(f"  !! {src.name} is {size[0]}x{size[1]}, expected {SOURCE_SIZE[0]}x{SOURCE_SIZE[1]}")
                continue

            # App Store: numbered so `numbered_pngs()` picks it up, per locale.
            locale_dir = "en-US" if lang == "en" else lang
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
            if shot in SITE_SHOTS and lang == "en":
                site_target = site_dir / f"{spec['name']}.png"
                shutil.copy2(src, site_target)
                run("sips", "--resampleWidth", str(SITE_WIDTH), str(site_target), "--out", str(site_target))
                site_count += 1

        print(f"  shot {shot:2d}  {spec['name']}")

    print(f"\nApp Store: {store_count} files in {store_dir.relative_to(repo)}/  at "
          f"{APP_STORE_SIZE[0]}x{APP_STORE_SIZE[1]}")
    print(f"Website:   {site_count} files in {site_dir.relative_to(repo)}/  at {SITE_WIDTH}px wide")


if __name__ == "__main__":
    main()
