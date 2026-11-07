// swift-tools-version: 6.0
// Template: the manifest of a new Feature package.
// Based on: Packages/Welcome/Package.swift.
// Replace `FeatureName`. Declare only the local packages that the source
// files use. Keep `defaultLocalization` and `resources` when the package has a
// `Resources/Localizable.xcstrings` (see Skills/Localization/spm-localization).
// A new package also needs, in the same pull request:
// 1. A new ADR for the package and its edges (Docs/adr/0004-package-dependencies.md
//    "Changes need an ADR"), plus its row in the ADR-0004 baseline table.
// 2. A line in `tools/package-categories`. `tools/check-package-graph` fails
//    for a package without a category or with an edge ADR-0004 does not permit.
// 3. `README.md` from ../package-readme-template.md.
// 4. The link in Alike/Alike.xcodeproj/project.pbxproj: 6 blocks next to a
//    sibling package (PBXBuildFile, Frameworks entry, packageProductDependencies,
//    packageReferences, XCLocalSwiftPackageReference,
//    XCSwiftPackageProductDependency), as in commit 968d3893. Do not use the
//    xcodeproj gem. Check with `plutil -lint` and a build.
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
