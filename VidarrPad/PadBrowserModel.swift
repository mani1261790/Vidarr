import Combine
import Foundation
import SwiftUI
import WebKit

@MainActor
final class PadBrowserModel: NSObject, ObservableObject {
    final class Tab: NSObject, Identifiable, ObservableObject {
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
    @Published var navigationStateToken = UUID()

    override init() {
        super.init()
        newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
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

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
            return
        }
        selectedIndex = min(selectedIndex, tabs.count - 1)
        if index <= selectedIndex {
            selectedIndex = max(0, selectedIndex - 1)
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
        return PadBrowserPreferences.shared.searchURL(for: raw)
    }

    func refreshPreferences() {
        if tabs.isEmpty {
            newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
        }
    }

    func canGoBack() -> Bool {
        selectedTab?.webView.canGoBack ?? false
    }

    func canGoForward() -> Bool {
        selectedTab?.webView.canGoForward ?? false
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
            self.navigationStateToken = UUID()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.navigationStateToken = UUID()
        }
    }
}
