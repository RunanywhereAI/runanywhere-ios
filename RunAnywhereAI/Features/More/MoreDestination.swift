import SwiftUI

/// The SDK screens: every diagnostic surface that exists to show a builder what
/// a modality does.
///
/// None of these ship to someone who came to chat, so the whole hub is gated on
/// developer mode and the sidebar drops it in user mode. Connect used to live
/// here and now sits in Settings, because it is the one thing on this list a
/// reader would look for.
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
        case .benchmarks, .storage: .device
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
        default:
            true
        }
    }

    static var available: [MoreDestination] {
        allCases.filter(\.isAvailable)
    }
}
