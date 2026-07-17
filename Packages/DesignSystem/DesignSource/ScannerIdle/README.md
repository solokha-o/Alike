# ALI Scanner Idle Assets

The four contextual Scanner Home idle scenes use the same square coordinate
space and must render the static PNG and optional Lottie overlay in one `ZStack`.

| State | Runtime stem | Static story | Overlay accent |
| --- | --- | --- | --- |
| `ready` | `ALIScannerIdleReady` | Curious ALI holding the magnifier | Magnifier glint |
| `hasReviews` | `ALIScannerIdleHasReviews` | ALI presenting a photo stack | Photo highlight |
| `allCaughtUp` | `ALIScannerIdleAllCaughtUp` | Relaxed seated ALI | Calm sparkle |
| `libraryChanged` | `ALIScannerIdleLibraryChanged` | Surprised ALI with a new photo | Notice pulse |

## Export and alignment rules

- Logical canvas: `418 × 418` points/pixels at 1×.
- Runtime PNG exports: `418 × 418`, `836 × 836`, and `1254 × 1254`.
- Source masters: transparent `1254 × 1254` PNGs under the sibling
  `ScannerIdle*` design-source directories.
- Lottie canvas: `418 × 418`, 30 fps, short seamless loops.
- Use aspect fit for both layers with identical frames and no independent offset.
- Set the overlay to `allowsHitTesting(false)`.
- With Reduce Motion enabled, or if overlay loading fails, omit the overlay. The
  static image is complete by itself.

## iOS lookup

Use `ALIAssets.scannerIdleURL(for:scale:)` for the static image and
`ALIAssets.scannerIdleOverlayURL(for:)` for the optional animation. State
resolution and Scanner layout belong to the consuming Scanner feature.

The images were generated with the built-in image generation workflow from the
approved ALI production renders, then chroma-keyed to transparent PNG masters.
