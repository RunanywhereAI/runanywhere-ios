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
    /// Register default models with the SDK
    static func registerDefaultModels() {
        // Register all LLM model variants (LFM2 + Qwen 3 + Qwen 3.5)
        for variant in LLMModelVariant.allCases {
            RunAnywhere.registerModel(
                id: variant.rawValue,
                name: variant.displayName,
                url: variant.url,
                framework: .llamaCpp,
                memoryRequirement: variant.memoryRequirement
            )
        }
        
        // Register all STT model variants (Whisper Tiny / Base / Small)
        for variant in STTModelVariant.allCases {
            RunAnywhere.registerModel(
                id: variant.rawValue,
                name: variant.registrationName,
                url: variant.url,
                framework: .onnx,
                modality: .speechRecognition,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: variant.memoryRequirement
            )
        }
        
        // Register TTS voice - Piper US English (natural sounding)
        if let piperURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz") {
            RunAnywhere.registerModel(
                id: ttsModelId,
                name: "Piper TTS (US English - Medium)",
                url: piperURL,
                framework: .onnx,
                modality: .speechSynthesis,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 65_000_000
            )
        }
        
        // Register VLM model - SmolVLM 256M (tiny multimodal model, GGUF + mmproj)
        let vlmModelURL = URL(string: "https://huggingface.co/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/main/SmolVLM-256M-Instruct-Q8_0.gguf")!
        let vlmMmprojURL = URL(string: "https://huggingface.co/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-256M-Instruct-f16.gguf")!
        
        RunAnywhere.registerMultiFileModel(
            id: vlmModelId,
            name: "SmolVLM 256M Instruct (Q8)",
            files: [
                ModelFileDescriptor(url: vlmModelURL, filename: "SmolVLM-256M-Instruct-Q8_0.gguf"),
                ModelFileDescriptor(url: vlmMmprojURL, filename: "mmproj-SmolVLM-256M-Instruct-f16.gguf"),
            ],
            framework: .llamaCpp,
            modality: .multimodal,
            memoryRequirement: 365_000_000
        )
        
        // Register Diffusion model - Apple Stable Diffusion 1.5 CoreML (palettized, split_einsum_v2 for ANE)
        if let sd15URL = URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled.zip") {
            RunAnywhere.registerModel(
                id: diffusionModelId,
                name: "Stable Diffusion 1.5 (CoreML)",
                url: sd15URL,
                framework: .coreml,
                modality: .imageGeneration,
                artifactType: .archive(.zip, structure: .nestedDirectory),
                memoryRequirement: 1_600_000_000
            )
        }
        
        print("✅ Models registered: LLM (\(LLMModelVariant.allCases.count) variants), STT (\(STTModelVariant.allCases.count) variants), TTS, VLM, Diffusion")
    }
    
    // MARK: - State Refresh
    func refreshLoadedStates() async {
        isLLMLoaded = await RunAnywhere.isModelLoaded
        isSTTLoaded = await RunAnywhere.isSTTModelLoaded
        isTTSLoaded = await RunAnywhere.isTTSVoiceLoaded
        isVLMLoaded = await RunAnywhere.isVLMModelLoaded
        isDiffusionLoaded = await RunAnywhere.isDiffusionModelLoaded
    }
    
    // MARK: - LLM Operations
    /// Download and load the currently selected LLM model variant
    func downloadAndLoadLLM() async {
        guard !isLLMDownloading && !isLLMLoading else { return }

        let modelId = llmModelId

        isLLMLoading = true
        do {
            try await RunAnywhere.loadModel(modelId)
            isLLMLoaded = true
            isLLMLoading = false
            print("✅ LLM model loaded from cache (\(selectedLLMVariant.displayName))")
            return
        } catch {
            print("LLM load attempt failed (will download): \(error)")
            isLLMLoading = false
        }

        isLLMDownloading = true
        llmDownloadProgress = 0.0

        do {
            let progressStream = try await RunAnywhere.downloadModel(modelId)
            for await progress in progressStream {
                llmDownloadProgress = progress.overallProgress
                if progress.stage == .completed {
                    break
                }
            }
        } catch {
            print("LLM download error: \(error)")
            isLLMDownloading = false
            return
        }

        isLLMDownloading = false
        isLLMLoading = true

        do {
            try await RunAnywhere.loadModel(modelId)
            isLLMLoaded = true
        } catch {
            print("LLM load error: \(error)")
        }

        isLLMLoading = false
    }

    /// Switch to a different LLM model variant, unloading the current one if needed
    func selectLLMVariant(_ variant: LLMModelVariant) async {
        guard variant != selectedLLMVariant else { return }

        if isLLMLoaded {
            do { try await RunAnywhere.unloadModel() } catch {
                print("LLM unload error during variant switch: \(error)")
            }
            isLLMLoaded = false
        }

        selectedLLMVariant = variant
    }
    
    // MARK: - STT Operations
    /// Download and load the currently selected STT model variant
    func downloadAndLoadSTT() async {
        guard !isSTTDownloading && !isSTTLoading else { return }

        let modelId = sttModelId

        // Try to load first if already downloaded
        isSTTLoading = true
        do {
            try await RunAnywhere.loadSTTModel(modelId)
            isSTTLoaded = true
            isSTTLoading = false
            print("✅ STT model loaded from cache (\(selectedSTTVariant.displayName))")
            return
        } catch {
            print("STT load attempt failed (will download): \(error)")
            isSTTLoading = false
        }

        // If loading failed, download the model
        isSTTDownloading = true
        sttDownloadProgress = 0.0

        do {
            let progressStream = try await RunAnywhere.downloadModel(modelId)
            for await progress in progressStream {
                sttDownloadProgress = progress.overallProgress
                if progress.stage == .completed {
                    break
                }
            }
        } catch {
            print("STT download error: \(error)")
            isSTTDownloading = false
            return
        }

        isSTTDownloading = false

        // Load the model after download
        isSTTLoading = true

        do {
            try await RunAnywhere.loadSTTModel(modelId)
            isSTTLoaded = true
        } catch {
            print("STT load error: \(error)")
        }

        isSTTLoading = false
    }

    /// Switch to a different STT model variant, unloading the current one if needed
    func selectSTTVariant(_ variant: STTModelVariant) async {
        guard variant != selectedSTTVariant else { return }

        if isSTTLoaded {
            do { try await RunAnywhere.unloadSTTModel() } catch {
                print("STT unload error during variant switch: \(error)")
            }
            isSTTLoaded = false
        }

        selectedSTTVariant = variant
    }

    /// Unload the current STT model (returns to model selection)
    func unloadSTTModel() async {
        guard isSTTLoaded else { return }
        do { try await RunAnywhere.unloadSTTModel() } catch {
            print("STT unload error: \(error)")
        }
        isSTTLoaded = false
    }
    
    // MARK: - TTS Operations
    /// Download and load TTS voice
    func downloadAndLoadTTS() async {
        guard !isTTSDownloading && !isTTSLoading else { return }
        
        // Try to load first if already downloaded
        isTTSLoading = true
        do {
            try await RunAnywhere.loadTTSVoice(Self.ttsModelId)
            isTTSLoaded = true
            isTTSLoading = false
            print("✅ TTS voice loaded from cache")
            return
        } catch {
            print("TTS load attempt failed (will download): \(error)")
            isTTSLoading = false
        }
        
        // If loading failed, download the model
        isTTSDownloading = true
        ttsDownloadProgress = 0.0
        
        do {
            let progressStream = try await RunAnywhere.downloadModel(Self.ttsModelId)
            for await progress in progressStream {
                ttsDownloadProgress = progress.overallProgress
                if progress.stage == .completed {
                    break
                }
            }
        } catch {
            print("TTS download error: \(error)")
            isTTSDownloading = false
            return
        }
        
        isTTSDownloading = false
        
        // Load the voice after download
        isTTSLoading = true
        
        do {
            try await RunAnywhere.loadTTSVoice(Self.ttsModelId)
            isTTSLoaded = true
        } catch {
            print("TTS load error: \(error)")
        }
        
        isTTSLoading = false
    }
    
    // MARK: - VLM Operations
    /// Download and load VLM model (SmolVLM 256M - multimodal)
    func downloadAndLoadVLM() async {
        guard !isVLMDownloading && !isVLMLoading else { return }
        
        // Try to load first if already downloaded
        isVLMLoading = true
        do {
            let models = try await RunAnywhere.availableModels()
            if let vlmModel = models.first(where: { $0.id == Self.vlmModelId && $0.isDownloaded }) {
                try await RunAnywhere.loadVLMModel(vlmModel)
                isVLMLoaded = true
                isVLMLoading = false
                print("✅ VLM model loaded from cache")
                return
            }
        } catch {
            print("VLM load attempt failed (will download): \(error)")
        }
        isVLMLoading = false
        
        // Download the model
        isVLMDownloading = true
        vlmDownloadProgress = 0.0
        
        do {
            let progressStream = try await RunAnywhere.downloadModel(Self.vlmModelId)
            for await progress in progressStream {
                vlmDownloadProgress = progress.overallProgress
                if progress.stage == .completed {
                    break
                }
            }
        } catch {
            print("VLM download error: \(error)")
            isVLMDownloading = false
            return
        }
        
        isVLMDownloading = false
        
        // Load the model after download
        isVLMLoading = true
        
        do {
            let models = try await RunAnywhere.availableModels()
            if let vlmModel = models.first(where: { $0.id == Self.vlmModelId }) {
                try await RunAnywhere.loadVLMModel(vlmModel)
                isVLMLoaded = true
            } else {
                print("VLM model not found in registry after download")
            }
        } catch {
            print("VLM load error: \(error)")
        }
        
        isVLMLoading = false
    }
    
    // MARK: - Diffusion Operations
    /// Download and load Diffusion model (Stable Diffusion 1.5 CoreML)
    /// Note: First-time CoreML compilation can take 5-15 minutes
    func downloadAndLoadDiffusion() async {
        guard !isDiffusionDownloading && !isDiffusionLoading else { return }
        
        // Try to load first if already downloaded
        isDiffusionLoading = true
        diffusionStatusMessage = "Checking for cached model..."
        do {
            let models = try await RunAnywhere.availableModels()
            if let model = models.first(where: { $0.id == Self.diffusionModelId && $0.isDownloaded }),
               let path = model.localPath {
                diffusionStatusMessage = "Loading CoreML pipeline (first time may take 5-15 min)..."
                let config = DiffusionConfiguration(
                    modelVariant: .sd15,
                    enableSafetyChecker: true,
                    reduceMemory: true
                )
                try await RunAnywhere.loadDiffusionModel(
                    modelPath: path.path,
                    modelId: model.id,
                    modelName: model.name,
                    configuration: config
                )
                isDiffusionLoaded = true
                isDiffusionLoading = false
                diffusionStatusMessage = "Model loaded"
                print("✅ Diffusion model loaded from cache")
                return
            }
        } catch {
            print("Diffusion load attempt failed (will download): \(error)")
        }
        isDiffusionLoading = false
        
        // Download the model
        isDiffusionDownloading = true
        diffusionDownloadProgress = 0.0
        diffusionStatusMessage = "Downloading (~1.6 GB)..."
        
        do {
            let progressStream = try await RunAnywhere.downloadModel(Self.diffusionModelId)
            for await progress in progressStream {
                diffusionDownloadProgress = progress.overallProgress
                if progress.stage == .completed {
                    break
                }
            }
        } catch {
            print("Diffusion download error: \(error)")
            diffusionStatusMessage = "Download failed"
            isDiffusionDownloading = false
            return
        }
        
        isDiffusionDownloading = false
        
        // Load the model after download
        isDiffusionLoading = true
        diffusionStatusMessage = "Loading CoreML pipeline (first time may take 5-15 min)..."
        
        do {
            let models = try await RunAnywhere.availableModels()
            if let model = models.first(where: { $0.id == Self.diffusionModelId }),
               let path = model.localPath {
                let config = DiffusionConfiguration(
                    modelVariant: .sd15,
                    enableSafetyChecker: true,
                    reduceMemory: true
                )
                try await RunAnywhere.loadDiffusionModel(
                    modelPath: path.path,
                    modelId: model.id,
                    modelName: model.name,
                    configuration: config
                )
                isDiffusionLoaded = true
                diffusionStatusMessage = "Model loaded"
            } else {
                print("Diffusion model not found in registry after download")
                diffusionStatusMessage = "Model not found after download"
            }
        } catch {
            print("Diffusion load error: \(error)")
            diffusionStatusMessage = "Load failed: \(error.localizedDescription)"
        }
        
        isDiffusionLoading = false
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
        do {
            try await RunAnywhere.unloadModel()
        } catch {
            print("LLM unload error: \(error)")
        }
        
        do {
            try await RunAnywhere.unloadSTTModel()
        } catch {
            print("STT unload error: \(error)")
        }
        
        do {
            try await RunAnywhere.unloadTTSVoice()
        } catch {
            print("TTS unload error: \(error)")
        }
        
        await refreshLoadedStates()
    }
}
