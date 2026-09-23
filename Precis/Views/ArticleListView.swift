import SwiftUI

struct ArticleListView: View {
    @ObservedObject var viewModel: ArticleListViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showThumbnails") private var showThumbnails: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inbox")
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                Spacer()

                if viewModel.items.contains(where: { !$0.isRead }) {
                    Button(action: { viewModel.markAllAsRead(context: modelContext) }) {
                        Text("Mark All Read")
                            .font(PrecisTypography.caption)
                            .foregroundStyle(PrecisDesignSystem.flag)
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.items.contains(where: { $0.isRead }) {
                    Button(action: { viewModel.markAllAsUnread(context: modelContext) }) {
                        Text("Mark All Unread")
                            .font(PrecisTypography.caption)
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                    }
                    .buttonStyle(.plain)
                }

                Text("\(viewModel.filteredItems.count)")
                    .font(PrecisTypography.metadata)
                    .foregroundStyle(PrecisDesignSystem.marginalia)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PrecisDesignSystem.marginalia.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(PrecisSpacing.md)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PrecisDesignSystem.marginalia)
                    .font(.caption)

                TextField("Search articles...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(PrecisTypography.body)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(PrecisDesignSystem.surface(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, PrecisSpacing.md)
            .padding(.bottom, PrecisSpacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.filteredItems) { item in
                        ArticleListRow(
                            item: item,
                            isSelected: viewModel.selectedItemID == item.id,
                            showThumbnails: showThumbnails,
                            onSelect: { viewModel.select(item) },
                            onToggleStar: { viewModel.toggleStarred(item, context: modelContext) }
                        )
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .background(PrecisDesignSystem.background(for: colorScheme))
        .focusable()
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress("d") {
            if let item = viewModel.selectedItem {
                viewModel.toggleRead(item, context: modelContext)
            }
            return .handled
        }
        .onKeyPress("s") {
            if let item = viewModel.selectedItem {
                viewModel.toggleStarred(item, context: modelContext)
            }
            return .handled
        }
    }
}

private struct ArticleListRow: View {
    let item: ArticleListItem
    let isSelected: Bool
    let showThumbnails: Bool
    let onSelect: () -> Void
    let onToggleStar: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showThumbnails, let imageURLString = item.imageURL, let imageURL = URL(string: imageURLString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        thumbnailPlaceholder
                    case .empty:
                        thumbnailPlaceholder
                    @unknown default:
                        thumbnailPlaceholder
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 4)
            }

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

                    Button(action: onToggleStar) {
                        Image(systemName: item.isStarred ? "star.fill" : "star")
                            .foregroundStyle(item.isStarred ? PrecisDesignSystem.flag : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)

                HStack(spacing: PrecisSpacing.sm) {
                    Text(item.feedTitle)
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.marginalia)

                    Text("•")
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.rule(for: colorScheme))

                    Text("\(item.readingTimeMinutes) min read")
                        .font(PrecisTypography.metadata)
                        .foregroundStyle(PrecisDesignSystem.marginalia.opacity(0.7))
                }

                Text(item.cleanSnippet)
                    .font(PrecisTypography.body)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.75))
                    .lineLimit(2)
            }
        }
        .padding(PrecisSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? PrecisDesignSystem.surface(for: colorScheme) : (item.isRead ? Color.clear : PrecisDesignSystem.surface(for: colorScheme)))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(PrecisDesignSystem.rule(for: colorScheme)),
            alignment: .bottom
        )
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(PrecisDesignSystem.surface(for: colorScheme))
            .frame(width: 64, height: 64)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(PrecisDesignSystem.marginalia.opacity(0.3))
                    .font(.title3)
            )
    }
}

#Preview {
    ArticleListView(viewModel: ArticleListViewModel())
}
