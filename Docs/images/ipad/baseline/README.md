# iPad baseline captures

Screens of the iPhone-only app on iPad simulators in compatibility mode, portrait.
They are the "before" set for the iPad audit and for the before/after comparison
in the iPad card.

- `ipad-11/`: iPad Pro 11-inch (M5), iOS 27.2.
- `ipad-13/`: iPad Pro 13-inch (M5), iOS 27.2.

The data is the DEBUG fake library (`-AlikeFakeLibrary`), not a real scan. The
photos are drawn landscapes, not real photos. Details:
`Skills/SwiftConcurrency/ios-debugger-agent/references/fake-library.md`.

## File names

`<screen>-<scenario>.png`, for example `cleanup-manyClusters.png`. The paywall is
drawn as shipped.

## Regenerate

Do steps 1-6 for 1 iPad, then repeat them for the other. Keep at most 1 booted
simulator.

1. Run the preflight: `machine_load.sh`. Shut down any simulator you booted before.
2. Boot the iPad through the shared queue. A boot outside the queue counts as a
   user device and stops all heavy work.

   ```bash
   ~/.agent-skills/local/dev-machine-load/scripts/heavy_slot.sh --label "Alike: boot iPad" -- \
     xcrun simctl bootstatus <udid> -b
   ```

3. Grant photo access to the app. The grant needs a booted device.

   ```bash
   xcrun simctl privacy <udid> grant photos com.alike.app
   ```

4. Export the output folder in the shell. An `xcodebuild` argument does not reach
   the test.

   ```bash
   export TEST_RUNNER_ALIKE_SCREENSHOT_DIR=/path/to/output
   ```

5. Run the suite through the shared queue:

   ```bash
   ~/.agent-skills/local/dev-machine-load/scripts/heavy_slot.sh --label "Alike: iPad captures" -- \
     xcodebuild -project Alike/Alike.xcodeproj -scheme Alike -destination 'id=<udid>' \
     -jobs 6 -parallel-testing-enabled NO \
     -only-testing:AlikeTests/FakeLibraryScreenCaptureTests test
   ```

6. Shut down the iPad: `xcrun simctl shutdown <udid>`.
7. After both iPads, copy `<output>/ipad-11` and `<output>/ipad-13` here. Look at
   each image: a photo cell that loaded late is not caught by the test.

Without `TEST_RUNNER_ALIKE_SCREENSHOT_DIR` the suite is skipped, so a normal test
run does not draw screens.
