import SwiftUI

/// Renders whichever More destination is open, or the hub when none is.
///
/// The switch is exhaustive on purpose: adding a case to `MoreDestination`
/// should fail to compile until it has a screen, rather than silently falling
/// through to a blank pane.
///
/// The platform branches below are the exception. Some screens are written for
/// one platform only and their type does not exist on the other, so the case
/// still has to compile there. `MoreDestination.isAvailable` keeps those
/// destinations off the hub, so the empty branch is unreachable.
struct MoreHost: View {
    @Binding var destination: MoreDestination?

    var body: some View {
        if let destination {
            screen(for: destination)
        } else {
            MoreScreen(destination: $destination)
        }
    }

    @ViewBuilder
    private func screen(for destination: MoreDestination) -> some View {
        switch destination {
        case .talk: TalkScreen()
        case .transcribe: TranscribeScreen()
        case .readAloud: ReadAloudScreen()
        case .voiceActivity: VoiceActivityScreen()
        case .diarization:
            #if os(iOS)
            DiarizationScreen()
            #else
            EmptyView()
            #endif
        case .vision: VisionScreen()
        case .segmentation:
            #if os(iOS)
            SegmentationScreen()
            #else
            EmptyView()
            #endif
        case .computerUse: ComputerUseScreen()
        case .benchmarks: BenchmarksScreen()
        case .connect:
            #if os(macOS)
            ConnectScreen()
            #else
            EmptyView()
            #endif
        case .storage: StorageScreen()
        }
    }
}
