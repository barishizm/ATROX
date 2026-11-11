// swift-tools-version: 6.2
import PackageDescription

// CoachKit: SSE client, message/tool-event models, stream state machine. Foundation only.

let package = Package(
    name: "CoachKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CoachKit", targets: ["CoachKit"])
    ],
    targets: [
        .target(
            name: "CoachKit",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "CoachKitTests",
            dependencies: ["CoachKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
