import SwiftUI

struct ReadingPaneView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("The quiet power of good reading interfaces")
                    .font(PrecisTypography.title)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                    .padding(.bottom, PrecisSpacing.sm)

                HStack(spacing: PrecisSpacing.sm) {
                    Text("The Verge")
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.marginalia)

                    Text("•")
                        .foregroundStyle(PrecisDesignSystem.rule(for: colorScheme))

                    Text("3 minutes ago")
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.7))
                }
                .padding(.bottom, PrecisSpacing.md)

                HStack(alignment: .top, spacing: PrecisSpacing.lg) {
                    VStack(alignment: .leading, spacing: PrecisSpacing.md) {
                        Text("Quiet interfaces don’t subtract from the reading experience — they make it easier to trust the words in front of you. A good reader is not a portal of endless activity; it is a place where attention can settle.")
                            .font(PrecisTypography.body)
                            .lineSpacing(7)
                            .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                        Text("This is the design principle behind a tool like Precis: remove clutter, preserve context, and leave the article itself in the foreground. Summaries are not a separate product; they are annotations that sit beside the text and aid understanding without taking over the page.")
                            .font(PrecisTypography.body)
                            .lineSpacing(7)
                            .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SummaryColumn() 
                        .frame(width: 220)
                }
            }
            .padding(PrecisSpacing.xl)
        }
    }
}

private struct SummaryColumn: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
            Text("MARGINALIA")
                .font(PrecisTypography.caption)
                .foregroundStyle(PrecisDesignSystem.marginalia)
                .tracking(1.2)

            Divider()
                .background(PrecisDesignSystem.rule(for: colorScheme))

            Text("The article points toward a simpler reading posture: less discovery churn, more absorption.")
                .font(PrecisTypography.body)
                .foregroundStyle(PrecisDesignSystem.marginalia)
                .lineSpacing(5)

            Text("- quieter interface\n- less clutter\n- more attention")
                .font(PrecisTypography.metadata)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.8))
                .lineSpacing(4)
        }
        .padding(PrecisSpacing.md)
        .background(PrecisDesignSystem.surface(for: colorScheme))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PrecisDesignSystem.rule(for: colorScheme), lineWidth: 1)
        )
    }
}

#Preview {
    ReadingPaneView()
}
