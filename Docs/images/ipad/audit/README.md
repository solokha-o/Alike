# iPad audit captures (native mode)

PR 2 of the iPad card. The app as it is today, built for iPad (native mode), with
the DEBUG fake library. Nothing in the app was changed for these images.

| Folder | Device | Window (pt) |
|---|---|---|
| `ipad-a16-portrait-light/` | iPad (A16), iOS 27.2 | 820 × 1180 |
| `ipad-a16-landscape-light/` | iPad (A16), iOS 27.2 | 1180 × 820 |
| `ipad-air-13-portrait-light/` | iPad Air 13-inch (M2), iOS 27.2 | 1024 × 1366 |
| `ipad-13-landscape-light/` | iPad Pro 13-inch (M5), iOS 27.2 | 1376 × 1032 |

- Images are 1× (half the device pixels) to keep the repository small.
- Dark mode was captured and checked for every set but is not committed.
- The compatibility-mode "before" set is in `../baseline/`.
- The problem table is in the iPad card in Notion ("Аудит UI").

## How native mode was built

`TARGETED_DEVICE_FAMILY` stays `1` in the project until PR 5. The audit build
passes it, and the iPad orientations, as `xcodebuild` arguments only:

```bash
~/.agent-skills/local/dev-machine-load/scripts/heavy_slot.sh --label "Alike: iPad native build-for-testing" -- \
  xcodebuild -project Alike/Alike.xcodeproj -scheme Alike -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /Volumes/KINGSTON/DeveloperData/Xcode/ProjectBuilds/Alike/ipad-native -jobs 6 \
  TARGETED_DEVICE_FAMILY=1,2 \
  "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad=UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight" \
  build-for-testing
```

Then run `-only-testing:AlikeTests/FakeLibraryScreenCaptureTests test-without-building`
with the same arguments and these variables exported in the shell:

- `TEST_RUNNER_ALIKE_SCREENSHOT_DIR`: output folder.
- `TEST_RUNNER_ALIKE_SCREENSHOT_ORIENTATION`: `portrait` or `landscape`.
- `TEST_RUNNER_ALIKE_SCREENSHOT_STYLE`: `light` or `dark`.

For landscape, rotate the booted simulator first. iPadOS ignores the app's own
rotation request.

Use a simulator that never ran the iPhone-only build, or erase it first. Otherwise
iPadOS can reopen the app in the iPhone-shaped window it remembered.
