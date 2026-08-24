import Foundation
import SwiftUI

@main
struct RunAnywhereAIApp: App {
    init() {
        #if os(macOS) && DEBUG
        // A locally built Mac app is signed ad hoc, so its signature changes
        // on every rebuild and the keychain treats each build as a different
        // program: it re-authorises every stored secret on every launch, which
        // is a password prompt per item. Debug builds keep secrets in a file
        // under Application Support instead. Release builds are signed once
        // and use the keychain as normal.
        setenv("RUNANYWHERE_SWIFT_SECURE_STORE", "file", 1)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1024, height: 720)
        .windowResizability(.contentMinSize)
        #endif
    }
}
