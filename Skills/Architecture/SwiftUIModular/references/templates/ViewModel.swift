// Template: the view model of one screen.
// File: Packages/FeatureName/Sources/FeatureName/FeatureNameViewModel.swift.
// Based on: Packages/Settings/Sources/Settings/DeleteAllDataModel.swift (state
// enum, duplicate-request guard, log once, localized failure message) and
// Packages/Settings/Sources/Settings/SettingsViewModel.swift (a Core protocol
// injected through `init`).
// Do not copy the default argument of `WelcomeViewModel.init`: default values
// belong only to the composition root (written rule 6).
// `FeatureNameL10n` is the typed string wrapper of the package
// (Skills/Localization/spm-localization).

import Core
import Foundation
import Observation

/// Loads the saved entries for ``FeatureNameView``.
@MainActor
@Observable
final class FeatureNameViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded([FeatureNameEntry])
        case failed(message: String)
    }

    // MARK: - Properties

    private(set) var state: State = .idle

    private let repository: any FeatureNameRepository

    var isLoading: Bool {
        state == .loading
    }

    var entries: [FeatureNameEntry] {
        guard case .loaded(let entries) = state else { return [] }
        return entries
    }

    var errorMessage: String? {
        guard case .failed(let message) = state else { return nil }
        return message
    }

    // MARK: - Init

    init(repository: any FeatureNameRepository) {
        self.repository = repository
    }

    // MARK: - Actions

    func load() async {
        guard !isLoading else { return }
        state = .loading

        do {
            state = try await .loaded(repository.loadEntries())
        } catch is CancellationError {
            // The view went away. A cancelled load is not a failure.
            state = .idle
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load FeatureName entries: \(error.localizedDescription)"))"
            )
            state = .failed(message: FeatureNameL10n.Main.entriesCouldNotLoad)
        }
    }
}
