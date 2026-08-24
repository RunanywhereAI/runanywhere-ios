//
//  WorkflowCanvasOverlays.swift
//  RunAnywhereAI
//
//  What floats above the graph: the zoom readout, the problem and run chips,
//  and the one-line hint. None of it is part of the canvas — it reads the
//  camera and the run state and never touches the graph — so it is applied as
//  one modifier rather than woven into the surface.
//

#if os(macOS)

import RunAnywhere
import SwiftUI

struct WorkflowCanvasOverlays: ViewModifier {
    var viewModel: WorkflowEditorViewModel
    @Binding var camera: WorkflowCanvasCamera
    let viewportSize: CGSize
    let onFitToContent: () -> Void
    let onReveal: (String) -> Void

    @State private var isShowingIssues = false

    private var viewportCenter: CGPoint {
        CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) { zoomControls }
            .overlay(alignment: .top) { statusStrip }
            .overlay(alignment: .bottom) { hintCapsule }
    }

    private var zoomControls: some View {
        HStack(spacing: Space.hair) {
            zoomButton("minus", "Zoom out (⌘−)") {
                withAnimation(.easeOut(duration: 0.18)) {
                    camera.magnify(by: 1 / 1.2, about: viewportCenter)
                }
            }
            .keyboardShortcut("-", modifiers: .command)

            Text(Double(camera.zoom).formatted(.percent.precision(.fractionLength(0))))
                .appType(.monoMetric)
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 48)

            zoomButton("plus", "Zoom in (⌘+)") {
                withAnimation(.easeOut(duration: 0.18)) {
                    camera.magnify(by: 1.2, about: viewportCenter)
                }
            }
            .keyboardShortcut("=", modifiers: .command)

            Divider().frame(height: Glyph.xs)

            zoomButton("arrow.down.left.and.arrow.up.right", "Fit to content (⇧⌘0)") {
                onFitToContent()
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])

            zoomButton("1.circle", "Actual size (⌘0)") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    camera.magnify(by: 1 / camera.zoom, about: viewportCenter)
                }
            }
            .keyboardShortcut("0", modifiers: .command)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .card(radius: Radius.pill)
        .padding(Space.md)
    }

    private func zoomButton(
        _ symbol: String, _ help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: Space.xl, height: Space.lg + Space.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var statusStrip: some View {
        HStack(spacing: Space.sm) {
            if !viewModel.issues.isEmpty {
                issuesChip
            }
            runChip
        }
        .padding(.top, Space.md)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.issues)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.runPhase)
    }

    private var issuesChip: some View {
        Button {
            isShowingIssues = true
        } label: {
            Label(
                "\(viewModel.issues.count) problem\(viewModel.issues.count == 1 ? "" : "s")",
                systemImage: "exclamationmark.triangle.fill"
            )
            .appType(.chip)
            .foregroundStyle(AppColors.danger)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .card(radius: Radius.pill)
        .popover(isPresented: $isShowingIssues, arrowEdge: .bottom) {
            issuesList
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var issuesList: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(viewModel.issues) { issue in
                Button {
                    isShowingIssues = false
                    if let nodeID = issue.nodeID {
                        viewModel.select(nodeID, additive: false)
                        onReveal(nodeID)
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.danger)
                        Text(issue.message)
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    .appType(.caption)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(issue.nodeID == nil)
            }
        }
        .padding(Space.lg)
        .frame(minWidth: 260, maxWidth: 360, alignment: .leading)
    }

    @ViewBuilder private var runChip: some View {
        switch viewModel.runPhase {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: Space.sm) {
                Circle()
                    .fill(AppColors.brand)
                    .frame(width: Space.sm, height: Space.sm)
                    .phaseAnimator([0.3, 1.0]) { view, opacity in
                        view.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.6) }
                Text("Running…")
                    .appType(.chip)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .card(radius: Radius.pill)
            .transition(.move(edge: .top).combined(with: .opacity))
        case let .finished(state, duration):
            Label(finishSummary(state, duration), systemImage: finishSymbol(state))
                .appType(.chip)
                .foregroundStyle(finishColor(state))
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.xs)
                .card(radius: Radius.pill)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func finishSummary(_ state: RAWorkflowRunState, _ duration: TimeInterval) -> String {
        let seconds = duration.formatted(.number.precision(.fractionLength(1)))
        switch state {
        case .succeeded: return "Finished in \(seconds)s"
        case .failed: return "Failed after \(seconds)s"
        case .cancelled: return "Cancelled"
        case .running, .unspecified, .UNRECOGNIZED: return "Run ended"
        }
    }

    private func finishSymbol(_ state: RAWorkflowRunState) -> String {
        switch state {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "flag.checkered"
        }
    }

    private func finishColor(_ state: RAWorkflowRunState) -> Color {
        switch state {
        case .succeeded: AppColors.success
        case .failed: AppColors.danger
        default: AppColors.textSecondary
        }
    }

    @ViewBuilder private var hintCapsule: some View {
        if viewModel.draft != nil {
            hint("link", "Drop on a highlighted input · ⎋ cancels")
        } else if viewModel.graph.nodes.count <= 1 && viewModel.graph.edges.isEmpty {
            hint("hand.draw", "Drag nodes in from the palette, then drag an output dot to an input")
        }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .appType(.caption)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .card(radius: Radius.pill)
            .padding(.bottom, Space.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#endif
