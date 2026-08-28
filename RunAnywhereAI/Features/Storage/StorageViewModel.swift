import Foundation
import Observation
import RunAnywhere
import os

/// One downloaded model as the storage screen shows it.
struct StoredModel: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
    let bytes: Int64
    let sizeLabel: String
}

@Observable
@MainActor
final class StorageViewModel {
    /// The one long-running job allowed at a time, so a row can show its own
    /// spinner without a second flag per action.
    enum Activity: Equatable {
        case clearingCache
        case cleaningTemp
        case deleting(String)
    }

    private(set) var usedBytes: Int64 = 0
    private(set) var freeBytes: Int64 = 0
    private(set) var models: [StoredModel] = []
    private(set) var isLoading = false
    private(set) var activity: Activity?
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Storage")

    var isBusy: Bool { activity != nil }

    var capacityBytes: Int64 { usedBytes + freeBytes }

    /// How much of the volume the models account for, as a bar fraction.
    var usedFraction: Double {
        guard capacityBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(capacityBytes), 0), 1)
    }

    func refresh(store: ModelStore) async {
        isLoading = true
        defer { isLoading = false }

        await store.refresh()
        let state = await RunAnywhere.models.state()
        usedBytes = state.storageUsedBytes
        freeBytes = state.storageFreeBytes
        models = Self.stored(in: store)
    }

    func clearCache(store: ModelStore) async {
        await run(.clearingCache, store: store) {
            try await RunAnywhere.clearCache()
        }
    }

    func cleanTempFiles(store: ModelStore) async {
        await run(.cleaningTemp, store: store) {
            try await RunAnywhere.cleanTempFiles()
        }
    }

    func delete(_ model: StoredModel, store: ModelStore) async {
        await run(.deleting(model.id), store: store) {
            try await RunAnywhere.models.delete(id: model.id)
        }
    }

    private func run(_ activity: Activity, store: ModelStore, _ work: () async throws -> Void) async {
        guard self.activity == nil else { return }
        self.activity = activity
        defer { self.activity = nil }

        do {
            try await work()
            lastError = nil
        } catch {
            logger.error("\(String(describing: activity), privacy: .public) failed: \(error, privacy: .public)")
            lastError = error.localizedDescription
        }
        await refresh(store: store)
    }

    /// Registry entries with bytes actually on disk, largest first.
    ///
    /// A zero download size means a registry-only entry — an Apple system model
    /// or a built-in pseudo-model — which occupies nothing and cannot be freed.
    private static func stored(in store: ModelStore) -> [StoredModel] {
        let kinds = Dictionary(store.models.map { ($0.id, $0.category) }) { first, _ in first }
        return store.raw
            .filter { !$0.localPath.isEmpty && $0.downloadSizeBytes > 0 }
            .map { info in
                StoredModel(
                    id: info.id,
                    name: info.name.isEmpty ? info.id : info.name,
                    kind: kinds[info.id] ?? "Model",
                    bytes: info.downloadSizeBytes,
                    sizeLabel: AppSettings.format(info.downloadSizeBytes)
                )
            }
            .sorted { $0.bytes > $1.bytes }
    }
}
