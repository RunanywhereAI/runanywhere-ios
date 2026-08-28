import SwiftUI

struct IntroScreen: View {
    let bootstrap: SDKBootstrap
    let onFinished: () -> Void

    @State private var shown: Double = 0

    var body: some View {
        Scaffold {
            VStack(spacing: Space.xl) {
                Spacer()

                VStack(spacing: Space.sm) {
                    Text("RunAnywhere")
                        .appType(.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(caption)
                        .appType(.secondary)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                ProgressTrack(progress: shown)
                    .frame(width: 260)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Space.xxl)
        }
        .task {
            await bootstrap.start()
        }
        .onChange(of: bootstrap.progress, initial: true) { _, value in
            withAnimation(.timingCurve(0.16, 0.9, 0.3, 1, duration: 0.55)) {
                shown = value
            }
        }
        .onChange(of: bootstrap.isReady) { _, ready in
            guard ready else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                onFinished()
            }
        }
    }

    private var caption: String {
        switch bootstrap.phase {
        case .failed(let message): message
        case .ready: "Ready"
        default: "Everything runs privately on your device."
        }
    }
}

private struct ProgressTrack: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.surfaceMuted)

                Capsule()
                    .fill(AppColors.brand)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 6)
        .overlay(Capsule().strokeBorder(AppColors.border, lineWidth: Stroke.hairline))
        .accessibilityElement()
        .accessibilityLabel("Starting RunAnywhere")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
