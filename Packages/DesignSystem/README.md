# DesignSystem

Shared UI tokens and components for every screen.
It holds spacing, corner radius, animations, buttons, photo grid layout, and the Alike mascot reaction view.
Lottie plays the mascot animations.

- **Category:** Foundation (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Give one visual language to all feature packages.
- **Main public types:** `Spacing`, `CornerRadius`, `Animations`, `PrimaryButton`, `AlikeReactionView`, `PhotoGridColumnsPicker`
- **Depends on:** Core; remote: `lottie-spm` (airbnb)
- **Does not do:** Contain feature logic, navigation, or data access.
