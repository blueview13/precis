import SwiftUI

struct DesignReviewBaseline: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Precis visual baseline")
                .font(PrecisTypography.headline)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

            VStack(alignment: .leading, spacing: 12) {
                Label("Light and dark mode review", systemImage: "moon.stars")
                Label("Narrow and wide window validation", systemImage: "rectangle.split.2x1")
                Label("Marginalia treatment remains distinct", systemImage: "note.text")
            }
            .font(PrecisTypography.body)
            .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.8))

            HStack(spacing: 16) {
                swatch(title: "paper", color: PrecisDesignSystem.paper)
                swatch(title: "ink", color: PrecisDesignSystem.ink)
                swatch(title: "marginalia", color: PrecisDesignSystem.marginalia)
                swatch(title: "flag", color: PrecisDesignSystem.flag)
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

    private func swatch(title: String, color: Color) -> some View {
        VStack(spacing: 8) {
            color
                .frame(width: 44, height: 44)
                .cornerRadius(10)

            Text(title)
                .font(PrecisTypography.caption)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.7))
        }
    }
}

#Preview {
    DesignReviewBaseline()
}
