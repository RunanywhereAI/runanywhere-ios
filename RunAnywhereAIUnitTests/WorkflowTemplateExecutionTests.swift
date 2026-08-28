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
        let ids = cleanup
        cleanup = []
        let done = expectation(description: "workflows removed")
        Task {
            for id in ids { try? await RunAnywhere.workflows.delete(id: id) }
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
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

        // One throwaway generation before anything is measured. The first
        // template in a fresh process kept writing an empty file while the same
        // template passed three times over once something else had run — so
        // this is here to find out whether a freshly loaded model answers its
        // first question, and to stop that being the first template's problem.
        // One template run and thrown away before anything is measured. A lone
        // run after a fresh init can come back with an empty answer — see
        // `testASingleGenerateNodeRunOnceProducesOutput`, which pins that on
        // its own. Without this, whichever template happened to go first wore
        // the blame for it.
        if let first = WorkflowTemplateLibrary.templates.first(where: { Fixture.plan(for: $0.name) != nil }),
           let plan = Fixture.plan(for: first.name) {
            _ = try? await run(first, plan: plan, model: model)
            note("warm-up run of \(first.name) discarded")
        }

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
    /// Workflow ids to remove once every run in a test has finished.
    private var cleanup: [String] = []

    struct Trouble: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private func note(_ text: String) {
        trace.append(text)
    }

    /// A single generate node, run once, must answer.
    ///
    /// It does not, reliably. Run this template three times and all three
    /// answer; run it exactly once after a fresh init and it writes an empty
    /// file. Reversing the order of the suite made the failure move to
    /// whichever template went first, which is what ruled out the template
    /// itself. What it has not yet ruled out is what makes a lone run
    /// different from the first of several — that is the open question.
    ///
    /// Kept as its own test so the bug keeps a name and a reproduction instead
    /// of being absorbed by the warm-up the suite above now does. It is
    /// expected to be red until the empty answer is explained.
    @MainActor
    func testASingleGenerateNodeRunOnceProducesOutput() async throws {
        try await bootSDK()
        guard let model = try await loadLanguageModel() else {
            throw XCTSkip("No language model is installed on this machine.")
        }
        let template = try XCTUnwrap(
            WorkflowTemplateLibrary.templates.first { $0.name == "Summarise a document" }
        )
        let plan = try XCTUnwrap(Fixture.plan(for: template.name))

        let (record, files) = try await run(template, plan: plan, model: model)
        let written = files.compactMap {
            try? String(contentsOf: sandbox.appendingPathComponent($0), encoding: .utf8)
        }.first ?? ""

        XCTAssertFalse(
            written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "a lone run wrote nothing. state=\(record.state), "
                + "nodes=\(record.nodeRuns.map { "\($0.nodeID):\($0.state)" }.joined(separator: ","))"
        )
    }

    /// The same template, three times over, in one process.
    ///
    /// Written because the suite kept failing on a different template each run
    /// while the code under it did not change: one pass would summarise fine
    /// and the next would write an empty file. That is not a template problem,
    /// and running one template repeatedly is the shortest way to tell a flaky
    /// engine from a flaky prompt.
    @MainActor
    func testTheSameTemplateGivesTheSameAnswerThreeTimesRunning() async throws {
        try await bootSDK()
        guard let model = try await loadLanguageModel() else {
            throw XCTSkip("No language model is installed on this machine.")
        }
        let template = try XCTUnwrap(
            WorkflowTemplateLibrary.templates.first { $0.name == "Summarise a document" }
        )
        let plan = try XCTUnwrap(Fixture.plan(for: template.name))

        var outcomes: [String] = []
        for attempt in 1 ... 3 {
            do {
                let (record, files) = try await run(template, plan: plan, model: model)
                let failed = record.nodeRuns.filter { $0.state == .failed }
                    .map { "\($0.nodeID):\($0.error.message)" }.joined(separator: ",")
                let written = files.compactMap {
                    try? String(contentsOf: sandbox.appendingPathComponent($0), encoding: .utf8)
                }.first ?? ""
                outcomes.append(
                    "run \(attempt): state=\(record.state) failed=[\(failed)] wrote=\(written.count) chars"
                )
            } catch {
                outcomes.append("run \(attempt): threw \(error)")
            }
        }

        let consistent = Set(outcomes.map { $0.contains("failed=[]") }).count == 1
        XCTAssertTrue(consistent, "the same template did not behave the same way:\n"
            + outcomes.joined(separator: "\n"))
        XCTAssertTrue(outcomes.allSatisfy { $0.contains("failed=[]") },
            outcomes.joined(separator: "\n"))
    }

    // MARK: - Running one

    @MainActor
    private func run(
        _ template: WorkflowTemplate, plan: Fixture, model: String
    ) async throws -> (RAWorkflowRunRecord, [String]) {
        var graph = template.graph()
        let expectedFiles = try rewrite(&graph, with: plan, model: model)

        // Ids become path components, so the store refuses anything with a
        // space in it. Template ids are display names, hence the slug — and the
        // suffix, because two runs of the same template must not share an id.
        let slug = template.name.lowercased().map {
            $0.isLetter || $0.isNumber ? String($0) : "-"
        }.joined()
        let id = "test-\(slug)-\(UUID().uuidString.prefix(8))"
        let document = WorkflowDocumentMapping.document(
            id: id, name: template.name, graph: graph, createdAtMs: 0
        )

        // Saved before running because `run` takes an id, not a document: the
        // engine reads what is stored, so an unsaved edit would not be executed.
        try await RunAnywhere.workflows.save(document)
        // Deleted at the end of the run, awaited. A detached cleanup task raced
        // the next run and deleted the workflow it had just saved, which
        // surfaced as "run_create_proto failed: Not found" on the run after any
        // successful one — an engine bug that was nothing of the sort.
        defer { cleanup.append(id) }
        // Read it straight back. If this succeeds and the run still cannot find
        // the workflow, the two halves disagree about where storage lives.
        let readBack = (try? await RunAnywhere.workflows.load(id: id))?.id ?? "<missing>"
        let listed = ((try? await RunAnywhere.workflows.list()) ?? []).map(\.id)
        note("saved \(id); load=\(readBack); list=\(listed.joined(separator: ","))")

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
        // Thrown, not asserted, so every outcome lands in one place and the
        // trace that explains it is printed with it.
        guard failed.isEmpty else {
            throw Trouble("had failing nodes: \(detail)")
        }
        guard record.state == .succeeded else {
            throw Trouble("did not finish: state=\(record.state) \(detail)")
        }

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
            // Bound on every node that generates, including the ones that ship
            // with it blank. An empty model id makes the engine answer with
            // "whatever is currently loaded", which is not something a test can
            // assert on — and `ensure_model_loaded` returns success without
            // loading anything at all when the id is empty.
            switch node.kind {
            case .llmGenerate, .llmStructured:
                graph.nodes[index].settings.modelID = model
            default:
                if !graph.nodes[index].settings.modelID.isEmpty {
                    graph.nodes[index].settings.modelID = model
                }
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

    /// Loads the best chat model this machine can actually run, and returns
    /// its id.
    ///
    /// Not the shipped default, and not simply the largest either. The default
    /// is chosen to run anywhere, which for structured output means one that
    /// cannot reliably produce schema-valid JSON — that failure measures the
    /// model, not the workflow. But "largest" picked a 27B that exhausted
    /// memory and failed generation outright, which measures the machine.
    ///
    /// So: models that advertise tool support, because that is the same
    /// discipline structured output needs, and among those the largest that
    /// still leaves the machine room to run it.
    @MainActor
    private func loadLanguageModel() async throws -> String? {
        let catalog = (try? await RunAnywhere.models.list()) ?? []
        // A third of RAM let a 16 GB 27B through, and it failed generation
        // outright: the weights are only part of what a run costs, and the KV
        // cache for a long prompt is the rest. A sixth, capped at 8 GB, keeps
        // the choice to models that have room to actually answer.
        let ceiling = min(Int64(ProcessInfo.processInfo.physicalMemory / 6), 8_000_000_000)

        let installed = catalog.filter {
            ModelPurpose.of($0) == .language
                && !$0.localPath.isEmpty
                && $0.isAvailableForUse
                && !$0.isLoRAAdapterArtifact
                && $0.consumerSizeBytes < ceiling
        }
        let capable = installed.filter {
            ToolCapability.supports(id: $0.id, name: $0.name, downloadBytes: $0.downloadSizeBytes)
        }
        let field = capable.isEmpty ? installed : capable

        guard let pick = field.max(by: { $0.consumerSizeBytes < $1.consumerSizeBytes }) else {
            return nil
        }
        note("chose \(pick.id) (\(pick.consumerSizeBytes / 1_000_000) MB, ceiling \(ceiling / 1_000_000) MB)")
        _ = try await RunAnywhere.models.load(id: pick.id)
        return pick.id
    }
}
