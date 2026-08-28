import Foundation

/// Who the app is being for right now.
///
/// Two audiences share one binary: someone using the product, and someone
/// building on the SDK who needs the diagnostic screens. User mode shows chat,
/// models and settings; developer mode adds the SDK hub to the sidebar and a
/// diagnostics section to Settings, and says which one is in force in the only
/// way that reads at a glance — the colour of its chrome.
enum AppMode: String, CaseIterable, Identifiable {
    case user
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user: "User"
        case .developer: "Developer"
        }
    }

    var caption: String {
        switch self {
        case .user: "Just the product: chat, models and settings."
        case .developer: "Adds the SDK screens and their diagnostics, and cools the theme so a screenshot says which mode it came from."
        }
    }

    var symbol: String {
        switch self {
        case .user: "person"
        case .developer: "hammer"
        }
    }

    /// Brand orange is the product and does not move. What moves is the
    /// chrome around it: user mode warms it, developer mode cools it toward
    /// blue, so a screenshot from either is unmistakable.
    var isCool: Bool { self == .developer }
}
