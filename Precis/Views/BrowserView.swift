import SwiftUI
import WebKit

struct BrowserView: View {
    let initialURL: URL
    @State private var address: String
    @State private var webView: WKWebView?

    init(url: URL) {
        initialURL = url
        _address = State(initialValue: url.absoluteString)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { webView?.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(webView?.canGoBack != true)
                Button { webView?.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(webView?.canGoForward != true)
                TextField("Website address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(loadAddress)
                Button("Go", action: loadAddress)
                    .buttonStyle(.borderedProminent)
                Button { webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload")
            }
            .padding(12)
            BrowserWebView(initialURL: initialURL, webView: $webView)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private func loadAddress() {
        let value = address.contains("://") ? address : "https://\(address)"
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        address = url.absoluteString
        webView?.load(URLRequest(url: url))
    }
}

private struct BrowserWebView: NSViewRepresentable {
    let initialURL: URL
    @Binding var webView: WKWebView?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if UserDefaults.standard.object(forKey: "browserAutoAcceptCookies") as? Bool ?? true {
            let script = WKUserScript(source: Self.cookieConsentScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            configuration.userContentController.addUserScript(script)
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.uiDelegate = context.coordinator
        DispatchQueue.main.async { webView = view }
        view.load(URLRequest(url: initialURL))
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate {
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            webView.load(navigationAction.request)
            return nil
        }
    }

    private static let cookieConsentScript = #"""
    (() => {
      const labels = /^(accept all|allow all|agree to all|allow cookies|accept cookies|accept all cookies)$/i;
      const visible = el => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
      const check = () => {
        for (const el of document.querySelectorAll('button, [role="button"], input[type="button"], input[type="submit"]')) {
          const text = (el.innerText || el.value || el.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' ');
          if (labels.test(text) && visible(el) && !el.disabled) { el.click(); return; }
        }
      };
      check();
      new MutationObserver(check).observe(document.documentElement, {childList:true, subtree:true});
    })();
    """#
}

