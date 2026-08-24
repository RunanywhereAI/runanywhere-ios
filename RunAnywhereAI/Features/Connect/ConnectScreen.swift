#if os(macOS)
import SwiftUI

struct ConnectScreen: View {
    @Environment(ModelStore.self) private var store
    @State private var model = ConnectHostModel.shared

    private var candidates: [InstalledModel] {
        ConnectHostModel.candidates(in: store)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header

                if model.isHosting {
                    ScreenSection(title: "Connected") { clients }
                } else {
                    ScreenSection(title: "Model") { picker }
                }

                ScreenSection(title: "Activity") { activity }

                Text("The first time you host, macOS asks for permission to find devices on the local network.")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.lg)
            .measured()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top, spacing: Space.md) {
                GlyphTile(
                    symbol: "antenna.radiowaves.left.and.right",
                    size: Measure.hitTarget,
                    glyphSize: Glyph.lg
                )

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(model.hostName)
                        .appType(.sectionTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Space.sm)

                statusBadge
            }

            HStack(spacing: Space.sm) {
                hostButton

                if model.isStarting {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)

                if let startedAt = model.startedAt {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "clock")
                            .glyph(Glyph.xs)
                            .foregroundStyle(AppColors.textTertiary)
                        Text(startedAt, style: .timer)
                            .appType(.monoMetric)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            if let error = model.lastError {
                Text(error)
                    .appType(.meta)
                    .foregroundStyle(AppColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.md)
        .card()
    }

    private var subtitle: String {
        if let hosted = model.hostedModel {
            return "Serving \(hosted.displayName) to iPhone, iPad and Android on this network."
        }
        return "Share a model loaded on this Mac with phones and tablets on the same network."
    }

    private var statusBadge: some View {
        StatusTag(
            text: model.status.title,
            tint: model.isHosting ? AppColors.success : AppColors.textSecondary,
            fill: model.isHosting ? AppColors.successMuted : AppColors.surfaceMuted
        )
    }

    private var hostButton: some View {
        let canStart = selected != nil && !model.isStarting
        return Button {
            if model.isHosting {
                model.stop()
            } else if let selected {
                Task { await model.start(selected, store: store) }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: model.isHosting ? "stop.fill" : "play.fill")
                    .glyph(Glyph.xs, weight: .semibold)
                Text(model.isHosting ? "Stop hosting" : "Start hosting")
                    .appType(.cardTitle)
            }
            .foregroundStyle(model.isHosting ? AppColors.danger : AppColors.brand)
            .padding(.horizontal, Space.lg)
            .frame(height: Measure.hitTarget)
            .background(
                Capsule().fill(model.isHosting ? AppColors.dangerMuted : AppColors.brandMuted)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isHosting ? false : !canStart)
        .opacity(model.isHosting || canStart ? 1 : 0.5)
    }

    private var selected: InstalledModel? {
        candidates.first { $0.id == model.selectedModelID }
            ?? candidates.first { $0.id == store.loadedLanguageModel?.id }
            ?? candidates.first
    }

    // MARK: - Model choice

    @ViewBuilder
    private var picker: some View {
        if candidates.isEmpty {
            EmptyState(
                symbol: "square.stack.3d.up.slash",
                title: "No chat model on this Mac",
                detail: "Hosting shares one language model. Download one in Manage Models first."
            )
            .card()
        } else {
            VStack(spacing: Space.sm) {
                ForEach(candidates) { candidate in
                    modelRow(candidate)
                }
            }
        }
    }

    private func modelRow(_ candidate: InstalledModel) -> some View {
        let isSelected = candidate.id == selected?.id
        return Button {
            model.selectedModelID = candidate.id
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .glyph(Glyph.sm)
                    .foregroundStyle(isSelected ? AppColors.brand : AppColors.textTertiary)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(candidate.name)
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("\(candidate.sizeLabel) · \(candidate.backend)")
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: Space.sm)

                if store.loadedLanguageModel?.id == candidate.id {
                    CapabilityTag(symbol: "checkmark", title: "Loaded", tint: AppColors.success)
                }
            }
            .padding(Space.md)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clients

    private var clients: some View {
        HStack(spacing: Space.xl) {
            metric("Devices", value: "\(model.clientCount)")
            metric("Model", value: model.hostedModel?.displayName ?? "—")
            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .card()
        .overlay(alignment: .bottomLeading) {
            if model.clientCount == 0 {
                Text("Open a chat on an iPhone or iPad on this network and pick this Mac.")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(Space.md)
            }
        }
    }

    // MARK: - Activity

    @ViewBuilder
    private var activity: some View {
        if model.entries.isEmpty {
            EmptyState(
                symbol: "list.bullet.rectangle",
                title: "Nothing yet",
                detail: "Starting a host, and every device that joins or leaves, shows up here."
            )
            .card()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().overlay(AppColors.border)
                    }
                    entryRow(entry)
                }
            }
            .card()
        }
    }

    private func entryRow(_ entry: ConnectHostModel.Entry) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Circle()
                .fill(tint(entry.tone))
                .frame(width: Space.sm, height: Space.sm)
                .padding(.top, Space.xs)

            Text(entry.text)
                .appType(.meta)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.sm)

            Text(entry.at, style: .time)
                .appType(.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(Space.md)
    }

    private func tint(_ tone: ConnectHostModel.Entry.Tone) -> Color {
        switch tone {
        case .neutral: AppColors.textTertiary
        case .good: AppColors.success
        case .bad: AppColors.danger
        }
    }

    // MARK: - Chrome

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Text(value)
                .appType(.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
            Text(label)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
#endif
