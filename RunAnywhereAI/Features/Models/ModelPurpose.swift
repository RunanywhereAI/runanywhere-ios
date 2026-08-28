import Foundation
import RunAnywhere

enum ModelPurpose: String, CaseIterable, Identifiable {
    case language
    case vision
    case speechToText
    case textToSpeech
    case embedding
    case voiceActivity
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .language: "Chat"
        case .vision: "Vision"
        case .speechToText: "Speech to text"
        case .textToSpeech: "Text to speech"
        case .embedding: "Embedding"
        case .voiceActivity: "Voice activity"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .language: "bubble.left.and.bubble.right"
        case .vision: "eye"
        case .speechToText: "waveform"
        case .textToSpeech: "speaker.wave.2"
        case .embedding: "point.3.connected.trianglepath.dotted"
        case .voiceActivity: "mic"
        case .other: "cube"
        }
    }

    static func of(_ info: ModelInfo) -> ModelPurpose {
        let raw = String(describing: info.category).lowercased()
        if raw.contains("speechrecognition") { return .speechToText }
        if raw.contains("speechsynthesis") || raw.contains("texttospeech") { return .textToSpeech }
        if raw.contains("voiceactivity") { return .voiceActivity }
        if raw.contains("embedding") { return .embedding }
        if raw.contains("multimodal") || raw.contains("vision") { return .vision }
        if raw.contains("language") { return .language }
        return .other
    }
}
