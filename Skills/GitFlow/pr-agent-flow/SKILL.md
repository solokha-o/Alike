---
name: pr-agent-flow
description: Prepare, review, and ship pull requests with a coding-agent pass, a reviewer-agent pass, clear validation, and a concise PR narrative.
---

# PR Agent Flow

Use this skill when the user wants to prepare a pull request, write a PR description, do a final self-review before opening a PR, or address review feedback in a consistent way.

## Trigger Conditions

- User asks to "create a PR", "prepare a PR", or "open a pull request"
- A feature/fix is implemented and needs a final agent-led review pass
- The branch is ready for summary, validation, and reviewer handoff
- Review comments or requested changes need to be addressed

## Goals

- Keep PRs small enough to review quickly
- Separate implementation from review thinking
- Ensure validation is proportional to the changes
- Produce a PR description that explains user impact, technical approach, and risk

## Workflow

1. Confirm branch intent and scope.
   - Identify the target branch using `Skills/GitFlow/ios-git-flow/SKILL.md`.
   - Summarize the change in one sentence.
   - If the diff mixes unrelated work, split it before continuing.

2. Run the coding-agent pass.
   - Finish the requested implementation only.
   - Remove dead code, debug leftovers, temporary comments, and accidental formatting churn.
   - If the change touches a repo area with a dedicated local skill, use that skill before finalizing the code.

3. Run the reviewer-agent pass.
   - Review the diff as if it came from another engineer.
   - Look first for regressions, missing validation, risky assumptions, and scope creep.
   - Use `references/review-rubric.md`.
   - Apply safe fixes before opening the PR.

4. Validate based on change type.
   - For code, test, build, manifest, generated-code, or settings changes, run the required validation.
   - For docs-only or skill-only changes, skip full compile unless the user asks or the change creates repo risk.
   - For app/package source changes in this repo, the build-completion gate is the full compile from `AGENTS.md`.

5. Write the PR narrative.
   - Use `references/pr-template.md`.
   - Capture what changed, why it matters, how it was implemented, and what was validated.
   - Call out known risks, follow-ups, and intentionally deferred work.

6. Open or hand off the PR.
   - Ensure the title matches the final scope.
   - Prefer a reviewer-ready PR over a draft only when validation is complete and open questions are resolved.
   - If review comments arrive later, repeat the reviewer-agent pass after each fix set.

## Decision Tree

1. Is the request only about branch/release mechanics?
   - Use `Skills/GitFlow/ios-git-flow/SKILL.md` first.

2. Is the request about implementing code that will later become a PR?
   - Use the narrow feature skill first, then come back to this skill for final PR preparation.

3. Is the request about reviewing an already-written diff?
   - Start at the reviewer-agent pass and skip implementation work unless fixes are requested.

4. Is the request about responding to PR comments?
   - Read the comments, group them by risk, fix the accepted items, then rewrite the validation and follow-up notes.

## Guardrails

- Do not open a large PR that mixes refactor, feature, cleanup, and release work without explicit user approval.
- Do not mark a PR ready if required validation has not been run.
- Do not hide known risk; document it in the PR body.
- Do not let the PR body become a changelog dump; optimize for reviewer comprehension.
- Do not resolve review comments by explanation alone when the code is still risky or unclear.

## Quick Checklist

- [ ] Scope is single-purpose and reviewable
- [ ] Diff is cleaned up and free of debug leftovers
- [ ] Reviewer-agent pass completed
- [ ] Validation matches the touched surface
- [ ] PR body explains what, why, how, and checks
- [ ] Risks and follow-ups are explicit

## Related Skills

- `Skills/GitFlow/ios-git-flow/SKILL.md` - branch targets, release flows, commit and merge policy
- `Skills/Meta/skill-authoring-governance/SKILL.md` - creating or evolving local skills
- `Skills/project-skill-audit/SKILL.md` - deciding whether repeated PR work needs more skill coverage
- `Skills/SwiftUI/swiftui-code-review/SKILL.md` - SwiftUI-specific review pass
- `Skills/Testing/swift-testing/SKILL.md` - test additions, fixes, and review
