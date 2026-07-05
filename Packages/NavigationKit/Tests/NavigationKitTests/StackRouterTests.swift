import Testing
@testable import NavigationKit

@Suite("StackRouter")
@MainActor
struct StackRouterTests {
    @Test("Push appends route to path")
    func pushAppendsRoute() {
        let router = StackRouter<Int>()

        router.push(1)
        router.push(2)

        #expect(router.path == [1, 2])
        #expect(router.currentRoute == 2)
    }

    @Test("Pop removes last route when present")
    func popRemovesLastRoute() {
        let router = StackRouter(path: [1, 2, 3])

        router.pop()

        #expect(router.path == [1, 2])
        #expect(router.currentRoute == 2)
    }

    @Test("Pop on empty path is no-op")
    func popOnEmptyPathIsNoOp() {
        let router = StackRouter<String>()

        router.pop()

        #expect(router.path.isEmpty)
    }

    @Test("Replace path swaps navigation state")
    func replaceSwapsPath() {
        let router = StackRouter(path: ["auth"])

        router.replace(path: ["auth", "channels"])

        #expect(router.path == ["auth", "channels"])
        #expect(router.currentRoute == "channels")
    }

    @Test("Pop to root clears all routes")
    func popToRootClearsPath() {
        let router = StackRouter(path: [1, 2, 3])

        router.popToRoot()

        #expect(router.path.isEmpty)
        #expect(router.currentRoute == nil)
    }
}
