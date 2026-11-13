import Core
import Foundation
import Photos
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

    @Test(arguments: [true, false])
    func testPremiumOverridesStayInTheArgumentDomain(isPremium: Bool) throws {
        let defaults = try makeDefaults()
        let environment = FakeLibraryEnvironment(scenario: .oneCluster, isPremium: isPremium)
        environment.applyPremiumOverrides(to: defaults)

        for feature in PremiumFeature.allCases {
            #expect(defaults.bool(forKey: feature.debugOverrideDefaultsKey) == isPremium)
            #expect(defaults.persistentDomain(forName: suiteName)?[feature.debugOverrideDefaultsKey] == nil)
            #expect(environment.premiumAccess.hasAccess(to: feature) == isPremium)
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
