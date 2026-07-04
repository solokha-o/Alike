<INSTRUCTIONS>
In this project, the agent must use local skills from
`/Users/oleksandrsolokha/Projects/Alike/Skills` for every request whenever possible.

If a request matches the description of at least one skill in this folder, the agent must:
1) Open the relevant `SKILL.md` and follow its instructions.
2) If multiple skills apply, choose the minimal set needed for the task
   and apply them in a logical order.
3) If no skill applies, briefly explain why and proceed without a skill.

The list of available skills must be derived from `SKILL.md` files inside
`/Users/oleksandrsolokha/Projects/Alike/Skills` subfolders (not from global paths).

Build-completion gate:
1) For any code change, do not mark the task as finished until a full app compile is executed.
2) Full compile command: `xcodebuild -project Alike/Alike.xcodeproj -scheme Alike -destination 'id=66E5E039-9C66-4878-B211-923932320166' build`.
3) If a fixed simulator ID is unavailable, first select an available iOS Simulator destination and then run the same full compile.
4) Report completion only after `BUILD SUCCEEDED`; otherwise continue fixing until success or report a concrete blocker.
</INSTRUCTIONS>
