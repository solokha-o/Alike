# PR Template

Use this structure when writing or updating the PR description.

## Title

- Keep it aligned with the final diff, not the original plan
- Prefer user-visible or domain language over internal shorthand
- If the repo uses ticket IDs, append the ticket once

Suggested pattern:

`<area>: <user-facing change or technical outcome>`

Examples:

- `Feed: fix duplicate refresh on first load`
- `Composer: add inline attachment preview`
- `Core: isolate image cache writes on MainActor`

## Body

**What**
- One short paragraph describing the concrete change

**Why**
- One short paragraph describing user impact, bug risk, or product need

**How**
- 2-5 flat bullets covering the important implementation choices

**Validation**
- List only what was actually run
- Include build/test commands or a concise human-readable summary

**Risks**
- Note any edge cases, migrations, follow-ups, or areas that deserve extra reviewer attention

## Writing Rules

- Lead with behavior and impact; implementation detail comes after
- Name important files, modules, or systems only when they help the reviewer orient quickly
- Avoid vague claims like "minor cleanup" or "various fixes"
- Avoid copying commit history into the PR body
- If no tests were added, say why
