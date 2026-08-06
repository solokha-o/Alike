---
name: app-store-screenshots
description: Create or revise Alike App Store product screenshots, marketing screenshot copy, background variants, phone-mockup renders, or the screenshot export workflow that feeds the upload bundle.
---

# App Store Screenshots

Use this skill when the request touches App Store screenshots, product or
marketing screenshots, screenshot headlines, iPhone mockups, or the generator
that renders them.

## Core Rule

Screenshots are advertisements, not UI documentation. Each slide sells one
outcome. Keep the captured UI real and dense inside the phone, and keep the
canvas around the phone sparse.

## Alike Defaults

- Captures: `Docs/images/raw/<locale>/`, written by `tools/import_device_screenshots.py`.
- Listing renders: `Docs/images/<locale>/`, read by `tools/prepare_app_store_upload_bundle.py`.
- Generator: `tools/generate_app_store_product_screenshots.py`.
- Drafts and contact sheets: `build/generated/product_screenshot_drafts/`, `build/generated/product_screenshots/`.
- Phone mockup: `tools/assets/iphone-mockup.png` (1022 x 2082, screen rect 52,46,970,2036).
- Canvas: `1320 x 2868` exactly — the bundle rejects anything else.
- Locales: `en-US` and `uk`; the bundle maps `en-GB` onto the `en-US` files.
- Runtime: `build/tools-venv/bin/python` — Pillow is not in the system Python.

```sh
python3 -m venv build/tools-venv && build/tools-venv/bin/pip install --upgrade pip Pillow
build/tools-venv/bin/python tools/generate_app_store_product_screenshots.py --drafts
build/tools-venv/bin/python tools/generate_app_store_product_screenshots.py --variant spotlight
```

## Workflow

1. Read `Skills/DesignConcept/SKILL.md` for the app's visual constraints.
2. Read `references/alike-screenshot-workflow.md` before generating or reviewing.
3. Look at the captures and the current renders before writing copy or layout code.
4. Change `SLIDES`/`COPY` in the generator, never the PNGs by hand.
5. Render drafts, inspect the contact sheet, then render the chosen variant into
   `Docs/images/`.
6. Re-run `python3 tools/prepare_app_store_upload_bundle.py --allow-placeholder-urls`
   so the upload bundle picks the new files up.

## Product Order

Lead with the scan (what the app does), then the review queue, then Best Shot,
then the safety of confirming before deleting, then the space that comes back.
Do not lead with the paywall, onboarding, or settings.

## Copy Rules

- One idea per headline; short enough to read at thumbnail size.
- Benefit first, implementation second. "Find the photos that look alike", not
  "Vision-based perceptual hashing".
- Line breaks in the headline are deliberate; the generator only rewraps when the
  line does not fit.
- Ukrainian runs longer than English — check both, never only `en-US`.
- Privacy is a selling point: on-device, no account, nothing deleted without
  confirmation.

## Visual Rules

- Dark canvas, because the app's UI is dark: gradient `(11,11,13) → (22,24,28)`.
- Palette is the app's own: teal `(90,180,204)`, mascot purple `(138,107,209)`,
  green `(48,209,88)` for freed space. No colour outside these.
- SF Pro only, via the variable `SFNS.ttf` named instances (Bold, Medium).
- Alternate composition: caption on top with the phone bleeding off the bottom,
  caption at the bottom with a whole device above. Never five identical slides.
- Decorations stay out of `SlideLayout.caption_zone`.
- A dark drop shadow is invisible here; the device separates from the canvas with
  an accent-tinted halo.
- Translucent fills must go through a layer and `alpha_composite`. `ImageDraw`
  writes ink alpha into the target instead of blending it, so drawing a 10%
  fill straight onto the canvas comes back opaque after the RGB flatten.

## Validation

- Every PNG in `Docs/images/<locale>/` is exactly `1320 x 2868`.
- Filenames keep their two-digit prefix, or `numbered_pngs()` skips them.
- Open the contact sheets: no clipped text, no frame over meaningful UI, no
  stretched capture, no two adjacent slides with the same composition.
- Thumbnail test at ~160px wide: the headline still reads.
- The captures are a real photo library — re-check every frame for faces,
  location clues, and legible personal data before an upload.

## Related Skills

- `Skills/DesignConcept/SKILL.md`
- `Skills/SwiftConcurrency/app-store-changelog/SKILL.md`
- `Skills/Localization/spm-localization/SKILL.md`
