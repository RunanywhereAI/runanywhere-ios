//
//  WorkflowScreen.swift
//  RunAnywhereAI
//
//  The workflow builder shell: palette, canvas, inspector, and the bar that
//  saves and runs. The canvas itself lives in WorkflowCanvasSurface; this view
//  owns the camera and everything that floats above the graph.
//
//  It takes the scaffold's content area and its top bar, and nothing more —
//  the window chrome belongs to the app, not to this screen.
//

#if os(macOS)

import RunAnywhere
import SwiftUI
import UniformTypeIdentifiers

struct WorkflowScreen: View {
    @State private var viewModel = WorkflowEditorViewModel()
    @State private var camera = WorkflowCanvasCamera()
    @State private var viewportSize = CGSize.zero
    @State private var isImporting = false
    @State private var exportRequest: WorkflowExportRequest?
    @State private var packEditor: WorkflowPackEditorMode?
    @Environment(\.undoManager)
    private var undoManager

    var body: some View {
        Scaffold {
            TopBar(
                leading: AnyView(documentControls),
                center: AnyView(nameField),
                trailing: AnyView(runControls)
            )
        } content: {
            editor
        }
        .task {
            // Idempotent: the scheduler is app-owned, so opening the editor
            // only makes sure it is up, never restarts it.
            WorkflowScheduler.shared.start()
            await viewModel.refreshLibrary()
            await viewModel.refreshCatalogs()
            viewModel.scheduleValidation()
        }
        .onAppear { viewModel.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in viewModel.undoManager = manager }
        .alert(
            "Workflow",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { viewModel.errorMessage = nil } },
            message: { Text(viewModel.errorMessage ?? "") }
        )
        .alert(
            "Node Packs",
            isPresented: Binding(
                get: { viewModel.packStore.errorMessage != nil },
                set: { if !$0 { viewModel.packStore.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { viewModel.packStore.errorMessage = nil } },
            message: { Text(viewModel.packStore.errorMessage ?? "") }
        )
        .modifier(WorkflowBundleTransfer(
            viewModel: viewModel,
            isImporting: $isImporting,
            exportRequest: $exportRequest,
            packEditor: $packEditor
        ))
    }

    private var editor: some View {
        HSplitView {
            WorkflowPalette(viewModel: viewModel) { item in
                addFromPalette(item)
            } onLoad: { workflowID in
                open(workflowID)
            } onExport: { workflowID in
                exportRequest = WorkflowExportRequest(selection: [workflowID])
            }
            .frame(minWidth: 200, idealWidth: 224, maxWidth: 280)

            canvas
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            WorkflowInspectorPane(viewModel: viewModel, onReveal: center(on:))
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 440)
        }
    }

    // MARK: - Canvas + overlays

    private var canvas: some View {
        WorkflowCanvasSurface(
            viewModel: viewModel,
            camera: $camera,
            viewportSize: $viewportSize
        )
        .dropDestination(for: WorkflowPaletteItem.self) { items, location in
            var placed = false
            for item in items {
                let position = camera.toGraph(location)
                let centered = CGPoint(
                    x: position.x - WorkflowCanvasMetrics.defaultCardSize.width / 2,
                    y: position.y - WorkflowCanvasMetrics.defaultCardSize.height / 2
                )
                let added = withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
                    place(item, at: centered)
                }
                if added != nil { placed = true }
            }
            return placed
        }
        .modifier(WorkflowCanvasOverlays(
            viewModel: viewModel,
            camera: $camera,
            viewportSize: viewportSize,
            onFitToContent: fitToContent,
            onReveal: center(on:)
        ))
    }

    // MARK: - Top bar

    private var documentControls: some View {
        HStack(spacing: Space.xs) {
            BarButton(systemImage: "doc.badge.plus") {
                viewModel.newWorkflow()
                fitToContent()
            }
            .help("New workflow")

            Menu {
                Button("Export…") {
                    exportRequest = WorkflowExportRequest(selection: [viewModel.workflowID])
                }
                Button("Import…") { isImporting = true }
                Divider()
                Button("Save as Node Pack…") { packEditor = .composite }
                Button("New Script Pack…") { packEditor = .script }
            } label: {
                Image(systemName: "shippingbox")
                    .glyph(Glyph.md)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: Measure.hitTarget)
            .help("Export or import a bundle, or turn this graph into a node pack")
        }
    }

    private var nameField: some View {
        TextField("Workflow name", text: $viewModel.workflowName)
            .textFieldStyle(.plain)
            .appType(.cardTitle)
            .foregroundStyle(AppColors.textPrimary)
            .multilineTextAlignment(.center)
            .frame(width: 240)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .background(
                AppColors.surfaceMuted,
                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            )
    }

    private var runControls: some View {
        let canRun = !viewModel.graph.nodes.isEmpty
        return HStack(spacing: Space.xs) {
            BarButton(
                systemImage: "arrow.uturn.backward",
                tint: enabledTint(viewModel.canUndo, AppColors.textSecondary)
            ) { viewModel.undo() }
                .help("Undo (⌘Z)")
                .disabled(!viewModel.canUndo)

            BarButton(
                systemImage: "arrow.uturn.forward",
                tint: enabledTint(viewModel.canRedo, AppColors.textSecondary)
            ) { viewModel.redo() }
                .help("Redo (⇧⌘Z)")
                .disabled(!viewModel.canRedo)

            BarButton(systemImage: "square.and.arrow.down") {
                Task { await viewModel.save() }
            }
            .help("Save workflow (⌘S)")
            .keyboardShortcut("s", modifiers: .command)

            if viewModel.isRunning {
                BarButton(systemImage: "stop.fill", tint: AppColors.danger) {
                    viewModel.cancelRun()
                }
                .help("Cancel the run")
            } else {
                BarButton(
                    systemImage: "play.fill",
                    tint: enabledTint(canRun, AppColors.brand)
                ) {
                    Task { await viewModel.run() }
                }
                .help("Save and run (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!canRun)
            }
        }
    }

    /// `.disabled` alone leaves a plain button looking live, so the tint says so
    /// too rather than leaving the user clicking a control that does nothing.
    private func enabledTint(_ isEnabled: Bool, _ tint: Color) -> Color {
        isEnabled ? tint : AppColors.textTertiary
    }

    // MARK: - Camera moves

    private var viewportCenter: CGPoint {
        CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    private func fitToContent() {
        guard let bounds = viewModel.graph.boundingRect(), viewportSize != .zero else {
            withAnimation(.easeInOut(duration: 0.25)) { camera = WorkflowCanvasCamera() }
            return
        }
        let padded = bounds.insetBy(dx: -64, dy: -64)
        let zoom = min(
            max(
                min(viewportSize.width / padded.width, viewportSize.height / padded.height),
                WorkflowCanvasMetrics.minZoom
            ),
            1.25
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            camera.zoom = zoom
            camera.pan = CGSize(
                width: viewportCenter.x - padded.midX * zoom,
                height: viewportCenter.y - padded.midY * zoom
            )
        }
    }

    private func center(on nodeID: String) {
        guard let node = viewModel.graph.node(nodeID) else { return }
        let frame = WorkflowCanvasMetrics.cardFrame(of: node)
        withAnimation(.easeInOut(duration: 0.25)) {
            camera.pan = CGSize(
                width: viewportCenter.x - frame.midX * camera.zoom,
                height: viewportCenter.y - frame.midY * camera.zoom
            )
        }
    }

    private func addFromPalette(_ item: WorkflowPaletteItem) {
        let center = camera.toGraph(viewportCenter)
        let cascade = CGFloat(viewModel.graph.nodes.count % 5) * 28
        let position = CGPoint(
            x: center.x - WorkflowCanvasMetrics.defaultCardSize.width / 2 + cascade,
            y: center.y - WorkflowCanvasMetrics.defaultCardSize.height / 2 + cascade
        )
        withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
            _ = place(item, at: position)
        }
    }

    /// A pack node's shape is mirrored from the pack right here, at drop time,
    /// the same way a tool node mirrors its tool's arguments.
    private func place(_ item: WorkflowPaletteItem, at position: CGPoint) -> WorkflowNode? {
        switch item {
        case .kind(let kind):
            return viewModel.addNode(kind, at: position)
        case .pack(let id):
            guard let pack = viewModel.packStore.pack(id) else {
                viewModel.errorMessage = "That node pack is no longer installed."
                return nil
            }
            return viewModel.addPackNode(pack, at: position)
        }
    }

    private func open(_ workflowID: String) {
        Task {
            await viewModel.load(id: workflowID)
            fitToContent()
        }
    }
}

#endif
