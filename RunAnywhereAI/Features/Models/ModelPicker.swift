import SwiftUI

struct ModelPickerList: View {
    let models: [InstalledModel]
    let activeID: String?
    let onSelect: (InstalledModel) -> Void
    let onManage: () -> Void

    private var groups: [(publisher: String, models: [InstalledModel])] {
        Dictionary(grouping: models, by: \.publisher)
            .map { (publisher: $0.key, models: $0.value) }
            .sorted { $0.publisher < $1.publisher }
    }

    var body: some View {
        VStack(spacing: 0) {
            if models.isEmpty {
                EmptyState(
                    symbol: "square.stack.3d.up.slash",
                    title: "Nothing downloaded yet",
                    detail: "No model of this kind is on the device. Open Manage Models and download one first.",
                    actionTitle: "Open Manage Models",
                    action: onManage
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(groups, id: \.publisher) { group in
                            Text(group.publisher)
                                .appType(.overline)
                                .textCase(.uppercase)
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.horizontal, Space.md)
                                .padding(.top, Space.sm)

                            ForEach(group.models) { model in
                                row(model)
                            }
                        }
                    }
                    .padding(.vertical, Space.sm)
                    .padding(.horizontal, Space.sm)
                }
            }

            Divider().overlay(AppColors.border)

            Button(action: onManage) {
                HStack(spacing: Space.md) {
                    Image(systemName: "square.stack.3d.up")
                        .glyph(Glyph.xs, weight: .semibold)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: Glyph.lg)

                    Text("Manage models…")
                        .appType(.secondary)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .glyph(Glyph.xs)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(AppColors.surface)
    }

    private func row(_ model: InstalledModel) -> some View {
        let isActive = model.id == activeID
        // A model the device refuses stays listed rather than vanishing: it is
        // still the model the user came looking for, and a row that explains
        // itself answers more than an empty list does.
        let blocked = model.unavailableReason
        return Button {
            onSelect(model)
        } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(model.label)
                        .appType(.secondary)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(blocked == nil ? AppColors.textPrimary : AppColors.textSecondary)
                        .lineLimit(1)

                    if let blocked {
                        Text(blocked)
                            .appType(.caption)
                            .foregroundStyle(AppColors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: Space.xs) {
                            Text("\(model.sizeLabel) · \(model.backend)")
                                .appType(.caption)
                                .foregroundStyle(AppColors.textSecondary)

                            if model.purpose == .vision {
                                CapabilityTag(symbol: "eye", title: "Vision", tint: AppColors.success)
                            }
                            if model.supportsTools {
                                CapabilityTag(symbol: "wrench.adjustable", title: "Tools", tint: AppColors.brand)
                            }
                            if model.supportsThinking {
                                CapabilityTag(symbol: "brain", title: "Thinking", tint: AppColors.info)
                            }
                        }
                    }
                }

                Spacer(minLength: Space.sm)

                if blocked != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .glyph(Glyph.xs, weight: .semibold)
                        .foregroundStyle(AppColors.warning)
                } else if isActive {
                    Image(systemName: "checkmark")
                        .glyph(Glyph.xs, weight: .semibold)
                        .foregroundStyle(AppColors.brand)
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isActive ? AppColors.brandMuted : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked != nil)
        .accessibilityHint(blocked ?? "")
    }
}

extension View {
    func modelPicker(
        isPresented: Binding<Bool>,
        models: [InstalledModel],
        activeID: String?,
        onSelect: @escaping (InstalledModel) -> Void,
        onManage: @escaping () -> Void
    ) -> some View {
        modifier(
            ModelPickerPresentation(
                isPresented: isPresented,
                models: models,
                activeID: activeID,
                onSelect: onSelect,
                onManage: onManage
            )
        )
    }
}

private struct ModelPickerPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let models: [InstalledModel]
    let activeID: String?
    let onSelect: (InstalledModel) -> Void
    let onManage: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(isPresented: $isPresented, arrowEdge: .bottom) {
            list
                .frame(width: 320, height: 420)
        }
        #else
        content.sheet(isPresented: $isPresented) {
            NavigationStack {
                list
                    .navigationTitle("Model")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isPresented = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        #endif
    }

    private var list: some View {
        ModelPickerList(
            models: models,
            activeID: activeID,
            onSelect: { model in
                onSelect(model)
                isPresented = false
            },
            onManage: {
                isPresented = false
                onManage()
            }
        )
    }
}


/// A one-word capability marker on a model row. Deliberately smaller than the
/// row's own text so a list of them still scans as a list of models.
struct CapabilityTag: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .glyph(Glyph.xs - 4, weight: .semibold)
            Text(title)
                .appType(.caption)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Space.xs)
        .frame(height: 16)
        .background(Capsule().fill(tint.opacity(0.12)))
        .accessibilityLabel("Supports \(title.lowercased())")
    }
}
