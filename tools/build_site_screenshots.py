#!/usr/bin/env python3
"""Render the landing page's device frames from the committed captures, per locale.

`tools/import_device_screenshots.py` fills `Docs/images/raw/<locale>/` with bare
1320 x 2868 captures. This script turns the five shots the landing page frames
into the renditions `alikeapp/alikeapp.github.io` serves:

    Docs/images/raw/<locale>/0N-<name>.png  ->  assets/img/screens/<lang>/<name>.avif
                                            ->  assets/img/screens/<lang>/<name>.jpg

The site used to show the English captures in every language, because the frames
were keyed by shot alone. They are keyed by locale now — the same contract the
site already uses for `assets/img/og/<lang>.jpg` and the App Store badge — so an
Arabic reader sees the Arabic build, right to left, rather than an English one.

Two formats, both per locale, following tools/build_site_assets.sh: AVIF at
520px — 2x the ~260px the frames render at — and a 1x JPEG the `<picture>` falls
back to on browsers without AVIF. `<picture>` downloads exactly one of them, so
the fallback is served only to that minority and does not need to be retina.

A locale-matched fallback is the point. A shared English one would put those
browsers back on the English screens for every other language, which is the bug
this pipeline exists to fix, and it would be invisible to anyone testing in a
browser that does have AVIF. PNG is what makes the matrix unaffordable — twelve
locales of it is ~17MB in a repository whose whole history is 5MB. AVIF plus 1x
JPEG is ~5MB, and a visitor downloads ~200KB of it.

The locale list is read from the site's own `_config.yml`, so a language added
there without captures fails this run instead of shipping a broken <img>. The
one spelling that differs is English: the App Store locale is en-US and the
capture directory is named for it, while the site's lang — its `_data/` filename
and its `<html lang>` — is plain en.

Usage:
    python3 tools/build_site_screenshots.py --site-repo ../alikeapp.github.io
    python3 tools/build_site_screenshots.py --site-repo ../alikeapp.github.io \\
        --locales ar,uk
"""
from __future__ import annotations

import argparse
import re
import struct
import subprocess
import sys
from pathlib import Path

CAPTURE_SIZE = (1320, 2868)

# The frames render at roughly 260px wide, so 520 covers 2x displays exactly.
SITE_WIDTH = 520

# The fallback is 1x, and JPEG rather than PNG: at 330px it is ~55KB against
# ~190KB, which is the difference between a fallback set that fits in this
# repository twelve times over and one that does not.
FALLBACK_WIDTH = 330
FALLBACK_QUALITY = 80

# sips' AVIF quality. 70 holds the app's UI text crisp at 520px and lands each
# shot between 25KB and 60KB; the same pixels as PNG are 130KB to 470KB.
AVIF_QUALITY = 70

# Which shots the landing page frames, matching _data/screens.yml in the site
# repository. Names come from the capture filenames, not a second table here.
SITE_SHOTS = (1, 3, 4, 5, 7)

# site lang -> capture directory. Only English differs, for the same reason
# Docs/images/en-US/ is spelled that way: the App Store locale is en-US.
CAPTURE_DIRECTORIES = {"en": "en-US"}


def site_languages(site_root: Path) -> list[str]:
    """The site's own `languages:` list, read from its _config.yml.

    Duplicating it here would let the two drift silently, and the failure mode
    of drift is a locale whose frames 404 on a published page.
    """
    config = site_root / "_config.yml"
    if not config.is_file():
        raise SystemExit(f"{config} not found; --site-repo must point at a checkout of alikeapp.github.io")

    match = re.search(r"^languages:\s*\[([^\]]*)\]", config.read_text(), re.MULTILINE)
    if match is None:
        raise SystemExit(f"{config}: no inline `languages: [...]` list to read the locale set from")

    languages = [code.strip().strip("\"'") for code in match.group(1).split(",")]
    return [code for code in languages if code]


def png_size(path: Path) -> tuple[int, int]:
    header = path.open("rb").read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", header[16:24])


def run(*args: str) -> None:
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def capture_for(capture_dir: Path, shot: int) -> Path:
    """The one `0N-<name>.png` capture for a shot, or a hard stop."""
    matches = sorted(capture_dir.glob(f"{shot:02d}-*.png"))
    if not matches:
        raise SystemExit(
            f"{capture_dir}/ has no capture for shot {shot}. Import it first:\n"
            f"  python3 tools/import_device_screenshots.py --source ~/Downloads "
            f"--locales <locale>"
        )
    if len(matches) > 1:
        raise SystemExit(f"{capture_dir}/ has {len(matches)} captures for shot {shot}: "
                         f"{', '.join(path.name for path in matches)}")
    return matches[0]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=".", help="repository root")
    ap.add_argument(
        "--site-repo",
        default="../alikeapp.github.io",
        help="checkout of alikeapp/alikeapp.github.io",
    )
    ap.add_argument(
        "--locales",
        help="comma-separated site langs to rebuild; default is every language the site publishes",
    )
    args = ap.parse_args()

    if not sys.platform.startswith("darwin"):
        raise SystemExit("sips is required to write AVIF, so this runs on macOS only")

    repo = Path(args.repo).resolve()
    store_dir = repo / "Docs" / "images" / "raw"
    if not store_dir.is_dir():
        raise SystemExit(f"{store_dir} not found; run from the repository root or pass --repo")

    site_root = Path(args.site_repo).expanduser().resolve()
    languages = site_languages(site_root)

    if args.locales:
        only = {code.strip() for code in args.locales.split(",") if code.strip()}
        unknown = sorted(only - set(languages))
        if unknown:
            raise SystemExit(
                f"--locales: {', '.join(unknown)} is not a site language. "
                f"Known: {', '.join(languages)}"
            )
        languages = [code for code in languages if code in only]

    screens_dir = site_root / "assets" / "img" / "screens"

    # Resolve every capture before writing anything, so a locale captured only
    # halfway stops the run instead of leaving the site with three of its five
    # frames in the new language and two in the old.
    captures: dict[tuple[str, int], Path] = {}
    for lang in languages:
        capture_dir = store_dir / CAPTURE_DIRECTORIES.get(lang, lang)
        if not capture_dir.is_dir():
            raise SystemExit(
                f"{capture_dir}/ not found, but the site publishes {lang}. Capture that "
                f"locale and import it before building the page images."
            )
        for shot in SITE_SHOTS:
            captures[(lang, shot)] = capture_for(capture_dir, shot)

    scratch = screens_dir / "scratch.png"
    written = 0
    for lang in languages:
        out_dir = screens_dir / lang
        out_dir.mkdir(parents=True, exist_ok=True)
        sizes = []
        for shot in SITE_SHOTS:
            source = captures[(lang, shot)]
            size = png_size(source)
            if size != CAPTURE_SIZE:
                raise SystemExit(
                    f"{source} is {size[0]}x{size[1]}, expected {CAPTURE_SIZE[0]}x{CAPTURE_SIZE[1]}; "
                    f"run it through tools/import_device_screenshots.py first"
                )

            name = source.stem.split("-", 1)[1]

            run("sips", "--resampleWidth", str(SITE_WIDTH), str(source), "--out", str(scratch))
            avif = out_dir / f"{name}.avif"
            run("sips", "-s", "format", "avif", "-s", "formatOptions", str(AVIF_QUALITY),
                str(scratch), "--out", str(avif))

            run("sips", "--resampleWidth", str(FALLBACK_WIDTH), str(source), "--out", str(scratch))
            jpeg = out_dir / f"{name}.jpg"
            run("sips", "-s", "format", "jpeg", "-s", "formatOptions", str(FALLBACK_QUALITY),
                str(scratch), "--out", str(jpeg))

            sizes.append(avif.stat().st_size + jpeg.stat().st_size)
            written += 2

        print(f"  {lang:<8} {len(SITE_SHOTS)} shots  {sum(sizes) / 1024:5.0f}KB avif + jpeg")

    scratch.unlink(missing_ok=True)
    print(f"\n{written} files in {screens_dir}/  at {SITE_WIDTH}px (avif) and {FALLBACK_WIDTH}px (jpeg)")
    print("Commit them in the site repository; _data/screens.yml keys the captions by the same langs.")


if __name__ == "__main__":
    main()
