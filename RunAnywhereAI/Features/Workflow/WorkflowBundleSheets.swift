//
//  WorkflowBundleSheets.swift
//  RunAnywhereAI
//
//  Moving workflows and packs in and out of a file the user chose.
//
//  Import is per item on purpose. A bundle of five workflows is usually shared
//  for one of them, and a workflow taken without its pack still opens — the
//  pack node renders as a marked placeholder instead of failing the document.
//
//  The four sheets share one route so only one can ever be up: the picker that
//  chooses what to export, the picker that chooses what to take out of a file,
//  the report of what actually landed, and the pack editors.
//

#if os(macOS)

import RunAnywhere
import SwiftUI
import UniformTypeIdentifiers

struct WorkflowExportRequest: Identifiable {
    let id = UUID()
    var selection: Set<String>
}

enum WorkflowPackEditorMode: String, Identifiable {
    /// The open graph becomes a CompositeImplementation.
    case composite
    /// A hand-written ScriptImplementation with declared capabilities.
    case script

    var id: String { rawValue }

    var title: String {
        self == .composite ? "Save as Node Pack" : "New Script Pack"
    }
}

private enum WorkflowSheetRoute: Identifiable {
    case export(WorkflowExportRequest)
    case pickImport(WorkflowBundleImportRequest)
    case importReport(WorkflowImportOutcome)
    case packEditor(WorkflowPackEditorMode)
    case nodeReference(WorkflowNodeReferenceRequest)

    var id: String {
        switch self {
        case .export(let request): return "export-\(request.id)"
        case .pickImport(let request): return "pick-\(request.id)"
        case .importReport(let outcome): return "report-\(outcome.id)"
        case .packEditor(let mode): return "editor-\(mode.id)"
        case .nodeReference(let request): return "reference-\(request.id)"
        }
    }
}

struct WorkflowBundleTransfer: ViewModifier {
    var viewModel: WorkflowEditorViewModel
    @Binding var isImporting: Bool
    @Binding var exportRequest: WorkflowExportRequest?
    @Binding var packEditor: WorkflowPackEditorMode?

    private var packStore: WorkflowPackStore { viewModel.packStore }

    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: Binding(
                    get: { packStore.pendingExport != nil },
                    set: { if !$0 { packStore.clearPendingExport() } }
                ),
                document: packStore.pendingExport,
                contentType: .runAnywhereWorkflowBundle,
                defaultFilename: packStore.pendingExportName,
                onCompletion: packStore.finishExport
            )
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.runAnywhereWorkflowBundle]
            ) { result in
                Task { await viewModel.loadBundle(result) }
            }
            .sheet(item: Binding(get: { route }, set: { if $0 == nil { dismissAll() } })) { route in
                sheet(for: route)
            }
    }

    /// One derived route rather than four independent `.sheet` modifiers, which
    /// on the same view would fight over which one is presented.
    private var route: WorkflowSheetRoute? {
        if let exportRequest { return .export(exportRequest) }
        if let pending = packStore.pendingImport { return .pickImport(pending) }
        if let outcome = packStore.importOutcome { return .importReport(outcome) }
        if let packEditor { return .packEditor(packEditor) }
        if let reference = viewModel.referenceRequest { return .nodeReference(reference) }
        return nil
    }

    private func dismissAll() {
        exportRequest = nil
        packEditor = nil
        viewModel.referenceRequest = nil
        packStore.clearPendingImport()
        packStore.clearImportOutcome()
    }

    @ViewBuilder
    private func sheet(for route: WorkflowSheetRoute) -> some View {
        switch route {
        case .export(let request):
            WorkflowExportPicker(viewModel: viewModel, request: request)
        case .pickImport(let request):
            WorkflowImportPicker(viewModel: viewModel, request: request)
        case .importReport(let outcome):
            WorkflowImportReport(outcome: outcome)
        case .packEditor(let mode):
            WorkflowPackEditorSheet(viewModel: viewModel, mode: mode)
        case .nodeReference(let request):
            WorkflowNodeReferenceSheet(focus: request.focus) {
                viewModel.referenceRequest = nil
            }
        }
    }
}

// MARK: - Export

private struct WorkflowExportPicker: View {
    var viewModel: WorkflowEditorViewModel
    let request: WorkflowExportRequest

    @Environment(\.dismiss)
    private var dismiss
    @State private var selection: Set<String> = []

    var body: some View {
        WorkflowSheetShell(
            title: "Export Workflows",
            message: "Every node pack the chosen workflows use is bundled with them.",
            confirm: selection.count == 1 ? "Export 1 Workflow" : "Export \(selection.count) Workflows",
            isConfirmEnabled: !selection.isEmpty,
            showsCancel: true
        ) {
            List {
                if !isCurrentSaved {
                    row(
                        id: viewModel.workflowID,
                        name: viewModel.workflowName,
                        detail: "Open, not saved yet"
                    )
                }
                ForEach(viewModel.savedWorkflows, id: \.id) { summary in
                    row(
                        id: summary.id,
                        name: summary.name,
                        detail: "\(summary.nodeCount) node\(summary.nodeCount == 1 ? "" : "s")"
                    )
                }
            }
        } onCancel: {
            dismiss()
        } onConfirm: {
            let chosen = selection
            dismiss()
            Task { await viewModel.exportBundle(workflowIDs: chosen) }
        }
        .onAppear { selection = request.selection }
    }

    private var isCurrentSaved: Bool {
        viewModel.savedWorkflows.contains { $0.id == viewModel.workflowID }
    }

    private func row(id: String, name: String, detail: String) -> some View {
        Toggle(isOn: Binding(
            get: { selection.contains(id) },
            set: { include in
                if include { selection.insert(id) } else { selection.remove(id) }
            }
        )) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(name.isEmpty ? id : name)
                    .appType(.body)
                Text(detail)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

// MARK: - Import

private struct WorkflowImportPicker: View {
    var viewModel: WorkflowEditorViewModel
    let request: WorkflowBundleImportRequest

    @Environment(\.dismiss)
    private var dismiss
    @State private var workflows: Set<String> = []
    @State private var packs: Set<String> = []

    private var chosenCount: Int { workflows.count + packs.count }

    var body: some View {
        WorkflowSheetShell(
            title: "Import from \(request.fileName)",
            message: "Take the items you want. A workflow imported without its pack still " +
                "opens; the pack node shows as a placeholder until the pack is installed.",
            confirm: chosenCount == 1 ? "Import 1 Item" : "Import \(chosenCount) Items",
            isConfirmEnabled: chosenCount > 0,
            showsCancel: true
        ) {
            List {
                if !request.bundle.workflows.isEmpty {
                    Section("Workflows") {
                        ForEach(request.bundle.workflows, id: \.id) { document in
                            workflowRow(document)
                        }
                    }
                }
                if !request.bundle.packs.isEmpty {
                    Section("Node Packs") {
                        ForEach(request.bundle.packs, id: \.id) { pack in
                            packRow(pack)
                        }
                    }
                }
            }
        } onCancel: {
            dismiss()
        } onConfirm: {
            let chosenWorkflows = workflows
            let chosenPacks = packs
            // Closed before the import runs, so the report presents into a free
            // slot rather than replacing a sheet that is still up.
            dismiss()
            Task {
                await viewModel.importBundle(
                    request, workflows: chosenWorkflows, packs: chosenPacks
                )
            }
        }
        .onAppear {
            // A composite pack composes nodes this app already has, so it is
            // pre-selected. A script pack carries JavaScript and starts off:
            // taking it is an explicit act, made after reading what it may reach.
            workflows = Set(request.bundle.workflows.map(\.id))
            packs = Set(request.bundle.packs.filter { !$0.isScript }.map(\.id))
        }
    }

    private func workflowRow(_ document: RAWorkflowDocument) -> some View {
        Toggle(isOn: membership(document.id, in: $workflows)) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(document.name.isEmpty ? document.id : document.name)
                    .appType(.body)
                Text("\(document.nodes.count) node\(document.nodes.count == 1 ? "" : "s")")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func packRow(_ pack: RANodePack) -> some View {
        Toggle(isOn: membership(pack.id, in: $packs)) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Image(systemName: pack.resolvedSymbol)
                        .glyph(Glyph.xs, weight: .semibold)
                        .foregroundStyle(pack.accent)
                    Text(pack.displayName)
                        .appType(.body)
                }
                Text(pack.subtitle)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                capabilityNotice(pack)
            }
        }
    }

    @ViewBuilder
    private func capabilityNotice(_ pack: RANodePack) -> some View {
        if pack.isScript {
            let granted = pack.capabilities.grantedSummaries
            VStack(alignment: .leading, spacing: Space.hair) {
                Label("Runs JavaScript on this machine", systemImage: "exclamationmark.shield.fill")
                    .appType(.chip)
                    .foregroundStyle(AppColors.warning)
                if granted.isEmpty {
                    Text("Asks for no extra access.")
                        .appType(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    ForEach(granted, id: \.self) { line in
                        Text("• " + line)
                            .appType(.caption)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
            .padding(Space.sm)
            .background(
                AppColors.warning.opacity(0.10),
                in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            )
        } else {
            Text("Composes nodes this app already has, so it grants nothing new.")
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func membership(_ id: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { include in
                if include {
                    set.wrappedValue.insert(id)
                } else {
                    set.wrappedValue.remove(id)
                }
            }
        )
    }
}

// MARK: - Import report

private struct WorkflowImportReport: View {
    let outcome: WorkflowImportOutcome

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        WorkflowSheetShell(
            title: title,
            message: message,
            confirm: "Done",
            isConfirmEnabled: true,
            showsCancel: false
        ) {
            List {
                if !outcome.workflows.isEmpty {
                    Section("Imported Workflows") {
                        ForEach(outcome.workflows, id: \.self) { name in
                            Label(name, systemImage: "checkmark.circle.fill")
                                .appType(.body)
                                .foregroundStyle(AppColors.success)
                        }
                    }
                }
                if !outcome.packs.isEmpty {
                    Section("Imported Node Packs") {
                        ForEach(outcome.packs, id: \.self) { name in
                            Label(name, systemImage: "checkmark.circle.fill")
                                .appType(.body)
                                .foregroundStyle(AppColors.success)
                        }
                    }
                }
                if !outcome.skipped.isEmpty {
                    Section("Skipped") {
                        ForEach(Array(outcome.skipped.enumerated()), id: \.offset) { _, issue in
                            skippedRow(issue)
                        }
                    }
                }
                if !outcome.declinedPacks.isEmpty {
                    Section("Not Taken") {
                        ForEach(outcome.declinedPacks, id: \.self) { name in
                            Label {
                                Text("\(name) — left out of this import")
                                    .appType(.body)
                            } icon: {
                                Image(systemName: "minus.circle")
                                    .glyph(Glyph.sm, weight: .semibold)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
            }
        } onCancel: {
            dismiss()
        } onConfirm: {
            dismiss()
        }
    }

    private func skippedRow(_ issue: RABundleImportIssue) -> some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Label("\(issue.kindLabel) \(issue.id)", systemImage: "exclamationmark.triangle.fill")
                .appType(.body)
                .foregroundStyle(AppColors.danger)
            Text(issue.message)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var title: String {
        if outcome.importedCount == 0 { return "Nothing Imported" }
        return outcome.isClean ? "Import Finished" : "Imported with Problems"
    }

    /// A partial import says so. Reading "Import finished" over a list with a
    /// skipped item in it is how a half-imported bundle goes unnoticed.
    private var message: String {
        var parts = ["\(outcome.importedCount) item\(outcome.importedCount == 1 ? "" : "s") imported"]
        if !outcome.skipped.isEmpty {
            parts.append("\(outcome.skipped.count) skipped")
        }
        if !outcome.declinedPacks.isEmpty {
            parts.append("\(outcome.declinedPacks.count) not taken")
        }
        return parts.joined(separator: " · ") + "."
    }
}

// MARK: - Shell

/// The frame every one of these sheets uses: a title, one line of explanation,
/// scrolling content, and a fixed action row that never scrolls away.
///
/// Built on `Scaffold` rather than by hand so a sheet's bars sit on the same
/// surface, at the same height, above the same hairline as the screen it opens
/// over.
struct WorkflowSheetShell<Content: View>: View {
    let title: String
    let message: String
    let confirm: String
    let isConfirmEnabled: Bool
    let showsCancel: Bool
    @ViewBuilder var content: Content
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        Scaffold {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(title)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(message)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
        } content: {
            content
        } bottomBar: {
            HStack(spacing: Space.sm) {
                Spacer(minLength: 0)
                if showsCancel {
                    PillButton(title: "Cancel", tint: AppColors.textSecondary, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                PillButton(
                    title: confirm,
                    tint: AppColors.onBrand,
                    fill: AppColors.brand,
                    isOutlined: false,
                    isEnabled: isConfirmEnabled,
                    action: onConfirm
                )
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.lg)
        }
        .frame(
            minWidth: 460,
            idealWidth: 520,
            maxWidth: 640,
            minHeight: 360,
            idealHeight: 460,
            maxHeight: 700
        )
    }
}

#endif
