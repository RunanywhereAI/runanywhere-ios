import Foundation
import SwiftUI

@main
struct RunAnywhereAIApp: App {
    init() {
        #if DEBUG && (os(macOS) || targetEnvironment(simulator))
        // Neither of these builds has a keychain the SDK can use.
        //
        // A locally built Mac app is signed ad hoc, so its signature changes on
        // every rebuild and the keychain treats each build as a different
        // program: a password prompt per stored secret per launch. A simulator
        // build on a machine with no development team is signed with no
        // entitlements at all, so it has no keychain access group and every
        // write comes back as missing-entitlement — which the SDK reports as
        // "Secure storage operation failed" and refuses to start on, because
        // DeviceIdentity will not mint a device id it cannot persist.
        //
        // Both keep secrets in a file under Application Support instead.
        // Release builds are signed properly and use the keychain as normal.
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
