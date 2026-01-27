// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Welcome",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Welcome",
            targets: ["Welcome"]
        ),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../PhotoAnalysis"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "Welcome",
            dependencies: ["Core", "PhotoAnalysis", "DesignSystem"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "WelcomeTests",
            dependencies: ["Welcome", "Core"]
        ),
    ]
)
