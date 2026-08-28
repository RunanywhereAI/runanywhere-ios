import SwiftUI

enum AppScreen {
    case intro
    case setup
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
        ZStack {
            // The two trees cross-fade, and a fade between translucent halves
            // would show the window through them. This is the opaque ground
            // they fade over.
            AppColors.background
                .ignoresSafeArea()

            Group {
                switch screen {
                case .intro:
                    IntroScreen(bootstrap: bootstrap) {
                        // The catalog is read here rather than on the far side,
                        // because whether setup has anything to offer is what
                        // decides which screen comes next. The intro stays up
                        // meanwhile, which is what it is for.
                        Task {
                            await store.refreshCatalog()
                            go(settings.hasCompletedSetup || !store.needsSetup ? .home : .setup)
                        }
                    }
                case .setup:
                    SetupScreen(store: store, settings: settings) { go(.home) }
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
            .transition(.opacity)
        }
        .animation(Motion.fade, value: settings.mode)
    }

    private func go(_ destination: AppScreen) {
        withAnimation(.easeOut(duration: 0.28)) { screen = destination }
    }
}
