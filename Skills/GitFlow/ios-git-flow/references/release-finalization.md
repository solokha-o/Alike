# Release Finalization

Use this reference before any task that merges a release into `main`, merges
`develop` into `main`, or creates an app release tag.

## Preferred Flow

1. Start from clean `develop`.
2. Choose the next `X.Y.Z` with `references/app-versioning.md`.
3. Create `release/X.Y.Z` from `develop`.
4. Bump versions on the release branch:

```sh
Skills/GitFlow/ios-git-flow/scripts/bump-ios-version.sh \
  --version X.Y.Z \
  --build N \
  --project Alike/Alike.xcodeproj/project.pbxproj \
  --apply
```

5. Update App Store notes/changelog when the release has user-visible changes.
6. Validate the app and changed packages.
7. Merge `release/X.Y.Z` into `main` with a merge commit.
8. Tag the `main` merge commit as `vX.Y.Z`.
9. Merge `release/X.Y.Z` back into `develop` so version/changelog changes stay
   on the integration branch.

## Direct `develop` -> `main` Request

If the user explicitly asks to merge `develop` into `main`, keep the flow
minimal and limited to the requested scope:

1. Verify the requested version/build, or choose the smallest bump from
   `references/app-versioning.md` if the request delegates that decision.
2. Make the version bump commit on `develop` before the merge.
3. Merge `develop` into `main` with a merge commit.
4. Tag that exact `main` merge commit as `vX.Y.Z` only when the user asked for
   a tag move/create.
5. Do not tag `develop` for app releases.
6. Do not create a release branch, run release-check, or perform upload work
   unless the user explicitly asked for those extra release actions.

If the version choice is ambiguous and the change range mixes patch/minor/major
signals, ask the user to choose the release version before mutating branches.

## Tag Rules

- App release tags use exactly `vX.Y.Z`.
- Prefer annotated tags:

```sh
git tag -a vX.Y.Z -m "Alike X.Y.Z"
```

- Create the tag only after the `main` merge commit exists.
- Do not delete or rewrite release tags without explicit user approval.

## GitHub Release Rules

- Publish exactly one GitHub release per shipped version, on the `vX.Y.Z` tag,
  and delete superseded drafts rather than keeping them.
- Release notes link to the App Store product page
  (`https://apps.apple.com/app/id6798399598`, the same ID as
  `AppStoreLinks.appID`).
- Never attach build artifacts — no IPA, archive, or dSYMs. Apple distributes
  the binary; the release carries notes and the store link only.
