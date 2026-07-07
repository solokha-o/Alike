---
name: ios-debugger-agent
description: Use XcodeBuildMCP to build, run, launch, and debug the current iOS project on a booted simulator. Trigger when asked to run an iOS app, interact with the simulator UI, inspect on-screen state, capture logs/console output, diagnose runtime behavior, or wire debug-only access such as premium-feature overrides and local feature flags.
---

# iOS Debugger Agent

## Overview
Use XcodeBuildMCP to build and run the current project scheme on a booted iOS simulator, interact with the UI, and capture logs. Prefer the MCP tools for simulator control, logs, and view inspection.

## Core Workflow
Follow this sequence unless the user asks for a narrower action.

### 1) Discover the booted simulator
- Call `mcp__XcodeBuildMCP__list_sims` and select the simulator with state `Booted`.
- If none are booted, ask the user to boot one (do not boot automatically unless asked).

### 2) Set session defaults
- Call `mcp__XcodeBuildMCP__session-set-defaults` with:
  - `projectPath` or `workspacePath` (whichever the repo uses)
  - `scheme` for the current app
  - `simulatorId` from the booted device
  - Optional: `configuration: "Debug"`, `useLatestOS: true`

### 3) Build + run (when requested)
- Call `mcp__XcodeBuildMCP__build_run_sim`.
- If the app is already built and only launch is requested, use `mcp__XcodeBuildMCP__launch_app_sim`.
- If bundle id is unknown:
  1) `mcp__XcodeBuildMCP__get_sim_app_path`
  2) `mcp__XcodeBuildMCP__get_app_bundle_id`

## App-Level Debug Overrides
Use this section when the user wants easier access to premium, paywalled, entitlement-gated, or feature-flagged flows in local debug builds.

### Preferred repo pattern
- Keep debug overrides in app composition/root wiring, not inside feature views.
- Reuse existing protocols such as `PremiumAccessControlling` or feature-flag abstractions instead of adding ad hoc booleans across modules.
- Prefer `#if DEBUG` plus a persisted local toggle (`@AppStorage`, launch argument, or debug-only settings row) over touching production code paths.
- If a feature is injected from the app target, add the debug seam there first and pass the resolved dependency into the feature.

### Recommended workflow
1. Find the composition root for the dependency being gated.
2. Check whether a protocol seam already exists.
3. Add a debug-only override source:
   - `@AppStorage` when the user should toggle it in-app
   - launch argument / environment when tests or simulator scripts should control it
4. Keep the production default unchanged.
5. Validate by building the app and, when needed, running the simulator flow that exercises the gated feature.

### Premium feature guidance
- For premium or entitlement work, prefer:
  - debug-only storage key in shared/core models only when it improves consistency
  - toggle surfaced in a debug-only Settings section
  - unlocked feature set resolved in the app root and injected through the existing premium controller
- Avoid hardcoding premium unlocks inside feature packages unless the feature itself owns the entitlement source.

## UI Interaction & Debugging
Use these when asked to inspect or interact with the running app.

- **Describe UI**: `mcp__XcodeBuildMCP__describe_ui` before tapping or swiping.
- **Tap**: `mcp__XcodeBuildMCP__tap` (prefer `id` or `label`; use coordinates only if needed).
- **Type**: `mcp__XcodeBuildMCP__type_text` after focusing a field.
- **Gestures**: `mcp__XcodeBuildMCP__gesture` for common scrolls and edge swipes.
- **Screenshot**: `mcp__XcodeBuildMCP__screenshot` for visual confirmation.

## Logs & Console Output
- Start logs: `mcp__XcodeBuildMCP__start_sim_log_cap` with the app bundle id.
- Stop logs: `mcp__XcodeBuildMCP__stop_sim_log_cap` and summarize important lines.
- For console output, set `captureConsole: true` and relaunch if required.

## Troubleshooting
- If build fails, ask whether to retry with `preferXcodebuild: true`.
- If the wrong app launches, confirm the scheme and bundle id.
- If UI elements are not hittable, re-run `describe_ui` after layout changes.
- If a gated screen is still locked in Debug, inspect the composition root before changing feature code. Confirm the override is persisted and that the resolved dependency is the one injected into the feature.
