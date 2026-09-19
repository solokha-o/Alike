// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Diagnostics",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Diagnostics",
            targets: ["Diagnostics"]
        )
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        // Depends on `Core` only. The crash prompt is plain SwiftUI on purpose:
        // `DesignSystem` drags in `lottie-spm`, and nothing here needs it.
        .target(
            name: "Diagnostics",
            dependencies: ["Core"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
