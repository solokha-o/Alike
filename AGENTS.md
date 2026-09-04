<INSTRUCTIONS>
In this project, the agent must use local skills from
`/Users/oleksandrsolokha/Projects/Alike/Skills` for every request whenever possible.

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
  `/Users/oleksandrsolokha/Projects/Alike/Skills` subfolders, not from global paths.
- If multiple local skills could apply, choose the narrowest one first.
- Do not bulk-read `Skills/External/**` for routine implementation, review, or
  test work.
- If no local skill applies, briefly say so and proceed by inspecting the repo
  directly before reaching for broader external guidance.

## Self-Service Defaults

When no failure analysis or repo mutation is needed, the user can directly run:

- `find Skills -name SKILL.md | sort`
- `./Skills/External/check-updates.sh`

## Code Exploration

Before using Grep, Glob, or Read for code exploration:

1. Call `get_minimal_context_tool` first.
2. Use `semantic_search_nodes_tool` to locate functions, types, and tests by
   intent.
3. Use `query_graph_tool` for callers, callees, imports, inheritance, and test
   relationships.
4. Call `get_impact_radius_tool` before edits that may cross package boundaries.
5. For reviews, call `detect_changes_tool`, then `get_review_context_tool`.
6. Fall back to Grep, Glob, or Read only when the graph is unavailable, stale,
   or cannot answer the question precisely.

## Build-Completion Gate

1. Run a full app compile before marking the task finished only when the
   changes affect compilable app or package source, build settings, package
   manifests, generated code, or any other area where compile validation is
   needed to know the repo still builds correctly.
2. Do not require a full app compile for documentation, skill files, comments,
   copy-only edits, or other non-compilable changes unless there is specific
   reason to doubt the change or the user asks for validation anyway.
3. Full compile command:
   `xcodebuild -project Alike/Alike.xcodeproj -scheme Alike -destination 'id=66E5E039-9C66-4878-B211-923932320166' build`.
4. If the fixed simulator ID is unavailable, first select an available iOS
   Simulator destination and then run the same full compile.
5. Report completion only after `BUILD SUCCEEDED`; otherwise continue fixing
   until success or report a concrete blocker.

## Change-Safety Gate

Alike has real installed users, so every change to already-shipped surface is
judged on what happens to *their* data and *their* flows, not only on whether it
compiles.

1. Before changing a `public` API of a package, a persisted value (Core Data
   attribute, `UserDefaults` key, `Codable`/`Data` payload, cached file), a
   shipped `enum`, or a known user flow, read
   `Skills/Architecture/change-safety/SKILL.md` and classify the change R0-R3.
2. Prefer extension over modification. New behaviour arrives as new code; an
   in-place change to shipped surface needs a stated reason and a compatibility
   plan in the commit message and PR body.
3. Any change to stored data additionally follows
   `Skills/Storage/persisted-data-evolution/SKILL.md` and is not done until its
   migration or round-trip test passes.
4. Before merging anything R1 or higher, walk the pre-merge gate in
   `Skills/Architecture/change-safety/references/release-compatibility-gate.md`.
5. Performance work follows `Skills/Performance/app-runtime-performance/SKILL.md`
   (runtime) or `Skills/Performance/xcode-build-performance/SKILL.md` (build
   time): measure before and after, on a realistic library, or do not claim it.

## Output style

- Reply in unified diff form. No full-file rewrites unless asked.
- No preamble, no trailing summary of what you just did.
- For research questions, answer in 10 lines or fewer unless I ask for depth.
</INSTRUCTIONS>
