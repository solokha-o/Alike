# iPad Definition of Done: before and after

The DoD of the iPad card asks for each audit screen before and after, on iPad 11"
and 13", portrait and landscape, light and dark. This folder fills the cells that
`../baseline/`, `../audit/` and `../after-pr4/` did not have.

- Devices: iPad Pro 11-inch (M5), 834 × 1210 pt, and iPad Pro 13-inch (M5),
  1032 × 1376 pt, iPadOS 27.2. These are the same simulators as `../baseline/`.
- "Before" is compatibility mode: the iPhone-only build, as Release users see it
  today. "After" is native mode on `develop` with PR 1–4 and PR 6 (`79fd64b2`).
- Data: the DEBUG fake library. Images are 1× (half the device pixels).
- Native mode came from `xcodebuild` arguments, as in `../audit/README.md`. The
  project still targets iPhone until PR 5.

## Screens

Each set has the 18 files of `FakeLibraryScreenCaptureTests`:

| Audit screen | File |
|---|---|
| Launch | `launch` |
| Welcome «Photo Access Required» | `welcome-no-photos-access` |
| Scanner | `scanner-empty`, `scanner-manyClusters` |
| Cleanup: group list and categories (Smart Cleanup card) | `cleanup-manyClusters`, `cleanup-largeCluster-premium`, `cleanup-afterCleanup` |
| Cleanup: history | `cleanup-history` |
| Cleanup: empty | `cleanup-empty` |
| Details: ClusterDetails | `details-largeCluster` |
| Details: comparison (unreviewed group) | `details-oneCluster` |
| Details: Best Shot celebration | `details-best-shot-celebration` |
| Details: fullscreen zoom | `details-fullscreen` |
| Settings | `settings-free`, `settings-premium` |
| Paywall (as shipped, «Пейвол 0») | `paywall` |
| User Guide: hub and topic | `user-guide`, `user-guide-topic` |

## Matrix

| Cell | iPad 11" | iPad 13" |
|---|---|---|
| before · portrait · light | `../baseline/ipad-11/` | `../baseline/ipad-13/` |
| before · portrait · dark | `before/ipad-11-portrait-dark/` | `before/ipad-13-portrait-dark/` |
| before · landscape · light | `before/ipad-11-landscape-light.png` (see below) | `before/ipad-13-landscape-light.png` |
| before · landscape · dark | `before/ipad-11-landscape-dark.png` | `before/ipad-13-landscape-dark.png` |
| after · portrait · light | `after/ipad-11-portrait-light/` | `after/ipad-13-portrait-light/` |
| after · portrait · dark | `after/ipad-11-portrait-dark/` | `after/ipad-13-portrait-dark/` |
| after · landscape · light | `after/ipad-11-landscape-light/` | `after/ipad-13-landscape-light/` |
| after · landscape · dark | `after/ipad-11-landscape-dark/` | `after/ipad-13-landscape-dark/` |

Before, landscape: compatibility mode supports portrait only. When the iPad turns,
the app keeps the same portrait iPhone window in the middle of the screen, so each
screen looks as in the portrait set. The capture test cannot draw this case: the
app scene stays portrait, and the test refuses a capture in the wrong
orientation. The 4 PNGs in `before/` are full-screen simulator screenshots of the
app in landscape (`-AlikeFakeLibrary manyClusters`), as evidence of that window.

## Widgets on iPad

`widgets/`: iPad Pro 11" with the native build, Home Screen and Lock Screen. The
App Group snapshot was written by hand (55 groups, 12 reviewed, 2.5 GB), as in
the widget note: terminate the app, write `widget-snapshot.json`, `simctl install`
without a launch.

| Widget | Family | Result |
|---|---|---|
| Alike (status) | `systemSmall` | Renders the snapshot, portrait and landscape, light and dark |
| Alike (status) | `systemMedium` | Renders the snapshot, portrait and landscape, light and dark |
| Alike Library | `systemMedium` | Renders the snapshot, portrait and landscape, light and dark |
| Alike (status) | `accessoryRectangular`, `accessoryCircular` | Render on the iPad Lock Screen (portrait, dark) |
| Alike (status) | `systemExtraLargePortrait` | Not offered: the iPad widget gallery lists only small and medium |
| Alike (status) | `accessoryInline` | Not checked |

A tap on the small widget opens the app in the full-screen native window. The
status widget declares no `systemLarge` or `systemExtraLarge`, so iPad users get
no large Alike widget. This is a product gap, not a defect.

## Regenerate

Follow `../audit/README.md`. Additions:

- "Before" needs an iPhone-only build in its own DerivedData folder. Since
  1.8.0 the project targets iPad, so pass `TARGETED_DEVICE_FAMILY=1` and leave
  out the iPad orientations. "After" uses the default build.
- Erase the simulator between the compatibility and the native run. Otherwise
  iPadOS can reopen the app in the iPhone-shaped window it remembered.
- After an erase and boot, detach and attach the simulator panel again before
  you rotate. A rotate sent to a stale panel does nothing, and the test then
  fails with "The simulator is not in landscape".
- The test saves device pixels (2×). Halve each PNG to get the 1× files here
  (`../baseline/` keeps 2×):

  ```bash
  for f in <output>/*/*.png; do
    w=$(sips -g pixelWidth "$f" | awk 'END {print $2}')
    sips --resampleWidth $((w / 2)) "$f" --out "$f" >/dev/null
  done
  ```
