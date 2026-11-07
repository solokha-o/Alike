// swift-tools-version: 6.0
// Template: the manifest of a new Feature package.
// Based on: Packages/Welcome/Package.swift.
// Replace `FeatureName`. Declare only the local packages that the source
// files use. `tools/check-package-graph` rejects an edge that ADR-0004 does
// not permit. Keep `defaultLocalization` and `resources` when the package has a
// `Resources/Localizable.xcstrings` (see Skills/Localization/spm-localization).
import PackageDescription

let package = Package(
    name: "FeatureName",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FeatureName",
            targets: ["FeatureName"]
        ),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "FeatureName",
            dependencies: [
                "Core",
                "DesignSystem"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FeatureNameTests",
            dependencies: ["FeatureName", "Core"]
        ),
    ]
)
