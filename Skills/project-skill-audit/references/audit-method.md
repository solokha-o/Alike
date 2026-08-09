# Project Skill Audit Method

Use this reference only when a skill audit needs historical evidence beyond the current repo files.

## Evidence Sources

- Runtime memory summary, when present.
- `~/.codex/memories/MEMORY.md`.
- `~/.codex/memories/rollout_summaries/`.
- Raw `~/.codex/sessions/` JSONL only when summaries do not contain the exact detail needed.
- Current repo guidance: `AGENTS.md`, `Skills/INDEX.md`, local `SKILL.md` files, and `agents/openai.yaml`.

## Memory Search

Search the memory index with:

- repo name and basename
- current `cwd`
- skill names
- repeated workflow handles
- validation commands or scripts

Prefer entries that cite rollout summaries for the same repo path. Open only the most relevant 1-3 summaries.

## Candidate Criteria

Recommend a skill update when:

- an existing skill is the right bucket but has stale triggers, missing guardrails, outdated paths, or incomplete validation
- top-level instructions are too broad and cause unnecessary reference loading
- `SKILL.md` and `agents/openai.yaml` drift

Recommend a new skill when:

- the same repo-specific workflow recurs across sessions
- success depends on project-specific paths, scripts, ownership rules, or validation steps
- stretching an existing skill would make it vague

Do not recommend a skill when:

- the pattern is a one-off bug
- a generic/global skill already fits without project-specific guardrails
- there is no repeated procedure, validation flow, or failure mode

## Reporting

Keep the report compact:

- existing skills
- suggested updates
- suggested new skills
- priority order

Include concrete evidence only when it changes the recommendation.
