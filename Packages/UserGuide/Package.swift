// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UserGuide",
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
        .package(path: "../DesignSystem"),
        .package(path: "../NavigationKit"),
        .package(path: "../Purchases")
    ],
    targets: [
        .target(
            name: "UserGuide",
            dependencies: [
                "DesignSystem", "NavigationKit",
                .product(name: "PurchasesUI", package: "Purchases")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "UserGuideTests",
            dependencies: ["UserGuide"]
        ),
    ]
)
