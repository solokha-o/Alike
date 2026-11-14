# 0005. iPad layout: one navigation stack, a readable column, width-based grids

- Status: Proposed
- Date: 2026-11-14
- Supersedes: none

## Context

Alike is iPhone-only today (`TARGETED_DEVICE_FAMILY = 1`), and iPad runs it in
compatibility mode. The iPad card asks for native iPad support. The audit in
PR 2 ([captures](../images/ipad/audit/), table in the iPad card) found 2 layout
problems in native mode:

1. Cleanup, History, Details, Settings, the user guide and the "Photo Access
   Required" screen stretch to the full window: up to 1376 pt on a 13-inch iPad
   in landscape. Only Scanner (620 pt), the paywall (620 pt) and the onboarding
   pages (560 pt) keep a narrower column.
2. Photo grids use 2 to 5 columns in regular width, default 4, whatever the
   width. Tiles reach 330 pt; a 13-inch iPad in landscape shows 1 row.

The card also asks whether Cleanup → Details should become a
`NavigationSplitView` (group list on the left, group on the right).

## Decision

We keep 1 `NavigationStack` per tab on iPad, as on iPhone, and we fit the
content to the width with 2 shared metrics in `DesignSystem/Layout/`:

- **Readable column.** `dsReadableContentWidth()` limits a column of cards,
  lists or text to `ReadableContentWidth.maximum` (720 pt), centred, in regular
  width. In compact width it does nothing, so iPhone layout does not change.
  PR 4 applies it screen by screen.
- **Width-based grids.** In regular width the column range comes from the
  container width, so each tile stays between 150 and 320 pt after the screen's
  padding (32 pt) and gaps (12 pt). The default aims at 200 pt tiles: 4 columns
  at 820–834 pt, 5 at 1024 and 1180 pt, 6 at 1376 pt. The app measures the
  width once per window and once per sheet with `dsMeasuresPhotoGridWidth()`.
  Compact width keeps 1–2 columns.
- The user's regular-width column choice (`photoGrid.columns.regular`) keeps its
  meaning, a preferred count, clamped to the range of the current width. No
  shipped build wrote this key: iPhone is portrait-only and iPad ran in an
  iPhone-sized window.

## Alternatives

- **`NavigationSplitView` for Cleanup → Details.** Rejected for the first iPad
  release. Review is a sequence: open a group, decide, go back, take the next.
  A split view needs a selection model for `RoutedNavigationStack`, a compact
  fallback that behaves like today, and changes in `CleanupView` and
  `ClusterDetailsView`, which are already above their SwiftLint length baselines.
  The risk is high for an iPad share we do not know yet. Revisit after the
  release, with the iPad cohort data from App Store Connect.
- **`GridItem(.adaptive(minimum:))` grids.** Rejected: it drops the column choice
  users already have in the toolbar.
- **A fixed `maxWidth` per screen.** Rejected: 1 shared value is easier to tune
  and review than 6 separate numbers.

## Consequences

- PR 4 applies the readable column per screen. It does not need a new layout per
  screen.
- A new screen with cards or text uses `dsReadableContentWidth()`. A new photo
  grid reads `PhotoGridColumnPreference` and sits under a view that has
  `dsMeasuresPhotoGridWidth()` (the tab view and the screenshot sheet in
  `RootView` today).
- A reviewer checks that iPhone (compact) layout does not change: both metrics
  must do nothing in compact width.
- Split View and Slide Over give the app a compact width, so it gets the iPhone
  layout there.

## Status

Proposed. Change to `Accepted` when the pull request merges.
