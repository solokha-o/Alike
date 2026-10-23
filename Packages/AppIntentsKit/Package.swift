// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppIntentsKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AppIntentsKit",
            targets: ["AppIntentsKit"]
        )
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        // Depends on `Core` only. Intents and entities reach the live app state through
        // the `AppIntentsEnvironmentProviding` and `ClusterIndexSource` protocols that
        // the app target registers with `AppDependencyManager`, so this package never
        // links `Cleanup`, `Scanner`, `Purchases` or `WidgetSupport`.
        .target(
            name: "AppIntentsKit",
            dependencies: ["Core"],
            resources: [.process("Resources")],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AppIntentsKitTests",
            dependencies: ["AppIntentsKit"]
        )
    ]
)
