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
        (.store, 12, 4),
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

    /// The store screenshots need reviewed groups and a group to resume with a
    /// decision half made: Best Shot kept, 2 other photos selected.
    @Test func testStoreReviewStates() throws {
        let assets = (0 ..< 54).map { FakeLibraryTestAsset("asset-\($0)") }
        let clusters = FakeLibraryEnvironment.makeClusters(for: .store, from: assets)
        let states = FakeLibraryEnvironment.makeStoreReviewStates(for: clusters)

        #expect(states.count == 12)
        #expect(states.values.count { $0.status == .reviewed } == 6)
        #expect(states.values.count { $0.status == .inReview } == 6)
        for cluster in clusters {
            let state = try #require(states[cluster.id])
            #expect(state.bestShotLocalIdentifier == cluster.assets[1].localIdentifier)
            #expect(state.selectedLocalIdentifiers.count == 2)
            #expect(!state.selectedLocalIdentifiers.contains(state.bestShotLocalIdentifier))
        }
    }

    @Test func testStorePhotoFolderIsReadSortedFromTheEnvironment() throws {
        #expect(FakeLibraryPhotoStore.photoFolderFromEnvironment([:]) == nil)
        #expect(FakeLibraryPhotoStore.photoFolderFromEnvironment(["ALIKE_FAKE_LIBRARY_PHOTOS": ""]) == nil)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["b-02.jpg", "a-01.JPG", "notes.txt", "c-03.jpeg"] {
            try Data([0xFF]).write(to: folder.appendingPathComponent(name))
        }

        let resolved = try #require(FakeLibraryPhotoStore.photoFolderFromEnvironment(
            ["ALIKE_FAKE_LIBRARY_PHOTOS": folder.path]
        ))
        #expect(FakeLibraryPhotoStore.photoFiles(in: resolved).map(\.lastPathComponent)
            == ["a-01.JPG", "b-02.jpg", "c-03.jpeg"])
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
    @Test func testCategoryCountsMatchTheirScreens() {
        let shown = (0 ..< 6).map { FakeLibraryTestAsset("category-\($0)") }
        let snapshots = FakeLibraryEnvironment.makeCategorySnapshots(from: shown)

        #expect(Set(snapshots.keys) == Set(CleanupCategoryKind.allCases))
        for snapshot in snapshots.values {
            #expect(snapshot.assetCount == shown.count)
            #expect(snapshot.localIdentifiers == shown.map(\.localIdentifier))
        }
        #expect(FakeLibraryEnvironment.makeCategorySnapshots(from: []).isEmpty)
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
