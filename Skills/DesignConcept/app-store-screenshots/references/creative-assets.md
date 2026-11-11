# Creative Assets: Product Page Header and Search Results

Creative assets are not screenshots. They live in the App Store Connect Asset
Library, need iOS 27+, and are placed per version localization. `deliver` does
not know about them, so they have their own generator and uploader.

## Specs (from `GET /v1/appAssetLibraryRefData`, 2026-11)

| Placement | API type | Size | Format |
|---|---|---|---|
| Product Page Header | `PRODUCT_PAGE_HEADER_ASSET` | 3840 x 1646 exactly (21:9) | PNG, no alpha |
| Search Results | `APP_STORE_SEARCH_RESULTS_ASSET` | 3:2, 1920x1280 … 3840x2560 | PNG/JPEG, no alpha |

Both: one per localization (`DEFAULT_PROFILE`), category `CREATIVE_ASSETS`. A
universal 16:9 5244x2950 PNG fits both, but we ship two dedicated files. Apple
gives safe areas only in its templates; check every placement in ASC Preview.
Content rules: no prices, URLs, awards, platform references; 4+.

## Pipeline

```
Docs/images/creative-assets/v7-{header,search}-plate.png   art, no text, no hero
Packages/DesignSystem/DesignSource/WelcomeHero/AlikeWelcomeHero-source.png
  → tools/generate_app_store_creative_assets.py
  → build/generated/creative_assets/{header,search}/<copy>.png + manifest.json
  → fastlane ios creative_assets_upload version:X.Y.Z [apply:true]
```

```sh
build/tools-venv/bin/python tools/generate_app_store_creative_assets.py
open build/generated/creative_assets/preview-header.png
tools/local_cd.sh plan-creative-assets --version X.Y.Z      # read-only plan
tools/upload-creative-assets [X.Y.Z]                         # plan, confirm, upload, place
```

## Rules

- Plates are cropped and downscaled, never upscaled. New art arrives as a
  plate with empty text and hero zones; the hero is always the app's own PNG.
- Copy lives in `COPY`; `APP_STORE_LOCALES` maps all 18 listing locales onto it
  and the test checks it against `DELIVER_ACCEPTED_LOCALES`. Header may run
  three lines; Search is one short line that reads at thumbnail size. No
  numbers, prices or deletion claims (the test rejects them).
- The generator fails on missing glyphs, contrast below 12:1, text near an
  edge, or a headline that only fits below the minimum size. Rebreak by hand.
- iPhone scales the Header to the banner height and shows only x ≈ 372…3468
  (measured on live 1.7.2, 2026-11-11); iPad and Mac show all of it. All
  Header text and the hero stay inside `safe` x 560…3280, and the generator
  fails otherwise. The paper frame is decoration and may bleed off. Check
  `preview-header-iphone.png`, which shows that crop for every copy key.
- `referenceName` is `alike-<placement>-<copy>-<sha12>`: identical renders are
  reused, changed renders upload as new assets.
- The uploader never deletes or archives, never replaces an occupied slot, and
  never submits or publishes. The API has no PATCH for
  `appAssetLibraryPlacements` (GET, POST, DELETE only), so a placement cannot
  swap its image. To swap one, wait until the new image is `APPROVED`, remove
  the old placement in ASC by hand, then re-run.
- `apply` uploads every image first, then places. Where it places depends on
  the version state:
  - `PREPARE_FOR_SUBMISSION` or a rejected state: every image; the placements
    ship with the next submission.
  - Live (`READY_FOR_DISTRIBUTION`, legacy `READY_FOR_SALE`): only images
    already `APPROVED`. Each placement is `ACTIVE` at once, no Publish step
    (36 placements on 1.7.2, 2026-11-11). A new image uploads only; after Apple
    approves it in the library, re-run to place it.
  - In review: none. ASC returns `409 STATE_ERROR.INVALID_STATE` (seen on 1.7.2
    in `WAITING_FOR_REVIEW`). The run fills the library only.
  Rows that cannot be placed show `upload_only` in the plan, before the
  confirmation. Re-runs reuse images by `referenceName`; nothing uploads twice.
- If ASC refuses a placement anyway, the run stops with the API error; uploaded
  images stay in the library for the next run. A reservation left in
  `AWAITING_UPLOAD` by a killed run is not reused; a fresh one is made.
