# ALI Comparison Review Asset

The static character and optional Lottie overlay share a square coordinate
space and must be rendered with identical frames in a `ZStack`.

- Logical canvas: `418 × 418` points/pixels at 1×.
- Runtime PNG exports: `418 × 418`, `836 × 836`, and `1254 × 1254`.
- Lottie canvas: `418 × 418`, 30 fps, 60 frames (2-second one-shot accent).
- Alignment: aspect fit both layers without independent padding or offsets.
- Motion: the left card focus leads into the right card focus while a small
  mint accent travels between them; no character or photo content is animated.
- Interaction: the overlay must not participate in hit testing.
- Reduce Motion/failure fallback: omit the overlay; the static pose remains complete.

`ALIComparisonReview-source.png` is the transparent production source. Runtime
exports live under `Sources/DesignSystem/Resources/ComparisonReview`.
