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

1. Run the preflight: `machine_load.sh`. Keep at most 1 booted simulator.
2. Grant photo access to the app on the iPad simulator:

   ```bash
   xcrun simctl privacy <udid> grant photos com.alike.app
   ```

3. Export the output folder in the shell. An `xcodebuild` argument does not reach
   the test.

   ```bash
   export TEST_RUNNER_ALIKE_SCREENSHOT_DIR=/path/to/output
   ```

4. Run the suite through the shared queue:

   ```bash
   ~/.agent-skills/local/dev-machine-load/scripts/heavy_slot.sh --label "Alike: iPad captures" -- \
     xcodebuild -project Alike/Alike.xcodeproj -scheme Alike -destination 'id=<udid>' \
     -jobs 6 -parallel-testing-enabled NO \
     -only-testing:AlikeTests/FakeLibraryScreenCaptureTests test
   ```

5. Copy `<output>/ipad-11` and `<output>/ipad-13` here. Images with identical file
   sizes are blank draws: run again.

Without `TEST_RUNNER_ALIKE_SCREENSHOT_DIR` the suite is skipped, so a normal test
run does not draw screens.
