//
//  WorkflowNodeReferenceSheet.swift
//  RunAnywhereAI
//
//  The node reference: a searchable list of every node kind grouped the way the
//  palette groups them, and a detail pane for the selected one. Opened from the
//  editor's top bar, and from the inspector for whichever node is selected.
//
//  All of its text comes from WorkflowNodeReferenceContent. This file decides
//  layout and nothing else.
//

#if os(macOS)

import SwiftUI

struct WorkflowNodeReferenceSheet: View {
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedID: String

    init(focus: WorkflowNodeKind?, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _selectedID = State(initialValue: (focus ?? .manualTrigger).rawValue)
    }

    private var matches: [WorkflowNodeReference] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return WorkflowNodeReference.all }
        return WorkflowNodeReference.all.filter { $0.searchText.contains(needle) }
    }

    private var selected: WorkflowNodeReference? {
        matches.first { $0.id == selectedID } ?? matches.first
    }

    var body: some View {
        Scaffold {
            TopBar(
                title: "Node Reference",
                subtitle: "What each node does, and what it does with its inputs.",
                trailing: AnyView(
                    PillButton(title: "Done", tint: AppColors.textSecondary, action: onClose)
                        .keyboardShortcut(.cancelAction)
                )
            )
        } content: {
            HStack(spacing: 0) {
                sidebar
                Divider().overlay(AppColors.border)
                detail
            }
        }
        .frame(
            minWidth: 760,
            idealWidth: 900,
            maxWidth: 1080,
            minHeight: 480,
            idealHeight: 620,
            maxHeight: 820
        )
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)

            Divider().overlay(AppColors.border)

            if matches.isEmpty {
                EmptyState(
                    symbol: "magnifyingglass",
                    title: "Nothing matches",
                    detail: "Search node names, settings, ports and the notes under each one."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.lg, pinnedViews: []) {
                        ForEach(groups, id: \.category) { group in
                            ScreenSection(title: group.category.rawValue) {
                                VStack(spacing: Space.hair) {
                                    ForEach(group.entries) { entry in
                                        row(entry)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.md)
                }
            }
        }
        .frame(width: 250)
        .background(AppColors.background)
    }

    private var groups: [(category: WorkflowNodeCategory, entries: [WorkflowNodeReference])] {
        let found = matches
        return WorkflowNodeCategory.allCases.compactMap { category in
            let entries = found.filter { $0.category == category }
            return entries.isEmpty ? nil : (category, entries)
        }
    }

    private var searchField: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .glyph(Glyph.xs)
                .foregroundStyle(AppColors.textTertiary)

            TextField("Search nodes", text: $query)
                .textFieldStyle(.plain)
                .appType(.body)
                .foregroundStyle(AppColors.textPrimary)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .glyph(Glyph.xs)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, Space.md)
        .frame(height: Control.pill)
        .background(
            AppColors.surfaceMuted,
            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        )
    }

    private func row(_ entry: WorkflowNodeReference) -> some View {
        let isSelected = entry.id == selected?.id
        return Button {
            withAnimation(Motion.quick) { selectedID = entry.id }
        } label: {
            HStack(spacing: Space.sm) {
                WorkflowIconWell(symbol: entry.systemImage, tint: entry.category.accent)

                Text(entry.title)
                    .appType(.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(
                isSelected ? AppColors.brandMuted : Color.clear,
                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        if let selected {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header(selected)

                    Text(selected.summary)
                        .appType(.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    inputs(selected)
                    outputs(selected)
                    example(selected)
                    notes(selected)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.xl)
            }
            .frame(maxWidth: .infinity)
            .background(AppColors.background)
        } else {
            EmptyState(
                symbol: "doc.text.magnifyingglass",
                title: "Pick a node",
                detail: "Choose one on the left to read what it does."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background)
        }
    }

    private func header(_ entry: WorkflowNodeReference) -> some View {
        HStack(spacing: Space.md) {
            GlyphTile(
                symbol: entry.systemImage,
                tint: entry.category.accent,
                wash: entry.category.accent.opacity(0.14)
            )

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(entry.title)
                    .appType(.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(entry.category.rawValue)
                    .appType(.meta)
                    .foregroundStyle(entry.category.accent)
            }

            Spacer(minLength: 0)
        }
    }

    private func inputs(_ entry: WorkflowNodeReference) -> some View {
        ScreenSection(title: "Inputs") {
            VStack(alignment: .leading, spacing: Space.md) {
                if entry.inputPorts.isEmpty {
                    prose("No input ports. Nothing on the canvas can connect into this node.")
                } else {
                    ForEach(entry.inputPorts) { port in
                        portRow(port, dot: AppColors.textTertiary)
                    }
                }

                if !entry.settings.isEmpty {
                    Divider().overlay(AppColors.border)
                    ForEach(entry.settings) { setting in
                        VStack(alignment: .leading, spacing: Space.hair) {
                            Text(setting.label)
                                .appType(.cardTitle)
                                .foregroundStyle(AppColors.textPrimary)
                            prose(setting.detail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func outputs(_ entry: WorkflowNodeReference) -> some View {
        ScreenSection(title: "Outputs") {
            VStack(alignment: .leading, spacing: Space.md) {
                prose(entry.emits)
                Divider().overlay(AppColors.border)
                ForEach(entry.outputPorts) { port in
                    portRow(port, dot: outputTint(port.name))
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    /// Named ports take the colour the canvas draws them in, so the reference
    /// and the graph agree on which dot is which. Anything descriptive rather
    /// than literal falls back to the ordinary output tint.
    private func outputTint(_ name: String) -> Color {
        WorkflowOutputPort(rawValue: name)?.tint ?? AppColors.brand
    }

    private func portRow(_ port: WorkflowReferencePort, dot: Color) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Circle()
                .fill(dot)
                .frame(width: Space.sm, height: Space.sm)
                .padding(.top, Space.xs)

            VStack(alignment: .leading, spacing: Space.hair) {
                HStack(spacing: Space.sm) {
                    Text(port.name)
                        .appType(.mono)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(port.role.label)
                        .appType(.chip)
                        .foregroundStyle(AppColors.textSecondary)
                }
                prose(port.detail)
            }

            Spacer(minLength: 0)
        }
    }

    private func example(_ entry: WorkflowNodeReference) -> some View {
        ScreenSection(title: "Example") {
            VStack(alignment: .leading, spacing: Space.sm) {
                prose(entry.example.caption)

                Text(entry.example.snippet)
                    .appType(.mono)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.md)
                    .background(
                        AppColors.surfaceMuted,
                        in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    )
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    @ViewBuilder
    private func notes(_ entry: WorkflowNodeReference) -> some View {
        if !entry.notes.isEmpty {
            ScreenSection(title: "Worth knowing") {
                VStack(alignment: .leading, spacing: Space.md) {
                    ForEach(Array(entry.notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .top, spacing: Space.sm) {
                            Image(systemName: "info.circle")
                                .glyph(Glyph.xs, weight: .semibold)
                                .foregroundStyle(AppColors.textTertiary)
                                .padding(.top, Space.hair)
                            prose(note)
                        }
                    }
                }
                .padding(Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }

    private func prose(_ text: String) -> some View {
        Text(text)
            .appType(.secondary)
            .foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
