// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WidgetSupport",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "WidgetSupport",
            targets: ["WidgetSupport"]
        )
    ],
    targets: [
        // Deliberately dependency-free. The widget extension links this target and
        // nothing else from `Packages/`: `DesignSystem` drags in `lottie-spm`, which
        // never plays in WidgetKit and would be dead weight against the widget's
        // ~30 MB memory budget, and `Purchases` drags in StoreKit. Mapping the app's
        // domain types into `WidgetSnapshot` happens in the app target, which already
        // imports them.
        .target(
            name: "WidgetSupport",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "WidgetSupportTests",
            dependencies: ["WidgetSupport"]
        )
    ]
)
