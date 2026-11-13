import Cleanup
import CleanupWorkspace
import Core
import PhotoAnalysis
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
