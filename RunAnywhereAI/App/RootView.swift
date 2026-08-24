import SwiftUI

enum AppScreen {
    case intro
    case home
}

struct RootView: View {
    @State private var screen: AppScreen = .intro
    @State private var bootstrap = SDKBootstrap()
    @State private var store = ModelStore()

    var body: some View {
        Group {
            switch screen {
            case .intro:
                IntroScreen(bootstrap: bootstrap) {
                    withAnimation(.easeOut(duration: 0.28)) { screen = .home }
                }
            case .home:
                HomeScreen(store: store)
                    .task { await store.refresh() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .environment(store)
    }
}
