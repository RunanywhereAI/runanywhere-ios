//
//  ImageGenerationViewModel.swift
//  RunAnywhereAI
//
//  Text-to-image over `RunAnywhere.images`.
//
//  This view model is pure platform plumbing: it loads a catalog diffusion
//  model, streams `RunAnywhere.images.generateStream`, and paints the bytes the
//  SDK hands back. Scheduling, denoising, tokenization and model routing all
//  live in the SDK / C++ commons.
//
//  Unlike the other vision features this one is NOT `#if canImport(UIKit)`:
//  generation takes no image input, so nothing here needs UIImage or a picker
//  and the screen works identically on macOS.
//

import Foundation
import SwiftUI
import RunAnywhere
import CoreGraphics
import os.log

@MainActor
@Observable
final class ImageGenerationViewModel {
    // Model lifecycle
    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String?
    private(set) var isProcessing = false

    // Prompt inputs
    var prompt = ""
    var negativePrompt = ""
    var steps = 20
    var guidanceScale: Float = 7.5

    // Generation output
    private(set) var isGenerating = false
    private(set) var currentStep = 0
    private(set) var totalSteps = 0
    private(set) var image: CGImage?
    private(set) var seedUsed: Int64 = 0
    private(set) var generationTimeMs: Int64 = 0

    private(set) var statusMessage = ""
    private(set) var error: String?

    private var generationTask: Task<Void, Never>?

    /// Identifies the current generation. A cancelled task keeps running until it next
    /// suspends, so without this its `catch`/`defer` can set `isGenerating = false` and
    /// "Cancelled." AFTER a replacement has started — leaving the UI idle mid-generation.
    /// Bumping the id invalidates every state write from the task it replaces.
    private var generationID = 0

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "ImageGeneration")

    /// Denoising step bounds. The Apple CoreML engine implements DDIM only
    /// (`rac_diffusion_coreml.mm`), which is stable well below 20 steps but
    /// stops improving much past 50.
    static let stepRange = 4...50

    /// Classifier-free guidance bounds. Below ~1 the prompt stops steering the
    /// result; far above ~15 SD1.5 oversaturates. A generation constraint, so it
    /// lives here beside `stepRange` rather than inline in the view.
    static let guidanceRange: ClosedRange<Float> = 1...15
    static let guidanceStep: Float = 0.5

    var canGenerate: Bool {
        isModelLoaded && !isGenerating
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Fractional denoising progress, or nil before the first step arrives.
    var progressFraction: Double? {
        guard isGenerating, totalSteps > 0 else { return nil }
        return min(1.0, Double(currentStep) / Double(totalSteps))
    }

    // MARK: - Model status

    func refreshModelStatus() async {
        let state = await RunAnywhere.models.state()
        guard let model = state.loaded[.imageGeneration] else {
            isModelLoaded = false
            return
        }
        isModelLoaded = true
        loadedModelName = model.name.isEmpty ? model.id : model.name
    }

    // MARK: - Model supply (catalog Get → Use)

    /// Load a model chosen from `ModelSelectionSheet`.
    func loadModelFromSelection(_ model: RAModelInfo) async {
        isProcessing = true
        error = nil
        statusMessage = "Loading model…"
        defer { isProcessing = false }

        do {
            try await RunAnywhere.models.load(id: model.id)
        } catch {
            self.error = "Model load failed: \(error.localizedDescription)"
            statusMessage = ""
            return
        }
        loadedModelName = model.name.isEmpty ? model.id : model.name
        isModelLoaded = true
        statusMessage = "Model loaded: \(loadedModelName ?? model.id)."
    }

    // MARK: - Generation

    func generate() {
        guard isModelLoaded else { error = "Load an image model first."; return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = "Describe the image you want."; return }

        generationTask?.cancel()
        generationID &+= 1
        let id = generationID
        generationTask = Task { await runGeneration(prompt: trimmed, id: id) }
    }

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
        generationID &+= 1   // anything the cancelled task still writes is now stale
        statusMessage = "Cancelled."
        isGenerating = false
    }

    private func runGeneration(prompt trimmed: String, id: Int) async {
        isGenerating = true
        error = nil
        image = nil
        currentStep = 0
        totalSteps = steps
        statusMessage = "Generating…"
        defer {
            if id == generationID {
                isGenerating = false
            }
        }

        let negative = negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = ImageOptions(
            negativePrompt: negative.isEmpty ? nil : negative,
            steps: steps,
            guidanceScale: guidanceScale
        )

        do {
            let started = Date()
            let events = try await RunAnywhere.images.generateStream(prompt: trimmed, options: options)
            for try await event in events {
                if Task.isCancelled || id != generationID { break }
                handle(event, startedAt: started)
            }
        } catch is CancellationError {
            if id == generationID {
                statusMessage = "Cancelled."
            }
        } catch {
            logger.error("Image generation failed: \(error.localizedDescription)")
            guard id == generationID else { return }
            self.error = "Image generation failed: \(error.localizedDescription)"
            statusMessage = ""
        }
    }

    /// Apply one stream event. Only reached while this generation is still the current one.
    private func handle(_ event: ImageEvent, startedAt started: Date) {
        switch event {
        case .started:
            statusMessage = "Denoising…"
        case let .progress(step, total, _):
            currentStep = step
            // The backend is authoritative about how many steps it actually
            // runs; `steps` is only what we asked for.
            totalSteps = total > 0 ? total : totalSteps
        case let .completed(result):
            generationTimeMs = Int64((Date().timeIntervalSince(started) * 1000).rounded())
            seedUsed = result.seed
            apply(result)
        @unknown default:
            break
        }
    }

    private func apply(_ result: ImageResult) {
        guard let first = result.images.first else {
            error = "The model returned no image."
            statusMessage = ""
            return
        }
        guard let rendered = Self.cgImage(fromRGBA: first.data, width: first.width, height: first.height) else {
            error = "Could not decode the returned image (\(first.width)×\(first.height), \(first.data.count) bytes)."
            statusMessage = ""
            return
        }
        image = rendered
        currentStep = totalSteps
        statusMessage = "Done — \(first.width)×\(first.height) in \(generationTimeMs)ms, seed \(seedUsed)."
    }

    // MARK: - Rendering

    /// Build a CGImage from the SDK's image payload.
    ///
    /// Every shipped diffusion engine emits RAW RGBA8, not a PNG/JPEG
    /// container — `rac_diffusion_result_to_proto` stamps the media type
    /// `image/raw-rgba` for exactly this reason. `Image(data:)` and
    /// `UIImage(data:)` therefore both fail silently on this buffer; it has to
    /// go through CGDataProvider. `ImageData` does not currently carry the
    /// media type through to Swift, so this assumption is checked by size
    /// rather than declared.
    static func cgImage(fromRGBA data: Data, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, data.count == width * height * 4 else { return nil }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
