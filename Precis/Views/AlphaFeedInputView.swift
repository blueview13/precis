import SwiftUI

struct AlphaFeedInputView: View {
    @StateObject private var viewModel = AlphaFeedViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Alpha feed intake")
                .font(PrecisTypography.headline)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

            HStack(spacing: 12) {
                TextField("https://example.com/feed.xml", text: $viewModel.inputURL)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    Task {
                        await viewModel.addFeed()
                    }
                }) {
                    if viewModel.isWorking {
                        ProgressView()
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Add feed")
                    }
                }
                .disabled(viewModel.isWorking)
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.statusText)
                    .font(PrecisTypography.body)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.8))

                if let feed = viewModel.addedFeed {
                    Text("Added: \(feed.title)")
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.marginalia)
                }
            }
        }
        .padding(24)
        .background(PrecisDesignSystem.surface(for: colorScheme))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(PrecisDesignSystem.rule(for: colorScheme), lineWidth: 1)
        )
    }
}

#Preview {
    AlphaFeedInputView()
}
