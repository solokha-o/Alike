# Alike Scanner Idle Assets

The four contextual Scanner Home idle scenes use the same square coordinate
space and must render the static PNG and optional Lottie overlay in one `ZStack`.

| State | Runtime stem | Static story | Overlay accent |
| --- | --- | --- | --- |
| `ready` | `AlikeScannerIdleReady` | Curious Alike holding the magnifier | Magnifier glint |
| `hasReviews` | `AlikeScannerIdleHasReviews` | Alike presenting a photo stack | Photo highlight |
| `allCaughtUp` | `AlikeScannerIdleAllCaughtUp` | Relaxed seated Alike | Calm sparkle |
| `libraryChanged` | `AlikeScannerIdleLibraryChanged` | Surprised Alike with a new photo | Notice pulse |

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

Use `AlikeAssets.scannerIdleURL(for:scale:)` for the static image and
`AlikeAssets.scannerIdleOverlayURL(for:)` for the optional animation. State
resolution and Scanner layout belong to the consuming Scanner feature.

The images were generated with the built-in image generation workflow from the
approved Alike production renders, then chroma-keyed to transparent PNG masters.
