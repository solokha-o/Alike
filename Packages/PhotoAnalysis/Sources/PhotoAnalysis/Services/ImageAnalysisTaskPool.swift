import Core
import Foundation
import os

private struct IndexedAnalysisResult<Output: Sendable>: Sendable {
    let index: Int
    let value: Output?
}

/// Bounded-concurrency map used by every image analysis service.
///
/// Extracted from `BlurAnalysisService` so blur detection and Best Shot quality
/// scoring share one pool: the same concurrency limit, the same cancellation
/// behaviour and the same "one bad photo never fails the batch" rule.
enum ImageAnalysisTaskPool {
    static func compactMap<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maxConcurrentTasks: Int,
        progress: @Sendable @escaping (Double) -> Void = { _ in },
        operation: @escaping @Sendable (Input) async throws -> Output?
    ) async throws -> [Output] {
        guard !inputs.isEmpty else { return [] }

        let taskLimit = min(max(maxConcurrentTasks, 1), inputs.count)
        return try await withThrowingTaskGroup(
            of: IndexedAnalysisResult<Output>.self
        ) { group in
            var results: [IndexedAnalysisResult<Output>] = []
            results.reserveCapacity(inputs.count)
            var nextIndex = 0
            var completedCount = 0

            func addTask(at index: Int) {
                let input = inputs[index]
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let value = try await operation(input)
                        try Task.checkCancellation()
                        return IndexedAnalysisResult(index: index, value: value)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        AppLog.photoKit.debug(
                            "\(AppLog.tag(.error, "Skipping analysis candidate after image failure: \(error.localizedDescription)"))"
                        )
                        return IndexedAnalysisResult(index: index, value: nil)
                    }
                }
            }

            while nextIndex < taskLimit {
                addTask(at: nextIndex)
                nextIndex += 1
            }

            while let result = try await group.next() {
                results.append(result)
                completedCount += 1
                progress(Double(completedCount) / Double(inputs.count))
                if nextIndex < inputs.count {
                    addTask(at: nextIndex)
                    nextIndex += 1
                }
            }

            return results
                .sorted { $0.index < $1.index }
                .compactMap(\.value)
        }
    }
}
