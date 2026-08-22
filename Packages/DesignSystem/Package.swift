// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DesignSystem",
            targets: ["DesignSystem"]
        ),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.6.1")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [
                "Core",
                .product(name: "Lottie", package: "lottie-spm")
            ],
            exclude: [
                // Asset-licensing notice, not a build input. Excluding it keeps
                // the file next to the assets it covers without adding it to
                // the processed resource bundle.
                "Resources/LICENSE"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem", "Core"]
        ),
    ]
)
