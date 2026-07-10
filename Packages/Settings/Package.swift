// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Settings",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Settings",
            targets: ["Settings"]
        ),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../NavigationKit"),
        .package(path: "../Cleanup"),
        .package(path: "../Storage")
    ],
    targets: [
        .target(
            name: "Settings",
            dependencies: ["Core", "DesignSystem", "NavigationKit", "Cleanup", "Storage"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SettingsTests",
            dependencies: ["Settings", "Core"]
        ),
    ]
)
