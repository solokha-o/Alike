# iPad App Store screenshots (13-inch)

4 slides x 14 locales at 2048 x 2732, the 13-inch iPad size App Store Connect
accepts. `tools/prepare_app_store_upload_bundle.py` adds them to the upload as
`NN-ipad-*.png` only when the app targets iPad (`TARGETED_DEVICE_FAMILY = "1,2"`).

| Slide | Capture | Copy (from the iPhone `COPY`) |
| --- | --- | --- |
| 01 | Scanner after a scan | slide 1, "iPhone" → "iPad" |
| 03 | Cleanup queue | slide 2 |
| 05 | A review half done: Best Shot, 2 selected | slide 4 |
| 07 | Cleanup in progress | slide 5 |

How they are made (details in `Skills/DesignConcept/app-store-screenshots/SKILL.md`):

1. `tools/build_fake_photo_library.py` — 54 photos from the generated scenes in
   `tools/assets/fake-library/`. No real photo library is involved.
2. `tools/capture_ipad_store_screens.py --udid <iPad>` — the DEBUG `store` fake
   library on an iPad Air 13-inch (M2) simulator, iOS 27.2, dark, 9:41, into
   `../raw/<locale>/`. `pt-PT` uses the `pt-BR` captures, as on iPhone.
3. `07-cleanup-progress` needs 2 taps per locale (the Move button and the alert),
   then `--only 07-cleanup-progress --no-launch`.
4. `tools/generate_ipad_store_screenshots.py` renders this folder.

Known limit: the status bar date ("Mon 16 Nov") is the simulator's English date in
every locale; `simctl status_bar` overrides the time only.
