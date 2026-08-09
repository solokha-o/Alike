# Package Versioning

Alike currently uses `Packages/*` as internal path-based SwiftPM modules.
They are part of the app release, not independently shipped products.

## Current Policy

- Do not add separate package versions for normal app work.
- Do not change `// swift-tools-version` as a release/version bump. That line is
  a SwiftPM tooling requirement, not the package product version.
- Package changes influence the app version according to
  `references/app-versioning.md`.

## App Bump From Package Changes

- Patch: internal package bug fixes, small UI component polish, localization
  fixes, performance work, dependency wiring fixes.
- Minor: package changes that expose new user-visible app capabilities or change
  monetization/settings/map/onboarding behavior.
- Major: package changes that intentionally break persisted data compatibility,
  server contracts, or broad app architecture in a release-visible way.

## When To Version Packages Separately

Introduce package tags only if a package becomes a separately consumed artifact,
for example another repository depends on it by git URL or it is distributed as
an SDK.

If that happens, use a dedicated tag namespace:

```text
package/<Name>/vX.Y.Z
```

Keep app release tags in the top-level `vX.Y.Z` format so app changelog
generation can ignore package-only tags.
