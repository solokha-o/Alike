// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cleanup",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Cleanup",
            targets: ["Cleanup"]
        ),
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "Cleanup",
            dependencies: ["Core"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CleanupTests",
            dependencies: ["Cleanup", "Core"]
        ),
    ]
)
