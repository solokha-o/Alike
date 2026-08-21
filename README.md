# 📸 Alike

**Find visually similar photos in your library**

Alike is an iOS app that finds and groups visually similar photos using Computer Vision (Apple Vision framework). Every scan runs on your device — no account, no uploads.

[![Download on the App Store](https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us)](https://apps.apple.com/app/id6798399598)

## ✨ Features

- 🔍 **Vision-based analysis** — uses `VNFeaturePrintObservation` for accurate comparisons
- 🎯 **Sensitivity levels** — 3 accuracy modes (Low/Medium/High)
- 🧭 **Guided cleanup review** — review each cluster with clear, step-by-step actions
- ⭐ **Best Shot detection** — deterministic pick of the strongest photo in each cluster
- ✅ **Quick cleanup actions** — Keep Best Only, Select All Except Best, and Clear Selection
- 🏷️ **Review badges and states** — Not reviewed, In review, Reviewed, and Needs review after rescans
- 🧹 **Smart categories** — screenshot cleanup and blurred-photo cleanup alongside similar-photo clusters *(Pro)*
- 📈 **Cleanup session progress** — track reviewed clusters, selected items, and estimated savings
- 🕓 **History and insights** — every completed cleanup recorded locally, grouped by month
- ⏰ **Cleanup reminders** — optional local notifications, on your own schedule *(custom schedules are Pro)*
- 📖 **In-app user guide** — searchable topics, one tap from the Scanner toolbar
- 💾 **Persistent review state** — selection and review progress are saved locally between app launches
- 📊 **Adaptive grid** — 1 to 2 columns on iPhone, remembered between screens and launches
- 💾 **CoreData caching** — stores scan results, with PhotoKit change history driving rescan prompts
- 🔒 **On-device by design** — no analytics, no tracking, no photo ever leaves the device
- 🎨 **Teal design** — modern UI with animations and haptic feedback
- 🌍 **Two languages** — Ukrainian and English
- 🌓 **Dark Mode** — full support

## 🆕 What ships in 1.0.0

The first public release, now live on the App Store. What it includes:

- Similar-photo scanning with Vision feature prints, three sensitivity levels, and complete-link clustering.
- Guided Cleanup Review in cluster details, with Best Shot picked for you and a selection-first flow.
- Quick bulk actions: Keep Best Only, Select All Except Best, and Clear Selection.
- Persistent cluster review states, so progress is restored after relaunch.
- Cleanup session progress summary with selected count and estimated storage savings.
- Scanner badges and the "Needs review" resurfacing flow after library changes and rescans.
- Cleanup history, monthly insights, and optional cleanup reminders.
- **Alike Free**: 3 scans per month. **Alike Pro**: unlimited scans, batch cleanup, screenshot and blurred-photo cleanup, advanced filters, and custom cleanup reminders.

## 🔒 Privacy

Alike makes no network requests. Photos, feature prints, scan results and cleanup history stay in the app's own storage on the device; deletion goes through PhotoKit into **Recently Deleted**, so nothing is removed without the system's own confirmation. There is no account, no analytics SDK, and no advertising SDK in the binary.

- [Privacy Policy](https://alikeapp.github.io/privacy/) · [Terms of Use](https://alikeapp.github.io/terms/) · [Support](https://alikeapp.github.io/support/)
- Ukrainian: [Політика конфіденційності](https://alikeapp.github.io/uk/privacy/) · [Умови використання](https://alikeapp.github.io/uk/terms/)
- Source copy for both lives in [`Docs/legal/`](Docs/legal/).

## 🧠 Similarity algorithm

1. **Image fingerprint**: each photo gets a Vision feature print.
2. **Pre-filter**: only photos close in capture time and location are compared; screenshots are excluded.
3. **Similarity metric**: compute distance between two feature prints; **smaller distance = more similar**.
4. **Sensitivity threshold**: Low/Medium/High define the maximum distance for similarity.
5. **Clustering** (complete‑link): a photo joins a group only if it is similar to **all** photos in that group.
6. **Result**: clusters are shown as tiles with the first photo as a preview.

## 🏗️ Architecture

Modular SwiftUI architecture with Swift Packages:

```
Alike/
├── Core/                    # Models, Protocols, Extensions
├── Storage/                 # CoreData persistence
├── PhotoAnalysis/           # Vision framework + clustering
├── DesignSystem/            # Theme, Typography, Components
├── NavigationKit/           # Shared navigation primitives
├── Launch/                  # Splash screen
├── Welcome/                 # Onboarding & permissions
├── Scanner/                 # Scan lifecycle, allowance, and scan admission
├── Cleanup/                 # Review queue, smart cleanup, deletion, and history
├── Purchases/               # StoreKit subscriptions, entitlements, paywalls
├── UserGuide/               # In-app guide catalog, hub and topics
├── Settings/                # Configuration
└── Details/                 # Cluster details
```

## 🛠 Tech stack

- **Platform**: iOS 17+ (iPhone only)
- **Language**: Swift 6.0 (Strict Concurrency)
- **UI**: SwiftUI
- **Frameworks**:
  - Vision (analysis)
  - Photos (PhotoKit — library access, change history, deletion)
  - CoreData (caching)
  - StoreKit 2 (subscriptions, entitlements, and the review prompt)
  - User Notifications (cleanup reminders)
- **Dependency**: [Lottie](https://github.com/airbnb/lottie-spm) via SwiftPM — see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
- **Architecture**: MVVM + Swift Packages
- **Async**: async/await, Actors

## 🚀 Installation

1. **Clone the repository**
```bash
git clone https://github.com/solokha-o/Alike.git
cd Alike
```

2. **Open in Xcode**
```bash
open Alike/Alike.xcodeproj
```

3. **Build & Run** (⌘R)

## 🧾 Schemes and logging

There are three shared schemes:

- `Alike` — builds and runs **Release** with no debugger attached and no local StoreKit configuration, so ⌘R gives the same build the App Store gets. Normal logging (info/errors only). Its Test action stays on Debug, because the test targets need the `#if DEBUG` mocks in `Packages/Core/Sources/Core/Mocks`.
- `Alike-VerboseLogs` — Debug build with verbose logging for scan/vision/storage via `OS_ACTIVITY_MODE=debug`.
- `Alike-DebugVerboseLogs` — Debug build with verbose logging, profiled and analyzed in Debug too.

Use one of the verbose schemes for anything that needs a debugger, the debug menu, the premium overrides, or local StoreKit transactions — all of those are compiled out of `Alike`.

## 📱 User flow

1. **Launch Screen** (3 sec) → 📸 animation
2. **Welcome Screen** → photo permission request
3. **Main TabView**:
   - **Scanner Tab**: start and monitor scans, retry failures, open cleanup results, and reach the user guide from the **How to Use** toolbar button
   - **Cleanup Tab**: continue review, browse smart categories and clusters, confirm cleanup, and view history
   - **Settings Tab**: configuration, subscription, reminders, legal links, and support

Scanning continues while you move between tabs. A completed scan refreshes the
Cleanup tab without automatically changing the selected tab.

## 🎨 Design

- **Accent Color**: Teal (#1F9EB8), defined in `DesignSystem/Theme.swift`
- **Typography**: SF Rounded
- **Spacing**: 8pt grid system
- **Animations**: Spring-based
- **Haptics**: Sensory Feedback API

## 🧪 Testing

Tests live in the package that owns the code and run with Swift Testing. The four
fastest suites, the ones `tools/quick` runs:

```bash
swift test --package-path Packages/Cleanup
swift test --package-path Packages/Scanner
swift test --package-path Packages/Settings
swift test --package-path Packages/UserGuide
```

`tools/full` runs every package that has tests, plus the app compile gate.
`Packages/Storage` is the one exception — SwiftPM does not compile its
`.xcdatamodeld`, so its suite runs in Xcode and its code is covered by the compile
gate instead. See [`Docs/ci-cd.md`](Docs/ci-cd.md).

SwiftUI `#Preview` blocks accompany the screens in each feature package; use one of
the verbose Debug schemes for previews and the debug menu.

## 🚦 CI/CD

Local validation and App Store delivery run through the wrappers in `tools/`:

```bash
tools/quick
```

```bash
tools/full
```

`tools/quick` runs whitespace checks, the four package suites above, and App Store
metadata bundle validation. `tools/full` adds every remaining package and the app
compile gate. Release preflight, metadata upload, and TestFlight upload live behind
`tools/release-check`, `tools/upload`, and `tools/upload-build`.

See [`Docs/ci-cd.md`](Docs/ci-cd.md) for the full runbook, required environment
variables, and the safety rules that keep uploads deliberate.

## 📝 Localization

Languages via `Localizable.xcstrings`:
- 🇬🇧 English (base)
- 🇺🇦 Ukrainian

## 🤝 Contributing

Contributions are welcome.

### Ways to contribute

- Open a **GitHub Issue** for:
  - bug reports
  - feature requests
  - UX or product proposals
- Submit a **Pull Request** with code, tests, or documentation improvements.
- Share cleanup-flow ideas and edge cases (for example, tricky photo-library scenarios) through Issues.

### Before opening an issue

- Search existing issues to avoid duplicates.
- Use a clear title and include context.
- For bugs, include:
  - expected behavior
  - actual behavior
  - steps to reproduce
  - device + iOS version

### Pull request guidelines

- Base feature work on `develop` and keep PRs focused.
- Use clear, English commit messages.
- Add or update tests when behavior changes.
- Update docs/README if user-facing behavior changes.

If GitHub Discussions are enabled later, product ideas and broader proposals can also be posted there. Until then, please use Issues.

## 👨‍💻 Contact

- Email: oleksandr.solokha@gmail.com
- Support: [alikeapp.github.io/support](https://alikeapp.github.io/support/)
- App Store: [Alike on the App Store](https://apps.apple.com/app/id6798399598)

## 📄 License

[MIT](LICENSE) © 2026 Oleksandr Solokha. Third-party components are covered by
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

---

Made with ❤️ using Swift & SwiftUI
