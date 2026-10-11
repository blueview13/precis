import SwiftUI

// MARK: - Help window

/// The Help window: a sidebar of bundled Markdown articles and a detail pane
/// that renders the selected one. Lives in its own `Window` scene so opening
/// Help never disturbs the reader's layout or state.
struct HelpWindowView: View {
    enum Article: String, CaseIterable, Identifiable {
        case gettingStarted = "Getting Started"
        case rightClickMenus = "Right-Click Menus"
        case headerIcons = "Header Icons"
        case keyboardShortcuts = "Keyboard Shortcuts"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .gettingStarted: "list.bullet.rectangle"
            case .rightClickMenus: "contextmenu"
            case .headerIcons: "toolbar"
            case .keyboardShortcuts: "keyboard"
            }
        }

        private var resourceName: String {
            switch self {
            case .gettingStarted: "GettingStarted"
            case .rightClickMenus: "RightClickMenus"
            case .headerIcons: "HeaderIcons"
            case .keyboardShortcuts: "KeyboardShortcuts"
            }
        }

        /// Loads the article from the bundle. Handles both a flat copy in
        /// `Resources` and a folder-reference copy under `Resources/Help`.
        var markdown: String {
            let name = resourceName
            let url = Bundle.main.url(forResource: name, withExtension: "md")
                ?? Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Help")
            guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
                return "# \(rawValue)\n\nThis help article is missing."
            }
            return text
        }
    }

    @State private var selectedArticle: Article? = .gettingStarted
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 660, minHeight: 440)
    }

    private var sidebar: some View {
        List(Article.allCases, selection: $selectedArticle) { article in
            Label(article.rawValue, systemImage: article.symbol)
                .tag(article)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 190)
        .background(PrecisDesignSystem.sidebar(for: colorScheme))
    }

    private var detail: some View {
        ScrollView {
            HelpMarkdownView(text: (selectedArticle ?? .gettingStarted).markdown)
                .padding(PrecisSpacing.lg)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PrecisDesignSystem.background(for: colorScheme))
    }
}

// MARK: - Markdown rendering

/// Renders the Help articles' Markdown subset — headings, paragraphs,
/// ordered/unordered lists, and pipe tables — using `AttributedString` for
/// inline formatting (**bold**, *italic*, `code`). Tables need the custom
/// treatment because `AttributedString(markdown:)` has no table support.
private struct HelpMarkdownView: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    enum Block {
        case heading(level: Int, text: String)
        case paragraph([String])
        case list(ordered: Bool, items: [String])
        case table(header: [String], rows: [[String]])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PrecisSpacing.md) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level <= 1 ? .system(size: 24, weight: .semibold) : .system(size: 17, weight: .semibold))
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme))
                .padding(.top, level <= 1 ? 0 : PrecisSpacing.xs)

        case .paragraph(let lines):
            inlineFlow(lines.joined(separator: " "))
                .font(PrecisTypography.body)
                .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: PrecisSpacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(PrecisTypography.body)
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                            .frame(width: ordered ? 22 : 10, alignment: .trailing)
                        inlineFlow(item)
                            .font(PrecisTypography.body)
                            .foregroundStyle(PrecisDesignSystem.foreground(for: colorScheme).opacity(0.85))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, PrecisSpacing.xs)

        case .table(let header, let rows):
            VStack(alignment: .leading, spacing: 0) {
                tableRow(header, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider().foregroundStyle(PrecisDesignSystem.rule(for: colorScheme))
                    tableRow(row, isHeader: false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(PrecisDesignSystem.rule(for: colorScheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PrecisSpacing.md) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(inline(cell))
                    .font(isHeader ? PrecisTypography.caption : PrecisTypography.body)
                    .textCase(isHeader ? .uppercase : nil)
                    .tracking(isHeader ? 1.2 : 0)
                    .foregroundStyle(
                        isHeader
                            ? PrecisDesignSystem.marginalia
                            : PrecisDesignSystem.foreground(for: colorScheme).opacity(0.85)
                    )
                    .lineLimit(1)
                    .frame(maxWidth: index == 0 ? 190 : .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, PrecisSpacing.sm)
        .padding(.vertical, 8)
        .background(isHeader ? PrecisDesignSystem.surface(for: colorScheme).opacity(0.6) : Color.clear)
    }

    private func inline(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    // MARK: Inline icon tokens

    /// A `{{icon:symbol}}` token or surrounding text.
    enum InlineSegment {
        case text(String)
        case icon(String)
    }

    /// Splits `"...{{icon:newspaper}} makes a PDF…"` into text/icon segments.
    static func splitIcons(_ markdown: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var rest = Substring(markdown)
        while let open = rest.range(of: "{{icon:"),
              let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            if open.lowerBound > rest.startIndex {
                segments.append(.text(String(rest[..<open.lowerBound])))
            }
            segments.append(.icon(String(rest[open.upperBound..<close.lowerBound])))
            rest = rest[close.upperBound...]
        }
        if !rest.isEmpty {
            segments.append(.text(String(rest)))
        }
        return segments
    }

    /// Inline flow that renders `{{icon:…}}` tokens as the real SF Symbols
    /// used in the app's UI; plain text still goes through `AttributedString`.
    @ViewBuilder
    private func inlineFlow(_ markdown: String) -> some View {
        let segments = Self.splitIcons(markdown)
        if segments.count == 1, case .text(let text) = segments[0] {
            Text(inline(text))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        Text(inline(text))
                    case .icon(let name):
                        Image(systemName: name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(PrecisDesignSystem.marginalia)
                    }
                }
            }
        }
    }

    // MARK: Parsing

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var listOrdered = false
        var collectingList = false
        var tableLines: [String] = []

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
                paragraph.removeAll()
            }
            if !listItems.isEmpty {
                blocks.append(.list(ordered: listOrdered, items: listItems))
                listItems.removeAll()
                collectingList = false
            }
            if !tableLines.isEmpty {
                let rows = tableLines.map(tableCells).filter { !$0.isSeparator }
                if let header = rows.first {
                    blocks.append(.table(header: header, rows: Array(rows.dropFirst())))
                }
                tableLines.removeAll()
            }
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flush()
                continue
            }

            let hashes = line.prefix(while: { $0 == "#" }).count
            if hashes > 0, hashes <= 6,
               line.count > hashes,
               line[line.index(line.startIndex, offsetBy: hashes)] == " "
            {
                flush()
                let text = String(line.dropFirst(hashes + 1))
                blocks.append(.heading(level: hashes, text: text))
                continue
            }

            if line.hasPrefix("|") {
                if !paragraph.isEmpty || !listItems.isEmpty { flush() }
                tableLines.append(line)
                continue
            }

            if line.hasPrefix("- ") {
                if !paragraph.isEmpty || !tableLines.isEmpty { flush() }
                if collectingList, !listOrdered {
                    listItems.append(String(line.dropFirst(2)))
                } else {
                    flush()
                    collectingList = true
                    listOrdered = false
                    listItems.append(String(line.dropFirst(2)))
                }
                continue
            }

            if let item = orderedItem(line) {
                if !paragraph.isEmpty || !tableLines.isEmpty { flush() }
                if collectingList, listOrdered {
                    listItems.append(item)
                } else {
                    flush()
                    collectingList = true
                    listOrdered = true
                    listItems.append(item)
                }
                continue
            }

            // Plain paragraph line.
            if !listItems.isEmpty || !tableLines.isEmpty { flush() }
            paragraph.append(line)
        }
        flush()
        return blocks
    }

    /// `"3. Do the thing"` → `"Do the thing"`, else nil.
    private static func orderedItem(_ line: String) -> String? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        var index = line.index(line.startIndex, offsetBy: digits.count)
        guard index < line.endIndex, line[index] == "." else { return nil }
        index = line.index(after: index)
        guard index < line.endIndex, line[index] == " " else { return nil }
        return String(line[line.index(after: index)...])
    }

    /// `| a | b |` → `["a", "b"]`.
    private static func tableCells(_ line: String) -> [String] {
        var stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.hasPrefix("|") { stripped.removeFirst() }
        if stripped.hasSuffix("|") { stripped.removeLast() }
        return stripped.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private extension Array where Element == String {
    /// True for a table separator row's cells (`---`, `:--:`).
    var isSeparator: Bool {
        !isEmpty && allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        }
    }
}

#Preview {
    HelpWindowView()
        .frame(width: 760, height: 520)
}
