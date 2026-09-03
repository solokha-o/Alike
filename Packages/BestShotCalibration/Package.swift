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
