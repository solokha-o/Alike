<!--
  Release PR: `develop` → `main`. Open it with
  ?template=release.md appended to the compare URL, or pick it from the
  template dropdown.

  Ordering, commands and expected output live in Docs/release-checklist.md.
  This template is the reviewer-facing summary, not a replacement for it.
-->

**What**

The X.Y.Z release merge: everything on `develop` goes to `main`.

**Version is `X.Y.Z`, build `N`.** `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` are already committed on `develop`, so `main` never
receives an unversioned release.

**Why**

<!-- What this release gives users. One paragraph, not a changelog dump. -->

**How**

- Merge commit, not squash — release history is preserved deliberately
  (`Skills/GitFlow/ios-git-flow/SKILL.md`, merge policy). Squash and rebase are
  disabled at the repository level, so the button cannot get this wrong.
- Tag `vX.Y.Z` is created **after** the merge commit exists, annotated, and
  `main` is merged back into `develop`.

**Validation — run on `<commit>`**

- [ ] `tools/full` — whitespace, every package's tests, and the app compile
      gate. `Packages/Storage` is a standing skip, not a gap.
- [ ] `tools/release-check X.Y.Z N` — version check, strict bundle validation,
      Release archive, no-upload IPA export.
- [ ] Strict metadata generation exits 0 with zero `TODO:` markers.

Evidence read out of the archive `release-check` produced, not from build
settings:

- [ ] `CFBundleShortVersionString` and `CFBundleVersion` match the title
- [ ] `ITSAppUsesNonExemptEncryption = false`
- [ ] `UIDeviceFamily = [1]` — the app is iPhone-only
- [ ] The binary carries the published legal URLs and no `stdeula` link

**Legal and support site**

- [ ] All six URLs return 200. The site is independent of this merge; it lives
      in `alikeapp/alikeapp.github.io`.

```sh
for u in "" privacy/ uk/privacy/ terms/ uk/terms/ support/; do printf "%s %s\n" "$(curl -s -o /dev/null -w '%{http_code}' https://alikeapp.github.io/$u)" "$u"; done
```

**Store metadata**

- [ ] Release notes written for `en-US` and `uk`
- [ ] `.env` carries the per-locale overrides — `ALIKE_PRIVACY_URL_UK`,
      `ALIKE_TERMS_URL_UK`, `ALIKE_SUPPORT_URL_UK`. Nothing fails without them;
      the uk listing just silently reuses the English URLs.
- [ ] IAP localizations uploaded separately — `deliver` does not touch in-app
      purchases

**Still open after this merge**

- [ ] Tag, back-merge, build upload, App Privacy questionnaire, submission —
      `Docs/release-checklist.md` steps 9–12

**Risks**

<!-- Known risks and anything deliberately deferred. Do not hide them. -->

**Merge instruction:** merge commit, **not** squash.
