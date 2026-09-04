# Scan and Analysis Pipeline

The pipeline lives in `Packages/PhotoAnalysis/Sources/PhotoAnalysis/Services`:
`AnalysisImageProvider`, `ImageAnalysisTaskPool`, `BlurAnalysisService`,
`VisionFeaturePrintService`, `PhotoQualityAnalysisService`,
`CachingPhotoQualityAnalyzer`, `PhotoClusteringService`.

## PhotoKit fetches

- Fetch results are lazy — keep them lazy. Do not map a `PHFetchResult` into an
  array of every asset before working on it; enumerate and process in batches.
- Request only the properties needed. Ask for the smallest target size that the
  analysis actually uses; a full-resolution decode for a blur score is pure waste.
- Prefer `deliveryMode`/`resizeMode` options that avoid a second, higher-quality
  callback when only one result is needed, and set `isSynchronous` deliberately.
- Never assume an asset still exists: the library changes under the app. Handle a
  missing or iCloud-only asset as a skipped item, not an error that fails the run.
- iCloud-backed originals can trigger network fetches. Decide explicitly whether
  a phase is allowed to download, and never let a download happen silently on a
  metered path during a background scan.

## Image loading and memory

- Downsample at decode time; never load a full-size image and scale afterwards.
- Wrap per-item image work in `autoreleasepool` when it runs in a loop —
  CoreGraphics buffers otherwise accumulate until the batch ends and the app is
  jetsammed on older devices.
- Peak memory, not average, decides whether a scan survives. Measure the peak
  during the largest batch.
- Caches are bounded: an `NSCache` (which evicts under pressure) or an explicit
  cap, never an unbounded dictionary keyed by asset identifier.

## Concurrency

- All bounded-concurrency mapping goes through `ImageAnalysisTaskPool`; it
  already gives one concurrency limit, cancellation propagation and the
  "one bad photo never fails the batch" rule. Do not hand-roll a second pool.
- Choose the limit from the work type, not from `activeProcessorCount` alone:
  Vision and image decode are memory-bound, so more tasks means more peak memory
  and thermal pressure, not more throughput. Validate the limit by measurement.
- Nothing in the pipeline touches the main actor. Progress callbacks hop to the
  main actor once, coalesced — not per photo.

## Cancellation and resumability

- `Task.checkCancellation()` inside every loop body, and on both sides of a long
  await, as the pool does.
- Persist progress in batches so a killed, backgrounded or user-cancelled scan
  resumes instead of restarting. Cached results carry their version marker, so a
  resumed scan re-measures only what is actually stale.
- Leaving the app must not lose work already paid for in CPU and battery.

## Thermals and power

- Check `ProcessInfo.processInfo.thermalState` and
  `isLowPowerModeEnabled` before and during long runs; reduce concurrency (or
  pause and inform the user) instead of pushing through a `.serious` state.
- Background execution has a hard budget. Persist partial results continuously
  rather than at the end, or the system kills the task and all of it is lost.

## Clustering

- Comparison is the quadratic step. Any change there is judged at scale: state
  the complexity in the PR body, and measure on a library at least an order of
  magnitude larger than the development one.
- Prefer bucketing/short-circuiting over a full pairwise pass, and never let a
  threshold change quietly turn a bounded pass into a full one.
