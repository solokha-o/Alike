public enum PhotoImageLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

public enum PhotoImageLoadResolution: Equatable, Sendable {
    case loaded
    case failed
    case cancelled
}

/// Guards view-owned image state against completions from cancelled or reused tasks.
public struct PhotoImageLoadState: Equatable, Sendable {
    public private(set) var phase: PhotoImageLoadPhase = .idle
    private var generation = 0

    public init() {}

    @discardableResult
    public mutating func begin() -> Int {
        generation += 1
        phase = .loading
        return generation
    }

    @discardableResult
    public mutating func resolve(
        _ resolution: PhotoImageLoadResolution,
        generation: Int
    ) -> Bool {
        guard generation == self.generation, phase == .loading else { return false }

        switch resolution {
        case .loaded:
            phase = .loaded
        case .failed:
            phase = .failed
        case .cancelled:
            phase = .idle
        }
        return true
    }
}
