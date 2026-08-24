import SwiftUI

struct DownloadIndicator: View {
    @Environment(ModelStore.self) private var store: ModelStore?

    var body: some View {
        if let store, store.isDownloading {
            Menu {
                ForEach(store.downloading.keys.sorted(), id: \.self) { id in
                    Text("\(store.name(for: id)) · \(Int((store.downloading[id] ?? 0) * 100))%")
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(AppColors.border, lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.02, store.aggregateProgress))
                        .stroke(AppColors.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "arrow.down")
                        .glyph(Glyph.xs - 3, weight: .bold)
                        .foregroundStyle(AppColors.brand)
                }
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("\(store.downloading.count) downloading")
            .accessibilityLabel("\(store.downloading.count) downloading")
            .transition(.opacity.combined(with: .scale))
            .animation(.easeOut(duration: 0.2), value: store.aggregateProgress)
        }
    }
}

struct DownloadProgressLine: View {
    @Environment(ModelStore.self) private var store: ModelStore?

    var body: some View {
        if let store, store.isDownloading {
            GeometryReader { geo in
                Rectangle()
                    .fill(AppColors.brand)
                    .frame(width: geo.size.width * max(0.02, store.aggregateProgress))
            }
            .frame(height: 2)
            .animation(.easeOut(duration: 0.25), value: store.aggregateProgress)
            .transition(.opacity)
        }
    }
}
