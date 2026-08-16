# RunAnywhereAI App Store release guide

Covers iOS and macOS releases of the shared `RunAnywhereAI` Xcode target: preparing and
validating local archives for App Store Connect. Upload and submission are separate,
explicit actions. Paths are relative to the repository root.

## Release invariants

- Build with the current App Store-required Xcode version. Check
  [Apple's upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)
  before each release.
- Keep iOS at `17.5` or later and macOS at `14.5` or later, matching
  `Package.swift`.
- Increment `CURRENT_PROJECT_VERSION` for every uploaded build. Update
  `MARKETING_VERSION` only when publishing a new user-facing version.
- Use the Release configuration and automatic signing for team `L86FH3K93L`.
- Never print, commit, or paste production credential values into logs or
  release notes.
- Do not upload until all archive checks in this guide pass.

## Production configuration

`RunAnywhereAI/App/RunAnywhereAIApp.swift` picks the API key and base URL from the
first source that yields a usable pair:

1. Keychain, written by the user in Settings (`runanywhere_api_key`, `runanywhere_base_url`).
2. `RunAnywhereLocalSecrets.plist` in the app bundle, keys `apiKey` and `baseURL`.
3. Info.plist keys `RUNANYWHERE_API_KEY` and `RUNANYWHERE_BASE_URL`, usually fed from an xcconfig.

Every candidate is rejected if it looks like a placeholder (`YOUR_`, `<your`,
`REPLACE_ME`, `PLACEHOLDER`, `$(`) or if the base URL is not a well-formed http or
https URL with a host. When nothing survives, a Release build calls `fatalError` at
launch; a Debug build falls back to `RunAnywhere.initialize(environment: .development)`.

The secrets plist is gitignored. Copy the template and fill it in:

```bash
SECRETS="RunAnywhereAI/Resources/RunAnywhereLocalSecrets.plist"
cp docs/RunAnywhereLocalSecrets.plist.example "$SECRETS"   # first time only
```

Verify it and both required keys without printing their values:

```bash
test -f "$SECRETS"
plutil -lint "$SECRETS"
/usr/libexec/PlistBuddy -c 'Print :apiKey' "$SECRETS" >/dev/null
/usr/libexec/PlistBuddy -c 'Print :baseURL' "$SECRETS" >/dev/null
```

The Release archive must contain both configuration files:

```bash
test -f "$APP/Contents/Resources/RunAnywhereLocalSecrets.plist" || \
  test -f "$APP/RunAnywhereLocalSecrets.plist"
test -f "$APP/Contents/Resources/RunAnywhereConfig-Release.plist" || \
  test -f "$APP/RunAnywhereConfig-Release.plist"
```

`RunAnywhereConfig-Release.plist` is bundled but no Swift code reads it today, so this
is a packaging assertion, not a functional one. The environment, base URL, and log level
that actually reach the SDK come from the credential sources above and from the
`environment:` argument in `RunAnywhereAIApp.swift`.

## Version and platform preflight

From the repository root:

```bash
PROJECT="RunAnywhereAI.xcodeproj"
SCHEME="RunAnywhereAI"

xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release -showBuildSettings \
  | rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|IPHONEOS_DEPLOYMENT_TARGET|MACOSX_DEPLOYMENT_TARGET'
```

Confirm:

- The marketing version matches the intended App Store version.
- The build number is higher than every build already uploaded for that
  marketing version.
- `IPHONEOS_DEPLOYMENT_TARGET` is `17.5` for `RunAnywhereAI` and `RunAnywhereKeyboard`.
  `RunAnywhereActivityExtension` reports `26.2`, which is correct: Live Activities in the
  shape this app uses need iOS 26. Do not lower it to make the output uniform.
- `MACOSX_DEPLOYMENT_TARGET` is `14.5`.

## App Store screenshots

Apple accepts one to ten screenshots per device family. Screenshots must show
the real app experience and use an accepted pixel size. Confirm current values
in [Apple's screenshot specification](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

Recommended master sizes for this app:

| Platform | Orientation | Master size |
|---|---:|---:|
| iPhone 6.9-inch | Portrait | `1320x2868` |
| macOS | Landscape, 16:10 | `2880x1800` |

Use sRGB PNG or JPEG without transparency. Keep the real UI as the dominant
content. Branded backgrounds and short factual captions are acceptable, but do
not imply that a capability was tested when it was not.

Capture assets are not tracked. `build/` is gitignored, so stage them there or anywhere
else and treat them as per-release artifacts.

Whatever a screenshot shows must have run on the build being shipped. MLX is the trap
here: it is a supported runtime, but it does not execute on the simulator that most
captures come from, so do not present it as tested evidence unless it was separately
verified on a device for that build.

## iOS build and archive

The iOS archive consumes immutable XCFrameworks whose metadata already declares
the canonical `MinimumOSVersion` of 17.5.

```bash
JOBS="$(sysctl -n hw.logicalcpu)"

# 1. Build the final Release inputs.
xcodebuild \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation \
  -jobs "$JOBS" \
  build

# 2. Archive into Xcode Organizer's standard folder.
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
ARCHIVE="$ARCHIVE_DIR/RunAnywhereAI iOS $(date +%Y-%m-%d\ %H.%M.%S).xcarchive"
mkdir -p "$ARCHIVE_DIR"

xcodebuild \
  -project RunAnywhereAI.xcodeproj \
  -scheme RunAnywhereAI \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -skipPackagePluginValidation \
  -jobs "$JOBS" \
  archive

open -a Xcode "$ARCHIVE"
```

## macOS build and archive

The Mac App Store build must include App Sandbox, Hardened Runtime, the app
privacy manifest, and the production configuration. The project supplies these
through `RunAnywhereAI.entitlements`, Release build settings, and
`PrivacyInfo.xcprivacy`.

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

An archive stored elsewhere may not appear automatically in Organizer. Put it
under `~/Library/Developer/Xcode/Archives/YYYY-MM-DD/` or open the `.xcarchive`
directly with Xcode.

## Archive validation

Set `ARCHIVE` to the new archive, then locate the app:

```bash
APP="$ARCHIVE/Products/Applications/RunAnywhereAI.app"
BIN="$APP/Contents/MacOS/RunAnywhereAI" # macOS
# BIN="$APP/RunAnywhereAI"              # iOS

test -d "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -archs "$BIN"
test -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" || \
  test -f "$APP/PrivacyInfo.xcprivacy"
test -f "$APP/Contents/Resources/RunAnywhereLocalSecrets.plist" || \
  test -f "$APP/RunAnywhereLocalSecrets.plist"
test -f "$APP/Contents/Resources/RunAnywhereConfig-Release.plist" || \
  test -f "$APP/RunAnywhereConfig-Release.plist"
test ! -e "$APP/Contents/Resources/RunAnywhereExportedSymbols.txt"
test ! -e "$APP/RunAnywhereExportedSymbols.txt"
```

For macOS, verify sandbox and Hardened Runtime without changing the signature:

```bash
codesign -d --entitlements :- "$APP" 2>/dev/null \
  | plutil -p - \
  | rg 'app-sandbox|application-groups|device.camera|device.audio-input|network.(client|server)|files.user-selected'

codesign -dvvv "$APP" 2>&1 | rg 'flags=.*runtime'
! xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1
```

`RunAnywhereAI.entitlements` is the reference for what should appear: App Sandbox, the
`group.com.runanywhere.runanywhereai` app group, `device.camera`, `device.audio-input`,
`network.client`, `network.server` (Connect hosts an `NWListener` over Bonjour),
`files.user-selected` read-only and read-write, HealthKit, and the increased memory limit.
Match on the real key names, not on the words "camera" and "microphone": the microphone
entitlement is spelled `com.apple.security.device.audio-input`.

A locally created development archive can contain `get-task-allow`; the App Store export
must be distribution-signed and must not retain it.

## Native ABI release gate

The linked binary must export every C symbol referenced by the Swift SDK.
Failure here causes startup errors such as:

```text
Native proto ABI is not exported by the linked RACommons binary: rac_sdk_init_phase1_proto
```

Run this against either the iOS or macOS archived binary. The expected set is derived from
the source directories listed below.

The Xcode target links five SDK products on both platforms: `RunAnywhere`,
`RunAnywhereLlamaCPP`, `RunAnywhereONNX`, `RunAnywhereMLX`, and `RunAnywhereNeuRT`. The
branches below predate that: the macOS branch audits only core and MLX, and neither branch
scans `NeuRTRuntime`. Widening them makes the gate stricter, so do it as a deliberate change
with an archive to test against, not silently during a release.

```bash
nm -gjU "$BIN" 2>/dev/null \
  | rg '^_(rac|ra_mlx)_' \
  | sed 's/^_//' \
  | sort -u > /tmp/runanywhere_archive_exported_symbols.txt

# `swift package resolve` places the SDK sources here. Xcode archives resolve
# into DerivedData instead, so override with
# SDK_CHECKOUT=<path-to-runanywhere-swift-checkout> when auditing those.
SDK_CHECKOUT="${SDK_CHECKOUT:-.build/checkouts/runanywhere-swift}"

if [[ "$BIN" == */Contents/MacOS/* ]]; then
  SRC_DIRS=(
    "$SDK_CHECKOUT/Sources/RunAnywhere"
    "$SDK_CHECKOUT/Sources/MLXRuntime"
  )
  REQUIRED_SYMBOLS=(
    rac_proto_buffer_free
    rac_backend_mlx_register
    rac_backend_mlx_unregister
    rac_mlx_set_callbacks
    ra_mlx_register_runtime
    ra_mlx_runtime_is_available
    ra_mlx_runtime_is_registered
    ra_mlx_unregister_runtime
  )
else
  SRC_DIRS=(
    "$SDK_CHECKOUT/Sources/RunAnywhere"
    "$SDK_CHECKOUT/Sources/LlamaCPPRuntime"
    "$SDK_CHECKOUT/Sources/ONNXRuntime"
    "$SDK_CHECKOUT/Sources/MLXRuntime"
  )
  REQUIRED_SYMBOLS=(
    rac_proto_buffer_free
    rac_backend_llamacpp_register
    rac_backend_llamacpp_unregister
    rac_backend_onnx_register
    rac_backend_onnx_unregister
    rac_plugin_entry_sherpa
    rac_plugin_register
    rac_plugin_unregister
    rac_backend_mlx_register
    rac_backend_mlx_unregister
    rac_mlx_set_callbacks
    ra_mlx_register_runtime
    ra_mlx_runtime_is_available
    ra_mlx_runtime_is_registered
    ra_mlx_unregister_runtime
  )
fi

rg -No '"(rac|ra_mlx)_[A-Za-z0-9_]+"' "${SRC_DIRS[@]}" --glob '*.swift' \
  | perl -ne 'while (/"((?:rac|ra_mlx)_[A-Za-z0-9_]+)"/g) { print "$1\n" }' \
  | sort -u > /tmp/runanywhere_expected_swift_native_symbols.from_strings

# The rg pass above is a plain text scan and does not evaluate `#if`, so it also
# picks up symbols that this archive correctly does not compile. Filter those, or
# the gate fails on every good archive.
#
#   ra_mlx_metal_resource_anchor is declared in MLXRuntime/MLX.swift inside
#   `#if RUNANYWHERE_MLX_DISTRIBUTION`. That flag is set only when the monorepo
#   builds the CocoaPods MLX distribution framework
#   (RUNANYWHERE_BUILD_MLX_DISTRIBUTION_FRAMEWORK=1). This app archives from
#   `runanywhere-swift`, which does not even ship the MLXRuntimeDistribution
#   target, so the symbol can never be present here.
#
# Add to this list only for a symbol you have confirmed is guarded out of this
# archive's configuration, never to silence a genuinely missing export.
PACKAGING_ONLY_SYMBOLS=(
  ra_mlx_metal_resource_anchor
)

{
  cat /tmp/runanywhere_expected_swift_native_symbols.from_strings
  printf '%s\n' "${REQUIRED_SYMBOLS[@]}"
} | sort -u \
  | grep -vxF "$(printf '%s\n' "${PACKAGING_ONLY_SYMBOLS[@]}")" \
  > /tmp/runanywhere_expected_swift_native_symbols.txt

comm -23 \
  /tmp/runanywhere_expected_swift_native_symbols.txt \
  /tmp/runanywhere_archive_exported_symbols.txt \
  > /tmp/runanywhere_missing_swift_native_symbols.txt

test ! -s /tmp/runanywhere_missing_swift_native_symbols.txt
```

The final command must pass. If it fails, rebuild the native XCFrameworks and
fix the Release linker/export settings before uploading.

## Organizer validation and upload

1. Open the archive in Xcode Organizer.
2. Select Validate App and resolve every blocking issue.
3. Select Distribute App, App Store Connect, Upload only after approval
   to upload.
4. In App Store Connect, attach the correct build, screenshots, release notes,
   privacy answers, and export-compliance answers.
5. Submit for review only after a final metadata and binary check.

Command-line export is optional and still does not upload. No export options plist is
tracked in this repo, so write one first (`method` = `app-store-connect`, plus your team
ID) and point at it:

```bash
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "build/archives/$(basename "$ARCHIVE" .xcarchive)-export" \
  -exportOptionsPlist "build/archives/ExportOptions-app-store-connect.plist" \
  -allowProvisioningUpdates
```

## Troubleshooting

### Archive is missing from Organizer

Confirm the archive is under Xcode's standard folder and open it directly:

```bash
find "$HOME/Library/Developer/Xcode/Archives" -name '*.xcarchive' -maxdepth 3 -print
open -a Xcode "$ARCHIVE"
```

### Invalid minimum OS version

Rebuild the canonical XCFrameworks; do not mutate DerivedData. Confirm the app
and every embedded framework declare the expected deployment floor.

### Missing native proto ABI

Do not retry or upload the same archive. Run the native ABI gate, rebuild the
XCFrameworks, and confirm the Release target still uses `-all_load`, the
exported-symbols list, and `STRIP_STYLE = non-global`.

### Signing or export failure

Confirm the Apple Developer account can manage signing and has a valid Apple
Distribution certificate and App Store provisioning profile for
`com.runanywhere.RunAnywhere`. A development-signed archive is sufficient for
local validation but not for the final App Store export.

## Final checklists

### iOS

```text
[ ] Marketing version and build number are correct
[ ] Production secrets and Release config are present without being printed
[ ] Release build succeeds at iOS 17.5
[ ] Every packaged framework declares `MinimumOSVersion = 17.5`
[ ] Archive appears in Organizer
[ ] Native ABI gate reports zero missing symbols
[ ] 1320x2868 screenshots are reviewed in upload order
[ ] Validate App passes before upload
```

### macOS

```text
[ ] Marketing version and build number are correct
[ ] Production secrets and Release config are present without being printed
[ ] Release build succeeds at macOS 14.5
[ ] App Sandbox, required entitlements, and Hardened Runtime are present
[ ] PrivacyInfo.xcprivacy is bundled
[ ] Archive appears in Organizer
[ ] codesign, architecture, quarantine, and native ABI checks pass
[ ] 2880x1800 screenshots are reviewed in upload order
[ ] App Store Connect Validate App passes before upload
```
