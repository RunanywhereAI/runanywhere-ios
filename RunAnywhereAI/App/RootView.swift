import SwiftUI

enum AppScreen {
    case intro
    case home
}

struct RootView: View {
    @State private var screen: AppScreen = .intro
    @State private var bootstrap = SDKBootstrap()
    @State private var store = ModelStore()
    @State private var settings = AppSettings()
    // Declared here rather than inside HomeScreen so the mode rebuild below
    // does not throw the reader back to Chat every time they flip the switch.
    @State private var tab: SideNavTab = .chat

    var body: some View {
        Group {
            switch screen {
            case .intro:
                IntroScreen(bootstrap: bootstrap) {
                    withAnimation(.easeOut(duration: 0.28)) { screen = .home }
                }
            case .home:
                HomeScreen(store: store, tab: $tab)
                    .task { await store.refresh() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .environment(store)
        .environment(settings)
        // The design tokens are read statically rather than through the
        // environment, so nothing observes them. Keying the tree on the mode
        // is what turns a token change into a redraw.
        .id(settings.mode)
    }
}
