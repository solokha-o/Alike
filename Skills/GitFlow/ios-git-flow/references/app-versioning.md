# App Versioning

Use this reference whenever a task mentions product version, build number,
`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, TestFlight build, App Store
version, release tag, or a release merge.

## Fields

- `MARKETING_VERSION` maps to `CFBundleShortVersionString`, the user-visible
  app version. Use exactly three numeric components: `X.Y.Z`.
- `CURRENT_PROJECT_VERSION` maps to `CFBundleVersion`, the build string that
  identifies one build/upload iteration. Use a positive integer.
- `Alike/Alike.xcodeproj/project.pbxproj` is the canonical place to check and
  update these settings in this repo.

## Baseline Version Rule

- This repo already has `v1.0.0` in git history.
- Keep semantic versioning monotonic from the latest released tag and current
  project setting; do not reintroduce prerelease `0.x.y` numbering.

## Build Number Rule

- Start build numbers at `1`.
- Increment by `1` for every distributable archive intended for TestFlight or
  App Store upload.
- Also increment by `1` whenever `MARKETING_VERSION` changes.
- Do not decrease build numbers once a build has been uploaded to App Store
  Connect for the same bundle/version context.

## Bump Selection

Choose the smallest bump that honestly describes the user-visible release.

- Patch: bug fixes, crash fixes, localization/copy fixes, small UI polish,
  performance improvements, non-breaking internal fixes, release metadata.
- Minor: new user-visible features, meaningful UX flow changes, monetization or
  subscription behavior changes, new settings, new map/event capabilities, new
  onboarding or notification behavior.
- Major: first public release `1.0.0`, a large product repositioning, broad
  platform/data compatibility changes, or a change that intentionally makes old
  persisted/server data incompatible without migration.

For `0.x.y` prerelease versions, compatibility can still move faster than after
`1.0.0`, but keep the same bump vocabulary so release history stays readable.

## Helper

Use the helper from the repo root:

```sh
Skills/GitFlow/ios-git-flow/scripts/bump-ios-version.sh \
  --version 0.0.1 \
  --build 1 \
  --project Alike/Alike.xcodeproj/project.pbxproj \
  --check
```

Use `--apply` only when the user asked to make the version change.

## Apple References

- Version number: https://developer.apple.com/help/glossary/version-number/
- CFBundleVersion: https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleversion
- Upload builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
