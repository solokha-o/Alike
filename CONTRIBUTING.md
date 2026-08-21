# Contributing to Alike

Thank you for helping improve Alike.

## Development workflow

1. Fork the repository and branch from `develop`.
2. Use a focused branch such as `feature/cleanup-filters` or `fix/scanner-retry`.
3. Keep credentials in ignored local files; never commit Apple or App Store Connect values.
4. Add or update tests for behavior changes.
5. Run `tools/quick` while iterating and `tools/full` before opening a pull request.
6. Open the pull request against `develop` and explain the product impact and validation performed.

Alike uses `main` for production and `develop` for integration. Release and hotfix branches follow the conventions in `Skills/GitFlow/ios-git-flow`.

## Commit messages

Start with an emoji and use a precise scope:

```text
<emoji> <scope>: <concrete change and affected area> [ticket]
```

Examples:

```text
✨ Cleanup: add favourites-only filter to the review queue
🐛 Scanner: stop double-counting clusters after a rescan
🧪 Tests: cover Delete Alike Data partial-failure retry
```

Do not mix unrelated changes in one commit.

## Configuration

- The app needs no accounts or third-party credentials to build and run.
- Local StoreKit testing uses `Alike/Configuration/Alike.storekit`.
- Keep App Store Connect and Apple signing values in the environment or an ignored `.env` file.

Before committing, verify that `git status` does not show any local configuration.

## Pull-request checklist

- [ ] The change has one clear purpose.
- [ ] Tests cover new or changed behavior.
- [ ] `tools/quick` and `tools/full` pass.
- [ ] User-facing strings are localized in EN and UK.
- [ ] No credentials, personal review data, generated upload bundles, or build artifacts are included.
- [ ] Documentation reflects public behavior and configuration changes.

## Contribution license

You keep ownership of your own contributions. By submitting a contribution to
this repository, you also agree to the following, in addition to the license
terms in [`LICENSE`](LICENSE) and the scope defined in [`NOTICE.md`](NOTICE.md):

- **Copyright license.** You grant Oleksandr Solokha a perpetual, irrevocable,
  worldwide, royalty-free, non-exclusive copyright license to use, reproduce,
  modify, prepare derivative works of, publicly display, publicly perform,
  sublicense, and distribute your contribution, in whole or in part, under any
  license terms — including the repository's
  [PolyForm Noncommercial License 1.0.0](LICENSE) and any future commercial or
  dual-licensing terms Oleksandr Solokha chooses to apply to Alike.
- **Patent license.** You grant Oleksandr Solokha a perpetual, irrevocable,
  worldwide, royalty-free, non-exclusive patent license to make, have made,
  use, sell, offer to sell, import, and otherwise transfer your contribution,
  for any patent claims you own or control that are necessarily infringed by
  your contribution alone or by its combination with Alike.
- **Your representations.** You represent that you have the legal authority
  to make the contribution under these terms, that the contribution is your
  original work (or that you have the necessary rights to submit it), and
  that it does not knowingly infringe any third party's rights.
- **Successors and assigns.** These terms bind and benefit your and Oleksandr
  Solokha's respective heirs, successors, and assigns.
- **How acceptance is recorded.** Opening a pull request against this
  repository constitutes your acceptance of these terms for the contribution
  contained in that pull request.
