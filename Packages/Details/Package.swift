// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Details",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Details",
            targets: ["Details"]
        ),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "Details",
            dependencies: ["Core", "DesignSystem"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DetailsTests",
            dependencies: ["Details"]
        ),
    ]
)
