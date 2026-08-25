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

extension ModelBadge {
    enum Style {
        /// A filled capsule with a status dot: the model is the subject of the
        /// screen, as on the vision and segmentation tools.
        case pill
        /// Plain text that recedes once a model is chosen, for chat, where the
        /// model is picked once and then forgotten.
        case quiet
    }
}

struct ModelBadge: View {
    let state: ModelState
    var style: Style = .pill
    /// Whether the runtime behind the model is worth naming. Developer mode
    /// wants to know it was MLX and not llama.cpp; nobody else does.
    var showsBackend = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            switch style {
            case .pill: pill
            case .quiet: quiet
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(state.name), \(state.detail)")
    }

    private var pill: some View {
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

    private var quiet: some View {
        HStack(spacing: Space.xs) {
            Text(quietTitle)
                .appType(.meta)
                .fontWeight(.medium)
                .foregroundStyle(state == .none ? AppColors.brand : AppColors.textSecondary)
                .lineLimit(1)

            if let trailing = quietDetail {
                Text(trailing)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textTertiary)
                    .monospacedDigit()
            }

            Image(systemName: "chevron.down")
                .glyph(Glyph.xs - 3)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: 28)
        .contentShape(Rectangle())
    }

    private var quietTitle: String {
        state == .none ? "Select model" : state.name
    }

    private var quietDetail: String? {
        switch state {
        case .loading: state.detail
        case .loaded(_, let backend): showsBackend ? backend : nil
        case .none: nil
        }
    }
}
