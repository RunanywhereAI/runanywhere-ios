import Observation
import SwiftUI

/// Sizes the four voice stages share, so their hero controls stay one control at
/// four call sites. Mac gets its own scale for the same reason `ComposerMetrics`
/// does: its windows are denser and a phone-sized target looks wrong in them.
enum VoiceMetrics {
    static var halo: CGFloat {
        #if os(macOS)
        104
        #else
        128
        #endif
    }

    static var ring: CGFloat {
        #if os(macOS)
        84
        #else
        104
        #endif
    }

    static var core: CGFloat {
        #if os(macOS)
        66
        #else
        86
        #endif
    }

    static var meter: CGFloat {
        #if os(macOS)
        22
        #else
        28
        #endif
    }
}

/// A rolling window of microphone levels.
///
/// Owned here rather than in each screen so the four meters move at one rate
/// and read the same way. `AudioCaptureManager` publishes a level whenever it
/// pleases; sampling it on a fixed tick is what turns that into a waveform
/// instead of a twitch.
@Observable
@MainActor
final class AudioLevelTrack {
    private(set) var levels: [Float]

    private static let window = 48
    private static let floor: Float = 0.04
    private var task: Task<Void, Never>?

    init() {
        levels = Array(repeating: Self.floor, count: Self.window)
    }

    func start(sampling source: @escaping @MainActor () -> Float) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, !Task.isCancelled else { return }
                push(source())
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        reset()
    }

    func reset() {
        levels = Array(repeating: Self.floor, count: Self.window)
    }

    private func push(_ level: Float) {
        let clamped = min(max(level, Self.floor), 1)
        var next = levels
        next.removeFirst()
        next.append(clamped)
        levels = next
    }
}

/// The level meter shared by every voice screen.
struct VoiceLevelMeter: View {
    let levels: [Float]
    var tint: Color = AppColors.brand
    var isActive: Bool = true

    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let spacing = Space.hair
            let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(isActive ? tint : AppColors.textTertiary)
                        .frame(width: width, height: height(for: level, in: geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(Motion.readout, value: levels)
        }
        .accessibilityHidden(true)
    }

    private func height(for level: Float, in available: CGFloat) -> CGFloat {
        max(3, CGFloat(min(max(level, 0), 1)) * available)
    }
}

/// One word for what the screen is doing right now.
struct VoiceStatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        StatusTag(text: text, tint: tint)
    }
}

/// Something went wrong, said once, where it happened.
struct VoiceNotice: View {
    let message: String
    var symbol = "exclamationmark.triangle"
    var tint: Color = AppColors.danger

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: symbol)
                .glyph(Glyph.sm)
                .foregroundStyle(tint)
            Text(message)
                .appType(.meta)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }
}

/// The row that names a slot's model and opens the chooser.
struct VoiceModelRow: View {
    let slot: VoiceModelSlot
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                GlyphTile(symbol: slot.slot.symbol)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(slot.slot.title)
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(slot.name ?? slot.slot.detail)
                        .appType(.meta)
                        .foregroundStyle(slot.model == nil ? AppColors.textSecondary : AppColors.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: Space.sm)

                status

                Image(systemName: "chevron.right")
                    .glyph(Glyph.sm)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(Space.md)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel("\(slot.slot.title) model, \(slot.name ?? "none chosen")")
    }

    @ViewBuilder
    private var status: some View {
        if slot.isLoading {
            ProgressView()
                .controlSize(.small)
        } else if slot.isResident {
            Text("Ready")
                .appType(.meta)
                .foregroundStyle(AppColors.success)
        } else {
            Text(slot.model == nil ? "Choose" : "Change")
                .appType(.meta)
                .foregroundStyle(AppColors.brand)
        }
    }
}

extension View {
    /// The chooser every voice screen uses: pick from what is installed for the
    /// slot, or open Manage Models and download one.
    func voiceModelPicker(
        slot: Binding<VoiceSlot?>,
        store: ModelStore,
        activeID: @escaping (VoiceSlot) -> String?,
        onSelect: @escaping (VoiceSlot, InstalledModel) -> Void
    ) -> some View {
        modifier(
            VoiceModelPicker(slot: slot, store: store, activeID: activeID, onSelect: onSelect)
        )
    }
}

private struct VoiceModelPicker: ViewModifier {
    @Binding var slot: VoiceSlot?
    let store: ModelStore
    let activeID: (VoiceSlot) -> String?
    let onSelect: (VoiceSlot, InstalledModel) -> Void

    @State private var isManaging = false

    func body(content: Content) -> some View {
        content
            .modelPicker(
                isPresented: Binding(get: { slot != nil }, set: { if !$0 { slot = nil } }),
                models: candidates,
                activeID: slot.flatMap(activeID),
                onSelect: { model in
                    guard let slot else { return }
                    onSelect(slot, model)
                },
                onManage: { isManaging = true }
            )
            .sheet(isPresented: $isManaging) {
                manageModels
            }
    }

    private var candidates: [InstalledModel] {
        guard let slot else { return [] }
        return store.installed.filter { $0.purpose == slot.purpose }
    }

    private var manageModels: some View {
        Scaffold {
            TopBar(
                title: "Manage Models",
                trailing: AnyView(BarButton(systemImage: "xmark") { isManaging = false })
            )
        } content: {
            ManageModelsView(store: store)
        }
        #if os(macOS)
        .frame(width: 620, height: 640)
        #endif
    }
}
