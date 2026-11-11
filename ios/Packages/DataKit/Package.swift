// swift-tools-version: 6.2
import PackageDescription

// DataKit: SwiftData models, repositories, sync engine and the Supabase client.
// supabase-swift: latest stable release verified on GitHub (supabase/supabase-swift releases).

let package = Package(
    name: "DataKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DataKit", targets: ["DataKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.6")
    ],
    targets: [
        .target(
            name: "DataKit",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "DataKitTests",
            dependencies: ["DataKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
