#!/usr/bin/env python3
"""Capture the raw iPad screens for the App Store slides from the DEBUG `store` library.

  in   a booted iPad simulator with a DEBUG build of Alike installed, and the photo
       set from `tools/build_fake_photo_library.py`.
  out  `Docs/images/ipad/raw/<locale>/<NN-name>.png` — full-screen captures at the
       simulator's native size, status bar fixed at 9:41.

The simulator cannot form clusters, so the app runs the `store` fake library
(`-AlikeFakeLibrary store`): 12 groups of photos, half reviewed, the rest in review.
The app's own deep links open each screen, passed at launch as
`-AlikeFakeOpenURL` so iPadOS shows no "Open in Alike?" prompt and no tap is needed:

  01-scanner-idle         launch (the finished scan: "Cleanup opportunities are ready")
  03-cleanup-queue        alike://cleanup
  05-comparison-review    alike://resume — the next group in review, 2 photos selected

`07-cleanup-progress` needs the delete button and its alert, so tap them by hand
and then run `--only 07-cleanup-progress --no-launch` for each locale; the `store`
cleanup never finishes, so the progress screen waits for the capture.

    build/tools-venv/bin/python tools/build_fake_photo_library.py
    build/tools-venv/bin/python tools/capture_ipad_store_screens.py --udid <ipad>
"""

from __future__ import annotations

import argparse
import os
import subprocess
import tempfile
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PHOTOS = ROOT / "build" / "generated" / "fake-photo-library"
OUTPUT = ROOT / "Docs" / "images" / "ipad" / "raw"
BUNDLE_ID = "com.alike.app"

# The generator's locale codes (directory names) → the app language and region.
LOCALES = {
    "en-US": ("en", "en_US"),
    "uk": ("uk", "uk_UA"),
    "de": ("de", "de_DE"),
    "fr": ("fr", "fr_FR"),
    "es": ("es", "es_ES"),
    "es-419": ("es-419", "es_MX"),
    "pt-BR": ("pt-BR", "pt_BR"),
    "it": ("it", "it_IT"),
    "nl": ("nl", "nl_NL"),
    "pl": ("pl", "pl_PL"),
    "tr": ("tr", "tr_TR"),
    "zh-Hant": ("zh-Hant", "zh_TW"),
    "ar": ("ar", "ar_SA"),
}

# Screen name → deep link opened after launch, or `None` for the launch screen.
SCREENS = {
    "01-scanner-idle": None,
    "03-cleanup-queue": "alike://cleanup",
    "05-comparison-review": "alike://resume",
}
MANUAL_SCREENS = ("07-cleanup-progress",)


def simctl(*args: str, env: dict[str, str] | None = None, check: bool = True) -> None:
    subprocess.run(["xcrun", "simctl", *args], check=check, env=env)


def prepare_device(udid: str) -> None:
    simctl("ui", udid, "appearance", "dark")
    simctl(
        "status_bar", udid, "override",
        "--time", "9:41",
        "--dataNetwork", "wifi",
        "--wifiMode", "active",
        "--wifiBars", "3",
        "--batteryState", "charged",
        "--batteryLevel", "100",
    )
    simctl("privacy", udid, "grant", "photos", BUNDLE_ID)


def launch(udid: str, locale: str, photos: Path, link: str | None) -> None:
    language, region = LOCALES[locale]
    simctl("terminate", udid, BUNDLE_ID, check=False)
    env = {
        **os.environ,
        "SIMCTL_CHILD_ALIKE_FAKE_LIBRARY_PHOTOS": str(photos),
    }
    simctl(
        "launch", udid, BUNDLE_ID,
        "-AlikeFakeLibrary", "store",
        "-AlikeFakePremium", "YES",
        "-AppleLanguages", f"({language})",
        "-AppleLocale", region,
        *(["-AlikeFakeOpenURL", link] if link else []),
        env=env,
    )


# The launch screen fills the window with the accent colour; the app's dark UI
# does not. Until its centre stops being this colour, the app is still loading.
LAUNCH_SCREEN_COLOUR = (31, 160, 185)


def is_launch_screen(path: Path) -> bool:
    with Image.open(path) as image:
        rgb = image.convert("RGB")
        pixel = rgb.getpixel((rgb.width // 2, rgb.height // 4))
    return all(abs(channel - target) < 40 for channel, target in zip(pixel, LAUNCH_SCREEN_COLOUR))


def wait_for_app(udid: str, timeout: float) -> None:
    """Waits until the launch screen is gone; the fake library loads behind it."""
    deadline = time.monotonic() + timeout
    with tempfile.TemporaryDirectory() as folder:
        probe = Path(folder) / "probe.png"
        while time.monotonic() < deadline:
            subprocess.run(
                ["xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(probe)],
                check=True,
                capture_output=True,
            )
            if not is_launch_screen(probe):
                return
            time.sleep(1)
    raise SystemExit(f"The app still shows its launch screen after {timeout:.0f} s")


def capture(udid: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(path)], check=True, capture_output=True)
    print(path.relative_to(ROOT))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--udid", required=True, help="Booted iPad simulator")
    parser.add_argument("--locales", default=",".join(LOCALES), help="Comma-separated generator locale codes")
    parser.add_argument("--only", help="Capture this one screen name")
    parser.add_argument("--no-launch", action="store_true", help="Capture the current screen as it is")
    parser.add_argument("--photos", type=Path, default=PHOTOS)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--settle", type=float, default=4.0, help="Seconds to wait after the app appears")
    parser.add_argument("--timeout", type=float, default=90.0, help="Seconds to wait for the app to load")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.photos = args.photos.resolve()

    locales = [code.strip() for code in args.locales.split(",") if code.strip()]
    unknown = [code for code in locales if code not in LOCALES]
    if unknown:
        raise SystemExit(f"Unknown locales: {', '.join(unknown)}")
    if len(list(args.photos.glob("*.jpg"))) < 54:
        raise SystemExit(f"Run tools/build_fake_photo_library.py first: {args.photos}")
    names = [args.only] if args.only else list(SCREENS)
    for name in names:
        if name not in SCREENS and name not in MANUAL_SCREENS:
            raise SystemExit(f"Unknown screen: {name}")

    prepare_device(args.udid)
    for locale in locales:
        if args.no_launch:
            for name in names:
                capture(args.udid, args.output / locale / f"{name}.png")
            continue
        for name in names:
            # One launch per screen: the link is a launch argument.
            launch(args.udid, locale, args.photos, SCREENS.get(name))
            time.sleep(2)
            wait_for_app(args.udid, args.timeout)
            # Thumbnails, the pushed screen and entry animations finish here.
            time.sleep(args.settle)
            capture(args.udid, args.output / locale / f"{name}.png")


if __name__ == "__main__":
    main()
