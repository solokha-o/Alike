#if DEBUG
import Foundation

/// A fixed photo library state that a DEBUG build can show without a scan.
///
/// The simulator cannot form clusters, so iPad layout work needs every screen in a
/// state with data from somewhere else. Turn a scenario on with a launch argument:
///
///     -AlikeFakeLibrary manyClusters -AlikeFakePremium YES
///
/// `UserDefaults` reads `-key value` launch arguments into its argument domain, so
/// nothing is parsed by hand and nothing is persisted.
enum FakeLibraryScenario: String, CaseIterable, Sendable {
    /// A finished scan that found nothing.
    case empty
    /// 1 group of 4 photos.
    case oneCluster
    /// 55 groups of 3 photos.
    case manyClusters
    /// 1 group of 32 photos and 2 small groups.
    case largeCluster
    /// Groups with finished reviews, a cleanup history and an active session.
    case afterCleanup
    /// Photo access denied: the app stops at the permission screen.
    case noPhotosAccess

    static let launchArgumentKey = "AlikeFakeLibrary"
    static let premiumLaunchArgumentKey = "AlikeFakePremium"

    /// The scenario named by the launch arguments, or `nil` for the real library.
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> FakeLibraryScenario? {
        guard let rawValue = defaults.string(forKey: launchArgumentKey) else { return nil }
        return FakeLibraryScenario(rawValue: rawValue)
    }

    static func isPremiumFromLaunchArguments(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: premiumLaunchArgumentKey)
    }

    var hasPhotoAccess: Bool {
        self != .noPhotosAccess
    }

    /// Photo count of each group, largest first.
    var clusterSizes: [Int] {
        switch self {
        case .empty, .noPhotosAccess:
            []
        case .oneCluster:
            [4]
        case .manyClusters:
            Array(repeating: 3, count: 55)
        case .largeCluster:
            [32, 3, 2]
        case .afterCleanup:
            [5, 4, 3, 3, 2, 2]
        }
    }

    /// Distinct photos the scenario needs, so every group has a unique set.
    var requiredPhotoCount: Int {
        switch self {
        case .manyClusters:
            // Group `i` uses photos `i ..< i + 3`, so neighbours overlap but no two
            // groups hold the same set.
            clusterSizes.count + 2
        default:
            clusterSizes.reduce(0, +)
        }
    }

    /// Photos shown in the screenshot and blurred-photo categories.
    var categoryPhotoCount: Int {
        switch self {
        case .empty, .noPhotosAccess, .oneCluster:
            0
        case .manyClusters, .largeCluster, .afterCleanup:
            6
        }
    }

    var hasCompletedScan: Bool {
        hasPhotoAccess
    }
}
#endif
