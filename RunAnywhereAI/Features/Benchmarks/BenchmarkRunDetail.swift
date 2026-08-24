import SwiftUI

/// One past run, category by category, with the report in the three formats
/// people actually paste it into.
struct BenchmarkRunDetail: View {
    let run: BenchmarkRun
    let model: BenchmarksModel

    @Environment(\.dismiss) private var dismiss
    @State private var files: [BenchmarkExportFormat: URL] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    device

                    ForEach(run.categories) { category in
                        section(category)
                    }

                    export

                    if run.results.contains(where: { $0.metrics.prefillTokensPerSecond != nil }) {
                        Text("Prefill is prompt tokens over time to first token. The SDK does not "
                            + "publish prefill wall time on its own, so that figure is a floor, not "
                            + "an exact rate.")
                            .appType(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Space.lg)
                .measured()
            }
        }
        .background(AppColors.background)
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 580)
        #endif
        .task { prepareFiles() }
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("\(run.succeeded) of \(run.results.count) measured")
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: Space.sm)

            BenchmarkStatusChip(status: run.status)

            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .appType(.secondary)
                .foregroundStyle(AppColors.brand)
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: Measure.barHeight)
        .background(AppColors.surface)
        .overlay(alignment: .bottom) { Divider().overlay(AppColors.border) }
    }

    private var device: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("\(run.device.model) · \(run.device.chip)")
                .appType(.secondary)
                .foregroundStyle(AppColors.textPrimary)
            Text("\(run.device.cores) cores · \(BenchmarkFormat.bytes(run.device.totalMemoryBytes)) "
                + "· \(run.device.osVersion)")
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)
            if let duration = run.duration {
                Text("Took \(BenchmarkFormat.seconds(duration))")
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func section(_ category: BenchmarkCategory) -> some View {
        ScreenSection(title: category.title) {
            ForEach(run.results.filter { $0.category == category }) { result in
                card(result)
            }
        }
    }

    private func card(_ result: BenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(result.model.name)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("\(result.scenario.detail) · \(result.model.backend)"
                    + (result.trials > 1 ? " · median of \(result.trials)" : ""))
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failure = result.failure {
                Text(failure)
                    .appType(.meta)
                    .foregroundStyle(AppColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(AppColors.dangerMuted)
                    )
            } else {
                VStack(spacing: Space.sm) {
                    ForEach(BenchmarkReport.rows(for: result)) { row in
                        metric(row)
                    }
                }
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func metric(_ row: BenchmarkReport.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Text(row.label)
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: Space.sm)

            VStack(alignment: .trailing, spacing: Space.hair) {
                Text(row.value)
                    .appType(.monoMetric)
                    .foregroundStyle(AppColors.textPrimary)
                if let spread = row.spread {
                    Text(spread)
                        .appType(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }

    // MARK: - Export

    private var export: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Export")

            VStack(spacing: Space.sm) {
                ForEach(BenchmarkExportFormat.allCases) { format in
                    exportRow(format)
                }
            }
        }
    }

    private func exportRow(_ format: BenchmarkExportFormat) -> some View {
        HStack(spacing: Space.md) {
            GlyphTile(
                symbol: format.symbol,
                tint: AppColors.accent,
                wash: AppColors.accentMuted,
                size: Control.tileSmall,
                glyphSize: Glyph.sm,
                radius: Radius.sm
            )

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(format.title)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(format.detail)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.sm)

            if let url = files[format] {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .glyph(Glyph.sm)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: Control.tileSmall, height: Control.tileSmall)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            copyButton(format)
        }
        .padding(Space.md)
        .card()
    }

    private func copyButton(_ format: BenchmarkExportFormat) -> some View {
        let isCopied = model.copied == format
        return PillButton(
            title: isCopied ? "Copied" : "Copy",
            symbol: isCopied ? "checkmark" : "doc.on.doc",
            tint: isCopied ? AppColors.success : AppColors.brand,
            fill: isCopied ? AppColors.successMuted : AppColors.brandMuted
        ) {
            model.copy(run, as: format)
        }
        .animation(Motion.fade, value: isCopied)
    }

    /// `ShareLink` needs a URL that already exists, so the three reports are
    /// written once when the sheet opens rather than on every redraw.
    private func prepareFiles() {
        guard files.isEmpty else { return }
        var written: [BenchmarkExportFormat: URL] = [:]
        for format in BenchmarkExportFormat.allCases {
            if let url = model.exportFile(run, as: format) {
                written[format] = url
            }
        }
        files = written
    }
}
