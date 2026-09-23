import SwiftUI
import WebKit

public struct BrowserView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: {}) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Button(action: {}) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                TextField("https://", text: .constant("https://example.com"))
                    .textFieldStyle(.roundedBorder)

                Button("Open") {}
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(PrecisDesignSystem.surface(for: colorScheme))

            
            WebView(url: URL(string: "https://example.com")!)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PrecisDesignSystem.background(for: colorScheme))
    }
}

public struct WebView: NSViewRepresentable {
    let url: URL

    public func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url == nil {
            nsView.load(URLRequest(url: url))
        }
    }
}

#Preview {
    BrowserView()
}
