import Foundation
import Observation
import RunAnywhere
import os
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
@MainActor
final class BenchmarksModel {
    let device = BenchmarkDevice.current
    let trialOptions = [1, 3, 5]

    var selectedCategories: Set<BenchmarkCategory> = [.llm]
    var selectedModelIDs: Set<String> = []
    var trials = 3
    var openRun: BenchmarkRun?

    private(set) var runs: [BenchmarkRun] = []
    private(set) var progress: BenchmarkProgress?
    private(set) var isRunning = false
    private(set) var lastError: String?
    private(set) var copied: BenchmarkExportFormat?

    private let history = BenchmarkHistory()
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Benchmarks")
    private var task: Task<Void, Never>?
    private var copiedResetTask: Task<Void, Never>?
    private var hasSeededSelection = false

    // MARK: - Setup

    func prepare(with store: ModelStore) {
        runs = history.loadNewestFirst()
        reconcile(with: store)
    }

    /// Keep the selection to models that are still on disk, and select
    /// everything the first time a list arrives. The store may still be
    /// refreshing when the screen opens, so this runs again when it lands.
    func reconcile(with store: ModelStore) {
        let installed = Set(store.installed.map(\.id))
        guard !installed.isEmpty else { return }
        if hasSeededSelection {
            selectedModelIDs.formIntersection(installed)
        } else {
            selectedModelIDs = installed
            hasSeededSelection = true
        }
    }

    /// Everything downloaded that this category can benchmark.
    func models(for category: BenchmarkCategory, in store: ModelStore) -> [InstalledModel] {
        store.installed
            .filter { $0.purpose == category.purpose }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func toggle(_ category: BenchmarkCategory, in store: ModelStore) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
            // Turning a category on with nothing ticked inside it would run
            // nothing, so its models arrive selected.
            let ids = models(for: category, in: store).map(\.id)
            if ids.allSatisfy({ !selectedModelIDs.contains($0) }) {
                selectedModelIDs.formUnion(ids)
            }
        }
        lastError = nil
    }

    func toggle(modelID: String) {
        if selectedModelIDs.contains(modelID) {
            selectedModelIDs.remove(modelID)
        } else {
            selectedModelIDs.insert(modelID)
        }
        lastError = nil
    }

    /// How many measured passes the current selection amounts to.
    func plannedPasses(in store: ModelStore) -> Int {
        items(in: store).count * trials
    }

    // MARK: - Running

    func start(with store: ModelStore) {
        guard !isRunning else { return }
        let plan = items(in: store)
        guard !plan.isEmpty else {
            lastError = "Pick at least one downloaded model to measure."
            return
        }

        isRunning = true
        lastError = nil
        progress = BenchmarkProgress(
            completed: 0,
            total: plan.count,
            modelName: "",
            scenarioName: "Preparing"
        )

        let trials = trials
        task = Task { [weak self] in
            await self?.execute(plan, trials: trials)
        }
    }

    func cancel() {
        task?.cancel()
    }

    func clearHistory() {
        history.clear()
        runs = []
        openRun = nil
    }

    // MARK: - Export

    func copy(_ run: BenchmarkRun, as format: BenchmarkExportFormat) {
        let text = BenchmarkReport.text(for: run, format: format)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif

        copied = format
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.copied = nil
        }
    }

    func exportFile(_ run: BenchmarkRun, as format: BenchmarkExportFormat) -> URL? {
        do {
            return try BenchmarkReport.file(for: run, format: format)
        } catch {
            logger.error("benchmark export failed: \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - Private

    private func execute(_ plan: [BenchmarkEngine.Item], trials: Int) async {
        var run = BenchmarkRun(device: device)
        let outcome = await BenchmarkEngine().run(items: plan, trials: trials) { [weak self] update in
            Task { @MainActor in self?.progress = update }
        }

        run.results = outcome.results
        run.finishedAt = Date()
        if outcome.wasCancelled {
            run.status = .cancelled
        } else {
            run.status = run.results.allSatisfy(\.didSucceed) ? .completed : .failed
        }

        // Individual failures are already spelled out in the run detail; the
        // banner is for a run where nothing worked at all.
        if run.succeeded == 0, let failure = run.results.first?.failure {
            lastError = failure
        }

        if !run.results.isEmpty {
            history.append(run)
            runs = history.loadNewestFirst()
            openRun = run
            logger.info(
                "benchmark run \(run.status.rawValue, privacy: .public) with \(run.results.count) measurements"
            )
        }

        progress = nil
        isRunning = false
        task = nil
    }

    private func items(in store: ModelStore) -> [BenchmarkEngine.Item] {
        BenchmarkCategory.allCases
            .filter(selectedCategories.contains)
            .flatMap { category -> [BenchmarkEngine.Item] in
                let workloads = BenchmarkWorkload.all(for: category)
                return models(for: category, in: store)
                    .filter { selectedModelIDs.contains($0.id) }
                    .flatMap { model in
                        workloads.map {
                            BenchmarkEngine.Item(model: Self.reference(to: model), workload: $0)
                        }
                    }
            }
    }

    private static func reference(to model: InstalledModel) -> BenchmarkModelRef {
        BenchmarkModelRef(id: model.id, name: model.name, backend: model.backend)
    }
}
