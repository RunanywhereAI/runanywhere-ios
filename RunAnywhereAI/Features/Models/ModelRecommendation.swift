//
//  ModelRecommendation.swift
//  RunAnywhereAI
//
//  Curated catalog picks for the Models / Voice screens. Model-fit decisions
//  consume SDK/commons `RAModelCompatibilityResult.canRun` when supplied; the
//  app never invents a per-tier memory budget.
//

import Foundation
import RunAnywhere

/// The curated set of recommendations surfaced at the top of the Models screen.
struct RecommendedSelection {
    /// The single best default chat model (Apple Foundation when available,
    /// otherwise the best-fit local LLM for this tier).
    let defaultChatModel: RAModelInfo?
    /// 3-5 LLMs appropriate for the tier, ordered from light to smart.
    let recommendedLLMs: [RAModelInfo]
    let recommendedASR: RAModelInfo?
    let recommendedTTS: RAModelInfo?
    let recommendedVLM: RAModelInfo?
    let recommendedEmbedding: RAModelInfo?

    /// All ids surfaced above the catalog, used to avoid duplicating them in
    /// the searchable list below.
    var surfacedModelIDs: Set<String> {
        var ids = Set(recommendedLLMs.map(\.id))
        [defaultChatModel, recommendedASR, recommendedTTS, recommendedVLM, recommendedEmbedding]
            .compactMap { $0?.id }
            .forEach { ids.insert($0) }
        return ids
    }

    /// The "also recommended" companions (ASR/TTS/VLM/embedding) in a stable order.
    var companions: [RAModelInfo] {
        [recommendedVLM, recommendedASR, recommendedTTS, recommendedEmbedding].compactMap { $0 }
    }
}

/// The best-for-device Voice AI trio (+ VAD) used to pre-configure the Voice
/// assistant with zero manual picking.
struct VoicePipeline {
    /// Speech-to-text model.
    let stt: RAModelInfo?
    /// Language model (Apple Foundation preferred when available).
    let llm: RAModelInfo?
    /// Text-to-speech model.
    let tts: RAModelInfo?
    /// Voice-activity-detection model (silero-vad).
    let vad: RAModelInfo?

    /// True when the three primary components (STT/LLM/TTS) are all resolved.
    var isComplete: Bool {
        stt != nil && llm != nil && tts != nil
    }
}

/// Pure engine that maps curated preference ids + optional commons
/// compatibility verdicts to a `RecommendedSelection`.
struct ModelRecommendationEngine {
    /// Preferred LLM ids per tier, ordered light → smart. The engine keeps the
    /// first few that are both present in the catalog and allowed by can_run.
    fileprivate struct TierPreferences {
        let llmIDs: [String]
        let asrIDs: [String]
        let ttsIDs: [String]
        let vlmIDs: [String]
        let embeddingIDs: [String]
    }

    func recommend(
        tier: HardwareTier,
        appleFoundationAvailable: Bool,
        from models: [RAModelInfo],
        canRunByModelID: [String: Bool] = [:]
    ) -> RecommendedSelection {
        let byID = Dictionary(models.map { ($0.id, $0) }) { first, _ in first }
        let prefs = preferences(for: tier)

        let recommendedLLMs = pickModels(
            ids: prefs.llmIDs,
            category: .language,
            from: byID,
            canRunByModelID: canRunByModelID,
            limit: 5
        )

        let appleFoundation = appleFoundationAvailable
            ? models.first { $0.isAppleFoundationModel && $0.category == .language }
            : nil

        let defaultChat = appleFoundation ?? recommendedLLMs.first

        return RecommendedSelection(
            defaultChatModel: defaultChat,
            recommendedLLMs: recommendedLLMs,
            recommendedASR: pickFirst(
                ids: prefs.asrIDs,
                category: .speechRecognition,
                from: byID,
                canRunByModelID: canRunByModelID
            ),
            recommendedTTS: pickFirst(
                ids: prefs.ttsIDs,
                category: .speechSynthesis,
                from: byID,
                canRunByModelID: canRunByModelID
            ),
            recommendedVLM: pickFirst(
                ids: prefs.vlmIDs,
                category: .multimodal,
                secondaryCategory: .vision,
                from: byID,
                canRunByModelID: canRunByModelID
            ),
            recommendedEmbedding: pickFirst(
                ids: prefs.embeddingIDs,
                category: .embedding,
                from: byID,
                canRunByModelID: canRunByModelID
            )
        )
    }

    /// Best-for-device Voice AI trio (+ VAD), reusing the same curated per-tier
    /// preferences. LLM prefers Apple Foundation when available, else the top
    /// recommended local LLM. Pure — safe to call from a view model.
    func recommendVoicePipeline(
        tier: HardwareTier,
        appleFoundationAvailable: Bool,
        from models: [RAModelInfo],
        canRunByModelID: [String: Bool] = [:]
    ) -> VoicePipeline {
        let byID = Dictionary(models.map { ($0.id, $0) }) { first, _ in first }
        let prefs = preferences(for: tier)

        let appleFoundation = appleFoundationAvailable
            ? models.first { $0.isAppleFoundationModel && $0.category == .language }
            : nil
        let llm = appleFoundation
            ?? pickFirst(ids: prefs.llmIDs, category: .language, from: byID, canRunByModelID: canRunByModelID)

        return VoicePipeline(
            stt: pickFirst(
                ids: prefs.asrIDs,
                category: .speechRecognition,
                from: byID,
                canRunByModelID: canRunByModelID
            ),
            llm: llm,
            tts: pickFirst(
                ids: prefs.ttsIDs,
                category: .speechSynthesis,
                from: byID,
                canRunByModelID: canRunByModelID
            ),
            // Through `pickFirst` like every other component, rather than a
            // hand-rolled lookup. That one skipped the `can_run` gate the rest of
            // the pipeline applies, so a VAD commons had already ruled out could
            // still be handed back, and it read `Dictionary.values.first`, whose
            // order is undefined once a catalog carries a second VAD row.
            vad: pickFirst(
                ids: [Self.vadModelID],
                category: .voiceActivityDetection,
                from: byID,
                canRunByModelID: canRunByModelID
            )
        )
    }

    /// The registered VAD model id (see `ModelCatalogBootstrap`).
    static let vadModelID = "silero-vad"

    // MARK: - Selection helpers

    /// Keep the ordered ids that exist in the catalog and pass can_run (when
    /// known), up to `limit`, then back-fill from the category if the curated
    /// list came up short.
    ///
    /// The back-fill is not a nicety. Curated ids are the app's opinion about
    /// which models are good; the catalog is edited on its own schedule, in its
    /// own PR, usually by someone not reading this file. Without a floor, a
    /// catalog pass that renames or drops a family silently turns the Models
    /// screen into a screen that recommends nothing — which is exactly what the
    /// 0.20.24 catalog rebuild did here, taking all five reachable ids with it.
    /// Mirrors Android `ModelRecommendation.pickLLMs`.
    private func pickModels(
        ids: [String],
        category: RAModelCategory,
        from byID: [String: RAModelInfo],
        canRunByModelID: [String: Bool],
        limit: Int
    ) -> [RAModelInfo] {
        var picked: [RAModelInfo] = []
        var pickedIDs = Set<String>()

        for id in ids {
            guard picked.count < limit else { break }
            if let model = byID[id], isRunnable(model, canRunByModelID: canRunByModelID) {
                picked.append(model)
                pickedIDs.insert(model.id)
            }
        }

        guard picked.count < minimumRecommendations else { return picked }

        // Smallest first, so a back-filled list still opens with something the
        // device can plausibly run rather than with the biggest file present.
        let backfill = byID.values
            .filter { $0.category == category }
            .filter { !pickedIDs.contains($0.id) }
            .filter { isRunnable($0, canRunByModelID: canRunByModelID) }
            .sorted { $0.consumerSizeBytes < $1.consumerSizeBytes }

        for model in backfill where picked.count < limit {
            picked.append(model)
            pickedIDs.insert(model.id)
        }
        return picked
    }

    /// Below this, the curated list is treated as having failed and the category
    /// back-fill runs. Matches Android's threshold.
    private let minimumRecommendations = 3

    /// First catalog model from the ordered ids that passes can_run when known,
    /// falling back to the smallest model in the category. Same reasoning as
    /// `pickModels`: a stale id must degrade to a worse answer, never to none.
    private func pickFirst(
        ids: [String],
        category: RAModelCategory,
        secondaryCategory: RAModelCategory? = nil,
        from byID: [String: RAModelInfo],
        canRunByModelID: [String: Bool]
    ) -> RAModelInfo? {
        for id in ids {
            if let model = byID[id], isRunnable(model, canRunByModelID: canRunByModelID) {
                return model
            }
        }
        return byID.values
            .filter { $0.category == category || $0.category == secondaryCategory }
            .filter { isRunnable($0, canRunByModelID: canRunByModelID) }
            .min { $0.consumerSizeBytes < $1.consumerSizeBytes }
    }

    /// Prefer commons `can_run`. When the SDK has not returned a verdict for
    /// this id, allow the catalog entry through — never invent a local byte
    /// budget in place of typed compatibility.
    private func isRunnable(_ model: RAModelInfo, canRunByModelID: [String: Bool]) -> Bool {
        canRunByModelID[model.id] ?? true
    }

    // MARK: - Curated per-tier preferences (real registered ids)

    /// `HardwareTierResolver` returns `.unknown` on every device today, so a
    /// straight tier switch meant one list was the only list anything ever read.
    /// Until commons publishes a typed tier, the platform is the one honest
    /// signal available: a Mac is not a phone. That is not a RAM heuristic and
    /// not a memory budget, so it does not cross the line the rest of this file
    /// holds. A real tier, when it arrives, outranks it.
    private func preferences(for tier: HardwareTier) -> TierPreferences {
        switch tier {
        case .lowEnd: return .lowEnd
        case .midRange: return .midRange
        case .highEnd: return .highEnd
        case .unknown:
            #if os(macOS)
            return .highEnd
            #else
            return .midRange
            #endif
        }
    }
}

// MARK: - Curated id lists

// Ids from the 0.20.24 catalog rebuild, ordered by how good the model is rather
// than by how small it is. Size still decides the back-fill, because a fallback
// should be cheap; these lists are where the app states a preference.
//
// Per-app curated lists are a deliberate, known-bad tradeoff: six apps hold six
// copies of this judgement, which is the shape of the breakage the back-fill
// above now absorbs. Promoting the ranking onto the catalog row is the escape
// hatch if it bites twice.
//
// MLX ids appear alongside their GGUF twins. MLX registration fails on the arm64
// simulator, so those rows are simply absent there and the next id wins.

private extension ModelRecommendationEngine.TierPreferences {
    /// Smallest current-generation models. Nothing above ~2B.
    static let lowEnd = Self(
        llmIDs: [
            "mlx-lfm2.5-230m-4bit",
            "lfm2.5-230m-q4_k_m",
            "mlx-qwen3.5-0.8b-mlx-4bit",
            "qwen3.5-0.8b-q4_k_m"
        ],
        asrIDs: [
            "sherpa-onnx-whisper-tiny.en"
        ],
        ttsIDs: [
            "vits-piper-en_US-lessac-medium"
        ],
        vlmIDs: [
            "smolvlm2-256m-video-instruct-q8_0",
            "lfm2.5-vl-3b-q4_k_m"
        ],
        embeddingIDs: [
            "all-minilm-l6-v2"
        ]
    )

    /// The phone and iPad default: a spread from instant to genuinely capable,
    /// none of it large enough to be a bad idea on battery.
    static let midRange = Self(
        llmIDs: [
            "mlx-lfm2.5-230m-4bit",
            "mlx-lfm2.5-1.2b-instruct-4bit",
            "lfm2.5-1.2b-instruct-q4_k_m",
            "mlx-qwen3.5-2b-4bit",
            "qwen3.5-2b-q4_k_m"
        ],
        asrIDs: [
            "sherpa-onnx-whisper-tiny.en"
        ],
        ttsIDs: [
            "vits-piper-en_US-lessac-medium"
        ],
        // No MLX Qwen2-VL, and no Qwen-family VLM as the default. Measured on an
        // M4 Max (MLX 4-bit): every vision turn decoded its opening token and
        // then repeated only that token, on photographs and synthetic cards
        // alike, while the MLX text path answered normally with the same sampler
        // settings. The web SDK forces Qwen2-VL off WebGPU for an f16 M-RoPE
        // overflow; this is the same family failing the same way on Metal.
        vlmIDs: [
            "lfm2.5-vl-3b-q4_k_m",
            "smolvlm2-500m-video-instruct-q8_0",
            "smolvlm2-256m-video-instruct-q8_0"
        ],
        embeddingIDs: [
            "all-minilm-l6-v2"
        ]
    )

    /// Mac. Commons still gates each id on real device RAM through `can_run`,
    /// so naming a 27B here is a preference, not a promise.
    static let highEnd = Self(
        llmIDs: [
            "mlx-lfm2.5-1.2b-instruct-4bit",
            "granite-4.1-3b-q4_k_m",
            "lfm2.5-1.2b-instruct-q4_k_m",
            "qwen3.5-4b-q4_k_m",
            "mlx-qwen3.5-4b-4bit"
        ],
        asrIDs: [
            "sherpa-onnx-whisper-tiny.en"
        ],
        ttsIDs: [
            "vits-piper-en_US-lessac-medium"
        ],
        vlmIDs: [
            "lfm2.5-vl-3b-q4_k_m",
            "mlx-qwen3-vl-4b-instruct-4bit"
        ],
        embeddingIDs: [
            "all-minilm-l6-v2"
        ]
    )
}
