// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoAnalysis",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PhotoAnalysis",
            targets: ["PhotoAnalysis"]
        ),
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "PhotoAnalysis",
            dependencies: ["Core"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "PhotoAnalysisTests",
            dependencies: ["PhotoAnalysis"]
        ),
    ]
)
