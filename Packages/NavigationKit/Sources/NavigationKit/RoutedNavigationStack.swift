import Observation
import SwiftUI

public struct RoutedNavigationStack<Route: Hashable, Root: View, Destination: View>: View {
    @State private var router: StackRouter<Route>

    private let onPathChange: ([Route]) -> Void
    private let root: (StackRouter<Route>) -> Root
    private let destination: (Route, StackRouter<Route>) -> Destination

    public init(
        initialPath: [Route] = [],
        onPathChange: @escaping ([Route]) -> Void = { _ in },
        @ViewBuilder root: @escaping (StackRouter<Route>) -> Root,
        @ViewBuilder destination: @escaping (Route, StackRouter<Route>) -> Destination
    ) {
        self._router = State(wrappedValue: StackRouter(path: initialPath))
        self.onPathChange = onPathChange
        self.root = root
        self.destination = destination
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            root(router)
                .navigationDestination(for: Route.self) { route in
                    destination(route, router)
                }
        }
        .onChange(of: router.path) { _, newPath in
            onPathChange(newPath)
        }
    }
}

public extension RoutedNavigationStack where Route == Never, Destination == EmptyView {
    init(
        initialPath: [Never] = [],
        onPathChange: @escaping ([Never]) -> Void = { _ in },
        @ViewBuilder root: @escaping () -> Root
    ) {
        self.init(
            initialPath: initialPath,
            onPathChange: onPathChange,
            root: { _ in root() },
            destination: { _, _ in
                assertionFailure("RoutedNavigationStack with Route == Never cannot produce a destination")
                return EmptyView()
            }
        )
    }
}
