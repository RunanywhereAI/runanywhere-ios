import SwiftUI

/// The tinted square that fronts a pack row, a node header and the inspector's
/// identity line.
///
/// It was written four times with three sizes and two wash opacities, which is
/// how the same pack ended up looking like a different pack in the palette and
/// on the canvas. The node header is the one legitimate size difference — a
/// 34pt card header has no room for the list row's well — so size is a
/// parameter and everything else is not.
struct WorkflowIconWell: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = Control.well

    var body: some View {
        Image(systemName: symbol)
            .glyph(Glyph.xs, weight: .semibold)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                tint.opacity(0.14),
                in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            )
    }
}
