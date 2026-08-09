---
name: workspace-hygiene
description: Use this skill when the user cares about disk cleanliness, temporary files, workspace clutter, leftover artifacts, or wants Codex to avoid creating trash while working. Applies to code changes, debugging, screenshots, logs, exports, scratch scripts, and any task that may leave disposable files behind.
---

# Workspace Hygiene

Use this skill when the user asks to keep the repo clean, complains about leftover artifacts, or when a task is likely to create temporary files.

## Goal

Leave the workspace in a better state than it started, with only intentional deliverables kept in the repo.

## Defaults

- Prefer editing existing files over creating new ones.
- Do not create extra markdown summaries, debug notes, copied source files, screenshots, exported logs, or one-off helper scripts unless the user explicitly wants them kept.
- Put disposable artifacts in `/private/tmp` or the system temp directory, not inside the repo.
- If a temporary file must be created in the repo for tool compatibility, delete it before finishing unless the user asked to keep it.
- Treat local build output as disposable by default unless the user explicitly asks to preserve it.

## Before Creating Files

1. Ask: is a new file actually required?
2. If not required, work in-place.
3. If required, keep the file count minimal and choose a location that matches its lifespan:
   - long-lived project asset: store in the repo
   - short-lived scratch artifact: store in `/private/tmp`

## Scratch File Rules

- Use a single task-scoped temp directory, for example `/private/tmp/alike-codex-<task>`.
- Reuse that directory instead of scattering files.
- Delete the directory before the final response once it is no longer needed.
- Prefer task-scoped build locations outside the repo, especially for Xcode/Swift build output.
- Avoid committing or leaving behind:
  - `*.log`
  - `*.tmp`
  - `*.bak`
  - `*.orig`
  - repo-local `build/` folders created only for verification
  - task-scoped DerivedData or Xcode result bundles
  - ad-hoc export files
  - screenshots used only for inspection
  - copied data files created only for experimentation

## Build Artifact Rules

- Do not create a repo-root `build/` folder unless a tool forces it.
- When possible, direct build output to `/private/tmp` rather than the repository.
- If a command creates a repo-local `build/` folder only for validation, remove it before finishing.
- For Xcode builds, prefer an explicit temporary `-derivedDataPath` when that does not conflict with the user's required command.
- If the project instructions require a specific build command that writes local artifacts, run it as required and then clean up only the artifacts created during the current task.

## Editing Rules

- Prefer `apply_patch` for file edits.
- Prefer `rg`/`find`/read commands over generating inspection artifacts.
- Do not create a new file just to explain a plan or summarize changes.
- Do not create "cleanup", "notes", or "analysis" files unless explicitly requested.

## Verification And Cleanup

Before finishing:

1. Check what changed in the workspace.
2. Remove disposable artifacts created during the task.
3. Keep only:
   - requested deliverables
   - necessary source changes
   - intentionally added project files
4. Check for leftover build output such as local `build/` directories or task-scoped DerivedData.
5. In the final response, mention any intentionally retained new files or build artifacts.

## Pre-Commit Rule

- Before presenting work as ready to commit, remove transient files and folders that are not part of the deliverable.
- This includes task-created folders such as `.build-cache/`, repo-local `.build/`, temporary result bundles, scratch exports, and other verification-only artifacts.
- If a validation command creates temporary repo files, clean them up before the final response unless the user explicitly asked to keep them.

## If Cleanup Is Risky

- Never delete pre-existing user files just because they look temporary.
- Only remove files you created during the current task, unless the user explicitly asks for broader cleanup.
- If ownership is unclear, leave the file alone and mention it.
