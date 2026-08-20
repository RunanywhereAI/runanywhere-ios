//
//  ModelRecommendationEngineTests.swift
//  RunAnywhereAIUnitTests
//
//  The engine picks by hardcoded id, and the catalog it picks from is edited in
//  a different PR by someone not reading that file. These lock the one property
//  that makes the coupling survivable: a curated list that has gone stale
//  degrades to a worse recommendation, never to no recommendation.
//
//  Deliberately no assertion that any particular id is present. A test that
//  names ids is a second copy of the list, and it would fail on the catalog
//  change it is supposed to tolerate.
//

import XCTest
@testable import RunAnywhereAI
import RunAnywhere

final class ModelRecommendationEngineTests: XCTestCase {

    private let engine = ModelRecommendationEngine()

    /// The 0.20.24 regression, as a test. Every curated id is absent, exactly as
    /// it was after the catalog rebuild dropped the superseded families, and the
    /// screen still has something to recommend.
    func testRecommendsLanguageModelsWhenNoCuratedIDMatches() {
        let catalog = [
            makeModel(id: "totally-unrelated-3b", name: "Unrelated 3B", bytes: 2_000_000_000),
            makeModel(id: "totally-unrelated-1b", name: "Unrelated 1B", bytes: 900_000_000),
            makeModel(id: "totally-unrelated-8b", name: "Unrelated 8B", bytes: 5_000_000_000)
        ]

        let selection = engine.recommend(
            tier: .unknown,
            appleFoundationAvailable: false,
            from: catalog
        )

        XCTAssertEqual(selection.recommendedLLMs.count, 3)
        XCTAssertNotNil(selection.defaultChatModel)
    }

    /// Back-fill opens with the cheapest option rather than the largest file in
    /// the category, so a fallback stays runnable on the device that triggered it.
    func testBackfillIsOrderedSmallestFirst() {
        let catalog = [
            makeModel(id: "big", name: "Big 8B", bytes: 5_000_000_000),
            makeModel(id: "small", name: "Small 1B", bytes: 900_000_000),
            makeModel(id: "medium", name: "Medium 3B", bytes: 2_000_000_000)
        ]

        let selection = engine.recommend(
            tier: .unknown,
            appleFoundationAvailable: false,
            from: catalog
        )

        XCTAssertEqual(selection.recommendedLLMs.map(\.id), ["small", "medium", "big"])
    }

    /// A model commons has ruled out is never recommended, even when nothing
    /// else is left to offer. Absent verdicts stay permissive.
    func testCanRunVerdictExcludesAndMissingVerdictAllows() {
        let catalog = [
            makeModel(id: "too-big", name: "Too Big 30B", bytes: 20_000_000_000),
            makeModel(id: "fits", name: "Fits 1B", bytes: 900_000_000)
        ]

        let selection = engine.recommend(
            tier: .unknown,
            appleFoundationAvailable: false,
            from: catalog,
            canRunByModelID: ["too-big": false]
        )

        XCTAssertEqual(selection.recommendedLLMs.map(\.id), ["fits"])
    }

    /// An empty catalog is the one case where recommending nothing is correct.
    func testEmptyCatalogRecommendsNothing() {
        let selection = engine.recommend(
            tier: .unknown,
            appleFoundationAvailable: false,
            from: []
        )

        XCTAssertTrue(selection.recommendedLLMs.isEmpty)
        XCTAssertNil(selection.defaultChatModel)
    }

    /// Companions fall back by category too, so a stale ASR id does not leave
    /// the Voice screen with no speech model.
    func testCompanionsFallBackByCategory() {
        let catalog = [
            makeModel(id: "some-llm", name: "Some 1B", bytes: 900_000_000),
            makeModel(id: "unknown-asr", name: "Unknown ASR", category: .speechRecognition, bytes: 80_000_000),
            makeModel(id: "unknown-tts", name: "Unknown TTS", category: .speechSynthesis, bytes: 60_000_000)
        ]

        let selection = engine.recommend(
            tier: .unknown,
            appleFoundationAvailable: false,
            from: catalog
        )

        XCTAssertEqual(selection.recommendedASR?.id, "unknown-asr")
        XCTAssertEqual(selection.recommendedTTS?.id, "unknown-tts")
    }

    /// The voice pipeline shares the same picking, so it inherits the same floor.
    func testVoicePipelineResolvesFromAnUnfamiliarCatalog() {
        let catalog = [
            makeModel(id: "some-llm", name: "Some 1B", bytes: 900_000_000),
            makeModel(id: "unknown-asr", name: "Unknown ASR", category: .speechRecognition, bytes: 80_000_000),
            makeModel(id: "unknown-tts", name: "Unknown TTS", category: .speechSynthesis, bytes: 60_000_000)
        ]

        let pipeline = engine.recommendVoicePipeline(
            tier: .unknown,
            appleFoundationAvailable: false,
            from: catalog
        )

        XCTAssertTrue(pipeline.isComplete)
    }

    private func makeModel(
        id: String,
        name: String,
        category: RAModelCategory = .language,
        bytes: Int64
    ) -> RAModelInfo {
        var model = RAModelInfo()
        model.id = id
        model.name = name
        model.category = category
        model.framework = .llamaCpp
        model.downloadSizeBytes = bytes
        return model
    }
}
