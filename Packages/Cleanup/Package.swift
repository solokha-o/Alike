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
        .package(path: "../Core"),
        .package(path: "../Storage"),
        .package(path: "../PhotoAnalysis"),
        .package(path: "../DesignSystem"),
        .package(path: "../Details"),
        .package(path: "../NavigationKit"),
        .package(path: "../Purchases")
    ],
    targets: [
        .target(
            name: "Cleanup",
            dependencies: [
                "Core", "Storage", "PhotoAnalysis", "DesignSystem", "Details", "NavigationKit",
                .product(name: "Purchases", package: "Purchases"),
                .product(name: "PurchasesUI", package: "Purchases")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CleanupTests",
            dependencies: ["Cleanup", "Core", "Storage", "PhotoAnalysis"]
        ),
    ]
)
