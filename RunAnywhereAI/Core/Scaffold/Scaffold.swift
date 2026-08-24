import SwiftUI

struct Scaffold<TopBar: View, Content: View, BottomBar: View>: View {
    private let topBar: TopBar
    private let content: Content
    private let bottomBar: BottomBar

    init(
        @ViewBuilder topBar: () -> TopBar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.topBar = topBar()
        self.content = content()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        VStack(spacing: 0) {
            if TopBar.self != EmptyView.self {
                topBar
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Measure.barHeight)
                    .background(AppColors.surface)
                    .overlay(alignment: .bottom) { Divider().overlay(AppColors.border) }
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if BottomBar.self != EmptyView.self {
                bottomBar
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Measure.barHeight)
                    .background(AppColors.surface)
                    .overlay(alignment: .top) { Divider().overlay(AppColors.border) }
            }
        }
        .background(AppColors.background)
    }
}

extension Scaffold where TopBar == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder bottomBar: () -> BottomBar) {
        self.init(topBar: { EmptyView() }, content: content, bottomBar: bottomBar)
    }
}

extension Scaffold where BottomBar == EmptyView {
    init(@ViewBuilder topBar: () -> TopBar, @ViewBuilder content: () -> Content) {
        self.init(topBar: topBar, content: content, bottomBar: { EmptyView() })
    }
}

extension Scaffold where TopBar == EmptyView, BottomBar == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(topBar: { EmptyView() }, content: content, bottomBar: { EmptyView() })
    }
}

struct TopBar: View {
    var title: String?
    var subtitle: String?
    var leading: AnyView?
    var center: AnyView?
    var trailing: AnyView?

    var body: some View {
        ZStack {
            HStack(spacing: Space.md) {
                if let leading { leading }

                if title != nil || subtitle != nil {
                    VStack(alignment: .leading, spacing: Space.hair) {
                        if let title {
                            Text(title)
                                .appType(.cardTitle)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .appType(.meta)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }

                Spacer(minLength: Space.md)

                DownloadIndicator()

                if let trailing { trailing }
            }

            if let center {
                center
                    .allowsHitTesting(true)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .overlay(alignment: .bottom) { DownloadProgressLine() }
    }
}

struct BarButton: View {
    let systemImage: String
    var tint: Color = AppColors.textSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .glyph(Glyph.md)
                .foregroundStyle(tint)
                .frame(width: Measure.hitTarget, height: Measure.hitTarget - Space.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
