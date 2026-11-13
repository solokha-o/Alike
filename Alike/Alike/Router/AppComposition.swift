import Cleanup
import CleanupWorkspace
import Core
import PhotoAnalysis
import Purchases
import Scanner
import Storage
import Welcome

/// The few dependencies `RootView` builds that a DEBUG fake library replaces.
///
/// In Release every function returns the production type, exactly as `RootView`
/// built it before. The fake branch is compiled only into DEBUG builds.
enum AppComposition {
    /// `true` while a `-AlikeFakeLibrary` scenario runs. Always `false` in Release.
    static var isFakeLibraryActive: Bool {
#if DEBUG
        FakeLibraryEnvironment.current != nil
#else
        false
#endif
    }

    static func makePhotoPermissionManager() -> any PhotoPermissionManager {
#if DEBUG
        if let fake = FakeLibraryEnvironment.current {
            return fake.permissionManager
        }
#endif
        return PhotoPermissionManagerImpl()
    }

    static func makeCleanupWorkspace() -> CleanupWorkspaceModel {
#if DEBUG
        if let fake = FakeLibraryEnvironment.current {
            return fake.makeWorkspace()
        }
#endif
        return CleanupWorkspaceModel()
    }

    static func makeCleanupReminderManager() -> any CleanupReminderManaging {
#if DEBUG
        if let fake = FakeLibraryEnvironment.current {
            return fake.reminderManager
        }
#endif
        return CleanupReminderManager(preferenceRepository: UserDefaultsCleanupReminderPreferenceRepository())
    }

    static func makeRatingPrompt() -> RatingPromptCoordinator {
#if DEBUG
        if let fake = FakeLibraryEnvironment.current {
            return RatingPromptCoordinator(repository: fake.ratingPromptRepository)
        }
#endif
        return RatingPromptCoordinator(repository: UserDefaultsRatingPromptHistoryRepository())
    }

    /// DEBUG keeps the Premium debug toggles on top of StoreKit; a fake library
    /// answers from its scenario instead. Release uses StoreKit alone.
    static func makePremiumAccess(base: SubscriptionStore) -> any PremiumAccessControlling {
#if DEBUG
        makePremiumAccess(base: base, fake: FakeLibraryEnvironment.current)
#else
        base
#endif
    }

    static func makeScannerViewModel(
        workspace: CleanupWorkspaceModel,
        sensitivity: SensitivityLevel,
        premiumAccess: any PremiumAccessControlling
    ) -> ScannerViewModel {
#if DEBUG
        if let stores = scannerStores(fake: FakeLibraryEnvironment.current) {
            return ScannerViewModel(
                workspace: workspace,
                sensitivity: sensitivity,
                premiumAccess: premiumAccess,
                scanUsageRepository: stores.scanUsage,
                premiumPromptHistoryRepository: stores.premiumPrompt
            )
        }
#endif
        return ScannerViewModel(workspace: workspace, sensitivity: sensitivity, premiumAccess: premiumAccess)
    }

    /// The store Details reads and writes review state in. Release keeps the
    /// file store `ClusterDetailsView` used before this parameter existed.
    static func makeDetailsReviewRepository() -> any ClusterReviewStateRepository {
#if DEBUG
        makeDetailsReviewRepository(fake: FakeLibraryEnvironment.current)
#else
        FileClusterReviewStateRepository()
#endif
    }

#if DEBUG
    // The forms below take the environment as a parameter, so tests can pass one;
    // the app passes `FakeLibraryEnvironment.current`.

    static func makePremiumAccess(
        base: SubscriptionStore,
        fake: FakeLibraryEnvironment?
    ) -> any PremiumAccessControlling {
        if let fake {
            return fake.premiumAccess
        }
        return DebugPremiumAccessController(base: base)
    }

    /// The Scanner's scan counts and prompt history, or `nil` for the real ones.
    static func scannerStores(
        fake: FakeLibraryEnvironment?
    ) -> (scanUsage: any ScanUsageRepository, premiumPrompt: any PremiumPromptHistoryRepository)? {
        guard let fake else { return nil }
        return (fake.scanUsageRepository, fake.premiumPromptRepository)
    }

    static func makeDetailsReviewRepository(fake: FakeLibraryEnvironment?) -> any ClusterReviewStateRepository {
        if let fake {
            return fake.reviewRepository
        }
        return FileClusterReviewStateRepository()
    }
#endif

    /// `nil` keeps `WelcomeView`'s own default view model.
    static func makeWelcomeViewModel() -> WelcomeViewModel? {
#if DEBUG
        if let fake = FakeLibraryEnvironment.current {
            return WelcomeViewModel(permissionManager: fake.permissionManager)
        }
#endif
        return nil
    }

    /// Runs while the launch screen shows. Fills the fake library in DEBUG.
    static func prepareLaunch() async {
#if DEBUG
        await FakeLibraryEnvironment.current?.prepare()
#endif
    }
}
