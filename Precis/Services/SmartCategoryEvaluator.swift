import Foundation

public struct SmartCategoryArticleContext {
    public var article: Article
    public var feedName: String
    public var categoryName: String?
    public init(article: Article, feedName: String, categoryName: String? = nil) {
        self.article = article; self.feedName = feedName; self.categoryName = categoryName
    }
}

/// Pure rule interpreter. A rule with no usable value evaluates false; empty
/// groups also evaluate false so incomplete definitions never match everything.
public struct SmartCategoryEvaluator {
    private let isoDateFormatter: ISO8601DateFormatter
    private let dayDateFormatter: DateFormatter
    public init() {
        isoDateFormatter = ISO8601DateFormatter()
        dayDateFormatter = DateFormatter()
        dayDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayDateFormatter.dateFormat = "yyyy-MM-dd"
    }
    public func matches(_ context: SmartCategoryArticleContext, category: SmartCategory, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !category.isDeleted else { return false }
        var root = category.rootGroup
        root.matchMode = category.matchMode
        return evaluate(root, context: context, now: now, calendar: calendar)
    }
    public func matches(_ article: Article, category: SmartCategory, feedName: String = "", categoryName: String? = nil, now: Date = Date()) -> Bool {
        matches(.init(article: article, feedName: feedName, categoryName: categoryName), category: category, now: now)
    }
    private func evaluate(_ group: SmartCategoryRuleGroup, context: SmartCategoryArticleContext, now: Date, calendar: Calendar) -> Bool {
        guard !group.children.isEmpty else { return false }
        let values = group.children.map { child -> Bool in
            switch child {
            case .group(let nested): evaluate(nested, context: context, now: now, calendar: calendar)
            case .rule(let rule): evaluate(rule, context: context, now: now, calendar: calendar)
            }
        }
        return group.matchMode == .all ? values.allSatisfy { $0 } : values.contains(true)
    }
    private func evaluate(_ rule: SmartCategoryRule, context: SmartCategoryArticleContext, now: Date, calendar: Calendar) -> Bool {
        let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch rule.field {
        case .title: return text(context.article.title, matches: value, using: rule.operation)
        case .content: return text(context.article.extractedContent ?? context.article.rawContent ?? "", matches: value, using: rule.operation)
        case .author: return text(context.article.author ?? "", matches: value, using: rule.operation)
        case .feed: return text(context.feedName, matches: value, using: rule.operation)
        case .category: return text(context.categoryName ?? "", matches: value, using: rule.operation)
        case .readStatus:
            return rule.operation == .isRead ? context.article.isRead : rule.operation == .isUnread && !context.article.isRead
        case .starred:
            guard rule.operation == .equal || rule.operation == .notEqual, let expected = parseBool(value) else { return false }
            return rule.operation == .equal ? context.article.isStarred == expected : context.article.isStarred != expected
        case .publishedDate:
            guard let date = context.article.publishedDate else { return false }
            switch rule.operation {
            case .inLastDays:
                guard let days = Int(value), days >= 0, let start = calendar.date(byAdding: .day, value: -days, to: now) else { return false }
                return date >= start && date <= now
            case .before: guard let dateValue = parseDate(value) else { return false }; return date < dateValue
            case .after: guard let dateValue = parseDate(value) else { return false }; return date > dateValue
            default: return false
            }
        }
    }
    private func text(_ source: String, matches raw: String, using operation: SmartCategoryOperator) -> Bool {
        guard !raw.isEmpty else { return false }
        let comparisonLocale = Locale(identifier: "en_US_POSIX")
        let lhs = source.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: comparisonLocale)
        let rhs = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: comparisonLocale)
        return switch operation {
        case .contains: lhs.contains(rhs)
        case .doesNotContain: !lhs.contains(rhs)
        case .equal: lhs == rhs
        case .notEqual: lhs != rhs
        case .beginsWith: lhs.hasPrefix(rhs)
        case .endsWith: lhs.hasSuffix(rhs)
        default: false
        }
    }
    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() { case "yes", "true", "starred": true; case "no", "false", "not starred": false; default: nil }
    }
    private func parseDate(_ value: String) -> Date? {
        if let date = isoDateFormatter.date(from: value) { return date }
        return dayDateFormatter.date(from: value)
    }
}
