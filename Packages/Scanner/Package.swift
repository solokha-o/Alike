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
        .package(path: "../DesignSystem"),
        .package(path: "../Cleanup"),
        .package(path: "../NavigationKit"),
        .package(path: "../Purchases"),
        .package(path: "../UserGuide")
    ],
    targets: [
        .target(
            name: "Scanner",
            dependencies: [
                "Core", "DesignSystem", "Cleanup", "NavigationKit", "UserGuide",
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
