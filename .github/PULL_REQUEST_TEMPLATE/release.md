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

- [ ] All 44 URLs return 200 — eleven locales by four pages. The site is
      independent of this merge; it lives in `alikeapp/alikeapp.github.io`, and
      its own `scripts/check-site.sh` has already asserted the matrix, the
      links, hreflang and the Terms guardrails before deploy.

```sh
for l in "" uk/ de/ fr/ es/ pt-br/ it/ nl/ pl/ tr/ zh-hant/; do for p in "" privacy/ terms/ support/; do u="$l$p"; printf "%s %s\n" "$(curl -s -o /dev/null -w '%{http_code}' https://alikeapp.github.io/$u)" "/$u"; done; done
```

**Store metadata**

- [ ] Release notes written for all twelve listing localizations — `en-US`,
      `uk`, `de-DE`, `fr-FR`, `es-ES`, `es-MX`, `pt-BR`, `it`, `nl-NL`, `pl`,
      `tr`, `zh-Hant`. Validation fails if `METADATA` and `UPLOAD_SAFE_LOCALES`
      drift apart, but nothing checks that a release note was actually
      refreshed — that is this box. `it`, `pl` and `tr` are bare codes on
      purpose: Fastlane `deliver` rejects the region-qualified spelling.
- [ ] `.env` carries the per-locale URL overrides for all eleven non-English
      listings — `ALIKE_{PRIVACY,TERMS,SUPPORT}_URL_` suffixed `UK`, `DE_DE`,
      `FR_FR`, `ES_ES`, `ES_MX`, `PT_BR`, `IT`, `NL_NL`, `PL`, `TR` and
      `ZH_HANT`, thirty-three in all (the full list with values is in
      `Docs/release-checklist.md` step 1). Nothing fails without them; a listing
      just silently reuses the English URLs. `ES_MX` points at the same `/es/`
      pages as `ES_ES` on purpose.
- [ ] IAP localizations uploaded separately — `deliver` does not touch in-app
      purchases

**Still open after this merge**

- [ ] Tag, back-merge, build upload, App Privacy questionnaire, submission —
      `Docs/release-checklist.md` steps 9–12

**Risks**

<!-- Known risks and anything deliberately deferred. Do not hide them. -->

**Merge instruction:** merge commit, **not** squash.
