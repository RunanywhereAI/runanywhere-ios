import SwiftUI

/// What an empty conversation says.
///
/// One question and nothing else. The reader already got past the download
/// gate, so there is nothing left to explain and no caveat left to make — the
/// only thing worth doing here is asking them something.
struct ChatWelcome: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.xxl)

            Text("What's on your mind?")
                .appType(.title)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xl)

            Spacer(minLength: Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { wash }
    }

    /// A warm cast over the whole empty screen, so the emptiness reads as room
    /// left on purpose rather than a screen that failed to load. Kept low
    /// enough to be felt rather than seen; any more and it is a shape.
    private var wash: some View {
        LinearGradient(
            colors: [AppColors.brand.opacity(0.07), AppColors.brand.opacity(0)],
            startPoint: .bottom,
            endPoint: .top
        )
        .allowsHitTesting(false)
    }
}
