//
//  WorkflowPalette.swift
//  RunAnywhereAI
//
//  The left sidebar: the fixed node types, the installed packs sitting in the
//  category each one declared, the pack library, the schedules the host is
//  running, and the saved workflows.
//
//  A pack row is the same affordance as a node row — click to place, drag onto
//  the canvas — because from the user's side an installed pack *is* a node.
//

#if os(macOS)

import RunAnywhere
import SwiftUI
import UniformTypeIdentifiers

/// What a palette row hands to the canvas. Both arms travel as JSON through the
/// same drag representation, so the drop site resolves one type rather than
/// guessing between two.
enum WorkflowPaletteItem: Codable, Transferable, Hashable {
    case kind(WorkflowNodeKind)
    case pack(String)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct WorkflowPalette: View {
    var viewModel: WorkflowEditorViewModel
    let onAdd: (WorkflowPaletteItem) -> Void
    let onLoad: (String) -> Void
    let onExport: (String) -> Void

    private var scheduler: WorkflowScheduler { WorkflowScheduler.shared }
    private var packStore: WorkflowPackStore { viewModel.packStore }

    var body: some View {
        List {
            ForEach(WorkflowNodeCategory.allCases) { category in
                categorySection(category)
            }

            ForEach(packStore.customCategories, id: \.self) { category in
                Section(category) {
                    ForEach(packStore.packs(inCategory: category), id: \.id) { pack in
                        packRow(pack)
                    }
                }
            }

            packLibrarySection

            if !scheduler.entries.isEmpty {
                Section("Scheduled") {
                    ForEach(scheduler.entries) { entry in
                        scheduleRow(entry)
                    }
                }
            }

        }
        .listStyle(.sidebar)
        .background(AppColors.background)
    }

    // MARK: - Nodes

    @ViewBuilder
    private func categorySection(_ category: WorkflowNodeCategory) -> some View {
        let kinds = WorkflowNodeKind.placeable.filter { $0.category == category }
        let packs = packStore.packs(inCategory: category.rawValue)
        if !kinds.isEmpty || !packs.isEmpty {
            Section(category.rawValue) {
                ForEach(kinds) { kind in
                    paletteRow(kind)
                }
                ForEach(packs, id: \.id) { pack in
                    packRow(pack)
                }
            }
        }
    }

    private func paletteRow(_ kind: WorkflowNodeKind) -> some View {
        Button {
            onAdd(.kind(kind))
        } label: {
            HStack(spacing: Space.sm) {
                rowIcon(kind.systemImage, tint: kind.category.accent)

                Text(kind.title)
                    .appType(.body)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(WorkflowPaletteItem.kind(kind))
        .help("Click to add, or drag onto the canvas")
    }

    private func packRow(_ pack: RANodePack) -> some View {
        Button {
            onAdd(.pack(pack.id))
        } label: {
            HStack(spacing: Space.sm) {
                rowIcon(pack.resolvedSymbol, tint: pack.accent)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(pack.displayName)
                        .appType(.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(pack.subtitle)
                        .appType(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(WorkflowPaletteItem.pack(pack.id))
        .help(pack.description_p.isEmpty
            ? "Click to add, or drag onto the canvas"
            : pack.description_p)
    }

    private func rowIcon(_ symbol: String, tint: Color) -> some View {
        WorkflowIconWell(symbol: symbol, tint: tint)
    }

    // MARK: - Pack library

    @ViewBuilder private var packLibrarySection: some View {
        Section("Node Packs") {
            if let failure = packStore.listError {
                unreadableRow("Couldn't read installed packs", detail: failure) {
                    Task { await packStore.refresh() }
                }
            } else if packStore.installedPacks.isEmpty {
                Text("No packs installed")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ForEach(packStore.installedPacks, id: \.id) { pack in
                    packLibraryRow(pack)
                }
            }
        }
    }

    private func packLibraryRow(_ pack: RANodePack) -> some View {
        HStack(spacing: Space.sm) {
            rowIcon(pack.resolvedSymbol, tint: pack.accent)

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(pack.displayName)
                    .appType(.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(pack.subtitle)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                Text(pack.paletteCategory)
                    .appType(.caption)
                    .foregroundStyle(pack.accent)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.xs)

            Button {
                Task { await viewModel.deletePack(pack) }
            } label: {
                Image(systemName: "trash")
                    .glyph(Glyph.xs, weight: .semibold)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Uninstall this pack. Nodes that use it become placeholders.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Schedules

    private func scheduleRow(_ entry: WorkflowScheduler.Entry) -> some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            HStack(spacing: Space.xs) {
                Text(entry.name)
                    .appType(.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Space.xs)
                Toggle("", isOn: Binding(
                    get: { entry.isEnabled },
                    set: { scheduler.setEnabled($0, for: entry.workflowID) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(entry.isEnabled ? "Disable this schedule" : "Enable this schedule")
            }

            Text(entry.summary)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)

            Text(nextFireText(entry))
                .appType(.caption)
                .foregroundStyle(nextFireColor(entry))
                .lineLimit(1)

            if let outcome = entry.lastOutcome {
                Text(outcome)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            Button("Open") { onLoad(entry.workflowID) }
            Button("Run Now") {
                Task { await scheduler.runNow(entry.workflowID) }
            }
        }
    }

    private func nextFireText(_ entry: WorkflowScheduler.Entry) -> String {
        guard entry.isEnabled else { return "Paused" }
        guard let next = entry.nextFireDate else { return "Never fires" }
        return "Next " + WorkflowScheduleFormat.nextFire(next)
    }

    private func nextFireColor(_ entry: WorkflowScheduler.Entry) -> Color {
        guard entry.isEnabled else { return AppColors.textSecondary }
        // No next fire means a cron expression that never comes round, such as
        // 30 February — worth flagging, but nothing is broken.
        return entry.isScheduled ? AppColors.success : AppColors.warning
    }




    /// A listing that threw, said as what it is, with the one thing worth
    /// offering: try again.
    private func unreadableRow(
        _ title: String,
        detail: String,
        retry: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .glyph(Glyph.xs, weight: .semibold)
                    .foregroundStyle(AppColors.danger)
                Text(title)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textPrimary)
            }
            Text(detail)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: retry)
                .buttonStyle(.plain)
                .appType(.caption)
                .foregroundStyle(AppColors.brand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func libraryMeta(_ summary: RAWorkflowSummary) -> String {
        let updated = Date(timeIntervalSince1970: TimeInterval(summary.updatedAtMs) / 1000)
        let relative = updated.formatted(.relative(presentation: .named))
        return "\(summary.nodeCount) nodes · \(relative)"
    }
}

#endif
