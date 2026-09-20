import SwiftUI

struct AlphaConsoleView: View {
    @StateObject private var viewModel = AlphaFeedViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("First alpha loop")
                .font(PrecisTypography.headline)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

            AlphaFeedInputView()

            if let feed = FeedStore.shared.feeds.last {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active feeds")
                        .font(PrecisTypography.caption)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.7))

                    Text(feed.title)
                        .font(PrecisTypography.body)
                        .foregroundStyle(PrecisDesignSystem.marginalia)

                    Text(feed.url.absoluteString)
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.7))
                }
            }
        }
        .padding(24)
    }
}

#Preview {
    AlphaConsoleView()
}
