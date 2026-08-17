# AGENTS.md RunAnywhereAI for iOS and macOS

One SwiftUI target, `RunAnywhereAI`, shipping to both the App Store and the Mac App Store,
plus a keyboard extension (`RunAnywhereKeyboard`) and a Live Activity widget
(`RunAnywhereActivityExtension`). It consumes the RunAnywhere SDK from
`github.com/RunanywhereAI/runanywhere-swift`, the generated Swift-only SwiftPM distribution
of the `runanywhere-sdks` monorepo. There is no monorepo checkout and no staged XCFramework:
SwiftPM downloads checksum-verified binaries on resolve.

The app was extracted from the monorepo at release 0.20.17 with history preserved, so every
path below is relative to this repository's root.

## Build and run

```bash
# Simulator
./scripts/build_and_run_ios_sample.sh simulator "iPhone 16 Pro"

# Physical device
./scripts/build_and_run_ios_sample.sh device

# Native macOS
./scripts/build_and_run_ios_sample.sh mac
```

`open RunAnywhereAI.xcodeproj` works too; SwiftPM resolves the SDK on open. `./scripts/verify.sh`
resolves and runs a full simulator `xcodebuild`; `./scripts/smoke.sh` greps the sources for SDK
call patterns and checks the Parakeet CTC catalog entry, without compiling. CI runs both plus
the unit tests. There is one app target: these scripts build `RunAnywhereKeyboard` and
`RunAnywhereActivityExtension` along with the main app, not separately.

Logs: `log stream --predicate 'subsystem CONTAINS "com.runanywhere"' --info --debug` on
simulator and Mac, `idevicesyslog | grep "com.runanywhere"` on device.

## App Store release

`docs/RELEASE_INSTRUCTIONS.md` carries the full flow. The packaged XCFrameworks already
declare the iOS 17.5 deployment floor, so release archives validate that metadata rather
than mutating it after the build.

### Native symbol gate (iOS)

Release stripping or a stale XCFramework can drop a Swift-facing native symbol and produce a
runtime startup failure such as `Native proto ABI is not exported by the linked RACommons
binary: rac_sdk_init_phase1_proto`. Every archive must therefore keep the export surface
intact:

- `RunAnywhereExportedSymbols.txt` contains `_rac_*` and `_ra_mlx_*`.
- The Release app target links with `-all_load`.
- The Release app target passes `-Wl,-exported_symbols_list,$(SRCROOT)/RunAnywhereExportedSymbols.txt`.
- The Release app target sets `STRIP_STYLE = non-global` so `dlsym` still resolves after
  archive post-processing.
- `RunAnywhereExportedSymbols.txt` is not bundled into app resources.

The archive procedure, the symbol audit script, the macOS entitlement checks, and the
screenshot rules all live in `docs/RELEASE_INSTRUCTIONS.md`. Do not duplicate them here.

Two facts that constrain code changes rather than the release run itself:

- The Live Activity extension deploys to iOS 26.2 while the app and keyboard deploy to
  17.5. A build-settings sweep will show both numbers, and that is correct.
- `RACommons` and every backend XCFramework (`RABackendLLAMACPP`, `RABackendONNX`,
  `RABackendSherpa`, `RABackendMLX`, `RABackendNeuRT`) carry a `macos-arm64` slice, so the
  shared target exposes the same providers on iOS and macOS. Nothing is compiled out on Mac.

## Architecture

The layering contract governs everything here. Each modality (LLM, STT, TTS, VAD, VLM, RAG,
LoRA, Voice) goes through one `RunAnywhere.*` entry point that does the heavy lifting. This
app holds UI and thin SDK calls only. A segmentation loop, a hardcoded model or engine
constant, prompt post-processing, or a multi-step bootstrap in app code is an SDK bug to fix
a layer down. See the monorepo's root `AGENTS.md`, Business Logic Layering Rules.

MVVM with Swift Observation. Views are SwiftUI with no business logic. View models are
`@MainActor @Observable` (or `ObservableObject`) classes owning state and SDK calls. Models
are `Codable` value types. Services are singletons for cross-feature concerns:
`ConversationStore`, `KeychainService`, `DeviceInfoService`, `ModelCatalogBootstrap`.

Chat is the product; the SDK demos sit behind a secondary hub (`ConsumerAdvancedHubView`)
rather than top-level tabs. macOS uses `ConsumerMacShell` (`NavigationSplitView` over
`MacSidebar`, with Chat/Models/Advanced destinations); iOS uses `ConsumerCompactShell`
(`ChatInterfaceView` plus sheets). The full shell/sidebar/hub breakdown — including why
`.chat` and `.conversation(String)` are separate `MacSidebarSelection` cases and what each
Advanced-hub row is gated on — is in
[`docs/reference/ARCHITECTURE.md`](docs/reference/ARCHITECTURE.md).

Dependency injection is mostly singleton-at-point-of-use (`ConversationStore.shared`,
`SettingsViewModel.shared`, `ToolSettingsViewModel.shared`, `ModelListViewModel.shared`,
`KeychainService.shared`) or the static `RunAnywhere.*` namespace. `RunAnywhereAIApp` injects
exactly one environment object, `FlowSessionManager`, and only on iOS; macOS injects nothing.

### Initialization gate

The UI is blocked behind `isSDKInitialized` in `RunAnywhereAIApp.swift`. `isInitializingSDK`
guards re-entry separately, because `isSDKInitialized` is only written at the end and cannot
gate a second call that arrives while the first is still awaiting. Both are `@State` on the
`App` struct, and both `.task` and the `scenePhase` observer check them.

1. Backend registration: `LlamaCPP.register(priority: 100)`, `MLX.register(priority: 100)`,
   `ONNX.register(priority: 100)`, `NeuRT.register(priority: 100)`. Only `MLX` returns
   `Bool`. All but MLX sit behind `#if canImport(...)` guards on their runtime module.
2. `RunAnywhere.initialize(apiKey:baseUrl:environment:)`, with network work continuing in the
   background.
3. `ModelCatalogBootstrap.registerAll(mlxRegistered:)`, which registers language, multimodal,
   speech recognition, speech synthesis, voice activity, diarization, segmentation, embedding,
   and LoRA rows, and omits every MLX row when registration failed.
4. `RunAnywhere.models.refresh()`, then `RunAnywhere.models.list()` and
   `RunAnywhere.lora.allRegistered()` to reconcile the registry with disk. Failures here log
   a warning and do not block startup.

All four `register` calls run before `RunAnywhere.initialize` and with no `await` between
them. That ordering is load-bearing: register later and a model load can race an empty
provider registry and fail with -422, "No provider could handle the request". The
`priority:` argument is currently decorative — every call declares `priority _: Int = 100`
and discards it; the real ordering comes from each plugin's base priority in C++ commons.

MLX executes only on a physical device or native macOS. On the arm64 simulator
`MLX.register()` returns false and no MLX rows are seeded.

### Cross-platform

iOS 17.5+ and macOS 14.5+, matching the SDK floor. Differences are handled with
`#if os(iOS)` / `#if os(macOS)` and `#if canImport(UIKit)`, `AdaptiveLayout.swift`
(`DeviceFormFactor` plus `AdaptiveSizing` for phone, tablet, and desktop),
`ViewCompatibility.swift` shims such as `navigationBarTitleDisplayModeCompat`, and `AppColors`
bridging `UIColor` and `NSColor`.

## Project structure

| Path | Contents |
|---|---|
| `RunAnywhereAI/App/` | `RunAnywhereAIApp` (entry, SDK init), `ContentView` (platform shells), `MacSidebar`, `ConsumerAdvancedHubView`, `AppCommands` (menu commands), `InitializationViews` |
| `RunAnywhereAI/Core/DesignSystem/` | `AppColors`, `AppSpacing`, `AppType`, `Typography`, `Layout`, `Motion`, `Surface`, `Haptics`, `EmptyStateMark`, `AudioActivityBars`, `ViewCompatibility` |
| `RunAnywhereAI/Core/Services/` | `ConversationStore`, `DeviceInfoService`, `KeychainService`, `ModelCatalogBootstrap`, `HardwareTier`, `HuggingFaceHubClient` |
| `RunAnywhereAI/Features/*` | One folder per feature (Chat, Voice, VoiceKeyboard, Models, Benchmarks, Vision, Connect, ComputerUse, Diarization, Segmentation, Settings, RAG, Storage) — behavior, flow, and the SDK calls each one makes are in [`docs/reference/FEATURES.md`](docs/reference/FEATURES.md) |
| `RunAnywhereAI/Extensions/` | `ModelInfo+Logo`, `String+Markdown`, `RunAnywhere+ExampleShims` — app-local helpers only; a feature needing net-new C bridge code belongs in the SDK, not here |
| `RunAnywhereAI/Shared/` | `SharedConstants` (IPC keys, Darwin notification names, URL scheme) and `SharedDataBridge`, shared with both extension targets below |
| `RunAnywhereKeyboard/` | `KeyboardViewController` (IPC via Darwin notifications), `KeyboardView`, `Info.plist` with `RequestsOpenAccess`, app-group entitlement |
| `RunAnywhereActivityExtension/` | `WidgetBundle` entry and the Dynamic Island / Lock Screen Live Activity |

Both extensions are thin (two source files each) and share their IPC protocol with the main
app through `RunAnywhereAI/Shared/`; see
[`docs/reference/FEATURES.md`](docs/reference/FEATURES.md) for the full dictation handshake.
Diffusion and image generation are excluded from the v1 build; see the comment at the top of
`RunAnywhereAIApp.swift` and the matching one in `ModelCatalogBootstrap.swift`. Their products,
registration calls, feature folders, catalog rows, and `generateImage` APIs are deliberately
absent.

## SDK surface

Every call goes through the `RunAnywhere` enum, one namespace per modality; the SDK owns
model resolution, loading, downloading, and orchestration behind each verb. The exact subset
this app calls — and what it deliberately does not (`embeddings`, `rerank`, `images`,
`generateStructured`, `tts.voices()`, `vad.detect(_:)`, `RunAnywhere.events`) — is in
[`docs/reference/FEATURES.md`](docs/reference/FEATURES.md). Do not assume an unused verb is
wired up here just because the SDK exposes it.

The older flat verbs (`loadModel`, `transcribe`, `ragQuery`) are deprecated forwarders in the
SDK; do not use them here. One-shot verbs throw `SDKException`; stream factories are
`async throws -> AsyncThrowingStream` and throw into the consumer mid-flight — no result
carries a `success` flag. Cancel by cancelling the consuming `Task`; there are no cancel verbs.

## Design system

No inline magic numbers or color literals in views. `AppColors` carries brand primary
`#FF6900` and semantic tokens for text, backgrounds, bubbles, badges, and status; the canonical
palette, motion tiers, and icon language live in the monorepo's
[`docs/DESIGN_GUIDELINE.md`](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/docs/DESIGN_GUIDELINE.md).
`AppSpacing`, `AppType`/`AppTypography`, `Layout`, `Motion`, `Surface`, and `AdaptiveSizing`
cover spacing/sizing tokens, text styles, window and content sizing, animation curves,
elevation treatments, and phone/tablet/desktop scaling respectively.

## Configuration

| File | Purpose |
|---|---|
| `Package.swift` | One dependency: `github.com/RunanywhereAI/runanywhere-swift` at `from: "0.20.24"`, giving RunAnywhere, RunAnywhereONNX, RunAnywhereLlamaCPP, RunAnywhereMLX, RunAnywhereNeuRT. The Xcode project mirrors it with `upToNextMajorVersion` from the same minimum, and declares all five products on the app target. Its `RunAnywhereAITests` testTarget must point at `RunAnywhereAIUnitTests/`, not the XCUITest bundle. |
| `Package.resolved` | Committed record of the resolved version and commit. CI fails if `swift package resolve` leaves it dirty, so commit it whenever the dependency moves. |
| `Info.plist` | URL scheme `runanywhere`, `audio` background mode, Live Activities, and the local-network and Bonjour (`_runanywhere-connect._tcp`) declarations that Connect needs |
| `RunAnywhereAI.entitlements` | App Sandbox, `device.camera`, `device.audio-input`, `network.client` and `network.server`, user-selected files (read-only and read-write), the `group.com.runanywhere.runanywhereai` app group, HealthKit, and `kernel.increased-memory-limit` |
| `Resources/RunAnywhereConfig-{Debug,Release}.plist` | Bundled but read by nothing today. Debug names `api-dev.runanywhere.ai` and debug logging, Release names `api.runanywhere.ai`, warning-level logging, and crash reporting, but none of it reaches `RunAnywhere.initialize`. Treat them as inert until code reads them. |
| `.swiftlint.yml` | Line length 120/150, function body 50/100, `force_cast` as error, TODOs require an issue number |

Credentials, in `RunAnywhereAIApp.swift`, come from the first source yielding a usable pair:
the Keychain (written in Settings), then `RunAnywhereLocalSecrets.plist` in the bundle (keys
`apiKey`, `baseURL`), then the Info.plist keys `RUNANYWHERE_API_KEY` and
`RUNANYWHERE_BASE_URL`. Placeholder-looking values and malformed URLs are rejected. With
credentials the app initializes at `environment: .production`; without them a Debug build
falls back to `.development` and a Release build calls `fatalError`. See
`docs/RELEASE_INSTRUCTIONS.md`.
