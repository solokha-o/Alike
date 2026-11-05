import SwiftUI
import Testing
@testable import NavigationKit

@MainActor
@Suite struct StackRouterTests {
    @Test func testPushAppendsRoute() {
        let router = StackRouter<Int>()

        router.push(1)
        router.push(2)

        #expect(router.path == [1, 2])
        #expect(router.currentRoute == 2)
    }

    @Test func testPopRemovesLastRouteWhenPresent() {
        let router = StackRouter(path: [1, 2, 3])

        router.pop()

        #expect(router.path == [1, 2])
        #expect(router.currentRoute == 2)
    }

    @Test func testPopOnEmptyPathIsNoOp() {
        let router = StackRouter<String>()

        router.pop()

        #expect(router.path.isEmpty)
    }

    @Test func testReplacePathSwapsNavigationState() {
        let router = StackRouter(path: ["auth"])

        router.replace(path: ["auth", "channels"])

        #expect(router.path == ["auth", "channels"])
        #expect(router.currentRoute == "channels")
    }

    @Test func testPopToRootClearsPath() {
        let router = StackRouter(path: [1, 2, 3])

        router.popToRoot()

        #expect(router.path.isEmpty)
        #expect(router.currentRoute == nil)
    }

    @Test func testRouteLessStackInitializerBuildsRootContent() {
        var didBuildRoot = false

        func makeRoot() -> Text {
            didBuildRoot = true
            return Text("Modal")
        }

        let stack = RoutedNavigationStack(root: makeRoot)

        _ = stack.body

        #expect(didBuildRoot)
    }
}
