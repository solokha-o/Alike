# GitHub Copilot Instructions for Alike

## Project Context

This repository contains specialized skills and reference materials for iOS/macOS development with Swift, SwiftUI, and modern concurrency patterns.

## Available Skills

### Architecture & Design
- **SwiftUI Modular Architecture**: `Skills/Architecture/SwiftUIModular/SKILL.md` - App architecture patterns
- **Design Concepts**: `Skills/DesignConcept/SKILL.md` - Design system and UI/UX patterns

### Git & Workflow
- **Git Flow**: `Skills/GitFlow/SKILL.md` - Branch strategy, releases, versioning for iOS apps
  - Uses `main` (production) and `develop` (integration)
  - Feature branches: `feature/<ticket>-<short-name>`
  - Release branches: `release/<version>`
  - Hotfix branches: `hotfix/<version>`
  - Tags: `ios/vX.Y.Z`

### Swift Concurrency
- **Swift Concurrency Expert**: `Skills/SwiftConcurrency/swift-concurrency-expert/SKILL.md`
  - Review and fix Swift 6.2+ concurrency issues
  - References: `approachable-concurrency.md`, `swift-6-2-concurrency.md`, `swiftui-concurrency-tour-wwdc.md`
- **iOS Debugger Agent**: `Skills/SwiftConcurrency/ios-debugger-agent/SKILL.md`
- **GitHub Issue Fix Flow**: `Skills/SwiftConcurrency/gh-issue-fix-flow/SKILL.md`

### SwiftUI Patterns & Performance
- **SwiftUI UI Patterns**: `Skills/SwiftUI/swiftui-ui-patterns/SKILL.md`
  - Comprehensive UI patterns and components
  - References include: navigationstack, sheets, forms, grids, lists, scrollview, tabview, searchable, theming, etc.
- **SwiftUI Performance Audit**: `Skills/SwiftUI/swiftui-performance-audit/SKILL.md`
  - Performance optimization and profiling
  - References: WWDC23 demystify, Instruments optimization, hangs analysis
- **SwiftUI View Refactor**: `Skills/SwiftUI/swiftui-view-refactor/SKILL.md`
  - View refactoring patterns and best practices
- **SwiftUI Liquid Glass**: `Skills/SwiftConcurrency/swiftui-liquid-glass/SKILL.md`
  - Advanced visual effects

### macOS & Packaging
- **macOS SPM App Packaging**: `Skills/SwiftConcurrency/macos-spm-app-packaging/SKILL.md`
  - Complete packaging, signing, and notarization workflow
  - References: packaging.md, release.md, scaffold.md
  - Templates: build scripts, signing scripts, bootstrap projects

### App Store & Release
- **App Store Changelog**: `Skills/SwiftConcurrency/app-store-changelog/SKILL.md`
  - Release notes and changelog generation
  - References: release-notes-guidelines.md
  - Scripts: collect_release_changes.sh

## Instructions for GitHub Copilot

1. **When asked about Git workflow**: Read `Skills/GitFlow/SKILL.md` and follow the branch naming and release process defined there.

2. **When fixing Swift concurrency errors**: Read `Skills/SwiftConcurrency/swift-concurrency-expert/SKILL.md` and the relevant references before suggesting fixes.

3. **When implementing UI patterns**: Check `Skills/SwiftUI/swiftui-ui-patterns/SKILL.md` and the specific component reference files.

4. **When optimizing performance**: Use `Skills/SwiftUI/swiftui-performance-audit/SKILL.md` and apply techniques from the WWDC references.

5. **When packaging/releasing**: Follow the workflows in `Skills/SwiftConcurrency/macos-spm-app-packaging/SKILL.md`.

6. **Always check the references directory** within each skill for detailed implementation guidance and examples.

## Code Style Preferences

- Follow Git Flow commit conventions (see GitFlow SKILL.md)
- Prioritize Swift concurrency safety (Swift 6.2+)
- Optimize for SwiftUI performance and best practices
- Keep code modular and well-architected
