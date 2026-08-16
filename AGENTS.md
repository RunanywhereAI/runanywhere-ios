# AGENTS.md RunAnywhereAI for iOS and macOS

One SwiftUI target, `RunAnywhereAI`, shipping to both the App Store and the Mac App Store,
plus a keyboard extension and a Live Activity widget. It consumes the RunAnywhere SDK from
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
the unit tests.

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

### Navigation

Chat is the product; the SDK demos sit behind a secondary hub rather than top-level tabs.
`ContentView` branches on platform.

| Platform | Shell | Structure |
|---|---|---|
| macOS | `ConsumerMacShell` | `NavigationSplitView` over `MacSidebar`. Three destinations (Chat, Models, Advanced) plus the conversation list, which is scoped to Chat. Detail is `ChatInterfaceView`, `SimplifiedModelsView`, or `ConsumerAdvancedHubView`. |
| iOS | `ConsumerCompactShell` | `ChatInterfaceView` alone, plus sheets. |

`MacSidebarSelection` has four cases: `.chat` (the transcript, whatever is current),
`.conversation(String)`, `.models`, and `.advanced`. Splitting `.chat` from `.conversation`
is what lets ⌘1 land somewhere real before anything is saved. ⌘1/⌘2/⌘3 are published from
the shell through `focusedSceneValue(\.shellNavigationActions)` because the chat cannot
navigate away from itself. One `@SceneStorage` key, `mac.sidebar.visibility`, persists
whether the sidebar is showing; column width is fixed by `navigationSplitViewColumnWidth`
and the selection is re-derived from the current conversation on restore.

On iOS, Settings and the Advanced hub are sheets, both opened from the conversation drawer
rather than the toolbar. Models is not the same kind of sheet: the chat presents
`ModelSelectionSheet` (a picker, cross-platform), while the full `SimplifiedModelsView`
management screen is reached through a `NavigationLink` inside `CombinedSettingsView`. On
macOS `SimplifiedModelsView` is the `.models` sidebar destination.

`ConsumerAdvancedHubView` has five sections and eight rows:

| Section | Rows | Availability |
|---|---|---|
| Connect | Host this Mac | macOS only (`#if os(macOS)`) |
| Voice Utilities | Transcribe, Read Aloud, Voice Activity | both |
| Voice Utilities | Diarization | iOS only (`#if canImport(UIKit)`) |
| Vision Utilities | Segmentation | iOS only, and so is the whole section |
| Agents | Talk, Computer Use | both |
| Management | Benchmarks | both |

Storage and tool calling live in Settings and Manage Models instead.

### Dependency injection

Three layers, the first thinner than it looks. `RunAnywhereAIApp` injects exactly one
environment object, `FlowSessionManager`, and only on iOS; on macOS it injects nothing.
Everything else is reached as a singleton at the point of use (`ConversationStore.shared`,
`SettingsViewModel.shared`, `ToolSettingsViewModel.shared`, `ModelListViewModel.shared`,
`KeychainService.shared`), or through the static `RunAnywhere.*` SDK namespace.

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
provider registry and fail with -422, "No provider could handle the request".

The `priority:` argument is currently decorative. Every `register` declares it as
`priority _: Int = 100` and discards it; the real ordering comes from each plugin's base
priority in C++ commons.

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
| `RunAnywhereAI/Helpers/` | `SmartMarkdownRenderer` (`AdaptiveMarkdownText`), `InlineMarkdownRenderer.swift` (declares `MarkdownText`, not a type of its own name), `AdaptiveLayout` |
| `RunAnywhereAI/Shared/` | `SharedConstants` (IPC keys, Darwin notification names, URL scheme), `SharedDataBridge` |
| `RunAnywhereKeyboard/` | `KeyboardViewController` (IPC via Darwin notifications), `KeyboardView`, `Info.plist` with `RequestsOpenAccess`, app-group entitlement |
| `RunAnywhereActivityExtension/` | `WidgetBundle` entry and the Dynamic Island / Lock Screen Live Activity |

Diffusion and image generation are excluded from the v1 build; see the comment at the top
of `RunAnywhereAIApp.swift` and the matching one in `ModelCatalogBootstrap.swift`. Their
products, registration calls, feature folders, catalog rows, and `generateImage` APIs are
deliberately absent.

## Features

### Chat and LLM

`LLMViewModel` is split across ten files by concern: core state and `sendMessage()` in
`LLMViewModel.swift`, then `+Generation` (streaming and non-streaming), `+ToolCalling`,
`+ModelManagement`, `+Analytics`, `+Events` (Combine subscription to `RunAnywhere.eventBus`),
`+Documents` (RAG-backed attachments), `+MessageActions`, `+Vision`, and the shared
`LLMViewModelTypes`. `ToolCallingModelPolicy` gates tools on context length alone
(`minimumContextTokens = 1024` against the model's `contextLength`), not on model identity;
its companion `ToolCallingExecutionPolicy` caps the run at two tool calls and 96 tokens of
final response, at temperature 0 with reasoning off.

Flow: input, `sendMessage()`, `prepareMessagesForSending()` (creates the user message and an
empty assistant message), `executeGeneration()`, `performGeneration()`, then the streaming,
non-streaming, or tool-calling path, token-by-token message updates, `finalizeGeneration()`,
and persistence to `ConversationStore`.

Tool calling runs through `RunAnywhere.llm.generate` with the registry active; the SDK owns
the call and execute loop and the format is auto-detected per model.

LoRA lives almost entirely in the SDK. `ModelCatalogBootstrap.registerLoraAdapters()` seeds
the curated catalog as `RALoraAdapterCatalogEntry` values, mirroring Android's
`ModelBootstrap.seedLora`, and registers each one with `RunAnywhere.lora.registerArtifact`.
From there the app calls `RunAnywhere.lora.queryCatalog(_:)` (with an
`RALoraAdapterCatalogQuery`), `.download(_:artifact:)`, `.importAdapter(from:)`,
`.applyCatalogAdapter(_:localPath:scale:)`, `.apply(RALoraApplyRequest)` for a raw path,
`.remove(RALoraRemoveRequest)`, and `.state()`. Removal is id-keyed or `clearAll`; the old
path-keyed fallback was deleted. Scale is user-adjustable.

Conversations persist as per-conversation JSON under `Documents/Conversations/`, attachments
under `Conversations/Attachments/{conversationID}/`. Search covers titles and message content.

Titles are written by whichever model answered, through `RunAnywhere.llm`, not by a separate
`FoundationModels.LanguageModelSession`. Apple's Foundation Models will not serve two clients
against one on-device model: the old app-side title session hung and wedged every subsequent
turn behind it with no error and no timeout. Only one title task exists at a time and
`cancelPendingTitleGeneration()` hands the model back the moment the chat claims a new turn.

Analytics: `MessageAnalytics` per message (time to first token, tokens per second, thinking
mode, completion status) and `ConversationAnalytics` rolled up onto the stored `Conversation`.
`ChatDetailsView` recomputes its figures from the per-message records rather than reading the
rolled-up type, and shows tokens per second, thinking usage, success rate, and average total
generation time. Per-message TTFT is rendered in `ChatMessageComponents`, not in
`ChatDetailsView`.

Thinking mode: models with `supportsThinking` expose reasoning through the SDK's `reasoning`
options and `thinkingText` or stream thought events. Commons owns tag parsing and `/no_think`
directives; the app toggles the mode and renders the returned channel in a collapsible
section.

Documents attached to a chat go through `ChatAttachmentLoader` and `DocumentService` for text
extraction, then `RunAnywhere.rag.open(embeddingModel:llmModel:)` for a `RagSession` cached on
the view model. The cache key is document plus embedding model plus answer model, so a session
is reused across turns rather than being strictly one per conversation. There is no separate
RAG screen.

### Voice agent

`RunAnywhere.voice.createSession(stt:llm:tts:)` then `session.start()`, which is the only
call that opens the microphone. `session.events` yields `agentStateChanged` (with
`.listening`, `.thinking`, `.speaking`), `speechStarted`, `speechEnded`, `userTranscribed`,
`agentResponse`, `inputSilent`, and `error`. `session.interrupt()` and `session.close()` are
the other two verbs. The SDK owns the whole audio pipeline including its own VAD. The user
loads STT, LLM, and TTS models independently through `ModelSelectionSheet`.

`VoiceAssistantParticleView` is a Metal-rendered 2000-particle system: a Fibonacci-lattice
sphere that morphs to a ring while listening or speaking, with amplitude from the real
microphone level when listening and a simulated sine wave when speaking, and touch scatter
decaying at 0.92.

### Speech, synthesis, and voice activity

STT has three modes. Batch records audio then calls
`RunAnywhere.stt.transcribe(.pcm16(buffer, sampleRate: 16_000))`. Live yields microphone
chunks into `RunAnywhere.stt.transcribeStream(_:)`, which owns segmentation and emits
`.partial` and `.final`. Hybrid runs on-device first with cloud fallback through the SDK's
`HybridSTTRouter`. Capture is the SDK's `AudioCaptureManager` driven by the app-local
`AudioCapturePump`; no app-side silence detection exists.

TTS is `RunAnywhere.tts.speak(text, options: TtsOptions(speed:))`, which synthesizes and plays
inside the SDK and hands back a handle. The app awaits `handle.waitForPlayout()` and interrupts
with `handle.interrupt()`; the whole-engine `RunAnywhere.tts.stop()` is deprecated and used only
as a fallback when no handle exists. Use `tts.synthesize(_:)` when the `Audio` buffer is wanted
instead of playback.

VAD feeds microphone chunks to `RunAnywhere.vad.detectStream(_:)`, which emits `VadEvent`
values: `.speechStarted`, `.speechEnded`, per-chunk `.activity(isSpeech, _, _)`, `.failed`, and
`.completed`. Framing is the SDK's job. The activity log holds 50 entries.

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
captures every 2.5 seconds (`autoStreamInterval`) and clears on the first token, so an
unchanged scene does not repeat itself. Its token cap is `autoStreamMaxTokens = 64`; the
single-shot path has its own, larger `singleShotMaxTokens`. Pixel conversion belongs to the SDK: pass
`ImageInput` a `CVPixelBuffer` and do not bridge through `CIContext`.

### Benchmarks

Deterministic tests across LLM, STT, TTS, and VLM, each with a `BenchmarkScenarioProvider`.
`BenchmarkRunner` orchestrates with cooperative cancellation. Results persist as JSON, capped
at 50 runs. `BenchmarkExportFormat` offers Markdown and JSON; CSV exists only as a
`writeCSV(run:)` file writer with no picker entry. `SyntheticInputGenerator` produces silent
and sine-wave audio (440 Hz at 16 kHz) and solid and gradient 224x224 images. LLM scenarios
run at 50, 256, and 512 tokens measuring TTFT and decode speed.

### Models

`ModelListViewModel` is the canonical registry singleton, subscribed to
`RunAnywhere.eventBus.modelLifecycle` for live load and unload state. `ModelSelectionSheet` is
the universal picker, parameterized by `ModelSelectionContext`: `.llm`, `.stt`, `.tts`, `.vad`,
`.voice`, `.vlm`, `.ragEmbedding`, `.ragLLM`, `.diarization`, `.segmentation`. Custom models
arrive through `AddModelFromURLView` or `AddFromHuggingFaceView`. `ModelRecommendationEngine`
and `ModelCompatibilityLookup` drive the recommended set, and `HardwareTier` scopes it to the
device.

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
`UserDefaults`, and API key and base URL in the Keychain. Temperature, max tokens, and system
prompt each save on a Combine `debounce(0.5s)`; the thinking-mode toggle writes through
immediately.

`ToolSettingsViewModel` is a separate singleton and registers tools through
`RunAnywhere.llm.tools`. Six are always available: `get_weather` (Open-Meteo),
`get_current_time`, `calculate` (a recursive-descent `SafeMathEvaluator`), `get_device_info`,
`get_battery_level`, and the SDK's own web search, added by `RunAnywhere.registerWebSearchTool()`.
Two more are opt-in behind a toggle and a permission prompt: `get_calendar_events`
(`CalendarTool`) and `get_health_data` (`HealthKitTool`, iOS only). `registerBuiltInTools()`
restores the enabled set at launch, because assigning a stored property inside `init` does not
fire `didSet`.

## Markdown rendering

One path, not a detect-and-route chain. `MarkdownBlockParser.parse(_:)` turns the reply into
`[MarkdownBlock]` (`paragraph`, `heading`, `list`, `quote`, `code`, `rule`) with no SwiftUI
involved, and `AdaptiveMarkdownText` renders one view per block: `MarkdownListView`,
`MarkdownQuoteView`, `MarkdownCodeBlock` (syntax-colored header, copy button, monospaced
scrollable body), and inline text through `MarkdownText` in `InlineMarkdownRenderer.swift`,
which uses `AttributedString(markdown:)` with bold as `.semibold`, italic as `.italic`, and
inline code monospaced and purple-tinted.

## SDK surface used here

Every call goes through the `RunAnywhere` enum. One namespace per modality; the SDK owns model
resolution, loading, downloading, and orchestration behind each verb. What follows is what this
app actually calls, not the SDK's full surface, which is larger.

```swift
// Core
try RunAnywhere.initialize(apiKey:baseUrl:environment:)   // one call, both phases
RunAnywhere.isReady
RunAnywhere.eventBus.events / .modelLifecycle             // Combine, raw RASDKEvent protos
RunAnywhere.clearCache() / .cleanTempFiles()

// Models
RunAnywhere.models.list(filter:) / .get(id:) / .register(_:) / .refresh()
RunAnywhere.models.download(id:) / .isResumable(...) / .checkCompatibility(...)
RunAnywhere.models.load(id:options:) / .unload(category:) / .delete(id:) / .state()

// Generation
RunAnywhere.llm.generate(...) / .generateStream(...)
RunAnywhere.llm.tools.register(_:executor:) / .list() / .clear()
RunAnywhere.vlm.generate(image:prompt:options:) / .generateStream(...)

// Audio and vision
RunAnywhere.stt.transcribe(_:options:) / .transcribeStream(_:options:)
RunAnywhere.tts.speak(_:options:) / .synthesize(_:options:) / .stop()
RunAnywhere.vad.detectStream(_:options:)
RunAnywhere.diarization.diarize(_:options:)
RunAnywhere.segmentation.segment(_:options:)

// Sessions
let voice = try await RunAnywhere.voice.createSession(stt:llm:tts:)
try voice.start()             // the only thing that opens the microphone
let rag = try await RunAnywhere.rag.open(embeddingModel:llmModel:)

// LoRA
RunAnywhere.lora.registerArtifact(_:artifact:) / .allRegistered() / .queryCatalog(_:)
RunAnywhere.lora.download(_:artifact:) / .importAdapter(from:) / .applyCatalogAdapter(...)
RunAnywhere.lora.apply(RALoraApplyRequest) / .remove(RALoraRemoveRequest) / .state()
```

The SDK also exposes `embeddings`, `rerank`, `images`, `generateStructured`, `tts.voices()`,
`vad.detect(_:)`, `RunAnywhere.events`, `.version`, `.deviceId`, and `deleteStorage(_:)`. This
app calls none of them. Do not document them here as if it did.

Inputs are `AudioInput` and `ImageInput`. The app constructs `.pcm16`, `.uiImage`, and
`.pixelBuffer`; the other cases exist but go unused here. Options types carry all-optional
fields whose defaults come from the IDL, so the app passes only what it overrides: `LlmOptions`
and `TtsOptions` in practice.

One-shot verbs throw `SDKException`. Stream factories are `async throws -> AsyncThrowingStream`,
so they throw on preflight failure and throw into the consumer mid-flight. No result carries a
`success` flag and no error text hides in a payload field. Cancel by cancelling the consuming
Task; there are no cancel verbs.

The older flat verbs (`loadModel`, `transcribe`, `ragQuery`) are deprecated forwarders in the
SDK. Do not use them here.

`RunAnywhere+ExampleShims.swift` holds one app-local helper,
`RunAnywhere.getRegisteredFrameworks() -> [RAInferenceFramework]`, which composes
`RunAnywhere.models.list()` into a framework filter sorted by descending model count. A new
feature needing net-new C bridge code belongs in the SDK; only UI plumbing over existing
canonical proto APIs belongs in that file.

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

## Scripts and configuration

| Script | Purpose |
|---|---|
| `scripts/build_and_run_ios_sample.sh` | Resolve, build, and deploy to simulator, device, or Mac |
| `scripts/verify.sh` | Local gate: resolves the remote SDK release, runs a full `xcodebuild` |
| `scripts/smoke.sh` | Greps sources for SDK call patterns and asserts the Parakeet CTC catalog policy, without compiling. Gated in CI. |

| File | Purpose |
|---|---|
| `Package.swift` | One dependency: `github.com/RunanywhereAI/runanywhere-swift` at `from: "0.20.19"`, giving RunAnywhere, RunAnywhereONNX, RunAnywhereLlamaCPP, RunAnywhereMLX, RunAnywhereNeuRT. The Xcode project mirrors it with `upToNextMajorVersion` from the same minimum, and declares all five products on the app target. Its `RunAnywhereAITests` testTarget must point at `RunAnywhereAIUnitTests/`, not the XCUITest bundle. |
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
