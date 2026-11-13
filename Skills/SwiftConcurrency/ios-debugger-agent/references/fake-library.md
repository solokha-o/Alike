# Fake library (DEBUG)

Use it to see a screen with data on a simulator, where a real scan forms no
groups. The code is in `Alike/Alike/Debug/FakeLibrary/`, under `#if DEBUG`. It
reuses the public mocks from `Packages/Core/Sources/Core/Mocks`.

## Launch arguments

| Argument | Values |
|---|---|
| `-AlikeFakeLibrary` | `empty`, `oneCluster`, `manyClusters` (55 groups), `largeCluster` (32 photos), `afterCleanup`, `noPhotosAccess` |
| `-AlikeFakePremium` | `YES` or `NO` (default `NO`) |

Example, in the scheme's Arguments tab or with `simctl launch`:

```bash
xcrun simctl launch <udid> com.alike.app -AlikeFakeLibrary manyClusters -AlikeFakePremium YES
```

## Behaviour

- All stores are in-memory mocks. The session writes no Core Data, no JSON in
  Application Support, and no widget snapshot. Delete all data only restarts
  onboarding.
- Premium sets every `DebugPremium` override in the argument domain for this
  process. The debug toggles in Settings cannot change it while the argument is on.
- On the simulator, the first launch asks for photo access and draws 64 photos
  into the album `Alike Fake Library`. On a device nothing is written: the newest
  library photos are used.
- An unknown scenario name logs an error and keeps the real library.

## Screen captures

`AlikeTests/FakeLibraryScreenCaptureTests` draws every main screen with this data.
The steps are in `Docs/images/ipad/baseline/README.md`.
