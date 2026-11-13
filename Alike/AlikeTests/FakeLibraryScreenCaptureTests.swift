import CleanupWorkspace
import Core
import Launch
import Photos
import PurchasesUI
import Scanner
import Settings
import SwiftUI
import Testing
import UserGuide
import Welcome
@testable import Alike
@testable import Cleanup
@testable import Details

/// Draws every main screen with fake library data, for the iPad layout audit.
///
/// The simulator cannot form clusters, so these screens never get data from a real
/// scan there. Each test builds a `FakeLibraryEnvironment`, the same one the
/// `-AlikeFakeLibrary` launch argument uses, and draws the screen in the test host.
///
/// The suite runs only when `TEST_RUNNER_ALIKE_SCREENSHOT_DIR` is set in the shell
/// before `xcodebuild`, so a normal test run stays fast. Grant photo access first
/// (`xcrun simctl privacy <udid> grant photos com.alike.app`): the first run draws
/// the scenario photos into an album. See `Docs/images/ipad/baseline/README.md`.
@MainActor
@Suite(
    .serialized,
    .enabled(if: ScreenCaptureHost.outputFolder != nil, "Set TEST_RUNNER_ALIKE_SCREENSHOT_DIR to capture")
)
struct FakeLibraryScreenCaptureTests {
    // MARK: - Launch and Welcome

    @Test func testLaunch() async throws {
        try await capture("launch") {
            LaunchView(isCompleted: .constant(false))
        }
    }

    @Test func testWelcomeWithoutPhotoAccess() async throws {
        let environment = FakeLibraryEnvironment(scenario: .noPhotosAccess, isPremium: false)
        try await capture("welcome-no-photos-access") {
            WelcomeView(
                isCompleted: .constant(false),
                mode: .permissionRequest,
                viewModel: WelcomeViewModel(permissionManager: environment.permissionManager)
            )
        }
    }

    // MARK: - Scanner

    @Test(arguments: [FakeLibraryScenario.empty, .manyClusters])
    func testScanner(scenario: FakeLibraryScenario) async throws {
        let (environment, workspace) = try await prepared(scenario)
        try await capture("scanner-\(scenario.rawValue)") {
            ScannerView(
                workspace: workspace,
                sensitivity: .constant(.medium),
                viewModel: ScannerViewModel(
                    workspace: workspace,
                    premiumAccess: environment.premiumAccess
                )
            )
        }
    }

    // MARK: - Cleanup

    @Test(arguments: [
        (FakeLibraryScenario.empty, false),
        (.manyClusters, false),
        (.largeCluster, true),
        (.afterCleanup, false),
    ])
    func testCleanup(scenario: FakeLibraryScenario, isPremium: Bool) async throws {
        let (environment, workspace) = try await prepared(scenario, isPremium: isPremium)
        let suffix = isPremium ? "-premium" : ""
        try await capture("cleanup-\(scenario.rawValue)\(suffix)") {
            CleanupView(
                workspace: workspace,
                sensitivity: .constant(.medium),
                premiumAccess: environment.premiumAccess,
                ratingPrompt: RatingPromptCoordinator(repository: environment.ratingPromptRepository),
                onOpenScanner: {},
                onRequestScan: {}
            ) { _ in
                EmptyView()
            } screenshotDestination: { _ in
                EmptyView()
            }
        }
    }

    @Test func testCleanupHistory() async throws {
        let (environment, _) = try await prepared(.afterCleanup)
        try await capture("cleanup-history") {
            NavigationStack {
                CleanupHistoryView(repository: environment.historyRepository)
            }
        }
    }

    // MARK: - Details

    @Test(arguments: [FakeLibraryScenario.oneCluster, .largeCluster])
    func testClusterDetails(scenario: FakeLibraryScenario) async throws {
        let (environment, workspace) = try await prepared(scenario)
        let cluster = try #require(environment.clusters.first)
        // An unreviewed group shows the comparison artwork in its summary card.
        try await capture("details-\(scenario.rawValue)") {
            NavigationStack {
                ClusterDetailsView(
                    cluster: cluster,
                    cleanupService: environment.cleanupService,
                    cleanupHistoryRepository: environment.historyRepository,
                    premiumAccess: environment.premiumAccess,
                    qualityAnalyzer: workspace.qualityAnalyzer,
                    enhancementService: workspace.enhancementService,
                    overrideMetrics: workspace.bestShotOverrideMetrics,
                    personalizedConfigProvider: workspace.bestShotPersonalizedConfigProvider
                )
            }
        }
    }

    /// Finishing the review starts the celebration; it plays for 4 s.
    @Test func testBestShotCelebration() async throws {
        let (environment, _) = try await prepared(.oneCluster)
        let cluster = try #require(environment.clusters.first)
        let viewModel = ClusterDetailsViewModel(
            cluster: cluster,
            reviewRepository: environment.reviewRepository,
            cleanupService: environment.cleanupService,
            cleanupHistoryRepository: environment.historyRepository,
            premiumAccess: environment.premiumAccess,
            qualityAnalyzer: environment.qualityAnalyzer
        )
        let host = try ScreenCaptureHost {
            NavigationStack {
                ClusterDetailsView(cluster: cluster, viewModel: viewModel)
            }
        }
        defer { host.close() }
        try await host.settle()
        viewModel.toggleReviewConfirmation()
        try await host.settle(for: .seconds(1))
        #expect(viewModel.bestShotCelebrationCue != nil)
        try host.capture("details-best-shot-celebration")
    }

    @Test func testFullscreenZoom() async throws {
        let (environment, _) = try await prepared(.oneCluster)
        let cluster = try #require(environment.clusters.first)
        try await capture("details-fullscreen") {
            FullscreenPhotoPagerView(assets: cluster.assets, selectedIndex: 0)
        }
    }

    // MARK: - Settings, Paywall, User Guide

    @Test(arguments: [false, true])
    func testSettings(isPremium: Bool) async throws {
        let environment = FakeLibraryEnvironment(scenario: .oneCluster, isPremium: isPremium)
        try await capture(isPremium ? "settings-premium" : "settings-free") {
            SettingsView(
                sensitivity: .constant(.medium),
                needsRescan: .constant(false),
                premiumAccess: environment.premiumAccess,
                viewModel: SettingsViewModel(cleanupReminderManager: environment.reminderManager)
            )
        }
    }

    /// Drawn as shipped: the paywall is not changed while its experiment runs.
    @Test func testPaywall() async throws {
        try await capture("paywall") {
            SubscriptionPaywallView(context: .general)
        }
    }

    @Test func testUserGuide() async throws {
        try await capture("user-guide") {
            UserGuideSheet()
        }
        try await capture("user-guide-topic") {
            NavigationStack {
                UserGuideTopicView(topicID: .comparingPhotos)
            }
        }
    }

    // MARK: - Helpers

    private func capture(
        _ name: String,
        settle: Duration = .seconds(2),
        @ViewBuilder content: () -> some View
    ) async throws {
        let host = try ScreenCaptureHost(content: content)
        defer { host.close() }
        // The first draw warms PhotoKit; the second, after the wait, is the one kept.
        host.draw()
        try await host.settle(for: settle)
        try host.capture(name)
    }

    /// A filled environment and its loaded workspace. Fails when a scenario that
    /// needs photos got none: a capture with empty groups is not evidence.
    private func prepared(
        _ scenario: FakeLibraryScenario,
        isPremium: Bool = false
    ) async throws -> (FakeLibraryEnvironment, CleanupWorkspaceModel) {
        // Never ask for access here: a system alert would hang the run.
        let environment = FakeLibraryEnvironment(
            scenario: scenario,
            isPremium: isPremium,
            requestsPhotoAccess: false
        )
        await environment.prepare()
        try #require(
            environment.clusters.count == scenario.clusterSizes.count,
            "No fake library photos: grant photo access to com.alike.app first"
        )
        let workspace = environment.makeWorkspace()
        await workspace.loadCachedContent()
        return (environment, workspace)
    }
}
