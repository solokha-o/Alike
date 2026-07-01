<INSTRUCTIONS>
In this project, the agent must use local skills from
`/Users/oleksandrs/Alike/Skills` for every request whenever possible.

## Priority Workflow

When a user submits any request:

1. Check the compact skill router in `Skills/INDEX.md`.
2. Read exactly one best-matching local `SKILL.md` first.
3. Add a repo-vendored external skill only when `Skills/INDEX.md` marks it as
   useful depth and the local skill is not enough.
4. Add global/plugin skills only when neither the local skill nor the vendored
   external skill covers the need.

Local Alike skills are the source of truth for repository paths, package
boundaries, validation commands, architectural conventions, and commit rules.

## Skill Rules

- Derive the available local skill list from `SKILL.md` files inside
  `/Users/oleksandrs/Alike/Skills` subfolders, not from global paths.
- If multiple local skills could apply, choose the narrowest one first.
- Do not bulk-read `Skills/External/**` for routine implementation, review, or
  test work.
- If no local skill applies, briefly say so and proceed by inspecting the repo
  directly before reaching for broader external guidance.

## Self-Service Defaults

When no failure analysis or repo mutation is needed, the user can directly run:

- `find Skills -name SKILL.md | sort`
- `./Skills/External/check-updates.sh`

## Build-Completion Gate

1. For any code change, do not mark the task as finished until a full app
   compile is executed.
2. Full compile command:
   `xcodebuild -project Alike/Alike.xcodeproj -scheme Alike -destination 'id=66E5E039-9C66-4878-B211-923932320166' build`.
3. If the fixed simulator ID is unavailable, first select an available iOS
   Simulator destination and then run the same full compile.
4. Report completion only after `BUILD SUCCEEDED`; otherwise continue fixing
   until success or report a concrete blocker.
</INSTRUCTIONS>
