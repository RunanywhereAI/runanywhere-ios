//
//  VoiceModeSheet.swift
//  RunAnywhereAI
//
//  Voice mode, presented from the composer rather than buried in More.
//

import SwiftUI

/// `TalkScreen` with a way out.
///
/// The screen itself is written for the More hub, which supplies the chrome and
/// the back button. Reached from chat it needs its own, and it needs a frame:
/// on macOS a sheet with no size is as tall as its content and no wider than it
/// has to be, which for a mic button and three model rows is a slot.
struct VoiceModeSheet: View {
    let onClose: () -> Void
    /// Each completed exchange, so a spoken conversation is the same
    /// conversation as the typed one.
    var onTurn: ((String, String) -> Void)?

    var body: some View {
        Scaffold {
            TopBar(
                title: "Voice mode",
                subtitle: "Speech in, an answer spoken back",
                trailing: AnyView(
                    Button("Done", action: onClose)
                        .appType(.meta)
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColors.brand)
                        .padding(.trailing, Space.md)
                )
            )
        } content: {
            TalkScreen(onTurn: onTurn)
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 560, idealHeight: 720)
        #endif
    }
}
