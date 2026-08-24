import SwiftUI

/// Everything the app can do that is not chat, models or settings.
///
/// Grouped the way the old Advanced hub grouped them, because the grouping was
/// the one part of that screen worth keeping: people look for "the voice one"
/// or "the vision one", not for an alphabetical list.
enum MoreDestination: String, CaseIterable, Identifiable {
    case talk
    case transcribe
    case readAloud
    case voiceActivity
    case diarization
    case vision
    case segmentation
    case computerUse
    case benchmarks
    case connect
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .talk: "Talk"
        case .transcribe: "Transcribe"
        case .readAloud: "Read Aloud"
        case .voiceActivity: "Voice Activity"
        case .diarization: "Diarization"
        case .vision: "Vision"
        case .segmentation: "Segmentation"
        case .computerUse: "Computer Use"
        case .benchmarks: "Benchmarks"
        case .connect: "Connect"
        case .storage: "Storage"
        }
    }

    var caption: String {
        switch self {
        case .talk: "Hold to speak, and it answers out loud"
        case .transcribe: "Turn a recording or live speech into text"
        case .readAloud: "Read any text in a downloaded voice"
        case .voiceActivity: "Watch speech being detected in real time"
        case .diarization: "Tell speakers apart in a recording"
        case .vision: "Ask about what the camera sees"
        case .segmentation: "Label every region of an image"
        case .computerUse: "Reason over a screenshot and pick an action"
        case .benchmarks: "Measure every downloaded model on this device"
        case .connect: "Share this Mac's models over the network"
        case .storage: "See what models are using, and reclaim it"
        }
    }

    var symbol: String {
        switch self {
        case .talk: "waveform.circle"
        case .transcribe: "text.bubble"
        case .readAloud: "speaker.wave.2"
        case .voiceActivity: "waveform.badge.magnifyingglass"
        case .diarization: "person.2.wave.2"
        case .vision: "camera.viewfinder"
        case .segmentation: "square.on.square.dashed"
        case .computerUse: "cursorarrow.rays"
        case .benchmarks: "gauge.with.dots.needle.bottom.50percent"
        case .connect: "antenna.radiowaves.left.and.right"
        case .storage: "internaldrive"
        }
    }

    enum Group: String, CaseIterable, Identifiable {
        case voice
        case vision
        case agents
        case device

        var id: String { rawValue }

        var title: String {
            switch self {
            case .voice: "Voice"
            case .vision: "Vision"
            case .agents: "Agents"
            case .device: "This device"
            }
        }
    }

    var group: Group {
        switch self {
        case .talk, .transcribe, .readAloud, .voiceActivity, .diarization: .voice
        case .vision, .segmentation: .vision
        case .computerUse: .agents
        case .benchmarks, .connect, .storage: .device
        }
    }

    /// Whether this belongs in front of someone who is not building on the SDK.
    ///
    /// The diagnostic screens are genuinely useful and genuinely confusing; a
    /// reader who came for a chat app should not meet a segmentation mask.
    var isDeveloperOnly: Bool {
        switch self {
        case .talk, .transcribe, .readAloud, .vision: false
        case .voiceActivity, .diarization, .segmentation, .computerUse, .benchmarks, .connect,
             .storage:
            true
        }
    }

    /// Screens that cannot run here at all, rather than merely being hidden.
    var isAvailable: Bool {
        switch self {
        case .diarization, .segmentation:
            // Both are hard-wired to UIKit image and audio types.
            #if os(iOS)
            true
            #else
            false
            #endif
        case .connect:
            // Hosting is the Mac side of Connect; the iOS client lives in chat.
            #if os(macOS)
            true
            #else
            false
            #endif
        default:
            true
        }
    }

    static func available(for mode: AppMode) -> [MoreDestination] {
        allCases.filter { $0.isAvailable && (mode == .developer || !$0.isDeveloperOnly) }
    }
}
