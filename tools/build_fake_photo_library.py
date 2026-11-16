#!/usr/bin/env python3
"""Build the photo set of the DEBUG `store` fake library from a few base scenes.

  in   `tools/assets/fake-library/scene-*.jpg` — base scenes, generated images
       with no people, no text and no personal data (see the README there).
  out  `build/generated/fake-photo-library/`   — 4 photos per scene, like a
       burst, then 6 single photos for the Smart Cleanup categories.

The simulator cannot form clusters, so the `store` scenario groups the photos by
file order: `s01-1 … s01-4` is the first group. Every change is deterministic, so
a rerun gives the same files and the same screenshots.

    build/tools-venv/bin/python tools/build_fake_photo_library.py
    SIMCTL_CHILD_ALIKE_FAKE_LIBRARY_PHOTOS="$PWD/build/generated/fake-photo-library" \\
      xcrun simctl launch <udid> com.alike.app -AlikeFakeLibrary store
"""

from __future__ import annotations

import argparse
import shutil
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SCENES = ROOT / "tools" / "assets" / "fake-library"
OUTPUT = ROOT / "build" / "generated" / "fake-photo-library"
SIZE = (4032, 3024)
PHOTOS_PER_SERIES = 4
CATEGORY_PHOTOS = 6


@dataclass(frozen=True)
class Shot:
    """One photo of a series: how far the framing and the light move."""

    zoom: float
    shift: tuple[float, float]
    rotation: float
    brightness: float
    blur: float = 0.0


# A burst: the same scene a moment apart. The third shot is a little soft, so a
# Best Shot is plausible on sight.
SERIES = (
    Shot(zoom=1.00, shift=(0.00, 0.00), rotation=0.0, brightness=1.00),
    Shot(zoom=1.04, shift=(0.02, 0.01), rotation=0.6, brightness=1.03),
    Shot(zoom=1.06, shift=(-0.02, 0.02), rotation=-0.8, brightness=0.95, blur=1.6),
    Shot(zoom=1.03, shift=(0.03, -0.01), rotation=0.3, brightness=0.98),
)

CATEGORY = Shot(zoom=1.15, shift=(-0.04, 0.03), rotation=-1.2, brightness=0.9, blur=3.0)


def shot(scene: Image.Image, spec: Shot) -> Image.Image:
    """Crops, rotates and relights the scene, then scales it to `SIZE`."""
    image = scene.convert("RGB")
    if spec.rotation:
        image = image.rotate(spec.rotation, resample=Image.Resampling.BICUBIC, expand=False)
    width, height = image.size
    target_ratio = SIZE[0] / SIZE[1]
    crop_width = min(width, height * target_ratio) / spec.zoom
    crop_height = crop_width / target_ratio
    # Rotation leaves dark corners; the zoom and a minimum margin keep them out.
    margin = 0.03
    crop_width = min(crop_width, width * (1 - 2 * margin))
    crop_height = min(crop_height, height * (1 - 2 * margin))
    center_x = width / 2 + spec.shift[0] * width
    center_y = height / 2 + spec.shift[1] * height
    left = min(max(center_x - crop_width / 2, width * margin), width * (1 - margin) - crop_width)
    top = min(max(center_y - crop_height / 2, height * margin), height * (1 - margin) - crop_height)
    image = image.crop((round(left), round(top), round(left + crop_width), round(top + crop_height)))
    image = image.resize(SIZE, Image.Resampling.LANCZOS)
    image = ImageEnhance.Brightness(image).enhance(spec.brightness)
    if spec.blur:
        image = image.filter(ImageFilter.GaussianBlur(spec.blur))
    return image


def build(scenes_dir: Path, output: Path) -> list[Path]:
    scenes = sorted(scenes_dir.glob("scene-*.jpg"))
    if not scenes:
        raise SystemExit(f"No base scenes in {scenes_dir}")
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    written: list[Path] = []
    for series_index, scene_path in enumerate(scenes, start=1):
        with Image.open(scene_path) as scene:
            for shot_index, spec in enumerate(SERIES, start=1):
                path = output / f"s{series_index:02d}-{shot_index}.jpg"
                shot(scene, spec).save(path, quality=92, optimize=True)
                written.append(path)
    # Category photos sort after the series (`x` > `s`), so the `store` scenario
    # takes them as the last photos of the album.
    for index, scene_path in enumerate(scenes[:CATEGORY_PHOTOS], start=1):
        with Image.open(scene_path) as scene:
            path = output / f"x{index:02d}.jpg"
            shot(scene, CATEGORY).save(path, quality=92, optimize=True)
            written.append(path)
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scenes", type=Path, default=SCENES)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    written = build(args.scenes, args.output)
    print(f"{len(written)} photos in {args.output}")


if __name__ == "__main__":
    main()
