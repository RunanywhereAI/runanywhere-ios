//
//  WorkflowTemplatePicker.swift
//  RunAnywhereAI
//
//  What "New Workflow" opens: a blank canvas first, then the built-in
//  templates grouped by what they are for. Picking one hands its graph back
//  to the editor as a fresh unsaved document.
//

import SwiftUI

struct WorkflowTemplatePicker: View {
    let onPick: (WorkflowTemplate?) -> Void

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        #if os(macOS)
        shell.frame(
            minWidth: 620,
            idealWidth: 760,
            maxWidth: 900,
            minHeight: 460,
            idealHeight: 620,
            maxHeight: 820
        )
        #else
        shell
        #endif
    }

    private var shell: some View {
        Scaffold {
            header
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    blankCard

                    ForEach(WorkflowTemplateLibrary.categories) { category in
                        ScreenSection(title: category.rawValue) {
                            grid(WorkflowTemplateLibrary.templates(in: category))
                        }
                    }
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.lg)
            }
        } bottomBar: {
            HStack(spacing: Space.sm) {
                Spacer(minLength: 0)
                PillButton(title: "Cancel", tint: AppColors.textSecondary) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Space.lg)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Text("New workflow")
                .appType(.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
            Text("Start from a blank canvas, or from one that already does a job.")
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
    }

    private func grid(_ templates: [WorkflowTemplate]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 280), spacing: Space.md)],
            spacing: Space.md
        ) {
            ForEach(templates) { template in
                card(template)
            }
        }
    }

    private var blankCard: some View {
        Button {
            choose(nil)
        } label: {
            HStack(spacing: Space.md) {
                GlyphTile(symbol: "plus", tint: AppColors.brand, wash: AppColors.brandMuted)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text("Blank workflow")
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("An empty canvas with the trigger already placed.")
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .glyph(Glyph.xs)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func card(_ template: WorkflowTemplate) -> some View {
        Button {
            choose(template)
        } label: {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.md) {
                    GlyphTile(
                        symbol: template.systemImage,
                        tint: AppColors.accent,
                        wash: AppColors.accentMuted
                    )

                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(template.name)
                            .appType(.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(template.purpose)
                            .appType(.meta)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)
                }

                chainRow(template)
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(template.chainDescription)
        .accessibilityLabel(
            "\(template.name). \(template.purpose) Builds \(template.chainDescription)."
        )
    }

    /// The chain as its nodes' own symbols, in their palette colours, so a
    /// card carries the shape of the graph it is about to draw.
    private func chainRow(_ template: WorkflowTemplate) -> some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(template.chain.enumerated()), id: \.offset) { index, kind in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .glyph(Glyph.xs)
                        .foregroundStyle(AppColors.textTertiary)
                }
                WorkflowIconWell(symbol: kind.systemImage, tint: kind.category.accent)
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private func choose(_ template: WorkflowTemplate?) {
        onPick(template)
        dismiss()
    }
}

extension View {
    func workflowTemplatePicker(
        isPresented: Binding<Bool>,
        onPick: @escaping (WorkflowTemplate?) -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            WorkflowTemplatePicker(onPick: onPick)
        }
    }
}
