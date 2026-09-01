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

    func testCatalogContextsDoNotSupportFolderImport() {
        XCTAssertFalse(ModelSelectionContext.llm.supportsFolderImport)
        XCTAssertFalse(ModelSelectionContext.stt.supportsFolderImport)
        XCTAssertFalse(ModelSelectionContext.diarization.supportsFolderImport)
        XCTAssertFalse(ModelSelectionContext.segmentation.supportsFolderImport)
    }
}
