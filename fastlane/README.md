fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios metadata_validate

```sh
[bundle exec] fastlane ios metadata_validate
```

Prepare and validate the App Store metadata/screenshot bundle without uploading.

### ios metadata_upload

```sh
[bundle exec] fastlane ios metadata_upload
```

Upload localized App Store metadata and screenshots without binary upload or review submission.

### ios metadata_text_upload

```sh
[bundle exec] fastlane ios metadata_text_upload
```

Upload only localized App Store text metadata (descriptions, keywords, review info) without screenshots, binary, or review submission.

### ios screenshots_upload

```sh
[bundle exec] fastlane ios screenshots_upload
```

Upload only App Store screenshots without text metadata, binary, or review submission.

### ios testflight_upload

```sh
[bundle exec] fastlane ios testflight_upload
```

Archive the release scheme and upload the build to TestFlight without review submission.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
