# Development reference

Detail moved out of the root README so it stays a consumer-facing page. Everything here
is about building, testing, and pinning the SDK, not about using the app.

## Setup

There is no monorepo checkout to build and no XCFramework to stage. SwiftPM downloads the
checksum-verified native archives during resolve.

```bash
git clone https://github.com/RunanywhereAI/runanywhere-ios.git
cd runanywhere-ios
swift package resolve
```

`Package.swift` declares one dependency, and the Xcode project mirrors it:

```swift
.package(
    url: "https://github.com/RunanywhereAI/runanywhere-swift.git",
    from: "0.20.24"
)
```

`runanywhere-swift` is a Swift-only SwiftPM distribution generated from the
`runanywhere-sdks` monorepo. Consume it rather than the monorepo: it is a few MB instead
of a few hundred, and it carries the generated proto sources that the monorepo no longer
commits. Its tags are bare semver with no `v` prefix, which is what `from:` needs. The
XCFramework binary targets still point at the checksum-verified release assets on
`runanywhere-sdks`.

The five products it publishes, all of which this app links:

| Product | Role |
|---|---|
| `RunAnywhere` | Core SDK, always required |
| `RunAnywhereLlamaCPP` | llama.cpp backend: LLM, VLM |
| `RunAnywhereONNX` | Sherpa-ONNX backend: STT, TTS, VAD |
| `RunAnywhereMLX` | Apple MLX backend, physical device or native macOS |
| `RunAnywhereNeuRT` | Apple Neural Engine backend |

Three files have to agree on the version: `Package.swift` (`from:`), the Xcode project's
package reference (`upToNextMajorVersion` from the same minimum), and `Package.resolved`,
which records the exact version and commit resolve selected. `Package.resolved` is
committed and CI fails if a fresh resolve leaves it dirty.

To take a newer SDK release within the same major, run `swift package update` and commit
the refreshed `Package.resolved`. To require a newer minimum, bump the version in
`Package.swift` and in the Xcode project's package reference, then resolve again. If
resolution misbehaves, use File, Packages, Reset Package Caches first.

## Build and run

Open `RunAnywhereAI.xcodeproj` and press ⌘R, or:

```bash
./scripts/build_and_run_ios_sample.sh simulator "iPhone 16 Pro"
./scripts/build_and_run_ios_sample.sh device
./scripts/build_and_run_ios_sample.sh mac
```

`./scripts/verify.sh` resolves the package and runs a full simulator `xcodebuild`, which is
the slow half of CI. `./scripts/smoke.sh` is the fast half: it greps the sources for SDK
call patterns and checks the Parakeet CTC catalog entry, without compiling.

Runtime logs:

```bash
log stream --predicate 'subsystem CONTAINS "com.runanywhere"' --info --debug
```

Most loggers use the `com.runanywhere.RunAnywhereAI` subsystem, a couple use plain
`com.runanywhere`, and the SDK logs under its own, so match on the prefix.

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


## Layout

`RunAnywhereAI/` holds the app: `App/` (entry point and platform shells), `Features/`,
`Core/` (design system, services, models), and `Helpers/`. `RunAnywhereKeyboard/` and
`RunAnywhereActivityExtension/` are the two extension targets. The app and the keyboard
deploy to iOS 17.5; the Live Activity extension needs iOS 26.2, so on older systems it
simply does not load.

Architecture is MVVM with Swift Observation, one `RunAnywhere.*` entry point per modality,
and centralized design tokens around brand orange `#FF6900`. `AGENTS.md` has the full
reference.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Missing XCFramework errors | Reset package caches and rerun `swift package resolve` so SwiftPM re-downloads the release archives |
| Package resolution failures | Same: reset caches, resolve again |
| Sandbox or derived-data issues | Clean the build folder (⇧⌘K), delete DerivedData if it persists |
| MLX unavailable | Use a physical device or native macOS; MLX reports unavailable on the simulator |

