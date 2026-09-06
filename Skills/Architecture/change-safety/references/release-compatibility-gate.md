# Release Compatibility Gate

Hard rules. These are not preferences: breaking one of them ships a broken app
to users who already have data, and no revert repairs it.

## MUST

1. **MUST** classify every change R0–R3 before writing code, and name the tier in
   the PR body for R2 and R3.
2. **MUST** add new behaviour additively when an additive shape exists
   (`extension-first.md`).
3. **MUST** keep every stored value written by the previous release readable by
   this one: Core Data attributes, `UserDefaults` keys, `Codable` payloads,
   cached files.
4. **MUST** ship a migration/round-trip test with any change to stored data
   (`Skills/Storage/persisted-data-evolution/references/migration-testing.md`).
5. **MUST** verify the build on a simulator that already holds data from the
   previous release, not on a fresh install.
6. **MUST** keep defaults for absent values equal to the behaviour existing users
   already see — the absent value is what every existing install has.
7. **MUST** state the compatibility window (when the old path is removed) for any
   deprecation, in the commit message.
8. **MUST** run the full compile per `AGENTS.md` before calling the task done.

## NEVER

1. **NEVER** rename or retype a persisted attribute or key in place.
2. **NEVER** repurpose an existing key, attribute, `enum` raw value, or stored
   unit for a new meaning.
3. **NEVER** delete a persisted value in the same release that stops writing it.
4. **NEVER** resolve a migration failure by deleting the store or resetting
   defaults. That is data loss, and it needs explicit user authorization (R3).
5. **NEVER** add `fatalError`, `try!`, or a forced unwrap on a path reachable
   from user data.
6. **NEVER** make an exhaustive `switch` over a shipped `public enum` in another
   package without a default path.
7. **NEVER** change a scoring/threshold default that already shaped stored
   results without a version marker beside it.
8. **NEVER** mix a schema change and a feature change in one PR.
9. **NEVER** land a "cleanup" that removes an old read path, an old key
   fallback, or a legacy branch without checking which shipped version wrote it.

## Pre-merge gate

A PR that touches shipped surface is not ready until every line is true:

- [ ] Tier stated (R0–R3); R2/R3 justified in the PR body.
- [ ] Additive alternative considered and, if rejected, the reason written down.
- [ ] All consumers listed, including data written by older app versions.
- [ ] Old stored data still loads — proven by a test, not by reasoning.
- [ ] Regression test pins the previous behaviour where it must not change.
- [ ] Defaults for absent values verified.
- [ ] Deprecation window recorded, and nothing is deleted before it elapses.
- [ ] Rollback answered: what does a user with new data see if this is reverted?
- [ ] Manual pass over pre-existing data on the simulator.
- [ ] Full compile succeeded.

## Deprecation windows

| Surface | Minimum before removal |
|---|---|
| `public` API inside the repo | Same PR migrates all call sites; the old symbol may go immediately once nothing references it |
| `UserDefaults` key | Stop writing now, keep the read fallback for **one** release |
| Core Data attribute | Stop writing now, remove the attribute a release later, in its own PR |
| `Codable` field | Keep decoding it for **two** releases — payloads live on disk longer than users update |
| A user-visible flow behind a flag | Keep the old path until the new one has shipped and held for one full release |

When in doubt, the longer window costs a few lines of fallback code; the shorter
one costs a user their data.
