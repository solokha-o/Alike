# Alike App Store Screenshot Workflow

## Source Basis

The product philosophy is the same one used on GeoBuzz, itself adapted from the
public `ParthJadhav/app-store-screenshots` skill: screenshots sell outcomes, one
idea per slide, headlines dominate, layout varies, and exports must pass a
clipped-text and thumbnail check.

The implementation is deliberately a deterministic Pillow script rather than an
interactive editor. The deck is five slides in seven locales, all driven by one
`COPY` table; a Next.js editor would be more machinery than the job needs. Reach
for one only if the user asks for manual iteration, multi-device export, or many
more locales.

## Pipeline

```
physical iPhone capture (1125 x 2436)
  → tools/import_device_screenshots.py      → Docs/images/raw/<locale>/  (1320 x 2868)
  → tools/generate_app_store_product_screenshots.py
                                            → Docs/images/<locale>/      (1320 x 2868)
  → tools/prepare_app_store_upload_bundle.py
                                            → build/generated/store_upload/screenshots/<apple locale>/
  → fastlane deliver
```

`numbered_pngs()` in the bundle script only picks up `*.png` whose name starts
with two digits and which sit directly in the locale folder. That is why
`Docs/images/raw/` and `Docs/images/review/` are invisible to it, and why slide
filenames keep the capture's numeric prefix.

## Draft Loop

```sh
build/tools-venv/bin/python tools/generate_app_store_product_screenshots.py --drafts
open build/generated/product_screenshot_drafts/contact-sheet-all-variants.png
```

Four background variants, one product concept:

| Variant | Direction |
| --- | --- |
| `glass-bands` | Tilted translucent bands and outline rings; the busiest. |
| `spotlight` | One soft glow behind the device, everything else black; ships on the listing. |
| `blocks` | A tinted block anchoring the caption half, phone crossing its edge. |
| `stack` | Dot grid plus three offset photo cards — the "similar photos" motif. |

Then render the chosen one:

```sh
build/tools-venv/bin/python tools/generate_app_store_product_screenshots.py --variant spotlight
python3 tools/prepare_app_store_upload_bundle.py --allow-placeholder-urls
```

Verify the sizes:

```sh
build/tools-venv/bin/python -c "from pathlib import Path; from PIL import Image; files=[p for p in Path('Docs/images').glob('*/[0-9][0-9]*.png')]; print(len(files), [str(p) for p in files if Image.open(p).size!=(1320,2868)])"
```

## Slide Deck

| # | Capture | Angle |
| --- | --- | --- |
| 1 | `01-scanner-idle` | On-device scan — the core promise |
| 2 | `03-cleanup-queue` | One queue with review badges |
| 3 | `04-cluster-details` | Best Shot already chosen |
| 4 | `05-comparison-review` | Nothing goes without confirmation |
| 5 | `07-cleanup-progress` | Selected photos and estimated savings |

## Layout Notes

- The captures put their UI in the top third to half of the screen and leave the
  rest black. Slides therefore either bleed the phone off the bottom edge or show
  a smaller whole device — never a full-height phone with a dead lower half in
  the middle of the canvas.
- `composite_clipped()` exists because `Image.alpha_composite` rejects negative
  offsets, and the bleeding layouts place the device off-canvas on purpose.
- `cover_crop()` trims from the bottom, not the centre, so the status bar and
  navigation title always survive.
- `fit_font_size()` shrinks the headline until it fits the caption box. Ukrainian
  usually lands one step smaller than English; that is expected, not a bug.

## QA Checklist

- Store PNGs are `1320 x 2868` and keep zero-padded numeric prefixes.
- Headline readable at `160px` width.
- No headline or subtitle crossing a ring, band, or block edge.
- Phone frame never covers meaningful UI; the capture is never stretched.
- The first slide communicates the core value in under a second.
- The captures come from a real photo library — check every frame for faces,
  location clues, and readable personal data before uploading.
