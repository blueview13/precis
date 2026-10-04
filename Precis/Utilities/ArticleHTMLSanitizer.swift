import Foundation

/// Strips source-site chrome out of feed-supplied article HTML before the
/// reading pane renders it — category labels, timestamps, bylines, read-time
/// estimates, hashtag runs, share links, and a headline that repeats the
/// pane's own title. The pane already hides a list of known chrome *class
/// names* in its CSS, but feeds whose markup carries none of those classes
/// still leak their metadata into the article, which is what this fixes.
///
/// Pure string/regex heuristics — deliberately no DOM dependency, in keeping
/// with `ArticleContentLoader`'s approach. Every pass is additive, and the
/// final retention check guarantees the sanitizer can never blank an article:
/// if less than half the visible text survives, the original is returned.
public enum ArticleHTMLSanitizer {

    /// Fragments that keep less than this fraction of their visible text
    /// after sanitizing are rejected in favour of the untouched original.
    public static let minimumRetainedTextRatio = 0.4

    /// Token-overlap ratio at which a lead paragraph counts as a redundant
    /// restatement of the body and gets dropped (genuine subheads score
    /// well below this).
    public static let deckRedundancyThreshold = 0.6

    // MARK: - Public API

    /// Sanitizes an HTML fragment for display. Returns the original string
    /// unchanged when the passes would remove too much text.
    public static func sanitize(_ fragment: String, title: String?) -> String {
        guard !fragment.isEmpty else { return fragment }

        let withoutComments = strippingComments(from: fragment)
        var text = strippedLeadingChrome(from: withoutComments, title: title)
        text = strippingDuplicateHeadline(from: text, title: title)
        text = strippingShareLinks(from: text)

        let before = ArticleContentLoader.visibleTextLength(in: fragment)
        let after = ArticleContentLoader.visibleTextLength(in: text)
        if before > 0, Double(after) < Double(before) * minimumRetainedTextRatio {
            return fragment
        }
        return text
    }

    /// Line-based counterpart of `sanitize(_:title:)` for the plain-text
    /// fallback path (no stored HTML): drops leading metadata lines and any
    /// share/hashtag lines, keeping everything else.
    public static func sanitizePlainText(_ text: String, title: String?) -> String {
        var lines = text.components(separatedBy: .newlines)
        guard lines.count > 1 || (lines.first.map { visibleLength($0) } ?? 0) < 600 else {
            // A single long blob is body, not metadata — leave it alone.
            return text
        }

        if let title, let firstIndex = lines.firstIndex(where: { visibleLength($0) > 0 }) {
            if normalizedForTitleMatch(lines[firstIndex]) == normalizedForTitleMatch(title) {
                lines.remove(at: firstIndex)
            }
        }

        // Leading metadata: consume lines while they read as chrome; stop at
        // the first line that looks like real content.
        while let first = lines.firstIndex(where: { visibleLength($0) > 0 }) {
            let line = lines[first]
            guard isChromeLine(line) else { break }
            lines.remove(at: first)
        }

        // Share/hashtag lines are safe to drop anywhere.
        lines = lines.filter { !isShareLine($0) && !isHashtagLine($0) }

        return lines.joined(separator: "\n")
    }

    // MARK: - Chrome predicates

    private static func isChromeLine(_ rawLine: String) -> Bool {
        let line = collapsed(rawLine)
        guard !line.isEmpty else { return false }
        if line.count <= 90, isDateLike(line) { return true }
        if line.count <= 40, matches(line, #"\b\d+\s*(?:min|mins|minute|minutes)\b"#) { return true }
        if line.count <= 80, isShareLine(line) { return true }
        if line.count <= 80, isHashtagLine(line) { return true }
        if line.count <= 60, isByline(line) { return true }
        if line.count <= 60, !hasInternalSentencePunctuation(line), titleCaseRatio(line) >= 0.6 {
            return true
        }
        return false
    }

    private static func isShareLine(_ rawLine: String) -> Bool {
        let line = collapsed(rawLine)
        guard line.count <= 80 else { return false }
        return matches(
            line,
            #"\bshare\s+(?:on|to|via|this|article|post|it)\b|^tweet\b|^retweet\b|email this|copy (?:the )?link"#,
            ignoreCase: true
        )
    }

    private static func isHashtagLine(_ rawLine: String) -> Bool {
        let line = collapsed(rawLine)
        guard line.count <= 80 else { return false }
        let words = line.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return false }
        let hashtags = words.filter { $0.hasPrefix("#") && $0.count > 1 }
        return Double(hashtags.count) / Double(words.count) >= 0.4
    }

    private static func isByline(_ rawLine: String) -> Bool {
        let line = collapsed(rawLine)
        guard line.count <= 60 else { return false }
        return matches(line, #"^by\s+[A-Z][\p{L}'’-]+(?:\s+[A-Z][\p{L}'’-]+){1,3}\.?$"#)
    }

    private static func isDateLike(_ line: String) -> Bool {
        let month = #"(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?"#
        let datePatterns = [
            #"\b\d{1,2}\s+\#(month)\s+\d{2,4}\b"#,
            #"\b\#(month)\s+\d{1,2},?\s+\d{2,4}\b"#,
            #"\b\d{4}-\d{2}-\d{2}\b"#,
            #"\b\d{1,2}[/.]\d{1,2}[/.]\d{2,4}\b"#
        ]
        for pattern in datePatterns {
            if matches(line, pattern) { return true }
        }
        // A bare clock time is metadata too ("18:02 •").
        if line.count <= 30, matches(line, #"\b\d{1,2}:\d{2}\b"#) { return true }
        return false
    }

    // MARK: - Fragment passes

    private static func strippingComments(from html: String) -> String {
        replacing(in: html, pattern: "<!--.*?-->", with: "")
    }

    /// Removes metadata nodes from the start of the fragment: category
    /// labels, timestamps, bylines, read-time, hashtags, locations, share
    /// links — and a redundant lead paragraph — until the first real content
    /// node is reached.
    ///
    /// Feeds often wrap the whole item in one `<div>`; when the strip hits a
    /// wrapper it descends into it (bounded depth) so inner metadata is
    /// still reached, rebuilding the wrapper around whatever survives.
    private static func strippedLeadingChrome(
        from html: String,
        title: String?,
        depth: Int = 0
    ) -> String {
        var position = html.startIndex
        while let node = nextNode(in: html, from: position) {
            guard node.range.upperBound > node.range.lowerBound else { break }
            switch kind(of: node, title: title) {
            case .removable:
                position = node.range.upperBound
            case .candidate:
                if let target = firstSubstantialNode(in: html, after: node.range.upperBound),
                   redundancy(of: node.text, against: target.text) >= deckRedundancyThreshold {
                    position = node.range.upperBound
                    break
                }
                if let rebuilt = descendingIntoWrapper(node, in: html, title: title, depth: depth) {
                    return String(html[..<node.range.lowerBound]) + rebuilt
                }
                return String(html[position...])
            case .content:
                if let rebuilt = descendingIntoWrapper(node, in: html, title: title, depth: depth) {
                    return String(html[..<node.range.lowerBound]) + rebuilt
                }
                return String(html[position...])
            }
        }
        return String(html[position...])
    }

    private static let maxWrapperDepth = 6
    private static let wrapperTags: Set<String> = [
        "div", "section", "article", "main", "center", "font", "span"
    ]

    /// When a content/candidate node is a plain wrapper element, sanitize its
    /// inner HTML and rebuild the element around the result. Returns nil when
    /// the node isn't a wrapper or nothing inside changed.
    private static func descendingIntoWrapper(
        _ node: FragmentNode,
        in html: String,
        title: String?,
        depth: Int
    ) -> String? {
        guard depth < maxWrapperDepth,
              let tag = node.tag,
              wrapperTags.contains(tag),
              let openEnd = html.range(of: ">", range: node.range)?.lowerBound
        else { return nil }

        let innerStart = html.index(after: openEnd)
        let closeSuffix = "</\(tag)>"
        let full = html[node.range]
        let innerEnd: String.Index
        if full.hasSuffix(closeSuffix) {
            innerEnd = html.index(node.range.upperBound, offsetBy: -closeSuffix.count)
        } else {
            innerEnd = node.range.upperBound // unclosed wrapper — inner runs to the end
        }
        guard innerStart < innerEnd else { return nil }

        let inner = String(html[innerStart..<innerEnd])
        let cleaned = strippedLeadingChrome(from: inner, title: title, depth: depth + 1)
        guard cleaned != inner else { return nil }

        let openTag = String(html[node.range.lowerBound...openEnd])
        let closeTag = full.hasSuffix(closeSuffix) ? closeSuffix : ""
        let suffix = String(html[node.range.upperBound...])
        return openTag + cleaned + closeTag + suffix
    }

    /// Removes an `<h1>` anywhere in the fragment whose text repeats the
    /// pane's own headline.
    private static func strippingDuplicateHeadline(from html: String, title: String?) -> String {
        guard let title else { return html }
        return replacingMatches(
            in: html,
            pattern: #"<h1\b[^>]*>[\s\S]*?</h1\s*>"#
        ) { match in
            fuzzyTitleEqual(visibleText(of: match), title) ? "" : match
        }
    }

    /// Removes share/social and pure-hashtag anchors regardless of position
    /// (a feed's "Share on X / Share on Facebook" row usually sits at the
    /// article's end).
    private static func strippingShareLinks(from html: String) -> String {
        let hrefPattern = #"twitter\.com/(?:intent|share)|facebook\.com/sharer|whatsapp:|linkedin\.com/share|pinterest\.com/pin/create|/share\b"#
        return replacingMatches(
            in: html,
            pattern: #"<a\b[^>]*>[\s\S]*?</a\s*>"#
        ) { match in
            let inner = innerHTML(ofAnchor: match)
            let innerText = visibleText(of: inner)
            let href = attributeValue(named: "href", in: match) ?? ""
            if innerText.hasPrefix("#") { return "" }
            if isShareLine(innerText) || matches(href, hrefPattern, ignoreCase: true) { return "" }
            return match
        }
    }

    // MARK: - Node scanning

    private enum NodeKind {
        /// Metadata / chrome — safe to drop.
        case removable
        /// Possible redundant lead paragraph — dropped only when it closely
        /// restates the paragraph that follows.
        case candidate
        /// Real content — the leading strip stops here.
        case content
    }

    private struct FragmentNode {
        let range: Range<String.Index>
        let tag: String?
        let text: String
    }

    /// Text-only tags that are safe to drop even when they hold no text —
    /// a tag that may wrap an image (`figure`, `a`, `div`) never qualifies.
    private static let emptyRemovableTags: Set<String> = [
        "p", "span", "em", "strong", "small", "time", "b", "i", "font", "br", "hr", "center"
    ]

    /// Tags whose text-only nodes are candidate lead paragraphs.
    private static let deckCandidateTags: Set<String> = ["p", "div", "section", "li", "td"]

    /// Tags that are always page chrome.
    private static let chromeTags: Set<String> = [
        "nav", "footer", "aside", "form", "button", "script", "style", "noscript", "header"
    ]

    /// Article media a node may never drop. SVG excluded — inline SVGs are
    /// overwhelmingly share icons, not article art.
    private static let mediaPattern = #"<(?:img|picture|figure|video|iframe|audio|source)\b"#

    /// Tags that always count as content anchors (stop the leading strip).
    private static let contentAnchorTags: Set<String> = [
        "h2", "h3", "h4", "h5", "h6", "figure", "img", "picture", "video", "iframe",
        "ul", "ol", "blockquote", "table", "pre", "article", "main", "audio", "details"
    ]

    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr"
    ]

    private static func kind(of node: FragmentNode, title: String?) -> NodeKind {
        let text = collapsed(node.text)
        guard !text.isEmpty else {
            // Media-only nodes (a lead `<p><img></p>`) are content even though
            // they carry no text — only bare text-holding tags drop when empty.
            if matches(node.text, mediaPattern, ignoreCase: true) {
                return .content
            }
            guard let tag = node.tag, emptyRemovableTags.contains(tag) else { return .content }
            return .removable
        }

        if let tag = node.tag {
            switch tag {
            case "h1":
                if let title, fuzzyTitleEqual(text, title) { return .removable }
                return .content
            case _ where chromeTags.contains(tag):
                // Page chrome drops wholesale even when it wraps an avatar
                // image — the picture is byline metadata, not article art.
                return .removable
            default:
                break
            }

            if contentAnchorTags.contains(tag) {
                // Media wins first: a figure/img wrapper is content even when
                // its caption reads like date chrome.
                if matches(node.text, Self.mediaPattern) { return .content }
                // Headings drop when they carry short date/read-time chrome
                // (a category rendered as `<h2>Latest News</h2>`), but
                // full-length content elements — an `<article>` whose text
                // mentions a date — must never match.
                if text.count <= 90, isDateLike(text) || isShareLine(text) || isHashtagLine(text) {
                    return .removable
                }
                return .content
            }
        }

        // Media wins over every text heuristic from here on: a wrapper around
        // a hero image (caption "Nico O'Reilly" reads as title-case chrome,
        // but dropping it deletes the picture) is content, always. SVG is
        // deliberately excluded — inline SVGs are overwhelmingly share icons.
        if matches(node.text, mediaPattern) { return .content }

        if isChromeLine(text) { return .removable }

        let length = text.count
        if 40...600 ~= length {
            if let tag = node.tag {
                if deckCandidateTags.contains(tag) { return .candidate }
            } else {
                return .candidate
            }
        }
        return .content
    }

    /// First node after `start` that reads as body: substantial text or a
    /// structural anchor — skipping removable nodes and the pane's own
    /// repeated headline so a deck sitting above them is still compared
    /// against the real body.
    private static func firstSubstantialNode(in html: String, after start: String.Index) -> FragmentNode? {
        var position = start
        while let node = nextNode(in: html, from: position) {
            guard node.range.upperBound > node.range.lowerBound else { return nil }
            position = node.range.upperBound
            switch kind(of: node, title: nil) {
            case .removable:
                continue
            case .content, .candidate:
                let tag = node.tag ?? ""
                if tag == "h1" { continue }
                if visibleLength(node.text) >= 80 { return node }
                if contentAnchorTags.contains(tag) { return node }
                continue
            }
        }
        return nil
    }

    /// Reads the node starting at `start`: skips whitespace, identifies the
    /// element (or bare text run) and its visible text. Text runs stop at the
    /// first newline so metadata laid out as plain lines classifies per line.
    private static func nextNode(in html: String, from start: String.Index) -> FragmentNode? {
        var i = start
        // Control characters too: stored articles can carry a leading 0x01
        // storage marker, which must not register as a content node and
        // stall the leading strip before any chrome has been examined.
        while i < html.endIndex,
              html[i].isWhitespace || html[i].unicodeScalars.allSatisfy({ $0.value < 0x20 }) {
            i = html.index(after: i)
        }
        guard i < html.endIndex else { return nil }

        guard html[i] == "<" else {
            var end = i
            while end < html.endIndex, html[end] != "<", html[end] != "\n" {
                end = html.index(after: end)
            }
            let slice = html[i..<end]
            return FragmentNode(range: i..<end, tag: nil, text: String(slice))
        }

        guard let headerEnd = html[i...].firstIndex(of: ">") else { return nil }
        let header = html[i...headerEnd]
        let end = html.index(after: headerEnd)

        // Stray closing tags / doctypes at depth zero — consume and ignore.
        if header.hasPrefix("</") || header.hasPrefix("<!") || header.hasPrefix("<?") {
            return FragmentNode(range: i..<end, tag: nil, text: "")
        }

        let name = tagName(of: header)
        if name.isEmpty {
            return FragmentNode(range: i..<end, tag: nil, text: "")
        }
        if voidTags.contains(name) || header.hasSuffix("/>") {
            return FragmentNode(range: i..<end, tag: name, text: "")
        }
        guard let closeEnd = matchingClose(of: name, in: html, after: headerEnd) else {
            // Unclosed element — the rest of the fragment belongs to it.
            return FragmentNode(range: i..<html.endIndex, tag: name, text: String(html[i...]))
        }
        return FragmentNode(range: i..<closeEnd, tag: name, text: String(html[i..<closeEnd]))
    }

    /// End index just past the element's matching close tag, tracking nested
    /// depth. `<p>` implicitly closes when another `<p>` opens (HTML allows
    /// unclosed paragraphs, and an unclosed first `<p>` would otherwise
    /// swallow the whole fragment).
    private static func matchingClose(of name: String, in html: String, after headerEnd: String.Index) -> String.Index? {
        var depth = 1
        var i = headerEnd
        while i < html.endIndex {
            guard let open = html[i...].firstIndex(of: "<"),
                  let close = html[open...].firstIndex(of: ">") else { return nil }
            let tag = html[open...close]
            i = html.index(after: close)

            if tag.hasPrefix("</") {
                depth -= 1
                if depth <= 0 { return i }
                continue
            }
            if tag.hasPrefix("<!") || tag.hasPrefix("<?") { continue }
            let innerName = tagName(of: tag)
            if !innerName.isEmpty, !voidTags.contains(innerName), !tag.hasSuffix("/>") {
                if depth == 1, name == "p", innerName == "p" { return open }
                depth += 1
            }
        }
        return nil
    }

    private static func tagName(of tag: Substring) -> String {
        let trimmed = tag.dropFirst().prefix(while: { !$0.isWhitespace && $0 != ">" && $0 != "/" })
        return trimmed.lowercased()
    }

    // MARK: - Text helpers

    private static func innerHTML(ofAnchor anchor: String) -> String {
        guard let openEnd = anchor.firstIndex(of: ">"),
              let closeStart = anchor.lastIndex(of: "<"),
              openEnd < closeStart else { return anchor }
        let innerStart = anchor.index(after: openEnd)
        return String(anchor[innerStart..<closeStart])
    }

    private static func attributeValue(named name: String, in markup: String) -> String? {
        let pattern = #"\#(name)\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: markup, range: NSRange(markup.startIndex..., in: markup)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: markup) else { return nil }
        return String(markup[range])
    }

    static func visibleText(of html: String) -> String {
        collapsed(html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
    }

    private static func visibleLength(_ html: String) -> Int {
        visibleText(of: html).count
    }

    /// Collapses whitespace and decodes the handful of entities that affect
    /// matching (apostrophes in titles, `&amp;`, `&#…;`).
    private static func collapsed(_ raw: String) -> String {
        let tagsStripped = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = decodeEntities(tagsStripped)
        return decoded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&rsquo;", "’"), ("&lsquo;", "‘")
        ] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        guard result.contains("&#") else { return result }

        var output = ""
        var remainder = Substring(result)
        while let open = remainder.range(of: "&#") {
            output += remainder[..<open.lowerBound]
            let afterOpen = remainder[open.upperBound...]
            if let close = afterOpen.firstIndex(of: ";") {
                let body = afterOpen[..<close]
                let isHex = body.first == "x" || body.first == "X"
                let digits = isHex ? String(body.dropFirst()) : String(body)
                if !digits.isEmpty,
                   let value = UInt32(digits, radix: isHex ? 16 : 10),
                   value != 0,
                   let scalar = Unicode.Scalar(value) {
                    output.append(Character(scalar))
                    remainder = afterOpen[afterOpen.index(after: close)...]
                    continue
                }
            }
            output += "&#"
            remainder = afterOpen
        }
        output += remainder
        return output
    }

    // MARK: - Title / overlap matching

    private static func normalizedForTitleMatch(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// True when two strings are the same headline modulo punctuation and
    /// case, or one contains the other outright (long enough to be safe).
    private static func fuzzyTitleEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizedForTitleMatch(lhs)
        let b = normalizedForTitleMatch(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let shorter = min(a.count, b.count)
        guard shorter >= 12 else { return false }
        return a.contains(b) || b.contains(a)
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "of", "to", "in", "on", "at", "for",
        "with", "from", "by", "as", "is", "are", "was", "were", "be", "been", "being",
        "it", "its", "this", "that", "these", "those", "has", "have", "had", "do", "does",
        "did", "will", "would", "could", "should", "may", "might", "can", "shall", "not",
        "no", "than", "then", "so", "such", "into", "over", "under", "about", "after",
        "before", "between", "out", "up", "down", "off", "again", "further", "once",
        "there", "here", "when", "where", "why", "how", "all", "any", "both", "each",
        "few", "more", "most", "other", "some", "only", "own", "same", "too", "very",
        "just", "because"
    ]

    private static func contentTokens(_ text: String) -> [String] {
        collapsed(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" })
            .map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "'’")) }
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    /// Fraction of `candidate`'s content words that also appear in `target` —
    /// a paraphrase scores near 1.0, an unrelated subhead well under 0.6.
    private static func redundancy(of candidate: String, against target: String) -> Double {
        let candidateTokens = contentTokens(candidate)
        guard candidateTokens.count >= 6 else { return 0 }
        let targetTokens = Set(contentTokens(target))
        guard !targetTokens.isEmpty else { return 0 }
        let matched = candidateTokens.filter { targetTokens.contains($0) }.count
        return Double(matched) / Double(candidateTokens.count)
    }

    // MARK: - Small regex/format helpers

    private static func matches(_ text: String, _ pattern: String, ignoreCase: Bool = false) -> Bool {
        var options: String.CompareOptions = [.regularExpression]
        if ignoreCase { options.insert(.caseInsensitive) }
        return text.range(of: pattern, options: options) != nil
    }

    /// `.`/`!`/`?` anywhere except as a trailing terminator — "He said no." is
    /// still sentence-like; "Peter Swales." is a label.
    private static func hasInternalSentencePunctuation(_ line: String) -> Bool {
        let strippedTrailing = line.replacingOccurrences(
            of: #"[.!?:•·\-–—\s]+$"#, with: "", options: .regularExpression
        )
        return strippedTrailing.range(of: #"[.!?]"#, options: .regularExpression) != nil
    }

    /// Fraction of the line's words that start uppercase — metadata labels
    /// ("Latest News", "Peter Swales", "Etihad Stadium") are near all-title-
    /// case, ordinary sentences are not.
    private static func titleCaseRatio(_ line: String) -> Double {
        let words = line.split(whereSeparator: { $0.isWhitespace })
        let alphabetic = words.filter { word in
            word.contains { $0.isLetter }
        }
        guard !alphabetic.isEmpty else { return 0 }
        let capitalized = alphabetic.filter { word in
            guard let first = word.first(where: { $0.isLetter }) else { return false }
            return first.isUppercase
        }
        return Double(capitalized.count) / Double(alphabetic.count)
    }

    private static func replacing(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement
        )
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        _ transform: (String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let replacement = transform(String(result[range]))
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
