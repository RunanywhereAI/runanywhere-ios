# RunAnywhere AI iOS and macOS example

<p align="center">
  <img src="https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/docs/logo.svg" alt="RunAnywhere" width="120"/>
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://img.shields.io/badge/App%20Store-Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store" />
  </a>
</p>

A reference app for the [RunAnywhere Swift SDK](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/bindings/swift/README.md):
LLM chat, speech, vision, voice agents, RAG, benchmarks, and model management, running
on-device on iPhone, iPad, and Mac.

## Requirements

| Item | Minimum |
|---|---|
| Xcode | 26+, with Swift 6.2 and iOS 17.5 simulator runtimes |
| Platforms | iOS 17.5, macOS 14.5 |
| Command line tools | Selected in Xcode, Settings, Locations |
| Disk | Several GB for SDK artifacts and models |
| Device | Apple Silicon recommended; MLX needs a physical device or native macOS |

## Setup

The SDK comes entirely from its published GitHub release. There is no monorepo checkout to
build and no XCFramework to stage: SwiftPM downloads the checksum-verified native archives
during resolve.

```bash
git clone https://github.com/RunanywhereAI/runanywhere-ios.git
cd runanywhere-ios
swift package resolve
```

`Package.swift` declares one dependency, and the Xcode project mirrors it:

```swift
.package(
    url: "https://github.com/RunanywhereAI/runanywhere-swift.git",
    from: "$LATEST-VERSION"
)
```

| Product | Role |
|---|---|
| `RunAnywhere` | Core SDK, always required |
| `RunAnywhereLlamaCPP` | llama.cpp backend: LLM, VLM |
| `RunAnywhereONNX` | Sherpa-ONNX backend: STT, TTS, VAD |
| `RunAnywhereMLX` | Apple MLX backend, physical device or native macOS |
| `RunAnywhereNeuRT` | Apple Neural Engine backend, registered behind `#if canImport(NeuRTRuntime)` |

`from:` is a version range, not a revision pin: it accepts every release up to the next
major. `Package.resolved` records the exact version and commit that resolve selected, and
it is committed — CI fails if it disagrees with the manifest, so commit it whenever the
dependency moves.

To take a newer SDK release within the same major, run `swift package update` and commit
the refreshed `Package.resolved`. To *require* a newer minimum, bump the version in
`Package.swift` and in the Xcode project's package reference, then resolve again. If
resolution misbehaves, use File, Packages, Reset Package Caches first.

## Build and run

Open `RunAnywhereAI.xcodeproj` and press ⌘R, or:

```bash
./scripts/build_and_run_ios_sample.sh simulator "iPhone 16 Pro"
./scripts/build_and_run_ios_sample.sh device
./scripts/build_and_run_ios_sample.sh mac
```

`./scripts/verify.sh` runs the same gate as CI (resolve plus a full `xcodebuild`).
`./scripts/smoke.sh` greps the sources for SDK call patterns without compiling.

Runtime logs: filter Console.app on `subsystem:com.runanywhere.RunAnywhereAI`.

## Tests

Unit tests live in `RunAnywhereAIUnitTests/` and build into the `RunAnywhereAITests`
target; the XCUITest launch test lives in `RunAnywhereAIUITests/`. Both need a booted
simulator:

```bash
xcodebuild test \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:RunAnywhereAITests
```

Drop `-only-testing:` to run the UI test as well.

## Continuous integration

`.github/workflows/ci.yml` runs on pushes and pull requests against `main`. It checks out a
clean clone on `macos-latest` (the macOS 26 arm64 image, the line carrying Xcode 26, which
`swift-tools-version: 6.2` requires), then:

1. resolves the SDK remotely, to prove no monorepo checkout is needed, and fails if the
   resolve left `Package.resolved` dirty (i.e. the committed pin was stale);
2. builds the `RunAnywhereAI` scheme for `generic/platform=iOS Simulator`, which pulls in
   the keyboard and Live Activity extensions;
3. runs `-only-testing:RunAnywhereAITests` on a booted simulator;
4. runs `./scripts/smoke.sh`.

Signing is off, since a simulator build needs no identity and hosted runners have no
`DEVELOPMENT_TEAM`.

## Features

| Feature | Description |
|---|---|
| Chat | Streaming LLM with thinking mode, tool calling, document attachments, and LoRA adapters |
| Speech to text | Batch, live, and hybrid transcription (Sherpa-ONNX, Whisper) |
| Text to speech | Neural Piper voices |
| Talk | Full STT, LLM, TTS voice agent with a Metal particle UI |
| Vision | Camera and photo-library image understanding, including a live mode |
| Diarization and segmentation | Who spoke when; labelled photo regions |
| Computer use | The model reads a screenshot and acts on it |
| Connect | Host a model on a Mac and share it with your other devices |
| Benchmarks | Deterministic LLM, STT, TTS, and VLM performance tests |
| Voice keyboard | iOS keyboard extension with a cross-process dictation flow |
| Model management | Download, load, storage, and deletion, plus Hugging Face import |

MLX-backed models run on physical iOS devices and native macOS. The arm64 simulator build
validates packaging and startup but does not execute MLX inference.

## Layout

`RunAnywhereAI/` holds the app: `App/` (entry point and platform shells), `Features/`,
`Core/` (design system, services, models), and `Helpers/`. `RunAnywhereKeyboard/` and
`RunAnywhereActivityExtension/` are the two extension targets. Architecture is MVVM with
Swift Observation, one `RunAnywhere.*` entry point per modality, and centralized design
tokens around brand orange `#FF6900`. `AGENTS.md` has the full reference.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Missing XCFramework errors | Reset package caches and rerun `swift package resolve` so SwiftPM re-downloads the release archives |
| Package resolution failures | Same: reset caches, resolve again |
| Sandbox or derived-data issues | Clean the build folder (⇧⌘K), delete DerivedData if it persists |
| MLX unavailable | Use a physical device or native macOS; MLX reports unavailable on the simulator |

## Links

| Resource | Link |
|---|---|
| Swift SDK | [bindings/swift](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/bindings/swift/README.md) |
| Android example | [runanywhere-android](https://github.com/RunanywhereAI/runanywhere-android) |
| Web example | [runanywhere-web](https://github.com/RunanywhereAI/runanywhere-web) |
| Electron example | [runanywhere-electron](https://github.com/RunanywhereAI/runanywhere-electron) |
| React Native example | [bindings/react-native/example](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/bindings/react-native/example/README.md) |
| Flutter example | [bindings/flutter/example](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/bindings/flutter/example/README.md) |
| App Store | [RunAnywhere](https://apps.apple.com/us/app/runanywhere/id6756506307) |
| Discord | [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd) |
| Issues | [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-ios/issues) |
| Email | founders@runanywhere.ai |

## License

RunAnywhere License, Apache 2.0 based with additional commercial-use terms. See
[LICENSE](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE).
