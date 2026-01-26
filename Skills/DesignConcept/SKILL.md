---
name: design_concept
description: Skill for creating iOS app design concepts in SwiftUI that follow Apple requirements and use only native elements and SF Symbols.
---

# Design Concept (iOS / SwiftUI)

## Purpose

This skill helps create iOS app design concepts that follow Apple Human Interface Guidelines, use only native SwiftUI elements, and rely on SF Symbols for iconography.

## Core Requirements

- Follow Apple Human Interface Guidelines (HIG).
- Use only native SwiftUI components (no custom controls).
- Icons only from SF Symbols (no images, PNG, SVG, or third-party icon sets).
- Typography uses Apple system fonts (SF Pro) only.
- Support both Light and Dark Mode.
- Colors may use system semantic colors **and** a custom palette, but custom colors must be defined as light/dark variants (asset catalog or color set).
- Accessibility: contrast, Dynamic Type, and adequate touch targets.
- If identical elements recur or a developer explicitly requests it, extract them into a separate reusable component for app-wide reuse.
- Visual language should feel like native Apple apps: clean spacing, grouped lists/forms, standard navigation, and platform‑consistent materials.

## Workflow

1. Clarify the screen goal and primary user action.
2. Define the structure: navigation (NavigationStack), tabs (TabView), modals (sheet), lists (List).
3. Choose native components for each element (Form, List, Section, Button, Toggle, Picker, etc.).
4. Specify exact SF Symbols names for icons.
5. Describe visual hierarchy and states (empty, loading, error) within native components.

## Output Format

- Short concept summary.
- List of screens and their structure.
- Key SwiftUI components used.
- SF Symbols used.
- Notes on accessibility and HIG compliance.
