import SwiftUI

struct AppRootView: View {
    @StateObject private var viewModel = ContentViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PrecisDesignSystem.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: PrecisSpacing.lg) {
                Image(systemName: "newspaper")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(PrecisDesignSystem.marginalia)

                Text(viewModel.appTitle)
                    .font(PrecisTypography.title)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                VStack(spacing: PrecisSpacing.xs) {
                    Text(viewModel.statusText)
                        .font(PrecisTypography.body)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.8))
                        .multilineTextAlignment(.center)

                    Text("marginalia-first reading")
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.marginalia)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }
                .padding(.horizontal, PrecisSpacing.xl)
            }
            .padding(PrecisSpacing.xl)
            .frame(maxWidth: 720, maxHeight: 420)
            .background(PrecisDesignSystem.surface(for: colorScheme))
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(PrecisDesignSystem.rule(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 10)
        }
    }
}

#Preview {
    AppRootView()
}
