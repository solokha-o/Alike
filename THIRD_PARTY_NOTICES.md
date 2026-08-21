# Third-Party Notices

Alike's [PolyForm Noncommercial License 1.0.0](LICENSE) applies to the
original source code of this project.

This repository also contains two categories of content that are **not**
covered by that source-code license:

1. **Third-party dependencies and upstream-generated content** — governed by
   their own upstream licenses, unaffected by Alike's terms. See the sections
   below.
2. **Alike-authored generated assets** (rendered screenshots, App Store
   visuals, and similar output produced from this project) — governed by
   [`NOTICE.md`](NOTICE.md)'s asset terms, not by upstream licenses and not
   by the PolyForm Noncommercial License.

## Lottie

`Packages/DesignSystem` depends on
[`airbnb/lottie-spm`](https://github.com/airbnb/lottie-spm), the Swift
Package distribution of Lottie for iOS. Lottie is distributed under the
Apache License 2.0; consult the dependency repository for its complete
notices and license text. (This governs the Lottie *library*; the `.json`
animation files authored for Alike under
`Packages/DesignSystem/Sources/DesignSystem/Resources/` are Alike-authored
assets covered by category 2 above and by `NOTICE.md`, not by Lottie's
license.)

## Apple frameworks

Alike uses Apple system frameworks including SwiftUI, Vision, PhotoKit, Core
Data, StoreKit, and User Notifications under the terms of Apple's SDK
agreements.

## Local Swift packages

The original source-code files of every module under `Packages/` are
project code covered by this repository's PolyForm Noncommercial License.
This does **not** extend to the non-source visual assets carried inside
`Packages/DesignSystem` (PNG illustrations, Lottie `*Overlay.json` files, and
`DesignSource/*-source.png` masters), which are excluded from the
source-code license under `NOTICE.md`; see that document's asset-path list
for the exact scope of the exclusion.

Add an entry above when a new third-party dependency is introduced.

This notice is informational and does not replace the license files supplied
by upstream projects.
