import Core
import Foundation
import Observation

@MainActor
@Observable
final class DeleteAllDataModel {
    enum State: Equatable {
        case idle
        case deleting
        case failed(message: String)
    }

    private(set) var state: State = .idle

    private let operation: @MainActor @Sendable () async throws -> Void

    init(operation: @escaping @MainActor @Sendable () async throws -> Void) {
        self.operation = operation
    }

    var isDeleting: Bool {
        state == .deleting
    }

    var errorMessage: String? {
        guard case .failed(let message) = state else { return nil }
        return message
    }

    func deleteAllData() async {
        guard !isDeleting else { return }
        state = .deleting

        do {
            try await operation()
            state = .idle
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to delete local app data: \(error.localizedDescription)"))"
            )
            state = .failed(
                message: SettingsL10n.DeleteAllDataModel.someDataMayAlreadyHave
            )
        }
    }

    func dismissError() {
        guard case .failed = state else { return }
        state = .idle
    }
}
