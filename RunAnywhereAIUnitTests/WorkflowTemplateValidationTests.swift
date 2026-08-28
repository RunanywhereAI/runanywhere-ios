//
//  WorkflowTemplateValidationTests.swift
//  RunAnywhereAITests
//
//  A template that does not validate cannot be saved, so "New Workflow" would
//  offer a document the editor immediately flags. Commons owns the rules, so
//  the check is a real `workflows.validate` call rather than a restatement of
//  them here.
//

import RunAnywhere
import XCTest
@testable import RunAnywhereAI

final class WorkflowTemplateValidationTests: XCTestCase {
    @MainActor
    func testEveryTemplateValidates() async throws {
        try RunAnywhere.initialize(environment: .development)

        for template in WorkflowTemplateLibrary.templates {
            let result = try await RunAnywhere.workflows.validate(document(for: template))
            let messages = result.issues.map(\.message).joined(separator: " | ")

            // One template deliberately ships its question blank rather than as
            // placeholder prose, which a run would otherwise research verbatim.
            // It is the single allowed exception, and only for that one reason:
            // anything else it reported would still be a broken template.
            if templatesAwaitingUserInput.contains(template.name) {
                XCTAssertFalse(result.valid, "\(template.name) no longer asks for its input")
                XCTAssertTrue(
                    result.issues.allSatisfy { $0.message.contains("no configured value") },
                    "\(template.name) reports more than the input it is waiting for: \(messages)"
                )
                continue
            }

            XCTAssertTrue(result.valid, "\(template.name): \(messages)")
        }
    }

    /// Templates that cannot be saved until the user fills something in. Kept
    /// as a named list so adding one is a decision someone makes on purpose.
    private let templatesAwaitingUserInput: Set<String> = ["Research a question and file it"]

    /// Filling the question in is all it takes — the rest of that template has
    /// to be sound, or the exception above would be hiding a real break.
    @MainActor
    func testTheAwaitingTemplateValidatesOnceItsQuestionIsFilledIn() async throws {
        try RunAnywhere.initialize(environment: .development)

        let template = try XCTUnwrap(
            WorkflowTemplateLibrary.templates.first { templatesAwaitingUserInput.contains($0.name) }
        )
        var graph = template.graph()
        let index = try XCTUnwrap(graph.nodes.firstIndex { $0.kind == .toolCall })
        graph.nodes[index].settings.setToolArgument("question", to: "why is the sky blue")

        let result = try await RunAnywhere.workflows.validate(
            WorkflowDocumentMapping.document(
                id: "filled-in",
                name: template.name,
                graph: graph,
                createdAtMs: 0
            )
        )
        XCTAssertTrue(result.valid, result.issues.map(\.message).joined(separator: " | "))
    }

    /// Guards the test above against passing because nothing was checked: a
    /// second trigger is the one rule every template is closest to breaking.
    @MainActor
    func testValidatorRejectsASecondTrigger() async throws {
        try RunAnywhere.initialize(environment: .development)

        let template = try XCTUnwrap(WorkflowTemplateLibrary.templates.first)
        var graph = template.graph()
        graph.nodes.append(
            WorkflowNode(id: "second-trigger", kind: .manualTrigger, name: "Also Start", position: .zero)
        )

        let result = try await RunAnywhere.workflows.validate(
            WorkflowDocumentMapping.document(
                id: "two-triggers",
                name: "Two triggers",
                graph: graph,
                createdAtMs: 0
            )
        )
        XCTAssertFalse(result.valid)
    }

    @MainActor
    private func document(for template: WorkflowTemplate) -> RAWorkflowDocument {
        WorkflowDocumentMapping.document(
            id: "template-\(template.id)",
            name: template.name,
            graph: template.graph(),
            createdAtMs: 0
        )
    }
}
