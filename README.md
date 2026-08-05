# 📸 Alike

**Find visually similar photos in your library**

Alike is an iOS app that finds and groups visually similar photos using Computer Vision (Apple Vision framework).

## ✨ Features

- 🔍 **Vision-based analysis** — uses `VNFeaturePrintObservation` for accurate comparisons
- 🎯 **Sensitivity levels** — 3 accuracy modes (Low/Medium/High)
- 🧭 **Guided cleanup review** — review each cluster with clear, step-by-step actions
- ⭐ **Best Shot detection** — deterministic pick of the strongest photo in each cluster
- ✅ **Quick cleanup actions** — Keep Best Only, Select All Except Best, and Clear Selection
- 🏷️ **Review badges and states** — Not reviewed, In review, Reviewed, and Needs review after rescans
- 📈 **Cleanup session progress** — track reviewed clusters, selected items, and estimated savings
- 💾 **Persistent review state** — selection and review progress are saved locally between app launches
- 📊 **Adaptive grid** — 1 to 2 columns optimized for phone and tablet layouts
- 💾 **CoreData caching** — stores scan results
- 🎨 **Indigo design** — modern UI with animations and haptic feedback
- 🌍 **Two languages** — Ukrainian and English
- 🌓 **Dark Mode** — full support
- 📱 **iPad support** — optimized for tablets

## 🆕 What's New in v1.1.1

- Added Guided Cleanup Review flow in cluster details with Best Shot and selection-first UX.
- Added quick bulk actions: Keep Best Only, Select All Except Best, and Clear Selection.
- Added persistent cluster review states so progress is restored after relaunch.
- Added cleanup session progress summary with selected count and estimated storage savings.
- Added scanner badges and "Needs review" resurfacing flow after library changes and rescans.
- Improved scanner-to-details navigation reliability during cleanup entry.

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
├── Launch/                  # Splash screen
├── Welcome/                 # Onboarding & permissions
├── Scanner/                 # Scan lifecycle, allowance, and scan admission
├── Cleanup/                 # Review queue, smart cleanup, deletion, and history
├── Settings/                # Configuration
└── Details/                 # Cluster details
```

## 🛠 Tech stack

- **Platform**: iOS 17+, iPadOS 17+
- **Language**: Swift 6.0 (Strict Concurrency)
- **UI**: SwiftUI
- **Frameworks**:
  - Vision (analysis)
  - Photos (PhotoKit)
  - CoreData (caching)
  - StoreKit (reviews)
- **Architecture**: MVVM + Swift Packages
- **Async**: async/await, Actors

## 🚀 Installation

1. **Clone the repository**
```bash
git clone <repository-url>
cd Alike
```

2. **Open in Xcode**
```bash
open Alike/Alike.xcodeproj
```

3. **Build & Run** (⌘R)

## 🧾 Logging

There are two shared schemes:

- `Alike` — normal logging (info/errors only).
- `Alike-VerboseLogs` — enables verbose logging for scan/vision/storage via `OS_ACTIVITY_MODE=debug`.

## 📱 User flow

1. **Launch Screen** (3 sec) → 📸 animation
2. **Welcome Screen** → photo permission request
3. **Main TabView**:
   - **Scanner Tab**: start and monitor scans, retry failures, and open cleanup results
   - **Cleanup Tab**: continue review, browse smart categories and clusters, confirm cleanup, and view history
   - **Settings Tab**: configuration, subscription, reminders, and support

Scanning continues while you move between tabs. A completed scan refreshes the
Cleanup tab without automatically changing the selected tab.

## 🎨 Design

- **Accent Color**: Indigo (#5C66F2)
- **Typography**: SF Rounded
- **Spacing**: 8pt grid system
- **Animations**: Spring-based
- **Haptics**: Sensory Feedback API

## 🧪 Testing

Previews for all screens:
```swift
#Preview("Scanner") { ScannerView(...) }
#Preview("Settings") { SettingsView(...) }
#Preview("Dark Mode") { ... }
```

Unit tests run within each package.

```bash
swift test --package-path Packages/Cleanup
swift test --package-path Packages/Scanner
swift test --package-path Packages/Settings
swift test --package-path Packages/UserGuide
```

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
- App Store: (coming soon)

## 📄 License

MIT

---

Made with ❤️ using Swift & SwiftUI
