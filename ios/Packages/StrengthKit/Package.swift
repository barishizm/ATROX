// swift-tools-version: 6.2
import PackageDescription

// StrengthKit: pure-Swift scoring engine. Depends on Foundation ONLY and must build and
// test on Linux as well as Apple platforms (fast CI).
//
// NOTE: Code that uses Core ML must live behind `#if canImport(CoreML)` (added in a later
// step: model package loading/inference). Never `import CoreML` unconditionally, and do not
// add any non-Foundation dependency to this package.

let package = Package(
    name: "StrengthKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "StrengthKit", targets: ["StrengthKit"])
    ],
    targets: [
        .target(
            name: "StrengthKit",
            // Embedded base model bundle (P060 `make export`); the app works offline from first launch.
            resources: [.copy("Resources/ModelBundle")],
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "StrengthKitTests",
            dependencies: ["StrengthKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
