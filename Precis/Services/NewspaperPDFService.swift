import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftData

struct NewspaperArticleReference: Sendable, Equatable {
    let id: UUID
    let feedID: UUID
    let publishedDate: Date
}

struct NewspaperPDFScope: Sendable {
    let feedIDs: Set<UUID>
    let articleIDs: Set<UUID>?

    init(feedIDs: Set<UUID>, articleIDs: Set<UUID>? = nil) {
        self.feedIDs = feedIDs
        self.articleIDs = articleIDs
    }
}

enum NewspaperArticleSelection {
    static let ageLimit: TimeInterval = 24 * 60 * 60

    static func recent(
        _ articles: [NewspaperArticleReference],
        scope: NewspaperPDFScope,
        now: Date
    ) -> [NewspaperArticleReference] {
        let earliestDate = now.addingTimeInterval(-ageLimit)
        return articles
            .filter {
                scope.feedIDs.contains($0.feedID)
                    && (scope.articleIDs?.contains($0.id) ?? true)
                    && $0.publishedDate >= earliestDate
                    && $0.publishedDate <= now
            }
            .sorted { $0.publishedDate > $1.publishedDate }
    }
}

struct NewspaperEdition {
    let pdfData: Data
    let includedCount: Int
    let excludedForFullText: Int
    let excludedForImage: Int
}

@MainActor
final class NewspaperPDFService {
    enum EditionError: LocalizedError {
        case noRecentArticles
        case noEligibleArticles(fullText: Int, image: Int)
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .noRecentArticles:
                return "There are no articles in this feed or category from the last 24 hours."
            case .noEligibleArticles(let fullText, let image):
                return "No articles had both full text and a usable image. Skipped \(fullText) because full text was unavailable and \(image) because an image was unavailable."
            case .saveFailed:
                return "The newspaper PDF could not be written to the selected location."
            }
        }
    }

    private struct Source: Sendable {
        let id: UUID
        let feedID: UUID
        let title: String
        let author: String?
        let feedTitle: String
        let publishedDate: Date
        let articleURL: URL?
        let existingHTML: String?
        let fullContentFetched: Bool
        let imageURL: String?
    }

    struct PreparedStory: Sendable {
        let id: UUID
        let title: String
        let author: String?
        let feedTitle: String
        let publishedDate: Date
        let html: String
        let imageData: Data
    }

    private struct PreparationResult: Sendable {
        let id: UUID
        let story: PreparedStory?
        let fetchedHTML: String?
        let excludedForFullText: Bool
        let excludedForImage: Bool
    }

    func createEdition(
        context: ModelContext,
        scope: NewspaperPDFScope,
        scopeTitle: String,
        now: Date = Date(),
        onProgress: (@MainActor (Int, Int) -> Void)? = nil
    ) async throws -> NewspaperEdition {
        let records = try ArticleRepository().fetchAll(context: context)
        let sources = records.compactMap { record -> Source? in
            guard let feed = record.feed,
                  let publishedDate = record.publishedDate else { return nil }
            return Source(
                id: record.id,
                feedID: feed.id,
                title: record.title,
                author: record.author,
                feedTitle: feed.title,
                publishedDate: publishedDate,
                articleURL: Self.webURL(record.link),
                existingHTML: record.contentHTMLText,
                fullContentFetched: record.fullContentFetched == true,
                imageURL: record.imageURL
            )
        }
        let references = sources.map {
            NewspaperArticleReference(id: $0.id, feedID: $0.feedID, publishedDate: $0.publishedDate)
        }
        let recent = NewspaperArticleSelection.recent(references, scope: scope, now: now)
        guard !recent.isEmpty else { throw EditionError.noRecentArticles }

        let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let candidates = recent.compactMap { sourceByID[$0.id] }
        let results = await prepare(candidates, onProgress: onProgress)

        var included: [PreparedStory] = []
        var fullTextExclusions = 0
        var imageExclusions = 0
        var updatedRecords = false

        for result in results {
            if let fetchedHTML = result.fetchedHTML,
               let record = try ArticleRepository().fetch(id: result.id, context: context) {
                record.contentHTML = fetchedHTML.data(using: .utf8)
                record.fullContentFetched = true
                let plainText = ArticleHTMLSanitizer.plainText(fromHTML: fetchedHTML)
                if !plainText.isEmpty {
                    record.normalizedText = plainText
                    record.extractedContent = plainText.data(using: .utf8)
                }
                updatedRecords = true
            }

            if let story = result.story {
                included.append(story)
            } else if result.excludedForFullText {
                fullTextExclusions += 1
            } else if result.excludedForImage {
                imageExclusions += 1
            }
        }
        if updatedRecords {
            try context.save()
        }
        guard !included.isEmpty else {
            throw EditionError.noEligibleArticles(fullText: fullTextExclusions, image: imageExclusions)
        }

        let pdfData = try NewspaperPDFRenderer.render(
            stories: included,
            scopeTitle: scopeTitle,
            issueDate: now
        )
        return NewspaperEdition(
            pdfData: pdfData,
            includedCount: included.count,
            excludedForFullText: fullTextExclusions,
            excludedForImage: imageExclusions
        )
    }

    private func prepare(
        _ sources: [Source],
        onProgress: (@MainActor (Int, Int) -> Void)?
    ) async -> [PreparationResult] {
        await withTaskGroup(of: PreparationResult.self) { group in
            var iterator = sources.makeIterator()
            let concurrencyLimit = min(4, sources.count)
            for _ in 0..<concurrencyLimit {
                if let source = iterator.next() {
                    group.addTask { await Self.prepare(source) }
                }
            }

            var results: [PreparationResult] = []
            results.reserveCapacity(sources.count)
            while let result = await group.next() {
                results.append(result)
                onProgress?(results.count, sources.count)
                if let source = iterator.next() {
                    group.addTask { await Self.prepare(source) }
                }
            }
            return results
        }
    }

    nonisolated private static func prepare(_ source: Source) async -> PreparationResult {
        var html = source.existingHTML ?? ""
        var fetchedHTML: String?

        if !source.fullContentFetched || ArticleContentLoader.visibleTextLength(in: html) < ArticleContentLoader.minimumArticleText {
            guard let articleURL = source.articleURL,
                  let readableHTML = try? await ArticleContentLoader.fetchReadableHTML(from: articleURL),
                  ArticleContentLoader.visibleTextLength(in: readableHTML) >= ArticleContentLoader.minimumArticleText else {
                return PreparationResult(
                    id: source.id,
                    story: nil,
                    fetchedHTML: nil,
                    excludedForFullText: true,
                    excludedForImage: false
                )
            }
            html = readableHTML
            fetchedHTML = readableHTML
        }

        let editionHTML = ArticleHTMLSanitizer.sanitize(html, title: source.title)
        guard ArticleContentLoader.visibleTextLength(in: editionHTML) >= ArticleContentLoader.minimumArticleText else {
            return PreparationResult(
                id: source.id,
                story: nil,
                fetchedHTML: fetchedHTML,
                excludedForFullText: true,
                excludedForImage: false
            )
        }

        let firstImage = firstImageURL(in: editionHTML, base: source.articleURL)
            ?? source.imageURL.flatMap { resolvedWebURL($0, base: source.articleURL) }
        guard let firstImage,
              let imageData = try? await downloadImage(from: firstImage) else {
            return PreparationResult(
                id: source.id,
                story: nil,
                fetchedHTML: fetchedHTML,
                excludedForFullText: false,
                excludedForImage: true
            )
        }

        return PreparationResult(
            id: source.id,
            story: PreparedStory(
                id: source.id,
                title: source.title,
                author: source.author,
                feedTitle: source.feedTitle,
                publishedDate: source.publishedDate,
                html: editionHTML,
                imageData: imageData
            ),
            fetchedHTML: fetchedHTML,
            excludedForFullText: false,
            excludedForImage: false
        )
    }

    nonisolated static func firstImageURL(in html: String, base: URL?) -> URL? {
        guard let base,
              let imageTagRegex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: [.caseInsensitive]),
              let sourceRegex = try? NSRegularExpression(
                pattern: #"\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
                options: [.caseInsensitive]
              ) else { return nil }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let imageMatch = imageTagRegex.firstMatch(in: html, range: fullRange),
              let tagRange = Range(imageMatch.range, in: html) else { return nil }
        let imageTag = String(html[tagRange])
        let tagNSRange = NSRange(imageTag.startIndex..<imageTag.endIndex, in: imageTag)
        guard let sourceMatch = sourceRegex.firstMatch(in: imageTag, range: tagNSRange) else { return nil }

        for capture in 1...3 {
            if let range = Range(sourceMatch.range(at: capture), in: imageTag) {
                let rawURL = String(imageTag[range])
                    .replacingOccurrences(of: "&amp;", with: "&")
                if let url = resolvedWebURL(rawURL, base: base) { return url }
            }
        }
        return nil
    }

    nonisolated private static func resolvedWebURL(_ value: String, base: URL?) -> URL? {
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    nonisolated private static func webURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        return resolvedWebURL(value, base: nil)
    }

    nonisolated private static func downloadImage(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Precis/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              !data.isEmpty,
              data.count <= 20 * 1024 * 1024,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              NewspaperImageDecoder.thumbnail(from: imageSource) != nil else {
            throw URLError(.cannotDecodeContentData)
        }
        return data
    }
}

enum NewspaperPDFRenderer {
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let pageMargin: CGFloat = 34
    private static let columnGap: CGFloat = 16
    private static let columnCount = 3
    private static let bodyFontSize: CGFloat = 9
    private static let bodyFontName = "Baskerville"
    private static let headingFontName = "Baskerville"
    private static let footerHeight: CGFloat = 22
    private static let headerBottom: CGFloat = 53
    private static let coverContentTop: CGFloat = 603
    private static let coverBodyBottom: CGFloat = 59
    private static let mastheadSize: CGFloat = 59

    static func render(stories: [NewspaperPDFService.PreparedStory], scopeTitle: String, issueDate: Date) throws -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(
                consumer: consumer,
                mediaBox: &mediaBox,
                [
                    kCGPDFContextTitle as String: "\(scopeTitle) — Precis Newspaper Edition",
                    kCGPDFContextCreator as String: "Precis"
                ] as CFDictionary
              ) else {
            throw NewspaperPDFService.EditionError.saveFailed
        }

        let columnsWidth = pageSize.width - pageMargin * 2
        let columnWidth = (columnsWidth - columnGap * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        let bodyBottom = pageMargin + footerHeight
        let dateText = issueDate.formatted(date: .long, time: .omitted)
        var pageNumber = 0
        var column = 0
        var cursorY: CGFloat = 0

        func drawPageFooter() {
            drawLine("EDITION  ·  PAGE \(pageNumber)", fontName: bodyFontName, size: 7, bold: false, alignment: .center,
                     in: CGRect(x: pageMargin, y: pageMargin - 1, width: pageSize.width - pageMargin * 2, height: 12),
                     context: context)
        }

        func drawColumnRules(top: CGFloat, bottom: CGFloat) {
            context.setStrokeColor(CGColor(gray: 0.45, alpha: 1))
            context.setLineWidth(0.45)
            for separator in 1..<columnCount {
                let x = pageMargin + CGFloat(separator) * columnWidth + CGFloat(separator - 1) * columnGap + columnGap / 2
                context.move(to: CGPoint(x: x, y: bottom))
                context.addLine(to: CGPoint(x: x, y: top))
                context.strokePath()
            }
        }

        func startInteriorPage() {
            pageNumber += 1
            context.beginPDFPage(nil)
            drawLine("PRECIS", fontName: headingFontName, size: 26, bold: true, alignment: .left,
                     in: CGRect(x: pageMargin, y: pageSize.height - pageMargin - 27, width: 220, height: 30),
                     context: context)
            drawLine(scopeTitle.uppercased(), fontName: headingFontName, size: 11, bold: true, alignment: .right,
                     in: CGRect(x: pageMargin + 225, y: pageSize.height - pageMargin - 23,
                               width: pageSize.width - pageMargin * 2 - 225, height: 18),
                     context: context)
            drawLine("\(dateText)  ·  LAST 24 HOURS", fontName: bodyFontName, size: 8, bold: false, alignment: .right,
                     in: CGRect(x: pageMargin, y: pageSize.height - pageMargin - 43,
                               width: pageSize.width - pageMargin * 2, height: 12),
                     context: context)
            let ruleY = pageSize.height - pageMargin - headerBottom
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(1.2)
            context.move(to: CGPoint(x: pageMargin, y: ruleY))
            context.addLine(to: CGPoint(x: pageSize.width - pageMargin, y: ruleY))
            context.strokePath()

            let top = ruleY - 15
            drawColumnRules(top: top, bottom: bodyBottom)
            drawPageFooter()
            cursorY = top
            column = 0
        }

        func startCoverPage() {
            pageNumber = 1
            context.beginPDFPage(nil)
            let fullWidth = pageSize.width - pageMargin * 2
            let topRuleY = pageSize.height - 30
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(2.2)
            context.move(to: CGPoint(x: pageMargin, y: topRuleY))
            context.addLine(to: CGPoint(x: pageSize.width - pageMargin, y: topRuleY))
            context.strokePath()

            let issueNumber = "NO. 001  ·  \(scopeTitle.uppercased())"
            drawLine(dateText.uppercased(), fontName: bodyFontName, size: 8, bold: true, alignment: .left,
                     in: CGRect(x: pageMargin, y: topRuleY - 18, width: 170, height: 12), context: context)
            drawLine("A DAILY EDITION FROM YOUR FEEDS", fontName: bodyFontName, size: 7.5, bold: false, alignment: .center,
                     in: CGRect(x: pageMargin + 150, y: topRuleY - 18, width: fullWidth - 300, height: 12), context: context)
            drawLine(issueNumber, fontName: bodyFontName, size: 7.5, bold: true, alignment: .right,
                     in: CGRect(x: pageSize.width - pageMargin - 180, y: topRuleY - 18, width: 180, height: 12), context: context)

            drawMasthead(in: CGRect(x: pageMargin, y: 667, width: fullWidth, height: 73), context: context)
            context.setLineWidth(1.35)
            context.move(to: CGPoint(x: pageMargin, y: 660))
            context.addLine(to: CGPoint(x: pageSize.width - pageMargin, y: 660))
            context.strokePath()
            context.setLineWidth(0.55)
            context.move(to: CGPoint(x: pageMargin, y: 654))
            context.addLine(to: CGPoint(x: pageSize.width - pageMargin, y: 654))
            context.strokePath()
            drawLine("\(scopeTitle.uppercased())  ·  THE LAST 24 HOURS", fontName: bodyFontName, size: 9,
                     bold: true, alignment: .center,
                     in: CGRect(x: pageMargin, y: 630, width: fullWidth, height: 16), context: context)
            context.setLineWidth(1.2)
            context.move(to: CGPoint(x: pageMargin, y: 620))
            context.addLine(to: CGPoint(x: pageSize.width - pageMargin, y: 620))
            context.strokePath()

            drawColumnRules(top: coverContentTop, bottom: coverBodyBottom)
            drawPageFooter()
        }

        func advanceColumn() {
            if column + 1 < columnCount {
                column += 1
                cursorY = pageSize.height - pageMargin - 68
            } else {
                context.endPDFPage()
                startInteriorPage()
            }
        }

        func columnRect() -> CGRect {
            CGRect(
                x: pageMargin + CGFloat(column) * (columnWidth + columnGap),
                y: bodyBottom,
                width: columnWidth,
                height: cursorY - bodyBottom
            )
        }

        func printContentsIndex() {
            let x = pageMargin
            let width = columnWidth
            let ruleY = coverContentTop - 6
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(1.2)
            context.move(to: CGPoint(x: x, y: ruleY))
            context.addLine(to: CGPoint(x: x + width, y: ruleY))
            context.strokePath()
            drawLine("IN THIS EDITION", fontName: headingFontName, size: 11, bold: true, alignment: .center,
                     in: CGRect(x: x, y: ruleY - 26, width: width, height: 17), context: context)
            context.setLineWidth(0.7)
            context.move(to: CGPoint(x: x, y: ruleY - 31))
            context.addLine(to: CGPoint(x: x + width, y: ruleY - 31))
            context.strokePath()

            var y = ruleY - 43
            let maxBottom = coverBodyBottom + 12
            let maxItems = min(stories.count, 16)
            var printedCount = 0
            for (index, story) in stories.prefix(maxItems).enumerated() {
                let source = attributed(story.feedTitle.uppercased(), fontName: bodyFontName, size: 6.5,
                                        bold: false, alignment: .left, paragraphSpacing: 0)
                let isLead = index == 0
                let headline = attributed(story.title, fontName: headingFontName, size: isLead ? 9 : 8,
                                          bold: isLead, alignment: .left, paragraphSpacing: 0)
                let sourceHeight = min(12, measuredHeight(of: source, width: width) + 1)
                let headlineHeight = measuredHeight(of: headline, width: width)
                let entryHeight = headlineHeight + 3
                guard y - sourceHeight - 1 - entryHeight - 5 >= maxBottom else {
                    break
                }
                _ = drawWrappedText(source, x: x, top: y, width: width,
                                    maximumHeight: sourceHeight, context: context)
                y -= sourceHeight + 1
                _ = drawWrappedText(headline, x: x, top: y, width: width,
                                    maximumHeight: entryHeight, context: context)
                y -= entryHeight + 5
                printedCount += 1
            }
            let omitted = stories.count - printedCount
            if omitted > 0 {
                let moreCount = omitted
                drawLine("AND \(moreCount) MORE STORIES", fontName: bodyFontName, size: 6.5, bold: true,
                         alignment: .left, in: CGRect(x: x, y: max(maxBottom, y - 12), width: width, height: 10),
                         context: context)
            }
            context.setLineWidth(1.2)
            context.move(to: CGPoint(x: x, y: maxBottom - 7))
            context.addLine(to: CGPoint(x: x + width, y: maxBottom - 7))
            context.strokePath()
        }

        func drawCoverLead(_ story: NewspaperPDFService.PreparedStory) {
            let centerX = pageMargin + columnWidth + columnGap
            let rightX = pageMargin + 2 * (columnWidth + columnGap)
            let contentTop = coverContentTop - 7
            drawLine(story.feedTitle.uppercased(), fontName: bodyFontName, size: 7.5, bold: true, alignment: .left,
                     in: CGRect(x: centerX, y: contentTop - 12, width: columnWidth, height: 10), context: context)
            context.setLineWidth(0.8)
            context.move(to: CGPoint(x: centerX, y: contentTop - 17))
            context.addLine(to: CGPoint(x: centerX + columnWidth, y: contentTop - 17))
            context.strokePath()

            let byline = story.author?.trimmingCharacters(in: .whitespacesAndNewlines)
            let meta = [byline, story.publishedDate.formatted(date: .abbreviated, time: .omitted)]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")

            var titleSize: CGFloat = 29
            var title = attributed(story.title, fontName: headingFontName, size: titleSize, bold: true,
                                   alignment: .left, paragraphSpacing: 0)
            let titleTop = contentTop - 25
            let maxTitleHeight: CGFloat = 286
            while measuredHeight(of: title, width: columnWidth) > maxTitleHeight, titleSize > 17 {
                titleSize -= 1
                title = attributed(story.title, fontName: headingFontName, size: titleSize, bold: true,
                                   alignment: .left, paragraphSpacing: 0)
            }
            let titleHeight = min(maxTitleHeight, measuredHeight(of: title, width: columnWidth))
            _ = drawWrappedText(title, x: centerX, top: titleTop, width: columnWidth,
                                maximumHeight: titleHeight, context: context)

            var imageTop = titleTop - titleHeight - 8
            if !meta.isEmpty {
                drawLine(meta, fontName: bodyFontName, size: 7, bold: false, alignment: .left,
                         in: CGRect(x: centerX, y: imageTop - 10, width: columnWidth, height: 10), context: context)
                imageTop -= 17
            }
            let image = halftoneImage(story.imageData)
            if let image, imageTop - coverBodyBottom > 55 {
                let aspect = CGFloat(image.height) / CGFloat(image.width)
                let imageHeight = min(columnWidth * aspect, 112, imageTop - coverBodyBottom - 20)
                context.draw(image, in: CGRect(x: centerX, y: imageTop - imageHeight,
                                               width: columnWidth, height: imageHeight))
                imageTop -= imageHeight + 8
            }
            context.setLineWidth(0.55)
            context.move(to: CGPoint(x: centerX, y: imageTop))
            context.addLine(to: CGPoint(x: centerX + columnWidth, y: imageTop))
            context.strokePath()

            let body = attributed(bodyText(from: story.html), fontName: bodyFontName, size: bodyFontSize,
                                 bold: false, alignment: .justified, paragraphSpacing: 3)
            let bodyTop = contentTop - (meta.isEmpty ? 2 : 17)
            drawLine(meta.isEmpty ? "LEAD STORY" : meta, fontName: bodyFontName, size: 7, bold: false,
                     alignment: .left,
                     in: CGRect(x: rightX, y: bodyTop - 10, width: columnWidth, height: 10), context: context)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: rightX, y: bodyTop - 13))
            context.addLine(to: CGPoint(x: rightX + columnWidth, y: bodyTop - 13))
            context.strokePath()

            let storyTextTop = bodyTop - 20
            let storyRect = CGRect(x: rightX, y: coverBodyBottom + 5, width: columnWidth,
                                   height: storyTextTop - coverBodyBottom - 5)
            let framesetter = CTFramesetterCreateWithAttributedString(body)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                                 CGPath(rect: storyRect, transform: nil), nil)
            CTFrameDraw(frame, context)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            var offset = visibleRange.location + visibleRange.length
            if offset < body.length {
                context.endPDFPage()
                startInteriorPage()
                while offset < body.length {
                    let rect = columnRect()
                    let nextFrame = CTFramesetterCreateFrame(
                        framesetter,
                        CFRange(location: offset, length: 0),
                        CGPath(rect: rect, transform: nil),
                        nil
                    )
                    let range = CTFrameGetVisibleStringRange(nextFrame)
                    guard range.length > 0 else {
                        advanceColumn()
                        continue
                    }
                    CTFrameDraw(nextFrame, context)
                    offset = range.location + range.length
                    if offset < body.length {
                        advanceColumn()
                    } else {
                        cursorY = max(bodyBottom, cursorY - occupiedHeight(of: nextFrame) - 8)
                    }
                }
            } else {
                cursorY = max(bodyBottom, storyTextTop - occupiedHeight(of: frame) - 8)
            }
        }

        startCoverPage()
        printContentsIndex()
        let remainingStories: ArraySlice<NewspaperPDFService.PreparedStory>
        if let lead = stories.first {
            drawCoverLead(lead)
            remainingStories = stories.dropFirst()
            if !remainingStories.isEmpty {
                context.endPDFPage()
                startInteriorPage()
            }
        } else {
            drawLine("NO ARTICLES AVAILABLE", fontName: headingFontName, size: 16, bold: true,
                     alignment: .center,
                     in: CGRect(x: pageMargin, y: pageSize.height / 2, width: columnsWidth, height: 24),
                     context: context)
            remainingStories = []
        }

        for (storyIndex, story) in remainingStories.enumerated() {
            let bodyText = bodyText(from: story.html)
            guard !bodyText.isEmpty else { continue }
            let body = attributed(
                bodyText,
                fontName: bodyFontName,
                size: bodyFontSize,
                bold: false,
                alignment: .justified,
                paragraphSpacing: 3
            )
            let bodyFramesetter = CTFramesetterCreateWithAttributedString(body)
            let image = halftoneImage(story.imageData)
            let imageHeight: CGFloat
            if let image {
                let aspectRatio = CGFloat(image.height) / CGFloat(image.width)
                imageHeight = min(columnWidth * aspectRatio, 92)
            } else {
                imageHeight = 0
            }
            let byline = [story.author, story.feedTitle, story.publishedDate.formatted(date: .abbreviated, time: .omitted)]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "  ·  ")
            let bylineHeight: CGFloat = byline.isEmpty ? 0 : 16
            let availableColumnHeight = pageSize.height - pageMargin - headerBottom - 15 - bodyBottom
            let maximumTitleHeight = max(80, availableColumnHeight - bylineHeight - imageHeight - 14 - 40)
            var titleSize: CGFloat = 17
            var title = attributed(story.title, fontName: headingFontName, size: titleSize, bold: true,
                                   alignment: .left, paragraphSpacing: 0)
            while measuredHeight(of: title, width: columnWidth) > maximumTitleHeight, titleSize > 12 {
                titleSize -= 1
                title = attributed(story.title, fontName: headingFontName, size: titleSize, bold: true,
                                   alignment: .left, paragraphSpacing: 0)
            }
            let titleHeight = max(20, min(maximumTitleHeight, measuredHeight(of: title, width: columnWidth) + 4))
            let titleFramesetter = CTFramesetterCreateWithAttributedString(title)
            let headingHeightWithoutImage = titleHeight + (byline.isEmpty ? 0 : 16) + 14

            var bodyOffset = 0
            var needsHeading = true
            while bodyOffset < body.length {
                let rect = columnRect()
                if needsHeading {
                    let includeImage = imageHeight > 0 && rect.height >= headingHeightWithoutImage + imageHeight + 40
                    let headingHeight = headingHeightWithoutImage + (includeImage ? imageHeight : 0)
                    guard rect.height >= headingHeight + 40 else {
                        advanceColumn()
                        continue
                    }
                    let x = rect.minX
                    let titleRect = CGRect(x: x, y: cursorY - titleHeight, width: columnWidth, height: titleHeight)
                    drawFrame(titleFramesetter, range: CFRange(location: 0, length: title.length),
                              in: titleRect, context: context)
                    cursorY -= titleHeight + 3
                    if !byline.isEmpty {
                        drawLine(byline, fontName: bodyFontName, size: 7.5, bold: false, alignment: .left,
                                 in: CGRect(x: x, y: cursorY - 11, width: columnWidth, height: 12),
                                 context: context)
                        cursorY -= 14
                    }
                    if let image, includeImage {
                        let imageRect = CGRect(x: x, y: cursorY - imageHeight, width: columnWidth, height: imageHeight)
                        context.draw(image, in: imageRect)
                        cursorY -= imageHeight + 7
                    }
                    context.setStrokeColor(CGColor(gray: 0.35, alpha: 1))
                    context.setLineWidth(0.5)
                    context.move(to: CGPoint(x: x, y: cursorY))
                    context.addLine(to: CGPoint(x: x + columnWidth, y: cursorY))
                    context.strokePath()
                    cursorY -= 7
                    needsHeading = false
                }

                let textRect = columnRect()
                guard textRect.height > 10 else {
                    advanceColumn()
                    continue
                }
                let path = CGPath(rect: textRect, transform: nil)
                let frame = CTFramesetterCreateFrame(bodyFramesetter, CFRange(location: bodyOffset, length: 0), path, nil)
                let visibleRange = CTFrameGetVisibleStringRange(frame)
                guard visibleRange.length > 0 else {
                    advanceColumn()
                    continue
                }
                CTFrameDraw(frame, context)
                bodyOffset += visibleRange.length
                if bodyOffset < body.length {
                    advanceColumn()
                } else {
                    cursorY = max(bodyBottom, cursorY - occupiedHeight(of: frame) - 12)
                }
            }
            if storyIndex < remainingStories.count - 1 {
                if cursorY - bodyBottom < 72 {
                    advanceColumn()
                } else {
                    cursorY -= 14
                }
            }
        }

        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    private static func measuredHeight(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0 else { return 0 }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: text.length),
            nil,
            CGSize(width: width, height: 10_000),
            nil
        )
        return ceil(suggested.height)
    }

    @discardableResult
    private static func drawWrappedText(
        _ text: NSAttributedString,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        maximumHeight: CGFloat,
        context: CGContext
    ) -> CGFloat {
        let height = min(maximumHeight, max(1, measuredHeight(of: text, width: width) + 1))
        let rect = CGRect(x: x, y: top - height, width: width, height: height)
        drawFrame(CTFramesetterCreateWithAttributedString(text),
                  range: CFRange(location: 0, length: text.length), in: rect, context: context)
        return height
    }

    private static func occupiedHeight(of frame: CTFrame) -> CGFloat {
        let lines = CTFrameGetLines(frame)
        let count = CFArrayGetCount(lines)
        guard count > 0 else { return 0 }
        var origins = [CGPoint](repeating: .zero, count: count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        var highest = CGFloat.leastNormalMagnitude
        var lowest = CGFloat.greatestFiniteMagnitude
        for index in 0..<count {
            let line = unsafeBitCast(CFArrayGetValueAtIndex(lines, index), to: CTLine.self)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            highest = max(highest, origins[index].y + ascent)
            lowest = min(lowest, origins[index].y - descent)
        }
        return max(0, highest - lowest)
    }

    private static func bodyText(from html: String) -> String {
        let cleanedHTML = html
            .replacingOccurrences(
                of: #"<(script|style|noscript|iframe|video|audio|picture|img|svg)\b[^>]*>.*?</\1\s*>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"<(script|style|noscript|iframe|video|audio|picture|img|svg)\b[^>]*/?>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        guard let data = cleanedHTML.data(using: .utf8),
              let imported = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return ArticleHTMLSanitizer.plainText(fromHTML: cleanedHTML)
        }

        let lines = imported.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n\n")
    }

    private static func attributed(
        _ text: String,
        fontName: String,
        size: CGFloat,
        bold: Bool,
        alignment: NSTextAlignment,
        paragraphSpacing: CGFloat
    ) -> NSAttributedString {
        let font = NSFont(name: fontName + (bold ? "-Bold" : ""), size: size)
            ?? NSFont(name: fontName, size: size)
            ?? NSFont(name: "Georgia", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = 1
        paragraph.paragraphSpacing = paragraphSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func drawLine(
        _ text: String,
        fontName: String,
        size: CGFloat,
        bold: Bool,
        alignment: NSTextAlignment,
        in rect: CGRect,
        context: CGContext
    ) {
        let string = attributed(text, fontName: fontName, size: size, bold: bold, alignment: alignment, paragraphSpacing: 0)
        var line = CTLineCreateWithAttributedString(string)
        if CTLineGetTypographicBounds(line, nil, nil, nil) > Double(rect.width),
           let truncated = CTLineCreateTruncatedLine(line, Double(rect.width), .end, nil) {
            line = truncated
        }
        var x = rect.minX
        if alignment == .right {
            x = rect.maxX - CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        } else if alignment == .center {
            x = rect.midX - CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) / 2
        }
        context.textPosition = CGPoint(x: x, y: rect.minY + max(0, (rect.height - size) / 2))
        CTLineDraw(line, context)
    }

    private static func drawFrame(
        _ framesetter: CTFramesetter,
        range: CFRange,
        in rect: CGRect,
        context: CGContext
    ) {
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
        CTFrameDraw(frame, context)
    }

    /// The masthead icon, stored as pure black ink on a transparent background.
    static let mastheadIcon: CGImage? = {
        guard let image = NSImage(named: NSImage.Name("NewspaperMastheadIcon")) else { return nil }
        var proposed = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }()

    struct MastheadLockup {
        let iconRect: CGRect?
        let wordOrigin: CGPoint
    }

    /// Centers the icon and the masthead word as one group, with the icon immediately to the left of
    /// the word. Falls back to centering the word on its own when no icon is available.
    static func mastheadLockup(
        in rect: CGRect,
        wordWidth: CGFloat,
        wordSize: CGFloat,
        ascent: CGFloat,
        descent: CGFloat,
        iconAspect: CGFloat?
    ) -> MastheadLockup {
        let baseline = rect.minY + max(0, (rect.height - wordSize) / 2)
        guard let iconAspect, iconAspect > 0 else {
            return MastheadLockup(iconRect: nil, wordOrigin: CGPoint(x: rect.midX - wordWidth / 2, y: baseline))
        }
        let iconHeight = min(rect.height - 6, wordSize * 0.88)
        let iconWidth = iconHeight * iconAspect
        let gap = iconHeight * 0.26
        let groupMinX = rect.midX - (iconWidth + gap + wordWidth) / 2
        return MastheadLockup(
            iconRect: CGRect(x: groupMinX,
                             y: baseline + (ascent - descent) / 2 - iconHeight / 2,
                             width: iconWidth,
                             height: iconHeight),
            wordOrigin: CGPoint(x: groupMinX + iconWidth + gap, y: baseline)
        )
    }

    private static func drawMasthead(in rect: CGRect, context: CGContext) {
        let line = CTLineCreateWithAttributedString(
            attributed("PRECIS", fontName: headingFontName, size: mastheadSize, bold: true,
                       alignment: .left, paragraphSpacing: 0)
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let wordWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let icon = mastheadIcon
        let lockup = mastheadLockup(
            in: rect,
            wordWidth: wordWidth,
            wordSize: mastheadSize,
            ascent: ascent,
            descent: descent,
            iconAspect: icon.map { CGFloat($0.width) / CGFloat($0.height) }
        )
        if let icon, let iconRect = lockup.iconRect {
            context.saveGState()
            context.interpolationQuality = .high
            context.draw(icon, in: iconRect)
            context.restoreGState()
        }
        context.textPosition = lockup.wordOrigin
        CTLineDraw(line, context)
    }

    static func halftoneImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = NewspaperImageDecoder.thumbnail(from: source),
              let bitmap = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard let pixelData = bitmap.data else { return nil }
        let pixels = pixelData.assumingMemoryBound(to: UInt8.self)
        let cellSize = 8
        let center = Double(cellSize - 1) / 2
        let maximumDistanceSquared = 2 * center * center
        let bytesPerRow = bitmap.bytesPerRow
        for y in 0..<image.height {
            for x in 0..<image.width {
                let dx = Double(x % cellSize) - center
                let dy = Double(y % cellSize) - center
                let screenThreshold = Int((dx * dx + dy * dy) / maximumDistanceSquared * 255)
                let pixelIndex = y * bytesPerRow + x
                let ink = 255 - Int(pixels[pixelIndex])
                pixels[pixelIndex] = ink > 0 && ink >= screenThreshold ? 0 : 255
            }
        }
        return bitmap.makeImage()
    }
}

private enum NewspaperImageDecoder {
    static func thumbnail(from source: CGImageSource) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_800
            ] as CFDictionary
        )
    }
}
