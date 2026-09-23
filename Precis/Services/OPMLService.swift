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

    private var currentFolder: String?
    private var currentAttributes: [String: String] = [:]
    private var inOutline = false

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

        if let xmlURL = attributeDict["xmlUrl"], !xmlURL.isEmpty {
            // This is a feed outline
            let title = attributeDict["title"] ?? attributeDict["text"] ?? xmlURL
            feeds.append(OPMLFeed(title: title, url: xmlURL, folderName: currentFolder))
        } else {
            // This is a folder outline
            currentFolder = attributeDict["title"] ?? attributeDict["text"]
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "outline" else { return }
        // If we were tracking a folder, check if we're leaving it
        // (The parser will call didEndElement for nested outlines first,
        //  so only clear the folder when we see the folder's own end element)
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
