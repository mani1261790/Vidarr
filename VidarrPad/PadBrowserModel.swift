import Combine
import Foundation
import SwiftUI
import WebKit

@MainActor
final class PadBrowserModel: NSObject, ObservableObject {
    private enum PreferenceKey {
        static let homePageURL = "prefs.homePageURL"
        static let searchTemplate = "prefs.searchTemplate"
    }

    private enum LocalDefaults {
        static let homePageURLString = "https://search.fenrir-inc.com/"
        static let searchTemplate = "https://search.fenrir-inc.com/?q={query}"
    }

    final class Tab: NSObject, Identifiable {
        let id = UUID()
        let webView: WKWebView
        @Published var title: String = "New Tab"
        @Published var urlString: String = ""

        init(webView: WKWebView) {
            self.webView = webView
            super.init()
        }
    }

    @Published private(set) var tabs: [Tab] = []
    @Published var selectedIndex: Int = 0
    @Published var addressInput: String = ""

    override init() {
        super.init()
        newTab(initialURL: resolvedHomePageURL())
    }

    var selectedTab: Tab? {
        guard selectedIndex >= 0, selectedIndex < tabs.count else { return nil }
        return tabs[selectedIndex]
    }

    func newTab(initialURL: URL? = nil) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(webView: webView)
        webView.navigationDelegate = self
        tabs.append(tab)
        selectedIndex = tabs.count - 1
        if let initialURL {
            webView.load(URLRequest(url: initialURL))
        }
        syncAddressBar()
    }

    func selectTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
        syncAddressBar()
    }

    func goBack() {
        selectedTab?.webView.goBack()
    }

    func goForward() {
        selectedTab?.webView.goForward()
    }

    func reload() {
        selectedTab?.webView.reload()
    }

    func commitAddressBar() {
        let trimmed = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = resolvedURL(from: trimmed)
        selectedTab?.webView.load(URLRequest(url: url))
    }

    func syncAddressBar() {
        addressInput = selectedTab?.urlString.isEmpty == false ? (selectedTab?.urlString ?? "") : (selectedTab?.webView.url?.absoluteString ?? "")
    }

    private func resolvedURL(from raw: String) -> URL {
        if let directURL = URL(string: raw), let scheme = directURL.scheme, ["http", "https"].contains(scheme.lowercased()) {
            return directURL
        }
        if raw.contains("."), let httpsURL = URL(string: "https://\(raw)") {
            return httpsURL
        }
        return resolvedSearchURL(for: raw)
    }

    private func resolvedHomePageURL() -> URL {
        let storedValue = UserDefaults.standard.string(forKey: PreferenceKey.homePageURL) ?? LocalDefaults.homePageURLString
        if let url = URL(string: storedValue), url.scheme != nil {
            return url
        }
        return URL(string: LocalDefaults.homePageURLString)!
    }

    private func resolvedSearchURL(for query: String) -> URL {
        let template = UserDefaults.standard.string(forKey: PreferenceKey.searchTemplate) ?? LocalDefaults.searchTemplate
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let rawURL = template.contains("{query}")
            ? template.replacingOccurrences(of: "{query}", with: encodedQuery)
            : "\(template)\(encodedQuery)"
        return URL(string: rawURL) ?? URL(string: "\(LocalDefaults.searchTemplate.replacingOccurrences(of: "{query}", with: encodedQuery))")!
    }
}

extension PadBrowserModel: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, let tab = self.tabs.first(where: { $0.webView === webView }) else { return }
            tab.title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (webView.title ?? "New Tab")
                : (webView.url?.host ?? webView.url?.absoluteString ?? "New Tab")
            tab.urlString = webView.url?.absoluteString ?? ""
            if self.selectedTab === tab {
                self.syncAddressBar()
            }
        }
    }
}
