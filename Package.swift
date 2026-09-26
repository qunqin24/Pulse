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
            ],
            linkerSettings: [
                // macOS picks which control design to draw from the SDK
                // version recorded in LC_BUILD_VERSION, not from the version
                // it is running on. Below 26 it draws the pre-Tahoe controls,
                // and no Info.plist key opts back in.
                //
                // SwiftPM records the wrong thing here: given `.macOS(.v14)`
                // above it stamps that **deployment target** into the SDK
                // field, so every build — `swift run`, `swift build`, and
                // running the package from Xcode — comes out drawn the old
                // way. Measured 2026-09-20: 14.0 draws the old controls, 26.5
                // and 27.0 both draw the current ones.
                //
                // 26.0 is the floor this app already requires (`glassEffect`
                // needs that SDK to compile at all), stated as a floor rather
                // than as whichever SDK happens to be installed, because a
                // manifest cannot ask the toolchain. Scripts/bundle.sh stamps
                // the real SDK over this for releases and then reads the
                // result back off every slice.
                .unsafeFlags(["-Xlinker", "-platform_version",
                              "-Xlinker", "macos",
                              "-Xlinker", "14.0",
                              "-Xlinker", "26.0"])
            ]
        ),
        // Tests the executable target directly rather than through a library
        // split. Pulse is one app, not a framework with an app on top, and
        // carving the app's files into two targets to make them reachable
        // would be a refactor in service of the test runner. SwiftPM has been
        // able to `@testable import` an executable target since Swift 5.5.
        .testTarget(
            name: "PulseTests",
            dependencies: ["Pulse"],
            path: "Tests/PulseTests",
            // Captured provider replies, kept as the files they arrived as so
            // a diff against a changed schema is readable.
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
