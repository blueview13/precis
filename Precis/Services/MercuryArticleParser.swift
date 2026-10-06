import Foundation
import JavaScriptCore

/// Runs the bundled Mercury Parser browser build in JavaScriptCore. The page
/// is fetched by ArticleContentLoader so Mercury only receives that HTML and
/// never performs its own network request.
enum MercuryArticleParser {

    struct Result: Sendable {
        let contentHTML: String
        let leadImageURL: String?
    }

    private static let queue = DispatchQueue(label: "app.precis.mercury-parser")
    nonisolated(unsafe) private static var context: JSContext?
    nonisolated(unsafe) private static var loadFailed = false

    static func parse(html: String, url: URL) async -> Result? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: parseSynchronously(html: html, url: url))
            }
        }
    }

    private static func parseSynchronously(html: String, url: URL) -> Result? {
        guard let context = makeContext() else { return nil }

        guard let urlLiteral = javascriptString(url.absoluteString),
              let htmlLiteral = javascriptString(html) else { return nil }

        let script = """
        globalThis.precisMercuryResult = null;
        Mercury.parse(\(urlLiteral), {
          html: \(htmlLiteral),
          contentType: 'html',
          fetchAllPages: false
        }).then(result => {
          globalThis.precisMercuryResult = JSON.stringify({
            content: result.content,
            leadImageURL: result.lead_image_url
          });
        }).catch(error => {
          globalThis.precisMercuryResult = JSON.stringify({error: String(error)});
        });
        """

        context.evaluateScript(script)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let value = context.evaluateScript("globalThis.precisMercuryResult")?.toString(),
               value != "null", !value.isEmpty,
               let data = value.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = object["content"] as? String,
               !content.isEmpty {
                return Result(
                    contentHTML: content,
                    leadImageURL: object["leadImageURL"] as? String
                )
            }

            // JavaScriptCore schedules async/Promise continuations on its
            // owning thread's run loop. This queue is dedicated to parsing.
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        return nil
    }

    private static func makeContext() -> JSContext? {
        if let context { return context }
        guard !loadFailed else { return nil }
        guard let scriptURL = Bundle.main.url(forResource: "mercury.web", withExtension: "js"),
              let source = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            loadFailed = true
            return nil
        }

        let context = JSContext()
        context?.exceptionHandler = { _, _ in
            // Extraction is best-effort; the current Precis extractor is the
            // fallback for a missing bundle or an unsupported page.
        }
        context?.evaluateScript(Self.browserCompatibilityShim)
        context?.evaluateScript(source)
        guard context?.exception == nil,
              context?.evaluateScript("typeof Mercury !== 'undefined'")?.toBool() == true else {
            loadFailed = true
            return nil
        }

        Self.context = context
        return context
    }

    private static func javascriptString(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// The Mercury browser bundle expects XMLHttpRequest to exist at load
    /// time and uses the URL constructor to identify the page domain. The
    /// supplied HTML avoids any browser/network APIs during extraction.
    private static let browserCompatibilityShim = #"""
    globalThis.XMLHttpRequest = function() {};
    globalThis.XMLHttpRequest.prototype = {};
    globalThis.URL = function(value) {
      this.href = String(value);
      const match = this.href.match(/^([a-z]+):\/\/([^/]+)(.*)$/i);
      if (!match) throw new Error('Invalid URL');
      this.protocol = match[1] + ':';
      this.host = match[2];
      this.hostname = match[2].split(':')[0];
      this.pathname = (match[3].split(/[?#]/)[0] || '/');
      this.origin = this.protocol + '//' + this.host;
      this.search = '';
      this.hash = '';
      this.toString = function() { return this.href; };
    };
    """#
}
