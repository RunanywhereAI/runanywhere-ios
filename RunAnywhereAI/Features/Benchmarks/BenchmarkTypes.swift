import Foundation
import RunAnywhere

enum BenchmarkCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case llm
    case stt
    case tts
    case vlm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .llm: "Language"
        case .stt: "Speech to text"
        case .tts: "Text to speech"
        case .vlm: "Vision"
        }
    }

    var code: String {
        switch self {
        case .llm: "LLM"
        case .stt: "STT"
        case .tts: "TTS"
        case .vlm: "VLM"
        }
    }

    var symbol: String {
        switch self {
        case .llm: "text.bubble"
        case .stt: "waveform"
        case .tts: "speaker.wave.2"
        case .vlm: "eye"
        }
    }

    var purpose: ModelPurpose {
        switch self {
        case .llm: .language
        case .stt: .speechToText
        case .tts: .textToSpeech
        case .vlm: .vision
        }
    }

    var modelCategory: ModelCategory {
        switch self {
        case .llm: .language
        case .stt: .speechRecognition
        case .tts: .speechSynthesis
        case .vlm: .multimodal
        }
    }
}

/// One measured pass: which model, and what it was asked to do.
struct BenchmarkScenario: Codable, Hashable, Identifiable, Sendable {
    let category: BenchmarkCategory
    let name: String
    let detail: String

    var id: String { "\(category.rawValue).\(name)" }
}

/// The work behind a scenario. The parameters live here rather than in the
/// persisted `BenchmarkScenario` so a stored run never has to be re-read for
/// its inputs, and so the engine matches on a value the compiler checks.
enum BenchmarkWorkload: Sendable {
    case llm(maxTokens: Int)
    case stt(seconds: Double)
    case tts(text: String, label: String)
    case vlm(maxTokens: Int)

    var category: BenchmarkCategory { scenario.category }

    var scenario: BenchmarkScenario {
        switch self {
        case .llm(let maxTokens):
            BenchmarkScenario(category: .llm, name: "\(maxTokens) tokens", detail: "Decode \(maxTokens) tokens")
        case .stt(let seconds):
            BenchmarkScenario(
                category: .stt,
                name: "\(Int(seconds))s audio",
                detail: "Transcribe \(Int(seconds))s of synthetic 16 kHz mono PCM"
            )
        case let .tts(text, label):
            BenchmarkScenario(category: .tts, name: label, detail: "Synthesize \(text.count) characters")
        case .vlm(let maxTokens):
            BenchmarkScenario(
                category: .vlm,
                name: "\(maxTokens) tokens",
                detail: "Describe a synthetic 224 × 224 image in \(maxTokens) tokens"
            )
        }
    }

    static func all(for category: BenchmarkCategory) -> [BenchmarkWorkload] {
        switch category {
        case .llm:
            [.llm(maxTokens: 64), .llm(maxTokens: 256)]
        case .stt:
            [.stt(seconds: 3), .stt(seconds: 8)]
        case .tts:
            [
                .tts(text: BenchmarkPrompts.shortLine, label: "Short line"),
                .tts(text: BenchmarkPrompts.paragraph, label: "Paragraph")
            ]
        case .vlm:
            [.vlm(maxTokens: 96)]
        }
    }
}

/// A model as the engine sees it: everything it needs, nothing that ties it
/// to the main actor.
struct BenchmarkModelRef: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let backend: String
}

struct BenchmarkMetrics: Codable, Sendable {
    var loadMs: Double = 0
    var warmupMs: Double = 0
    var latencyMs: Double = 0
    var memoryDeltaBytes: Int64 = 0
    var ttftMs: Double?
    var prefillTokensPerSecond: Double?
    var decodeTokensPerSecond: Double?
    var inputTokens: Int?
    var outputTokens: Int?
    var audioSeconds: Double?
    var realTimeFactor: Double?
    var characters: Int?
}

/// The lowest and highest value a metric took across the measured trials.
struct BenchmarkRange: Codable, Sendable {
    let low: Double
    let high: Double
}

/// How far the headline metrics moved between trials. Absent for a single
/// trial, where there is no spread to report.
struct BenchmarkSpread: Codable, Sendable {
    let latencyMs: BenchmarkRange?
    let ttftMs: BenchmarkRange?
    let decodeTokensPerSecond: BenchmarkRange?
    let realTimeFactor: BenchmarkRange?
}

extension BenchmarkMetrics {
    /// Reduce repeated trials to a per-metric median plus the observed range.
    ///
    /// The median rather than the mean: a single pass that lands during
    /// thermal throttling or a background download would drag an average
    /// somewhere no trial actually reached, while the range keeps that
    /// outlier visible instead of hiding it.
    static func combine(_ trials: [BenchmarkMetrics]) -> (metrics: BenchmarkMetrics, spread: BenchmarkSpread?) {
        guard let first = trials.first else { return (BenchmarkMetrics(), nil) }
        guard trials.count > 1 else { return (first, nil) }

        func median(_ value: (BenchmarkMetrics) -> Double?) -> Double? {
            let sorted = trials.compactMap(value).filter(\.isFinite).sorted()
            guard !sorted.isEmpty else { return nil }
            let middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2)
                ? (sorted[middle - 1] + sorted[middle]) / 2
                : sorted[middle]
        }

        func medianCount(_ value: (BenchmarkMetrics) -> Int?) -> Int? {
            median { value($0).map(Double.init) }.map { Int($0.rounded()) }
        }

        func range(_ value: (BenchmarkMetrics) -> Double?) -> BenchmarkRange? {
            let values = trials.compactMap(value).filter(\.isFinite)
            guard values.count > 1, let low = values.min(), let high = values.max() else { return nil }
            return BenchmarkRange(low: low, high: high)
        }

        var combined = BenchmarkMetrics()
        combined.loadMs = median { $0.loadMs } ?? 0
        combined.warmupMs = median { $0.warmupMs } ?? 0
        combined.latencyMs = median { $0.latencyMs } ?? 0
        combined.memoryDeltaBytes = Int64((median { Double($0.memoryDeltaBytes) } ?? 0).rounded())
        combined.ttftMs = median { $0.ttftMs }
        combined.prefillTokensPerSecond = median { $0.prefillTokensPerSecond }
        combined.decodeTokensPerSecond = median { $0.decodeTokensPerSecond }
        combined.inputTokens = medianCount { $0.inputTokens }
        combined.outputTokens = medianCount { $0.outputTokens }
        combined.audioSeconds = median { $0.audioSeconds }
        combined.realTimeFactor = median { $0.realTimeFactor }
        combined.characters = medianCount { $0.characters }

        let spread = BenchmarkSpread(
            latencyMs: range { $0.latencyMs },
            ttftMs: range { $0.ttftMs },
            decodeTokensPerSecond: range { $0.decodeTokensPerSecond },
            realTimeFactor: range { $0.realTimeFactor }
        )
        return (combined, spread)
    }
}

struct BenchmarkResult: Codable, Identifiable, Sendable {
    let id: UUID
    let category: BenchmarkCategory
    let scenario: BenchmarkScenario
    let model: BenchmarkModelRef
    let trials: Int
    let metrics: BenchmarkMetrics
    let spread: BenchmarkSpread?
    let failure: String?

    var didSucceed: Bool { failure == nil }

    init(
        category: BenchmarkCategory,
        scenario: BenchmarkScenario,
        model: BenchmarkModelRef,
        trials: Int,
        metrics: BenchmarkMetrics,
        spread: BenchmarkSpread? = nil,
        failure: String? = nil
    ) {
        self.id = UUID()
        self.category = category
        self.scenario = scenario
        self.model = model
        self.trials = trials
        self.metrics = metrics
        self.spread = spread
        self.failure = failure
    }
}

struct BenchmarkDevice: Codable, Sendable {
    let model: String
    let chip: String
    let osVersion: String
    let totalMemoryBytes: Int64
    let cores: Int

    static var current: BenchmarkDevice {
        let info = DeviceInfoFactory.current
        return BenchmarkDevice(
            model: info.deviceModel,
            chip: info.chipName,
            osVersion: info.osVersion,
            totalMemoryBytes: info.totalMemoryBytes,
            cores: Int(info.coreCount)
        )
    }
}

struct BenchmarkRun: Codable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case completed
        case failed
        case cancelled

        var title: String {
            switch self {
            case .completed: "Completed"
            case .failed: "Failed"
            case .cancelled: "Cancelled"
            }
        }
    }

    let id: UUID
    let startedAt: Date
    var finishedAt: Date?
    let device: BenchmarkDevice
    var results: [BenchmarkResult]
    var status: Status

    var duration: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }

    var succeeded: Int { results.filter(\.didSucceed).count }

    var categories: [BenchmarkCategory] {
        BenchmarkCategory.allCases.filter { category in
            results.contains { $0.category == category }
        }
    }

    init(device: BenchmarkDevice) {
        self.id = UUID()
        self.startedAt = Date()
        self.device = device
        self.results = []
        self.status = .failed
    }
}

struct BenchmarkProgress: Sendable {
    let completed: Int
    let total: Int
    let modelName: String
    let scenarioName: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

/// The fixed inputs every run uses. Deterministic by construction: the same
/// text, the same audio and the same image on every device, so two reports can
/// be compared without asking what was fed in.
enum BenchmarkPrompts {
    static let system = "You are a benchmarking harness. Answer at length and never stop early."

    static let generation = """
        Explain how a transformer language model turns a prompt into text, covering tokenization, \
        embeddings, attention, the feed-forward blocks, sampling, and the key-value cache. Be thorough.
        """

    static let shortLine = "The quick brown fox jumps over the lazy dog."

    static let paragraph = """
        Speech synthesis turns a sequence of characters into a waveform. The model predicts duration, \
        pitch and timbre for every phoneme, then a vocoder renders those features as audio samples.
        """

    static let imageQuestion = "Describe this image in detail."
}
