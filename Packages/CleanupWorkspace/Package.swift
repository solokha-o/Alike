// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanupWorkspace",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CleanupWorkspace",
            targets: ["CleanupWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Storage"),
        .package(path: "../PhotoAnalysis")
    ],
    targets: [
        .target(
            name: "CleanupWorkspace",
            dependencies: ["Core", "Storage", "PhotoAnalysis"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ]
)
