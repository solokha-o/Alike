# Alike Screenshot Shot List

Nine of the thirteen shots are captured, in English and Ukrainian, from a
physical iPhone at 1125 x 2436. `tools/import_device_screenshots.py` upscales
them to the required 1320 x 2868 and pads the 10px remainder with black (the
app's screens are black at both edges, so the padding is invisible), and emits
520px copies for the landing-page device frames.

Re-run after adding captures:

```sh
python3 tools/import_device_screenshots.py --source ~/Downloads
```

The mapping from source filename to shot lives in `SHOTS` in that script.

Two consumers, one set of captures:

| Consumer | Where the files go |
| --- | --- |
| App Store | `Docs/images/` — picked up by `tools/prepare_app_store_upload_bundle.py` and copied into every upload-safe locale |
| Landing page | `site/assets/img/screens/` — see "Wiring a screenshot into the site" below |

## Capture spec

- **Device:** a physical iPhone, or the iPhone 17 Pro Max simulator.
- **Size:** the bundle requires exactly **1320 × 2868**. Captures at
  1125 × 2436 are accepted and converted by the import script; anything smaller
  would upscale too far to stay sharp.
- **Format:** PNG. Files must be named with a leading two-digit number
  (`01-scanner.png`), because `numbered_pngs()` only picks up names starting
  with two digits.
- **Languages:** capture every shot twice, EN and UK. `Docs/images/` feeds
  `en-US`, `en-GB`, and `uk`.
- **Appearance:** light for the App Store set. Dark is optional and only for
  the site.
- **Content:** the current captures use a real photo library. These become
  public assets, so before each release check every frame for recognisable
  faces, location-revealing images, readable personal data, and anything legible
  on a screen shown inside a photo. `tools/generate_demo_library.py` builds a
  synthetic library if you would rather not publish real photos.
- **Status bar:** full signal, full battery, no notifications.

## Shots

| # | Screen | EN | UK | On site | File |
|---|---|---|---|---|---|
| 1 | Scanner idle | ✅ | ✅ | ✅ | `01-scanner-idle` |
| 2 | Scanner scanning | ✅ | ✅ | — | `02-scanner-scanning` |
| 3 | Cleanup queue | ✅ | ✅ | ✅ | `03-cleanup-queue` |
| 4 | Cluster details, Best Shot | ✅ | ✅ | ✅ | `04-cluster-details` |
| 5 | Comparison review | ✅ | ✅ | ✅ | `05-comparison-review` |
| 6 | Cleanup confirm (iOS dialog) | ✅ | — | — | `06-cleanup-confirm` |
| 7 | Cleanup progress | ✅ | ✅ | ✅ | `07-cleanup-progress` |
| 8 | Screenshot cleanup | ✅ | — | — | `08-screenshot-cleanup` |
| 9 | History | — | — | — | still needed |
| 10 | Settings with Legal section | — | — | — | still needed |
| 11 | Paywall with disclosure | — | — | — | still needed |
| 12 | User Guide | — | — | — | still needed |
| 13 | Welcome / privacy | ✅ | ✅ | — | `13-welcome-privacy` |

Outstanding: 9, 10, 11, 12, plus Ukrainian versions of 6 and 8.

Shots 10 and 11 do not ship on the listing but are worth capturing as App
Review evidence that the Legal section and the subscription disclosure exist.

The App Store allows up to 10 screenshots, so the nine captured cover the
listing with room for one more.

## Wiring a screenshot into the site

1. Put the PNG at `site/assets/img/screens/<name>.png`.
2. Add `image: <name>` to the matching entry in `site/_data/screens.yml`.

The frame swaps from the pending placeholder to the screenshot with no layout
or CSS change. Entries carry EN and UK `caption` and `alt` text already.

Landing-page captures do not need to be 1320 × 2868 — the frames render at
roughly 260px wide, so a downscaled copy keeps the page light. Run them through
`tools/build_site_assets.sh` conventions (AVIF plus a PNG fallback) if the set
grows large.
