# Animated Static Hero

Use this pattern when an approved raster illustration must feel alive during a
loading, scanning, reviewing, cleanup, or success state without making the
character dependent on animation playback.

## Core composition

1. Keep a complete PNG as the authoritative visual.
2. Add a transparent, project-owned Lottie overlay on the same coordinate
   canvas for decorative effects such as scan lines, glints, particles,
   candidate cards, or success accents.
3. Compose both layers with `AnimatedImageOverlay` from DesignSystem.
4. Bind overlay presence to feature state, view visibility, and
   `scenePhase == .active`.
5. Keep progress and business state independent from Lottie timing.

The static layer must still communicate the full scene when Lottie fails to
load, Reduce Motion is enabled, or the app is inactive.

## Existing implementation

- Composition primitive:
  `Packages/DesignSystem/Sources/DesignSystem/Components/AnimatedImageOverlay.swift`
- Typed asset access:
  `Packages/DesignSystem/Sources/DesignSystem/AlikeAssets.swift`
- Scanner example:
  `Packages/Scanner/Sources/Scanner/ScannerView.swift`
- Scanner resources:
  `Packages/DesignSystem/Sources/DesignSystem/Resources/ScannerSearching/`
- Resource and parsing tests:
  `Packages/DesignSystem/Tests/DesignSystemTests/AlikeAssetsTests.swift`
  and `AnimatedImageOverlayTests.swift`

## Component shape

Keep feature-state ownership outside the hero. The focused hero component may
own only presentation environment and visibility state.

```swift
private struct FeatureAlikeHero: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        AnimatedImageOverlay(
            animationURL: playsOverlay ? overlayURL : nil,
            aspectRatio: 1,
            maximumWidth: 260,
            playback: .loop,
            ambientMotion: .breathe
        ) {
            staticImage
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(appLocalized("Alike status description")))
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private var playsOverlay: Bool {
        isVisible && scenePhase == .active
    }
}
```

Use `.breathe` only when character motion supports the state. Use `.none` for
focused review, destructive confirmation, or any scene where ambient movement
would distract from the primary decision.

## Playback truth table

| Feature state | Scene phase | Visible | Static image | Lottie overlay |
|---|---|---:|---:|---:|
| Active target state | Active | Yes | Shown | Playing unless Reduce Motion |
| Active target state | Inactive/background | Yes | Shown | Removed |
| Active target state | Active | No | Not rendered or static | Removed |
| Any other state | Any | Any | Absent | Absent |

Prefer removing the optional animation URL over introducing timers, polling,
or playback state in a feature view model. State transitions should remove the
hero naturally through the parent view's state switch.

### Bounded celebration loops

Some success effects, including the Details Best Shot celebration, are authored
as seamless loops shown by a bounded one-shot reaction cue. For these effects:

- Keep `OverlayAnimationPlayback.loop`; the cue lifecycle owns the presentation
  duration and removes the view when the celebration is complete.
- Gate the animation URL on view visibility and `scenePhase == .active`, so the
  loop cannot continue offscreen or in the background.
- Keep deterministic cue consumption or dismissal coverage in the feature.
- Do not "correct" the playback mode to `.once`. A one-shot reaction cue and a
  looping Lottie overlay are intentionally different concerns.

Current policy example:
`Packages/Details/Sources/Details/AlikeBestShotCelebrationView.swift`.

## Asset rules

- Store the PNG exports and JSON together under a named DesignSystem resource
  subdirectory.
- Provide 1×, 2×, and 3× PNGs and select them through `displayScale`.
- Add typed URL access in `AlikeAssets`; feature code must not repeat filenames or
  perform raw bundle lookup.
- Use the same width, height, and visual alignment for the PNG and Lottie JSON.
- Keep the Lottie transparent and decorative. Do not duplicate the complete
  character in JSON.
- Prefer simple vector shape layers and a short seamless loop. Avoid embedded
  raster assets, expressions, fonts, network dependencies, and licensed
  third-party animation files.
- Motion must explain the current state. Examples: photo candidates and a scan
  pulse for analysis, comparison markers for review, sorting motion for
  cleanup, and restrained accents for success.

## Accessibility and layout

- Mark the decorative Lottie layer hidden from accessibility and disable hit
  testing. `AnimatedImageOverlay` already enforces this.
- Expose the composite as one accessibility element with localized EN/UK copy.
- Preserve VoiceOver order for adjacent progress, status, and actions.
- Bound hero width conservatively and use a scroll-safe container when large
  Dynamic Type or compact height can clip the rest of the state UI.
- Do not add a custom Reduce Motion branch in the feature. The shared component
  omits Lottie and ambient motion while retaining the static image.

## Reuse workflow

1. Define the state-specific motion story before creating layers.
2. Produce the complete static PNG exports and a transparent overlay on one
   shared canvas.
3. Add typed accessors and resource parsing coverage in DesignSystem.
4. Create a small feature-local hero component and gate overlay playback by
   state, visibility, and scene phase.
5. Add localized accessibility copy.
6. Test state entry, progress independence, success, and failure at the view
   model boundary without asserting Lottie internals.
7. Verify Reduce Motion, background/foreground, offscreen navigation, compact
   height, large Dynamic Type, and light/dark appearance in Simulator.
8. Run affected package tests and the repository-required full app compile.

## Avoid

- A full-character Lottie as the only visual source of truth.
- Generic loading spinners that do not explain the feature state.
- Starting animation from progress callbacks.
- Playback that continues after navigation, completion, error, or backgrounding.
- Fixed full-screen hero heights that crowd progress or actions.
- Importing community Lottie files without explicit license review and asset
  provenance.
