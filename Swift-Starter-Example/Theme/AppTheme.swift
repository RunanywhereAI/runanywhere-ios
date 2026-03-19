//
//  AppTheme.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App
//

import SwiftUI

// MARK: - App Colors
/// Color palette inspired by modern AI/tech aesthetics - Deep space with electric accents
struct AppColors {
    // Primary gradient colors - Deep space with electric accents
    static let primaryDark = Color(hex: "0A0E1A")
    static let primaryMid = Color(hex: "141B2D")
    static let surfaceCard = Color(hex: "1C2438")
    static let surfaceElevated = Color(hex: "242F4A")
    
    // Accent colors - Electric cyan and violet
    static let accentCyan = Color(hex: "00D9FF")
    static let accentViolet = Color(hex: "8B5CF6")
    static let accentPink = Color(hex: "EC4899")
    static let accentGreen = Color(hex: "10B981")
    static let accentOrange = Color(hex: "F59E0B")
    
    // Text colors
    static let textPrimary = Color(hex: "F1F5F9")
    static let textSecondary = Color(hex: "94A3B8")
    static let textMuted = Color(hex: "64748B")
    
    // Status colors
    static let success = Color(hex: "22C55E")
    static let warning = Color(hex: "F59E0B")
    static let error = Color(hex: "EF4444")
    static let info = Color(hex: "3B82F6")
    
    // Gradients
    static let primaryGradient = LinearGradient(
        colors: [primaryDark, primaryMid],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let accentGradient = LinearGradient(
        colors: [accentCyan, accentViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let backgroundGradient = LinearGradient(
        colors: [primaryDark, Color(hex: "0F1629"), primaryMid],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography
struct AppFonts {
    // Headline fonts
    static func headline(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    
    static func headlineLarge() -> Font {
        .system(size: 28, weight: .semibold, design: .rounded)
    }
    
    static func headlineMedium() -> Font {
        .system(size: 24, weight: .semibold, design: .rounded)
    }
    
    // Title fonts
    static func titleLarge() -> Font {
        .system(size: 20, weight: .semibold)
    }
    
    static func titleMedium() -> Font {
        .system(size: 16, weight: .semibold)
    }
    
    // Body fonts
    static func bodyLarge() -> Font {
        .system(size: 16, weight: .regular)
    }
    
    static func bodyMedium() -> Font {
        .system(size: 14, weight: .regular)
    }
    
    static func bodySmall() -> Font {
        .system(size: 12, weight: .regular)
    }
    
    // Label fonts
    static func labelLarge() -> Font {
        .system(size: 14, weight: .semibold)
    }
    
    static func labelSmall() -> Font {
        .system(size: 12, weight: .medium)
    }
}

// MARK: - View Modifiers
struct CardStyle: ViewModifier {
    var borderColor: Color = AppColors.textMuted.opacity(0.1)
    
    func body(content: Content) -> some View {
        content
            .background(AppColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle(borderColor: Color = AppColors.textMuted.opacity(0.1)) -> some View {
        modifier(CardStyle(borderColor: borderColor))
    }
}

// MARK: - Button Styles
struct GradientButtonStyle: ButtonStyle {
    var colors: [Color]
    var cornerRadius: CGFloat = 24
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 12, y: 4)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.titleMedium())
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [AppColors.accentCyan, AppColors.accentViolet],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(color: AppColors.accentCyan.opacity(0.3), radius: 12, y: 4)
    }
}

// MARK: - Thinking Tag Stripping

extension String {
    /// Strips `<think>…</think>` blocks (and any unclosed `<think>` tail) from model output.
    static func stripThinkingTags(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        if let range = result.range(of: "<think>[\\s\\S]*", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
