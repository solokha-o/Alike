// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Purchases",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Purchases", targets: ["Purchases"]),
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "Purchases",
            dependencies: ["Core"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "PurchasesTests",
            dependencies: ["Purchases", "Core"]
        ),
    ]
)
