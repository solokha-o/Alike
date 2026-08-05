# Alike Screenshot Shot List

The specification to capture against. Nothing here is captured yet — both the
App Store upload bundle and the landing page are waiting on these.

Two consumers, one set of captures:

| Consumer | Where the files go |
| --- | --- |
| App Store | `Docs/images/` — picked up by `tools/prepare_app_store_upload_bundle.py` and copied into every upload-safe locale |
| Landing page | `site/assets/img/screens/` — see "Wiring a screenshot into the site" below |

## Capture spec

- **Device:** iPhone 6.9" simulator.
- **Size:** exactly **1320 × 2868**. `validate_screenshots()` in
  `tools/prepare_app_store_upload_bundle.py` rejects anything else.
- **Format:** PNG. Files must be named with a leading two-digit number
  (`01-scanner.png`), because `numbered_pngs()` only picks up names starting
  with two digits.
- **Languages:** capture every shot twice, EN and UK. `Docs/images/` feeds
  `en-US`, `en-GB`, and `uk`.
- **Appearance:** light for the App Store set. Dark is optional and only for
  the site.
- **Content:** use a **synthetic demo library**. These become public assets, so
  no real personal photos, no recognisable faces, no location-revealing images,
  and no readable personal data in any status bar or notification.
- **Status bar:** full signal, full battery, no notifications.

## Shots

| # | Screen | State to set up | App Store | Site |
|---|---|---|---|---|
| 1 | Scanner idle | Ready state, mascot hero visible, Start Scan prominent | ✅ | ✅ |
| 2 | Scanner scanning | Mid-scan with progress and a photo count | ✅ | — |
| 3 | Cleanup queue | Several clusters, mixed New / Needs review / Reviewed badges | ✅ | ✅ |
| 4 | Cluster details | Best Shot highlighted, some photos selected, estimated savings shown | ✅ | ✅ |
| 5 | Comparison review | `AlikeComparisonReviewView` with two similar photos side by side | ✅ | ✅ |
| 6 | Cleanup confirm | Confirmation sheet showing selected count and estimated savings | — | — |
| 7 | Cleanup success | `CleanupSuccess` celebration with freed space | ✅ | ✅ |
| 8 | Screenshot cleanup | `ScreenshotCleanupView` with a screenshot group | ✅ | — |
| 9 | History | `CleanupHistoryView` grouped by month with an all-time total | — | ✅ |
| 10 | Settings | Subscription card, Data & Privacy, and the Legal section | — | — |
| 11 | Paywall | Both plans, renewal and trial disclosure, both legal links visible | — | — |
| 12 | User Guide | `UserGuideHubView` topic list | — | — |
| 13 | Welcome | Permission explanation shown before the system prompt | ✅ | — |

The App Store allows up to 10 screenshots; the eight marked above are the
recommended set, in that order.

**Capture 10 and 11 even though neither ships.** They are the evidence that the
Legal section and the subscription disclosure exist, which is exactly what App
Review checks for an auto-renewable subscription. Keep them to hand for the
review notes in `Docs/app-store-review-notes.txt`.

## Wiring a screenshot into the site

1. Put the PNG at `site/assets/img/screens/<name>.png`.
2. Add `image: <name>` to the matching entry in `site/_data/screens.yml`.

The frame swaps from the pending placeholder to the screenshot with no layout
or CSS change. Entries carry EN and UK `caption` and `alt` text already.

Landing-page captures do not need to be 1320 × 2868 — the frames render at
roughly 260px wide, so a downscaled copy keeps the page light. Run them through
`tools/build_site_assets.sh` conventions (AVIF plus a PNG fallback) if the set
grows large.
