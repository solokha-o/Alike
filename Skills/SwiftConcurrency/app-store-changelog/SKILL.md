---
name: app-store-changelog
description: Create user-facing App Store release notes by collecting and summarizing all user-impacting changes since the last git tag (or a specified ref). Use when asked to generate a comprehensive release changelog, App Store "What's New" text, or release notes based on git history or tags.
---

# App Store Changelog

Write for a person with a photo library, not for a developer. The store text says
what the person can do now and where to find it; the technical record goes to the
README's "What ships" section, never into the store text.

## Overview
Collect user-impacting changes from git history since the last tag, then write App Store release notes in plain, everyday language.

## Workflow

### 1) Collect changes
- Run `scripts/collect_release_changes.sh` from the repo root to gather commits and touched files.
- If needed, pass a specific tag or ref: `scripts/collect_release_changes.sh v1.2.3 HEAD`.
- If no tags exist, the script falls back to full history.

### 2) Triage for user impact
- Scan commits and files to identify user-visible changes.
- Group changes by theme (New, Improved, Fixed) and deduplicate overlaps.
- Drop internal-only work (build scripts, refactors, dependency bumps, CI).

### 3) Draft App Store notes
- Follow the rules table in `references/release-notes-guidelines.md`.
- Use "you" form, say where to find each new thing, and use the app's own UI names per locale.
- State an OS requirement once; fit 2–5 bullets to the size of the update.

### 4) Validate
- Ensure every bullet maps back to a real change in the range.
- Run the QA checklist in `references/release-notes-guidelines.md`, including the "read it as a non-technical friend" pass.
- Ask for clarification if any change is ambiguous or possibly internal-only.

## Output Format
- Title (optional): "What’s New" or product name + version.
- Bullet list only; one sentence per bullet.
- Stick to storefront limits if the user provides one.

## Routing map
- Collect commits and touched files since the last tag -> `scripts/collect_release_changes.sh`
- Rules, words to replace, shape, examples and QA for store text -> `references/release-notes-guidelines.md`
