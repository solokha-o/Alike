# 📸 Alike

**Find visually similar photos in your library**

Alike - iOS додаток для пошуку та групування візуально схожих фотографій за допомогою технології Computer Vision (Apple Vision framework).

## ✨ Особливості

- 🔍 **Vision-based аналіз** - використання VNFeaturePrintObservation для точного порівняння
- 🎯 **Налаштована чутливість** - 3 рівні точності пошуку (Low/Medium/High)
- 📊 **Адаптивна сітка** - від 2 до 8 стовпців (залежно від пристрою)
- 💾 **CoreData кешування** - збереження результатів сканування
- 🎨 **Індиго дизайн** - сучасний UI з анімаціями та haptic feedback
- 🌍 **Дві мови** - Українська та Англійська
- 🌓 **Темна тема** - повна підтримка Dark Mode
- 📱 **iPad підтримка** - оптимізований для планшетів

## 🏗️ Архітектура

Модульна SwiftUI архітектура з Swift Packages:

```
Alike/
├── Core/                    # Models, Protocols, Extensions
├── Storage/                 # CoreData persistence
├── PhotoAnalysis/           # Vision framework + clustering
├── DesignSystem/            # Theme, Typography, Components
├── Launch/                  # Splash screen
├── Welcome/                 # Onboarding & permissions
├── Scanner/                 # Analysis & results
├── Settings/                # Configuration
└── Details/                 # Cluster details
```

## 🛠 Технології

- **Platform**: iOS 17+, iPadOS 17+
- **Language**: Swift 6.0 (Strict Concurrency)
- **UI**: SwiftUI
- **Frameworks**: 
  - Vision (аналіз)
  - Photos (PhotoKit)
  - CoreData (кешування)
  - StoreKit (відгуки)
- **Architecture**: MVVM + Swift Packages
- **Async**: async/await, Actors

## 🚀 Встановлення

1. **Клонувати репозиторій**
```bash
git clone <repository-url>
cd Alike
```

2. **Відкрити в Xcode**
```bash
open Alike/Alike.xcodeproj
```

3. **Додати Swift Packages** (див. SETUP.sh)
   - File → Add Package Dependencies → Add Local...
   - Додати всі пакети з `Packages/` папки

4. **Build & Run** (⌘R)

## 📱 User Flow

1. **Launch Screen** (3 sec) → 📸 анімація
2. **Welcome Screen** → запит дозволу на фото
3. **Main TabView**:
   - **Scanner Tab**: сканування → результати → деталі
   - **Settings Tab**: налаштування + підтримка

## 🎨 Дизайн

- **Accent Color**: Індиго (#5C66F2)
- **Typography**: SF Rounded
- **Spacing**: 8pt grid system
- **Animations**: Spring-based
- **Haptics**: Sensory Feedback API

## 🧪 Тестування

Previews для всіх екранів:
```swift
#Preview("Scanner") { ScannerView(...) }
#Preview("Settings") { SettingsView(...) }
#Preview("Dark Mode") { ... }
```

Unit tests в кожному package:
```bash
swift test --package-path Packages/Core
swift test --package-path Packages/Storage
```

## 📝 Локалізація

Підтримка мов через `Localizable.xcstrings`:
- 🇬🇧 English (базова)
- 🇺🇦 Українська

## 🔐 Permissions

Required в Info.plist:
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription`

## 📦 Bundle ID

`com.solokhao.alike`

## 👨‍💻 Контакт

- Email: oleksandr.solokha@gmail.com
- App Store: (coming soon)

## 📄 Ліцензія

Proprietary - All rights reserved

---

Made with ❤️ using Swift & SwiftUI
