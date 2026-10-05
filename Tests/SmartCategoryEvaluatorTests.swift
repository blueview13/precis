import XCTest
@testable import Precis

final class SmartCategoryEvaluatorTests: XCTestCase {
    private let evaluator = SmartCategoryEvaluator()
    private func category(_ rules: [SmartCategoryCondition], mode: SmartCategoryMatchMode = .all) -> SmartCategory {
        SmartCategory(name: "Test", matchMode: mode, rootGroup: .init(matchMode: mode, children: rules))
    }
    private func rule(_ field: SmartCategoryField, _ operation: SmartCategoryOperator, _ value: String) -> SmartCategoryCondition {
        .rule(.init(field: field, operation: operation, value: value))
    }
    private func context(title: String = "Café News", body: String = "A useful ARTICLE", date: Date? = nil, read: Bool = false, starred: Bool = true) -> SmartCategoryArticleContext {
        .init(article: Article(feedID: UUID(), title: title, author: "Ada Lovelace", publishedDate: date, rawContent: body, isRead: read, isStarred: starred), feedName: "Daily Feed", categoryName: "Science")
    }

    func testAllTextOperatorsAndDiacriticInsensitiveMatching() {
        let cases: [(SmartCategoryOperator, String, Bool)] = [
            (.contains, "cafe", true), (.doesNotContain, "other", true), (.equal, "CAFÉ NEWS", true),
            (.notEqual, "other", true), (.beginsWith, "cafe", true), (.endsWith, "NEWS", true)
        ]
        for (op, value, expected) in cases {
            XCTAssertEqual(evaluator.matches(context(), category: category([rule(.title, op, value)])), expected)
        }
    }

    func testAllAnyAndNestedGroups() {
        let nested = SmartCategoryCondition.group(.init(matchMode: .any, children: [rule(.feed, .equal, "missing"), rule(.category, .contains, "sci")]))
        XCTAssertTrue(evaluator.matches(context(), category: category([rule(.title, .contains, "cafe"), nested])))
        XCTAssertFalse(evaluator.matches(context(), category: category([rule(.title, .contains, "cafe"), rule(.author, .equal, "nobody")])))
        XCTAssertTrue(evaluator.matches(context(), category: category([rule(.author, .equal, "nobody"), rule(.title, .contains, "cafe")], mode: .any)))
    }

    func testContentAuthorFeedAndRealCategoryFields() {
        let rules: [SmartCategoryCondition] = [
            rule(.content, .contains, "useful article"),
            rule(.author, .beginsWith, "ada"),
            rule(.feed, .equal, "daily feed"),
            rule(.category, .endsWith, "science")
        ]
        XCTAssertTrue(evaluator.matches(context(), category: category(rules)))
    }

    func testDateAndStateOperators() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let articleDate = now.addingTimeInterval(-2 * 86_400)
        XCTAssertTrue(evaluator.matches(context(date: articleDate), category: category([rule(.publishedDate, .inLastDays, "3")]), now: now))
        XCTAssertTrue(evaluator.matches(context(date: articleDate), category: category([rule(.publishedDate, .before, ISO8601DateFormatter().string(from: now))]), now: now))
        XCTAssertTrue(evaluator.matches(context(date: articleDate), category: category([rule(.publishedDate, .after, "2020-01-01")]), now: now))
        XCTAssertTrue(evaluator.matches(context(read: false), category: category([rule(.readStatus, .isUnread, "")]), now: now))
        XCTAssertTrue(evaluator.matches(context(), category: category([rule(.starred, .equal, "yes")]), now: now))
    }

    func testEmptyAndInvalidRulesNeverMatch() {
        XCTAssertFalse(evaluator.matches(context(), category: category([rule(.title, .contains, " ")])))
        XCTAssertFalse(evaluator.matches(context(date: nil), category: category([rule(.publishedDate, .inLastDays, "oops")])))
        XCTAssertFalse(evaluator.matches(context(), category: category([])))
    }

    func testCodableRoundTripIgnoresUnknownFields() throws {
        let original = category([rule(.title, .contains, "cafe"), .group(.init(matchMode: .any, children: [rule(.starred, .equal, "yes")]))])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SmartCategory.self, from: data)
        XCTAssertEqual(decoded, original)
        let json = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"futureField\":\"ignored\"")
        XCTAssertEqual(try JSONDecoder().decode(SmartCategory.self, from: Data(json.utf8)), original)
    }
}
