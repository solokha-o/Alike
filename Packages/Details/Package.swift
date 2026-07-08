// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Details",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Details",
            targets: ["Details"]
        ),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Storage"),
        .package(path: "../NavigationKit")
    ],
    targets: [
        .target(
            name: "Details",
            dependencies: ["Core", "DesignSystem", "Storage", "NavigationKit"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DetailsTests",
            dependencies: ["Details"]
        ),
    ]
)
