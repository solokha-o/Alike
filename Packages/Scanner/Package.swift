// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scanner",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
        .package(path: "../Details"),
        .package(path: "../Cleanup"),
        .package(path: "../NavigationKit"),
        .package(path: "../Purchases")
    ],
    targets: [
        .target(
            name: "Scanner",
            dependencies: [
                "Core", "Storage", "PhotoAnalysis", "DesignSystem", "Details", "Cleanup", "NavigationKit",
                .product(name: "Purchases", package: "Purchases"),
                .product(name: "PurchasesUI", package: "Purchases")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ScannerTests",
            dependencies: ["Scanner", "Core", "Cleanup"]
        ),
    ]
)
