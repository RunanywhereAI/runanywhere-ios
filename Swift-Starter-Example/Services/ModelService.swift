//
//  ModelService.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App - Model Management Service
//

import SwiftUI
import Combine
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

// MARK: - LLM Model Variants
enum LLMModelVariant: String, CaseIterable, Identifiable {
    case lfm2_350m = "lfm2-350m-q4_k_m"
    case qwen3_06b = "qwen3-0.6b-q4_k_m"
    case qwen35_08b = "qwen3.5-0.8b-q4_k_m"
    case qwen35_2b = "qwen3.5-2b-q4_k_m"
    case qwen3_17b = "qwen3-1.7b-q4_k_m"
    case qwen35_4b = "qwen3.5-4b-q4_k_m"
    case qwen3_4b = "qwen3-4b-q4_k_m"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lfm2_350m: return "LFM2 350M"
        case .qwen3_06b: return "Qwen3 0.6B"
        case .qwen35_08b: return "Qwen3.5 0.8B"
        case .qwen35_2b: return "Qwen3.5 2B"
        case .qwen3_17b: return "Qwen3 1.7B"
        case .qwen35_4b: return "Qwen3.5 4B"
        case .qwen3_4b: return "Qwen3 4B"
        }
    }

    var url: URL {
        switch self {
        case .lfm2_350m:
            return URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf")!
        case .qwen3_06b:
            return URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf")!
        case .qwen35_08b:
            return URL(string: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf")!
        case .qwen35_2b:
            return URL(string: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf")!
        case .qwen3_17b:
            return URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf")!
        case .qwen35_4b:
            return URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf")!
        case .qwen3_4b:
            return URL(string: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf")!
        }
    }

    var memoryRequirement: Int64 {
        switch self {
        case .lfm2_350m: return 250_000_000
        case .qwen3_06b: return 500_000_000
        case .qwen35_08b: return 600_000_000
        case .qwen35_2b: return 1_500_000_000
        case .qwen3_17b: return 1_200_000_000
        case .qwen35_4b: return 2_800_000_000
        case .qwen3_4b: return 2_500_000_000
        }
    }

    var sizeLabel: String {
        switch self {
        case .lfm2_350m: return "~250 MB"
        case .qwen3_06b: return "~460 MB"
        case .qwen35_08b: return "~550 MB"
        case .qwen35_2b: return "~1.4 GB"
        case .qwen3_17b: return "~1.1 GB"
        case .qwen35_4b: return "~2.7 GB"
        case .qwen3_4b: return "~2.5 GB"
        }
    }

    var qualityLabel: String {
        switch self {
        case .lfm2_350m: return "Tiny, fastest inference"
        case .qwen3_06b: return "Small, fast, 32K context"
        case .qwen35_08b: return "Small, improved reasoning"
        case .qwen35_2b: return "Medium, strong quality"
        case .qwen3_17b: return "Medium, good balance"
        case .qwen35_4b: return "Large, best Qwen3.5 quality"
        case .qwen3_4b: return "Large, best Qwen3 quality"
        }
    }
}

// MARK: - STT Model Variants
enum STTModelVariant: String, CaseIterable, Identifiable {
    case whisperTiny = "sherpa-onnx-whisper-tiny.en"
    case whisperBase = "sherpa-onnx-whisper-base.en"
    case whisperSmall = "sherpa-onnx-whisper-small.en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperTiny: return "Whisper Tiny"
        case .whisperBase: return "Whisper Base"
        case .whisperSmall: return "Whisper Small"
        }
    }

    var registrationName: String {
        switch self {
        case .whisperTiny: return "Sherpa Whisper Tiny (ONNX)"
        case .whisperBase: return "Sherpa Whisper Base (ONNX)"
        case .whisperSmall: return "Sherpa Whisper Small (ONNX)"
        }
    }

    var url: URL {
        switch self {
        case .whisperTiny:
            return URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz")!
        case .whisperBase:
            return URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-base.en.tar.gz")!
        case .whisperSmall:
            return URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-small.en.tar.gz")!
        }
    }

    var memoryRequirement: Int64 {
        switch self {
        case .whisperTiny: return 75_000_000
        case .whisperBase: return 290_000_000
        case .whisperSmall: return 760_000_000
        }
    }

    var sizeLabel: String {
        switch self {
        case .whisperTiny: return "~75 MB"
        case .whisperBase: return "~253 MB"
        case .whisperSmall: return "~759 MB"
        }
    }

    var qualityLabel: String {
        switch self {
        case .whisperTiny: return "Fastest, basic accuracy"
        case .whisperBase: return "Balanced speed & accuracy"
        case .whisperSmall: return "Best accuracy, slower"
        }
    }
}

/// Service for managing AI models - handles downloading, loading, and state tracking
@MainActor
final class ModelService: ObservableObject {
    // MARK: - Model IDs (must match registered model IDs)
    static let ttsModelId = "vits-piper-en_US-lessac-medium"
    static let vlmModelId = "smolvlm-256m-instruct"
    static let diffusionModelId = "sd15-coreml-palettized"

    /// Currently selected LLM model variant, persisted across launches
    @Published var selectedLLMVariant: LLMModelVariant {
        didSet { UserDefaults.standard.set(selectedLLMVariant.rawValue, forKey: "selectedLLMVariant") }
    }

    /// Computed model ID for the active LLM variant
    var llmModelId: String { selectedLLMVariant.rawValue }

    /// Currently selected STT model variant, persisted across launches
    @Published var selectedSTTVariant: STTModelVariant {
        didSet { UserDefaults.standard.set(selectedSTTVariant.rawValue, forKey: "selectedSTTVariant") }
    }

    /// Computed model ID for the active STT variant
    var sttModelId: String { selectedSTTVariant.rawValue }

    // MARK: - Download State
    @Published var isLLMDownloading = false
    @Published var isSTTDownloading = false
    @Published var isTTSDownloading = false
    @Published var isVLMDownloading = false
    @Published var isDiffusionDownloading = false

    @Published var llmDownloadProgress: Double = 0.0
    @Published var sttDownloadProgress: Double = 0.0
    @Published var ttsDownloadProgress: Double = 0.0
    @Published var vlmDownloadProgress: Double = 0.0
    @Published var diffusionDownloadProgress: Double = 0.0

    // MARK: - Load State
    @Published var isLLMLoading = false
    @Published var isSTTLoading = false
    @Published var isTTSLoading = false
    @Published var isVLMLoading = false
    @Published var isDiffusionLoading = false

    // MARK: - Loaded State
    @Published private(set) var isLLMLoaded = false
    @Published private(set) var isSTTLoaded = false
    @Published private(set) var isTTSLoaded = false
    @Published private(set) var isVLMLoaded = false
    @Published private(set) var isDiffusionLoaded = false

    /// Status message for diffusion (loading can take minutes for CoreML compilation)
    @Published var diffusionStatusMessage = ""

    // MARK: - Computed Properties
    var isVoiceAgentReady: Bool {
        isLLMLoaded && isSTTLoaded && isTTSLoaded
    }

    var isAnyDownloading: Bool {
        isLLMDownloading || isSTTDownloading || isTTSDownloading || isVLMDownloading || isDiffusionDownloading
    }

    var isAnyLoading: Bool {
        isLLMLoading || isSTTLoading || isTTSLoading || isVLMLoading || isDiffusionLoading
    }

    // MARK: - Initialization
    init() {
        if let raw = UserDefaults.standard.string(forKey: "selectedLLMVariant"),
           let variant = LLMModelVariant(rawValue: raw) {
            self.selectedLLMVariant = variant
        } else {
            self.selectedLLMVariant = .qwen35_08b
        }

        if let raw = UserDefaults.standard.string(forKey: "selectedSTTVariant"),
           let variant = STTModelVariant(rawValue: raw) {
            self.selectedSTTVariant = variant
        } else {
            self.selectedSTTVariant = .whisperTiny
        }
        Task {
            await refreshLoadedStates()
        }
    }

    // MARK: - Model Registration
    /// Register default models with the SDK.
    ///
    /// Registration is `async throws` in the current SDK (commons owns id/name/
    /// format/artifact derivation), so each call is awaited and failures are
    /// logged per-model instead of aborting the whole catalog.
    static func registerDefaultModels() async {
        // Register all LLM model variants (LFM2 + Qwen 3 + Qwen 3.5)
        for variant in LLMModelVariant.allCases {
            do {
                _ = try await RunAnywhere.registerModel(
                    id: variant.rawValue,
                    name: variant.displayName,
                    url: variant.url.absoluteString,
                    framework: .llamaCpp,
                    memoryRequirement: variant.memoryRequirement
                )
            } catch {
                print("⚠️ Failed to register LLM \(variant.rawValue): \(error)")
            }
        }

        // Register all STT model variants (Whisper Tiny / Base / Small)
        for variant in STTModelVariant.allCases {
            do {
                _ = try await RunAnywhere.registerModel(
                    archive: variant.url.absoluteString,
                    structure: .nestedDirectory,
                    id: variant.rawValue,
                    name: variant.registrationName,
                    framework: .sherpa,
                    modality: .speechRecognition,
                    archiveType: .tarGz,
                    memoryRequirement: variant.memoryRequirement
                )
            } catch {
                print("⚠️ Failed to register STT \(variant.rawValue): \(error)")
            }
        }

        // Register TTS voice - Piper US English (natural sounding)
        do {
            _ = try await RunAnywhere.registerModel(
                archive: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
                structure: .nestedDirectory,
                id: ttsModelId,
                name: "Piper TTS (US English - Medium)",
                framework: .sherpa,
                modality: .speechSynthesis,
                archiveType: .tarGz,
                memoryRequirement: 65_000_000
            )
        } catch {
            print("⚠️ Failed to register TTS \(ttsModelId): \(error)")
        }

        // Register VLM model - SmolVLM 256M (tiny multimodal model, GGUF + mmproj)
        let vlmModelURL = URL(string: "https://huggingface.co/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/main/SmolVLM-256M-Instruct-Q8_0.gguf")!
        let vlmMmprojURL = URL(string: "https://huggingface.co/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-256M-Instruct-f16.gguf")!
        let vlmDescriptors: [RAModelFileDescriptor] = [
            makeDescriptor(url: vlmModelURL, filename: "SmolVLM-256M-Instruct-Q8_0.gguf", modality: .multimodal),
            makeDescriptor(url: vlmMmprojURL, filename: "mmproj-SmolVLM-256M-Instruct-f16.gguf", modality: .multimodal)
        ]
        do {
            _ = try await RunAnywhere.registerModel(
                multiFile: vlmDescriptors,
                id: vlmModelId,
                name: "SmolVLM 256M Instruct (Q8)",
                framework: .llamaCpp,
                modality: .multimodal,
                memoryRequirement: 365_000_000
            )
        } catch {
            print("⚠️ Failed to register VLM \(vlmModelId): \(error)")
        }

        // Register Diffusion model - Apple Stable Diffusion 1.5 CoreML (palettized,
        // split_einsum_v2 for ANE). Kept as a catalog entry; on-device image
        // generation is not exposed by the current SDK surface.
        do {
            _ = try await RunAnywhere.registerModel(
                archive: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled.zip",
                structure: .nestedDirectory,
                id: diffusionModelId,
                name: "Stable Diffusion 1.5 (CoreML)",
                framework: .coreml,
                modality: .imageGeneration,
                archiveType: .zip,
                memoryRequirement: 1_600_000_000
            )
        } catch {
            print("⚠️ Failed to register Diffusion \(diffusionModelId): \(error)")
        }

        print("✅ Models registered: LLM (\(LLMModelVariant.allCases.count) variants), STT (\(STTModelVariant.allCases.count) variants), TTS, VLM, Diffusion")
    }

    /// Build a multi-file descriptor with an inferred role, mirroring the
    /// canonical `ModelCatalogBootstrap` in the in-repo iOS example.
    private static func makeDescriptor(url: URL, filename: String, modality: ModelCategory) -> RAModelFileDescriptor {
        var descriptor = RAModelFileDescriptor(url: url, filename: filename, isRequired: true)
        descriptor.role = RunAnywhere.inferModelFileRole(filename: filename, modality: modality)
        return descriptor
    }

    // MARK: - State Refresh
    func refreshLoadedStates() async {
        isLLMLoaded = Self.isCategoryLoaded(.language)
        isSTTLoaded = Self.isCategoryLoaded(.speechRecognition)
        isTTSLoaded = Self.isCategoryLoaded(.speechSynthesis)
        isVLMLoaded = Self.isCategoryLoaded(.multimodal)
        isDiffusionLoaded = Self.isCategoryLoaded(.imageGeneration)
    }

    // MARK: - Lifecycle Helpers (unified proto-request API)

    /// Whether a model is currently loaded for a modality category.
    private static func isCategoryLoaded(_ category: RAModelCategory) -> Bool {
        var request = RACurrentModelRequest()
        request.category = category
        return RunAnywhere.currentModel(request).found
    }

    /// Load `modelId` under `category` via the unified lifecycle API.
    /// Returns whether the load succeeded.
    private func load(_ modelId: String, category: RAModelCategory) async -> Bool {
        var request = RAModelLoadRequest()
        request.modelID = modelId
        request.category = category
        return await RunAnywhere.loadModel(request).success
    }

    /// Unload whatever model is loaded under `category`.
    private func unload(category: RAModelCategory) async {
        var request = RAModelUnloadRequest()
        request.category = category
        _ = await RunAnywhere.unloadModel(request)
    }

    /// Download a registered model by id, forwarding progress to `onProgress`.
    /// The registry entry (URL, artifact layout, checksums) is resolved by the
    /// SDK from the id, so a stub `RAModelInfo` carrying only the id is enough.
    private func download(_ modelId: String, onProgress: @escaping (Double) -> Void) async throws {
        var stub = RAModelInfo()
        stub.id = modelId
        for try await progress in RunAnywhere.downloadModelStream(stub) {
            onProgress(Double(progress.overallProgress))
            if progress.stage == .completed {
                break
            }
        }
    }

    // MARK: - LLM Operations
    /// Download and load the currently selected LLM model variant
    func downloadAndLoadLLM() async {
        guard !isLLMDownloading && !isLLMLoading else { return }

        let modelId = llmModelId

        isLLMLoading = true
        if await load(modelId, category: .language) {
            isLLMLoaded = true
            isLLMLoading = false
            print("✅ LLM model loaded from cache (\(selectedLLMVariant.displayName))")
            return
        }
        isLLMLoading = false

        isLLMDownloading = true
        llmDownloadProgress = 0.0
        do {
            try await download(modelId) { [weak self] progress in
                self?.llmDownloadProgress = progress
            }
        } catch {
            print("LLM download error: \(error)")
            isLLMDownloading = false
            return
        }
        isLLMDownloading = false

        isLLMLoading = true
        if await load(modelId, category: .language) {
            isLLMLoaded = true
        } else {
            print("LLM load error after download")
        }
        isLLMLoading = false
    }

    /// Switch to a different LLM model variant, unloading the current one if needed
    func selectLLMVariant(_ variant: LLMModelVariant) async {
        guard variant != selectedLLMVariant else { return }

        if isLLMLoaded {
            await unload(category: .language)
            isLLMLoaded = false
        }

        selectedLLMVariant = variant
    }

    // MARK: - STT Operations
    /// Download and load the currently selected STT model variant
    func downloadAndLoadSTT() async {
        guard !isSTTDownloading && !isSTTLoading else { return }

        let modelId = sttModelId

        isSTTLoading = true
        if await load(modelId, category: .speechRecognition) {
            isSTTLoaded = true
            isSTTLoading = false
            print("✅ STT model loaded from cache (\(selectedSTTVariant.displayName))")
            return
        }
        isSTTLoading = false

        isSTTDownloading = true
        sttDownloadProgress = 0.0
        do {
            try await download(modelId) { [weak self] progress in
                self?.sttDownloadProgress = progress
            }
        } catch {
            print("STT download error: \(error)")
            isSTTDownloading = false
            return
        }
        isSTTDownloading = false

        isSTTLoading = true
        if await load(modelId, category: .speechRecognition) {
            isSTTLoaded = true
        } else {
            print("STT load error after download")
        }
        isSTTLoading = false
    }

    /// Switch to a different STT model variant, unloading the current one if needed
    func selectSTTVariant(_ variant: STTModelVariant) async {
        guard variant != selectedSTTVariant else { return }

        if isSTTLoaded {
            await unload(category: .speechRecognition)
            isSTTLoaded = false
        }

        selectedSTTVariant = variant
    }

    /// Unload the current STT model (returns to model selection)
    func unloadSTTModel() async {
        guard isSTTLoaded else { return }
        await unload(category: .speechRecognition)
        isSTTLoaded = false
    }

    // MARK: - TTS Operations
    /// Download and load TTS voice
    func downloadAndLoadTTS() async {
        guard !isTTSDownloading && !isTTSLoading else { return }

        isTTSLoading = true
        if await load(Self.ttsModelId, category: .speechSynthesis) {
            isTTSLoaded = true
            isTTSLoading = false
            print("✅ TTS voice loaded from cache")
            return
        }
        isTTSLoading = false

        isTTSDownloading = true
        ttsDownloadProgress = 0.0
        do {
            try await download(Self.ttsModelId) { [weak self] progress in
                self?.ttsDownloadProgress = progress
            }
        } catch {
            print("TTS download error: \(error)")
            isTTSDownloading = false
            return
        }
        isTTSDownloading = false

        isTTSLoading = true
        if await load(Self.ttsModelId, category: .speechSynthesis) {
            isTTSLoaded = true
        } else {
            print("TTS load error after download")
        }
        isTTSLoading = false
    }

    // MARK: - VLM Operations
    /// Download and load VLM model (SmolVLM 256M - multimodal)
    func downloadAndLoadVLM() async {
        guard !isVLMDownloading && !isVLMLoading else { return }

        isVLMLoading = true
        if await load(Self.vlmModelId, category: .multimodal) {
            isVLMLoaded = true
            isVLMLoading = false
            print("✅ VLM model loaded from cache")
            return
        }
        isVLMLoading = false

        isVLMDownloading = true
        vlmDownloadProgress = 0.0
        do {
            try await download(Self.vlmModelId) { [weak self] progress in
                self?.vlmDownloadProgress = progress
            }
        } catch {
            print("VLM download error: \(error)")
            isVLMDownloading = false
            return
        }
        isVLMDownloading = false

        isVLMLoading = true
        if await load(Self.vlmModelId, category: .multimodal) {
            isVLMLoaded = true
        } else {
            print("VLM load error after download")
        }
        isVLMLoading = false
    }

    // MARK: - Diffusion Operations
    /// Diffusion / on-device image generation is not exposed by the current
    /// RunAnywhere SDK surface. The model stays registered as a catalog entry,
    /// but there is no load/generate path, so surface a clear status instead.
    func downloadAndLoadDiffusion() async {
        diffusionStatusMessage = "Image generation is not available in this SDK version."
    }

    // MARK: - Batch Operations
    /// Download and load all models for voice agent
    /// Note: Downloads run sequentially to avoid SDK concurrency issues
    func downloadAndLoadAllModels() async {
        // Run sequentially to avoid race conditions in SDK's download service
        await downloadAndLoadLLM()
        await downloadAndLoadSTT()
        await downloadAndLoadTTS()
    }

    /// Unload all models
    func unloadAllModels() async {
        await unload(category: .language)
        await unload(category: .speechRecognition)
        await unload(category: .speechSynthesis)
        await refreshLoadedStates()
    }
}
