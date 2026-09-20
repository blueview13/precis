import SwiftUI

struct ArticleListView: View {
    @StateObject private var viewModel = ArticleListViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inbox")
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                Spacer()

                Text("\(viewModel.items.count)")
                    .font(PrecisTypography.metadata)
                    .foregroundStyle(PrecisDesignSystem.marginalia)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PrecisDesignSystem.marginalia.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(PrecisSpacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.items) { item in
                        ArticleListRow(item: item)
                            .onTapGesture {
                                viewModel.toggleRead(item)
                            }
                    }
                }
            }
        }
        .background(PrecisDesignSystem.background(for: colorScheme))
    }
}

private struct ArticleListRow: View {
    let item: ArticleListItem
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if !item.isRead {
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundStyle(PrecisDesignSystem.flag)
                }

                Text(item.title)
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                    .strikethrough(item.isRead)
                    .lineLimit(2)

                Spacer()

                Button(action: {}) {
                    Image(systemName: item.isStarred ? "star.fill" : "star")
                        .foregroundStyle(item.isStarred ? PrecisDesignSystem.flag : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Text(item.feedTitle)
                .font(PrecisTypography.metadata)
                .foregroundStyle(PrecisDesignSystem.marginalia)

            Text(item.snippet)
                .font(PrecisTypography.body)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.75))
                .lineLimit(2)
        }
        .padding(PrecisSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.isRead ? Color.clear : PrecisDesignSystem.surface(for: colorScheme))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(PrecisDesignSystem.rule(for: colorScheme)),
            alignment: .bottom
        )
    }
}

#Preview {
    ArticleListView()
}
