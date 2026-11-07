# 0003. Format change process

- Status: Accepted
- Date: 2026-11-07
- Supersedes: none

## Context

A format change touches many files and lines. If it mixes with behaviour
changes, a reviewer cannot see the behaviour change. It also hides the real
author of each line in `git blame`, and it causes merge conflicts in open
branches.

## Decision

A format change is any change to the SwiftFormat rules or options
([ADR-0001](0001-alike-swift-style.md)), or any change to the SwiftLint rules
or thresholds ([ADR-0002](0002-selective-swiftlint.md)). Each LATER rule of
ADR-0001 is one format change.

Do a format change in these steps:

1. Write a new ADR or update the related ADR. Merge it, or put it in the same
   pull request.
2. Make one commit that contains only the configuration change and the
   reformatted code. Do not put a behaviour change in this commit.
3. Build the app and run the package tests. The commit must not change
   behaviour.
4. In a separate, later commit, add the full hash of the commit from step 2 to
   [.git-blame-ignore-revs](../../.git-blame-ignore-revs), with a comment that
   names the rule.

Rules for the timing:

- Start a format change only when no open branch conflicts with it. Check the
  open pull requests and the active branches first.
- Never do a format change right before a release. Do not do it while a
  `release/*` or `hotfix/*` branch is open.
- A format change pull request contains one rule (stage 7) or the CORE set
  (stage 2).

The hash in step 4 must be the hash on the target branch. Alike merges pull
requests with a merge commit, so the hash of the format commit does not change
at merge. If you rebase the branch, write the new hash.

## Alternatives

- Reformat in each feature pull request when a file is touched: reviews mix
  style and behaviour, and the change never finishes.
- One large commit for all rules: the diff is too large to review, and one bad
  rule blocks all others.

## Consequences

- `git blame` shows the real author when the local Git uses the ignore file:
  `git config blame.ignoreRevsFile .git-blame-ignore-revs`.
- Format changes wait for a quiet period between releases.
- Each format commit can be reverted alone.

## Status

Accepted on 2026-11-07 by the project owner.
