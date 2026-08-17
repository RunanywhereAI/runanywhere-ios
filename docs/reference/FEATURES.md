# Feature behavior and SDK surface

Per-feature detail behind the one-line index in the root `AGENTS.md`. Read the relevant
section before touching that feature's code — several of these encode a fix for a real bug,
not just a design choice.

## Chat and LLM

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

## Voice agent

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

## Speech, synthesis, and voice activity

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

## Voice keyboard (RunAnywhereKeyboard + RunAnywhereActivityExtension)

Cross-process dictation over two IPC channels: App Group `UserDefaults`
(`group.com.runanywhere.runanywhereai`) for shared state (session state, transcribed text,
audio level, heartbeat), and Darwin `CFNotificationCenter` for zero-latency signals (six names
in `SharedConstants.DarwinNotifications`, in `RunAnywhereAI/Shared/`). Both channel definitions
are shared code, not owned by either extension target.

The keyboard's Run button opens `runanywhere://startFlow`. The main app activates a session,
loads the STT model, starts capture, and posts `sessionReady`. The user returns to the host
app, the keyboard sends `startListening`, the main app buffers audio, the keyboard sends
`stopListening`, the main app calls `RunAnywhere.stt.transcribe(_:)`, writes the result to
shared `UserDefaults`, and posts `transcriptionReady`; the keyboard inserts it through
`textDocumentProxy.insertText()`.

`DictationActivityAttributes.ContentState` (Live Activity, in `RunAnywhereActivityExtension/`)
carries phase, elapsed seconds, transcript, and word count for the Dynamic Island and Lock
Screen. A one-second heartbeat lets the keyboard detect a main-app crash after a three-second
staleness window.

Both extensions are thin: `RunAnywhereKeyboard/` is `KeyboardViewController` + `KeyboardView`;
`RunAnywhereActivityExtension/` is the `WidgetBundle` entry plus the Live Activity view. Neither
has its own build/test entry point — `scripts/build_and_run_ios_sample.sh` and `scripts/verify.sh`
build the whole app target including both extensions.

## Vision

Camera and photo-library image understanding, reached from the chat rather than its own tab.
`AVCaptureSession` with BGRA pixel format feeds
`RunAnywhere.vlm.generateStream(image: .pixelBuffer(frame), prompt:, options:)`. Live mode
captures every 2.5 seconds (`autoStreamInterval`) and clears on the first token, so an
unchanged scene does not repeat itself. Its token cap is `autoStreamMaxTokens = 64`; the
single-shot path has its own, larger `singleShotMaxTokens`. Pixel conversion belongs to the SDK: pass
`ImageInput` a `CVPixelBuffer` and do not bridge through `CIContext`.

## Benchmarks

Deterministic tests across LLM, STT, TTS, and VLM, each with a `BenchmarkScenarioProvider`.
`BenchmarkRunner` orchestrates with cooperative cancellation. Results persist as JSON, capped
at 50 runs. `BenchmarkExportFormat` offers Markdown and JSON; CSV exists only as a
`writeCSV(run:)` file writer with no picker entry. `SyntheticInputGenerator` produces silent
and sine-wave audio (440 Hz at 16 kHz) and solid and gradient 224x224 images. LLM scenarios
run at 50, 256, and 512 tokens measuring TTFT and decode speed.

## Models

`ModelListViewModel` is the canonical registry singleton, subscribed to
`RunAnywhere.eventBus.modelLifecycle` for live load and unload state. `ModelSelectionSheet` is
the universal picker, parameterized by `ModelSelectionContext`: `.llm`, `.stt`, `.tts`, `.vad`,
`.voice`, `.vlm`, `.ragEmbedding`, `.ragLLM`, `.diarization`, `.segmentation`. Custom models
arrive through `AddModelFromURLView` or `AddFromHuggingFaceView`. `ModelRecommendationEngine`
and `ModelCompatibilityLookup` drive the recommended set, and `HardwareTier` scopes it to the
device.

## Storage

`RunAnywhere.models.state()` gives used and free bytes;
`RunAnywhere.models.list(filter: ModelFilter(downloadedOnly: true))` gives the rows, filtered
to entries with a real on-disk size so Apple system pseudo-models drop out. Each row reads its
own `ModelInfo` for name, local path, framework, and `lastUsedAtUnixMs`. Deletion is
`RunAnywhere.models.delete(id:)`; cache and temp clearing are `RunAnywhere.clearCache()` and
`RunAnywhere.cleanTempFiles()`. `StorageViewModel` surfaces this inside Settings and the models
views.

## Settings and tools

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
