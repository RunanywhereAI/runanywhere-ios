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
        // The `runanywhere-swift` package publishes:
        //   - RunAnywhere (core)
        //   - RunAnywhereONNX (STT/TTS/VAD)
        //   - RunAnywhereLlamaCPP (LLM)
        //   - RunAnywhereMLX (Apple MLX)
        //   - RunAnywhereNeuRT (Apple Neural Engine)
        //
        // `runanywhere-swift` is the Swift-only SPM distribution generated from
        // the `runanywhere-sdks` monorepo. Consume it, NOT the monorepo:
        //   1. `.package(url: ".../runanywhere-sdks", …)` clones ~340 MB of C++
        //      core, engines, and five language bindings to compile Sources/.
        //   2. From v0.20.18 the monorepo de-committed its generated trees, so
        //      its tag ships only 1 of the 42 files in
        //      `bindings/swift/Sources/RunAnywhere/Generated/` (only
        //      Versions.swift survives). Building against it fails: CI run
        //      31728792120 emitted 733 "cannot find type 'RA…' in scope"
        //      errors naming 195 distinct types (RAModelInfo x38, RASDKEvent
        //      x25, RADownloadProgress x20, …). The generated sources are
        //      materialized into `runanywhere-swift` at release time by
        //      `bindings/swift/scripts/sync-dist-repo.sh`.
        // The XCFramework binaryTargets still point at the checksum-verified
        // release assets on `runanywhere-sdks`; only the Swift sources move.
        //
        // Its tags are bare semver with NO `v` prefix, which is what `from:`
        // needs.
        .package(
            url: "https://github.com/RunanywhereAI/runanywhere-swift.git",
            from: "0.20.34"
        ),
    ],
    targets: [
        .target(
            name: "RunAnywhereAI",
            dependencies: [
                // Core SDK (always needed)
                .product(name: "RunAnywhere", package: "runanywhere-swift"),

                // Optional modules - pick what you need:
                // All native backend XCFrameworks now carry macOS arm64 slices,
                // so the shared example exposes the same portable providers on
                // iOS and macOS instead of compiling them out on Mac.
                .product(name: "RunAnywhereONNX", package: "runanywhere-swift"),
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-swift"),
                .product(name: "RunAnywhereMLX", package: "runanywhere-swift"),

                // Apple Neural Engine backend. RunAnywhereAIApp.swift registers
                // it behind `#if canImport(NeuRTRuntime)`, so leaving it out
                // does not fail the build — it silently compiles the ANE
                // backend out. Keep this in sync with the .xcodeproj, which
                // also declares RunAnywhereNeuRT on the app target.
                .product(name: "RunAnywhereNeuRT", package: "runanywhere-swift"),
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
