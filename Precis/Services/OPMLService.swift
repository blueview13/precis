import Foundation

/// Represents a single feed entry parsed from or written to OPML.
public struct OPMLFeed {
    public let title: String
    public let url: String
    public let folderName: String?

    public init(title: String, url: String, folderName: String? = nil) {
        self.title = title
        self.url = url
        self.folderName = folderName
    }
}

/// Handles parsing OPML XML into feed entries and generating OPML from feed records.
public enum OPMLService {

    // MARK: - Import

    /// Parse OPML XML data into an array of `OPMLFeed` entries.
    public static func parse(data: Data) throws -> [OPMLFeed] {
        let parser = OPMLParser(data: data)
        try parser.parse()
        return parser.feeds
    }

    /// Parse an OPML file at the given URL.
    public static func parse(contentsOf url: URL) throws -> [OPMLFeed] {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    // MARK: - Export

    /// Generate OPML XML from an array of `OPMLFeed` entries.
    public static func generate(feeds: [OPMLFeed], title: String = "Precis Subscriptions") -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<opml version=\"2.0\">\n"
        xml += "  <head>\n"
        xml += "    <title>\(escapeXML(title))</title>\n"
        xml += "  </head>\n"
        xml += "  <body>\n"

        // Group feeds by folder
        var unfiled: [OPMLFeed] = []
        var grouped: [String: [OPMLFeed]] = [:]

        for feed in feeds {
            if let folder = feed.folderName {
                grouped[folder, default: []].append(feed)
            } else {
                unfiled.append(feed)
            }
        }

        // Write unfiled feeds
        for feed in unfiled {
            xml += "    <outline text=\"\(escapeXML(feed.title))\" title=\"\(escapeXML(feed.title))\" xmlUrl=\"\(escapeXML(feed.url))\" type=\"rss\" />\n"
        }

        // Write grouped feeds
        for (folder, folderFeeds) in grouped.sorted(by: { $0.key < $1.key }) {
            xml += "    <outline text=\"\(escapeXML(folder))\" title=\"\(escapeXML(folder))\">\n"
            for feed in folderFeeds {
                xml += "      <outline text=\"\(escapeXML(feed.title))\" title=\"\(escapeXML(feed.title))\" xmlUrl=\"\(escapeXML(feed.url))\" type=\"rss\" />\n"
            }
            xml += "    </outline>\n"
        }

        xml += "  </body>\n"
        xml += "</opml>\n"
        return xml
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - OPML Parser

private final class OPMLParser: NSObject, XMLParserDelegate {
    let data: Data
    var feeds: [OPMLFeed] = []

    /// Folder names currently open, innermost last.
    private var folderStack: [String] = []
    /// One entry per outline start: the folder name it pushed, or nil.
    private var scopeStack: [String?] = []

    init(data: Data) {
        self.data = data
    }

    func parse() throws {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw OPMLParserError.invalidXML
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "outline" else { return }

        // `xmlUrl` is the OPML standard; some exporters write `xmlURL`.
        let xmlURL = attributeDict["xmlUrl"] ?? attributeDict["xmlURL"]
        if let xmlURL, !xmlURL.isEmpty {
            // Feed outline — belongs to the innermost folder still open.
            let title = attributeDict["title"] ?? attributeDict["text"] ?? xmlURL
            feeds.append(OPMLFeed(title: title, url: xmlURL, folderName: folderStack.last))
            scopeStack.append(nil)
        } else {
            // Folder outline — remember what to pop when it closes.
            if let name = attributeDict["title"] ?? attributeDict["text"] {
                folderStack.append(name)
                scopeStack.append(name)
            } else {
                scopeStack.append(nil)
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "outline" else { return }
        // Pop this outline's scope. `popLast()` on [String?] yields String??,
        // so unwrap TWICE: only a scope that actually pushed a folder name
        // should pop that name from the folder stack.
        guard let pushed = scopeStack.popLast(), pushed != nil else { return }
        if !folderStack.isEmpty {
            folderStack.removeLast()
        }
    }
}

public enum OPMLParserError: LocalizedError {
    case invalidXML

    public var errorDescription: String? {
        switch self {
        case .invalidXML:
            return "The OPML file could not be parsed."
        }
    }
}
