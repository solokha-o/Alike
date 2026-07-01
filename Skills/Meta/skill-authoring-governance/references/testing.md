# Skill Testing Reference

Use this reference to validate that a skill remains discoverable and actionable.

## Manual Validation

1. Open `SKILL.md` and verify it can be scanned in under 1 minute.
2. Confirm each reference file has a single clear purpose.
3. Confirm relative paths are valid and resolve from the skill directory.
4. Confirm "Related Skills" entries point to existing files.

## Regression Checks

- No duplicated long sections between `SKILL.md` and references.
- No stale template paths.
- No contradictory trigger conditions.
- Logging policy remains aligned with `Packages/Core/Sources/Core/Logging/AppLog.swift`.
