import Observation

@MainActor
@Observable
public final class StackRouter<Route: Hashable> {
    public var path: [Route]

    public init(path: [Route] = []) {
        self.path = path
    }

    public var currentRoute: Route? {
        path.last
    }

    public func push(_ route: Route) {
        path.append(route)
    }

    public func push<S: Sequence>(contentsOf routes: S) where S.Element == Route {
        path.append(contentsOf: routes)
    }

    public func pop() {
        guard path.isEmpty == false else {
            return
        }
        path.removeLast()
    }

    public func popToRoot() {
        path.removeAll()
    }

    public func replace(path newPath: [Route]) {
        path = newPath
    }
}
