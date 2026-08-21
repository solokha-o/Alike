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

## Vendored skills

`Skills/External/` contains agent-skill content vendored from other people's
repositories at a pinned commit, tracked in
`Skills/External/external-skills.tsv`. This content is owned by its
respective upstream authors and governed by each upstream's own license, not
by Alike's PolyForm Noncommercial License; see `Skills/External/LICENSE` and
`NOTICE.md`.

| Directory | Upstream repo | License | Copyright holder | Pinned SHA |
| --- | --- | --- | --- | --- |
| `swiftui-expert-skill` | [`solokha-o/SwiftUI-Agent-Skill`](https://github.com/solokha-o/SwiftUI-Agent-Skill) | MIT | Antoine van der Lee | `f06d1437a3fbec7df6cdce93f77004e5409b31ee` |
| `swift-concurrency` | [`AvdLee/Swift-Concurrency-Agent-Skill`](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) | MIT | Antoine van der Lee | `0d472de78225d2875283c35eaca1c060c493bdb3` |
| `core-data-expert` | [`AvdLee/Core-Data-Agent-Skill`](https://github.com/AvdLee/Core-Data-Agent-Skill) | MIT | Antoine van der Lee | `855ca7d0df50e82b00c12881dd9cd23c19ef5f49` |
| `swift-testing-expert` | [`AvdLee/Swift-Testing-Agent-Skill`](https://github.com/AvdLee/Swift-Testing-Agent-Skill) | MIT | Antoine van der Lee | `798e9b1a2bcac164d4f0c781908199e754f0bab6` |
| `emilkowalski-skills` | [`emilkowalski/skills`](https://github.com/emilkowalski/skills) | MIT | Emil Kowalski | `6bf24434f7730ad169077756cf9c7cd7bd675fc6` |

Each directory's `LICENSE` file is the exact license text from its upstream
repository at the pinned commit.

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
