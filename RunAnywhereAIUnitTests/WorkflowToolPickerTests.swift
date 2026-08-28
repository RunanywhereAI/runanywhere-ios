//
//  WorkflowToolPickerTests.swift
//  RunAnywhereAITests
//
//  The Tool Call node's picker reads two registries: this app's, and commons'
//  own providers. Reading only the first is what made `web_research` — the one
//  tool a research workflow is built on — impossible to select.
//

import RunAnywhere
import SwiftUI
import XCTest
@testable import RunAnywhereAI

final class WorkflowToolPickerTests: XCTestCase {
    @MainActor
    func testTheToolPickerListsCommonsProvidersAlongsideOurOwn() async throws {
        try RunAnywhere.initialize(environment: .development)
        await AppTools.registerAll()

        let hostNames = await Set(RunAnywhere.llm.tools.list().map(\.name))
        // The premise: a provider is dispatchable without ever being listed by
        // the SDK's own registry. If this stops holding, the merge is moot.
        XCTAssertFalse(hostNames.contains("web_research"))
        XCTAssertTrue(hostNames.contains("calculate"))

        let viewModel = WorkflowEditorViewModel()
        await viewModel.refreshCatalogs()

        let offered = viewModel.availableTools.map(\.name)
        XCTAssertTrue(offered.contains("web_research"))
        XCTAssertTrue(offered.contains("calculate"))
        XCTAssertEqual(offered, offered.sorted())
        XCTAssertEqual(Set(offered).count, offered.count, "a tool in both registries was listed twice")
    }

    @MainActor
    func testPickingWebResearchGivesTheNodeItsQuestionSocket() async throws {
        try RunAnywhere.initialize(environment: .development)
        await AppTools.registerAll()

        let viewModel = WorkflowEditorViewModel()
        await viewModel.refreshCatalogs()

        let node = try XCTUnwrap(viewModel.addNode(.toolCall, at: CGPoint(x: 400, y: 200)))
        viewModel.selectTool(named: "web_research", for: node.id)

        let placed = try XCTUnwrap(viewModel.graph.node(node.id))
        XCTAssertEqual(placed.settings.toolName, "web_research")
        // One socket per declared argument, read from the provider's own JSON
        // schema rather than from anything hardcoded here.
        XCTAssertEqual(placed.settings.toolPorts.map(\.name), ["question"])
        XCTAssertEqual(placed.inputPorts.map(\.name), ["in", "question"])
    }
}
