import Foundation
import Observation
import RunAnywhere
import os

struct InstalledModel: Identifiable, Hashable {
    let id: String
    let name: String
    let publisher: String
    let sizeLabel: String
    let backend: String
    let category: String
    let supportsThinking: Bool
    let contextLength: Int
    let supportsTools: Bool
    let purpose: ModelPurpose
    let isDownloaded: Bool
    let isAvailable: Bool
}

@Observable
@MainActor
final class ModelStore {
    private(set) var models: [InstalledModel] = []
    private(set) var raw: [ModelInfo] = []
    private(set) var loadedLanguageModel: InstalledModel?
    private(set) var isRefreshing = false
    private(set) var downloading: [String: Double] = [:]
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "ModelStore")

    var installed: [InstalledModel] { models.filter(\.isDownloaded) }
    var downloadable: [InstalledModel] { models.filter { !$0.isDownloaded } }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let list = try await RunAnywhere.models.list()
            raw = list
            models = list.map(Self.map)
            let state = await RunAnywhere.models.state()
            loadedLanguageModel = state.loaded[.language].map(Self.map)
            lastError = nil
        } catch {
            logger.error("model list failed: \(error, privacy: .public)")
            lastError = String(describing: error)
        }
    }

    func download(_ id: String) async {
        guard downloading[id] == nil else { return }
        downloading[id] = 0
        defer { downloading[id] = nil }
        do {
            let stream = try await RunAnywhere.models.download(id: id)
            for try await event in stream {
                switch event {
                case .started:
                    downloading[id] = 0
                case .progress(let snapshot):
                    if let percent = snapshot.percent {
                        downloading[id] = min(max(Double(percent) / 100, 0), 1)
                    }
                case .verifying:
                    downloading[id] = 1
                case .extracting(_, _, let percent):
                    downloading[id] = percent.map { min(max(Double($0) / 100, 0), 1) } ?? 1
                case .completed:
                    downloading[id] = 1
                    // Refresh inside the stream, not only after it: the loop can
                    // stay open for verification and extraction, and the row
                    // should flip to Installed the moment the bytes are down.
                    await refresh()
                case .failed(_, _, let error):
                    lastError = error.message
                case .cancelled:
                    break
                }
            }
            await refresh()
            lastError = nil
        } catch {
            logger.error("download failed for \(id, privacy: .public): \(error, privacy: .public)")
            lastError = String(describing: error)
        }
    }

    func name(for id: String) -> String {
        models.first { $0.id == id }?.name ?? id
    }

    var isDownloading: Bool { !downloading.isEmpty }

    var aggregateProgress: Double {
        guard !downloading.isEmpty else { return 0 }
        return downloading.values.reduce(0, +) / Double(downloading.count)
    }

    func delete(_ id: String) async {
        do {
            try await RunAnywhere.models.delete(id: id)
            await refresh()
            lastError = nil
        } catch {
            logger.error("delete failed for \(id, privacy: .public): \(error, privacy: .public)")
            lastError = String(describing: error)
        }
    }

    func load(_ id: String) async throws {
        _ = try await RunAnywhere.models.load(id: id)
    }

    private static func map(_ info: ModelInfo) -> InstalledModel {
        InstalledModel(
            id: info.id,
            name: info.name.isEmpty ? info.id : info.name,
            publisher: publisher(for: info),
            sizeLabel: sizeLabel(info.downloadSizeBytes),
            backend: backendLabel(info),
            category: categoryLabel(info),
            supportsThinking: info.supportsThinking,
            contextLength: Int(info.contextLength),
            supportsTools: ModelPurpose.of(info) == .language && ToolCapability.supports(
                id: info.id,
                name: info.name,
                downloadBytes: info.downloadSizeBytes
            ),
            purpose: ModelPurpose.of(info),
            isDownloaded: !info.localPath.isEmpty,
            isAvailable: info.isAvailableForUse
        )
    }

    private static func publisher(for info: ModelInfo) -> String {
        let name = info.name.isEmpty ? info.id : info.name
        let lowered = name.lowercased()
        let table: [(String, String)] = [
            ("qwen", "Qwen"),
            ("gemma", "Google"),
            ("lfm", "Liquid AI"),
            ("liquid", "Liquid AI"),
            ("ministral", "Mistral"),
            ("mistral", "Mistral"),
            ("llama", "Meta"),
            ("granite", "IBM"),
            ("phi", "Microsoft"),
            ("smol", "Hugging Face"),
            ("whisper", "OpenAI"),
            ("parakeet", "NVIDIA"),
            ("piper", "Piper"),
            ("silero", "Silero"),
            ("sherpa", "Sherpa")
        ]
        for (needle, label) in table where lowered.contains(needle) {
            return label
        }
        return "Other"
    }

    private static func sizeLabel(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func categoryLabel(_ info: ModelInfo) -> String {
        let raw = String(describing: info.category).lowercased()
        if raw.contains("speechrecognition") { return "Speech to text" }
        if raw.contains("speechsynthesis") || raw.contains("texttospeech") { return "Text to speech" }
        if raw.contains("voiceactivity") { return "Voice activity" }
        if raw.contains("diariz") { return "Diarization" }
        if raw.contains("segment") { return "Segmentation" }
        if raw.contains("embedding") { return "Embedding" }
        if raw.contains("multimodal") || raw.contains("vision") { return "Vision" }
        return "Language"
    }

    private static func backendLabel(_ info: ModelInfo) -> String {
        let raw = String(describing: info.preferredFramework).lowercased()
        if raw.contains("mlx") { return "MLX" }
        if raw.contains("llama") { return "llama.cpp" }
        if raw.contains("onnx") || raw.contains("sherpa") { return "ONNX" }
        if raw.contains("neurt") || raw.contains("ane") { return "ANE" }
        return "Local"
    }
}
