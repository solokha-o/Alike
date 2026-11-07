# Settings

The settings screen: sensitivity, grid, cleanup reminder, subscription, local data, and language.
It also has the Best Shot learning reset and the debug labelling tool that exports a calibration corpus.

- **Category:** Feature (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Show and change user preferences and app data actions.
- **Main public types:** `SettingsView`, `SettingsViewModel`, `BestShotCalibrationLabelingView`, `BestShotCalibrationLabelingViewModel`, `SettingsL10n`
- **Depends on:** Core, DesignSystem, Diagnostics, NavigationKit, PhotoAnalysis, Purchases, Storage, UserGuide
- **Does not do:** Store preferences itself (Storage) or run calibration sweeps (BestShotCalibration).
