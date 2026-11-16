# Fake library (DEBUG)

Use it to see a screen with data on a simulator, where a real scan forms no
groups. The code is in `Alike/Alike/Debug/FakeLibrary/`, under `#if DEBUG`. It
reuses the public mocks from `Packages/Core/Sources/Core/Mocks`.

## Launch arguments

| Argument | Values |
|---|---|
| `-AlikeFakeLibrary` | `empty`, `oneCluster`, `manyClusters` (55 groups), `largeCluster` (32 photos), `afterCleanup`, `noPhotosAccess`, `store` (App Store screenshots) |
| `-AlikeFakePremium` | `YES` or `NO` (default `NO`) |
| `-AlikeFakeOpenURL` | An `alike://` link to follow at launch, as a widget tap does: `alike://cleanup`, `alike://resume`. No "Open in Alike?" prompt, unlike `simctl openurl` |

Example, in the scheme's Arguments tab or with `simctl launch`:

```bash
xcrun simctl launch <udid> com.alike.app -AlikeFakeLibrary manyClusters -AlikeFakePremium YES
```

## Behaviour

- All stores are in-memory mocks. The session writes no Core Data, no JSON in
  Application Support, and no widget snapshot. Delete all data only restarts
  onboarding. Scan counts go to the suite `com.alike.fake-library.scan-usage`,
  emptied at each launch.
- Premium comes from `MockPremiumAccessController`, not StoreKit, so `NO` stays
  free with a sandbox subscription. The paywall and the Settings plan row still
  read the real `SubscriptionStore`. The `DebugPremium` toggles have no effect.
- Enhance edits only the drawn album photos on the simulator. On a device it is
  off, because the groups hold the user's own photos.
- On the simulator, the first launch asks for photo access and draws 64 photos
  into the album `Alike Fake Library`. On a device nothing is written: the newest
  library photos are used.
- An unknown scenario name logs an error and keeps the real library.
- Do not use the DEBUG section of Settings in a fake session. Best Shot
  Calibration and the Premium toggles there read and write the real stores.
- Both categories show the same photos: the mock returns 1 list for any category.
- If photo access is denied, the groups stay empty and only a log line says why.
  Grant access, then launch again.

## The `store` scenario

12 groups of 4 photos for the iPad App Store screenshots. Half are reviewed, the
rest are in review with the Best Shot kept and 2 photos selected, so
`alike://resume` opens a review half done. Its cleanup never finishes and deletes
nothing, so the "Organizing Photos" screen stays up for a capture.

The photos come from a folder, not from drawing: set `ALIKE_FAKE_LIBRARY_PHOTOS`
(`SIMCTL_CHILD_ALIKE_FAKE_LIBRARY_PHOTOS` with `simctl launch`). They go into
their own album, `Alike Store Library`. Build the folder with
`tools/build_fake_photo_library.py` from the generated scenes in
`tools/assets/fake-library/`. To replace the photos in the album, erase the
simulator. `tools/capture_ipad_store_screens.py` runs the whole capture.

## Screen captures

`AlikeTests/FakeLibraryScreenCaptureTests` draws every main screen with this data.
The steps are in `Docs/images/ipad/baseline/README.md`.
