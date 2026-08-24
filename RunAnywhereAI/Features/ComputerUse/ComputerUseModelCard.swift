import SwiftUI
import RunAnywhere

/// The model strip above the agent: which computer-use model is driving, and a
/// way to get one when none is.
struct ComputerUseModelCard: View {
    let store: ModelStore
    let model: ComputerUseViewModel

    private var agents: [ModelInfo] {
        ComputerUseViewModel.agents(in: store)
    }

    var body: some View {
        if model.profile != nil, let name = model.loadedModelName {
            driving(name)
        } else if agents.isEmpty {
            EmptyState(
                symbol: "cursorarrow.rays",
                title: "No computer-use model in the catalog",
                detail: "Computer use needs a model that declares an agent profile. None is registered on this device."
            )
            .card()
        } else {
            choices
        }
    }

    private func driving(_ name: String) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: "cursorarrow.rays")
                .glyph(Glyph.md)
                .foregroundStyle(AppColors.brand)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(AppColors.brandMuted)
                )

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(name)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(model.profile ?? "")
                    .appType(.mono)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.sm)

            CapabilityTag(symbol: "checkmark", title: "Ready", tint: AppColors.success)
        }
        .padding(Space.md)
        .card()
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(prompt)
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(agents, id: \.id) { agent in
                row(agent)
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

    /// A vision model can be resident and still not be an agent — say which
    /// case the reader is in rather than showing the same line either way.
    private var prompt: String {
        if let name = model.loadedModelName {
            return "\(name) is loaded, but it does not declare a computer-use profile. Load one of these instead."
        }
        return "Computer use runs on a model that declares an agent profile."
    }

    private func row(_ agent: ModelInfo) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(agent.name.isEmpty ? agent.id : agent.name)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(agent.cuaProfile)
                    .appType(.mono)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.sm)

            action(agent)
        }
        .padding(.vertical, Space.xs)
    }

    @ViewBuilder
    private func action(_ agent: ModelInfo) -> some View {
        if let progress = store.downloading[agent.id] {
            HStack(spacing: Space.xs) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(AppColors.brand)
                Text("\(Int(progress * 100))%")
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(width: 130)
        } else if agent.localPath.isEmpty {
            pill("Get", symbol: "arrow.down", tint: AppColors.brand, wash: AppColors.brandMuted) {
                Task { await store.download(agent.id) }
            }
        } else {
            pill(
                model.isLoadingModel ? "Loading…" : "Use",
                symbol: "play.fill",
                tint: AppColors.brand,
                wash: AppColors.brandMuted
            ) {
                Task { await model.load(agent, store: store) }
            }
        }
    }

    private func pill(
        _ title: String,
        symbol: String,
        tint: Color,
        wash: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .glyph(Glyph.xs, weight: .semibold)
                Text(title)
                    .appType(.meta)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, Space.md)
            .frame(height: 30)
            .background(Capsule().fill(wash))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isLoadingModel)
    }
}
