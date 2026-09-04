// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BestShotCalibration",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "bestshot-calibrate",
            targets: ["BestShotCalibrationCLI"]
        ),
        // The logic is a product of its own so a throwaway analysis script can
        // measure a corpus without going through the CLI's argument parsing.
        .library(
            name: "BestShotCalibration",
            targets: ["BestShotCalibration"]
        ),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "BestShotCalibration",
            dependencies: ["Core"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "BestShotCalibrationCLI",
            dependencies: ["BestShotCalibration"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "BestShotCalibrationTests",
            dependencies: ["BestShotCalibration"]
        ),
    ]
)
