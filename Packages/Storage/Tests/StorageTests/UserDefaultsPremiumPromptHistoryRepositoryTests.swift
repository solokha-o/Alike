import Testing
import Foundation
@testable import Storage

/// A `final class` suite: each test gets its own `UserDefaults` suite, and `deinit`
/// removes it. The repository is an actor and `UserDefaults` is not `Sendable`, so
/// each repository gets its own `UserDefaults` instance of that suite.
@Suite final class UserDefaultsPremiumPromptHistoryRepositoryTests {
    private let suiteName = UUID().uuidString
    private let defaults: UserDefaults
    private let key = "premium.prompt.test.\(UUID().uuidString)"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func testClaimSucceedsExactlyOnceAndSurvivesRepositoryRecreation() async {
        let firstRepository = makeRepository()

        let firstClaim = await firstRepository.claimPostFirstUsefulScanPrompt()
        let secondClaim = await firstRepository.claimPostFirstUsefulScanPrompt()
        let relaunchedClaim = await makeRepository().claimPostFirstUsefulScanPrompt()

        #expect(firstClaim)
        #expect(!secondClaim)
        #expect(!relaunchedClaim)
    }

    @Test func testConcurrentClaimsProduceOneWinner() async {
        let repository = makeRepository()

        let claims = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<20 {
                group.addTask { await repository.claimPostFirstUsefulScanPrompt() }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(claims.filter { $0 }.count == 1)
    }

    @Test func testConcurrentClaimsAcrossRepositoryInstancesProduceOneWinner() async {
        let repositories = (0..<100).map { _ in makeRepository() }

        let claims = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for repository in repositories {
                group.addTask { await repository.claimPostFirstUsefulScanPrompt() }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(claims.filter { $0 }.count == 1)
    }

    @Test func testReleasedClaimCanBeClaimedAgain() async {
        let repository = makeRepository()
        let firstClaim = await repository.claimPostFirstUsefulScanPrompt()

        #expect(firstClaim)
        await repository.releasePostFirstUsefulScanPromptClaim()

        let reclaimed = await makeRepository().claimPostFirstUsefulScanPrompt()
        #expect(reclaimed)
    }

    private func makeRepository() -> UserDefaultsPremiumPromptHistoryRepository {
        UserDefaultsPremiumPromptHistoryRepository(defaults: UserDefaults(suiteName: suiteName)!, postFirstUsefulScanKey: key)
    }
}
