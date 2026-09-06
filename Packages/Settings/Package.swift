// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Settings",
    defaultLocalization: "en",
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
        .package(path: "../Storage"),
        .package(path: "../Purchases"),
        .package(path: "../UserGuide"),
        .package(path: "../PhotoAnalysis")
    ],
    targets: [
        .target(
            name: "Settings",
            dependencies: [
                "Core", "DesignSystem", "NavigationKit", "Cleanup", "Storage", "UserGuide", "PhotoAnalysis",
                .product(name: "Purchases", package: "Purchases"),
                .product(name: "PurchasesUI", package: "Purchases")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SettingsTests",
            dependencies: ["Settings", "Core", "Cleanup"]
        ),
    ]
)
