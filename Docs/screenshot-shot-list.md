# Alike Screenshot Shot List

Ten of the thirteen shots are captured, from a physical iPhone at 1125 x 2436.
One shot is still open, one is optional and the rest are retired — see
"What is actually outstanding" below. `tools/import_device_screenshots.py` upscales
them to the required 1320 x 2868 and pads the 10px remainder with black (the
app's screens are black at both edges, so the padding is invisible), and emits
520px copies for the landing-page device frames.

Re-run after adding captures:

```sh
python3 tools/import_device_screenshots.py --source ~/Downloads
```

The mapping from source filename to shot lives in `SHOTS` in that script.

Three consumers, one set of captures:

| Consumer | Where the files go |
| --- | --- |
| Captures | `Docs/images/raw/<locale>/` — the bare screens, the input for everything below |
| App Store | `Docs/images/<locale>/` — product renders, picked up by `tools/prepare_app_store_upload_bundle.py` and copied into every upload-safe locale |
| Landing page | `site/assets/img/screens/` — see "Wiring a screenshot into the site" below |

## From captures to product screenshots

The listing does not ship bare captures. `tools/generate_app_store_product_screenshots.py`
renders five marketing slides per locale — headline, supporting line, tilted
iPhone — onto a dark canvas that matches the app's own appearance:

```sh
build/tools-venv/bin/python tools/generate_app_store_product_screenshots.py
```

The venv is created once, because Pillow is not in the system Python:

```sh
python3 -m venv build/tools-venv && build/tools-venv/bin/pip install --upgrade pip Pillow
```

Slides, copy and layout live in `SLIDES` and `COPY` in that script. Four
background variants share the same concept; `--drafts` renders all of them into
`build/generated/product_screenshot_drafts/` with a comparison contact sheet, and
`--variant <name>` renders the chosen one into `Docs/images/`. The listing
currently ships `spotlight`.

`Docs/screenshot-brief.md` is the production brief for that deck: the five
slides in listing order, their copy per locale, the composition and band colour
of each, and what to check before upload. See
`Skills/DesignConcept/app-store-screenshots/SKILL.md` for the copy and visual
rules behind it.

## Capture spec

- **Device:** a physical iPhone, or the iPhone 17 Pro Max simulator.
- **Size:** the bundle requires exactly **1320 × 2868**. Captures at
  1125 × 2436 are accepted and converted by the import script; anything smaller
  would upscale too far to stay sharp.
- **Format:** PNG. Files must be named with a leading two-digit number
  (`01-scanner.png`), because `numbered_pngs()` only picks up names starting
  with two digits.
- **Languages:** capture every shot twice, EN and UK. `Docs/images/raw/en-US/`
  feeds `en-US`, `Docs/images/raw/uk/` feeds `uk`. Those are the only two
  localizations the listing has. Some shots are English-only on purpose; the
  status table says which.
- **Appearance:** light for the App Store set. Dark is optional and only for
  the site.
- **Content:** the current captures use a real photo library. These become
  public assets, so before each release check every frame for recognisable
  faces, location-revealing images, readable personal data, and anything legible
  on a screen shown inside a photo. The frames captured so far have been
  reviewed and accepted as they are, including the laptop screen visible in
  shot 5 UK; the sweep applies to new captures. There is no synthetic-library
  generator in the repo — an earlier draft of this document promised a
  `tools/generate_demo_library.py` that was never written. Curate the capture
  device's library by hand instead.
- **Status bar:** full signal, full battery, no notifications.

## Shots

| # | Screen | EN | UK | On site | File |
|---|---|---|---|---|---|
| 1 | Scanner idle | ✅ | ✅ | ✅ | `01-scanner-idle` |
| 2 | Scanner scanning | ✅ | ✅ | — | `02-scanner-scanning` |
| 3 | Cleanup queue | ✅ | ✅ | ✅ | `03-cleanup-queue` |
| 4 | Cluster details, Best Shot | ✅ | ✅ | ✅ | `04-cluster-details` |
| 5 | Comparison review | ✅ | ✅ | ✅ | `05-comparison-review` |
| 6 | Cleanup confirm (iOS dialog) | ✅ | n/a | — | `06-cleanup-confirm` |
| 7 | Cleanup progress | ✅ | ✅ | ✅ | `07-cleanup-progress` |
| 8 | Screenshot cleanup | ✅ | n/a | — | `08-screenshot-cleanup` |
| 9 | History | optional | optional | — | — |
| 10 | Settings with Legal section | open | n/a | — | — |
| 11 | Paywall with disclosure | ✅ | n/a | — | `review/11-paywall-features`, `review/11-paywall-disclosure` |
| 12 | User Guide | retired | retired | — | — |
| 13 | Welcome / privacy | ✅ | ✅ | — | `13-welcome-privacy` |

### What is actually outstanding

Every shot is now either captured, or has a reason it is not. A shot with no
consumer is not a gap.

**Open — one shot:**

- **10. Settings with the Legal section.** App Review evidence that the legal
  links are in the app. English only; App Review reads one language. Cheap to
  capture and worth having if the legal links are ever queried.

**Optional — capture only if you decide to grow a surface:**

- **9. History.** Earlier notes called this "the last landing-page frame". That
  is no longer true: `site/_data/screens.yml` holds five slots and all five have
  images. Adding History means adding a sixth entry there, or a sixth deck
  slide — a deliberate choice about the surface, not a hole to plug.

**Retired — with the reason, so nobody re-opens them:**

- **12. User Guide.** Always "optional, listing only". The deck is five slides
  with a deliberate alternating rhythm and no room for a sixth that says nothing
  new.
- **Ukrainian 6 and 8.** Shots 6 and 8 are not in the deck or on the site in
  *either* locale, so a Ukrainian twin has no consumer.
- **Ukrainian 11.** App Store Connect takes one review screenshot per in-app
  purchase and it is locale-agnostic. The English capture is that screenshot.

`n/a` in the table means the same thing: not missing, not wanted.

Shots 1, 3, 4, 5 and 7 make up the product deck in `SLIDES`; the others are
captured but unused on the listing. Adding one to the deck means adding a
`SlideLayout` and a copy line per locale in
`tools/generate_app_store_product_screenshots.py`.

Shots 10 and 11 do not ship on the listing but are App Review evidence that the
Legal section and the subscription disclosure exist. They live in
`Docs/images/review/`, which the upload bundle deliberately ignores — like
`Docs/images/raw/`, it is a subfolder, and only numbered PNGs sitting directly
in `Docs/images/en-US/` and `Docs/images/uk/` are copied into the listing.

`review/11-paywall-disclosure.png` is the paywall shot App Store Connect asks
for with the subscription; point `ALIKE_IAP_REVIEW_SCREENSHOT_PATH` at it.
Both shot 11 files came from the iPhone 17 Pro simulator at 1206 × 2622, which
the import script does not handle. Converting a 6.3" capture takes:

```sh
sips --resampleWidth 1320 in.png --out tmp.png
sips -c 2868 1320 tmp.png --out out.png
```

The crop trims one pixel from the top and bottom, inside the status-bar and
home-indicator margins.

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
