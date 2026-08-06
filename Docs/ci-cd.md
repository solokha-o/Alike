# Alike CI/CD Runbook

Run everything from the repository root.

## Quick Start

Daily commands are the short wrappers in `tools/`:

| Goal | Short command | Under the hood |
|---|---|---|
| Fast local validation | `tools/quick` | `tools/local_ci.sh quick` |
| Broad local validation | `tools/full` | `tools/local_ci.sh full` |
| Release preflight | `tools/release-check` | `tools/local_ci.sh release-check --version X.Y.Z --build N` |
| Prepare or validate App Store metadata locally | `tools/meta` | `fastlane ios metadata_validate` or placeholder bundle generation |
| Upload text + screenshots | `tools/upload` | `tools/local_cd.sh upload-metadata` |
| Upload text only | `tools/text` | `tools/local_cd.sh upload-text-metadata` |
| Upload screenshots only | `tools/upload-screenshots` | `tools/local_cd.sh upload-screenshots` |
| Upload TestFlight build | `tools/upload-build` | `tools/local_cd.sh upload-testflight --version X.Y.Z --build N` |

## What The Shortcuts Do

- `tools/quick` and `tools/full` automatically set a writable `CLANG_MODULE_CACHE_PATH` when one is not already provided.
- `tools/meta`, `tools/upload`, `tools/text`, `tools/upload-screenshots`, and `tools/upload-build` automatically load `.env` when it exists. Disable that with `ALIKE_NO_ENV=1`.
- Upload shortcuts ask for interactive confirmation. For non-interactive runs, set `ALIKE_ASSUME_YES=1`.
- `tools/release-check` and `tools/upload-build` infer `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `Alike/Alike.xcodeproj/project.pbxproj` when you omit them.

Examples:

```sh
tools/quick
```

```sh
tools/full
```

```sh
tools/release-check
```

```sh
tools/meta
```

If you need to override version and build explicitly:

```sh
tools/release-check 1.0.0 6
```

```sh
tools/upload-build 1.0.0 6
```

## Mental Model

There are two real engines:

| Script | Purpose | External state |
|---|---|---|
| `tools/local_ci.sh` | Local validation only | Never uploads or submits anything |
| `tools/local_cd.sh` | App Store Connect and TestFlight mutations | Can upload metadata, screenshots, or a build |

Use the short wrappers for day-to-day work. Use `local_ci.sh` and `local_cd.sh` directly only when you need the raw low-level interface.

## Prerequisites

For CI:

- Xcode and command line tools are installed.
- SwiftPM can build packages under `Packages/`.
- The app project exists at `Alike/Alike.xcodeproj`.

For metadata validation and uploads:

- `.env` or your shell provides real public `https` values for:
  - `ALIKE_PRIVACY_URL`
  - `ALIKE_SUPPORT_URL`
  - `ALIKE_MARKETING_URL` — optional. Set, it writes `marketing_url.txt`;
    unset, the App Store Connect value is left untouched.

For App Store Connect uploads:

- `.env` or your shell provides:
  - `APP_STORE_CONNECT_KEY_ID`
  - `APP_STORE_CONNECT_ISSUER_ID`
  - `APP_STORE_CONNECT_API_KEY_PATH`
    or `APP_STORE_CONNECT_API_KEY_CONTENT`

For TestFlight upload:

- Signing is already configured locally.
- The `Alike` scheme can archive and export successfully in the `Release` configuration.

## CI Commands

### `tools/quick`

Use after narrow code, docs, or script changes.

Runs:

- whitespace validation
- `swift test` for:
  - `Packages/Cleanup`
  - `Packages/Scanner`
  - `Packages/Settings`
  - `Packages/UserGuide`
- App Store upload bundle validation

Does not:

- build the full app
- archive a release
- upload anything

### `tools/full`

Use before PR handoff or after broader app changes.

Runs:

- whitespace validation
- `swift test` for every package under `Packages/` that has tests
- `swift build` for packages without tests
- App Store upload bundle validation
- the full app compile gate with `xcodebuild -scheme Alike`

`Packages/Storage` is explicitly skipped. SwiftPM does not compile the package's
`.xcdatamodeld`, so `PersistenceController` traps with "Failed to load Core Data
model" before any test runs. Its code is still compiled by the app compile gate,
and its tests run normally in Xcode. The skip is recorded in the run report, and
the exclusion list lives in `SWIFTPM_UNSUPPORTED_PACKAGES` in
`tools/local_ci.sh`.

Does not:

- archive a release
- export an IPA
- upload anything

The compile gate is the same one required by `AGENTS.md`. To run it by hand against the pinned simulator:

```sh
xcodebuild -project Alike/Alike.xcodeproj -scheme Alike -destination 'id=66E5E039-9C66-4878-B211-923932320166' build
```

### `tools/release-check [version] [build]`

Use before TestFlight upload or release work.

Runs:

- version/build validation against `project.pbxproj` via `Skills/GitFlow/ios-git-flow/scripts/bump-ios-version.sh --check`
- App Store upload bundle validation
- `Alike` Release archive
- no-upload IPA export

Does not:

- upload a build
- submit for review
- create or push tags
- change version/build numbers

## Metadata Commands

### `tools/meta`

Use when you want a local metadata check without any App Store Connect mutation.

Behavior:

- If `ALIKE_PRIVACY_URL` and `ALIKE_SUPPORT_URL` are available, runs strict Fastlane metadata validation.
- Otherwise, regenerates the bundle with placeholder URLs for local structural validation.

Strict validation also fails while the localized App Store copy in `tools/prepare_app_store_upload_bundle.py` still contains `TODO:` placeholders, so no placeholder text can reach App Store Connect.

### `tools/upload`

Uploads localized text metadata and screenshots.

Maps to:

```sh
ALIKE_CONFIRM_UPLOAD=metadata tools/local_cd.sh upload-metadata
```

### `tools/text`

Uploads only localized text metadata and App Review information.

Maps to:

```sh
ALIKE_CONFIRM_UPLOAD=metadata tools/local_cd.sh upload-text-metadata
```

### `tools/upload-screenshots`

Uploads only screenshots.

Maps to:

```sh
ALIKE_CONFIRM_UPLOAD=metadata tools/local_cd.sh upload-screenshots
```

All three upload commands:

- regenerate and validate the App Store upload bundle
- require real public `https` privacy/support URLs
- require App Store Connect API credentials
- do not upload a binary
- do not submit for review
- do not create or push tags

### Duplicate screenshots

App Store Connect does not list freshly uploaded screenshots straight away, and
deliver 2.230.0 reads that empty list as "nothing was uploaded": it prints
`... is missing on App Store Connect` for every file and uploads the whole deck
a second time, leaving 9-10 images in a set that should hold 5.

`wait_for_screenshot_indexing_before_verifying` in `fastlane/Fastfile` holds the
verification back until App Store Connect lists as many screenshots as were just
uploaded. The wait is capped by `ALIKE_SCREENSHOT_INDEXING_GRACE_SECONDS`
(default 120); after that deliver decides for itself, which is the old
behaviour.

If a set already holds duplicates, just upload again — `overwrite_screenshots`
deletes the whole set first. Watch for a single `Uploaded ...` block and no
`missing on App Store Connect` lines.

## Build Upload Command

### `tools/upload-build [version] [build]`

Uploads the `Alike` Release IPA to TestFlight.

If version/build are omitted, the script uses the current values from `project.pbxproj`.

Maps to:

```sh
ALIKE_CONFIRM_UPLOAD=testflight tools/local_cd.sh upload-testflight --version X.Y.Z --build N
```

Before upload it always runs:

```sh
tools/local_ci.sh release-check --version X.Y.Z --build N
```

It does not:

- submit for review
- notify external testers
- create or push tags
- publish a release

## Schemes

| Scheme | Use for |
|---|---|
| `Alike` | local validation, package and app compile checks, release archive/export, TestFlight upload |
| `Alike-VerboseLogs` | manual debugging with verbose scan/vision/storage logging |
| `Alike-DebugVerboseLogs` | manual debugging with verbose logging in Debug builds |

Only `Alike` is used by CI/CD. The verbose schemes are for interactive debugging.

## Reports

- CI reports: `build/reports/local-ci`
- CD reports: `build/reports/local-cd`

Each CI run updates:

```sh
build/reports/local-ci/latest.json
```

## Non-Interactive Usage

If you need automation or copy-paste without prompts:

```sh
ALIKE_ASSUME_YES=1 tools/upload
```

```sh
ALIKE_ASSUME_YES=1 tools/text
```

```sh
ALIKE_ASSUME_YES=1 tools/upload-screenshots
```

```sh
ALIKE_ASSUME_YES=1 tools/upload-build
```

If you do not want `.env` auto-loading:

```sh
ALIKE_NO_ENV=1 tools/meta
```

## Source Of Truth

- App Review notes: `Docs/app-store-review-notes.txt`
- Screenshot captures: `Docs/images/raw/`
- Uploaded product screenshots: `Docs/images/<locale>/`, rendered by
  `tools/generate_app_store_product_screenshots.py`
- Metadata source: `tools/prepare_app_store_upload_bundle.py`
- Subscription catalog reference: `Docs/Subscriptions.md`
- Generated upload bundle: `build/generated/store_upload/`

Do not edit generated files under `build/generated/store_upload/` by hand.

## Landing Page

The marketing site and the legal pages live in `site/` and deploy to GitHub Pages
via `.github/workflows/pages.yml` on every push to `main` that touches `site/`.

| Page | EN | UK |
|---|---|---|
| Home | `/Alike/` | `/Alike/uk/` |
| Privacy Policy | `/Alike/privacy/` | `/Alike/uk/privacy/` |
| Terms of Use | `/Alike/terms/` | `/Alike/uk/terms/` |
| Support | `/Alike/support/` | `/Alike/uk/support/` |

Those last two supply the values the metadata bundle needs:

```sh
ALIKE_PRIVACY_URL="https://solokha-o.github.io/Alike/privacy/"
```

```sh
ALIKE_SUPPORT_URL="https://solokha-o.github.io/Alike/support/"
```

The landing page itself is the marketing URL:

```sh
ALIKE_MARKETING_URL="https://solokha-o.github.io/Alike/"
```

Local preview needs Ruby and Jekyll:

```sh
cd site && JEKYLL_NO_BUNDLER_REQUIRE=true jekyll build --destination _site
```

Regenerate the image assets from the app's own artwork after changing the
mascot illustrations or the app icon:

```sh
tools/build_site_assets.sh
```

The deploy workflow fails the build if the rendered site references any
third-party host. That is deliberate: the privacy policy states Alike makes no
network requests and bundles no analytics, and a landing page loading a web font
or an analytics script would make that claim false.

## Outstanding Setup

The tooling is in place but the App Store content is not:

- `Docs/images/` carries five product screenshots per locale. Four of the thirteen shots in `Docs/screenshot-shot-list.md` are still uncaptured.
- GitHub Pages must be switched to the **GitHub Actions** source, and `site/` must reach `main`, before the site first deploys. Until then the privacy, support and marketing URLs in the metadata are dead links.

`tools/quick`, `tools/full`, and `tools/meta` work today; the upload commands intentionally refuse to run until the items above are done.
