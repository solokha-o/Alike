// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NavigationKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NavigationKit",
            targets: ["NavigationKit"]
        )
    ],
    targets: [
        .target(
            name: "NavigationKit",
            path: "Sources/NavigationKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "NavigationKitTests",
            dependencies: ["NavigationKit"],
            path: "Tests/NavigationKitTests"
        )
    ]
)
