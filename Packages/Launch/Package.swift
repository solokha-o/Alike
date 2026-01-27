// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Launch",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Launch",
            targets: ["Launch"]
        ),
    ],
    dependencies: [
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "Launch",
            dependencies: ["DesignSystem"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LaunchTests",
            dependencies: ["Launch"]
        ),
    ]
)
