# Alike Screenshot Shot List

Eleven of the fifteen shots are captured in EN and UK. All seven deck shots are
captured in the Tier 1 and Tier 3 languages and in `ar` too, so as of 1.4.0 every
one of the thirteen decks is complete at seven slides. One more shot is open in
English, one is optional and the rest are retired — see "What is actually
outstanding" below.

Shots 1–14 come from a physical iPhone at 1125 x 2436;
`tools/import_device_screenshots.py` upscales
them to the required 1320 x 2868 and pads the 10px remainder with black (the
app's screens are black at both edges, so the padding is invisible), filling the
capture store every deck and the landing page are built from.

Re-run both steps after adding captures — the import fills the store, and the
site's device frames are a separate render off that store:

```sh
python3 tools/import_device_screenshots.py --source ~/Downloads
python3 tools/build_site_screenshots.py --site-repo ../alikeapp.github.io
```

The mapping from source filename to shot lives in `SHOTS` in the import
script, for EN and UK. Other languages come from an optional
`Docs/images/raw/capture-manifest.json`, which the script merges over `SHOTS`:

```json
{
  "de": {"1": "IMG_4101.PNG", "3": "IMG_4102.PNG"},
  "fr": {"1": "IMG_4110.PNG", "3": "IMG_4111.PNG"}
}
```

Camera-roll filenames for a session that has not happened yet do not belong in
a checked-in table, which is why they live in a manifest instead of another
column. Captures already at 1320 x 2868 — what the iPhone 17 Pro Max simulator
produces — need neither the script nor the manifest; drop them straight into
`Docs/images/raw/<locale>/` under the names in the table below.

Three consumers, one set of captures:

| Consumer | Where the files go |
| --- | --- |
| Captures | `Docs/images/raw/<locale>/` — the bare screens, the input for everything below |
| App Store | `Docs/images/<locale>/` — product renders, picked up by `tools/prepare_app_store_upload_bundle.py` and copied into every upload-safe locale |
| Landing page | `assets/img/screens/` in `alikeapp/alikeapp.github.io` — see "Wiring a screenshot into the site" below |

## From captures to product screenshots

The listing does not ship bare captures. `tools/generate_app_store_product_screenshots.py`
renders the deck — headline, supporting line, tilted iPhone — onto a dark canvas
that matches the app's own appearance, one slide per entry in `SLIDES`:

```sh
build/tools-venv/bin/python tools/generate_app_store_product_screenshots.py
```

The venv is created once, because Pillow is not in the system Python:

```sh
python3 -m venv build/tools-venv && build/tools-venv/bin/pip install --upgrade pip Pillow arabic-reshaper python-bidi
```

Slides, copy and layout live in `SLIDES` and `COPY` in that script. The deck is
seven slides in listing order, and `SLIDES` and `COPY` hold seven. A new entry
and its frames land in the same commit, for the reason spelled out under
"Adding a slide" in the brief: `validate_sources()` refuses to render a slide
with no capture, and refuses a locale whose `COPY` is short an entry, so a
half-landed slide breaks the deck for every locale at once. Four background variants
share the same concept; `--drafts` renders all of them into
`build/generated/product_screenshot_drafts/` with a comparison contact sheet, and
`--variant <name>` renders the chosen one into `Docs/images/`. The listing
currently ships `spotlight`.

`Docs/screenshot-brief.md` is the production brief for that deck: the six
slides in listing order, their copy per locale, the composition and band colour
of each, and what to check before upload. The sixth slide's copy is approved and
parked there in all thirteen locales, so the capture session is the only thing
standing between it and a render. See
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
- **Languages:** the listing has thirteen localizations, and each needs its own
  captures — a translated app behind English screenshots reads as an English
  app. The capture directory is the app's own language code:
  `Docs/images/raw/{en-US,uk,de,fr,es,es-419,pt-BR}/`. Only the six deck shots
  (1, 3, 4, 5, 7, 14) are needed in every language; the rest exist for the site or
  for App Review and stay EN/UK, as the status table says. The device or
  simulator has to be *running* in that language — Settings, General, Language &
  Region, or launch with `-AppleLanguages` / `-AppleLocale`. Keep the same
  library content across languages so the thirteen decks read as one set.
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

"Tier 1" below is the five locales added for the App Store listing in task 40:
`de`, `fr`, `es`, `es-419`, `pt-BR`. "Tier 3" is the five added in task 44:
`it`, `nl`, `pl`, `tr`, `zh-Hant`.

| # | Screen | EN | UK | Tier 1 | Tier 3 | On site | File |
|---|---|---|---|---|---|---|---|
| 1 | Scanner idle | ✅ | ✅ | ✅ | ✅ | ✅ | `01-scanner-idle` |
| 2 | Scanner scanning | ✅ | ✅ | n/a | n/a | — | `02-scanner-scanning` |
| 3 | Cleanup queue | ✅ | ✅ | ✅ | ✅ | ✅ | `03-cleanup-queue` |
| 4 | Cluster details, Best Shot | ✅ | ✅ | ✅ | ✅ | ✅ | `04-cluster-details` |
| 5 | Comparison review | ✅ | ✅ | ✅ | ✅ | ✅ | `05-comparison-review` |
| 6 | Cleanup confirm (iOS dialog) | ✅ | n/a | n/a | n/a | — | `06-cleanup-confirm` |
| 7 | Cleanup progress | ✅ | ✅ | ✅ | ✅ | ✅ | `07-cleanup-progress` |
| 8 | Screenshot cleanup | ✅ | n/a | n/a | n/a | — | `08-screenshot-cleanup` |
| 9 | History | optional | optional | n/a | n/a | — | — |
| 10 | Settings with Legal section | open | n/a | n/a | n/a | — | — |
| 11 | Paywall with disclosure | ✅ | n/a | n/a | n/a | — | `review/11-paywall-features`, `review/11-paywall-disclosure` |
| 12 | User Guide | retired | retired | n/a | n/a | — | — |
| 13 | Welcome / privacy | ✅ | ✅ | n/a | n/a | — | `13-welcome-privacy` |
| 14 | Cluster details, enhanced | ✅ | ✅ | ✅ | ✅ | — | `14-best-shot-enhanced` |
| 15 | Home screen with both widgets | ✅ | ✅ | ✅ | ✅ | ✅ | `15-widgets-home` |

The table has no `ar` column — Arabic was added to the listing after it was
written, and the existing rows were never re-cut. For shot 14, read the four
status columns as thirteen: it is open in `en-US`, `uk`, the five Tier 1
languages, the five Tier 3 languages **and** `ar`. Twelve of thirteen is a
failing deck, not a partial one.

### What is actually outstanding

Every shot is either captured or has a reason it is not. A shot with no
consumer is not a gap. Shots 14 and 15 both ship in the deck, in all thirteen
locales; shot 15 also reaches the landing page.

**Captured — the Tier 3 decks, 25 files.** Shots 1, 3, 4, 5 and 7 in `it`, `nl`,
`pl`, `tr` and `zh-Hant`, taken in one session on a physical iPhone and recorded
in `capture-manifest.json`, exactly as Tier 1 was. With the Arabic deck that
followed, all thirteen listing locales have one.

Polish shot 1 is the one frame that did not arrive as a 1125 × 2436 PNG: it came
off the device as a 1119 × 2436 JPEG, so it was resampled to 1320 wide and centre-
cropped by 6px rather than run through `import_device_screenshots.py`, and its
manifest entry is absent for that reason. The render is indistinguishable from
its siblings, but it is the one source frame that is not pristine, so replacing it
with the original PNG is a cheap improvement if that file ever turns up.

**Captured — the Tier 1 decks, 25 files.** Shots 1, 3, 4, 5 and 7 in `de`, `fr`,
`es`, `es-419` and `pt-BR`, taken in one session on a physical iPhone and
recorded in `capture-manifest.json`. Nothing else is needed in these languages:
shots 2, 6, 8 and 13 have no consumer outside EN/UK, and 10 and 11 are App
Review evidence, which is locale-agnostic. English shot 5 was recaptured in the
same session so its frame matches the five new decks.

Ukrainian shot 5 is still the older capture, so `uk` is the one deck whose
comparison-review frame shows different photos from the other six. Not wrong —
the deck reads fine on its own — but recapturing it is what would make all
thirteen decks a single set.

**Captured — the seventh deck shot, thirteen files, and the first one taken on a
simulator.** `15-widgets-home` in all thirteen listing locales, shot for 1.4.0 on
an iPhone 17 Pro Max simulator running iOS 26.5, which captures at 1320 × 2868
natively — so these frames go straight into `Docs/images/raw/<locale>/` and need
neither `import_device_screenshots.py` nor a `capture-manifest.json` entry.

A device could not have produced this shot any more faithfully: the widget
gallery always renders `WidgetSnapshot.placeholder()`, and a real library with
24 groups, 86 screenshots and 12 blurred photos cannot be staged on demand. The
frame is driven by a hand-written App Group snapshot instead — terminate the app,
write `widget-snapshot.json`, reinstall **without launching** (launching makes
the app republish from its own empty library and wipes the file). The home screen
is a page carrying only the two Alike widgets, the app icon and the dock, with
the other pages hidden in Edit Pages so a reboot lands on it; the locale loop
switches `AppleLanguages`/`AppleLocale`, reboots, and screenshots via
`simctl io`.

This shot is what caught the extension's missing `CFBundleLocalizations`: with no
localization list of its own the appex resolved `Locale.current` to English, so
every non-English frame drew an English month and the English plural form
("24 груп" for "24 групи"). Fixed in `Alike/AlikeWidgets-Info.plist`; the frames
here are from the fixed build.

**Captured — the sixth deck shot, thirteen files.** `14-best-shot-enhanced` in
all thirteen listing locales, taken in one session on a physical iPhone on
6 September 2026 and recorded in `capture-manifest.json`. Cluster details after
Apply: the Best Shot carries both badges, the gold "Best Shot" and the
"Enhanced" capsule. The revert action is deliberately *not* in frame — it lives
in the photo's context menu, so showing it would mean shooting a half-open menu,
which the deck does not do. The slide's headline carries "keep the original"
instead.

**Known weakness, accepted.** The captured cluster holds two photos, so the grid
fills only the upper part of the screen and the lower half renders as empty
black. Against shot 4's full 2 × 2 grid and its cleanup button, slide 6 reads as
the emptiest frame in the deck, and it is visible at thumbnail width. Recapturing
on a four-photo cluster is what would fix it; the owner chose to ship this
capture rather than hold the release for another session. If the deck is ever
reshot, this is the first frame to redo — and a cluster where the enhanced photo
visibly beats its neighbour would sell the slide better than this one does.

**Open — one more shot, unrelated to the deck:**

- **10. Settings with the Legal section.** App Review evidence that the legal
  links are in the app. English only; App Review reads one language. Cheap to
  capture and worth having if the legal links are ever queried.

**Optional — capture only if you decide to grow a surface:**

- **9. History.** Earlier notes called this "the last landing-page frame". That
  is no longer true: `_data/screens.yml` in the site repo holds five slots, one
  per framed shot, and all five have images. Adding History means adding a sixth
  entry there — a deliberate choice about the site's surface, not a hole to plug.
  It is no longer a candidate for the deck either: the sixth deck slot is spoken
  for by shot 14, so History would have to argue its way into a seventh.

**Retired — with the reason, so nobody re-opens them:**

- **12. User Guide.** Always "optional, listing only". A screenshot of the help
  text is a picture of documentation: a shopper reads it, learns that the app
  explains itself, and acts on nothing. The App Store's ceiling is ten
  screenshots and the deck is nowhere near it, so the constraint was never
  room — it is that a slide has to move somebody who has not installed the app
  yet, and this one does not.

  That is also why shot 14 *does* earn the sixth slot instead of contradicting
  this entry. Reversibility is the objection that stops people letting an app
  touch their photos at all, and none of the five existing frames can answer it:
  1 is the scan, 3 the queue, 4 the pick, 5 the comparison before a deletion, 7
  the space returned. Not one of them shows a change made to a photo and then
  undone. Shot 14 is the only frame that carries "one tap puts it back" — a
  reason to trust the app, not a picture of its manual.
- **Ukrainian 6 and 8.** Shots 6 and 8 are not in the deck or on the site in
  *either* locale, so a Ukrainian twin has no consumer.
- **Ukrainian 11.** App Store Connect takes one review screenshot per in-app
  purchase and it is locale-agnostic. The English capture is that screenshot.
- **Tier 1 shots 2, 6, 8, 13.** Same reasoning one step wider: 2 and 13 are
  captured only because EN and UK already had them, and the deck uses neither.
  Capturing them in five more languages would produce twenty files nothing
  reads.

`n/a` in the table means the same thing: not missing, not wanted.

Shots 1, 3, 4, 5 and 7 make up the product deck in `SLIDES` as it stands, and
shot 14 is the sixth slide once its frames exist; the others are captured but
unused on the listing. Adding one to the deck means adding a `SlideLayout` and a
copy line per locale in `tools/generate_app_store_product_screenshots.py` — in
the same commit as the captures, never ahead of them.

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

The App Store allows up to 10 screenshots. The deck ships five today and six
once shot 14 is captured, so the ceiling has never been the binding constraint:
what a slide has to earn is a shopper's attention, not a free slot.

## Wiring a screenshot into the site

The page frames shots 1, 3, 4, 5, 7 and 15, in every language it publishes.
`SITE_SHOTS` in `tools/build_site_screenshots.py` and the site's own
`_data/screens.yml` name the same set, so the two change together. Render them
from the captures already committed here:

```sh
python3 tools/build_site_screenshots.py --site-repo ../alikeapp.github.io
```

That writes two renditions per shot per language — `<name>.avif` at 520px and
the 1x `<name>.jpg` the `<picture>` falls back to on browsers without AVIF, both
under `assets/img/screens/<lang>/`. The lang list comes from the site's own
`_config.yml`, so a locale published without captures fails the run instead of
shipping a broken frame.

The fallback is per locale too, deliberately: a shared English one would put
those browsers back on English screens for every other language — the bug this
whole pipeline exists to fix, and an invisible one to anyone testing in a
browser that does have AVIF. PNG is what the matrix cannot afford: it measured
~17MB back when the matrix was twelve locales wide, and the listing is thirteen
now, against ~5MB for AVIF plus 1x JPEG.

The one remaining step happens in the `alikeapp/alikeapp.github.io` repository:
add `image: <name>` to the matching entry in `_data/screens.yml`. The frame
swaps from the pending placeholder to the screenshot with no layout or CSS
change, and each entry already carries `caption` and `alt` text per locale.
