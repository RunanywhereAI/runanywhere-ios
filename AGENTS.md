# AGENTS.md RunAnywhereAI for iOS and macOS

One SwiftUI target, `RunAnywhereAI`, shipping to both the App Store and the Mac App Store,
plus a keyboard extension and a Live Activity widget. It consumes the RunAnywhere SDK from
its published GitHub release. The app was extracted from the `runanywhere-sdks` monorepo at
release 0.20.17 with history preserved, so every path below is relative to this repository's
root, not to a monorepo `examples/` directory.

---

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
is the local gate (resolve plus full `xcodebuild`), and `./scripts/smoke.sh` greps the sources
for SDK call patterns without compiling.

Logs: `log stream --predicate 'subsystem CONTAINS "com.runanywhere"' --info --debug` on
simulator and Mac, `idevicesyslog | grep "com.runanywhere"` on device.

---

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

From the repository root:

```bash
# 1. Build the final release inputs.
xcodebuild \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation \
  -jobs "$(sysctl -n hw.logicalcpu)" \
  build

# 2. Archive directly into Xcode Organizer's archive folder.
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
ARCHIVE="$ARCHIVE_DIR/RunAnywhereAI-$(date +%Y%m%d-%H%M%S).xcarchive"
mkdir -p "$ARCHIVE_DIR"
xcodebuild \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -skipPackagePluginValidation \
  -jobs "$(sysctl -n hw.logicalcpu)" \
  archive

open -a Xcode "$ARCHIVE"
```

Then audit the archived binary:

```bash
APP="$ARCHIVE/Products/Applications/RunAnywhereAI.app"
BIN="$APP/RunAnywhereAI"

nm -gjU "$BIN" 2>/dev/null \
  | rg '^_(rac|ra_mlx)_' \
  | sed 's/^_//' \
  | sort -u > /tmp/runanywhere_archive_exported_symbols.txt

# `swift package resolve` places the SDK sources here. Xcode archives resolve
# into DerivedData instead, so override with
# SDK_CHECKOUT=<path-to-runanywhere-swift-checkout> when auditing those.
# The dependency is the generated `runanywhere-swift` distribution, whose Swift
# sources sit at `Sources/` — NOT the monorepo's `bindings/swift/Sources/`. A
# checkout of `runanywhere-sdks` instead of `runanywhere-swift` needs that
# prefix added back, and from v0.20.18 it is missing the generated proto
# sources entirely.
SDK_CHECKOUT="${SDK_CHECKOUT:-.build/checkouts/runanywhere-swift}"
SRC_DIRS=(
  "$SDK_CHECKOUT/Sources/RunAnywhere"
  "$SDK_CHECKOUT/Sources/LlamaCPPRuntime"
  "$SDK_CHECKOUT/Sources/ONNXRuntime"
  "$SDK_CHECKOUT/Sources/MLXRuntime"
)

rg -No '"(rac|ra_mlx)_[A-Za-z0-9_]+"' "${SRC_DIRS[@]}" --glob '*.swift' \
  | perl -ne 'while (/"((?:rac|ra_mlx)_[A-Za-z0-9_]+)"/g) { print "$1\n" }' \
  | sort -u > /tmp/runanywhere_expected_swift_native_symbols.from_strings

# Declared only inside a build-configuration guard this archive does not compile.
# The rg pass above is a plain text scan and does not evaluate `#if`, so without
# this filter the gate fails on every good archive over a symbol that is
# CORRECTLY absent. `ra_mlx_metal_resource_anchor` lives in MLXRuntime/MLX.swift
# under `#if RUNANYWHERE_MLX_DISTRIBUTION`, set only for the CocoaPods
# distribution build; a SwiftPM archive never compiles it.
# Extend this list ONLY for a symbol confirmed guarded out of this configuration.
PACKAGING_ONLY_SYMBOLS=(
  ra_mlx_metal_resource_anchor
)

{
  cat /tmp/runanywhere_expected_swift_native_symbols.from_strings
  printf '%s\n' \
    rac_proto_buffer_free \
    rac_backend_llamacpp_register \
    rac_backend_llamacpp_unregister \
    rac_backend_onnx_register \
    rac_backend_onnx_unregister \
    rac_plugin_entry_sherpa \
    rac_plugin_register \
    rac_plugin_unregister \
    rac_backend_mlx_register \
    rac_backend_mlx_unregister \
    rac_mlx_set_callbacks \
    ra_mlx_register_runtime \
    ra_mlx_runtime_is_available \
    ra_mlx_runtime_is_registered \
    ra_mlx_unregister_runtime
} | sort -u \
  | grep -vxF "$(printf '%s\n' "${PACKAGING_ONLY_SYMBOLS[@]}")" \
  > /tmp/runanywhere_expected_swift_native_symbols.txt

comm -23 \
  /tmp/runanywhere_expected_swift_native_symbols.txt \
  /tmp/runanywhere_archive_exported_symbols.txt \
  > /tmp/runanywhere_missing_swift_native_symbols.txt

test ! -s /tmp/runanywhere_missing_swift_native_symbols.txt
```

That final `test` must pass. When it fails, read
`/tmp/runanywhere_missing_swift_native_symbols.txt`, rebuild the native XCFrameworks, fix the
Release linker and strip settings, and archive again.

Confirm the release configuration and secrets are present without printing their values:

```bash
test -f "$APP/RunAnywhereLocalSecrets.plist"
test -f "$APP/RunAnywhereConfig-Release.plist"
test ! -e "$APP/RunAnywhereExportedSymbols.txt"
```

Upload from Xcode Organizer: Validate App, then Distribute App, App Store Connect, Upload.
From the command line, use the repository's export options plist when present:

```bash
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "build/archives/$(basename "$ARCHIVE" .xcarchive)-export" \
  -exportOptionsPlist "build/archives/ExportOptions-app-store-connect.plist" \
  -allowProvisioningUpdates
```

### macOS gate

The same target ships as a native Mac app. Before every Mac App Store release:

- Increment `CURRENT_PROJECT_VERSION`. Never reuse an uploaded build number.
- Keep `MACOSX_DEPLOYMENT_TARGET = 14.5`, matching `Package.swift`.
- Archive Release for `generic/platform=macOS` at the host logical CPU count.
- Require App Sandbox, the RunAnywhere app group, and the camera, microphone, outbound
  network, and user-selected file entitlements.
- Require Hardened Runtime.
- Bundle `PrivacyInfo.xcprivacy`, `RunAnywhereLocalSecrets.plist`, and
  `RunAnywhereConfig-Release.plist` without printing credential values.
- Keep `RunAnywhereExportedSymbols.txt` out of app resources, and run the platform-filtered
  ABI audit against `Contents/MacOS/RunAnywhereAI`. Every published Swift backend binary
  carries a macOS arm64 slice.
- Verify `codesign`, `arm64`, absence of quarantine metadata, and zero missing `_rac_*` and
  `_ra_mlx_*` symbols before opening Organizer.

```bash
JOBS="$(sysctl -n hw.logicalcpu)"
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
ARCHIVE="$ARCHIVE_DIR/RunAnywhereAI macOS $(date +%Y-%m-%d\ %H.%M.%S).xcarchive"
mkdir -p "$ARCHIVE_DIR"

xcodebuild \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -skipPackagePluginValidation \
  -jobs "$JOBS" \
  archive

open -a Xcode "$ARCHIVE"
```

Store media: one to ten screenshots in upload order, `1320x2868` sRGB for the 6.9-inch
iPhone family and `2880x1800` sRGB for macOS. Real app UI stays the dominant content;
branded framing and factual feature copy are fine. The current voice-first iPhone set uses
authenticated simulator captures from llama.cpp LFM2 350M, Sherpa-ONNX Whisper Tiny, and
Piper TTS. MLX may be listed as a supported runtime but must not be presented as tested
evidence unless separately verified for that build. Until the llama.cpp XCFramework gains a
macOS slice, Mac copy describes the shared model catalog rather than claiming local
llama.cpp execution.

---

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

### Navigation

Chat is the product; the SDK demos sit behind a secondary hub rather than top-level tabs.
`ContentView` branches on platform.

| Platform | Shell | Structure |
|---|---|---|
| macOS | `ConsumerMacShell` | `NavigationSplitView` over `MacSidebar`. Three destinations (Chat, Models, Advanced) plus the conversation list, which is scoped to Chat. Detail is `ChatInterfaceView`, `SimplifiedModelsView`, or `ConsumerAdvancedHubView`. |
| iOS | `ConsumerCompactShell` | `ChatInterfaceView` alone. Settings, Models, and the Advanced hub are sheets off the chat toolbar. |

`MacSidebarSelection` distinguishes `.chat` (the transcript, whatever is current) from
`.conversation(id)`, so ⌘1 lands somewhere real before anything is saved. Sidebar width and
selection persist across relaunch via `@SceneStorage`. ⌘1/⌘2/⌘3 are published from the shell
through `focusedSceneValue(\.shellNavigationActions)` because the chat cannot navigate away
from itself.

`ConsumerAdvancedHubView` lists Connect (macOS only), Voice Utilities (Transcribe, Read
Aloud, Voice Activity, Diarization), Vision Utilities (Segmentation), Agents (Talk, Computer
Use), and Management (Benchmarks). Storage and tool calling live in Settings and Manage
Models instead.

### Dependency injection

Three layers: environment objects from `RunAnywhereAIApp` (`FlowSessionManager`), singleton
services (`ConversationStore.shared`, `SettingsViewModel.shared`, `ModelListViewModel.shared`,
`KeychainService.shared`), and the static `RunAnywhere.*` SDK namespace.

### Initialization gate

The UI is blocked behind `isSDKInitialized` in `RunAnywhereAIApp.swift`. `isInitializing`
guards re-entry separately, because `isSDKInitialized` is only written at the end and cannot
gate a second call that arrives while the first is still awaiting.

1. Backend registration, synchronously and before any `await`: `LlamaCPP.register(priority: 100)`,
   `MLX.register(priority: 100)` (returns `Bool`), `ONNX.register(priority: 100)`,
   `NeuRT.register(priority: 100)`.
2. `RunAnywhere.initialize(apiKey:baseUrl:environment:)`, with network work continuing in the
   background.
3. `ModelCatalogBootstrap.registerAll(mlxRegistered:)`, which registers LLM, VLM, STT, TTS,
   VAD, embedding, and LoRA rows and omits every MLX row when registration failed.
4. `RunAnywhere.models.refresh()` then `RunAnywhere.models.list()` to reconcile the registry
   with disk.

Backends must be registered before any `await`, otherwise a model load can race an empty
provider registry and fail with -422. MLX executes only on a physical device or native macOS;
on the arm64 simulator `MLX.register()` returns false and no MLX rows are seeded.

### Cross-platform

iOS 17.5+ and macOS 14.5+, matching the SDK floor. Differences are handled with
`#if os(iOS)` / `#if os(macOS)` and `#if canImport(UIKit)`, `AdaptiveLayout.swift`
(`DeviceFormFactor` plus `AdaptiveSizing` for phone, tablet, and desktop),
`ViewCompatibility.swift` shims such as `navigationBarTitleDisplayModeCompat`, and `AppColors`
bridging `UIColor` and `NSColor`.

---

## Project structure

| Path | Contents |
|---|---|
| `RunAnywhereAI/App/` | `RunAnywhereAIApp` (entry, SDK init), `ContentView` (platform shells), `MacSidebar`, `ConsumerAdvancedHubView`, `AppCommands` (menu commands), `InitializationViews` |
| `RunAnywhereAI/Core/DesignSystem/` | `AppColors`, `AppSpacing`, `AppType`, `Typography`, `Layout`, `Motion`, `Surface`, `Haptics`, `EmptyStateMark`, `AudioActivityBars`, `ViewCompatibility` |
| `RunAnywhereAI/Core/Models/` | `AppTypes` (`SystemDeviceInfo`, `Int64.formattedFileSize`), `MarkdownBlock` (block model plus `MarkdownBlockParser`) |
| `RunAnywhereAI/Core/Services/` | `ConversationStore`, `DeviceInfoService`, `KeychainService`, `ModelCatalogBootstrap`, `HardwareTier`, `HuggingFaceHubClient` |
| `RunAnywhereAI/Features/Chat/` | 29 files across `Models/`, `ViewModels/`, `Views/` |
| `RunAnywhereAI/Features/Voice/` | STT, TTS, VAD, and the voice agent (15 files) |
| `RunAnywhereAI/Features/VoiceKeyboard/` | Dictation flow and Live Activity attributes (5 files) |
| `RunAnywhereAI/Features/Models/` | Model browser, download tracking, selection sheet, Hugging Face import (17 files) |
| `RunAnywhereAI/Features/Benchmarks/` | Scenario providers, runner, report formatting, share card (16 files) |
| `RunAnywhereAI/Features/Vision/` | `VLMViewModel`, `VLMCameraView`, `VLMCameraPreview` |
| `RunAnywhereAI/Features/Connect/` | Host management, client controller, status banner |
| `RunAnywhereAI/Features/ComputerUse/` | `ComputerUseAgentView` and its view model |
| `RunAnywhereAI/Features/Diarization/`, `Segmentation/` | One view plus one view model each |
| `RunAnywhereAI/Features/Settings/` | `CombinedSettingsView`, `SettingsViewModel`, `ToolSettingsView`, `CalendarTool`, `HealthKitTool` |
| `RunAnywhereAI/Features/RAG/Services/` | `DocumentService` only; text extraction for chat document attachments |
| `RunAnywhereAI/Features/Storage/` | `StorageViewModel` only; surfaced inside Settings and the models views |
| `RunAnywhereAI/Extensions/` | `ModelInfo+Logo`, `String+Markdown`, `RunAnywhere+ExampleShims` |
| `RunAnywhereAI/Helpers/` | `SmartMarkdownRenderer`, `InlineMarkdownRenderer`, `AdaptiveLayout` |
| `RunAnywhereAI/Shared/` | `SharedConstants` (IPC keys, Darwin notification names, URL scheme), `SharedDataBridge` |
| `RunAnywhereKeyboard/` | `KeyboardViewController` (IPC via Darwin notifications), `KeyboardView`, `Info.plist` with `RequestsOpenAccess`, app-group entitlement |
| `RunAnywhereActivityExtension/` | `WidgetBundle` entry and the Dynamic Island / Lock Screen Live Activity |

Diffusion and image generation are excluded from the v1 build (`RunAnywhereAIApp.swift:12`).
Their products, registration calls, feature folders, and `generateImage` APIs are
deliberately absent.

---

## Features

### Chat and LLM

`LLMViewModel` is split across ten files by concern: core state and `sendMessage()` in
`LLMViewModel.swift`, then `+Generation` (streaming and non-streaming), `+ToolCalling`,
`+ModelManagement`, `+Analytics`, `+Events` (Combine subscription to `RunAnywhere.eventBus`),
`+Documents` (RAG-backed attachments), `+MessageActions`, `+Vision`, and the shared
`LLMViewModelTypes`. `ToolCallingModelPolicy` decides which models get tools.

Flow: input, `sendMessage()`, `prepareMessagesForSending()` (creates the user message and an
empty assistant message), `executeGeneration()`, `performGeneration()`, then the streaming,
non-streaming, or tool-calling path, token-by-token message updates, `finalizeGeneration()`,
and persistence to `ConversationStore`.

Tool calling runs through `RunAnywhere.llm.generate` with the registry active; the SDK owns
the call and execute loop and the format is auto-detected per model.

LoRA lives almost entirely in the SDK. `ModelCatalogBootstrap.registerLoraAdapters()` seeds
the curated catalog as `RALoraAdapterCatalogEntry` values, mirroring Android's
`ModelBootstrap.seedLora`. From there the app calls `RunAnywhere.lora.queryCatalog(_:)`,
`.download(_:artifact:)`, `.importAdapter(from:)`, `.applyCatalogAdapter(_:localPath:scale:)`,
`.apply(RALoraApplyRequest)` for a raw path, `.remove(_:)`, and `.state()`. Removal of an
adapter with no catalog id falls back to path-keyed removal, which fails cleanly when other
adapters are also loaded. Scale is user-adjustable.

Conversations persist as per-conversation JSON under `Documents/Conversations/`, attachments
under `Conversations/Attachments/{conversationID}/`. Search covers titles and message content.

Titles are written by whichever model answered, through `RunAnywhere.llm`, not by a separate
`FoundationModels.LanguageModelSession`. Apple's Foundation Models will not serve two clients
against one on-device model: the old app-side title session hung and wedged every subsequent
turn behind it with no error and no timeout. Only one title task exists at a time and
`cancelPendingTitleGeneration()` hands the model back the moment the chat claims a new turn.

Analytics: `MessageAnalytics` per message and `ConversationAnalytics` per conversation,
tracking TTFT, tokens per second, token counts, thinking-mode usage, and completion rate,
shown in `ChatDetailsView`.

Thinking mode: models with `supportsThinking` expose reasoning through the SDK's `reasoning`
options and `thinkingText` or stream thought events. Commons owns tag parsing and `/no_think`
directives; the app toggles the mode and renders the returned channel in a collapsible
section.

Documents attached to a chat go through `ChatAttachmentLoader` and `DocumentService` for text
extraction, then `RunAnywhere.rag.open(...)` for a per-conversation `RagSession` held on the
view model. There is no separate RAG screen.

### Voice agent

`RunAnywhere.voice.createSession(stt:llm:tts:)` then `session.start()`, which is the only
call that opens the microphone. `session.events` yields `userTranscribed`,
`agentStateChanged`, `agentResponse`, `speechStarted`, `speechEnded`, and `error`. The SDK
owns the whole audio pipeline including its own VAD. The user loads STT, LLM, and TTS models
independently through `ModelSelectionSheet`.

`VoiceAssistantParticleView` is a Metal-rendered 2000-particle system: a Fibonacci-lattice
sphere that morphs to a ring while listening or speaking, with amplitude from the real
microphone level when listening and a simulated sine wave when speaking, and touch scatter
decaying at 0.92.

### Speech, synthesis, and voice activity

STT has three modes. Batch records audio then calls
`RunAnywhere.stt.transcribe(.pcm16(buffer, sampleRate: 16_000))`. Live yields microphone
chunks into `RunAnywhere.stt.transcribeStream(_:)`, which owns segmentation and emits
`.partial` and `.final`. Hybrid runs on-device first with cloud fallback through
`HybridSTTRouter`. Capture is `AudioCaptureManager` and `AudioCapturePump`; no app-side
silence detection exists.

TTS is `RunAnywhere.tts.speak(text, options: TtsOptions(speed:pitch:))`, which synthesizes and
plays inside the SDK and returns nothing, with `RunAnywhere.tts.stop()` to interrupt. Use
`tts.synthesize(_:)` when the `Audio` buffer is wanted instead of playback.

VAD feeds microphone chunks to `RunAnywhere.vad.detectStream(_:)`, which emits
`.speechStarted`, `.speechEnded`, and per-chunk `.frame(VadResult)`. Framing is the SDK's job.
The activity log holds 50 entries.

### Voice keyboard

Cross-process dictation over two IPC channels: App Group `UserDefaults`
(`group.com.runanywhere.runanywhereai`) for shared state (session state, transcribed text,
audio level, heartbeat), and Darwin `CFNotificationCenter` for zero-latency signals (six names
in `SharedConstants.DarwinNotifications`).

The keyboard's Run button opens `runanywhere://startFlow`. The main app activates a session,
loads the STT model, starts capture, and posts `sessionReady`. The user returns to the host
app, the keyboard sends `startListening`, the main app buffers audio, the keyboard sends
`stopListening`, the main app calls `RunAnywhere.stt.transcribe(_:)`, writes the result to
shared `UserDefaults`, and posts `transcriptionReady`; the keyboard inserts it through
`textDocumentProxy.insertText()`.

`DictationActivityAttributes.ContentState` carries phase, elapsed seconds, transcript, and
word count for the Dynamic Island and Lock Screen. A one-second heartbeat lets the keyboard
detect a main-app crash after a three-second staleness window.

### Vision

Camera and photo-library image understanding, reached from the chat rather than its own tab.
`AVCaptureSession` with BGRA pixel format feeds
`RunAnywhere.vlm.generateStream(image: .pixelBuffer(frame), prompt:, options:)`. Live mode
captures every 2.5 seconds (`autoStreamInterval`) with a 64-token cap and clears on the first
token, so an unchanged scene does not repeat itself. Pixel conversion belongs to the SDK: pass
`ImageInput` a `CVPixelBuffer` and do not bridge through `CIContext`.

### Benchmarks

Deterministic tests across LLM, STT, TTS, and VLM, each with a `BenchmarkScenarioProvider`.
`BenchmarkRunner` orchestrates with cooperative cancellation. Results persist as JSON, capped
at 50 runs, and export as Markdown, JSON, or CSV. `SyntheticInputGenerator` produces silent
and sine-wave audio and solid and gradient images. LLM scenarios run at 50, 256, and 512
tokens measuring TTFT and decode speed.

### Models

`ModelListViewModel` is the canonical registry singleton, subscribed to
`RunAnywhere.eventBus.modelLifecycle` for live load and unload state. `ModelSelectionSheet` is
the universal picker, parameterized by `ModelSelectionContext` (`.llm`, `.stt`, `.tts`, `.vad`,
`.vlm`, `.ragEmbedding`, `.ragLLM`). Custom models arrive through `AddModelFromURLView` or
`AddFromHuggingFaceView`. `ModelRecommendation` and `ModelCompatibilityLookup` drive the
recommended set, and `HardwareTier` scopes it to the device.

### Storage

`RunAnywhere.models.state()` gives used and free bytes;
`RunAnywhere.models.list(filter: ModelFilter(downloadedOnly: true))` gives the rows, filtered
to entries with a real on-disk size so Apple system pseudo-models drop out. Each row reads its
own `ModelInfo` for name, local path, framework, and `lastUsedAtUnixMs`. Deletion is
`RunAnywhere.models.delete(id:)`; cache and temp clearing are `RunAnywhere.clearCache()` and
`RunAnywhere.cleanTempFiles()`. `StorageViewModel` surfaces this inside Settings and the models
views.

### Settings and tools

`SettingsViewModel` (singleton) owns temperature, max tokens, and system prompt in
`UserDefaults`, API key and base URL in the Keychain, and the thinking-mode toggle, saving on a
Combine `debounce(0.5s)`.

`ToolSettingsViewModel` registers tools through `RunAnywhere.llm.tools`. Five are always
available: `get_weather` (Open-Meteo), `get_current_time`, `calculate` (a recursive-descent
`SafeMathEvaluator`), `get_device_info`, and `get_battery_level`. Two more are opt-in behind a
toggle and a permission prompt: `get_calendar_events` (`CalendarTool`) and `get_health_data`
(`HealthKitTool`). `registerBuiltInTools()` restores the enabled set at launch, because
assigning a stored property inside `init` does not fire `didSet`.

---

## Markdown rendering

One path, not a detect-and-route chain. `MarkdownBlockParser.parse(content)` turns the reply
into `[MarkdownBlock]` (paragraph, heading, list, quote, code fence, rule) with no SwiftUI
involved, and `AdaptiveMarkdownText` renders one view per block: `MarkdownListView`,
`MarkdownQuoteView`, `MarkdownCodeBlock` (syntax-colored header, copy button, monospaced
scrollable body), and inline text through `InlineMarkdownRenderer`, which uses
`AttributedString(markdown:)` with bold as `.semibold`, italic as `.italic`, and inline code
monospaced and purple-tinted.

---

## SDK surface used here

Every call goes through the `RunAnywhere` enum, following the cross-SDK v3 contract in the
monorepo's `thoughts/shared/plans/public_api_spec.md`. One namespace per modality; the SDK owns
model resolution, loading, downloading, and orchestration behind each verb.

```swift
// Core
try RunAnywhere.initialize(apiKey:baseUrl:environment:)   // one call, both phases
RunAnywhere.isReady / .version / .deviceId
RunAnywhere.events            // AsyncStream<SdkEvent>
RunAnywhere.eventBus          // Combine publisher over raw RASDKEvent protos

// Models
RunAnywhere.models.list(filter:) / .get(id:) / .register(_:) / .download(id:)
RunAnywhere.models.load(id:options:) / .unload(category:) / .delete(id:) / .state()

// Generation
RunAnywhere.llm.generate(prompt:options:) / .generate(messages:options:)
RunAnywhere.llm.generateStream(...) / .generateStructured(prompt:schema:options:)
RunAnywhere.llm.tools.register(_:executor:) / .unregister(name:) / .list() / .clear()
RunAnywhere.vlm.generate(image:prompt:options:) / .generateStream(...)

// Audio and vision
RunAnywhere.stt.transcribe(_:options:) / .transcribeStream(_:options:) / .state()
RunAnywhere.tts.synthesize(_:options:) / .speak(_:options:) / .stop() / .voices()
RunAnywhere.vad.detect(_:options:) / .detectStream(_:options:)
RunAnywhere.diarization.diarize(_:options:)
RunAnywhere.segmentation.segment(_:options:)

// Sessions
let voice = try await RunAnywhere.voice.createSession(stt:llm:tts:)
try voice.start()             // the only thing that opens the microphone
let rag = try await RunAnywhere.rag.open(embeddingModel:llmModel:)

// LoRA, embeddings, rerank, storage
RunAnywhere.lora.apply(adapterId:scale:) / .remove(adapterId:) / .list()
RunAnywhere.embeddings.embed(_:options:)
RunAnywhere.rerank.rerank(query:documents:topN:)
RunAnywhere.clearCache() / .cleanTempFiles() / .deleteStorage(_:)
```

Inputs are `AudioInput` (`.pcm16`, `.float32`, `.wav`, `.file`) and `ImageInput` (`.file`,
`.bytes`, `.rawRgb`, `.uiImage`, `.cgImage`, `.pixelBuffer`). Options are `LlmOptions`,
`SttOptions`, `TtsOptions`, `VadOptions`, `EmbedOptions`, `ImageOptions`,
`DiarizationOptions`, `SegmentationOptions`, `LoadOptions`, and `RagConfig`; every field is
optional and every default comes from the IDL.

One-shot verbs throw `SDKException`. Stream factories are `async throws -> AsyncThrowingStream`,
so they throw on preflight failure and throw into the consumer mid-flight. No result carries a
`success` flag and no error text hides in a payload field. Cancel by cancelling the consuming
Task; there are no cancel verbs.

The older flat verbs (`loadModel`, `transcribe`, `ragQuery`) survive as deprecated forwarders
in the SDK for one release. Do not use them here.

`RunAnywhere+ExampleShims.swift` holds one app-local helper,
`RunAnywhere.getRegisteredFrameworks() -> [RAInferenceFramework]`, which composes
`RunAnywhere.models.list()` into a framework filter sorted by descending model count. A new
feature needing net-new C bridge code belongs in the SDK; only UI plumbing over existing
canonical proto APIs belongs in that file.

---

## Design system

No inline magic numbers or color literals in views. `AppColors` carries brand primary
`#FF6900` and semantic tokens for text, backgrounds, bubbles, badges, and status; the canonical
palette, motion tiers, and icon language live in the monorepo's
[`docs/DESIGN_GUIDELINE.md`](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/docs/DESIGN_GUIDELINE.md).
`AppSpacing` runs xxSmall (2) to xxxLarge (40) plus icon sizes, button heights, corner radii,
and strokes. `AppType` and `AppTypography` cover text styles and weighted or monospaced
variants. `Layout` holds window sizes, content widths, and animation durations, `Motion` the
shared curves and springs, `Surface` the elevation treatments, and `AdaptiveSizing` the phone,
tablet, and desktop scaling.

---

## Scripts and configuration

| Script | Purpose |
|---|---|
| `scripts/build_and_run_ios_sample.sh` | Resolve, build, and deploy to simulator, device, or Mac |
| `scripts/verify.sh` | Local gate: resolves the remote SDK release, runs a full `xcodebuild` |
| `scripts/smoke.sh` | Greps sources for SDK call patterns and asserts the Parakeet CTC catalog policy, without compiling. Gated in CI. |

| File | Purpose |
|---|---|
| `Package.swift` | One dependency: `github.com/RunanywhereAI/runanywhere-swift` at `from: "0.20.18"` (the Swift-only SPM distribution generated from the monorepo — the monorepo itself stopped committing `bindings/swift/Sources/RunAnywhere/Generated/` at v0.20.18 and no longer compiles as an SPM dependency), giving RunAnywhere, RunAnywhereONNX, RunAnywhereLlamaCPP, RunAnywhereMLX, RunAnywhereNeuRT. The Xcode project mirrors it with `upToNextMajorVersion` from the same version. Its `RunAnywhereAITests` testTarget must point at `RunAnywhereAIUnitTests/`, not the XCUITest bundle. |
| `Package.resolved` | Committed record of the resolved version and commit. CI fails if `swift package resolve` leaves it dirty, so commit it whenever the dependency moves. |
| `Info.plist` | URL scheme `runanywhere`, `audio` background mode, Live Activities |
| `RunAnywhereAI.entitlements` | macOS sandbox, camera, microphone, network, app group |
| `Resources/RunAnywhereConfig-Debug.plist` | Dev API URL, debug logging, 30s timeout |
| `Resources/RunAnywhereConfig-Release.plist` | Prod API URL, warning-level logging, 15s timeout, crash reporting |
| `.swiftlint.yml` | Line length 120/150, function body 50/100, `force_cast` as error, TODOs require an issue number |

Environment: `#if DEBUG` initializes with no API key and uses Supabase; Release requires a
stored API key and base URL from Settings and calls `fatalError` when they are missing. The
config plists supply `environment`, `api.baseURL`, and `logging.minimumLogLevel`.
