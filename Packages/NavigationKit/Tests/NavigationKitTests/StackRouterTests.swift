import SwiftUI
import XCTest
@testable import NavigationKit

@MainActor
final class StackRouterTests: XCTestCase {
    func testPushAppendsRoute() {
        let router = StackRouter<Int>()

        router.push(1)
        router.push(2)

        XCTAssertEqual(router.path, [1, 2])
        XCTAssertEqual(router.currentRoute, 2)
    }

    func testPopRemovesLastRouteWhenPresent() {
        let router = StackRouter(path: [1, 2, 3])

        router.pop()

        XCTAssertEqual(router.path, [1, 2])
        XCTAssertEqual(router.currentRoute, 2)
    }

    func testPopOnEmptyPathIsNoOp() {
        let router = StackRouter<String>()

        router.pop()

        XCTAssertTrue(router.path.isEmpty)
    }

    func testReplacePathSwapsNavigationState() {
        let router = StackRouter(path: ["auth"])

        router.replace(path: ["auth", "channels"])

        XCTAssertEqual(router.path, ["auth", "channels"])
        XCTAssertEqual(router.currentRoute, "channels")
    }

    func testPopToRootClearsPath() {
        let router = StackRouter(path: [1, 2, 3])

        router.popToRoot()

        XCTAssertTrue(router.path.isEmpty)
        XCTAssertNil(router.currentRoute)
    }

    func testRouteLessStackInitializerBuildsRootContent() {
        var didBuildRoot = false

        func makeRoot() -> Text {
            didBuildRoot = true
            return Text("Modal")
        }

        let stack = RoutedNavigationStack(root: makeRoot)

        _ = stack.body

        XCTAssertTrue(didBuildRoot)
    }
}
