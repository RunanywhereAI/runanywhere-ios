# RunAnywhere AI for iOS and macOS

<p align="center">
  <img src="https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/docs/logo.svg" alt="RunAnywhere" width="120"/>
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://img.shields.io/badge/App%20Store-Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store" />
  </a>
  <a href="https://github.com/RunanywhereAI/runanywhere-ios/releases/latest">
    <img src="https://img.shields.io/badge/macOS-Download%20.dmg-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.5%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 17.5+" />
  <img src="https://img.shields.io/badge/macOS-14.5%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14.5+" />
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.2" />
  <img src="https://img.shields.io/badge/License-RunAnywhere-blue?style=flat-square" alt="RunAnywhere License" />
</p>

The RunAnywhere consumer app for iPhone, iPad, and Mac, written in Swift.

Ask it questions, talk to it, or show it what your camera sees. The models run on the device
itself, so your prompts and photos never leave it, and everything still works in airplane
mode.

The one exception is Connect, described below, where you deliberately host a model on your
own Mac and use it from your iPhone. In that mode the request travels to that Mac. It still
reaches no third party.

## Get it

| Platform | Where |
| --- | --- |
| iPhone, iPad | [App Store](https://apps.apple.com/us/app/runanywhere/id6756506307) |
| Mac | [Signed `.dmg`](https://github.com/RunanywhereAI/runanywhere-ios/releases/latest), notarized by Apple, macOS 14.5 or newer |

To install on a Mac, open the `.dmg` and drag RunAnywhereAI to Applications.

<!-- GIF slot: chat with tool calling, the voice agent, and camera vision.
     Waiting on the capture pass that follows the current app bug fixes. -->

## What it looks like

Captured on an iPhone 17 Pro simulator, running a small GGUF chat model through the
llama.cpp backend.

| | |
|---|---|
| ![Chat with a model loaded](docs/screenshots/03-ready.png) | ![A streamed answer](docs/screenshots/04-chat.png) |
| Model loaded and ready. The header shows which one is active and that it is local. | An answer, with tokens per second and wall time under it. Nothing left the device. |
| ![Choosing a model](docs/screenshots/02-model-picker.png) | ![The Advanced hub](docs/screenshots/06-more.png) |
| Models are grouped by who published them. The picker recommends one for the device, and can pull any GGUF from Hugging Face. | Everything beyond chat lives here, grouped by what it does. |
| ![Segmentation](docs/screenshots/19-segmentation.png) | ![Settings](docs/screenshots/14-settings.png) |
| Segmentation outlines objects in a photo and labels them. | Settings covers the system prompt, sampling, tool calling, and local storage. |

The image files are in [`docs/screenshots/`](docs/screenshots).

## What you can do

| | |
| --- | --- |
| **Chat** | Streaming conversation with thinking mode, tool calling, and document attachments |
| **Talk** | A spoken conversation. Speech in, model, speech back out |
| **Vision** | Ask about a photo, or point the camera and ask about what it sees live |
| **Transcribe** | Turn recordings or live speech into text |
| **Read aloud** | Neural Piper voices speak any text you give them |
| **Documents** | Drop in a file and ask questions about what is inside it |
| **Voice keyboard** | Dictate into any app through the keyboard extension |
| **Connect** | Host a model on your Mac and use it from your iPhone |
| **Benchmarks** | Measure what your own hardware actually does |

Chat is the app. Everything else sits behind an Advanced hub, reached from the chat on
iPhone and from the sidebar on Mac.

## Models

The picker groups models by publisher, so you pick a name you recognise and then a size. It
carries current-generation open models across chat, vision, speech, and embedding, from a
230M model that answers instantly to larger ones a Mac can hold. Sizes shown are measured,
not estimated, and the app checks each one against your device before recommending it.

You can also paste any GGUF repo from Hugging Face and it will be fetched and registered
alongside the rest.

## Build it yourself

There is no monorepo to clone and no XCFramework to stage. SwiftPM downloads the
checksum-verified native archives when it resolves.

```bash
git clone https://github.com/RunanywhereAI/runanywhere-ios.git
cd runanywhere-ios
swift package resolve
open RunAnywhereAI.xcodeproj      # then press ⌘R
```

Or from the command line:

```bash
./scripts/build_and_run_ios_sample.sh simulator "iPhone 17 Pro"
./scripts/build_and_run_ios_sample.sh device
./scripts/build_and_run_ios_sample.sh mac
```

You need Xcode 26 or newer with Swift 6.2, and a few GB of disk for the SDK artifacts plus
whichever models you download. MLX models need a physical device or a native Mac. On the
simulator `MLX.register()` returns false, so the build validates packaging and startup but
runs no MLX inference.

[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) covers version pinning, tests, CI, and
troubleshooting.

## Architecture

One dependency supplies everything. The app links five products from
[`runanywhere-swift`](https://github.com/RunanywhereAI/runanywhere-swift), the Swift-only
SwiftPM distribution generated from the SDK monorepo, currently pinned at `0.20.24`.

```text
              RunAnywhereAI
        SwiftUI, MVVM + Observation
                    │
        ┌───────────┴────────────┐
        │    runanywhere-swift   │   one package, five products
        └───────────┬────────────┘
                    │
   ┌────────────┬───┴────┬─────────────┬──────────────┐
   │            │        │             │              │
RunAnywhere  LlamaCPP   ONNX          MLX           NeuRT
   core      LLM · VLM  STT·TTS·VAD   device or     Apple Neural
                                      native Mac    Engine
                    │
                    ▼
            C++ commons, one core
      shared with Kotlin, Web, and Electron
```

Business logic lives in the SDK rather than here. The app is SwiftUI views, view models, and
thin `RunAnywhere.*` calls, one entry point per modality.

| Reference | |
| --- | --- |
| Per-feature behavior and SDK surface | [`docs/reference/FEATURES.md`](docs/reference/FEATURES.md) |
| Navigation and shell structure | [`docs/reference/ARCHITECTURE.md`](docs/reference/ARCHITECTURE.md) |
| Building, pinning, tests, CI | [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) |
| Contributor conventions | [`AGENTS.md`](AGENTS.md) |

## The other apps

| Platform | Repo |
| --- | --- |
| Android, Kotlin | [runanywhere-android](https://github.com/RunanywhereAI/runanywhere-android) |
| Windows, Electron | [runanywhere-electron](https://github.com/RunanywhereAI/runanywhere-electron) |
| Web, TypeScript | [runanywhere-web](https://github.com/RunanywhereAI/runanywhere-web) |
| SDK monorepo | [runanywhere-sdks](https://github.com/RunanywhereAI/runanywhere-sdks) |
| Documentation | [docs.runanywhere.ai](https://docs.runanywhere.ai) |
| Discord | [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd) |

## License

RunAnywhere License, Apache 2.0 based with additional commercial-use terms. See
[LICENSE](LICENSE).
