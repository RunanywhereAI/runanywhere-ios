//
//  FirstGenerationTests.swift
//  RunAnywhereAITests
//
//  What the very first generation after a load actually returns.
//

import RunAnywhere
import XCTest
@testable import RunAnywhereAI

/// Whether a freshly loaded model answers its first question.
///
/// Written to settle one observation: a workflow that summarised a document
/// wrote an empty file when its test ran first in the process, and 545
/// characters when the same template ran later. The template did not change
/// between those two runs, and neither did the engine — only what had happened
/// before them. That points at the load, not the workflow.
final class FirstGenerationTests: XCTestCase {

    @MainActor
    func testTheFirstGenerationAfterALoadIsNotEmpty() async throws {
        try RunAnywhere.initialize(environment: .development)
        await ModelCatalogBootstrap.registerAll(mlxRegistered: true)
        _ = try? await RunAnywhere.models.refresh()

        let catalog = (try? await RunAnywhere.models.list()) ?? []
        let ceiling = min(Int64(ProcessInfo.processInfo.physicalMemory / 6), 8_000_000_000)
        let candidates = catalog.filter {
            ModelPurpose.of($0) == .language && !$0.localPath.isEmpty
                && $0.isAvailableForUse && $0.consumerSizeBytes < ceiling
        }
        guard let model = candidates.max(by: { $0.consumerSizeBytes < $1.consumerSizeBytes }) else {
            throw XCTSkip("No language model is installed on this machine.")
        }

        _ = try await RunAnywhere.models.load(id: model.id)

        // The same question twice: once as any caller would ask it, and once
        // with tools explicitly declined. `generate` folds every globally
        // registered tool into a request that asked for none, so these were not
        // the same call — one threw while the other answered. They must agree.
        let asAsked = try await RunAnywhere.llm.generate(
            prompt: "Reply with exactly one word: ready"
        ).text.trimmingCharacters(in: .whitespacesAndNewlines)

        var declined = LlmOptions()
        declined.toolChoice = .none
        let withoutTools = try await RunAnywhere.llm.generate(
            prompt: "Reply with exactly one word: ready",
            options: declined
        ).text.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertFalse(
            asAsked.isEmpty,
            "a plain generate answered nothing while declining tools answered "
                + "\(withoutTools.count) characters, on \(model.id)"
        )
        XCTAssertFalse(withoutTools.isEmpty, "declining tools answered nothing on \(model.id)")
    }
}
