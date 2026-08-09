# Alike CI/CD Runbook

Run everything from the repository root.

Shipping a release rather than validating a change? Follow
`Docs/release-checklist.md` — it sequences these commands into the go-live gate.

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
tools/release-check 1.0.0 4
```

```sh
tools/upload-build 1.0.0 4
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

`xcode-select` does not have to point at Xcode. `local_ci.sh` and `local_cd.sh`
both source `tools/xcode-env.sh` and call `ensure_developer_dir`, which falls
back to the newest installed Xcode when the active developer directory is the
Command Line Tools. An explicit `DEVELOPER_DIR` always wins. Both scripts
resolve it independently, because `local_cd.sh` runs Fastlane as a sibling of
`local_ci.sh` and does not inherit its export — and Fastlane fails obscurely
without it: `Helper.xcode_version` shells out to `xcodebuild -version`, gets
nothing, and `iTunesTransporter` crashes on `nil.start_with?`.

For metadata validation and uploads:

- `.env` or your shell provides real public `https` values for:
  - `ALIKE_PRIVACY_URL`
  - `ALIKE_SUPPORT_URL`
  - `ALIKE_TERMS_URL` — the footer appended to every description.
  - `ALIKE_MARKETING_URL` — optional. Set, it writes `marketing_url.txt`;
    unset, the App Store Connect value is left untouched.
  - `ALIKE_PRIVACY_URL_UK`, `ALIKE_TERMS_URL_UK`, `ALIKE_SUPPORT_URL_UK` —
    per-locale overrides. Unset, the uk listing reuses the three URLs above,
    which point at the English pages even though the site publishes Ukrainian
    ones under `/uk/`. The suffix is the App Store locale, uppercased, with `-`
    replaced by `_`, so a third localization follows the same pattern.

For App Store Connect uploads:

- `.env` or your shell provides:
  - `APP_STORE_CONNECT_KEY_ID`
  - `APP_STORE_CONNECT_ISSUER_ID`
  - `APP_STORE_CONNECT_API_KEY_PATH`
    or `APP_STORE_CONNECT_API_KEY_CONTENT`

For TestFlight upload:

- Signing is already configured locally. Specifically an **App Store
  distribution** profile for `com.alike.app` — a development certificate is
  enough to archive but not to export, and the export fails with
  `No profiles for 'com.alike.app' were found`.
- `ALIKE_XCODE_ALLOW_PROVISIONING_UPDATES=1` if it is not, which lets
  `xcodebuild` create the certificate and profile using the App Store Connect
  API key. The key must be Admin or App Manager.
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

deliver 2.230.0 decides whether a screenshot arrived by matching the local MD5
against `sourceFileChecksum` on App Store Connect, and App Store Connect keeps
returning that field as `null` for roughly 20-30 seconds after the bytes land.
deliver looks about 7 seconds in, prints `... is missing on App Store Connect`
for every file and uploads the whole deck a second time, leaving 9-10 images in
a set that should hold 5.

Counting what App Store Connect lists does not detect this: Spaceship creates a
placeholder row before it uploads any bytes, so the full count is there from the
start.

`wait_for_screenshot_checksums_before_verifying` in `fastlane/Fastfile` holds the
verification back until every local checksum is readable on App Store Connect.
The wait is capped by `ALIKE_SCREENSHOT_CHECKSUM_GRACE_SECONDS` (default 300).
On timeout it deletes the screenshots for the locales being uploaded, so
deliver's own retry starts from an empty set instead of stacking a second copy
on top; the worst case is a slow clean re-upload, never a doubled set. A
screenshot that App Store Connect reports as failed ends the wait immediately
and is left to deliver's retry.

If a set already holds duplicates, just upload again — `overwrite_screenshots`
deletes the whole set first. Watch for at least one
`Waiting for App Store Connect to publish screenshot checksums ...` line, a
single `Uploaded ...` block, and no `missing on App Store Connect` lines.

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

| Scheme | Run configuration | Use for |
|---|---|---|
| `Alike` | Release | local validation, package and app compile checks, release archive/export, TestFlight upload |
| `Alike-VerboseLogs` | Debug | manual debugging with verbose scan/vision/storage logging |
| `Alike-DebugVerboseLogs` | Debug | manual debugging with verbose logging in Debug builds |

Only `Alike` is used by CI/CD. The verbose schemes are for interactive debugging.

`Alike` runs Release with no debugger attached and no local StoreKit
configuration, so ⌘R gives the same build the App Store gets: optimized, with
every `#if DEBUG` surface compiled out (the premium override in
`DebugPremiumAccessController`, the debug section in `SettingsView`, the
`Core/Mocks` doubles) and purchases going to the real StoreKit sandbox instead
of `Alike.storekit`. Use `Alike-DebugVerboseLogs` for anything that needs a
debugger, the debug menu, or local StoreKit transactions.

Its Test action stays on Debug: the test targets depend on the `#if DEBUG`
mocks in `Packages/Core/Sources/Core/Mocks`, which do not exist in a Release
build.

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
- Screenshot deck brief: `Docs/screenshot-brief.md`
- Subscription catalog reference: `Docs/Subscriptions.md`
- Generated upload bundle: `build/generated/store_upload/`

Do not edit generated files under `build/generated/store_upload/` by hand.

## Landing Page

The marketing site and the legal pages live in their own repository,
[`alikeapp/alikeapp.github.io`](https://github.com/alikeapp/alikeapp.github.io), and
deploy to GitHub Pages on every push to that repository's `main`. An organization Pages
site has to be served from a repository named `<org>.github.io`, which is what buys the
clean `https://alikeapp.github.io/` address instead of a `/Alike/` sub-path.

The practical consequence for releases: the site no longer rides along with the app
release merge. It can be deployed and its URLs verified at any time, independently of
this repository.

| Page | EN | UK |
|---|---|---|
| Home | `/` | `/uk/` |
| Privacy Policy | `/privacy/` | `/uk/privacy/` |
| Terms of Use | `/terms/` | `/uk/terms/` |
| Support | `/support/` | `/uk/support/` |

Those last two supply the values the metadata bundle needs:

```sh
ALIKE_PRIVACY_URL="https://alikeapp.github.io/privacy/"
```

```sh
ALIKE_SUPPORT_URL="https://alikeapp.github.io/support/"
```

The landing page itself is the marketing URL:

```sh
ALIKE_MARKETING_URL="https://alikeapp.github.io/"
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

- `Docs/images/` carries five product screenshots per locale. Three of the thirteen shots in `Docs/screenshot-shot-list.md` are still uncaptured, plus some Ukrainian counterparts. None of them are in the shipping deck — see `Docs/screenshot-brief.md`.
- The `alikeapp/alikeapp.github.io` repository must exist, hold the site, and have Pages switched to the **GitHub Actions** source before the site first deploys. Until then the privacy, support and marketing URLs in the metadata are dead links. This is no longer blocked by the app's release merge — it can be done first.

`tools/quick`, `tools/full`, and `tools/meta` work today; the upload commands intentionally refuse to run until the items above are done.
