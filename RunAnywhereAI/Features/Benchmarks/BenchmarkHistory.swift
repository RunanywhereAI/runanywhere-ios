import Foundation
import os

/// Past runs, on disk as one JSON file.
///
/// Application Support rather than Documents: a benchmark history is the
/// app's own record, not a document the reader is expected to find in Files.
struct BenchmarkHistory {
    private static let limit = 25
    private static let logger = Logger(
        subsystem: "com.runanywhere.RunAnywhereAI",
        category: "Benchmarks"
    )

    private let url: URL?

    init() {
        let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        url = base?.appending(path: "benchmarks.json")
    }

    func load() -> [BenchmarkRun] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try Self.decoder.decode([BenchmarkRun].self, from: data)
        } catch {
            Self.logger.error("benchmark history unreadable: \(error, privacy: .public)")
            return []
        }
    }

    /// Newest first, which is the order every caller wants to show.
    func loadNewestFirst() -> [BenchmarkRun] {
        load().sorted { $0.startedAt > $1.startedAt }
    }

    func append(_ run: BenchmarkRun) {
        guard let url else { return }
        var runs = load()
        runs.append(run)
        if runs.count > Self.limit {
            runs = Array(runs.suffix(Self.limit))
        }
        do {
            try Self.encoder.encode(runs).write(to: url, options: .atomic)
        } catch {
            Self.logger.error("benchmark history not saved: \(error, privacy: .public)")
        }
    }

    func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
