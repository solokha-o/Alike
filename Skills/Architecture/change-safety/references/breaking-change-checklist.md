# Breaking Change Checklist

Fill this in the PR body whenever a change is R1 or higher and additive shapes
in `extension-first.md` were rejected.

## 1. Name the break

- What symbol / key / attribute changes, and where does it live?
- Which risk tier (R1 cross-package, R2 persisted, R3 irreversible)?
- Why is the additive alternative worse? One sentence, concrete.

## 2. Enumerate the consumers

- Every call site in `Packages/*` and the app target (list them).
- Every persisted producer/consumer: Core Data attribute, `UserDefaults` key,
  `Codable` payload field, cached file on disk.
- Anything written by an **older app version** that a user may still have on
  disk after updating. This is the one that gets forgotten.

## 3. Choose the transition

| Situation | Transition |
|---|---|
| Renaming a `public` symbol | Add the new name, mark the old `@available(*, deprecated, renamed:)`, migrate call sites in the same PR, delete the old one a release later |
| Changing the meaning of a stored value | New key/attribute; read old → write new; keep the old readable for one release |
| Removing a stored value | Stop writing it now; keep reading it with a fallback; delete the storage in a later release |
| Changing a default that shaped user data | Add a version marker beside the value; re-derive lazily, do not mass-invalidate |
| Reworking a shipped user flow | Put the new path behind a build-configuration flag; keep the old path reachable in the same binary until the new one is proven |

## 4. Prove it

- [ ] Regression test that pins the old behaviour or the old stored payload
      (`Skills/Testing/swift-testing/SKILL.md`).
- [ ] For R2: a migration test that opens a store/payload written by the
      previous release and asserts it still loads
      (`Skills/Storage/persisted-data-evolution/references/migration-testing.md`).
- [ ] Full compile per `AGENTS.md`.
- [ ] Manual pass on a simulator with **pre-existing** data, not a fresh install.

## 5. Plan the rollback

- If this ships and is wrong, what does a user with the new data see after they
  downgrade or after a hotfix reverts the code?
- A change is only safely revertible if the reverted code can still read the
  data the new code wrote. If it cannot, that must be stated in the PR body
  explicitly — a plain `git revert` will not be enough.

## 6. Record it

The commit message and the PR body must say which symbol/key changed, which
tier, and what the compatibility window is. A breaking change that is invisible
in the history costs someone a debugging session in six months.
