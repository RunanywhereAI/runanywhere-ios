//
//  ConnectorsSheet.swift
//  RunAnywhereAI
//
//  Connectors: the list, and the form that is generated from whichever type
//  the reader picked.
//
//  There is no per-connector screen. Every form here is rendered from the
//  field list in `ConnectorCatalog`, so a new connector type is a record in
//  that file and nothing in this one.
//

#if os(macOS)

import SwiftUI

struct ConnectorsSheet: View {
    @Bindable var store: ConnectorStore
    let onClose: () -> Void

    @State private var editing: Connector?
    @State private var isPickingType = false

    var body: some View {
        NavigationStack {
            Group {
                if store.connectors.isEmpty {
                    EmptyState(
                        symbol: "app.connected.to.app.below.fill",
                        title: "No connectors yet",
                        detail: "A connector is somewhere a workflow can reach: an API, a webhook, "
                            + "or a server already running on this Mac.",
                        actionTitle: "Add a connector"
                    ) {
                        isPickingType = true
                    }
                } else {
                    list
                }
            }
            .frame(minWidth: 520, minHeight: 420)
            .background(AppColors.background)
            .navigationTitle("Connectors")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPickingType = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .sheet(item: $editing) { connector in
            ConnectorEditor(store: store, connector: connector) { editing = nil }
        }
        .sheet(isPresented: $isPickingType) {
            ConnectorTypePicker { type in
                isPickingType = false
                editing = Connector(typeID: type.id, name: type.displayName)
            } onCancel: {
                isPickingType = false
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.connectors) { connector in
                row(connector)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = connector }
            }
        }
        .listStyle(.inset)
    }

    private func row(_ connector: Connector) -> some View {
        HStack(spacing: Space.md) {
            GlyphTile(symbol: connector.type?.symbol ?? "network")

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(connector.name)
                    .appType(.body)
                    .foregroundStyle(AppColors.textPrimary)
                Text(connector.url?.absoluteString ?? connector.type?.displayName ?? "Not configured")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.sm)

            probeStatus(connector)

            Button {
                Task { await store.probe(connector) }
            } label: {
                Text("Test")
                    .appType(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.brand)
            .disabled(store.probing.contains(connector.id))

            Button {
                store.delete(connector.id)
            } label: {
                Image(systemName: "trash")
                    .glyph(Glyph.xs, weight: .semibold)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Forget this connector and its token.")
        }
        .padding(.vertical, Space.xs)
    }

    @ViewBuilder
    private func probeStatus(_ connector: Connector) -> some View {
        if store.probing.contains(connector.id) {
            ProgressView().controlSize(.small)
        } else if let probe = store.probes[connector.id] {
            StatusTag(
                text: probe.summary,
                tint: probe.isGood ? AppColors.success : AppColors.danger
            )
            .help(probe.summary)
        }
    }
}

/// The catalogue. A list rather than a dialog: macOS silently drops buttons
/// past the third in a confirmation dialog, which quietly hid a connector type,
/// and a one-line summary per row is worth more than a bare name anyway.
private struct ConnectorTypePicker: View {
    let onPick: (ConnectorType) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List(ConnectorCatalog.all) { type in
                HStack(spacing: Space.md) {
                    GlyphTile(symbol: type.symbol)

                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(type.displayName)
                            .appType(.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(type.summary)
                            .appType(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.xs)
                .contentShape(Rectangle())
                .onTapGesture { onPick(type) }
            }
            .listStyle(.inset)
            .frame(minWidth: 460, minHeight: 320)
            .background(AppColors.background)
            .navigationTitle("What are you connecting to?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

/// The generated form. Every control comes from the type's field list.
private struct ConnectorEditor: View {
    @Bindable var store: ConnectorStore
    @State var connector: Connector
    let onClose: () -> Void

    @State private var secret = ""
    @State private var didLoadSecret = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $connector.name)
                } footer: {
                    if let summary = connector.type?.summary {
                        Text(summary)
                            .appType(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Section(connector.type?.displayName ?? "Settings") {
                    ForEach(connector.type?.fields ?? []) { field in
                        control(field)
                    }
                }

                if let probe = store.probes[connector.id] {
                    Section("Last test") {
                        Text(probe.summary)
                            .appType(.caption)
                            .foregroundStyle(probe.isGood ? AppColors.success : AppColors.danger)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 460, minHeight: 380)
            .navigationTitle(connector.name.isEmpty ? "New connector" : connector.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        store.save(connector, secret: secret)
                        onClose()
                    }
                    .disabled(connector.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .automatic) {
                    Button("Test") {
                        store.save(connector, secret: secret)
                        Task { await store.probe(connector) }
                    }
                    .disabled(store.probing.contains(connector.id))
                }
            }
        }
        .task {
            // Once: reopening the sheet should not overwrite a token the reader
            // has just typed with the one already stored.
            guard !didLoadSecret else { return }
            secret = store.secret(for: connector.id)
            didLoadSecret = true
        }
    }

    @ViewBuilder
    private func control(_ field: ConnectorField) -> some View {
        switch field {
        case let .text(key, label, placeholder, _):
            TextField(label, text: binding(key), prompt: Text(placeholder))
        case let .secret(_, label, hint):
            // Two rows, not a VStack in one: a Form lays a labelled control out
            // across the row, and nesting it collapsed the field to nothing.
            SecureField(label, text: $secret)
            Text(hint)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
        case let .number(key, label, _):
            TextField(label, text: binding(key))
                .monospacedDigit()
        case let .toggle(key, label, _):
            Toggle(label, isOn: Binding(
                get: { connector.value(key) == "true" },
                set: { connector.values[key] = $0 ? "true" : "false" }
            ))
        case let .choice(key, label, options, _):
            Picker(label, selection: binding(key)) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(
            get: { connector.value(key) },
            set: { connector.values[key] = $0 }
        )
    }
}

#endif
