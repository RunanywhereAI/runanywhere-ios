import SwiftUI

/// Deterministic timings for the models already on this device: the same
/// prompts, the same synthetic audio and the same image every time, so two
/// reports differ only where the device or the model does.
struct BenchmarksScreen: View {
    @Environment(ModelStore.self) private var store
    @State private var model = BenchmarksModel()

    var body: some View {
        @Bindable var model = model

        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                device

                if model.isRunning {
                    running
                } else {
                    plan
                }

                history
            }
            .padding(Space.lg)
            .measured()
        }
        .background(AppColors.background)
        .task { model.prepare(with: store) }
        .onChange(of: store.installed.count) { model.reconcile(with: store) }
        .sheet(item: $model.openRun) { run in
            BenchmarkRunDetail(run: run, model: model)
        }
    }

    // MARK: - Device

    private var device: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.md) {
                GlyphTile(symbol: "cpu", tint: AppColors.accent, wash: AppColors.accentMuted)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(model.device.model)
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(model.device.chip)
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: Space.xl) {
                fact("Memory", BenchmarkFormat.bytes(model.device.totalMemoryBytes))
                fact("Cores", "\(model.device.cores)")
                fact("System", model.device.osVersion)
                Spacer(minLength: 0)
            }
        }
        .padding(Space.md)
        .card()
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Text(value)
                .appType(.cardTitle)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
            Text(label)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Plan

    private var plan: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ScreenSection(title: "What to measure") {
                VStack(spacing: Space.sm) {
                    ForEach(BenchmarkCategory.allCases) { category in
                        categoryCard(category)
                    }
                }
            }

            ScreenSection(title: "Repeats") {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.xs) {
                        ForEach(model.trialOptions, id: \.self) { count in
                            trialChip(count)
                        }
                        Spacer(minLength: 0)
                    }

                    Text("Every measurement runs this many times. Above one, the report gives "
                        + "the median and the range it moved through.")
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error = model.lastError {
                Text(error)
                    .appType(.meta)
                    .foregroundStyle(AppColors.danger)
                    .padding(Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(AppColors.dangerMuted)
                    )
            }

            runButton
        }
    }

    private var runButton: some View {
        let passes = model.plannedPasses(in: store)
        return Button {
            model.start(with: store)
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: "play.fill")
                    .glyph(Glyph.sm, weight: .semibold)
                Text(passes == 0 ? "Nothing selected" : "Run \(passes) measurement\(passes == 1 ? "" : "s")")
                    .appType(.cardTitle)
            }
            .foregroundStyle(passes == 0 ? AppColors.textTertiary : AppColors.onBrand)
            .frame(maxWidth: .infinity)
            .frame(height: Measure.hitTarget)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(passes == 0 ? AppColors.surfaceMuted : AppColors.brand)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(passes == 0)
    }

    private func categoryCard(_ category: BenchmarkCategory) -> some View {
        let models = model.models(for: category, in: store)
        let isOn = model.selectedCategories.contains(category)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !models.isEmpty else { return }
                withAnimation(Motion.expand) {
                    model.toggle(category, in: store)
                }
            } label: {
                HStack(spacing: Space.md) {
                    GlyphTile(
                        symbol: category.symbol,
                        tint: models.isEmpty ? AppColors.textTertiary : AppColors.brand,
                        wash: models.isEmpty ? AppColors.surfaceMuted : AppColors.brandMuted,
                        size: Control.tileSmall,
                        glyphSize: Glyph.sm,
                        radius: Radius.sm
                    )

                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(category.title)
                            .appType(.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(caption(for: category, models: models))
                            .appType(.meta)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer(minLength: Space.sm)

                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .glyph(Glyph.md, weight: .regular)
                        .foregroundStyle(isOn ? AppColors.brand : AppColors.borderStrong)
                }
                .padding(Space.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(models.isEmpty)

            if isOn, !models.isEmpty {
                Divider().overlay(AppColors.border)
                VStack(spacing: 0) {
                    ForEach(models) { installed in
                        modelRow(installed)
                    }
                }
                .padding(.vertical, Space.xs)
            }
        }
        .card()
    }

    private func caption(for category: BenchmarkCategory, models: [InstalledModel]) -> String {
        guard !models.isEmpty else {
            return "Nothing downloaded for this — add one in Manage Models"
        }
        let workloads = BenchmarkWorkload.all(for: category).count
        let noun = models.count == 1 ? "model" : "models"
        return "\(models.count) \(noun) · \(workloads) per model"
    }

    private func modelRow(_ installed: InstalledModel) -> some View {
        let isOn = model.selectedModelIDs.contains(installed.id)
        return Button {
            model.toggle(modelID: installed.id)
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .glyph(Glyph.sm)
                    .foregroundStyle(isOn ? AppColors.brand : AppColors.borderStrong)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(installed.name)
                        .appType(.secondary)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("\(installed.sizeLabel) · \(installed.backend)")
                        .appType(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func trialChip(_ count: Int) -> some View {
        let isOn = model.trials == count
        return Button {
            model.trials = count
        } label: {
            Text("\(count)×")
                .appType(.meta)
                .monospacedDigit()
                .foregroundStyle(isOn ? AppColors.onBrand : AppColors.textSecondary)
                .padding(.horizontal, Space.lg)
                .frame(height: Control.pill)
                .background(Capsule().fill(isOn ? AppColors.brandSelected : AppColors.surfaceMuted))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Running

    private var running: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.md) {
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(model.progress?.scenarioName ?? "Measuring")
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(model.progress?.modelName ?? "")
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Space.sm)

                PillButton(
                    title: "Stop",
                    symbol: "stop.fill",
                    tint: AppColors.danger,
                    fill: AppColors.dangerMuted
                ) {
                    model.cancel()
                }
            }

            ProgressView(value: model.progress?.fraction ?? 0)
                .tint(AppColors.brand)

            if let progress = model.progress {
                Text("\(progress.completed) of \(progress.total) measurements · \(model.trials)× each")
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
            }

            Text("Keep the app in front. Backgrounding it or letting the device sleep changes "
                + "what the numbers mean.")
                .appType(.caption)
                .foregroundStyle(AppColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.md)
        .card()
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                SectionHeader("History")

                Spacer(minLength: 0)

                if !model.runs.isEmpty {
                    Button("Clear") { model.clearHistory() }
                        .buttonStyle(.plain)
                        .appType(.meta)
                        .foregroundStyle(AppColors.danger)
                }
            }

            if model.runs.isEmpty {
                EmptyState(
                    symbol: "gauge.with.dots.needle.bottom.50percent",
                    title: "No runs yet",
                    detail: "Pick what to measure and run it. Every run is kept here with the "
                        + "device it was measured on."
                )
                .card()
            } else {
                VStack(spacing: Space.sm) {
                    ForEach(model.runs) { run in
                        runRow(run)
                    }
                }
            }
        }
    }

    private func runRow(_ run: BenchmarkRun) -> some View {
        Button {
            model.openRun = run
        } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.sm) {
                        Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .appType(.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)

                        BenchmarkStatusChip(status: run.status)
                    }

                    Text(summary(of: run))
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)

                    HStack(spacing: Space.xs) {
                        ForEach(run.categories) { category in
                            CapabilityTag(
                                symbol: category.symbol,
                                title: category.code,
                                tint: AppColors.info
                            )
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .glyph(Glyph.sm)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(Space.md)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func summary(of run: BenchmarkRun) -> String {
        var parts = ["\(run.succeeded) of \(run.results.count) measured"]
        if let duration = run.duration {
            parts.append(BenchmarkFormat.seconds(duration))
        }
        parts.append(run.device.chip)
        return parts.joined(separator: " · ")
    }
}

struct BenchmarkStatusChip: View {
    let status: BenchmarkRun.Status

    private var tint: Color {
        switch status {
        case .completed: AppColors.success
        case .failed: AppColors.danger
        case .cancelled: AppColors.textSecondary
        }
    }

    var body: some View {
        StatusTag(text: status.title, tint: tint, showsDot: false)
    }
}
