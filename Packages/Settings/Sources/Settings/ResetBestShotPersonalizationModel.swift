import Core
import Foundation
import Observation

/// Backs the Settings row that lets the user undo Best Shot personalization.
/// Mirrors ``DeleteAllDataModel``'s state shape so the two destructive-action
/// rows in Settings behave the same way under the hood.
@MainActor
@Observable
final class ResetBestShotPersonalizationModel {
    enum State: Equatable {
        case idle
        case resetting
        case failed(message: String)
    }

    private(set) var state: State = .idle

    private let operation: @MainActor @Sendable () async throws -> Void

    init(operation: @escaping @MainActor @Sendable () async throws -> Void) {
        self.operation = operation
    }

    var isResetting: Bool {
        state == .resetting
    }

    var errorMessage: String? {
        guard case .failed(let message) = state else { return nil }
        return message
    }

    func reset() async {
        guard !isResetting else { return }
        state = .resetting

        do {
            try await operation()
            state = .idle
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to reset Best Shot personalization: \(error.localizedDescription)"))"
            )
            state = .failed(
                message: SettingsL10n.ResetBestShotPersonalizationModel.bestShotPersonalizationMayNotHave
            )
        }
    }

    func dismissError() {
        guard case .failed = state else { return }
        state = .idle
    }
}
