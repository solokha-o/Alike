// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scanner",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Scanner",
            targets: ["Scanner"]
        ),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Storage"),
        .package(path: "../PhotoAnalysis"),
        .package(path: "../DesignSystem"),
        .package(path: "../Details")
    ],
    targets: [
        .target(
            name: "Scanner",
            dependencies: ["Core", "Storage", "PhotoAnalysis", "DesignSystem", "Details"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ScannerTests",
            dependencies: ["Scanner"]
        ),
    ]
)
