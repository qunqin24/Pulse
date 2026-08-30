// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Pulse",
    // Required for the localized resources in Sources/Pulse/Resources/*.lproj.
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Pulse", targets: ["Pulse"])
    ],
    dependencies: [
        // In-place updates. Sparkle needs its framework embedded in the app
        // bundle, which Scripts/bundle.sh does — a bare `swift run` build
        // links against it but has nowhere to put it, so the updater is
        // inert there. See AppUpdate.swift.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Pulse",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Pulse",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
