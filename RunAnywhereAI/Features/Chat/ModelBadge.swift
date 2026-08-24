import SwiftUI

enum ModelState: Equatable {
    case none
    case loading(String, Double)
    case loaded(String, String)

    var name: String {
        switch self {
        case .none: "No model"
        case .loading(let name, _): name
        case .loaded(let name, _): name
        }
    }

    var detail: String {
        switch self {
        case .none: "Choose a model"
        case .loading(_, let progress): "Loading \(Int(progress * 100))%"
        case .loaded(_, let backend): backend
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var tint: Color {
        switch self {
        case .none: AppColors.textTertiary
        case .loading: AppColors.info
        case .loaded: AppColors.success
        }
    }
}

struct ModelBadge: View {
    let state: ModelState
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Circle()
                    .fill(state.tint)
                    .frame(width: 7, height: 7)

                Text(state.name)
                    .appType(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if state.isLoading {
                    Text(state.detail)
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.down")
                    .glyph(Glyph.xs - 2)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, Space.md)
            .frame(height: 28)
            .background(Capsule().fill(AppColors.surfaceMuted))
            .overlay(Capsule().strokeBorder(AppColors.border, lineWidth: Stroke.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(state.name), \(state.detail)")
    }
}
