---
name: project-skill-audit
description: Analyze project history and local skills to recommend targeted skill updates or new skills. Use when auditing skill coverage, reducing token use, checking stale skills, or deciding whether a recurring workflow deserves a skill.
---

# Project Skill Audit

## Goal

Audit real recurring workflows before recommending skill changes. Prefer updating an existing local skill over creating a duplicate.

## Fast Workflow

1. Map the current project surface:
   - `AGENTS.md`
   - `Skills/INDEX.md`
   - relevant local `SKILL.md` files
   - `agents/openai.yaml` when present
2. Use memory/session evidence only when the request needs history:
   - start from the runtime memory summary if present
   - search `~/.codex/memories/MEMORY.md` for repo name, cwd, skill names, and repeated workflow keywords
   - open only the 1-3 most relevant rollout summaries
3. Compare recurring work against existing local skills:
   - repeated validation sequences
   - repeated failure shields
   - recurring ownership boundaries
   - stale paths or overly broad triggers
4. Recommend the smallest durable change:
   - update an existing skill when it is already the right bucket
   - create a new skill only for a distinct repeated workflow
   - remove or narrow routing that loads external skills unnecessarily

For the detailed evidence workflow, use `references/audit-method.md`.

## Output Shape

Return:

1. Existing skills and what each covers.
2. Suggested updates with the highest-value change.
3. Suggested new skills only when justified by repeated workflow evidence.
4. Priority order by expected value and token/runtime savings.

## Token-Saving Rules

- Do not bulk-load rollout summaries.
- Do not bulk-load vendored external skills.
- Do not recommend a new skill when a trigger/reference update is enough.
- Do not copy large examples into `SKILL.md`; route to `references/`.
- If the audit is about reducing token usage, inspect `AGENTS.md`, `Skills/INDEX.md`, and top-level skill descriptions first.

## Guardrails

- Do not invent recurring patterns without repo or session evidence.
- Do not treat one-off bugs as skill candidates.
- Do not replace local Alike rules with generic external guidance.
- Do not run external skill update checks except for skill-maintenance tasks or explicit user requests.

## Related Skills

- `Skills/Meta/skill-authoring-governance/SKILL.md`
- `Skills/GitFlow/ios-git-flow/SKILL.md`
- `Skills/Testing/swift-testing/SKILL.md`
