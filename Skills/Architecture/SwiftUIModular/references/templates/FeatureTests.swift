// Template: the tests of one view model, in Swift Testing.
// File: Packages/FeatureName/Tests/FeatureNameTests/FeatureNameViewModelTests.swift.
// Based on: Packages/Settings/Tests/SettingsTests/DeleteAllDataModelTests.swift
// (`@MainActor struct` without a bare `@Suite`, one behaviour in each test,
// private test error)
// and Packages/Settings/Tests/SettingsTests/SettingsViewModelTests.swift (the
// Core mock injected through `init`).
// No `import XCTest`: tools/check_no_xctest_imports.py fails the build.
// Rules: Skills/Testing/swift-testing/SKILL.md.

import Core
import Foundation
import Testing
@testable import FeatureName

@MainActor
struct FeatureNameViewModelTests {
    @Test func testLoadShowsStoredEntries() async throws {
        let entry = FeatureNameEntry(title: "First")
        let repository = MockFeatureNameRepository(entries: [entry])
        let viewModel = FeatureNameViewModel(repository: repository)

        await viewModel.load()

        let loaded = try #require(viewModel.entries.first)
        #expect(loaded == entry)
        #expect(viewModel.errorMessage == nil)
        #expect(await repository.didCallLoadEntries)
    }

    @Test func testLoadExposesFailureMessage() async {
        let repository = MockFeatureNameRepository()
        await repository.setLoadEntriesError(FeatureNameTestError.failure)
        let viewModel = FeatureNameViewModel(repository: repository)

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.entries.isEmpty)
        #expect(!viewModel.isLoading)
    }

    @Test func testLoadTreatsCancellationAsIdle() async {
        let repository = MockFeatureNameRepository()
        await repository.setLoadEntriesError(CancellationError())
        let viewModel = FeatureNameViewModel(repository: repository)

        await viewModel.load()

        #expect(viewModel.state == .idle)
        #expect(viewModel.errorMessage == nil)
    }
}

private enum FeatureNameTestError: Error {
    case failure
}
