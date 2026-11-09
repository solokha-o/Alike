# BestShotCalibration

An offline tool that measures the Best Shot ranker against a labelled corpus.
It loads a corpus that the Settings labelling tool exports, sweeps the scoring weights, and writes metric reports.
The `bestshot-calibrate` executable runs it on the Mac. The app does not link this package.

- **Category:** Tool (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Measure Best Shot accuracy and personal-weight results on exported corpora.
- **Main public types:** `CorpusLoader`, `WeightSweep`, `MetricsReport`, `PersonalizationReport`, `ReportWriter`
- **Depends on:** Core
- **Does not do:** Ship in the app, read the photo library, or change the default scoring config by itself.
