//
//  WorkflowTemplateExecutionTests.swift
//  RunAnywhereAITests
//
//  Every shipped template, actually run, against real models and real files.
//

import RunAnywhere
import XCTest
@testable import RunAnywhereAI

/// Runs the templates rather than inspecting them.
///
/// `WorkflowTemplateValidationTests` proves a template is well-formed, which is
/// a different claim from "it works": a template can validate perfectly and
/// still reference a prompt variable no node produces, or write to a path that
/// does not exist, and nobody finds out until someone builds it in the UI and
/// watches it fail. So these run each one end to end and read the record.
///
/// Two things are deliberately real. The models are the ones on this machine —
/// nothing is stubbed, so a template that asks more of a model than it can give
/// fails here. And the files are real files, written into a temporary directory
/// and read back afterwards, so a template that claims to save a summary has to
/// have actually saved one.
final class WorkflowTemplateExecutionTests: XCTestCase {

    /// Where the templates' file paths are pointed for the duration of a test.
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    // MARK: - The suite

    /// Every template that can run without someone sitting in front of it.
    ///
    /// The exclusions are capabilities, not failures, and each one is named so
    /// that adding to this list is a decision rather than a way of making the
    /// suite pass.
    @MainActor
    func testEveryRunnableTemplateSucceeds() async throws {
        note("start")
        try await bootSDK()
        note("sdk booted")
        guard let model = try await loadLanguageModel() else {
            throw XCTSkip("No language model is installed on this machine.")
        }
        note("model \(model)")

        var ran = 0
        var failures: [String] = []

        for template in WorkflowTemplateLibrary.templates {
            guard let plan = Fixture.plan(for: template.name) else { continue }
            note("running \(template.name)")
            do {
                let (record, files) = try await run(template, plan: plan, model: model)
                try assertSucceeded(record, template: template, plan: plan, expectedFiles: files)
                ran += 1
            } catch {
                failures.append("\(template.name): \(error)")
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            (failures + ["--- trace ---"] + trace).joined(separator: "\n")
        )
        XCTAssertGreaterThan(ran, 0, "No template ran, so this suite proved nothing.")
    }

    /// Collected rather than printed: test output written to stderr does not
    /// reach `xcodebuild`, so anything worth reading has to travel in the
    /// failure message.
    private var trace: [String] = []

    private func note(_ text: String) {
        trace.append(text)
    }

    // MARK: - Running one

    @MainActor
    private func run(
        _ template: WorkflowTemplate, plan: Fixture, model: String
    ) async throws -> (RAWorkflowRunRecord, [String]) {
        var graph = template.graph()
        let expectedFiles = try rewrite(&graph, with: plan, model: model)

        // Ids become path components, so the store refuses anything with a
        // space in it. Template ids are display names, hence the slug.
        let id = "test-" + template.name.lowercased().map {
            $0.isLetter || $0.isNumber ? String($0) : "-"
        }.joined()
        let document = WorkflowDocumentMapping.document(
            id: id, name: template.name, graph: graph, createdAtMs: 0
        )

        // Saved before running because `run` takes an id, not a document: the
        // engine reads what is stored, so an unsaved edit would not be executed.
        try await RunAnywhere.workflows.save(document)
        // Read it straight back. If this succeeds and the run still cannot find
        // the workflow, the two halves disagree about where storage lives.
        let readBack = (try? await RunAnywhere.workflows.load(id: id))?.id ?? "<missing>"
        let listed = ((try? await RunAnywhere.workflows.list()) ?? []).map(\.id)
        note("saved \(id); load=\(readBack); list=\(listed.joined(separator: ","))")
        defer { Task { try? await RunAnywhere.workflows.delete(id: id) } }

        let handle = try await RunAnywhere.workflows.run(workflowID: id)
        defer { handle.destroy() }
        try handle.start()

        // Draining the event stream is not enough on its own: it can close
        // while the last node is still running, and the record then reports
        // that node cancelled — which reads exactly like a product bug and is
        // not one. So the stream is drained and then the record is polled until
        // it actually reaches a terminal state.
        for await _ in handle.events {}

        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            let record = try handle.record()
            if record.state != .running && record.state != .unspecified {
                return (record, expectedFiles)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        return (try handle.record(), expectedFiles)
    }

    private func assertSucceeded(
        _ record: RAWorkflowRunRecord, template: WorkflowTemplate, plan: Fixture,
        expectedFiles: [String]
    ) throws {
        let failed = record.nodeRuns.filter { $0.state == .failed }
        let detail = failed
            .map { "\($0.nodeID): \($0.error.message)" }
            .joined(separator: "; ")
        XCTAssertTrue(failed.isEmpty, "\(template.name) had failing nodes: \(detail)")
        XCTAssertEqual(record.state, .succeeded, "\(template.name) did not finish: \(detail)")

        // Every node that ran has to have produced something. A node that
        // succeeds with no output is how an empty prompt variable reaches the
        // next node and quietly poisons the rest of the run.
        for node in record.nodeRuns where node.state == .succeeded {
            XCTAssertFalse(
                node.output.isEmpty,
                "\(template.name): \(node.nodeID) succeeded without producing anything"
            )
        }

        try plan.verify(files: expectedFiles, in: sandbox, template: template.name)
    }

    // MARK: - Pointing a template at the sandbox

    /// Rewrites the paths and the model so a template runs here rather than
    /// against whatever happens to be in the reader's home directory.
    ///
    /// The filenames come from the template, never from the fixture. Guessing
    /// them meant a template that reads `inbox-note.txt` was handed a
    /// `note.txt`, and the run failed on a missing file that the test itself
    /// had misplaced — a fixture bug wearing the costume of a product bug.
    private func rewrite(
        _ graph: inout WorkflowGraph, with plan: Fixture, model: String
    ) throws -> [String] {
        var written: [String] = []
        for index in graph.nodes.indices {
            let node = graph.nodes[index]
            if !node.settings.filePath.isEmpty {
                let name = URL(fileURLWithPath: node.settings.filePath).lastPathComponent
                let redirected = sandbox.appendingPathComponent(name)
                graph.nodes[index].settings.filePath = redirected.path(percentEncoded: false)

                switch node.kind {
                case .fileRead:
                    try Data(plan.input.utf8).write(to: redirected)
                case .fileWrite:
                    written.append(name)
                default:
                    break
                }
            }
            if !graph.nodes[index].settings.modelID.isEmpty {
                graph.nodes[index].settings.modelID = model
            }
            plan.adjust(&graph.nodes[index])
        }
        return written
    }

    // MARK: - Environment

    @MainActor
    private func bootSDK() async throws {
        try RunAnywhere.initialize(environment: .development)
        await ModelCatalogBootstrap.registerAll(mlxRegistered: false)
        _ = try? await RunAnywhere.models.refresh()
    }

    /// Loads the model the app would choose, and returns its id.
    @MainActor
    private func loadLanguageModel() async throws -> String? {
        let catalog = (try? await RunAnywhere.models.list()) ?? []
        guard let pick = ShippedModels.installed(for: .language, from: catalog)
            ?? catalog.first(where: {
                ModelPurpose.of($0) == .language && !$0.localPath.isEmpty && $0.isAvailableForUse
            })
        else { return nil }
        _ = try await RunAnywhere.models.load(id: pick.id)
        return pick.id
    }
}
