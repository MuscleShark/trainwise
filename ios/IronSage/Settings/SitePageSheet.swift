import SwiftUI
import WebKit

/// A page of ironsage.app shown inside the app: the privacy policy or support.
enum SitePage: String, Identifiable {
    case privacy, support

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .privacy: "Privacy policy"
        case .support: "Support"
        }
    }

    /// The page in the app's language. The app's copy (`?app=1`) leaves out the site's
    /// header and title, which the sheet shows itself.
    func url(inApp: Bool) -> URL {
        let url = Site.page(rawValue)
        return inApp ? url.appending(queryItems: [URLQueryItem(name: "app", value: "1")]) : url
    }
}

/// Opens a site page in a sheet, as a link would.
struct SitePageButton: View {
    let page: SitePage
    @State private var isShowing = false

    var body: some View {
        Button(page.title) { isShowing = true }
            .sheet(isPresented: $isShowing) {
                SitePageSheet(page: page)
            }
    }
}

/// The page in a sheet four fifths of the screen high, pulled up to full height.
/// Links that leave the page open in Safari or Mail.
struct SitePageSheet: View {
    let page: SitePage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var state = WebPage.State.loading
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            WebPage(url: page.url(inApp: true), state: $state) { openURL($0) }
                .id(attempt)
                .overlay {
                    switch state {
                    case .loading:
                        ProgressView()
                    case .loaded:
                        EmptyView()
                    case .failed:
                        ContentUnavailableView {
                            Label("Couldn't load this page", systemImage: "wifi.slash")
                        } description: {
                            Text("Check your connection and try again, or open it in your browser.")
                        } actions: {
                            Button("Try again") {
                                state = .loading
                                attempt += 1
                            }
                            .buttonStyle(.bordered)
                            Button("Open in browser") { openURL(page.url(inApp: false)) }
                                .buttonStyle(.borderedProminent)
                        }
                        .background(Color.appBackground)
                    }
                }
                .background(Color.appBackground)
                .navigationTitle(page.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Open in Safari", systemImage: "safari") {
                            openURL(page.url(inApp: false))
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }
}

/// A web view of one page. Links to anywhere else go to `openExternally`.
private struct WebPage: UIViewRepresentable {
    enum State { case loading, loaded, failed }

    let url: URL
    @Binding var state: State
    let openExternally: (URL) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        // The page's own background shows; it follows light and dark like the app.
        view.isOpaque = false
        view.backgroundColor = .clear
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebPage

        init(_ parent: WebPage) {
            self.parent = parent
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                parent.openExternally(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.state = .loaded
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.state = .failed
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.state = .failed
        }
    }
}
