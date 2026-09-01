//
//  ModelSelectionContextTests.swift
//  RunAnywhereAIUnitTests
//

import XCTest
@testable import RunAnywhereAI

final class ModelSelectionContextTests: XCTestCase {
    func testRAGEmbeddingAllowsPortableLlamaCppModels() throws {
        let frameworks = try XCTUnwrap(ModelSelectionContext.ragEmbedding.allowedFrameworks)

        // `.coreml` is NeuRT, the Apple Neural Engine. Its absence was a SILENT filter: a CoreML
        // row passed the `relevantCategories` check and was then dropped from the picker with no
        // error and no log, so the model downloaded, loaded and ran while nothing could offer it.
        // SDK 0.20.32 fills NeuRT's embedding slot, so the framework now has something to drive.
        XCTAssertEqual(frameworks, [.llamaCpp, .onnx, .mlx, .coreml])
    }

    func testDiarizationContextFiltersSpeakerDiarization() {
        XCTAssertEqual(ModelSelectionContext.diarization.title, "Choose Diarization Model")
        XCTAssertEqual(ModelSelectionContext.diarization.relevantCategories, [.speakerDiarization])
        XCTAssertFalse(ModelSelectionContext.diarization.supportsFolderImport)
        XCTAssertNil(ModelSelectionContext.diarization.allowedFrameworks)
    }

    func testSegmentationContextFiltersSemanticSegmentation() {
        XCTAssertEqual(ModelSelectionContext.segmentation.title, "Choose Segmentation Model")
        XCTAssertEqual(ModelSelectionContext.segmentation.relevantCategories, [.semanticSegmentation])
        XCTAssertFalse(ModelSelectionContext.segmentation.supportsFolderImport)
        XCTAssertNil(ModelSelectionContext.segmentation.allowedFrameworks)
    }

    func testImageGenerationContextFiltersImageGeneration() {
        XCTAssertEqual(ModelSelectionContext.imageGeneration.title, "Choose Image Model")
        XCTAssertEqual(ModelSelectionContext.imageGeneration.relevantCategories, [.imageGeneration])
        XCTAssertFalse(ModelSelectionContext.imageGeneration.supportsFolderImport)
        // nil, not [.coreml]: the CoreML diffusion engine is the only backend
        // that serves this category today, so an explicit allow-list would only
        // be a second place to forget when a second one lands.
        XCTAssertNil(ModelSelectionContext.imageGeneration.allowedFrameworks)
    }

    /// Raw RGBA in, CGImage out -- the decode path the diffusion result takes.
    /// `Image(data:)` cannot read this buffer, so a regression here is a blank
    /// result card rather than a crash.
    @MainActor
    func testRawRGBADecodesToCGImageAndRejectsShortBuffers() {
        let width = 4, height = 3
        let pixels = Data(repeating: 0x7F, count: width * height * 4)
        let image = ImageGenerationViewModel.cgImage(fromRGBA: pixels, width: width, height: height)
        XCTAssertEqual(image?.width, width)
        XCTAssertEqual(image?.height, height)

        let truncated = Data(repeating: 0x7F, count: width * height * 4 - 1)
        XCTAssertNil(ImageGenerationViewModel.cgImage(fromRGBA: truncated, width: width, height: height))
        XCTAssertNil(ImageGenerationViewModel.cgImage(fromRGBA: pixels, width: 0, height: height))
    }

    func testCatalogContextsDoNotSupportFolderImport() {
        XCTAssertFalse(ModelSelectionContext.llm.supportsFolderImport)
        XCTAssertFalse(ModelSelectionContext.stt.supportsFolderImport)
        XCTAssertFalse(ModelSelectionContext.diarization.supportsFolderImport)
        XCTAssertFalse(ModelSelectionContext.segmentation.supportsFolderImport)
    }
}
