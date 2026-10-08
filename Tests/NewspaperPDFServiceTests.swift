import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Precis

final class NewspaperPDFServiceTests: XCTestCase {
    func testRecentArticleSelectionUsesRollingDayAndFeedScope() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selectedFeed = UUID()
        let otherFeed = UUID()
        let articles = [
            NewspaperArticleReference(
                id: UUID(),
                feedID: selectedFeed,
                publishedDate: now.addingTimeInterval(-60 * 60)
            ),
            NewspaperArticleReference(
                id: UUID(),
                feedID: selectedFeed,
                publishedDate: now.addingTimeInterval(-25 * 60 * 60)
            ),
            NewspaperArticleReference(
                id: UUID(),
                feedID: otherFeed,
                publishedDate: now.addingTimeInterval(-30 * 60)
            ),
            NewspaperArticleReference(
                id: UUID(),
                feedID: selectedFeed,
                publishedDate: now.addingTimeInterval(60)
            )
        ]

        let selected = NewspaperArticleSelection.recent(
            articles,
            scope: NewspaperPDFScope(feedIDs: [selectedFeed]),
            now: now
        )

        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.feedID, selectedFeed)
        XCTAssertEqual(selected.first?.publishedDate, now.addingTimeInterval(-60 * 60))
    }

    func testRecentArticleSelectionRestrictsSmartCategoryToMatchingArticleIDs() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstFeed = UUID()
        let secondFeed = UUID()
        let firstMatchingArticleID = UUID()
        let secondMatchingArticleID = UUID()
        let matchingArticleIDs: Set<UUID> = [firstMatchingArticleID, secondMatchingArticleID]
        let articles = [
            NewspaperArticleReference(
                id: firstMatchingArticleID,
                feedID: firstFeed,
                publishedDate: now.addingTimeInterval(-60 * 60)
            ),
            NewspaperArticleReference(
                id: UUID(),
                feedID: firstFeed,
                publishedDate: now.addingTimeInterval(-30 * 60)
            ),
            NewspaperArticleReference(
                id: secondMatchingArticleID,
                feedID: secondFeed,
                publishedDate: now.addingTimeInterval(-15 * 60)
            )
        ]

        let selected = NewspaperArticleSelection.recent(
            articles,
            scope: NewspaperPDFScope(feedIDs: [firstFeed, secondFeed], articleIDs: matchingArticleIDs),
            now: now
        )

        XCTAssertEqual(Set(selected.map(\.id)), matchingArticleIDs)
        XCTAssertEqual(selected.count, 2)
    }

    func testFirstImageURLResolvesRelativePathAndDoesNotSkipArticleOrder() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://example.com/news/story"))
        let html = """
        <img src="../images/lead.jpg?size=large&amp;format=webp">
        <img src="https://example.com/second.jpg">
        """

        let imageURL = NewspaperPDFService.firstImageURL(in: html, base: baseURL)

        XCTAssertEqual(imageURL?.absoluteString, "https://example.com/images/lead.jpg?size=large&format=webp")
    }

    func testPDFRendererProducesReadableEmptyEditionPDF() throws {
        let data = try NewspaperPDFRenderer.render(
            stories: [],
            scopeTitle: "Technology",
            issueDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertEqual(PDFDocument(data: data)?.pageCount, 1)
    }

    func testPDFRendererIncludesFullTextAndPaginatesLongStories() throws {
        let text = "News content continues across newspaper columns. "
        let html = "<p>Full text verification marker.</p><p>\(String(repeating: text, count: 500))</p>"
        let story = NewspaperPDFService.PreparedStory(
            id: UUID(),
            title: "A Test Headline",
            author: "Test Reporter",
            feedTitle: "The Test Gazette",
            publishedDate: Date(timeIntervalSince1970: 1_800_000_000),
            html: html,
            imageData: try onePixelPNG()
        )

        let data = try NewspaperPDFRenderer.render(
            stories: [story],
            scopeTitle: "Technology",
            issueDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        let extractedText = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(extractedText.contains("A Test Headline"))
        XCTAssertTrue(extractedText.contains("Full text verification marker"))
        XCTAssertTrue(extractedText.contains("News content continues"))
    }

    func testPDFRendererUsesRemainingColumnSpaceWithoutAnImage() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let imageData = try onePixelPNG()
        let stories = [
            NewspaperPDFService.PreparedStory(
                id: UUID(),
                title: "Cover Story",
                author: nil,
                feedTitle: "The Test Gazette",
                publishedDate: now,
                html: "<p>Cover story body.</p>",
                imageData: imageData
            ),
            NewspaperPDFService.PreparedStory(
                id: UUID(),
                title: "FILLER STORY MARKER",
                author: "Test Reporter",
                feedTitle: "The Test Gazette",
                publishedDate: now,
                html: "<p>\(String(repeating: "The column filler continues with enough detail. ", count: 24))</p>",
                imageData: imageData
            ),
            NewspaperPDFService.PreparedStory(
                id: UUID(),
                title: "BOTTOM GAP MARKER",
                author: "Test Reporter",
                feedTitle: "The Test Gazette",
                publishedDate: now,
                html: "<p>Following story body.</p>",
                imageData: imageData
            )
        ]

        let data = try NewspaperPDFRenderer.render(stories: stories, scopeTitle: "Technology", issueDate: now)
        let document = try XCTUnwrap(PDFDocument(data: data))
        let pageIndex = try XCTUnwrap(
            (1..<document.pageCount).first { index in
                let text = document.page(at: index)?.string ?? ""
                return text.contains("FILLER STORY") && text.contains("BOTTOM")
            }
        )
        let page = try XCTUnwrap(document.page(at: pageIndex))
        let text = try XCTUnwrap(page.string) as NSString
        let fillerBounds = try XCTUnwrap(
            page.selection(for: text.range(of: "FILLER STORY"))?.bounds(for: page)
        )
        let followingBounds = try XCTUnwrap(
            page.selection(for: text.range(of: "BOTTOM"))?.bounds(for: page)
        )

        XCTAssertEqual(followingBounds.minX, fillerBounds.minX, accuracy: 1)
        XCTAssertLessThan(followingBounds.midY, fillerBounds.midY - 100)
    }

    func testCoverPageHasMastheadAndEditionIndexAndInteriorHeadlineDoesNotOverlapBody() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let imageData = try onePixelPNG()
        let coverStory = NewspaperPDFService.PreparedStory(
            id: UUID(),
            title: "Cover Story Headline",
            author: "Cover Reporter",
            feedTitle: "The Daily Feed",
            publishedDate: now,
            html: "<p>\(String(repeating: "Cover story full text. ", count: 30))</p>",
            imageData: imageData
        )
        let interiorStory = NewspaperPDFService.PreparedStory(
            id: UUID(),
            title: "A Longer Interior Headline That Wraps Across Several Lines",
            author: "Interior Reporter",
            feedTitle: "The Other Feed",
            publishedDate: now,
            html: "<p>INTERIOR BODY MARKER. \(String(repeating: "The story continues with additional detail. ", count: 10)) INTERIORENDMARKER.</p>",
            imageData: imageData
        )
        let followingStory = NewspaperPDFService.PreparedStory(
            id: UUID(),
            title: "NEXT STORY HEADLINE",
            author: "Following Reporter",
            feedTitle: "The Following Feed",
            publishedDate: now,
            html: "<p>Following story body marker. \(String(repeating: "Following story details. ", count: 10))</p>",
            imageData: imageData
        )
        let data = try NewspaperPDFRenderer.render(
            stories: [coverStory, interiorStory, followingStory],
            scopeTitle: "Technology",
            issueDate: now
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        let coverPage = try XCTUnwrap(document.page(at: 0))
        let coverText = try XCTUnwrap(coverPage.string)
        XCTAssertTrue(coverText.contains("PRECIS"))
        XCTAssertTrue(coverText.contains("IN THIS EDITION"))
        XCTAssertTrue(coverText.contains("Cover Story Headline"))

        let pageTexts = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        let interiorPageIndex = try XCTUnwrap(
            pageTexts.enumerated().first { $0.offset > 0 && $0.element.contains("A Longer") }?.offset
        )
        let interiorPage = try XCTUnwrap(document.page(at: interiorPageIndex))
        let interiorText = try XCTUnwrap(interiorPage.string)
        let titleRange = (interiorText as NSString).range(of: "Lines")
        let bodyRange = (interiorText as NSString).range(of: "BODY")
        XCTAssertNotEqual(titleRange.location, NSNotFound)
        XCTAssertNotEqual(bodyRange.location, NSNotFound)
        let titleBounds = try XCTUnwrap(interiorPage.selection(for: titleRange)).bounds(for: interiorPage)
        let bodyBounds = try XCTUnwrap(interiorPage.selection(for: bodyRange)).bounds(for: interiorPage)
        XCTAssertGreaterThan(titleBounds.minY, bodyBounds.maxY, "A headline must not cover the article body.")

        let endPageIndex = try XCTUnwrap(pageTexts.firstIndex(where: { $0.contains("INTERIORENDMARKER") }))
        let nextPageIndex = try XCTUnwrap(
            pageTexts.enumerated().first { $0.offset > 0 && $0.element.contains("NEXT") }?.offset
        )
        if endPageIndex == nextPageIndex, let endPage = document.page(at: endPageIndex) {
            let endText = try XCTUnwrap(endPage.string)
            let endRange = (endText as NSString).range(of: "INTERIORENDMARKER")
            let nextHeadlineRange = (endText as NSString).range(of: "NEXT")
            if endRange.location != NSNotFound, nextHeadlineRange.location != NSNotFound {
                let endBounds = try XCTUnwrap(endPage.selection(for: endRange)).bounds(for: endPage)
                let nextHeadlineBounds = try XCTUnwrap(endPage.selection(for: nextHeadlineRange)).bounds(for: endPage)
                XCTAssertFalse(endBounds.intersects(nextHeadlineBounds), "The following headline must not overlap the preceding article's final line.")
            }
        }
    }

    func testHalftoneImageUsesBlackAndWhiteDotScreen() throws {
        let data = try grayscaleStripePNG()
        let image = try XCTUnwrap(NewspaperPDFRenderer.halftoneImage(data))
        let grayContext = try XCTUnwrap(CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        grayContext.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(grayContext.data).assumingMemoryBound(to: UInt8.self)
        let values = Set((0..<image.height).flatMap { row in
            (0..<image.width).map { column in
                pixels[row * grayContext.bytesPerRow + column]
            }
        })

        XCTAssertEqual(values, Set([UInt8(0), UInt8(255)]))
    }

    private func onePixelPNG() throws -> Data {
        let output = NSMutableData()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func grayscaleStripePNG() throws -> Data {
        let size = 64
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        for stripe in 0..<8 {
            let gray = CGFloat(stripe) / 7
            context.setFillColor(CGColor(gray: gray, alpha: 1))
            context.fill(CGRect(x: stripe * (size / 8), y: 0, width: size / 8, height: size))
        }
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
