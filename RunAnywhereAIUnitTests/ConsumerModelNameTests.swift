//
//  ConsumerModelNameTests.swift
//  RunAnywhereAITests
//
//  The derivation runs over the whole catalog, not a handful of examples, and
//  the catalog is edited on its own schedule by people not reading the rules.
//  These are the cases where a naive strip gets it wrong.
//

import RunAnywhere
import XCTest
@testable import RunAnywhereAI

final class ConsumerModelNameTests: XCTestCase {
    /// The examples below are chosen; this is the whole catalog. A row added in
    /// a catalog PR by someone who never opened this file still has to come out
    /// the other side with a name, without a quantisation string in it, and
    /// distinguishable from every other row.
    func testEveryCatalogRowGetsACleanUniqueName() async throws {
        try RunAnywhere.initialize(environment: .development)
        await ModelCatalogBootstrap.registerAll(mlxRegistered: true)
        let catalog = try await RunAnywhere.models.list()
        XCTAssertFalse(catalog.isEmpty, "nothing registered, so nothing was checked")

        let names = ConsumerModelName.uniqueNames(for: catalog)
        XCTAssertEqual(names.count, catalog.count)

        for model in catalog {
            let name = try XCTUnwrap(names[model.id])
            XCTAssertFalse(name.trimmingCharacters(in: .whitespaces).isEmpty, model.id)
            for banned in ["Q4_K", "Q8_0", "Q1_0", "4bit", "8bit", "INT8", "MLX ", "GGUF"] {
                XCTAssertFalse(
                    name.localizedCaseInsensitiveContains(banned),
                    "\(model.id) still reads as \(name)"
                )
            }
        }

        XCTAssertEqual(Set(names.values).count, catalog.count, "two rows share one name")
    }

    private func name(_ raw: String, _ publisher: ModelOrg) -> String {
        ConsumerModelName.derive(rawName: raw, publisher: publisher)
    }

    func testQuantizationAndRuntimePrefixesGo() {
        XCTAssertEqual(name("MLX Qwen3.5 0.8B 4bit", .alibaba), "Alibaba Qwen3.5 0.8B")
        XCTAssertEqual(name("Qwen3.5 2B Q4_K_M", .alibaba), "Alibaba Qwen3.5 2B")
        XCTAssertEqual(name("LiquidAI LFM2.5 350M Q4_K_M", .liquid), "Liquid AI LFM2.5 350M")
        XCTAssertEqual(name("Gemma 4 26B-A4B IT Q4_K_XL", .google), "Google Gemma 4 26B")
        XCTAssertEqual(name("Maple Preview 20B-A1B TQ1_0 (1-bit)", .deepgrove), "Deepgrove Maple Preview 20B")
    }

    /// A family whose name starts with the letter the quant tokens start with.
    /// Stripping on a "starts with q" rule erases the model.
    func testAFamilyNameIsNotMistakenForAQuantToken() {
        XCTAssertEqual(name("Qwen3-VL 4B Instruct 4bit", .alibaba), "Alibaba Qwen3-VL 4B")
        XCTAssertEqual(name("MLX Qwen3-ASR 0.6B 8bit", .alibaba), "Alibaba Qwen3-ASR 0.6B")
    }

    func testTechnicalParentheticalsGoAndMeaningfulOnesStay() {
        XCTAssertEqual(name("Sherpa Whisper Tiny (ONNX)", .openAI), "OpenAI Whisper Tiny")
        XCTAssertEqual(name("LFM2.5 2.6B (NeuRT / Neural Engine)", .liquid), "Liquid AI LFM2.5 2.6B")
        XCTAssertEqual(name("MLX Parakeet CTC 1.1B (NVIDIA)", .nvidia), "NVIDIA Parakeet CTC 1.1B")
        XCTAssertEqual(name("Gemma 4 E2B IT Q8_0 (Experimental)", .google), "Google Gemma 4 E2B (Experimental)")
        XCTAssertEqual(
            name("NVIDIA Nemotron 3 Nano Omni 30B-A3B Reasoning Q4_K_M (Image+Text)", .nvidia),
            "NVIDIA Nemotron 3 Nano Omni 30B Reasoning (Image+Text)"
        )
        XCTAssertEqual(
            name("Piper TTS (US English - Medium)", .openSource),
            "Piper TTS (US English - Medium)"
        )
    }

    func testAFamilyRunTogetherWithItsSizeIsSplitButAFamilySuffixIsNot() {
        XCTAssertEqual(name("Bonsai-1.7B 1-bit Q1_0 (CPU)", .prism), "Prism Bonsai 1.7B")
        XCTAssertEqual(name("MLX LFM2.5-VL 3B 4bit", .liquid), "Liquid AI LFM2.5-VL 3B")
        XCTAssertEqual(name("MLX GLM-ASR Nano 2512 4bit", .zhipu), "Zhipu AI GLM-ASR Nano 2512")
    }

    func testThePublisherIsNeverSaidTwiceAndOpenSourceIsNeverSaidAtAll() {
        XCTAssertEqual(name("IBM Granite 4.1 3B Q4_K_M", .ibm), "IBM Granite 4.1 3B")
        XCTAssertEqual(name("Meta Muse Glimmer 30B Q4_K_XL", .meta), "Meta Muse Glimmer 30B")
        XCTAssertEqual(name("Silero VAD", .openSource), "Silero VAD")
        XCTAssertEqual(name("All MiniLM L6 v2 (Embedding)", .openSource), "All MiniLM L6 v2")
        XCTAssertEqual(name("MLX Kokoro 82M 6bit", .openSource), "Kokoro 82M")
    }

    /// Nothing in the rules may produce an empty label, whatever the catalog
    /// hands over.
    func testANameMadeEntirelyOfStrippedTokensFallsBackToTheCatalogName() {
        XCTAssertEqual(name("Q4_K_M", .openSource), "Q4_K_M")
        XCTAssertEqual(name("MLX 4bit", .openSource), "MLX 4bit")
    }
}
