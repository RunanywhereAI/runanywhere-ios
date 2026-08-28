import Foundation
import Observation
import RunAnywhere
import os

@Observable
@MainActor
final class DefaultModels {
    var llmID: String? { didSet { persist(llmID, for: Key.llm) } }
    var ttsID: String? { didSet { persist(ttsID, for: Key.tts) } }
    var sttID: String? { didSet { persist(sttID, for: Key.stt) } }
    var embeddingID: String? { didSet { persist(embeddingID, for: Key.embedding) } }
    var visionID: String? { didSet { persist(visionID, for: Key.vision) } }

    private(set) var loaded: Set<String> = []
    private(set) var isPreparing = false
    var lastError: String?
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "DefaultModels")

    private enum Key {
        static let llm = "default.model.llm"
        static let tts = "default.model.tts"
        static let stt = "default.model.stt"
        static let embedding = "default.model.embedding"
        static let vision = "default.model.vision"
    }

    init() {
        llmID = UserDefaults.standard.string(forKey: Key.llm)
        ttsID = UserDefaults.standard.string(forKey: Key.tts)
        sttID = UserDefaults.standard.string(forKey: Key.stt)
        embeddingID = UserDefaults.standard.string(forKey: Key.embedding)
        visionID = UserDefaults.standard.string(forKey: Key.vision)
    }

    /// Fills in whatever the reader has not chosen with the model this app
    /// ships pointed at.
    ///
    /// Every id starts empty, so a fresh install had a default for nothing: the
    /// reader who could name a model did not need the choice, and the reader who
    /// needed it could not make it. Seeding is done from what is actually on
    /// disk — a modality whose download has not finished is left unset rather
    /// than pointed at something absent — and it never overwrites a choice, so
    /// this is safe to call on every catalog refresh.
    func seed(from models: [ModelInfo]) {
        if llmID == nil { llmID = settled(.language, from: models) }
        if visionID == nil { visionID = settled(.vision, from: models) }
        if sttID == nil { sttID = settled(.speechToText, from: models) }
        if ttsID == nil { ttsID = settled(.textToSpeech, from: models) }
        if embeddingID == nil { embeddingID = settled(.embedding, from: models) }
    }

    /// What should answer for `purpose` right now: the shipped pick when it is
    /// on disk, otherwise the smallest thing installed that can do the job.
    ///
    /// The fallback matters more than it sounds. Someone who already has models
    /// from before this list existed has none of ours, and without it every
    /// modality would read as unset on a machine that is fully equipped.
    /// Smallest rather than first because the order of the catalog is not a
    /// ranking, and because size is the one axis on which the safe default is
    /// obvious — it is also what keeps a four-billion-parameter computer-use
    /// agent from being handed a photo to describe.
    private func settled(_ purpose: ModelPurpose, from models: [ModelInfo]) -> String? {
        if let shipped = ShippedModels.installed(for: purpose, from: models) {
            return shipped.id
        }
        return models
            .filter {
                ModelPurpose.of($0) == purpose
                    && (!$0.localPath.isEmpty || $0.isBuiltIn)
                    && $0.isAvailableForUse
                    && !$0.isLoRAAdapterArtifact
            }
            .min { $0.consumerSizeBytes < $1.consumerSizeBytes }?
            .id
    }

    /// Load `id` and confirm it actually landed in `category`.
    ///
    /// The in-memory `loaded` set is a cache, never the source of truth: a model
    /// can be evicted natively without the app hearing about it, and a stale
    /// "already loaded" reading is how a session opens against nothing.
    @discardableResult
    func ensureLoaded(_ id: String?, category: ModelCategory? = nil) async -> Bool {
        guard let id else { return false }

        if let category, await isLoaded(id, in: category) {
            loaded.insert(id)
            return true
        }

        do {
            _ = try await RunAnywhere.models.load(id: id)
            loaded.insert(id)
            guard let category else { return true }
            let confirmed = await isLoaded(id, in: category)
            if !confirmed {
                logger.error("\(id, privacy: .public) loaded but is not active for \(String(describing: category), privacy: .public)")
            }
            return confirmed
        } catch {
            logger.error("load failed for \(id, privacy: .public): \(error, privacy: .public)")
            lastError = "Could not load that model: \(error.localizedDescription)"
            return false
        }
    }

    private func isLoaded(_ id: String, in category: ModelCategory) async -> Bool {
        let state = await RunAnywhere.models.state()
        return state.loaded[category]?.id == id
    }

    func warmUp() async {
        await ensureLoaded(ttsID, category: .speechSynthesis)
        await ensureLoaded(sttID, category: .speechRecognition)
    }

    func resolveVision(from installed: [InstalledModel]) -> String? {
        if let visionID, installed.contains(where: { $0.id == visionID }) { return visionID }
        let candidates = installed.filter { $0.purpose == .vision }
        return candidates.count == 1 ? candidates[0].id : nil
    }

    /// Loads a vision model into the multimodal slot. `vlm.generate` resolves
    /// `.multimodal` first and falls back to `.vision`, so a model that is only
    /// downloaded is not enough: it has to be the loaded one.
    func prepareVision(_ id: String) async -> Bool {
        isPreparing = true
        defer { isPreparing = false }
        var ok = await ensureLoaded(id, category: .multimodal)
        if !ok {
            ok = await ensureLoaded(id, category: .vision)
        }
        if ok { visionID = id }
        return ok
    }

    /// The embedding model documents should be indexed with: the chosen
    /// default, or the only installed one when nothing has been chosen.
    func resolveEmbedding(from installed: [InstalledModel]) -> String? {
        if let embeddingID, installed.contains(where: { $0.id == embeddingID }) { return embeddingID }
        let candidates = installed.filter { $0.purpose == .embedding }
        return candidates.count == 1 ? candidates[0].id : nil
    }

    /// The model dictation should use: the chosen default, or the only installed
    /// speech model when nothing has been chosen yet.
    func resolveSTT(from installed: [InstalledModel]) -> String? {
        if let sttID, installed.contains(where: { $0.id == sttID }) { return sttID }
        let candidates = installed.filter { $0.purpose == .speechToText }
        guard candidates.count == 1 else { return nil }
        return candidates[0].id
    }

    func prepareSTT(_ id: String) async -> Bool {
        isPreparing = true
        defer { isPreparing = false }
        let ok = await ensureLoaded(id, category: .speechRecognition)
        if ok { sttID = id }
        return ok
    }

    private func persist(_ value: String?, for key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
