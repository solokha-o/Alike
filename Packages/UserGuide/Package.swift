// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UserGuide",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "UserGuide",
            targets: ["UserGuide"]
        ),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../NavigationKit"),
        .package(path: "../Purchases")
    ],
    targets: [
        .target(
            name: "UserGuide",
            dependencies: [
                "Core", "DesignSystem", "NavigationKit",
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
            name: "UserGuideTests",
            dependencies: ["UserGuide", "Core"]
        ),
    ]
)
