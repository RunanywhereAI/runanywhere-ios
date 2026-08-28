import SwiftUI

struct ComposerStrip<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let wash: Color
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .glyph(Glyph.xs)
                .foregroundStyle(tint)
                .frame(width: Glyph.lg)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .appType(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .appType(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Space.sm)

            trailing
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(wash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: Stroke.hairline)
        )
    }
}

struct StripButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .glyph(Glyph.xs)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The offer to change model because of what was just attached.
///
/// Two answers, and both are real: take the model that can read the file, or
/// drop the file and keep the model. There is no third option where a text
/// model answers a picture, which is what the app used to do.
struct ModelSwitchStrip: View {
    let offer: AttachmentModelOffer
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ComposerStrip(
            symbol: "arrow.triangle.2.circlepath",
            tint: AppColors.brand,
            wash: AppColors.brandMuted,
            title: "Switch to \(offer.modelLabel)?",
            detail: offer.reason
        ) {
            HStack(spacing: Space.xs) {
                Button("Switch", action: onAccept)
                    .appType(.caption)
                    .fontWeight(.semibold)
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.brand)
                StripButton(symbol: "xmark", label: "Keep the current model", action: onDecline)
            }
        }
    }
}

extension AnyTransition {
    static var composerStrip: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }
}
