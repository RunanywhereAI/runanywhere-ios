// swift-tools-version: 6.2
// =============================================================================
// RunAnywhereAI - iOS Example App
// =============================================================================
//
// This example app demonstrates how to use the RunAnywhere SDK.
//
// The SDK is consumed entirely from the published GitHub release — no local
// checkout of the monorepo and no pre-built XCFrameworks are required.
// SwiftPM downloads the checksum-verified binary artifacts on resolve.
//
// SETUP (first time):
//   swift package resolve      # or just open the project in Xcode
//
// =============================================================================

import PackageDescription

let package = Package(
    name: "RunAnywhereAI",
    defaultLocalization: "en",
    platforms: [
        // Must be ≥ the RunAnywhere SDK platform floor so the remote
        // dependency on RunAnywhere / RunAnywhereONNX / RunAnywhereLlamaCPP
        // resolves cleanly (the SDK floor is iOS 17.5 / macOS 14.5).
        .iOS("17.5"),
        .macOS("14.5")
    ],
    products: [
        .library(
            name: "RunAnywhereAI",
            targets: ["RunAnywhereAI"]
        )
    ],
    dependencies: [
        // ===================================
        // RunAnywhere SDK (published GitHub release)
        // ===================================
        // The `runanywhere-sdks` package publishes:
        //   - RunAnywhere (core)
        //   - RunAnywhereONNX (STT/TTS/VAD)
        //   - RunAnywhereLlamaCPP (LLM)
        //   - RunAnywhereMLX (Apple MLX)
        //   - RunAnywhereNeuRT (Apple Neural Engine)
        //
        .package(
            url: "https://github.com/RunanywhereAI/runanywhere-sdks.git",
            from: "0.20.17"
        ),
    ],
    targets: [
        .target(
            name: "RunAnywhereAI",
            dependencies: [
                // Core SDK (always needed)
                .product(name: "RunAnywhere", package: "runanywhere-sdks"),

                // Optional modules - pick what you need:
                // All native backend XCFrameworks now carry macOS arm64 slices,
                // so the shared example exposes the same portable providers on
                // iOS and macOS instead of compiling them out on Mac.
                .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereMLX", package: "runanywhere-sdks"),

                // Apple Neural Engine backend. RunAnywhereAIApp.swift registers
                // it behind `#if canImport(NeuRTRuntime)`, so leaving it out
                // does not fail the build — it silently compiles the ANE
                // backend out. Keep this in sync with the .xcodeproj, which
                // also declares RunAnywhereNeuRT on the app target.
                .product(name: "RunAnywhereNeuRT", package: "runanywhere-sdks"),
            ],
            path: "RunAnywhereAI",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "Preview Content",
                "RunAnywhereAI.entitlements"
            ]
        ),
        // The unit tests. `path` must point at RunAnywhereAIUnitTests — the
        // XCUITest bundle in RunAnywhereAIUITests/ drives a launched app and
        // cannot run under `swift test`.
        .testTarget(
            name: "RunAnywhereAITests",
            dependencies: ["RunAnywhereAI"],
            path: "RunAnywhereAIUnitTests"
        )
    ]
)
