import Foundation

enum BenchmarkExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case json
    case csv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        case .csv: "CSV"
        }
    }

    var detail: String {
        switch self {
        case .markdown: "Readable report to paste into an issue"
        case .json: "Every field, exactly as recorded"
        case .csv: "One row per measurement, for a spreadsheet"
        }
    }

    var symbol: String {
        switch self {
        case .markdown: "doc.text"
        case .json: "curlybraces"
        case .csv: "tablecells"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .json: "json"
        case .csv: "csv"
        }
    }
}

/// Shared number formatting. The screen and the exported report read from the
/// same functions so a figure someone quotes from the UI matches the file.
enum BenchmarkFormat {
    static func duration(_ milliseconds: Double) -> String {
        milliseconds >= 1000
            ? String(format: "%.2f s", milliseconds / 1000)
            : String(format: "%.0f ms", milliseconds)
    }

    static func rate(_ tokensPerSecond: Double) -> String {
        String(format: "%.1f tok/s", tokensPerSecond)
    }

    static func factor(_ realTimeFactor: Double) -> String {
        String(format: "%.2f×", realTimeFactor)
    }

    static func seconds(_ value: Double) -> String {
        String(format: "%.2f s", value)
    }

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        let magnitude = formatter.string(fromByteCount: abs(value))
        return value < 0 ? "−\(magnitude)" : magnitude
    }

    static func range(_ range: BenchmarkRange?, _ format: (Double) -> String) -> String? {
        guard let range else { return nil }
        return "\(format(range.low)) – \(format(range.high))"
    }
}

enum BenchmarkReport {
    static func text(for run: BenchmarkRun, format: BenchmarkExportFormat) -> String {
        switch format {
        case .markdown: markdown(for: run)
        case .json: json(for: run)
        case .csv: csv(for: run)
        }
    }

    /// Write a report next to the temporary directory and hand back the URL,
    /// which is what `ShareLink` needs.
    static func file(for run: BenchmarkRun, format: BenchmarkExportFormat) throws -> URL {
        let stamp = ISO8601DateFormatter.filenameSafe.string(from: run.startedAt)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "benchmark-\(stamp).\(format.fileExtension)")
        try text(for: run, format: format).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Markdown

    private static func markdown(for run: BenchmarkRun) -> String {
        var lines: [String] = ["# Benchmark report", ""]
        lines.append("- Device: \(run.device.model) · \(run.device.chip) · \(run.device.cores) cores")
        lines.append("- Memory: \(BenchmarkFormat.bytes(run.device.totalMemoryBytes))")
        lines.append("- OS: \(run.device.osVersion)")
        lines.append("- Started: \(run.startedAt.formatted(date: .abbreviated, time: .standard))")
        if let duration = run.duration {
            lines.append("- Duration: \(BenchmarkFormat.seconds(duration))")
        }
        lines.append("- Status: \(run.status.title)")
        lines.append("- Measurements: \(run.results.count), of which \(run.succeeded) succeeded")
        lines.append("")

        for category in run.categories {
            lines.append("## \(category.title)")
            lines.append("")
            for result in run.results where result.category == category {
                lines.append("### \(result.model.name) — \(result.scenario.name)")
                lines.append("")
                lines.append("- Backend: \(result.model.backend)")
                if let failure = result.failure {
                    lines.append("- Failed: \(failure)")
                    lines.append("")
                    continue
                }
                if result.trials > 1 {
                    lines.append("- Trials: \(result.trials), median reported, range in brackets")
                }
                for row in rows(for: result) {
                    let bracket = row.spread.map { " [\($0)]" } ?? ""
                    lines.append("- \(row.label): \(row.value)\(bracket)")
                }
                lines.append("")
            }
        }

        if run.results.contains(where: { $0.metrics.prefillTokensPerSecond != nil }) {
            lines.append("Prefill throughput is prompt tokens divided by time to first token; "
                + "the SDK does not publish prefill wall time separately, so it is a floor.")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON

    private static func json(for run: BenchmarkRun) -> String {
        guard let data = try? BenchmarkHistory.encoder.encode(run),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    // MARK: - CSV

    private static let csvColumns = [
        "category", "model", "model_id", "backend", "scenario", "trials",
        "load_ms", "warmup_ms", "latency_ms", "latency_min_ms", "latency_max_ms",
        "ttft_ms", "ttft_min_ms", "ttft_max_ms",
        "prefill_tokens_per_second", "decode_tokens_per_second",
        "decode_min_tokens_per_second", "decode_max_tokens_per_second",
        "input_tokens", "output_tokens", "audio_seconds", "real_time_factor",
        "characters", "memory_delta_bytes", "succeeded", "failure"
    ]

    private static func csv(for run: BenchmarkRun) -> String {
        var lines = [csvColumns.joined(separator: ",")]
        for result in run.results {
            let metrics = result.metrics
            let spread = result.spread
            let fields: [String] = [
                result.category.code,
                result.model.name,
                result.model.id,
                result.model.backend,
                result.scenario.name,
                String(result.trials),
                number(metrics.loadMs),
                number(metrics.warmupMs),
                number(metrics.latencyMs),
                number(spread?.latencyMs?.low),
                number(spread?.latencyMs?.high),
                number(metrics.ttftMs),
                number(spread?.ttftMs?.low),
                number(spread?.ttftMs?.high),
                number(metrics.prefillTokensPerSecond),
                number(metrics.decodeTokensPerSecond),
                number(spread?.decodeTokensPerSecond?.low),
                number(spread?.decodeTokensPerSecond?.high),
                metrics.inputTokens.map(String.init) ?? "",
                metrics.outputTokens.map(String.init) ?? "",
                number(metrics.audioSeconds),
                number(metrics.realTimeFactor),
                metrics.characters.map(String.init) ?? "",
                String(metrics.memoryDeltaBytes),
                result.didSucceed ? "true" : "false",
                result.failure ?? ""
            ]
            lines.append(fields.map(escaped).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.4f", value)
    }

    private static func escaped(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Metric rows

    /// One measurement as a label, a value and an optional spread. The detail
    /// view renders the same list, so a metric is added in one place.
    struct Row: Identifiable {
        let label: String
        let value: String
        let spread: String?

        var id: String { label }
    }

    static func rows(for result: BenchmarkResult) -> [Row] {
        let metrics = result.metrics
        let spread = result.spread
        var rows: [Row] = []

        func add(_ label: String, _ value: String?, _ spread: String? = nil) {
            guard let value else { return }
            rows.append(Row(label: label, value: value, spread: spread))
        }

        add("Model load", BenchmarkFormat.duration(metrics.loadMs))
        add(
            "End to end",
            BenchmarkFormat.duration(metrics.latencyMs),
            BenchmarkFormat.range(spread?.latencyMs, BenchmarkFormat.duration)
        )
        add(
            "Time to first token",
            metrics.ttftMs.map(BenchmarkFormat.duration),
            BenchmarkFormat.range(spread?.ttftMs, BenchmarkFormat.duration)
        )
        add(
            "Decode",
            metrics.decodeTokensPerSecond.map(BenchmarkFormat.rate),
            BenchmarkFormat.range(spread?.decodeTokensPerSecond, BenchmarkFormat.rate)
        )
        add("Prefill (derived)", metrics.prefillTokensPerSecond.map(BenchmarkFormat.rate))
        add("Prompt tokens", metrics.inputTokens.map(String.init))
        add("Output tokens", metrics.outputTokens.map(String.init))
        add("Audio", metrics.audioSeconds.map(BenchmarkFormat.seconds))
        add(
            "Real time factor",
            metrics.realTimeFactor.map(BenchmarkFormat.factor),
            BenchmarkFormat.range(spread?.realTimeFactor, BenchmarkFormat.factor)
        )
        add("Characters", metrics.characters.map(String.init))
        add("Warmup", metrics.warmupMs > 0 ? BenchmarkFormat.duration(metrics.warmupMs) : nil)
        add("Memory delta", metrics.memoryDeltaBytes != 0 ? BenchmarkFormat.bytes(metrics.memoryDeltaBytes) : nil)
        return rows
    }
}

private extension ISO8601DateFormatter {
    static let filenameSafe: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        return formatter
    }()
}
