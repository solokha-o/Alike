---
name: ios-git-flow
description: Git Flow for iOS apps using main/develop, feature/release/hotfix branches, app product/build versioning, release tags, and release hygiene.
---

# iOS Git Flow (main/develop)

Use this skill when the user wants branch strategy, release process, version/build changes, release tags, or guidance for an iOS app repo that follows Git Flow.

## Defaults

- Long-lived branches: `main` (production), `develop` (integration)
- Short-lived branches:
  - `feature/<ticket>-<short-name>` from `develop`
  - `release/<version>` from `develop`
  - `hotfix/<version>` from `main`
- App release tags use exactly `vX.Y.Z`
- App versioning policy lives in `references/app-versioning.md`
- Release finalization and `develop` -> `main` rules live in `references/release-finalization.md`

## Workflow

1) **Feature work**
   - Branch from `develop`.
   - Keep PRs small and focused.
   - Merge via PR into `develop` after required checks pass.

2) **Release prep**
   - Create `release/<version>` from `develop`.
   - Only release-critical changes here (fixes, version bump, metadata).
   - Choose `patch`, `minor`, or `major` using `references/app-versioning.md`.
   - Update versions with `scripts/bump-ios-version.sh`:
     - `MARKETING_VERSION` = `X.Y.Z`
     - `CURRENT_PROJECT_VERSION` = positive integer build number
   - Stabilize and then merge `release/<version>` into `main` and `develop`.
   - Tag the `main` merge commit with `vX.Y.Z`.

3) **Hotfix**
   - Branch `hotfix/<version>` from `main`.
   - Fix, bump versions if needed, then merge back to `main` and `develop`.
   - Tag the `main` merge commit with `vX.Y.Z`.

4) **Direct develop to main request**
   - Treat the user's wording as authoritative; do not expand into the full
     release-branch flow unless they ask for it.
   - If the user explicitly asks to merge `develop` into `main`, first read
     `references/release-finalization.md` and do only the requested scope
     before the merge.
   - For a "build bump only" request, change only `CURRENT_PROJECT_VERSION`.
   - Do not add tag moves, release-check runs, uploads, or extra release
     branch ceremony unless the user explicitly asks for those actions.

## Guardrails

- No direct commits to `main` or `develop`.
- Required checks for release merges: version check + build + tests + lint.
- Always keep `develop` green.

## Commit rules (best practices)

- Keep commit messages informative and ~150–200 characters where possible.
- Use emojis at the start for quick scanning (pick the closest intent).
- Prefer single-purpose commits; avoid mixing unrelated changes.
- Reference ticket IDs when available (e.g., `ABC-123`).
- Avoid large "dump" commits; split into logical steps.
- Ensure the message clearly describes what changed and where (feature/area), not just the intent.

**Suggested format**

`<emoji> <scope>: <what changed + where> [<ticket>]`

**Examples**

- `✨ UI: add onboarding header in WelcomeScreen ABC-123`
- `🐛 Auth: fix token refresh loop in SessionManager ABC-128`
- `🧪 Tests: cover date formatter in DateFormatTests ABC-140`
- `♻️ Core: extract analytics helper from EventTracker`
- `🧹 CI: remove deprecated lane from Fastlane`

**Emoji suggestions (common)**

- ✨ feature
- 🐛 bug fix
- 🧪 tests
- ♻️ refactor
- 🧹 chore/cleanup
- 📦 deps/build

## PR Checklist (short)

- Tests pass; build succeeds.
- Version bump done when on release/hotfix or a direct `develop` -> `main` release merge.
- Release notes or changelog updated.
- No leftover debug flags or test endpoints.

## Merge policy

- Prefer squash merge for feature branches to keep history clean.
- Use merge commit for release/hotfix to preserve context.
- Keep PR title meaningful; it becomes the squash commit title.
- If multiple commits are useful (e.g., refactor + feature), ensure each is complete and buildable.
- For full PR preparation, self-review, PR body authoring, or review-comment response, use `Skills/GitFlow/pr-agent-flow/SKILL.md`.

## PR template (short)

**What**
- One sentence summary

**Why**
- User or business impact

**How**
- Key technical notes (optional)

**Checks**
- [ ] Build passes
- [ ] Tests added/updated
- [ ] Version bump (release/hotfix)

## When to adjust

- If release cadence is very high, consider shortening release branch lifetime.
- If team is small, allow direct merge from feature to `main` only for hotfixes.

## Related resources

- `references/app-versioning.md` - Product version, build number, and bump rules.
- `references/release-finalization.md` - Release branch, direct `develop` -> `main`, and tag workflow.
- `references/package-versioning.md` - Internal SwiftPM package version policy.
- `scripts/bump-ios-version.sh` - Deterministic Xcode project version check/apply helper.
- For Xcode scheme and build configuration setup (Debug/Staging/Release), see `Skills/Architecture/SwiftUIModular/references/xcode-schemes-configurations.md`
- For versioning automation and CI/CD integration, consult the scheme configuration reference
