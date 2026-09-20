import SwiftUI

struct MainWindowLayout: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 260)

            Divider()
                .frame(width: 1)
                .background(PrecisDesignSystem.rule(for: colorScheme))

            articleListView
                .frame(width: 340)

            Divider()
                .frame(width: 1)
                .background(PrecisDesignSystem.rule(for: colorScheme))

            readingPaneView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PrecisDesignSystem.background(for: colorScheme))
        .ignoresSafeArea()
    }

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Precis")
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))

                Spacer()

                Button(action: {}) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(PrecisDesignSystem.marginalia)
                }
                .buttonStyle(.plain)
            }
            .padding(PrecisSpacing.md)

            VStack(alignment: .leading, spacing: PrecisSpacing.sm) {
                SidebarSection(title: "Library")
                SidebarItem(title: "All Items", active: true)
                SidebarItem(title: "Unread", active: false)
                SidebarItem(title: "Starred", active: false)
                SidebarItem(title: "Later", active: false)

                SidebarSection(title: "Folders")
                SidebarItem(title: "News", active: false)
                SidebarItem(title: "Tech", active: false)
                SidebarItem(title: "Culture", active: false)
            }
            .padding(.horizontal, PrecisSpacing.md)

            Spacer()
        }
        .background(PrecisDesignSystem.surface(for: colorScheme))
    }

    private var articleListView: some View {
        ArticleListView()
    }

    private var readingPaneView: some View {
        ReadingPaneView()
    }
}

private struct SidebarSection: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(PrecisTypography.caption)
            .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
            .textCase(.uppercase)
            .tracking(1.2)
            .padding(.top, PrecisSpacing.sm)
    }
}

private struct SidebarItem: View {
    let title: String
    let active: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            if active {
                Capsule()
                    .frame(width: 4, height: 18)
                    .foregroundStyle(PrecisDesignSystem.flag)
            } else {
                Color.clear
                    .frame(width: 4, height: 18)
            }

            Text(title)
                .font(PrecisTypography.body)
                .foregroundStyle(active ? PrecisDesignSystem.foreground(for: colorScheme) : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.75))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? PrecisDesignSystem.surface(for: colorScheme).opacity(0.8) : Color.clear)
        .cornerRadius(10)
    }
}

private struct ArticleRow: View {
    let title: String
    let meta: String
    let unread: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if unread {
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundStyle(PrecisDesignSystem.flag)
                }

                Text(title)
                    .font(PrecisTypography.headline)
                    .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                    .lineLimit(2)
            }

            Text(meta)
                .font(PrecisTypography.metadata)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.6))
        }
        .padding(PrecisSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(unread ? PrecisDesignSystem.surface(for: colorScheme) : Color.clear)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(PrecisDesignSystem.rule(for: colorScheme))
                .padding(.horizontal, 0),
            alignment: .bottom
        )
    }
}

#Preview {
    MainWindowLayout()
}
