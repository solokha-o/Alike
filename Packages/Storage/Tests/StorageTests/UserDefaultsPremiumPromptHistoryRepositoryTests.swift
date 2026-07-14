import XCTest
import Foundation
@testable import Storage

final class UserDefaultsPremiumPromptHistoryRepositoryTests: XCTestCase {
    private var key: String!

    override func setUp() {
        key = "premium.prompt.test.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        key = nil
    }

    func testClaimSucceedsExactlyOnceAndSurvivesRepositoryRecreation() async {
        let firstRepository = makeRepository()

        let firstClaim = await firstRepository.claimPostFirstUsefulScanPrompt()
        let secondClaim = await firstRepository.claimPostFirstUsefulScanPrompt()
        let relaunchedClaim = await makeRepository().claimPostFirstUsefulScanPrompt()

        XCTAssertTrue(firstClaim)
        XCTAssertFalse(secondClaim)
        XCTAssertFalse(relaunchedClaim)
    }

    func testConcurrentClaimsProduceOneWinner() async {
        let repository = makeRepository()

        let claims = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<20 {
                group.addTask { await repository.claimPostFirstUsefulScanPrompt() }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertEqual(claims.filter { $0 }.count, 1)
    }

    func testConcurrentClaimsAcrossRepositoryInstancesProduceOneWinner() async {
        let repositories = (0..<100).map { _ in makeRepository() }

        let claims = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for repository in repositories {
                group.addTask { await repository.claimPostFirstUsefulScanPrompt() }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertEqual(claims.filter { $0 }.count, 1)
    }

    func testReleasedClaimCanBeClaimedAgain() async {
        let repository = makeRepository()
        let firstClaim = await repository.claimPostFirstUsefulScanPrompt()

        XCTAssertTrue(firstClaim)
        await repository.releasePostFirstUsefulScanPromptClaim()

        let reclaimed = await makeRepository().claimPostFirstUsefulScanPrompt()
        XCTAssertTrue(reclaimed)
    }

    private func makeRepository() -> UserDefaultsPremiumPromptHistoryRepository {
        UserDefaultsPremiumPromptHistoryRepository(postFirstUsefulScanKey: key)
    }
}
