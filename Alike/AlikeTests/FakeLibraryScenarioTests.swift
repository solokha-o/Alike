import Core
import Foundation
import Photos
import Purchases
import Storage
import Testing
@testable import Alike

/// Pins the `-AlikeFakeLibrary` launch argument and the shape of each scenario.
@MainActor
struct FakeLibraryScenarioTests {
    @Test func testLaunchArgumentNamesTheScenario() throws {
        let defaults = try makeDefaults()
        defaults.set("manyClusters", forKey: FakeLibraryScenario.launchArgumentKey)
        defaults.set(true, forKey: FakeLibraryScenario.premiumLaunchArgumentKey)

        #expect(FakeLibraryScenario.fromLaunchArguments(defaults) == .manyClusters)
        #expect(FakeLibraryScenario.isPremiumFromLaunchArguments(defaults))
    }

    @Test func testNoOrUnknownArgumentKeepsTheRealLibrary() throws {
        let defaults = try makeDefaults()
        #expect(FakeLibraryScenario.fromLaunchArguments(defaults) == nil)
        #expect(!FakeLibraryScenario.isPremiumFromLaunchArguments(defaults))

        defaults.set("everything", forKey: FakeLibraryScenario.launchArgumentKey)
        #expect(FakeLibraryScenario.fromLaunchArguments(defaults) == nil)
    }

    /// The real app runs without the argument, so the shared environment must be off.
    @Test func testTestHostRunsWithoutAFakeLibrary() {
        #expect(FakeLibraryEnvironment.current == nil)
        #expect(!AppComposition.isFakeLibraryActive)
    }

    @Test(arguments: [
        (FakeLibraryScenario.empty, 0, 0),
        (.oneCluster, 1, 4),
        (.manyClusters, 55, 3),
        (.largeCluster, 3, 32),
        (.afterCleanup, 6, 5),
        (.noPhotosAccess, 0, 0),
    ])
    func testScenarioShape(scenario: FakeLibraryScenario, clusterCount: Int, largestCluster: Int) {
        let assets = (0 ..< 80).map { FakeLibraryTestAsset("asset-\($0)") }
        let clusters = FakeLibraryEnvironment.makeClusters(for: scenario, from: assets)

        #expect(clusters.count == clusterCount)
        #expect((clusters.map(\.count).max() ?? 0) == largestCluster)
        #expect(scenario.requiredPhotoCount + scenario.categoryPhotoCount <= FakeLibraryPhotoStore.seededPhotoCount)
    }

    /// Groups that held the same photos would share a view identity in Cleanup.
    @Test func testEveryGroupHasItsOwnPhotos() {
        let assets = (0 ..< FakeLibraryPhotoStore.seededPhotoCount).map { FakeLibraryTestAsset("asset-\($0)") }
        for scenario in FakeLibraryScenario.allCases {
            let clusters = FakeLibraryEnvironment.makeClusters(for: scenario, from: assets)
            let photoSets = clusters.map { Set($0.assets.map(\.localIdentifier)) }
            #expect(Set(photoSets).count == clusters.count, "\(scenario)")
            #expect(Set(clusters.map(\.id)).count == clusters.count, "\(scenario)")
            #expect(clusters.allSatisfy { $0.count >= 2 }, "\(scenario)")
        }
    }

    /// Too few photos gives fewer groups, never a crash.
    @Test func testTooFewPhotosGiveFewerGroups() {
        let assets = (0 ..< 10).map { FakeLibraryTestAsset("asset-\($0)") }
        #expect(FakeLibraryEnvironment.makeClusters(for: .largeCluster, from: assets).isEmpty)
        #expect(FakeLibraryEnvironment.makeClusters(for: .manyClusters, from: assets).count == 8)
    }

    @Test func testNoPhotosAccessDeniesPermission() {
        let environment = FakeLibraryEnvironment(scenario: .noPhotosAccess, isPremium: false)
        #expect(environment.permissionManager.authorizationStatus == .denied)
        #expect(!environment.permissionManager.isAuthorized)
    }

    /// The fake answer replaces StoreKit's, so `NO` is free even with a sandbox
    /// subscription, and it matches what `AppComposition` hands to the screens.
    @Test(arguments: [true, false])
    func testPremiumFlagDecidesEveryFeature(isPremium: Bool) {
        let environment = FakeLibraryEnvironment(scenario: .oneCluster, isPremium: isPremium)
        #expect(environment.premiumAccess.entitlementState.isPremium == isPremium)
        for feature in PremiumFeature.allCases where feature != .unlimitedScans {
            #expect(environment.premiumAccess.hasAccess(to: feature) == isPremium, "\(feature)")
        }
    }

    /// A fake rescan must not use the real free scans.
    @Test func testScanCountsStayOutOfTheRealDefaults() async {
        let suiteName = "FakeLibraryScenarioTests.scanUsage.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let date = Date()
        let realBefore = await UserDefaultsScanUsageRepository().loadMonthlyUsage(at: date)
        let environment = FakeLibraryEnvironment(scenario: .oneCluster, isPremium: false, scanUsageSuiteName: suiteName)
        _ = await environment.scanUsageRepository.recordCompletedScan(at: date)

        #expect(await environment.scanUsageRepository.loadMonthlyUsage(at: date)?.completedScanCount == 1)
        #expect(await UserDefaultsScanUsageRepository().loadMonthlyUsage(at: date) == realBefore)

        // A new fake session starts with no scans counted.
        let next = FakeLibraryEnvironment(scenario: .oneCluster, isPremium: false, scanUsageSuiteName: suiteName)
        #expect(await next.scanUsageRepository.loadMonthlyUsage(at: date) == nil)
    }

    /// What `RootView` gets from `AppComposition`: the fake stores in fake mode, the
    /// shipped ones otherwise.
    @Test func testCompositionHandsTheFakeStoresToTheScreens() {
        let environment = FakeLibraryEnvironment(scenario: .oneCluster, isPremium: false)
        let store = SubscriptionStore(catalog: .production)

        let fakeAccess = AppComposition.makePremiumAccess(base: store, fake: environment)
        #expect(fakeAccess is MockPremiumAccessController)
        #expect(!fakeAccess.entitlementState.isPremium)
        #expect(AppComposition.makePremiumAccess(base: store, fake: nil) is DebugPremiumAccessController)

        let stores = AppComposition.scannerStores(fake: environment)
        #expect((stores?.scanUsage as? UserDefaultsScanUsageRepository) === environment.scanUsageRepository)
        #expect((stores?.premiumPrompt as? MockPremiumPromptHistoryRepository) === environment.premiumPromptRepository)
        #expect(AppComposition.scannerStores(fake: nil) == nil)

        let review = AppComposition.makeDetailsReviewRepository(fake: environment)
        #expect((review as? MockClusterReviewStateRepository) === environment.reviewRepository)
        #expect(AppComposition.makeDetailsReviewRepository(fake: nil) is FileClusterReviewStateRepository)

        // The real deleter opens the Core Data store when it is made.
        #expect(AppComposition.makeLocalAppDataDeleter(fake: environment) is FakeLibraryDataDeleter)
    }

    /// Each category card counts the photos its screen shows: the mock returns 1
    /// list for any category.
    @Test func testCategoryCountsMatchTheirScreens() async throws {
        let environment = FakeLibraryEnvironment(scenario: .manyClusters, isPremium: true, requestsPhotoAccess: false)
        await environment.prepare()
        let snapshots = try await environment.categoryRepository.loadAllSnapshots()
        let shown = try await environment.analysisService.loadAssets(for: .screenshots)
        for snapshot in snapshots.values {
            #expect(snapshot.assetCount == shown.count)
            #expect(snapshot.localIdentifiers == shown.map(\.localIdentifier))
        }
    }

    @Test func testDrawnPhotosAreJPEGs() {
        let data = FakeLibraryPhotoStore.photoData(index: 5)
        #expect(data.count > 10_000)
        #expect(data.starts(with: [0xFF, 0xD8]))
    }

    // MARK: - Helpers

    private let suiteName = "FakeLibraryScenarioTests"

    private func makeDefaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class FakeLibraryTestAsset: PHAsset, @unchecked Sendable {
    private let identifier: String

    init(_ identifier: String) {
        self.identifier = identifier
        super.init()
    }

    override var localIdentifier: String { identifier }
}
