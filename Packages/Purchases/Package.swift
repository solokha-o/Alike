// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Purchases",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Purchases", targets: ["Purchases"]),
        .library(name: "PurchasesUI", targets: ["PurchasesUI"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../NavigationKit")
    ],
    targets: [
        .target(
            name: "Purchases",
            dependencies: ["Core"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "PurchasesUI",
            dependencies: ["Purchases", "Core", "DesignSystem", "NavigationKit"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "PurchasesTests",
            dependencies: ["Purchases", "Core"]
        ),
        .testTarget(
            name: "PurchasesUITests",
            dependencies: ["PurchasesUI", "Purchases", "Core"]
        ),
    ]
)
